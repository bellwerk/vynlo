-- M2-MEDIA-AC-027, VYN-MEDIA-001, VYN-JOB-001, VYN-TEN-001,
-- VYN-SEC-001, VYN-AUD-001, T-MED-003, T-JOB-001, T-TEN-001,
-- T-RBAC-001, T-AUD-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(34);

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
  perform pg_catalog.set_config(
    'request.jwt.claim.sub', fixture_user_id::text, true
  );
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

-- Actor B has the same workspace permission as actor A. Ownership assertions
-- therefore test the upload boundary rather than a role mismatch.
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '62000000-0000-4000-8000-000000000024',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '51000000-0000-4000-8000-000000000001',
  'active'
);

create temporary table pg_temp.vehicle_retry_inventory (
  inventory_unit_id uuid, vehicle_id uuid, stock_number text, replayed boolean
);
create temporary table pg_temp.vehicle_retry_uploads (
  media_id uuid, upload_session_id uuid, upload_bucket text,
  upload_object_key text, expires_at timestamptz, collection_version bigint,
  aggregate_version bigint, replayed boolean, audit_event_id uuid,
  outbox_event_id uuid, probe text
);
create temporary table pg_temp.vehicle_retry_requests (
  media_id uuid, upload_session_id uuid, job_id uuid, job_status text,
  aggregate_version bigint, replayed boolean, audit_event_id uuid,
  outbox_event_id uuid, probe text
);
create temporary table pg_temp.vehicle_retry_claims (
  job_id uuid, workspace_id uuid, outbox_event_id uuid, job_type text,
  entity_type text, entity_id uuid, payload_schema_version integer,
  payload jsonb, idempotency_key text, attempt_number integer,
  max_attempts integer, lease_token uuid, lease_expires_at timestamptz,
  correlation_id uuid, causation_id uuid, probe text
);
create temporary table pg_temp.vehicle_retry_failures (
  job_status text, retry_at timestamptz, review_required boolean, probe text
);
create temporary table pg_temp.vehicle_retry_rejections (
  media_id uuid, media_status text, aggregate_version bigint,
  replayed boolean, audit_event_id uuid, outbox_event_id uuid, probe text
);
create temporary table pg_temp.vehicle_retry_statuses (
  upload_session_id uuid, media_id uuid, status text, job_id uuid,
  attempt_count integer, maximum_attempts integer, retry_at timestamptz,
  retryable boolean, error_classification text, error_code text,
  completed_at timestamptz, probe text
);
create temporary table pg_temp.vehicle_retries (
  upload_session_id uuid, media_id uuid, source_job_id uuid, job_id uuid,
  job_status text, aggregate_version bigint, replayed boolean,
  audit_event_id uuid, outbox_event_id uuid, probe text
);
grant all on pg_temp.vehicle_retry_inventory, pg_temp.vehicle_retry_uploads,
  pg_temp.vehicle_retry_requests, pg_temp.vehicle_retry_claims,
  pg_temp.vehicle_retry_failures, pg_temp.vehicle_retry_rejections,
  pg_temp.vehicle_retry_statuses, pg_temp.vehicle_retries
to authenticated, service_role;

