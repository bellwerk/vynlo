-- M2-MEDIA-AC-026, VYN-MEDIA-001, VYN-JOB-001, VYN-TEN-001,
-- VYN-SEC-001, VYN-AUD-001, T-MED-003, T-JOB-001, T-TEN-001,
-- T-RBAC-001, T-AUD-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(39);

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

-- Actor B receives the same workspace administrator role so ownership and raw
-- command-key namespace tests do not accidentally test a permission mismatch.
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '61000000-0000-4000-8000-000000000023',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '51000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.document_types (
  id, workspace_id, key, version, display_name, field_schema,
  production_enabled, status, labels, field_schema_checksum, checksum
) values (
  'f5100000-0000-4000-8000-000000000023',
  '10000000-0000-4000-8000-000000000001',
  'legal_retry_fixture', 1, 'Legal retry fixture', '{}', false, 'active',
  '{"en":"Legal retry fixture","fr":"Nouvel essai legal fictif"}', repeat('d', 64), repeat('e', 64)
);
insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_checksum, renderer_version, field_schema,
  production_approved, watermark, status, source_bundle_checksum,
  field_schema_checksum
) values (
  'f5200000-0000-4000-8000-000000000023',
  '10000000-0000-4000-8000-000000000001',
  'f5100000-0000-4000-8000-000000000023', 1, 'en-CA',
  'synthetic_non_production', '<html><body>fixture</body></html>',
  repeat('1', 64), 'synthetic-html-v1', '{}', false,
  'DRAFT / NON-PRODUCTION', 'active', repeat('f', 64), repeat('d', 64)
);
insert into public.deals (
  id, workspace_id, deal_type_key, status, currency_code,
  owner_membership_id, idempotency_key, command_fingerprint, created_by
) values (
  'f5300000-0000-4000-8000-000000000023',
  '10000000-0000-4000-8000-000000000001',
  'retail.cash', 'draft', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'legal-retry-fixture-deal', repeat('2', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.numbering_definitions (
  id, workspace_id, key, labels
) values (
  'f5500000-0000-4000-8000-000000000023',
  '10000000-0000-4000-8000-000000000001',
  'legal_retry_fixture',
  '{"en":"Legal retry fixture","fr":"Fixture de nouvelle tentative legale"}'
);
insert into public.numbering_definition_versions (
  id, workspace_id, numbering_definition_id, version, semantic_version,
  status, scope_type, prefix, suffix, numeric_width, starting_value,
  increment_by, reset_policy, timezone_name, format_pattern,
  import_policy, reuse_policy, allocation_event, checksum, created_by
) values (
  'f5510000-0000-4000-8000-000000000023',
  '10000000-0000-4000-8000-000000000001',
  'f5500000-0000-4000-8000-000000000023',
  1, '1.0.0', 'draft', 'workspace', 'LR-', '', 6, 1, 1,
  'never', 'UTC', '{{prefix}}{{sequence}}{{suffix}}',
  'authorized_reservation', 'never', 'official_document_created',
  repeat('5', 64), '31000000-0000-4000-8000-000000000001'
);
insert into public.number_allocations (
  id, workspace_id, numbering_version_id, scope_key, period_key,
  sequence_value, formatted_value, entity_type, entity_id,
  idempotency_key, allocation_reason, allocated_by
) values (
  'f5520000-0000-4000-8000-000000000023',
  '10000000-0000-4000-8000-000000000001',
  'f5510000-0000-4000-8000-000000000023',
  'workspace', 'never', 1, 'LR-000001', 'document',
  'f5400000-0000-4000-8000-000000000023',
  'legal-retry-number-allocation', 'Legal retry signed-file fixture',
  '31000000-0000-4000-8000-000000000001'
);
insert into public.documents (
  id, workspace_id, document_type_id, template_version_id, deal_id,
  mode, official_number, status, locale, watermark,
  render_input_snapshot, render_input_checksum, generated_checksum,
  idempotency_key, command_fingerprint, created_by, number_allocation_id,
  numbering_version_id, renderer_version, version_snapshot,
  version_snapshot_checksum
) values (
  'f5400000-0000-4000-8000-000000000023',
  '10000000-0000-4000-8000-000000000001',
  'f5100000-0000-4000-8000-000000000023',
  'f5200000-0000-4000-8000-000000000023',
  'f5300000-0000-4000-8000-000000000023',
  'official', 'LR-000001', 'generated', 'en-CA', null,
  '{}', repeat('3', 64), repeat('6', 64),
  'legal-retry-fixture-document', repeat('4', 64),
  '31000000-0000-4000-8000-000000000001',
  'f5520000-0000-4000-8000-000000000023',
  'f5510000-0000-4000-8000-000000000023',
  'fixture-renderer-v1', '{}', repeat('7', 64)
);

create temporary table pg_temp.legal_retry_intents (
  upload_session_id uuid, document_id uuid, media_kind text,
  upload_bucket text, upload_object_key text, expires_at timestamptz,
  replayed boolean, audit_event_id uuid, probe text
);
create temporary table pg_temp.legal_retry_requests (
  upload_session_id uuid, document_id uuid, job_id uuid, job_status text,
  replayed boolean, audit_event_id uuid, outbox_event_id uuid, probe text
);
create temporary table pg_temp.legal_retry_claims (
  job_id uuid, workspace_id uuid, outbox_event_id uuid, job_type text,
  entity_type text, entity_id uuid, payload_schema_version integer,
  payload jsonb, idempotency_key text, attempt_number integer,
  max_attempts integer, lease_token uuid, lease_expires_at timestamptz,
  correlation_id uuid, causation_id uuid, probe text
);
create temporary table pg_temp.legal_retry_failures (
  job_status text, retry_at timestamptz, review_required boolean, probe text
);
create temporary table pg_temp.legal_retry_statuses (
  upload_session_id uuid, document_id uuid, media_kind text, status text,
  job_id uuid, attempt_count integer, maximum_attempts integer,
  retry_at timestamptz, retryable boolean, error_classification text,
  error_code text, completed_at timestamptz, probe text
);
create temporary table pg_temp.legal_retries (
  upload_session_id uuid, document_id uuid, source_job_id uuid, job_id uuid,
  job_status text, replayed boolean, audit_event_id uuid,
  outbox_event_id uuid, probe text
);
create temporary table pg_temp.legal_retry_rejections (
  upload_session_id uuid, upload_status text, replayed boolean,
  audit_event_id uuid, outbox_event_id uuid, probe text
);
create temporary table pg_temp.legal_retry_cleanup_schedules (
  cleanup_id uuid, upload_session_id uuid, cleanup_reason text,
  job_id uuid, outbox_event_id uuid, probe text
);
create temporary table pg_temp.legal_retry_cleanup_completions (
  cleanup_id uuid, cleanup_status text, replayed boolean, probe text
);
grant all on pg_temp.legal_retry_intents, pg_temp.legal_retry_requests,
  pg_temp.legal_retry_claims, pg_temp.legal_retry_failures,
  pg_temp.legal_retry_statuses, pg_temp.legal_retries,
  pg_temp.legal_retry_rejections, pg_temp.legal_retry_cleanup_schedules,
  pg_temp.legal_retry_cleanup_completions
to authenticated, service_role;

select extensions.has_function(
  'app', 'get_legal_original_upload_status', array['uuid', 'uuid', 'uuid'],
  'browser-safe legal original status projection exists'
);
select extensions.has_function(
  'app', 'retry_legal_original_upload_verification',
  array['uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'uuid'],
  'reasoned dead-letter retry command exists'
);
select extensions.ok(
  (select function_row.prosecdef and function_row.provolatile = 's'
     and exists (
       select 1
       from pg_catalog.unnest(
         coalesce(function_row.proconfig, array[]::text[])
       ) setting
       where setting in ('search_path=', 'search_path=""')
     )
   from pg_catalog.pg_proc function_row
   where function_row.oid =
     'app.get_legal_original_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure),
  'status projection is stable SECURITY DEFINER with an empty search path'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.get_legal_original_upload_status(uuid,uuid,uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'app.retry_legal_original_upload_verification(uuid,text,uuid,uuid,text,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'app.get_legal_original_upload_status(uuid,uuid,uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'app.retry_legal_original_upload_verification(uuid,text,uuid,uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'only authenticated browser actors receive the status and retry RPCs'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.legal_original_upload_sessions', 'SELECT'
  )
  and not exists (
    select 1 from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'legal_original_upload_sessions'
      and 'authenticated' = any(policy.roles)
      and policy.cmd in ('SELECT', 'ALL')
  ),
  'authenticated actors retain no direct upload-session read path'
);
select extensions.ok(
  pg_catalog.pg_get_function_result(
    'app.get_legal_original_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%bucket%'
  and pg_catalog.pg_get_function_result(
    'app.get_legal_original_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%object%'
  and pg_catalog.pg_get_function_result(
    'app.get_legal_original_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%checksum%'
  and pg_catalog.pg_get_function_result(
    'app.get_legal_original_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%detail%'
  and pg_catalog.pg_get_function_result(
    'app.get_legal_original_upload_status(uuid,uuid,uuid)'::pg_catalog.regprocedure
  ) not ilike '%receipt%',
  'status return shape excludes provider coordinates and verification evidence'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legal_retry_intents
select result.*, 'actor-a' from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001', 'legal-retry-intent-actor-a',
  'f5400000-0000-4000-8000-000000000023', 'legal_document',
  'registration.pdf', 'application/pdf', 1000, repeat('a', 64),
  'request-legal-retry-a', 'f6000000-0000-4000-8000-000000000001'
) result;
insert into pg_temp.legal_retry_requests
select result.*, 'actor-a' from app.request_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'legal-retry-request-actor-a',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
  'request-legal-retry-verify-a',
  'f6000000-0000-4000-8000-000000000002'
) result;
insert into pg_temp.legal_retry_intents
select result.*, 'signed' from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001', 'legal-retry-intent-signed',
  'f5400000-0000-4000-8000-000000000023', 'signed_document',
  'signed.pdf', 'application/pdf', 900, repeat('b', 64),
  'request-legal-retry-signed',
  'f6000000-0000-4000-8000-000000000003'
) result;
insert into pg_temp.legal_retry_requests
select result.*, 'signed' from app.request_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'legal-retry-request-signed',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'signed'),
  'request-legal-retry-verify-signed',
  'f6000000-0000-4000-8000-000000000004'
) result;
insert into pg_temp.legal_retry_intents
select result.*, 'rejected' from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001', 'legal-retry-intent-rejected',
  'f5400000-0000-4000-8000-000000000023', 'legal_document',
  'rejected.pdf', 'application/pdf', 800, repeat('c', 64),
  'request-legal-retry-rejected',
  'f6000000-0000-4000-8000-000000000005'
) result;
insert into pg_temp.legal_retry_requests
select result.*, 'rejected' from app.request_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'legal-retry-request-rejected',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'rejected'),
  'request-legal-retry-verify-rejected',
  'f6000000-0000-4000-8000-000000000006'
) result;
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
insert into pg_temp.legal_retry_intents
select result.*, 'actor-b' from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001', 'legal-retry-intent-actor-b',
  'f5400000-0000-4000-8000-000000000023', 'legal_document',
  'purchase.pdf', 'application/pdf', 700, repeat('d', 64),
  'request-legal-retry-b', 'f6000000-0000-4000-8000-000000000007'
) result;
insert into pg_temp.legal_retry_requests
select result.*, 'actor-b' from app.request_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'legal-retry-request-actor-b',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-b'),
  'request-legal-retry-verify-b',
  'f6000000-0000-4000-8000-000000000008'
) result;
set local role service_role;
insert into pg_temp.legal_retry_claims
select claim.*, request.probe
from app.claim_jobs(
  'legal-retry.fixture-01', 4, 300, array['media.verify_legal_original']
) claim
join pg_temp.legal_retry_requests request on request.job_id = claim.job_id;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.legal_retry_claims),
  4::bigint,
  'all retry fixtures receive one bounded active verification lease'
);
insert into pg_temp.legal_retry_failures
select failed.*, claim.probe
from pg_temp.legal_retry_claims claim
cross join lateral app.fail_job(
  claim.job_id, 'legal-retry.fixture-01', claim.lease_token,
  'permanent', 'media.fixture_provider_failure',
  'Synthetic verification reached a terminal provider failure.'
) failed;
select extensions.ok(
  (select pg_catalog.bool_and(
    failure.job_status = 'dead_letter' and failure.review_required
  ) from pg_temp.legal_retry_failures failure),
  'terminal failure makes every source verification job visible as dead letter'
);
reset role;

