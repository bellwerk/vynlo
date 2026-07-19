-- VYN-MEDIA-001, VYN-STOR-001, VYN-JOB-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, T-MED-003, T-MED-004, T-STOR-001
-- M2-MEDIA-AC-001 through M2-MEDIA-AC-004
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(36);

-- Test-only fixture primitive. Production authenticated access remains revoked
-- by the canonical VIN intake migration.
grant execute on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) to authenticated;

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  assurance text default 'aal2'
)
returns void
language plpgsql
as $$
declare
  claims jsonb;
begin
  claims := pg_catalog.jsonb_build_object(
    'sub', fixture_user_id::text,
    'role', 'authenticated',
    'aal', assurance,
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', case when assurance = 'aal2' then 'totp' else 'password' end,
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.inventory_fixture (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean
);
create temporary table pg_temp.upload_fixture (
  media_id uuid,
  upload_session_id uuid,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  collection_version bigint,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.verification_fixture (
  media_id uuid,
  upload_session_id uuid,
  job_id uuid,
  job_status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.claimed_verification (
  job_id uuid,
  workspace_id uuid,
  outbox_event_id uuid,
  job_type text,
  entity_type text,
  entity_id uuid,
  payload_schema_version integer,
  payload jsonb,
  idempotency_key text,
  attempt_number integer,
  max_attempts integer,
  lease_token uuid,
  lease_expires_at timestamptz,
  correlation_id uuid,
  causation_id uuid,
  probe text
);
create temporary table pg_temp.verified_completion (
  media_id uuid,
  processing_run_id uuid,
  job_id uuid,
  media_status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.rejection_fixture (
  media_id uuid,
  media_status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
grant all on
  pg_temp.inventory_fixture,
  pg_temp.upload_fixture,
  pg_temp.verification_fixture,
  pg_temp.claimed_verification,
  pg_temp.verified_completion,
  pg_temp.rejection_fixture
to authenticated, service_role;

select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_attribute attribute
    join pg_catalog.pg_class relation on relation.oid = attribute.attrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'media_upload_sessions'
      and attribute.attname = 'expected_checksum_sha256'
      and attribute.attnotnull
      and not attribute.attisdropped
  ),
  'upload intents require an expected SHA-256 checksum at the database boundary'
);

select extensions.has_column(
  'public', 'media_upload_sessions', 'verification_job_id',
  'upload sessions retain the durable verification job'
);
select extensions.has_column(
  'public', 'media_upload_sessions', 'verification_outbox_event_id',
  'upload sessions retain verification outbox provenance'
);
select extensions.has_column(
  'public', 'media_upload_sessions', 'verification_audit_event_id',
  'upload sessions retain verification audit provenance'
);
select extensions.has_column(
  'public', 'media_upload_sessions', 'verification_requested_at',
  'upload sessions retain verification request time'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_constraint constraint_record
    where constraint_record.conname = 'media_upload_sessions_verification_shape_check'
      and constraint_record.contype = 'c'
  ),
  'verification provenance columns are all-null or all-present'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.policyname = 'managed_media_uploads_insert'
      and policy.cmd = 'INSERT'
      and 'authenticated' = any(policy.roles)
      and policy.with_check like
        '%vehicle_photo_upload_object_is_authorized%'
      and policy.with_check not like '%media_upload_sessions%'
  ),
  'authenticated Storage insert delegates to the boolean exact-intent boundary'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.request_vehicle_photo_upload_verification(uuid,text,uuid,uuid,text,uuid)',
    'EXECUTE'
  ),
  'authenticated users can request durable upload verification'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.complete_vehicle_photo_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,integer,integer,integer,jsonb,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.reject_vehicle_photo_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,text,text,uuid)',
      'EXECUTE'
    ),
  'browser roles cannot attest or reject verification results'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.load_vehicle_photo_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer)',
    'EXECUTE'
  )
    and pg_catalog.has_function_privilege(
      'service_role',
      'app.complete_vehicle_photo_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,integer,integer,integer,jsonb,text,uuid)',
      'EXECUTE'
    ),
  'only the trusted worker role can load and complete verification'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.inventory_fixture
select result.*
from app.create_inventory_unit(
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'm2-media-verify-inventory-001',
  '1HGCM82633A900012',
  2025,
  'Synthetic',
  'Verification Fixture',
  date '2026-07-16',
  10,
  'km',
  'CAD',
  3200000,
  'Fictional verification test inventory',
  'request-media-verify-inventory-001',
  'b9000000-0000-4000-8000-000000000001'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.inventory_fixture),
  1::bigint,
  'verification fixture owns one synthetic inventory unit'
);