select extensions.has_function(
  'app', 'get_vehicle_photo_upload_status', array['uuid', 'uuid', 'uuid'],
  'owner-safe vehicle upload status projection exists'
);
select extensions.has_function(
  'app', 'retry_vehicle_photo_upload_verification',
  array['uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'uuid'],
  'reasoned vehicle verification dead-letter retry exists'
);
select extensions.ok(
  (select status_fn.prosecdef and status_fn.provolatile = 's'
     and retry_fn.prosecdef and retry_fn.provolatile = 'v'
     and exists (
       select 1
       from pg_catalog.unnest(
         coalesce(status_fn.proconfig, array[]::text[])
       ) setting
       where setting in ('search_path=', 'search_path=""')
     )
     and exists (
       select 1
       from pg_catalog.unnest(
         coalesce(retry_fn.proconfig, array[]::text[])
       ) setting
       where setting in ('search_path=', 'search_path=""')
     )
   from pg_catalog.pg_proc status_fn
   cross join pg_catalog.pg_proc retry_fn
   where status_fn.oid =
     'app.get_vehicle_photo_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
     and retry_fn.oid =
     'app.retry_vehicle_photo_upload_verification(uuid,text,uuid,uuid,text,text,uuid)'::pg_catalog.regprocedure),
  'both browser functions are SECURITY DEFINER with an empty search path'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.get_vehicle_photo_upload_status(uuid,uuid,uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'app.retry_vehicle_photo_upload_verification(uuid,text,uuid,uuid,text,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'app.get_vehicle_photo_upload_status(uuid,uuid,uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'app.retry_vehicle_photo_upload_verification(uuid,text,uuid,uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'only authenticated browser actors receive status and retry execution'
);
select extensions.ok(
  pg_catalog.pg_get_function_result(
    'app.get_vehicle_photo_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%bucket%'
  and pg_catalog.pg_get_function_result(
    'app.get_vehicle_photo_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%object%'
  and pg_catalog.pg_get_function_result(
    'app.get_vehicle_photo_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%checksum%'
  and pg_catalog.pg_get_function_result(
    'app.get_vehicle_photo_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%detail%'
  and pg_catalog.pg_get_function_result(
    'app.get_vehicle_photo_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%receipt%',
  'status shape excludes storage coordinates, checksums, receipts, and details'
);
select extensions.ok(
  (select
     -- Exactly three row locks, with the first one on the source job, proves
     -- the owner probe is unlocked and the new-command path follows the same
     -- job -> media -> upload order as terminal workers.
     (
       pg_catalog.char_length(definition)
       - pg_catalog.char_length(
           pg_catalog.replace(definition, ' for update;', '')
         )
     ) / pg_catalog.char_length(' for update;') = 3
     and pg_catalog.strpos(
       definition,
       'select job.* into source_job from public.jobs job'
     ) > 0
     and pg_catalog.strpos(definition, ' for update;') > pg_catalog.strpos(
       definition,
       'select job.* into source_job from public.jobs job'
     )
     and pg_catalog.strpos(
       definition,
       'select asset.* into target_media from public.media_assets asset'
     ) > pg_catalog.strpos(definition, ' for update;')
     and pg_catalog.strpos(
       definition,
       'select locked_upload.* into target_upload from public.media_upload_sessions locked_upload'
     ) > pg_catalog.strpos(
       definition,
       'select asset.* into target_media from public.media_assets asset'
     )
   from (
     select pg_catalog.lower(
       pg_catalog.regexp_replace(
         pg_catalog.pg_get_functiondef(
           'app.retry_vehicle_photo_upload_verification(uuid,text,uuid,uuid,text,text,uuid)'::pg_catalog.regprocedure
         ),
         '[[:space:]]+', ' ', 'g'
       )
     ) as definition
   ) normalized),
  'manual retry uses the worker-compatible job-media-upload row-lock order'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.vehicle_retry_inventory
select result.*
from app.create_inventory_unit(
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'vehicle-retry-inventory-024', '1HGCM82633A900024', 2026,
  'Synthetic', 'Vehicle retry fixture', date '2026-07-16', 10, 'km',
  'CAD', 3200000, 'Synthetic vehicle retry test inventory',
  'request-vehicle-retry-inventory-024',
  'c4000000-0000-4000-8000-000000000001'
) result;

insert into pg_temp.vehicle_retry_uploads
select result.*, 'actor-a'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'vehicle-retry-upload-actor-a',
  (select inventory_unit_id from pg_temp.vehicle_retry_inventory),
  'actor-a.jpg', 'image/jpeg', 1000, repeat('a', 64),
  'request-vehicle-retry-upload-a',
  'c4000000-0000-4000-8000-000000000002'
) result;
insert into pg_temp.vehicle_retry_statuses
select status_row.*, 'awaiting-upload'
from app.get_vehicle_photo_upload_status(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a')
) status_row;
select extensions.ok(
  exists (
    select 1 from pg_temp.vehicle_retry_statuses status_row
    where status_row.probe = 'awaiting-upload'
      and status_row.status = 'awaiting_upload'
      and not status_row.retryable and status_row.job_id is null
      and status_row.error_classification is null
      and status_row.error_code is null
  ),
  'unqueued owner status is safe, non-null, and not retryable'
);
insert into pg_temp.vehicle_retry_requests
select result.*, 'actor-a'
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'vehicle-retry-request-actor-a',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  'request-vehicle-retry-verify-a',
  'c4000000-0000-4000-8000-000000000003'
) result;

insert into pg_temp.vehicle_retry_uploads
select result.*, 'rejected'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'vehicle-retry-upload-rejected',
  (select inventory_unit_id from pg_temp.vehicle_retry_inventory),
  'rejected.png', 'image/png', 900, repeat('b', 64),
  'request-vehicle-retry-upload-rejected',
  'c4000000-0000-4000-8000-000000000004'
) result;
insert into pg_temp.vehicle_retry_requests
select result.*, 'rejected'
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'vehicle-retry-request-rejected',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'rejected'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'rejected'),
  'request-vehicle-retry-verify-rejected',
  'c4000000-0000-4000-8000-000000000005'
) result;
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
insert into pg_temp.vehicle_retry_uploads
select result.*, 'actor-b'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'vehicle-retry-upload-actor-b',
  (select inventory_unit_id from pg_temp.vehicle_retry_inventory),
  'actor-b.webp', 'image/webp', 800, repeat('c', 64),
  'request-vehicle-retry-upload-b',
  'c4000000-0000-4000-8000-000000000006'
) result;
insert into pg_temp.vehicle_retry_requests
select result.*, 'actor-b'
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'vehicle-retry-request-actor-b',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-b'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-b'),
  'request-vehicle-retry-verify-b',
  'c4000000-0000-4000-8000-000000000007'
) result;
reset role;

select extensions.is(
  (select pg_catalog.count(*) from pg_temp.vehicle_retry_uploads),
  3::bigint,
  'two equally permitted owners create three exact vehicle upload intents'
);

set local role service_role;
insert into pg_temp.vehicle_retry_claims
select claim.*, request.probe
from app.claim_jobs(
  'vehicle-retry.fixture-024', 3, 300,
  array['media.verify_vehicle_photo_upload']
) claim
join pg_temp.vehicle_retry_requests request on request.job_id = claim.job_id;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.vehicle_retry_claims),
  3::bigint,
  'each exact verification receives one bounded worker lease'
);