update public.legal_original_upload_sessions upload
set status = 'rejected',
    rejection_code = 'provider detail must not project',
    completed_at = pg_catalog.statement_timestamp()
where upload.id = (
  select intent.upload_session_id
  from pg_temp.legal_retry_intents intent
  where intent.probe = 'rejected'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$ select * from public.legal_original_upload_sessions $$,
  '42501', 'permission denied for table legal_original_upload_sessions',
  'browser actors cannot replace the status RPC with direct SELECT'
);
insert into pg_temp.legal_retry_statuses
select status_row.*, 'dead-letter'
from app.get_legal_original_upload_status(
  '10000000-0000-4000-8000-000000000001',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a')
) status_row;
select extensions.ok(
  exists (
    select 1 from pg_temp.legal_retry_statuses status_row
    where status_row.probe = 'dead-letter'
      and status_row.status = 'dead_letter'
      and status_row.retryable
      and status_row.attempt_count = 1
      and status_row.maximum_attempts = 6
      and status_row.error_classification = 'permanent'
      and status_row.error_code = 'media.fixture_provider_failure'
      and status_row.completed_at is null
  ),
  'owner sees only bounded safe dead-letter status and retry eligibility'
);
select extensions.throws_ok(
  $$
    select * from app.get_legal_original_upload_status(
      '20000000-0000-4000-8000-000000000002',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a')
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'a caller cannot move the status lookup to another workspace'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
select extensions.throws_ok(
  $$
    select * from app.get_legal_original_upload_status(
      '10000000-0000-4000-8000-000000000001',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'signed')
    )
  $$,
  '42501', 'active workspace membership and permission are required',
  'AAL1 administrator is denied before signed-original status'
);
select extensions.throws_ok(
  $$
    select * from app.retry_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'signed-retry-needs-stepup',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'signed'),
      'Operator confirmed a safe signed-original retry.',
      'request-signed-retry-no-stepup',
      'f6000000-0000-4000-8000-000000000009'
    )
  $$,
  '42501', 'active workspace membership and permission are required',
  'AAL1 administrator is denied before signed-original retry'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
