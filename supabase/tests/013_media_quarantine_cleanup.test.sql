-- VYN-MEDIA-001, VYN-STOR-001, VYN-JOB-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, T-MED-003, T-MED-004, T-STOR-001
-- M2-MEDIA-AC-014 through M2-MEDIA-AC-020
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(47);

-- Test-only fixture primitive. Production authenticated access remains revoked.
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
create temporary table pg_temp.scheduled_cleanup (
  cleanup_id uuid,
  upload_session_id uuid,
  job_id uuid,
  cleanup_reason text,
  created boolean,
  job_status text,
  probe text
);
create temporary table pg_temp.claimed_job (
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
create temporary table pg_temp.loaded_cleanup (
  cleanup_id uuid,
  media_id uuid,
  cleanup_reason text,
  generation integer,
  storage_bucket text,
  storage_object_key text,
  expected_checksum_sha256 text,
  already_deleted boolean
);
create temporary table pg_temp.fenced_cleanup (
  cleanup_id uuid,
  checksum_sha256 text,
  replayed boolean,
  probe text
);
create temporary table pg_temp.completed_cleanup (
  cleanup_id uuid,
  media_id uuid,
  cleanup_status text,
  completed_at timestamptz,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.verification_fixture (
  media_id uuid,
  upload_session_id uuid,
  job_id uuid,
  job_status text,
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
  outbox_event_id uuid
);
grant all on
  pg_temp.inventory_fixture,
  pg_temp.upload_fixture,
  pg_temp.scheduled_cleanup,
  pg_temp.claimed_job,
  pg_temp.loaded_cleanup,
  pg_temp.fenced_cleanup,
  pg_temp.completed_cleanup,
  pg_temp.verification_fixture,
  pg_temp.rejection_fixture
to authenticated, service_role;

select extensions.has_table(
  'public', 'media_quarantine_cleanups',
  'durable quarantine cleanup lineage exists'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'media_quarantine_cleanups'
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'quarantine cleanup lineage has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.media_quarantine_cleanups', 'SELECT'
  )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.media_quarantine_cleanups', 'INSERT'
    )
    and not pg_catalog.has_table_privilege(
      'service_role', 'public.media_quarantine_cleanups', 'UPDATE'
    ),
  'browser and worker roles cannot mutate cleanup provenance directly'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.enqueue_due_media_quarantine_cleanup(integer,uuid)', 'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.load_media_quarantine_cleanup(uuid,uuid,uuid,text,uuid,integer)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.complete_media_quarantine_cleanup(uuid,uuid,uuid,text,uuid,integer,text,text,text,uuid)',
      'EXECUTE'
    ),
  'there is no browser path to schedule, inspect, or attest deletion'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.enqueue_due_media_quarantine_cleanup(integer,uuid)', 'EXECUTE'
  )
    and pg_catalog.has_function_privilege(
      'service_role',
      'app.fence_media_quarantine_cleanup_checksum(uuid,uuid,uuid,text,uuid,integer,text,bigint)',
      'EXECUTE'
    )
    and pg_catalog.has_function_privilege(
      'service_role',
      'app.complete_media_quarantine_cleanup(uuid,uuid,uuid,text,uuid,integer,text,text,text,uuid)',
      'EXECUTE'
    ),
  'trusted scheduler and workers receive only canonical cleanup commands'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_constraint constraint_record
    where constraint_record.conname = 'media_quarantine_cleanups_reason_shape_check'
      and constraint_record.contype = 'c'
  )
    and exists (
      select 1 from pg_catalog.pg_constraint constraint_record
      where constraint_record.conname = 'media_quarantine_cleanups_lifecycle_shape_check'
        and constraint_record.contype = 'c'
    ),
  'cleanup reason and lifecycle shapes are database-enforced'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.enqueue_due_media_quarantine_cleanup(integer,uuid)'::regprocedure
  ) like '%expired_intent%'
    and pg_catalog.pg_get_functiondef(
      'app.enqueue_due_media_quarantine_cleanup(integer,uuid)'::regprocedure
    ) like '%terminal_rejection%'
    and pg_catalog.pg_get_functiondef(
      'app.enqueue_due_media_quarantine_cleanup(integer,uuid)'::regprocedure
    ) like '%verified_raw_copy%'
    and pg_catalog.pg_get_functiondef(
      'app.enqueue_due_media_quarantine_cleanup(integer,uuid)'::regprocedure
    ) like '%normalized_master%',
  'scheduler covers all three quarantine reasons and requires a verified master'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.enqueue_due_media_quarantine_cleanup(integer,uuid)'::regprocedure
  ) like '%asset.media_kind = ''vehicle_photo''%'
    and pg_catalog.pg_get_functiondef(
      'app.enqueue_due_media_quarantine_cleanup(integer,uuid)'::regprocedure
    ) not like '%legal_document_original%',
  'legal originals are structurally excluded from quarantine cleanup'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.inventory_fixture