insert into pg_temp.vehicle_retry_rejections
select rejected.*, 'rejected'
from app.reject_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'rejected'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'rejected'),
  (select job_id from pg_temp.vehicle_retry_claims where probe = 'rejected'),
  'vehicle-retry.fixture-024',
  (select lease_token from pg_temp.vehicle_retry_claims where probe = 'rejected'),
  (select attempt_number from pg_temp.vehicle_retry_claims where probe = 'rejected'),
  'media.malware_detected', 'validation',
  'job:vehicle-retry-rejected',
  'c4000000-0000-4000-8000-000000000008'
) rejected;

insert into pg_temp.vehicle_retry_failures
select failed.*, claim.probe
from pg_temp.vehicle_retry_claims claim
cross join lateral app.fail_job(
  claim.job_id, 'vehicle-retry.fixture-024', claim.lease_token,
  case when claim.probe = 'rejected' then 'validation' else 'permanent' end,
  case
    when claim.probe = 'rejected' then 'media.malware_detected'
    else 'media.fixture_provider_failure'
  end,
  'Synthetic terminal vehicle verification failure.'
) failed;
select extensions.ok(
  (select pg_catalog.bool_and(
     failure.job_status = 'dead_letter' and failure.review_required
   )
   from pg_temp.vehicle_retry_failures failure
   where failure.probe in ('actor-a', 'actor-b')),
  'terminal verification failure becomes visible dead letter'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.vehicle_retry_rejections rejection
    join public.media_assets asset on asset.id = rejection.media_id
    where rejection.probe = 'rejected' and asset.status = 'failed'
      and rejection.media_status = 'failed' and not rejection.replayed
  ),
  'terminal verification rejection preserves a distinct failed media state'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.vehicle_retry_statuses
