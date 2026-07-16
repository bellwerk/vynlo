-- VYN-MEDIA-001, VYN-STOR-001, VYN-JOB-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, T-MED-001 through T-MED-005, T-STOR-001
-- M2-MEDIA-AC-001 through M2-MEDIA-AC-013
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(79);

-- Test-only compatibility grant for media fixture setup. The canonical VIN
-- intake migration keeps this primitive revoked outside the transaction.
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
          pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.media_inventory (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean
);
create temporary table pg_temp.upload_results (
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
create temporary table pg_temp.upload_completions (
  media_id uuid,
  processing_run_id uuid,
  job_id uuid,
  media_status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.upload_verification_requests (
  media_id uuid,
  upload_session_id uuid,
  job_id uuid,
  job_status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.claimed_upload_verification_jobs (
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
  causation_id uuid
);
create temporary table pg_temp.claimed_media_jobs (
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
  causation_id uuid
);
create temporary table pg_temp.processing_completions (
  media_id uuid,
  processing_run_id uuid,
  media_status text,
  aggregate_version bigint,
  raw_file_id uuid,
  normalized_master_file_id uuid,
  raw_delete_after timestamptz,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.legal_original_results (
  media_id uuid,
  media_file_id uuid,
  replayed boolean
);
create temporary table pg_temp.legal_upload_intents (
  upload_session_id uuid,
  document_id uuid,
  media_kind text,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  replayed boolean,
  audit_event_id uuid
);
create temporary table pg_temp.legal_job_queue (
  outbox_event_id uuid,
  job_id uuid
);
create temporary table pg_temp.raw_retention_jobs (
  media_file_id uuid,
  job_id uuid,
  created boolean,
  job_status text
);
create temporary table pg_temp.raw_retention_completions (
  media_file_id uuid,
  media_id uuid,
  deleted_at timestamptz,
  replayed boolean,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.retention_hold_results (
  media_file_id uuid,
  retention_hold boolean,
  retention_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
grant all on
  pg_temp.media_inventory,
  pg_temp.upload_results,
  pg_temp.upload_completions,
  pg_temp.upload_verification_requests,
  pg_temp.claimed_upload_verification_jobs,
  pg_temp.claimed_media_jobs,
  pg_temp.processing_completions,
  pg_temp.legal_original_results,
  pg_temp.legal_upload_intents,
  pg_temp.legal_job_queue,
  pg_temp.raw_retention_jobs,
  pg_temp.raw_retention_completions,
  pg_temp.retention_hold_results
to authenticated, service_role;

select extensions.has_table('public', 'media_processing_profiles', 'immutable media profiles exist');
select extensions.has_table('public', 'inventory_media_collections', 'versioned media collections exist');
select extensions.has_table('public', 'media_assets', 'media aggregates exist');
select extensions.has_table('public', 'media_upload_sessions', 'private upload sessions exist');
select extensions.has_table('public', 'media_processing_runs', 'processing lineage exists');
select extensions.has_table('public', 'media_processing_completions', 'exact lease completions exist');
select extensions.has_table('public', 'media_files', 'managed media file provenance exists');
select extensions.has_table('public', 'media_retention_hold_events', 'audited media retention holds exist');
select extensions.has_table('public', 'media_command_receipts', 'media idempotency receipts exist');
select extensions.ok(
  (
    select pg_catalog.count(*) = 9
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'media_processing_profiles', 'inventory_media_collections',
        'media_assets', 'media_upload_sessions', 'media_processing_runs',
        'media_processing_completions', 'media_files',
        'media_retention_hold_events', 'media_command_receipts'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'T-TEN-001 every exposed media table has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.media_assets', 'INSERT')
    and not pg_catalog.has_table_privilege('authenticated', 'public.media_files', 'UPDATE')
    and not pg_catalog.has_table_privilege('service_role', 'public.media_files', 'INSERT')
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.media_processing_completions', 'SELECT'
    ),
  'T-RBAC-001 browsers and workers cannot bypass canonical media commands'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.create_vehicle_photo_upload_session(uuid,text,uuid,text,text,bigint,text,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.complete_vehicle_photo_processing(uuid,uuid,uuid,uuid,text,uuid,integer,jsonb,text,uuid)',
      'EXECUTE'
    )
    and pg_catalog.has_function_privilege(
      'service_role',
      'app.complete_vehicle_photo_processing(uuid,uuid,uuid,uuid,text,uuid,integer,jsonb,text,uuid)',
      'EXECUTE'
    ),
  'T-RBAC-001 browser intent and service completion grants are separated'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.authorize_managed_media_download(uuid,text,uuid,integer,text,uuid)',
    'EXECUTE'
  )
    and pg_catalog.has_function_privilege(
      'authenticated',
      'app.set_managed_media_retention_hold(uuid,text,uuid,bigint,boolean,text,text,text,uuid)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'service_role',
      'app.record_preserved_legal_original(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)',
      'EXECUTE'
    )
    and pg_catalog.has_function_privilege(
      'service_role',
      'app.complete_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,text,jsonb,text,uuid)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'anon',
      'app.authorize_managed_media_download(uuid,text,uuid,integer,text,uuid)',
      'EXECUTE'
    ),
  'download, hold, and legal-original wrappers expose only their exact intended roles'
);
select extensions.ok(
  exists (
    select 1 from storage.buckets bucket
    where bucket.id = 'media-private' and not bucket.public
  ),
  'T-STOR-001 managed media bucket is private'
);
select extensions.ok(
  not exists (
    select 1 from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.cmd = 'SELECT'
      and 'authenticated' = any(policy.roles)
  )
    and not pg_catalog.has_table_privilege('authenticated', 'storage.objects', 'SELECT'),
  'T-STOR-001 authenticated clients have no persistent storage object read path'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_record
    where constraint_record.conname = 'inventory_cost_entries_supporting_file_fk'
      and constraint_record.contype = 'f'
      and constraint_record.confdeltype = 'r'
  ),
  'cost evidence uses the canonical workspace-scoped media file foreign key'
);

select extensions.throws_ok(
  $$
    insert into public.media_processing_profiles (
      workspace_id, profile_key, version, profile_snapshot, checksum_sha256,
      status, created_by, activated_at
    ) values (
      '10000000-0000-4000-8000-000000000001',
      'vehicle_photo.invalid_insert', 1, '{"fixture":true}', repeat('1', 64),
      'active', '31000000-0000-4000-8000-000000000001',
      pg_catalog.statement_timestamp()
    )
  $$,
  '55000',
  'media processing profiles must be created as draft',
  'processing profiles cannot bypass draft review on insert'
);
select extensions.lives_ok(
  $$
    insert into public.media_processing_profiles (
      workspace_id, profile_key, version, profile_snapshot, checksum_sha256,
      created_by
    ) values (
      '10000000-0000-4000-8000-000000000001',
      'vehicle_photo.lifecycle_fixture', 1, '{"fixture":true}', repeat('2', 64),
      '31000000-0000-4000-8000-000000000001'
    )
  $$,
  'processing profile begins as draft'
);
select extensions.throws_ok(
  $$
    update public.media_processing_profiles
    set status = 'retired',
        activated_at = pg_catalog.statement_timestamp(),
        retired_at = pg_catalog.statement_timestamp()
    where profile_key = 'vehicle_photo.lifecycle_fixture'
  $$,
  '55000',
  'media processing profile lifecycle transition is not allowed',
  'draft profile cannot skip directly to retired'
);
select extensions.lives_ok(
  $$
    update public.media_processing_profiles
    set status = 'active', activated_at = pg_catalog.statement_timestamp()
    where profile_key = 'vehicle_photo.lifecycle_fixture'
  $$,
  'draft processing profile activates explicitly'
);
select extensions.throws_ok(
  $$
    update public.media_processing_profiles
    set status = 'draft', activated_at = null
    where profile_key = 'vehicle_photo.lifecycle_fixture'
  $$,
  '55000',
  'media processing profile lifecycle transition is not allowed',
  'active processing profile cannot return to draft'
);
select extensions.lives_ok(
  $$
    update public.media_processing_profiles
    set status = 'retired', retired_at = pg_catalog.statement_timestamp()
    where profile_key = 'vehicle_photo.lifecycle_fixture'
  $$,
  'active processing profile retires explicitly'
);
select extensions.throws_ok(
  $$
    update public.media_processing_profiles
    set status = 'active', retired_at = null
    where profile_key = 'vehicle_photo.lifecycle_fixture'
  $$,
  '55000',
  'media processing profile lifecycle transition is not allowed',
  'retired processing profile cannot reactivate'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.media_inventory
select result.*
from app.create_inventory_unit(
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'm2-media-inventory-001',
  '1HGCM82633A900001',
  2025,
  'Synthetic',
  'Media Fixture',
  date '2026-07-16',
  10,
  'km',
  'CAD',
  3200000,
  'Fictional media test inventory',
  'request-media-inventory-001',
  'a9000000-0000-4000-8000-000000000001'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.media_inventory),
  1::bigint,
  'media test owns one synthetic inventory unit'
);

insert into pg_temp.upload_results
select result.*, 'first'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-upload-001',
  (select inventory_unit_id from pg_temp.media_inventory),
  'fixture-photo.jpg',
  'image/jpeg',
  1000,
  repeat('a', 64),
  'request-media-upload-001',
  'a9000000-0000-4000-8000-000000000002'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.upload_results upload
    where upload.probe = 'first'
      and upload.upload_bucket = 'media-private'
      and upload.upload_object_key = 'workspaces/10000000-0000-4000-8000-000000000001/uploads/'
        || upload.upload_session_id::text || '/source'
      and upload.upload_object_key not like '%fixture-photo%'
      and upload.expires_at > pg_catalog.statement_timestamp()
      and upload.expires_at <= pg_catalog.statement_timestamp() + interval '16 minutes'
      and not upload.replayed
  ),
  'M2-MEDIA-AC-001 private bounded upload intent uses an opaque workspace key'
);
insert into pg_temp.upload_results
select result.*, 'replay'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-upload-001',
  (select inventory_unit_id from pg_temp.media_inventory),
  'fixture-photo.jpg',
  'image/jpeg',
  1000,
  repeat('a', 64),
  'request-media-upload-replay',
  'a9000000-0000-4000-8000-000000000003'
) result;
select extensions.ok(
  (
    select replay.media_id = original.media_id
      and replay.upload_session_id = original.upload_session_id
      and replay.replayed
    from pg_temp.upload_results original
    join pg_temp.upload_results replay on replay.probe = 'replay'
    where original.probe = 'first'
  ),
  'T-MED-004 upload intent replay returns the original aggregate and session'
);
select extensions.throws_ok(
  $$
    select * from app.create_vehicle_photo_upload_session(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-upload-001',
      (select inventory_unit_id from pg_temp.media_inventory),
      'different.png', 'image/png', 1000, repeat('a', 64),
      'request-media-upload-conflict',
      'a9000000-0000-4000-8000-000000000004'
    )
  $$,
  '23505',
  'media idempotency key was used for a different upload request',
  'T-MED-004 changed upload replay fails closed'
);