select result.*
from app.create_inventory_unit(
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'm2-quarantine-cleanup-inventory-001',
  '1HGCM82633A900013', 2025, 'Synthetic', 'Cleanup Fixture',
  date '2026-07-16', 10, 'km', 'CAD', 3200000,
  'Fictional quarantine cleanup inventory',
  'request-quarantine-cleanup-inventory-001',
  'ba000000-0000-4000-8000-000000000001'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.inventory_fixture),
  1::bigint,
  'cleanup fixture owns one synthetic inventory unit'
);

insert into pg_temp.upload_fixture
select result.*, 'expired'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-quarantine-expired-upload-001',
  (select inventory_unit_id from pg_temp.inventory_fixture),
  'expired-source.jpg', 'image/jpeg', 1000, repeat('a', 64),
  'request-quarantine-expired-upload-001',
  'ba000000-0000-4000-8000-000000000002'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.upload_fixture where probe = 'expired'),
  1::bigint,
  'expired cleanup starts from one exact vehicle upload intent'
);
reset role;

update public.media_upload_sessions upload
set expires_at = pg_catalog.statement_timestamp() - interval '1 minute'
where upload.id = (
  select upload_session_id from pg_temp.upload_fixture where probe = 'expired'
);

set local role service_role;
insert into pg_temp.scheduled_cleanup
select result.*, 'expired'
from app.enqueue_due_media_quarantine_cleanup(
  1, 'ba000000-0000-4000-8000-000000000003'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.scheduled_cleanup where probe = 'expired'),
  1::bigint,
  'bounded scheduler enqueues one expired abandoned intent'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.upload_fixture fixture
    join public.media_upload_sessions upload on upload.id = fixture.upload_session_id
    where fixture.probe = 'expired' and upload.status = 'expired'
  ),
  'scheduler closes the abandoned upload intent before cleanup'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.scheduled_cleanup scheduled
    join public.media_quarantine_cleanups cleanup on cleanup.id = scheduled.cleanup_id
    where scheduled.probe = 'expired'
      and cleanup.workspace_id = '10000000-0000-4000-8000-000000000001'
      and cleanup.upload_session_id = scheduled.upload_session_id
      and cleanup.reason = 'expired_intent'
      and cleanup.generation = 1
      and cleanup.expected_checksum_sha256 is null
      and cleanup.status = 'queued'
  ),
  'cleanup row preserves workspace, session, generation, and unknown-checksum fence'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.scheduled_cleanup scheduled
    join public.jobs job on job.id = scheduled.job_id
    where scheduled.probe = 'expired'
      and job.job_type = 'media.delete_quarantine_upload'
      and job.entity_type = 'media_upload_session'
      and job.entity_id = scheduled.upload_session_id
      and job.payload_schema_version = 1
      and pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(job.payload, '$.keyvalue()')) = 5
      and job.payload ->> 'reason' = 'expired_intent'
      and job.payload -> 'checksum_sha256' = 'null'::jsonb
      and (job.payload ->> 'generation')::integer = 1
      and job.max_attempts = 8
      and job.backoff_base_seconds = 60
      and job.backoff_max_seconds = 3600
  ),
  'cleanup job has minimized fenced payload and bounded retry telemetry'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.scheduled_cleanup scheduled
    join public.media_quarantine_cleanups cleanup on cleanup.id = scheduled.cleanup_id
    join public.audit_events audit on audit.id = cleanup.queued_audit_event_id
    join public.outbox_events event on event.id = cleanup.outbox_event_id
    where audit.action = 'media.quarantine_cleanup_queued'
      and event.event_name = 'media.quarantine_cleanup_queued'
      and event.correlation_id = 'ba000000-0000-4000-8000-000000000003'
  ),
  'cleanup enqueue commits audit and outbox provenance atomically'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from app.enqueue_due_media_quarantine_cleanup(
      1, 'ba000000-0000-4000-8000-000000000004'
    )
  ),
  0::bigint,
  'scheduler replay cannot enqueue a duplicate cleanup for one session'
);
select extensions.throws_ok(
  $$
    select * from app.enqueue_due_media_quarantine_cleanup(
      501, 'ba000000-0000-4000-8000-000000000005'
    )
  $$,
  '22023',
  'invalid quarantine cleanup enqueue request',
  'scheduler batch size is bounded at the database boundary'
);
select extensions.throws_ok(
  $$
    select * from app.enqueue_due_media_quarantine_cleanup(
      null, 'ba000000-0000-4000-8000-000000000005'
    )
  $$,
  '22023',
  'invalid quarantine cleanup enqueue request',
  'null scheduler limit cannot become an unbounded batch'
);