insert into pg_temp.legal_retries
select result.*, 'actor-a'
from app.retry_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'a1:legal-retry-shared-key',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
  'Operator confirmed the private source is still available.',
  'request-legal-retry-command-a',
  'f6000000-0000-4000-8000-000000000010'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.legal_retries retry
    where retry.probe = 'actor-a' and retry.job_status = 'queued'
      and not retry.replayed and retry.source_job_id <> retry.job_id
      and retry.audit_event_id is not null and retry.outbox_event_id is not null
  ),
  'owner queues one fresh audited verification job from dead letter'
);
reset role;
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_retries retry
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
  'fresh job preserves payload and bounded scheduling policy with causation and replay lineage'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_retries retry
    join public.legal_original_upload_sessions upload
      on upload.id = retry.upload_session_id
    where retry.probe = 'actor-a'
      and upload.status = 'verification_requested'
      and upload.verification_job_id = retry.job_id
      and upload.verification_outbox_event_id = retry.outbox_event_id
      and upload.verification_audit_event_id = retry.audit_event_id
  ),
  'upload fence advances atomically to the fresh verification lineage'
);
select extensions.ok(
  exists (
    select 1
    from public.media_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'media.retry_legal_verify'
      and receipt.idempotency_key = 'a1:legal-retry-shared-key'
      and receipt.result ->> 'job_id' = (
        select retry.job_id::text from pg_temp.legal_retries retry
        where retry.probe = 'actor-a'
      )
  ),
  'actor-aware media receipt stores the raw external command key unchanged'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_retries retry
    join public.audit_events audit on audit.id = retry.audit_event_id
    join public.outbox_events event on event.id = retry.outbox_event_id
    where retry.probe = 'actor-a'
      and audit.action = 'media.legal_original_verification_retry_requested'
      and audit.reason = 'Operator confirmed the private source is still available.'
      and audit.actor_user_id = '31000000-0000-4000-8000-000000000001'
      and audit.metadata ->> 'source_job_id' = retry.source_job_id::text
      and event.event_name = 'media.legal_original_verification_retry_requested'
      and event.actor_user_id = audit.actor_user_id
  ),
  'manual retry records the explicit reason and actor in audit and outbox'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legal_retries