insert into pg_temp.upload_verification_requests
select result.*
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-verify-upload-001',
  (select media_id from pg_temp.upload_results where probe = 'first'),
  (select upload_session_id from pg_temp.upload_results where probe = 'first'),
  'request-media-verify-upload-001',
  'a9000000-0000-4000-8000-000000000005'
) result;
reset role;

set local role service_role;
insert into pg_temp.claimed_upload_verification_jobs
select claimed.*
from app.claim_jobs(
  'media-worker.verify-upload-01',
  1,
  300,
  array['media.verify_vehicle_photo_upload']
) claimed;
insert into pg_temp.upload_completions
select result.*
from app.complete_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.upload_results where probe = 'first'),
  (select upload_session_id from pg_temp.upload_results where probe = 'first'),
  (select job_id from pg_temp.claimed_upload_verification_jobs),
  'media-worker.verify-upload-01',
  (select lease_token from pg_temp.claimed_upload_verification_jobs),
  (select attempt_number from pg_temp.claimed_upload_verification_jobs),
  'image/jpeg',
  1000,
  repeat('a', 64),
  2000,
  1000,
  6,
  pg_catalog.jsonb_build_object(
    'scanner', pg_catalog.jsonb_build_object('name', 'fixture-scan', 'version', '1.0.0'),
    'sourceChecksumSha256', repeat('a', 64),
    'verdict', 'clean',
    'signatureVersion', 'fixture-1'
  ),
  'request-media-complete-001',
  'a9000000-0000-4000-8000-000000000005'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.upload_completions completion
    join public.jobs job on job.id = completion.job_id
    join public.outbox_events event on event.id = completion.outbox_event_id
    where completion.media_status = 'quarantined'
      and not completion.replayed
      and job.job_type = 'media.process_vehicle_photo'
      and job.status = 'queued'
      and job.payload ? 'media_id'
      and job.payload ? 'processing_run_id'
      and job.payload ? 'profile_checksum'
      and job.payload ? 'source'
      and pg_catalog.jsonb_object_length(job.payload) = 4
      and event.event_name = 'media.processing_queued'
  ),
  'M2-MEDIA-AC-002 verified quarantine completion atomically queues a reference-only job'
);
select extensions.throws_ok(
  $$
    select * from app.complete_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.upload_results where probe = 'first'),
      (select upload_session_id from pg_temp.upload_results where probe = 'first'),
      (select job_id from pg_temp.claimed_upload_verification_jobs),
      'media-worker.verify-upload-01',
      (select lease_token from pg_temp.claimed_upload_verification_jobs),
      (select attempt_number from pg_temp.claimed_upload_verification_jobs),
      'image/jpeg', 1000, repeat('a', 64), 2000, 1000, 6,
      '{"scanner":{"name":"fixture","version":"1"},"sourceChecksumSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","verdict":"clean"}'::jsonb,
      'request-media-spoof', 'a9000000-0000-4000-8000-000000000006'
    )
  $$,
  '23514',
  'upload must pass signature, dimension, checksum, and malware validation',
  'T-MED-003 incomplete worker verification evidence fails in quarantine'
);