insert into pg_temp.claimed_job
select claimed.*, 'expired-cleanup'
from app.claim_jobs(
  'media-cleaner.fixture-01', 1, 300,
  array['media.delete_quarantine_upload']
) claimed;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.claimed_job where probe = 'expired-cleanup'),
  1::bigint,
  'quarantine cleanup is consumed only through a durable lease'
);
select extensions.throws_ok(
  $$
    select * from app.load_media_quarantine_cleanup(
      '10000000-0000-4000-8000-000000000001',
      (select upload_session_id from pg_temp.upload_fixture where probe = 'expired'),
      (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
      'media-cleaner.stale',
      (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
      (select attempt_number from pg_temp.claimed_job where probe = 'expired-cleanup')
    )
  $$,
  '55000',
  'only the active quarantine cleanup lease can load an object',
  'stale worker identity cannot read the private exact key'
);
select extensions.throws_ok(
  $$
    select * from app.load_media_quarantine_cleanup(
      '10000000-0000-4000-8000-000000000001',
      (select upload_session_id from pg_temp.upload_fixture where probe = 'expired'),
      (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
      'media-cleaner.fixture-01',
      (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
      null
    )
  $$,
  '22023',
  'invalid quarantine cleanup worker identity',
  'null attempt cannot bypass exact-attempt fencing'
);

insert into pg_temp.loaded_cleanup
select source.*
from app.load_media_quarantine_cleanup(
  '10000000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.upload_fixture where probe = 'expired'),
  (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
  'media-cleaner.fixture-01',
  (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
  (select attempt_number from pg_temp.claimed_job where probe = 'expired-cleanup')
) source;
select extensions.ok(
  exists (
    select 1 from pg_temp.loaded_cleanup source
    where source.cleanup_reason = 'expired_intent'
      and source.generation = 1
      and source.storage_bucket = 'media-private'
      and source.storage_object_key = 'workspaces/10000000-0000-4000-8000-000000000001/uploads/'
        || (select upload_session_id::text from pg_temp.upload_fixture where probe = 'expired')
        || '/source'
      and source.expected_checksum_sha256 is null
      and not source.already_deleted
  ),
  'active lease receives only the exact quarantine object identity'
);
select extensions.throws_ok(
  $$
    select * from app.load_media_quarantine_cleanup(
      '20000000-0000-4000-8000-000000000002',
      (select upload_session_id from pg_temp.upload_fixture where probe = 'expired'),
      (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
      'media-cleaner.fixture-01',
      (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
      (select attempt_number from pg_temp.claimed_job where probe = 'expired-cleanup')
    )
  $$,
  '55000',
  'only the active quarantine cleanup lease can load an object',
  'workspace substitution cannot borrow a cleanup lease'
);

insert into pg_temp.fenced_cleanup
select result.*, 'first'
from app.fence_media_quarantine_cleanup_checksum(
  '10000000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.upload_fixture where probe = 'expired'),
  (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
  'media-cleaner.fixture-01',
  (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
  (select attempt_number from pg_temp.claimed_job where probe = 'expired-cleanup'),
  repeat('c', 64), 1000
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.fenced_cleanup result
    join public.media_quarantine_cleanups cleanup on cleanup.id = result.cleanup_id
    where result.probe = 'first'
      and result.checksum_sha256 = repeat('c', 64)
      and not result.replayed
      and cleanup.status = 'fenced'
      and cleanup.object_checksum_sha256 = repeat('c', 64)
      and cleanup.observed_byte_size = 1000
  ),
  'worker observation establishes the immutable checksum fence before deletion'
);
insert into pg_temp.fenced_cleanup
select result.*, 'replay'
from app.fence_media_quarantine_cleanup_checksum(
  '10000000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.upload_fixture where probe = 'expired'),
  (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
  'media-cleaner.fixture-01',
  (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
  (select attempt_number from pg_temp.claimed_job where probe = 'expired-cleanup'),
  repeat('c', 64), 1000
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.fenced_cleanup result
    where result.probe = 'replay' and result.replayed
  ),
  'same-checksum fence replay is idempotent'
);
select extensions.throws_ok(
  $$
    select * from app.complete_media_quarantine_cleanup(
      '10000000-0000-4000-8000-000000000001',
      (select upload_session_id from pg_temp.upload_fixture where probe = 'expired'),
      (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
      'media-cleaner.fixture-01',
      (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
      (select attempt_number from pg_temp.claimed_job where probe = 'expired-cleanup'),
      repeat('d', 64), 'deleted', 'job:wrong-checksum',
      (select correlation_id from pg_temp.claimed_job where probe = 'expired-cleanup')
    )
  $$,
  '23514',
  'deleted object does not match its checksum fence',
  'completion refuses a replacement checksum'
);

insert into pg_temp.completed_cleanup
select result.*
from app.complete_media_quarantine_cleanup(
  '10000000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.upload_fixture where probe = 'expired'),
  (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
  'media-cleaner.fixture-01',
  (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
  (select attempt_number from pg_temp.claimed_job where probe = 'expired-cleanup'),
  repeat('c', 64), 'not_found', 'job:quarantine-not-found',
  (select correlation_id from pg_temp.claimed_job where probe = 'expired-cleanup')
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.completed_cleanup completion
    join public.media_quarantine_cleanups cleanup on cleanup.id = completion.cleanup_id
    where completion.cleanup_status = 'not_found'
      and not completion.replayed
      and cleanup.status = 'not_found'
      and cleanup.storage_result = 'not_found'
      and cleanup.completed_at = completion.completed_at
  ),
  'worker records exact object absence as a terminal idempotent outcome'
);
select extensions.ok(
  exists (
    select 1 from pg_temp.completed_cleanup completion
    join public.audit_events audit on audit.id = completion.audit_event_id
    join public.outbox_events event on event.id = completion.outbox_event_id
    where audit.action = 'media.quarantine_not_found'
      and event.event_name = 'media.quarantine_not_found'
      and event.payload ->> 'checksum_sha256' = repeat('c', 64)
  ),
  'terminal cleanup emits append-only audit and outbox telemetry'
);
select extensions.lives_ok(
  $$
    select app.complete_job(
      (select job_id from pg_temp.claimed_job where probe = 'expired-cleanup'),
      'media-cleaner.fixture-01',
      (select lease_token from pg_temp.claimed_job where probe = 'expired-cleanup'),
      '{"cleanup_status":"not_found"}'::jsonb,
      null
    )
  $$,
  'generic durable lifecycle closes the cleanup lease'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.claimed_job claimed
    join public.jobs job on job.id = claimed.job_id
    join public.job_attempts attempt on attempt.job_id = job.id
    where claimed.probe = 'expired-cleanup'
      and job.status = 'succeeded'
      and attempt.outcome = 'succeeded'
      and attempt.attempt_number = claimed.attempt_number
  ),
  'cleanup attempt and terminal job result remain observable'
);
reset role;
select extensions.throws_ok(
  $$
    delete from public.media_quarantine_cleanups
    where id = (select cleanup_id from pg_temp.completed_cleanup)
  $$,
  '55000',
  'media history is append-only',
  'cleanup lineage cannot be hard-deleted'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.upload_fixture
select result.*, 'rejected'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-quarantine-rejected-upload-001',
  (select inventory_unit_id from pg_temp.inventory_fixture),
  'rejected-source.png', 'image/png', 900, repeat('d', 64),
  'request-quarantine-rejected-upload-001',
  'ba000000-0000-4000-8000-000000000006'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.upload_fixture where probe = 'rejected'),
  1::bigint,
  'terminal rejection starts from an independent exact upload intent'
);
insert into pg_temp.verification_fixture
select result.*
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'm2-quarantine-rejected-verification-001',
  (select media_id from pg_temp.upload_fixture where probe = 'rejected'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'rejected'),
  'request-quarantine-rejected-verification-001',
  'ba000000-0000-4000-8000-000000000007'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.verification_fixture),
  1::bigint,
  'terminal rejection is linked to one durable verification job'
);
reset role;

set local role service_role;
insert into pg_temp.claimed_job
select claimed.*, 'rejected-verification'
from app.claim_jobs(
  'media-verifier.fixture-01', 1, 300,
  array['media.verify_vehicle_photo_upload']
) claimed;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.claimed_job where probe = 'rejected-verification'),
  1::bigint,
  'terminal verification owns an exact active lease'
);
insert into pg_temp.rejection_fixture
select result.*
from app.reject_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.upload_fixture where probe = 'rejected'),
  (select upload_session_id from pg_temp.upload_fixture where probe = 'rejected'),
  (select job_id from pg_temp.claimed_job where probe = 'rejected-verification'),
  'media-verifier.fixture-01',
  (select lease_token from pg_temp.claimed_job where probe = 'rejected-verification'),
  (select attempt_number from pg_temp.claimed_job where probe = 'rejected-verification'),
  'media.malware_detected', 'validation', 'job:terminal-rejection',
  (select correlation_id from pg_temp.claimed_job where probe = 'rejected-verification')
) result;
select extensions.is(
  (select media_status from pg_temp.rejection_fixture),
  'failed'::text,
  'trusted verification records the terminal rejected media state'
);
select extensions.is(
  (
    select failure.job_status
    from app.fail_job(
      (select job_id from pg_temp.claimed_job where probe = 'rejected-verification'),
      'media-verifier.fixture-01',
      (select lease_token from pg_temp.claimed_job where probe = 'rejected-verification'),
      'validation', 'media.malware_detected',
      'The private scanner rejected the uploaded object.', null, null
    ) failure
  ),
  'dead_letter'::text,
  'generic job lifecycle makes terminal rejection eligible only after dead letter'
);

insert into pg_temp.scheduled_cleanup
select result.*, 'rejected'
from app.enqueue_due_media_quarantine_cleanup(
  10, 'ba000000-0000-4000-8000-000000000008'
) result;
select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_temp.scheduled_cleanup scheduled
    where scheduled.probe = 'rejected'
      and scheduled.cleanup_reason = 'terminal_rejection'
  ),
  1::bigint,
  'bounded scheduler enqueues a terminal rejected upload'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.scheduled_cleanup scheduled
    join public.media_quarantine_cleanups cleanup on cleanup.id = scheduled.cleanup_id
    join public.jobs job on job.id = scheduled.job_id
    where scheduled.probe = 'rejected'
      and cleanup.reason = 'terminal_rejection'
      and cleanup.expected_checksum_sha256 is null
      and cleanup.processing_run_id is null
      and job.payload -> 'checksum_sha256' = 'null'::jsonb
      and (job.payload ->> 'generation')::integer = cleanup.generation
  ),
  'rejected object checksum is observed and fenced by the worker, never trusted from the browser'
);
reset role;
select extensions.ok(
  not exists (
    select 1 from public.jobs job
    where job.job_type = 'media.delete_quarantine_upload'
      and app.job_payload_contains_forbidden_key(job.payload)
  ),
  'cleanup jobs never persist credential-bearing payload keys'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.upload_fixture
select result.*, 'verified'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-quarantine-verified-upload-001',
  (select inventory_unit_id from pg_temp.inventory_fixture),
  'verified-source.jpg', 'image/jpeg', 800, repeat('e', 64),
  'request-quarantine-verified-upload-001',
  'ba000000-0000-4000-8000-000000000011'
) result;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.upload_fixture where probe = 'verified'),
  1::bigint,
  'verified cleanup starts from an independent exact upload intent'
);
reset role;