select result.*, 'actor-a-replay'
from app.retry_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'a1:legal-retry-shared-key',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
  'Operator confirmed the private source is still available.',
  'request-legal-retry-command-a-replay',
  'f6000000-0000-4000-8000-000000000011'
) result;
select extensions.ok(
  (select original.job_id = replay.job_id
     and original.audit_event_id = replay.audit_event_id
     and replay.replayed
   from pg_temp.legal_retries original
   join pg_temp.legal_retries replay on replay.probe = 'actor-a-replay'
   where original.probe = 'actor-a'),
  'same actor and raw command key replay the original retry receipt'
);
select extensions.throws_ok(
  $$
    select * from app.retry_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'a1:legal-retry-shared-key',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
      'A changed reason must conflict with the original command.',
      'request-legal-retry-command-a-conflict',
      'f6000000-0000-4000-8000-000000000012'
    )
  $$,
  '23505', 'legal verification retry replay conflicts',
  'same actor cannot reuse a retry key for a changed reason'
);
select extensions.throws_ok(
  $$
    select * from app.retry_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'legal-retry-stale-current-job',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
      'A second command cannot bypass the current queued job.',
      'request-legal-retry-stale',
      'f6000000-0000-4000-8000-000000000013'
    )
  $$,
  '55000', 'only a dead-letter legal verification job can be manually retried',
  'a stale command cannot retry while a fresh job is active'
);
insert into pg_temp.legal_retry_statuses
select status_row.*, 'queued-after-retry'
from app.get_legal_original_upload_status(
  '10000000-0000-4000-8000-000000000001',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a')
) status_row;
select extensions.ok(
  exists (
    select 1 from pg_temp.legal_retry_statuses status_row
    where status_row.probe = 'queued-after-retry'
      and status_row.status = 'queued' and not status_row.retryable
      and status_row.error_classification is null
      and status_row.error_code is null
  ),
  'status projection clears stale failure fields after retry is queued'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.throws_ok(
  $$
    select * from app.get_legal_original_upload_status(
      '10000000-0000-4000-8000-000000000001',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a')
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'equally permitted actor receives not-found for another actor upload status'
);
select extensions.throws_ok(
  $$
    select * from app.get_legal_original_upload_status(
      '10000000-0000-4000-8000-000000000001',
      'f5400000-0000-4000-8000-000000000023',
      'f5ff0000-0000-4000-8000-000000000023'
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'equally permitted actor receives the same result for an absent upload status'
);
select extensions.throws_ok(
  $$
    select * from app.retry_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'a1:legal-retry-shared-key',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
      'Cross-actor retry must not inspect another actor receipt.',
      'request-legal-retry-cross-actor',
      'f6000000-0000-4000-8000-000000000014'
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'equally permitted actor receives not-found when retrying another actor upload'
);
select extensions.throws_ok(
  $$
    select * from app.retry_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'actor-b-absent-retry-key',
      'f5400000-0000-4000-8000-000000000023',
      'f5ff0000-0000-4000-8000-000000000023',
      'An absent upload must be indistinguishable from another actor upload.',
      'request-legal-retry-actor-b-absent',
      'f6000000-0000-4000-8000-000000000018'
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'equally permitted actor receives the same retry result for an absent upload'
);
insert into pg_temp.legal_retries
select result.*, 'actor-b'
from app.retry_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'a1:legal-retry-shared-key',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-b'),
  'Operator confirmed the second private source is still available.',
  'request-legal-retry-command-b',
  'f6000000-0000-4000-8000-000000000015'
) result;
reset role;
select extensions.ok(
  exists (
    select 1 from pg_temp.legal_retries retry
    where retry.probe = 'actor-b' and retry.job_status = 'queued'
      and not retry.replayed
  )
  and (
    select pg_catalog.count(*)
    from public.media_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'media.retry_legal_verify'
      and receipt.idempotency_key = 'a1:legal-retry-shared-key'
      and receipt.actor_user_id in (
        '31000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000002'
      )
  ) = 2,
  'different owners may use the same raw retry key in separate actor namespaces'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from app.get_legal_original_upload_status(
      '10000000-0000-4000-8000-000000000001',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a')
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'unaffiliated actor receives not-found for an exact upload status identifier'
);
select extensions.throws_ok(
  $$
    select * from app.get_legal_original_upload_status(
      '10000000-0000-4000-8000-000000000001',
      'f5400000-0000-4000-8000-000000000023',
      'f5ff0000-0000-4000-8000-000000000023'
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'unaffiliated actor receives the same result for an absent upload status'
);
select extensions.throws_ok(
  $$
    select * from app.retry_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'unaffiliated-exact-retry-key',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
      'An unaffiliated actor cannot retry an exact upload identifier.',
      'request-legal-retry-unaffiliated-exact',
      'f6000000-0000-4000-8000-000000000019'
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'unaffiliated actor receives not-found when retrying an exact upload identifier'
);
select extensions.throws_ok(
  $$
    select * from app.retry_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'unaffiliated-absent-retry-key',
      'f5400000-0000-4000-8000-000000000023',
      'f5ff0000-0000-4000-8000-000000000023',
      'An absent upload must remain indistinguishable for an unaffiliated actor.',
      'request-legal-retry-unaffiliated-absent',
      'f6000000-0000-4000-8000-000000000020'
    )
  $$,
  'P0002', 'legal upload intent was not found',
  'unaffiliated actor receives the same retry result for an absent upload'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
insert into pg_temp.legal_retry_statuses
select status_row.*, 'rejected'
from app.get_legal_original_upload_status(
  '10000000-0000-4000-8000-000000000001',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'rejected')
) status_row;
select extensions.ok(
  exists (
    select 1 from pg_temp.legal_retry_statuses status_row
    where status_row.probe = 'rejected' and status_row.status = 'rejected'
      and not status_row.retryable
      and status_row.error_code = 'media.verification_rejected'
  ),
  'terminally rejected upload is visible but never retryable'
);
select extensions.throws_ok(
  $$
    select * from app.retry_legal_original_upload_verification(
      '10000000-0000-4000-8000-000000000001', 'legal-retry-rejected-stale',
      'f5400000-0000-4000-8000-000000000023',
      (select upload_session_id from pg_temp.legal_retry_intents where probe = 'rejected'),
      'Rejected bytes require a new upload instead of retry.',
      'request-legal-retry-rejected-stale',
      'f6000000-0000-4000-8000-000000000016'
    )
  $$,
  '55000', 'only an active legal verification can be retried',
  'terminal rejection cannot be revived by manual retry'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
insert into pg_temp.legal_retries
select result.*, 'signed'
from app.retry_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'signed-retry-with-stepup',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'signed'),
  'Operator reauthenticated and confirmed the signed source.',
  'request-legal-retry-signed-stepup',
  'f6000000-0000-4000-8000-000000000017'
) result;
select extensions.ok(
  exists (
    select 1 from pg_temp.legal_retries retry
    join public.audit_events audit on audit.id = retry.audit_event_id
    where retry.probe = 'signed' and retry.job_status = 'queued'
      and audit.auth_assurance = 'step_up'
  ),
  'recent strong authentication permits and labels signed-original retry'
);

reset role;
set local role service_role;
do $$
begin
  perform app.cancel_job(
    (select retry.job_id from pg_temp.legal_retries retry where retry.probe = 'signed'),
    '31000000-0000-4000-8000-000000000001',
    'Synthetic operator cancellation after the verification retry was queued.',
    'f6000000-0000-4000-8000-000000000021'
  );
end;
$$;
reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legal_retry_statuses
select status_row.*, 'cancelled'
from app.get_legal_original_upload_status(
  '10000000-0000-4000-8000-000000000001',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'signed')
) status_row;
select extensions.ok(
  exists (
    select 1 from pg_temp.legal_retry_statuses status_row
    where status_row.probe = 'cancelled'
      and status_row.status = 'rejected'
      and not status_row.retryable
      and status_row.error_code = 'media.verification_cancelled'
  ),
  'generic job cancellation projects as a safe parseable terminal status'
);

reset role;
set local role service_role;
insert into pg_temp.legal_retry_claims
select claim.*, 'actor-a-retry-terminal'
from app.claim_jobs(
  'legal-retry.terminal-01', 10, 300,
  array['media.verify_legal_original']
) claim
join pg_temp.legal_retries retry on retry.job_id = claim.job_id
where retry.probe = 'actor-a';
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_retry_claims claim
    join pg_temp.legal_retries retry on retry.job_id = claim.job_id
    where claim.probe = 'actor-a-retry-terminal'
      and retry.probe = 'actor-a'
  ),
  'the retried verification receives a fresh bounded worker lease'
);