select status_row.*, 'dead-letter'
from app.get_vehicle_photo_upload_status(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a')
) status_row;
select extensions.ok(
  exists (
    select 1 from pg_temp.vehicle_retry_statuses status_row
    where status_row.probe = 'dead-letter'
      and status_row.status = 'dead_letter' and status_row.retryable
      and status_row.attempt_count = 1 and status_row.maximum_attempts = 6
      and status_row.error_classification = 'permanent'
      and status_row.error_code = 'media.fixture_provider_failure'
      and status_row.completed_at is null
  ),
  'owner sees bounded dead-letter status and explicit retry eligibility'
);

insert into pg_temp.vehicle_retry_statuses
select status_row.*, 'rejected'
from app.get_vehicle_photo_upload_status(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'rejected'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'rejected')
) status_row;
select extensions.ok(
  exists (
    select 1 from pg_temp.vehicle_retry_statuses status_row
    where status_row.probe = 'rejected' and status_row.status = 'rejected'
      and not status_row.retryable
      and status_row.error_code = 'media.verification_rejected'
  ),
  'terminally rejected bytes are visible but require a new upload'
);

select extensions.throws_ok(
  $$
    select * from app.get_vehicle_photo_upload_status(
      '20000000-0000-4000-8000-000000000002',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a')
    )
  $$,
  'P0002', 'vehicle upload intent was not found',
  'workspace substitution is indistinguishable from an absent upload'
);

insert into pg_temp.vehicle_retry_requests
select result.*, 'actor-a-original-replay'
from app.request_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'vehicle-retry-request-actor-a',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  'request-vehicle-retry-original-replay',
  'c4000000-0000-4000-8000-000000000018'
) result;
select extensions.ok(
  (select replay.job_id = original.job_id
     and replay.job_status = 'dead_letter' and replay.replayed
   from pg_temp.vehicle_retry_requests original
   join pg_temp.vehicle_retry_requests replay
     on replay.probe = 'actor-a-original-replay'
   where original.probe = 'actor-a'),
  'original completion receipt still replays after verification exhaustion'
);
select extensions.throws_ok(
  $$
    select * from app.request_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001',
      'vehicle-retry-unreasoned-bypass',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      'request-vehicle-retry-unreasoned-bypass',
      'c4000000-0000-4000-8000-000000000019'
    )
  $$,
  '55000',
  'dead-letter vehicle verification requires the reasoned retry command',
  'a fresh completion key cannot bypass the reasoned retry boundary'
);
select extensions.throws_ok(
  $$
    select * from app.retry_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'vehicle-retry-empty-reason',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      '   ', 'request-vehicle-retry-empty-reason',
      'c4000000-0000-4000-8000-000000000009'
    )
  $$,
  '22023',
  'vehicle verification retry requires a safe reason and correlation ID',
  'manual retry always requires an explicit bounded reason'
);