update public.media_upload_sessions upload
set status = 'completed',
    completed_at = pg_catalog.statement_timestamp(),
    observed_mime_type = 'image/jpeg',
    observed_byte_size = 800,
    observed_checksum_sha256 = repeat('e', 64),
    width = 1600,
    height = 900,
    exif_orientation = 1,
    malware_scan_receipt = pg_catalog.jsonb_build_object(
      'verdict', 'clean',
      'scanner', pg_catalog.jsonb_build_object('name', 'fixture', 'version', '1'),
      'signatureVersion', 'fixture-1',
      'sourceChecksumSha256', repeat('e', 64)
    )
where upload.id = (
  select upload_session_id from pg_temp.upload_fixture where probe = 'verified'
);

insert into public.media_processing_runs (
  id, workspace_id, media_id, generation, source_kind, source_id,
  processing_profile_id, profile_snapshot, profile_checksum_sha256,
  status, terminal_receipt_checksum_sha256, started_at, completed_at
)
select
  'ac000000-0000-4000-8000-000000000001', upload.workspace_id,
  upload.media_id, 1, 'upload_session', upload.id,
  profile.id, profile.profile_snapshot, profile.checksum_sha256,
  'succeeded', repeat('1', 64),
  pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp()
from public.media_upload_sessions upload
join public.media_assets asset
  on asset.workspace_id = upload.workspace_id and asset.id = upload.media_id