insert into pg_temp.claimed_media_jobs
select claimed.*
from app.claim_jobs('media-worker.fixture-01', 1, 300, array['media.process_vehicle_photo']) claimed;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.claimed_media_jobs),
  1::bigint,
  'durable media processing job is claimable'
);
select extensions.throws_ok(
  $$
    select * from app.start_vehicle_photo_processing(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.upload_completions),
      (select processing_run_id from pg_temp.upload_completions),
      (select job_id from pg_temp.claimed_media_jobs),
      'media-worker.stale',
      (select lease_token from pg_temp.claimed_media_jobs),
      (select attempt_number from pg_temp.claimed_media_jobs),
      'job:stale'
    )
  $$,
  '55000',
  'only the active media job lease can start processing',
  'M2-MEDIA-AC-004 stale worker identity cannot start processing'
);
select extensions.lives_ok(
  $$
    select * from app.start_vehicle_photo_processing(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.upload_completions),
      (select processing_run_id from pg_temp.upload_completions),
      (select job_id from pg_temp.claimed_media_jobs),
      'media-worker.fixture-01',
      (select lease_token from pg_temp.claimed_media_jobs),
      (select attempt_number from pg_temp.claimed_media_jobs),
      'job:media-start'
    )
  $$,
  'active exact worker lease starts processing'
);

insert into pg_temp.processing_completions
select result.*, 'initial'
from app.complete_vehicle_photo_processing(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.upload_completions),
  (select processing_run_id from pg_temp.upload_completions),
  (select job_id from pg_temp.claimed_media_jobs),
  'media-worker.fixture-01',
  (select lease_token from pg_temp.claimed_media_jobs),
  (select attempt_number from pg_temp.claimed_media_jobs),
  pg_catalog.jsonb_build_object(
    'schemaVersion', 1,
    'workspaceId', '10000000-0000-4000-8000-000000000001',
    'mediaId', (select media_id from pg_temp.upload_completions),
    'processingRunId', (select processing_run_id from pg_temp.upload_completions),
    'jobId', (select job_id from pg_temp.claimed_media_jobs),
    'workerId', 'media-worker.fixture-01',
    'leaseId', (select lease_token from pg_temp.claimed_media_jobs),
    'attempt', (select attempt_number from pg_temp.claimed_media_jobs),
    'profileChecksumSha256', 'b2188b2782b7ed47b572910e85e9bf3fb5ae3232d70e310a8e66fa459c850349',
    'sourceChecksumSha256', repeat('a', 64),
    'rawObject', pg_catalog.jsonb_build_object(
      'bucket', 'media-private',
      'objectKey', 'workspaces/10000000-0000-4000-8000-000000000001/media/'
        || (select media_id from pg_temp.upload_completions)::text
        || '/raw/' || repeat('a', 64) || '.jpg',
      'byteSize', 1000,
      'mimeType', 'image/jpeg',
      'checksumSha256', repeat('a', 64)
    ),
    'processorReceipt', pg_catalog.jsonb_build_object(
      'processor', pg_catalog.jsonb_build_object('name', 'fixture-image', 'version', '1.0.0'),
      'profileChecksumSha256', 'b2188b2782b7ed47b572910e85e9bf3fb5ae3232d70e310a8e66fa459c850349',
      'sourceChecksumSha256', repeat('a', 64),
      'outputs', (
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'variant', output.variant,
          'role', output.role,
          'mimeType', 'image/webp',
          'width', output.width,
          'height', output.height,
          'byteSize', output.byte_size,
          'checksumSha256', repeat(output.checksum_character, 64),
          'orientationPolicyApplied', true,
          'normalizedOrientation', 1,
          'outputColorSpace', 'srgb',
          'upscaled', false,
          'metadata', pg_catalog.jsonb_build_object(
            'exifPresent', false, 'gpsPresent', false,
            'iptcPresent', false, 'xmpPresent', false
          )
        ) order by output.ordinality)
        from (values
          ('normalized_master', 'normalized_master', 2000, 1000, 800, 'b', 1),
          ('website_1080', 'website', 1080, 540, 600, 'c', 2),
          ('thumbnail_640', 'thumbnail', 640, 320, 400, 'd', 3),
          ('thumbnail_320', 'thumbnail', 320, 160, 200, 'e', 4)
        ) output(variant, role, width, height, byte_size, checksum_character, ordinality)
      )
    ),
    'derivativeObjects', (
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'bucket', 'media-private',
        'objectKey', 'workspaces/10000000-0000-4000-8000-000000000001/media/'
          || (select media_id from pg_temp.upload_completions)::text
          || '/runs/' || (select processing_run_id from pg_temp.upload_completions)::text
          || '/' || output.variant || '/' || repeat(output.checksum_character, 64) || '.webp',
        'byteSize', output.byte_size,
        'mimeType', 'image/webp',
        'checksumSha256', repeat(output.checksum_character, 64)
      ) order by output.ordinality)
      from (values
        ('normalized_master', 800, 'b', 1),
        ('website_1080', 600, 'c', 2),
        ('thumbnail_640', 400, 'd', 3),
        ('thumbnail_320', 200, 'e', 4)
      ) output(variant, byte_size, checksum_character, ordinality)
    )
  ),
  'job:media-complete',
  (select correlation_id from pg_temp.claimed_media_jobs)
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.processing_completions completion
    where completion.probe = 'initial'
      and completion.media_status = 'ready'
      and completion.raw_file_id is not null
      and completion.normalized_master_file_id is not null
      and completion.raw_delete_after >= pg_catalog.statement_timestamp() + interval '6 days 23 hours'
      and not completion.replayed
  ),
  'M2-MEDIA-AC-004 exact lease completion records ready state and seven-day raw retention'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.media_files file
    where file.processing_run_id = (select processing_run_id from pg_temp.upload_completions)
  ),
  5::bigint,
  'T-MED-001 one raw original and four configured derivatives are recorded'
);
select extensions.ok(
  not exists (
    select 1 from public.media_files file
    where file.processing_run_id = (select processing_run_id from pg_temp.upload_completions)
      and file.file_class = 'vehicle_photo_derivative'
      and (
        file.mime_type <> 'image/webp'
        or not file.metadata_stripped
        or file.width is null or file.height is null
      )
  ),
  'T-MED-002 all public derivatives are WebP with stripped metadata receipts'
);
select extensions.ok(
  exists (
    select 1 from public.media_processing_completions completion
    where completion.processing_run_id = (select processing_run_id from pg_temp.upload_completions)
      and completion.worker_id = 'media-worker.fixture-01'
      and completion.lease_token = (select lease_token from pg_temp.claimed_media_jobs)
      and completion.attempt_number = (select attempt_number from pg_temp.claimed_media_jobs)
  ),
  'exact worker, lease, and attempt completion provenance is append-only'
);