insert into pg_temp.upload_fixture
select result.*, 'first'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-verify-upload-001',
  (select inventory_unit_id from pg_temp.inventory_fixture),
  'verify-source.jpg', 'image/jpeg', 1000, repeat('a', 64),
  'request-media-verify-upload-001',
  'b9000000-0000-4000-8000-000000000002'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.upload_fixture where probe = 'first'),
  1::bigint,
  'authenticated actor creates one exact quarantine upload intent'
);
select extensions.throws_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata)
    values (
      'b9100000-0000-4000-8000-000000000001',
      (select upload_bucket from pg_temp.upload_fixture where probe = 'first'),
      (select upload_object_key from pg_temp.upload_fixture where probe = 'first'),
      '{"size":999,"mimetype":"image/jpeg"}'::jsonb
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'vehicle upload policy rejects bytes whose actual size differs from the intent'
);
select extensions.throws_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata)
    values (
      'b9100000-0000-4000-8000-000000000002',
      (select upload_bucket from pg_temp.upload_fixture where probe = 'first'),
      (select upload_object_key from pg_temp.upload_fixture where probe = 'first'),
      '{"size":1000,"mimetype":"image/png"}'::jsonb
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'vehicle upload policy rejects bytes whose normalized MIME differs from the intent'
);
select extensions.lives_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata)
    values (
      'b9100000-0000-4000-8000-000000000003',
      (select upload_bucket from pg_temp.upload_fixture where probe = 'first'),
      (select upload_object_key from pg_temp.upload_fixture where probe = 'first'),
      '{"size":1000,"mimetype":"IMAGE/JPEG"}'::jsonb
    )
  $$,
  'vehicle upload policy accepts the exact intent size and normalized MIME only'
);

insert into pg_temp.verification_fixture
select result.*, 'first'
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-verify-request-001',
  (select media_id from pg_temp.upload_fixture where probe = 'first'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'first'),
  'request-media-verification-001',
  'b9000000-0000-4000-8000-000000000003'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.verification_fixture verification
    where verification.probe = 'first'
      and verification.job_status = 'queued'
      and not verification.replayed
      and verification.audit_event_id is not null
      and verification.outbox_event_id is not null
  ),
  'upload completion request atomically queues durable verification'
);
reset role;
select extensions.ok(
  exists (
    select 1 from pg_temp.verification_fixture verification
    join public.jobs job on job.id = verification.job_id
    where verification.probe = 'first'
      and job.job_type = 'media.verify_vehicle_photo_upload'
      and job.entity_type = 'media_upload_session'
      and job.entity_id = verification.upload_session_id
      and pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(job.payload, '$.keyvalue()')) = 2
      and job.payload ? 'media_id'
      and job.payload ? 'upload_session_id'
      and not app.job_payload_contains_forbidden_key(job.payload)
  ),
  'verification job contains references only and binds the upload session'
);
reset role;
select extensions.ok(
  exists (
    select 1 from pg_temp.verification_fixture verification
    join public.media_upload_sessions upload
      on upload.id = verification.upload_session_id
    where verification.probe = 'first'
      and upload.verification_job_id = verification.job_id
      and upload.verification_outbox_event_id = verification.outbox_event_id
      and upload.verification_audit_event_id = verification.audit_event_id
      and upload.verification_requested_at is not null
  ),
  'upload session persists exact job, outbox, and audit linkage'
);
set local role authenticated;

insert into pg_temp.verification_fixture
select result.*, 'replay'
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-verify-request-001',
  (select media_id from pg_temp.upload_fixture where probe = 'first'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'first'),
  'request-media-verification-replay',
  'b9000000-0000-4000-8000-000000000004'
) result;
select extensions.ok(
  (
    select replay.job_id = original.job_id and replay.replayed
    from pg_temp.verification_fixture original
    join pg_temp.verification_fixture replay on replay.probe = 'replay'
    where original.probe = 'first'
  ),
  'same-key verification replay returns the original durable job'
);

insert into pg_temp.verification_fixture
select result.*, 'active-duplicate'
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-verify-request-active-duplicate',
  (select media_id from pg_temp.upload_fixture where probe = 'first'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'first'),
  'request-media-verification-active-duplicate',
  'b9000000-0000-4000-8000-000000000005'
) result;
select extensions.ok(
  (
    select duplicate.job_id = original.job_id and duplicate.replayed
    from pg_temp.verification_fixture original
    join pg_temp.verification_fixture duplicate
      on duplicate.probe = 'active-duplicate'
    where original.probe = 'first'
  ),
  'new-key request cannot enqueue a duplicate active verification job'
);