insert into pg_temp.vehicle_retries
select result.*, 'actor-a'
from app.retry_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'vehicle-retry-shared-key',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  'Operator confirmed private storage recovery.',
  'request-vehicle-retry-command-a',
  'c4000000-0000-4000-8000-000000000010'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.vehicle_retries retry
    where retry.probe = 'actor-a' and retry.job_status = 'queued'
      and not retry.replayed and retry.source_job_id <> retry.job_id
      and retry.aggregate_version > 1 and retry.audit_event_id is not null
      and retry.outbox_event_id is not null
  ),
  'owner queues one fresh audited job from the exact dead letter'
);
reset role;
select extensions.ok(
  exists (
    select 1
    from pg_temp.vehicle_retries retry
    join public.jobs replay_job on replay_job.id = retry.job_id
    join public.jobs source_job on source_job.id = retry.source_job_id
    join public.outbox_events event on event.id = retry.outbox_event_id
    where retry.probe = 'actor-a'
      and replay_job.replay_of_job_id = source_job.id
      and replay_job.causation_id = source_job.outbox_event_id
      and event.causation_id = source_job.outbox_event_id
      and replay_job.payload = source_job.payload
      and replay_job.payload_schema_version = source_job.payload_schema_version
      and replay_job.priority = source_job.priority
      and replay_job.max_attempts = source_job.max_attempts
      and replay_job.backoff_base_seconds = source_job.backoff_base_seconds
      and replay_job.backoff_max_seconds = source_job.backoff_max_seconds
  ),
  'fresh job copies bounded policy and exact payload with causal lineage'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.vehicle_retries retry
    join public.media_upload_sessions upload on upload.id = retry.upload_session_id
    join public.media_assets asset on asset.id = retry.media_id
    where retry.probe = 'actor-a'
      and upload.verification_job_id = retry.job_id
      and upload.verification_outbox_event_id = retry.outbox_event_id
      and upload.verification_audit_event_id = retry.audit_event_id
      and asset.version = retry.aggregate_version
  ),
  'upload fence and media aggregate version advance atomically'
);
select extensions.ok(
  exists (
    select 1 from public.media_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'media.retry_upload_verify'
      and receipt.idempotency_key = 'vehicle-retry-shared-key'
      and receipt.result ->> 'job_id' = (
        select retry.job_id::text from pg_temp.vehicle_retries retry
        where retry.probe = 'actor-a'
      )
  ),
  'actor-aware receipt preserves the raw external command key'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.vehicle_retries retry
    join public.audit_events audit on audit.id = retry.audit_event_id
    join public.outbox_events event on event.id = retry.outbox_event_id
    where retry.probe = 'actor-a'
      and audit.action = 'media.upload_verification_retry_requested'
      and audit.reason = 'Operator confirmed private storage recovery.'
      and audit.actor_user_id = '31000000-0000-4000-8000-000000000001'
      and audit.metadata ->> 'source_job_id' = retry.source_job_id::text
      and event.event_name = 'media.upload_verification_retry_requested'
      and event.actor_user_id = audit.actor_user_id
  ),
  'retry records the explicit reason and actor in audit and outbox'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.vehicle_retry_statuses
select status_row.*, 'queued-after-retry'
from app.get_vehicle_photo_upload_status(
  '10000000-0000-4000-8000-000000000001',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a')
) status_row;
select extensions.ok(
  exists (
    select 1 from pg_temp.vehicle_retry_statuses status_row
    where status_row.probe = 'queued-after-retry'
      and status_row.status = 'queued' and not status_row.retryable
      and status_row.error_classification is null
      and status_row.error_code is null
  ),
  'fresh queued state clears stale failure projection'
);
select extensions.throws_ok(
  $$
    select * from app.retry_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'vehicle-retry-second-key',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      'A second command cannot bypass the current queued job.',
      'request-vehicle-retry-second-key',
      'c4000000-0000-4000-8000-000000000011'
    )
  $$,
  '55000',
  'only a dead-letter vehicle verification job can be manually retried',
  'a new command cannot retry while the fresh job is active'
);
reset role;