insert into pg_temp.legal_retry_rejections
select result.*, 'actor-a-retry-terminal'
from app.reject_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'f5400000-0000-4000-8000-000000000023',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
  (select job_id from pg_temp.legal_retry_claims where probe = 'actor-a-retry-terminal'),
  'legal-retry.terminal-01',
  (select lease_token from pg_temp.legal_retry_claims where probe = 'actor-a-retry-terminal'),
  (select attempt_number from pg_temp.legal_retry_claims where probe = 'actor-a-retry-terminal'),
  'media.retry_terminal_rejected',
  'validation',
  'job:legal-retry-terminal-rejection',
  (select correlation_id from pg_temp.legal_retry_claims where probe = 'actor-a-retry-terminal')
) result;
reset role;
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_retry_rejections rejection
    join public.legal_original_upload_sessions upload
      on upload.id = rejection.upload_session_id
    where rejection.probe = 'actor-a-retry-terminal'
      and rejection.upload_status = 'rejected'
      and not rejection.replayed
      and upload.rejection_code = 'media.retry_terminal_rejected'
  ),
  'a retried verification can terminate without colliding with retry event versioning'
);

set local role service_role;
insert into pg_temp.legal_retry_cleanup_schedules
select scheduled.*, 'after-retry-terminal'
from app.enqueue_due_legal_original_quarantine_cleanup(
  500,
  'f6000000-0000-4000-8000-000000000022'
) scheduled;
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_retry_cleanup_schedules schedule
    where schedule.probe = 'after-retry-terminal'
      and schedule.upload_session_id = (
        select upload_session_id
        from pg_temp.legal_retry_intents
        where probe = 'actor-a'
      )
      and schedule.cleanup_reason = 'terminal_rejection'
  ),
  'terminal bytes from a retried verification enqueue durable quarantine cleanup'
);