reset role;
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.request_vehicle_photo_upload_verification(
      '20000000-0000-4000-8000-000000000002',
      'm2-media-verify-cross-workspace',
      (select media_id from pg_temp.upload_fixture where probe = 'first'),
      (select upload_session_id from pg_temp.upload_fixture where probe = 'first'),
      'request-media-verification-cross-workspace',
      'b9000000-0000-4000-8000-000000000006'
    )
  $$,
  '42501',
  'media upload intent is not owned by the actor',
  'cross-workspace actor cannot borrow an upload intent'
);
reset role;

set local role service_role;
insert into pg_temp.claimed_verification
select claimed.*, 'first'
from app.claim_jobs(
  'media-verifier.fixture-01', 1, 300,
  array['media.verify_vehicle_photo_upload']
) claimed;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.claimed_verification where probe = 'first'),
  1::bigint,
  'verification job is claimable only through the durable lease queue'
);
select extensions.throws_ok(
  $$
    select * from app.load_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.upload_fixture where probe = 'first'),
      (select upload_session_id from pg_temp.upload_fixture where probe = 'first'),
      (select job_id from pg_temp.claimed_verification where probe = 'first'),
      'media-verifier.stale',
      (select lease_token from pg_temp.claimed_verification where probe = 'first'),
      (select attempt_number from pg_temp.claimed_verification where probe = 'first')
    )
  $$,
  '55000',
  'only the active media verification lease can load an upload',
  'stale worker identity cannot read the private quarantine object key'
);
select extensions.ok(
  exists (
    select 1 from app.load_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.upload_fixture where probe = 'first'),
      (select upload_session_id from pg_temp.upload_fixture where probe = 'first'),
      (select job_id from pg_temp.claimed_verification where probe = 'first'),
      'media-verifier.fixture-01',
      (select lease_token from pg_temp.claimed_verification where probe = 'first'),
      (select attempt_number from pg_temp.claimed_verification where probe = 'first')
    ) source
    where source.upload_bucket = 'media-private'
      and source.expected_mime_type = 'image/jpeg'
      and source.expected_byte_size = 1000
      and source.expected_checksum_sha256 = repeat('a', 64)
  ),
  'active exact lease receives only the intended bounded object metadata'
);
select extensions.throws_ok(
  $$
    select * from app.complete_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.upload_fixture where probe = 'first'),
      (select upload_session_id from pg_temp.upload_fixture where probe = 'first'),
      (select job_id from pg_temp.claimed_verification where probe = 'first'),
      'media-verifier.stale',
      (select lease_token from pg_temp.claimed_verification where probe = 'first'),
      (select attempt_number from pg_temp.claimed_verification where probe = 'first'),
      'image/jpeg', 1000, repeat('a', 64), 2000, 1000, 6,
      '{"scanner":{"name":"clamd","version":"1.4.2"},"sourceChecksumSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","verdict":"clean","signatureVersion":"27345"}'::jsonb,
      'job:stale-complete',
      'b9000000-0000-4000-8000-000000000007'
    )
  $$,
  '55000',
  'only the active media verification lease can complete an upload',
  'stale worker identity cannot attest a clean upload'
);