insert into pg_temp.processing_completions
select result.*, 'replay'
from app.complete_vehicle_photo_processing(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.upload_completions),
  (select processing_run_id from pg_temp.upload_completions),
  (select job_id from pg_temp.claimed_media_jobs),
  'media-worker.fixture-01',
  (select lease_token from pg_temp.claimed_media_jobs),
  (select attempt_number from pg_temp.claimed_media_jobs),
  (select receipt from public.media_processing_completions limit 1),
  'job:media-complete-replay',
  (select correlation_id from pg_temp.claimed_media_jobs)
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.processing_completions replay
    join pg_temp.processing_completions original
      on original.probe = 'initial' and replay.probe = 'replay'
    where replay.replayed
      and replay.raw_file_id = original.raw_file_id
      and replay.normalized_master_file_id = original.normalized_master_file_id
  ),
  'T-MED-004 exact completion replay does not duplicate derivatives or mappings'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.media_files file
    where file.processing_run_id = (select processing_run_id from pg_temp.upload_completions)
  ),
  5::bigint,
  'completion replay preserves the original five file records'
);
select extensions.lives_ok(
  $$
    select app.complete_job(
      (select job_id from pg_temp.claimed_media_jobs),
      'media-worker.fixture-01',
      (select lease_token from pg_temp.claimed_media_jobs),
      '{"media_status":"ready"}'::jsonb,
      null
    )
  $$,
  'generic durable job completion follows media artifact completion'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.upload_results
select result.*, 'second'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-upload-002',
  (select inventory_unit_id from pg_temp.media_inventory),
  'second.webp', 'image/webp', 900, repeat('f', 64),
  'request-media-upload-002', 'a9000000-0000-4000-8000-000000000007'
) result;
select extensions.ok(
  (
    select pg_catalog.count(*) = 1
      and pg_catalog.bool_and(asset.is_cover)
    from public.media_assets asset
    where asset.inventory_unit_id = (select inventory_unit_id from pg_temp.media_inventory)
      and asset.is_cover
      and asset.status <> 'archived'
  ),
  'T-MED-005 concurrent-safe collection has exactly one cover after multiple uploads'
);
select extensions.lives_ok(
  $$
    select * from app.reorder_inventory_media(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-reorder-001',
      (select inventory_unit_id from pg_temp.media_inventory),
      (select collection_version from pg_temp.upload_results where probe = 'second'),
      pg_catalog.jsonb_build_array(
        (select media_id from pg_temp.upload_results where probe = 'second'),
        (select media_id from pg_temp.upload_results where probe = 'first')
      ),
      'request-media-reorder-001',
      'a9000000-0000-4000-8000-000000000008'
    )
  $$,
  'T-MED-005 complete optimistic reorder succeeds'
);
select extensions.results_eq(
  $$
    select asset.media_id, asset.sort_order
    from (
      select id as media_id, sort_order
      from public.media_assets
      where inventory_unit_id = (select inventory_unit_id from pg_temp.media_inventory)
        and status <> 'archived'
    ) asset
    order by asset.sort_order
  $$,
  $$
    values
      ((select media_id from pg_temp.upload_results where probe = 'second'), 0),
      ((select media_id from pg_temp.upload_results where probe = 'first'), 1)
  $$,
  'media reorder persists contiguous requested order'
);
select extensions.throws_ok(
  $$
    select * from app.set_inventory_media_cover(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-cover-stale',
      (select inventory_unit_id from pg_temp.media_inventory),
      (select media_id from pg_temp.upload_results where probe = 'second'),
      (select collection_version from pg_temp.upload_results where probe = 'second'),
      'request-media-cover-stale',
      'a9000000-0000-4000-8000-000000000009'
    )
  $$,
  '40001',
  'stale media collection version',
  'T-MED-005 stale concurrent cover edit is rejected'
);
select extensions.lives_ok(
  $$
    select * from app.set_inventory_media_cover(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-cover-001',
      (select inventory_unit_id from pg_temp.media_inventory),
      (select media_id from pg_temp.upload_results where probe = 'second'),
      (select version from public.inventory_media_collections
       where inventory_unit_id = (select inventory_unit_id from pg_temp.media_inventory)),
      'request-media-cover-001',
      'a9000000-0000-4000-8000-000000000010'
    )
  $$,
  'T-MED-005 current cover edit succeeds'
);
select extensions.is(
  (
    select asset.id from public.media_assets asset
    where asset.inventory_unit_id = (select inventory_unit_id from pg_temp.media_inventory)
      and asset.is_cover and asset.status <> 'archived'
  ),
  (select media_id from pg_temp.upload_results where probe = 'second'),
  'cover uniqueness resolves to the requested active media item'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.bool_and(
        event.aggregate_type = 'inventory_media_collection'
        and event.aggregate_id = (select inventory_unit_id from pg_temp.media_inventory)
      )
      and pg_catalog.max(event.aggregate_version) = (
        select collection.version
        from public.inventory_media_collections collection
        where collection.inventory_unit_id = (
          select inventory_unit_id from pg_temp.media_inventory
        )
      )
    from public.outbox_events event
    where event.workspace_id = '10000000-0000-4000-8000-000000000001'
      and event.event_name in ('media.collection_reordered', 'media.cover_changed')
      and event.aggregate_id = (select inventory_unit_id from pg_temp.media_inventory)
  ),
  'collection reorder and cover events use the versioned media collection aggregate'
);
select extensions.throws_ok(
  $$
    select * from app.create_vehicle_photo_upload_session(
      '20000000-0000-4000-8000-000000000002',
      'm2-media-cross-workspace',
      (select inventory_unit_id from pg_temp.media_inventory),
      'cross.jpg', 'image/jpeg', 1000, repeat('1', 64),
      'request-media-cross', 'a9000000-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'active workspace membership and media permission are required',
  'T-TEN-001 request workspace cannot be borrowed across memberships'
);
reset role;

insert into public.deals (
  id, workspace_id, deal_type_key, status, currency_code,
  owner_membership_id, idempotency_key, command_fingerprint, created_by
) values (
  'a9300000-0000-4000-8000-000000000090',
  '10000000-0000-4000-8000-000000000001',
  'synthetic.media', 'draft', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'm2-media-legal-deal', repeat('3', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.documents (
  id, workspace_id, document_type_id, template_version_id, deal_id,
  locale, render_input_snapshot, render_input_checksum,
  idempotency_key, command_fingerprint, created_by
) values (
  'a9000000-0000-4000-8000-000000000099',
  '10000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001',
  'a9300000-0000-4000-8000-000000000090',
  'en-CA', '{"synthetic":true}', repeat('4', 64),
  'm2-media-legal-document', repeat('5', 64),
  '31000000-0000-4000-8000-000000000001'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legal_upload_intents
select result.*
from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-legal-intent-001',
  'a9000000-0000-4000-8000-000000000099',
  'legal_document',
  'fixture-original.pdf',
  'application/pdf',
  2048,
  repeat('9', 64),
  'request-media-legal-intent-001',
  'a9000000-0000-4000-8000-000000000012'
) result;
insert into pg_temp.legal_job_queue
select result.outbox_event_id, result.job_id
from app.request_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-legal-verification-001',
  'a9000000-0000-4000-8000-000000000099',
  (select upload_session_id from pg_temp.legal_upload_intents),
  'request-media-legal-verification-001',
  'a9000000-0000-4000-8000-000000000012'
) result;
reset role;

set local role service_role;
insert into pg_temp.claimed_media_jobs
select claimed.*
from app.claim_jobs(
  'media-worker.legal-01', 1, 300, array['media.verify_legal_original']
) claimed;
select extensions.throws_ok(
  $$
    select * from app.complete_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001',
      'a9000000-0000-4000-8000-000000000099',
      (select upload_session_id from pg_temp.legal_upload_intents),
      (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
      'media-worker.stale',
      (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
      (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
      'application/pdf', 2048, repeat('9', 64),
      'provider-generation-legal-001', '{}'::jsonb,
      'request-media-legal-stale',
      'a9000000-0000-4000-8000-000000000012'
    )
  $$,
  '55000',
  'only the active legal verification lease can complete an upload',
  'stale legal verification worker cannot record preserved bytes'
);
select extensions.throws_ok(
  $$
    select * from app.complete_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001',
      'a9000000-0000-4000-8000-000000000099',
      (select upload_session_id from pg_temp.legal_upload_intents),
      (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
      'media-worker.legal-01',
      (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
      (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
      'application/pdf', 2048, repeat('9', 64),
      'provider-generation-legal-001',
      pg_catalog.jsonb_build_object(
        'schemaVersion', 1,
        'jobId', (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
        'workerId', 'media-worker.legal-01',
        'leaseId', (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
        'attempt', (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
        'verifier', pg_catalog.jsonb_build_object('name', 'fixture-verifier', 'version', '1.0.0'),
        'storage', pg_catalog.jsonb_build_object(
          'bucket', 'media-private',
          'objectKey', (select upload_object_key from pg_temp.legal_upload_intents),
          'generation', 'provider-generation-legal-001',
          'mimeType', 'application/pdf',
          'byteSize', '2048',
          'checksumSha256', repeat('8', 64)
        ),
        'malwareScan', pg_catalog.jsonb_build_object(
          'verdict', 'clean', 'sourceChecksumSha256', repeat('9', 64),
          'scanner', 'fixture-clamd', 'signatureVersion', 'fixture-1'
        )
      ),
      'request-media-legal-bad-receipt',
      'a9000000-0000-4000-8000-000000000012'
    )
  $$,
  '23514',
  'legal original verification does not match upload intent',
  'legal original checksum and provider generation require an exact verification receipt'
);
insert into pg_temp.legal_original_results
select result.*
from app.complete_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'a9000000-0000-4000-8000-000000000099',
  (select upload_session_id from pg_temp.legal_upload_intents),
  (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
  'media-worker.legal-01',
  (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
  (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
  'application/pdf', 2048, repeat('9', 64),
  'provider-generation-legal-001',
  pg_catalog.jsonb_build_object(
    'schemaVersion', 1,
    'jobId', (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
    'workerId', 'media-worker.legal-01',
    'leaseId', (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
    'attempt', (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.verify_legal_original'),
    'verifier', pg_catalog.jsonb_build_object('name', 'fixture-verifier', 'version', '1.0.0'),
    'storage', pg_catalog.jsonb_build_object(
      'bucket', 'media-private',
      'objectKey', (select upload_object_key from pg_temp.legal_upload_intents),
      'generation', 'provider-generation-legal-001',
      'mimeType', 'application/pdf',
      'byteSize', '2048',
      'checksumSha256', repeat('9', 64)
    ),
    'malwareScan', pg_catalog.jsonb_build_object(
      'verdict', 'clean', 'sourceChecksumSha256', repeat('9', 64),
      'scanner', 'fixture-clamd', 'signatureVersion', 'fixture-1'
    )
  ),
  'request-media-legal-001',
  'a9000000-0000-4000-8000-000000000012'
) result;
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_original_results result
    join public.media_files file on file.id = result.media_file_id
    join public.media_assets asset on asset.id = result.media_id
    where asset.status = 'ready'
      and file.file_class = 'legal_document_original'
      and file.variant = 'legal_original'
      and file.retention_policy = 'preserve_original'
      and file.delete_after is null
      and file.deleted_at is null
      and not file.metadata_stripped
      and file.storage_generation = 'provider-generation-legal-001'
      and file.verification_receipt -> 'malwareScan' ->> 'verdict' = 'clean'
  ),
  'T-MED-002 legal originals are byte-preserved with no deletion schedule'
);
reset role;
select extensions.throws_ok(
  $$
    update public.media_files
    set deleted_at = pg_catalog.statement_timestamp()
    where id = (select media_file_id from pg_temp.legal_original_results)
  $$,
  '55000',
  'media file provenance is immutable',
  'legal original deletion is prohibited even for the database owner'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.retention_hold_results
select result.*, 'legal-hold'
from app.set_managed_media_retention_hold(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-legal-hold-001',
  (select media_file_id from pg_temp.legal_original_results),
  1, true, 'legal', 'Synthetic legal hold fixture',
  'request-media-legal-hold-001',
  'a9000000-0000-4000-8000-000000000013'
) result;
insert into pg_temp.retention_hold_results
select result.*, 'legal-hold-replay'
from app.set_managed_media_retention_hold(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-legal-hold-001',
  (select media_file_id from pg_temp.legal_original_results),
  1, true, 'legal', 'Synthetic legal hold fixture',
  'request-media-legal-hold-replay',
  'a9000000-0000-4000-8000-000000000014'
) result;
select extensions.ok(
  (
    select initial.retention_hold
      and initial.retention_version = 2
      and not initial.replayed
      and replay.replayed
      and replay.retention_version = initial.retention_version
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
    from pg_temp.retention_hold_results initial
    join pg_temp.retention_hold_results replay
      on replay.probe = 'legal-hold-replay'
    where initial.probe = 'legal-hold'
  ),
  'legal hold command is audited, versioned, and exactly idempotent'
);
select extensions.throws_ok(
  $$
    select * from app.set_managed_media_retention_hold(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-legal-unhold-stale',
      (select media_file_id from pg_temp.legal_original_results),
      1, false, 'legal', 'Synthetic stale release fixture',
      'request-media-legal-unhold-stale',
      'a9000000-0000-4000-8000-000000000015'
    )
  $$,
  '40001',
  'media retention version conflict',
  'stale legal hold release fails optimistic concurrency'
);
insert into pg_temp.retention_hold_results
select result.*, 'legal-release'
from app.set_managed_media_retention_hold(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-legal-unhold-001',
  (select media_file_id from pg_temp.legal_original_results),
  2, false, 'legal', 'Synthetic legal release fixture',
  'request-media-legal-unhold-001',
  'a9000000-0000-4000-8000-000000000016'
) result;
select extensions.ok(
  exists (
    select 1
    from pg_temp.retention_hold_results result
    join public.media_retention_hold_events hold_event
      on hold_event.outbox_event_id = result.outbox_event_id
     and hold_event.audit_event_id = result.audit_event_id
    where result.probe = 'legal-release'
      and not result.retention_hold
      and result.retention_version = 3
      and hold_event.action = 'released'
      and hold_event.hold_kind = 'legal'
  ),
  'legal release preserves an append-only audit and outbox evidence chain'
);
reset role;

alter table public.media_files disable trigger media_files_guard;
update public.media_files
set delete_after = pg_catalog.statement_timestamp() - interval '1 minute'
where id = (
  select raw_file_id from pg_temp.processing_completions where probe = 'initial'
);
alter table public.media_files enable trigger media_files_guard;

set local role service_role;
insert into pg_temp.raw_retention_jobs
select result.*
from app.enqueue_due_vehicle_raw_retention(
  10,
  'a9000000-0000-4000-8000-000000000020'
) result
where result.media_file_id = (
  select raw_file_id from pg_temp.processing_completions where probe = 'initial'
);
insert into pg_temp.claimed_media_jobs
select claimed.*
from app.claim_jobs(
  'media-worker.retention-01', 1, 300, array['media.delete_retained_raw']
) claimed;
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.retention_hold_results
select result.*, 'raw-incident-hold'
from app.set_managed_media_retention_hold(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-raw-hold-001',
  (select raw_file_id from pg_temp.processing_completions where probe = 'initial'),
  1, true, 'incident', 'Synthetic incident hold before deletion',
  'request-media-raw-hold-001',
  'a9000000-0000-4000-8000-000000000021'
) result;
reset role;

set local role service_role;
select extensions.throws_ok(
  $$
    select * from app.load_vehicle_raw_retention(
      '10000000-0000-4000-8000-000000000001',
      (select raw_file_id from pg_temp.processing_completions where probe = 'initial'),
      (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
      'media-worker.retention-01',
      (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
      (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw')
    )
  $$,
  '55000',
  'raw retention is not due',
  'incident hold acquired before load blocks physical deletion authorization'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.retention_hold_results
select result.*, 'raw-incident-release'
from app.set_managed_media_retention_hold(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-raw-unhold-001',
  (select raw_file_id from pg_temp.processing_completions where probe = 'initial'),
  2, false, 'incident', 'Synthetic incident release before deletion',
  'request-media-raw-unhold-001',
  'a9000000-0000-4000-8000-000000000022'
) result;
reset role;

set local role service_role;
select extensions.lives_ok(
  $$
    select * from app.load_vehicle_raw_retention(
      '10000000-0000-4000-8000-000000000001',
      (select raw_file_id from pg_temp.processing_completions where probe = 'initial'),
      (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
      'media-worker.retention-01',
      (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
      (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw')
    )
  $$,
  'exact retention lease establishes a deletion fence before storage mutation'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.set_managed_media_retention_hold(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-raw-hold-too-late',
      (select raw_file_id from pg_temp.processing_completions where probe = 'initial'),
      3, true, 'incident', 'Synthetic hold after deletion fence',
      'request-media-raw-hold-too-late',
      'a9000000-0000-4000-8000-000000000023'
    )
  $$,
  '55000',
  'media retention deletion is already in progress',
  'hold and physical deletion are mutually exclusive after the deletion fence'
);
reset role;

set local role service_role;
insert into pg_temp.raw_retention_completions
select result.*, 'initial'
from app.complete_vehicle_raw_retention(
  '10000000-0000-4000-8000-000000000001',
  (select raw_file_id from pg_temp.processing_completions where probe = 'initial'),
  (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
  'media-worker.retention-01',
  (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
  (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
  'deleted', 'request-media-raw-delete-001',
  'a9000000-0000-4000-8000-000000000020'
) result;
insert into pg_temp.raw_retention_completions
select result.*, 'replay'
from app.complete_vehicle_raw_retention(
  '10000000-0000-4000-8000-000000000001',
  (select raw_file_id from pg_temp.processing_completions where probe = 'initial'),
  (select job_id from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
  'media-worker.retention-01',
  (select lease_token from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
  (select attempt_number from pg_temp.claimed_media_jobs where job_type = 'media.delete_retained_raw'),
  'deleted', 'request-media-raw-delete-replay',
  'a9000000-0000-4000-8000-000000000020'
) result;
select extensions.ok(
  (
    select not initial.replayed
      and replay.replayed
      and initial.deleted_at = replay.deleted_at
      and initial.aggregate_version = replay.aggregate_version
      and initial.aggregate_version = asset.version
      and event.aggregate_version = asset.version
      and event.aggregate_type = 'media_asset'
    from pg_temp.raw_retention_completions initial
    join pg_temp.raw_retention_completions replay on replay.probe = 'replay'
    join public.media_assets asset on asset.id = initial.media_id
    join public.outbox_events event on event.id = initial.outbox_event_id
    where initial.probe = 'initial'
  ),
  'raw retention completion advances and replays the exact media aggregate version'
);
reset role;

-- Policy probes cover every non-vehicle media kind. The additional signed and
-- attachment rows are transaction-local storage fixtures; they do not grant or
-- introduce a browser write path.
insert into public.media_assets (
  id, workspace_id, document_id, owner_entity_type, owner_entity_id, media_kind,
  status, created_by
) values
  (
    'a9100000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'a9000000-0000-4000-8000-000000000099',
    'document',
    'a9000000-0000-4000-8000-000000000099',
    'signed_document',
    'ready',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    'a9100000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    null,
    'attachment',
    'a9300000-0000-4000-8000-000000000002',
    'attachment',
    'ready',
    '31000000-0000-4000-8000-000000000001'
  );
insert into public.media_files (
  id, workspace_id, media_id, file_class, variant, storage_bucket,
  storage_object_key, storage_generation, mime_type, byte_size, checksum_sha256,
  metadata_stripped, retention_policy, verification_receipt
) values
  (
    'a9200000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'a9100000-0000-4000-8000-000000000001',
    'legal_document_original',
    'legal_original',
    'media-private',
    'workspaces/10000000-0000-4000-8000-000000000001/documents/'
      || 'a9000000-0000-4000-8000-000000000099/files/'
      || 'a9200000-0000-4000-8000-000000000001/' || repeat('7', 64) || '.pdf',
    'provider-generation-signed-001',
    'application/pdf',
    1024,
    repeat('7', 64),
    false,
    'preserve_original',
    pg_catalog.jsonb_build_object(
      'schemaVersion', 1,
      'verifier', pg_catalog.jsonb_build_object('name', 'fixture-verifier', 'version', '1.0.0'),
      'storage', pg_catalog.jsonb_build_object(
        'bucket', 'media-private',
        'objectKey', 'workspaces/10000000-0000-4000-8000-000000000001/documents/a9000000-0000-4000-8000-000000000099/files/a9200000-0000-4000-8000-000000000001/' || repeat('7', 64) || '.pdf',
        'generation', 'provider-generation-signed-001',
        'byteSize', '1024', 'checksumSha256', repeat('7', 64)
      ),
      'malwareScan', pg_catalog.jsonb_build_object(
        'verdict', 'clean', 'sourceChecksumSha256', repeat('7', 64),
        'scanner', 'fixture-clamd', 'signatureVersion', 'fixture-1'
      )
    )
  ),
  (
    'a9200000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'a9100000-0000-4000-8000-000000000002',
    'legal_document_original',
    'legal_original',
    'media-private',
    'workspaces/10000000-0000-4000-8000-000000000001/attachments/'
      || 'a9300000-0000-4000-8000-000000000002/files/'
      || 'a9200000-0000-4000-8000-000000000002/' || repeat('8', 64) || '.pdf',
    'provider-generation-attachment-001',
    'application/pdf',
    512,
    repeat('8', 64),
    false,
    'preserve_original',
    pg_catalog.jsonb_build_object(
      'schemaVersion', 1,
      'verifier', pg_catalog.jsonb_build_object('name', 'fixture-verifier', 'version', '1.0.0'),
      'storage', pg_catalog.jsonb_build_object(
        'bucket', 'media-private',
        'objectKey', 'workspaces/10000000-0000-4000-8000-000000000001/attachments/a9300000-0000-4000-8000-000000000002/files/a9200000-0000-4000-8000-000000000002/' || repeat('8', 64) || '.pdf',
        'generation', 'provider-generation-attachment-001',
        'byteSize', '512', 'checksumSha256', repeat('8', 64)
      ),
      'malwareScan', pg_catalog.jsonb_build_object(
        'verdict', 'clean', 'sourceChecksumSha256', repeat('8', 64),
        'scanner', 'fixture-clamd', 'signatureVersion', 'fixture-1'
      )
    )
  );

insert into storage.objects (id, bucket_id, name)
select
  'b9000000-0000-4000-8000-000000000001',
  file.storage_bucket,
  file.storage_object_key
from public.media_files file
where file.id = (
  select normalized_master_file_id
  from pg_temp.processing_completions
  where probe = 'initial'
)
union all
select
  'b9000000-0000-4000-8000-000000000002',
  file.storage_bucket,
  file.storage_object_key
from public.media_files file
where file.id = (select media_file_id from pg_temp.legal_original_results)
union all
select
  'b9000000-0000-4000-8000-000000000003',
  file.storage_bucket,
  file.storage_object_key
from public.media_files file
where file.id = 'a9200000-0000-4000-8000-000000000001'
union all
select
  'b9000000-0000-4000-8000-000000000004',
  file.storage_bucket,
  file.storage_object_key
from public.media_files file
where file.id = 'a9200000-0000-4000-8000-000000000002';

insert into public.role_permissions (
  workspace_id, role_id, permission_id, status, granted_by
)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000002',
  permission.id,
  'active',
  '31000000-0000-4000-8000-000000000001'
from public.permissions permission
where permission.workspace_id is null
  and permission.key = 'media.read';

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.results_eq(
  $$select distinct asset.media_kind from public.media_assets asset order by asset.media_kind$$,
  $$values ('vehicle_photo'::text)$$,
  'media-only role sees vehicle-photo assets and no document-like asset kind'
);
select extensions.results_eq(
  $$
    select distinct asset.media_kind
    from public.media_files file
    join public.media_assets asset
      on asset.workspace_id = file.workspace_id
     and asset.id = file.media_id
    order by asset.media_kind
  $$,
  $$values ('vehicle_photo'::text)$$,
  'media-only role sees vehicle-photo file metadata and no document-like file metadata'
);
select extensions.throws_ok(
  $$
    select pg_catalog.count(*) from storage.objects
  $$,
  '42501',
  'permission denied for table objects',
  'media-only role cannot directly read any storage object row'
);
select extensions.lives_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'm2-download-media-only-001',
      (select normalized_master_file_id from pg_temp.processing_completions where probe = 'initial'),
      60,
      'request-download-media-only-001',
      'a9000000-0000-4000-8000-000000000030'
    )
  $$,
  'media-only role can authorize an exact vehicle-photo download'
);
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'm2-download-media-legal-denied',
      (select media_file_id from pg_temp.legal_original_results),
      60,
      'request-download-media-legal-denied',
      'a9000000-0000-4000-8000-000000000031'
    )
  $$,
  '42501',
  'managed media download is not authorized',
  'media-only role cannot authorize a legal-document download'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
update public.role_permissions role_permission
set status = 'revoked',
    revoked_by = '31000000-0000-4000-8000-000000000001',
    revoked_at = pg_catalog.statement_timestamp()
from public.permissions permission
where role_permission.workspace_id = '10000000-0000-4000-8000-000000000001'
  and role_permission.role_id = '51000000-0000-4000-8000-000000000002'
  and role_permission.permission_id = permission.id
  and permission.workspace_id is null
  and permission.key = 'media.read';
insert into public.role_permissions (
  workspace_id, role_id, permission_id, status, granted_by
)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000002',
  permission.id,
  'active',
  '31000000-0000-4000-8000-000000000001'
from public.permissions permission
where permission.workspace_id is null
  and permission.key = 'documents.read';

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.results_eq(
  $$select distinct asset.media_kind from public.media_assets asset order by asset.media_kind$$,
  $$
    values
      ('attachment'::text),
      ('legal_document'::text),
      ('signed_document'::text)
  $$,
  'documents-only role sees every non-vehicle asset kind and no vehicle photos'
);
select extensions.results_eq(
  $$
    select distinct asset.media_kind
    from public.media_files file
    join public.media_assets asset
      on asset.workspace_id = file.workspace_id
     and asset.id = file.media_id
    order by asset.media_kind
  $$,
  $$
    values
      ('attachment'::text),
      ('legal_document'::text),
      ('signed_document'::text)
  $$,
  'documents-only role sees every non-vehicle file kind and no vehicle-photo file metadata'
);
select extensions.throws_ok(
  $$
    select pg_catalog.count(*) from storage.objects
  $$,
  '42501',
  'permission denied for table objects',
  'documents-only role cannot directly read any storage object row'
);
select extensions.lives_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'm2-download-doc-only-001',
      (select media_file_id from pg_temp.legal_original_results),
      60,
      'request-download-doc-only-001',
      'a9000000-0000-4000-8000-000000000032'
    )
  $$,
  'documents-only role can authorize an exact legal-document download'
);
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'm2-download-doc-media-denied',
      (select normalized_master_file_id from pg_temp.processing_completions where probe = 'initial'),
      60,
      'request-download-doc-media-denied',
      'a9000000-0000-4000-8000-000000000033'
    )
  $$,
  '42501',
  'managed media download is not authorized',
  'documents-only role cannot authorize a vehicle-photo download'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(distinct asset.workspace_id)
    from public.media_assets asset
  ),
  1::bigint,
  'T-TEN-001 authenticated media reads expose one authorized workspace only'
);
select extensions.lives_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'm2-download-admin-001',
      (select normalized_master_file_id from pg_temp.processing_completions where probe = 'initial'),
      60,
      'request-download-admin-001',
      'a9000000-0000-4000-8000-000000000034'
    )
  $$,
  'T-STOR-001 eligible media reader can authorize one exact managed object'
);
select extensions.ok(
  (
    select result.replayed
    from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'm2-download-admin-001',
      (select normalized_master_file_id from pg_temp.processing_completions where probe = 'initial'),
      60,
      'request-download-admin-replay',
      'a9000000-0000-4000-8000-000000000036'
    ) result
  ),
  'download authorization replay returns the original audited grant decision'
);
select extensions.ok(
  exists (
    select 1
    from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'm2-download-admin-legal-001',
      (select media_file_id from pg_temp.legal_original_results),
      60,
      'request-download-admin-legal-001',
      'a9000000-0000-4000-8000-000000000037'
    ) result
    join public.audit_events audit on audit.id = result.audit_event_id
    where result.media_file_id = (
        select media_file_id from pg_temp.legal_original_results
      )
      and result.mime_type = 'application/pdf'
      and result.byte_size = 2048
      and result.checksum_sha256 = repeat('9', 64)
      and result.media_kind = 'legal_document'
      and not result.replayed
      and pg_catalog.to_jsonb(result)::text
        !~* '(storage_bucket|storage_object|storage_generation|provider-generation)'
      and audit.request_id = 'request-download-admin-legal-001'
      and audit.correlation_id = 'a9000000-0000-4000-8000-000000000037'
  ),
  'download authorization returns exact immutable metadata without provider coordinates'
);
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '20000000-0000-4000-8000-000000000002',
      'm2-download-admin-cross-denied',
      (select normalized_master_file_id from pg_temp.processing_completions where probe = 'initial'),
      60,
      'request-download-admin-cross-denied',
      'a9000000-0000-4000-8000-000000000035'
    )
  $$,
  '42501',
  'managed media download is not authorized',
  'T-STOR-001 cross-workspace download authorization fails closed'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'm2-download-legal-aal1-denied',
      (select media_file_id from pg_temp.legal_original_results),
      60,
      'request-download-legal-aal1-denied',
      'a9000000-0000-4000-8000-000000000038'
    )
  $$,
  '42501',
  'recent strong authentication is required',
  'legal original download authorization requires recent strong authentication'
);
reset role;

select extensions.lives_ok(
  $$
    update public.media_processing_profiles
    set status = 'retired', retired_at = pg_catalog.statement_timestamp()
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and profile_key = 'vehicle_photo.default'
      and status = 'active'
  $$,
  'active default processing profile retires before roll-forward'
);
select extensions.lives_ok(
  $$
    select app.ensure_default_vehicle_photo_profile(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001'
    )
  $$,
  'default processing profile rolls forward after retirement'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(*) filter (where status = 'retired' and version = 1) = 1
      and pg_catalog.count(*) filter (where status = 'active' and version = 2) = 1
      and pg_catalog.count(distinct checksum_sha256) = 2
      and pg_catalog.bool_and(profile_snapshot ->> 'checksumSha256' = checksum_sha256)
      and pg_catalog.bool_and((profile_snapshot ->> 'version')::integer = version)
    from public.media_processing_profiles
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and profile_key = 'vehicle_photo.default'
  ),
  'profile roll-forward preserves retired version one and activates checksummed version two'
);

select extensions.ok(
  not exists (
    select 1
    from public.outbox_events event
    where event.event_name like 'media.%'
      and app.job_payload_contains_forbidden_key(event.payload)
  ),
  'media outbox payloads contain no credential-bearing fields'
);
select extensions.ok(
  not exists (
    select 1
    from public.audit_events audit
    where audit.action like 'media.%'
      and (
        coalesce(audit.before_data, '{}'::jsonb) ? 'original_filename'
        or coalesce(audit.after_data, '{}'::jsonb) ? 'original_filename'
        or coalesce(audit.metadata, '{}'::jsonb) ? 'original_filename'
      )
  ),
  'audit telemetry excludes original filenames and object credentials'
);

select * from extensions.finish();
rollback;