join public.media_processing_profiles profile
  on profile.workspace_id = asset.workspace_id
 and profile.id = asset.processing_profile_id
where upload.id = (
  select upload_session_id from pg_temp.upload_fixture where probe = 'verified'
);

insert into public.media_files (
  id, workspace_id, media_id, processing_run_id, file_class, variant,
  storage_bucket, storage_object_key, mime_type, byte_size, checksum_sha256,
  width, height, metadata_stripped, retention_policy, delete_after
)
select
  'ac000000-0000-4000-8000-000000000002', upload.workspace_id,
  upload.media_id, 'ac000000-0000-4000-8000-000000000001',
  'vehicle_photo_raw', 'raw_original', 'media-private',
  'workspaces/' || upload.workspace_id::text || '/media/'
    || upload.media_id::text || '/raw/' || repeat('e', 64) || '.jpg',
  'image/jpeg', 800, repeat('e', 64), 1600, 900, false,
  'delete_after_verified_master',
  pg_catalog.statement_timestamp() + interval '7 days'
from public.media_upload_sessions upload
where upload.id = (
  select upload_session_id from pg_temp.upload_fixture where probe = 'verified'
);

insert into public.media_files (
  id, workspace_id, media_id, processing_run_id, file_class, variant,
  storage_bucket, storage_object_key, mime_type, byte_size, checksum_sha256,
  width, height, metadata_stripped, retention_policy
)
select
  'ac000000-0000-4000-8000-000000000003', upload.workspace_id,
  upload.media_id, 'ac000000-0000-4000-8000-000000000001',
  'vehicle_photo_derivative', 'normalized_master', 'media-private',
  'workspaces/' || upload.workspace_id::text || '/media/'
    || upload.media_id::text
    || '/runs/ac000000-0000-4000-8000-000000000001/normalized_master/'
    || repeat('f', 64) || '.webp',
  'image/webp', 400, repeat('f', 64), 1600, 900, true,
  'retain_until_archive'