insert into pg_temp.legal_retry_claims
select claim.*, 'cleanup-after-retry-terminal'
from app.claim_jobs(
  'legal-retry.cleanup-01', 100, 300,
  array['media.delete_legal_original_quarantine']
) claim
join pg_temp.legal_retry_cleanup_schedules schedule
  on schedule.job_id = claim.job_id
where schedule.upload_session_id = (
  select upload_session_id
  from pg_temp.legal_retry_intents
  where probe = 'actor-a'
);
insert into pg_temp.legal_retry_cleanup_completions
select result.*, 'after-retry-terminal'
from app.complete_legal_original_quarantine_cleanup(
  '10000000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_retry_intents where probe = 'actor-a'),
  (select job_id from pg_temp.legal_retry_claims where probe = 'cleanup-after-retry-terminal'),
  'legal-retry.cleanup-01',
  (select lease_token from pg_temp.legal_retry_claims where probe = 'cleanup-after-retry-terminal'),
  (select attempt_number from pg_temp.legal_retry_claims where probe = 'cleanup-after-retry-terminal'),
  'not_found',
  null,
  'job:legal-retry-cleanup-not-found',
  (select correlation_id from pg_temp.legal_retry_claims where probe = 'cleanup-after-retry-terminal')
) result;
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_retry_cleanup_completions completion
    where completion.probe = 'after-retry-terminal'
      and completion.cleanup_status = 'not_found'
      and not completion.replayed
  )
  and (
    select pg_catalog.array_agg(
      event.aggregate_version order by event.aggregate_version
    ) = array[1, 2, 3, 4, 5]::bigint[]
      and pg_catalog.array_agg(
        event.event_name order by event.aggregate_version
      ) = array[
        'media.legal_original_verification_queued',
        'media.legal_original_verification_retry_requested',
        'media.legal_original_verification_rejected',
        'media.legal_original_quarantine_cleanup_queued',
        'media.legal_original_quarantine_cleanup_completed'
      ]::text[]
    from public.outbox_events event
    where event.workspace_id = '10000000-0000-4000-8000-000000000001'
      and event.aggregate_type = 'legal_original_upload_session'
      and event.aggregate_id = (
        select upload_session_id
        from pg_temp.legal_retry_intents
        where probe = 'actor-a'
      )
  ),
  'retry, rejection, and cleanup preserve one unique monotonic aggregate event lineage'
);

select * from extensions.finish();
rollback;