insert into pg_temp.verified_completion
select result.*
from app.complete_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.upload_fixture where probe = 'first'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'first'),
  (select job_id from pg_temp.claimed_verification where probe = 'first'),
  'media-verifier.fixture-01',
  (select lease_token from pg_temp.claimed_verification where probe = 'first'),
  (select attempt_number from pg_temp.claimed_verification where probe = 'first'),
  'image/jpeg', 1000, repeat('a', 64), 2000, 1000, 6,
  pg_catalog.jsonb_build_object(
    'scanner', pg_catalog.jsonb_build_object('name', 'clamd', 'version', '1.4.2'),
    'sourceChecksumSha256', repeat('a', 64),
    'verdict', 'clean',
    'signatureVersion', '27345'
  ),
  'job:verified-complete',
  'b9000000-0000-4000-8000-000000000008'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.verified_completion completion
    where completion.media_status = 'quarantined'
      and completion.processing_run_id is not null
      and completion.job_id is not null
      and not completion.replayed
  ),
  'active verified receipt transitions quarantine and creates processing lineage'
);
select extensions.ok(
  exists (
    select 1 from pg_temp.upload_fixture fixture
    join public.media_upload_sessions upload
      on upload.id = fixture.upload_session_id
    where fixture.probe = 'first'
      and upload.status = 'completed'
      and upload.observed_checksum_sha256 = repeat('a', 64)
      and upload.malware_scan_receipt ->> 'verdict' = 'clean'
  ),
  'trusted completion persists server-derived metadata and clean scan receipt'
);
reset role;
select extensions.ok(
  exists (
    select 1 from pg_temp.verified_completion completion
    join public.jobs job on job.id = completion.job_id
    where job.job_type = 'media.process_vehicle_photo'
      and job.status = 'queued'
      and pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(job.payload, '$.keyvalue()')) = 4
      and not app.job_payload_contains_forbidden_key(job.payload)
  ),
  'verified completion atomically queues minimized image processing work'
);
set local role service_role;
select extensions.lives_ok(
  $$
    select app.complete_job(
      (select job_id from pg_temp.claimed_verification where probe = 'first'),
      'media-verifier.fixture-01',
      (select lease_token from pg_temp.claimed_verification where probe = 'first'),
      '{"media_status":"quarantined"}'::jsonb,
      null
    )
  $$,
  'generic durable completion closes the verification lease after artifact handoff'
);
select extensions.ok(
  exists (
    select 1 from public.audit_events event
    where event.action = 'media.upload_verification_queued'
      and event.entity_id = (select media_id from pg_temp.upload_fixture where probe = 'first')
  ),
  'verification request emits an append-only actor audit event'
);
select extensions.ok(
  exists (
    select 1 from public.outbox_events event
    where event.event_name = 'media.upload_verification_queued'
      and event.aggregate_id = (select media_id from pg_temp.upload_fixture where probe = 'first')
  ),
  'verification request commits its outbox event with authoritative state'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.upload_fixture
select result.*, 'rejected'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-verify-upload-rejected',
  (select inventory_unit_id from pg_temp.inventory_fixture),
  'rejected.png', 'image/png', 900, repeat('b', 64),
  'request-media-verify-upload-rejected',
  'b9000000-0000-4000-8000-000000000009'
) result;
insert into pg_temp.verification_fixture
select result.*, 'rejected'
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-verify-request-rejected',
  (select media_id from pg_temp.upload_fixture where probe = 'rejected'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'rejected'),
  'request-media-verification-rejected',
  'b9000000-0000-4000-8000-000000000010'
) result;
reset role;
set local role service_role;
insert into pg_temp.claimed_verification
select claimed.*, 'rejected'
from app.claim_jobs(
  'media-verifier.fixture-01', 1, 300,
  array['media.verify_vehicle_photo_upload']
) claimed;
select extensions.ok(
  exists (
    select 1 from pg_temp.claimed_verification claim
    join pg_temp.verification_fixture verification on verification.job_id = claim.job_id
    where claim.probe = 'rejected' and verification.probe = 'rejected'
  ),
  'a second exact upload receives an independent durable verification lease'
);

insert into pg_temp.rejection_fixture
select result.*, 'first'
from app.reject_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.upload_fixture where probe = 'rejected'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'rejected'),
  (select job_id from pg_temp.claimed_verification where probe = 'rejected'),
  'media-verifier.fixture-01',
  (select lease_token from pg_temp.claimed_verification where probe = 'rejected'),
  (select attempt_number from pg_temp.claimed_verification where probe = 'rejected'),
  'media.malware_detected', 'validation',
  'job:rejected-upload',
  'b9000000-0000-4000-8000-000000000011'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.rejection_fixture rejection
    join public.media_assets asset on asset.id = rejection.media_id
    where rejection.probe = 'first'
      and rejection.media_status = 'failed'
      and asset.status = 'failed'
      and not rejection.replayed
  ),
  'terminal scanner verdict records a visible failed media state'
);
select extensions.ok(
  exists (
    select 1 from pg_temp.rejection_fixture rejection
    join public.audit_events audit on audit.id = rejection.audit_event_id
    join public.outbox_events event on event.id = rejection.outbox_event_id
    where rejection.probe = 'first'
      and audit.action = 'media.upload_rejected'
      and event.event_name = 'media.upload_rejected'
      and event.payload ->> 'error_code' = 'media.malware_detected'
  ),
  'terminal rejection is both audited and emitted through the outbox'
);

insert into pg_temp.rejection_fixture
select result.*, 'replay'
from app.reject_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.upload_fixture where probe = 'rejected'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'rejected'),
  (select job_id from pg_temp.claimed_verification where probe = 'rejected'),
  'media-verifier.fixture-01',
  (select lease_token from pg_temp.claimed_verification where probe = 'rejected'),
  (select attempt_number from pg_temp.claimed_verification where probe = 'rejected'),
  'media.malware_detected', 'validation',
  'job:rejected-upload-replay',
  'b9000000-0000-4000-8000-000000000012'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.rejection_fixture rejection
    where rejection.probe = 'replay'
      and rejection.media_status = 'failed'
      and rejection.replayed
  ),
  'terminal rejection replay cannot duplicate state transitions'
);

reset role;
select extensions.ok(
  not exists (
    select 1 from public.jobs job
    where job.job_type = 'media.verify_vehicle_photo_upload'
      and app.job_payload_contains_forbidden_key(job.payload)
  ),
  'verification jobs never persist credential-bearing payload keys'
);

select * from extensions.finish();
rollback;