from public.media_upload_sessions upload
where upload.id = (
  select upload_session_id from pg_temp.upload_fixture where probe = 'verified'
);

update public.media_assets asset
set status = 'ready', updated_at = pg_catalog.statement_timestamp()
where asset.id = (
  select media_id from pg_temp.upload_fixture where probe = 'verified'
);

set local role service_role;
insert into pg_temp.scheduled_cleanup
select result.*, 'verified'
from app.enqueue_due_media_quarantine_cleanup(
  10, 'ba000000-0000-4000-8000-000000000012'
) result;
select extensions.is(
  (
    select pg_catalog.count(*) from pg_temp.scheduled_cleanup scheduled
    where scheduled.probe = 'verified'
      and scheduled.cleanup_reason = 'verified_raw_copy'
  ),
  1::bigint,
  'bounded scheduler enqueues a successful upload only after verified raw copy'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.scheduled_cleanup scheduled
    join public.media_quarantine_cleanups cleanup on cleanup.id = scheduled.cleanup_id
    where scheduled.probe = 'verified'
      and cleanup.processing_run_id = 'ac000000-0000-4000-8000-000000000001'
      and cleanup.generation = 1
      and cleanup.expected_checksum_sha256 = repeat('e', 64)
  ),
  'successful cleanup is fenced to its exact run generation and source checksum'
);
reset role;
select extensions.ok(
  app.media_quarantine_cleanup_still_safe(
    '10000000-0000-4000-8000-000000000001',
    (select cleanup_id from pg_temp.scheduled_cleanup where probe = 'verified')
  ),
  'deterministic raw and normalized-master keys satisfy the deletion safety fence'
);