-- Simulate a later terminal worker transition after the command response was
-- lost. Exact command replay and changed-fingerprint conflict must still be
-- deterministic before current-state eligibility is evaluated.
update public.media_assets asset
set status = 'failed', updated_at = pg_catalog.statement_timestamp()
where asset.id = (
  select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.vehicle_retries
select result.*, 'actor-a-terminal-replay'
from app.retry_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'vehicle-retry-shared-key',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
  'Operator confirmed private storage recovery.',
  'request-vehicle-retry-command-a-replay',
  'c4000000-0000-4000-8000-000000000012'
) result;
select extensions.ok(
  (select original.job_id = replay.job_id
     and original.audit_event_id = replay.audit_event_id
     and replay.replayed
   from pg_temp.vehicle_retries original
   join pg_temp.vehicle_retries replay
     on replay.probe = 'actor-a-terminal-replay'
   where original.probe = 'actor-a'),
  'exact command replay survives a later terminal aggregate state'
);
select extensions.throws_ok(
  $$
    select * from app.retry_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'vehicle-retry-shared-key',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      'A changed reason conflicts even after terminal state.',
      'request-vehicle-retry-command-a-conflict',
      'c4000000-0000-4000-8000-000000000013'
    )
  $$,
  '23505', 'vehicle verification retry replay conflicts',
  'same key with a changed reason conflicts deterministically after terminal state'
);
select extensions.throws_ok(
  $$
    select * from app.retry_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'vehicle-retry-after-terminal',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      'A terminal upload cannot be revived with a fresh command.',
      'request-vehicle-retry-after-terminal',
      'c4000000-0000-4000-8000-000000000014'
    )
  $$,
  '55000', 'only an active vehicle upload verification can be retried',
  'fresh retry cannot revive a terminal media aggregate'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.throws_ok(
  $$
    select * from app.get_vehicle_photo_upload_status(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a')
    )
  $$,
  'P0002', 'vehicle upload intent was not found',
  'equally permitted actor receives not-found for another owner upload'
);
select extensions.throws_ok(
  $$
    select * from app.get_vehicle_photo_upload_status(
      '10000000-0000-4000-8000-000000000001',
      'c4ff0000-0000-4000-8000-000000000024',
      'c4ff0000-0000-4000-8000-000000000025'
    )
  $$,
  'P0002', 'vehicle upload intent was not found',
  'absent and other-owner status identifiers are indistinguishable'
);
select extensions.throws_ok(
  $$
    select * from app.retry_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'cross-owner-retry-key',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      'Cross-owner retry cannot inspect another owner receipt.',
      'request-cross-owner-retry',
      'c4000000-0000-4000-8000-000000000015'
    )
  $$,
  'P0002', 'vehicle upload intent was not found',
  'equally permitted actor cannot retry another owner upload'
);

insert into pg_temp.vehicle_retries
select result.*, 'actor-b'
from app.retry_vehicle_photo_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'vehicle-retry-shared-key',
  (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-b'),
  (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-b'),
  'Second owner confirmed private storage recovery.',
  'request-vehicle-retry-command-b',
  'c4000000-0000-4000-8000-000000000016'
) result;
reset role;
select extensions.ok(
  exists (
    select 1 from pg_temp.vehicle_retries retry
    where retry.probe = 'actor-b' and retry.job_status = 'queued'
      and not retry.replayed
  )
  and (
    select pg_catalog.count(*)
    from public.media_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'media.retry_upload_verify'
      and receipt.idempotency_key = 'vehicle-retry-shared-key'
      and receipt.actor_user_id in (
        '31000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000002'
      )
  ) = 2,
  'different owners share a raw key only through separate actor namespaces'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from app.retry_vehicle_photo_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'rejected-upload-retry-key',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'rejected'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'rejected'),
      'Rejected bytes require a new upload.',
      'request-rejected-upload-retry',
      'c4000000-0000-4000-8000-000000000017'
    )
  $$,
  '55000', 'only an active vehicle upload verification can be retried',
  'terminal rejection cannot be revived by verification retry'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from app.get_vehicle_photo_upload_status(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a'),
      (select upload_session_id from pg_temp.vehicle_retry_uploads where probe = 'actor-a')
    )
  $$,
  'P0002', 'vehicle upload intent was not found',
  'unaffiliated actor receives not-found for an exact upload identifier'
);

reset role;
select extensions.ok(
  not exists (
    select 1 from public.jobs job
    where job.job_type = 'media.verify_vehicle_photo_upload'
      and app.job_payload_contains_forbidden_key(job.payload)
  ),
  'original and replay verification jobs retain reference-only payloads'
);

select * from extensions.finish();
rollback;