reset role;
select extensions.throws_ok(
  $$
    update public.media_files file
    set storage_object_key = file.storage_object_key || '.replacement'
    where file.id = 'ac000000-0000-4000-8000-000000000002'
  $$,
  '55000',
  'media file provenance is immutable',
  'deterministic raw provenance cannot be replaced after scheduling'
);

set local role service_role;
select extensions.ok(
  not exists (
    select 1
    from public.media_quarantine_cleanups cleanup
    join public.media_assets asset
      on asset.workspace_id = cleanup.workspace_id
     and asset.id = cleanup.media_id
    where asset.media_kind in ('legal_document', 'signed_document', 'attachment')
  ),
  'preserved legal originals remain untouched by quarantine cleanup'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from app.enqueue_due_media_quarantine_cleanup(
      10, 'ba000000-0000-4000-8000-000000000010'
    )
  ),
  0::bigint,
  'scheduler is idempotent after all eligible sessions have cleanup lineage'
);
select extensions.ok(
  not exists (
    select 1
    from public.media_quarantine_cleanups cleanup
    join public.media_assets asset
      on asset.workspace_id = cleanup.workspace_id
     and asset.id = cleanup.media_id
    where asset.media_kind <> 'vehicle_photo'
  ),
  'cleanup provenance cannot cross into document media kinds'
);

reset role;
select * from extensions.finish();
rollback;
