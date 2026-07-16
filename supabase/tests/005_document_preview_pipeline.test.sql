-- M1-DOC-AC-006 through M1-DOC-AC-013
-- T-DOC-JOB-001 through T-DOC-JOB-010
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(54);

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

select extensions.has_table(
  'public',
  'document_preview_jobs',
  'preview job mappings exist'
);
select extensions.has_table(
  'public',
  'document_preview_artifacts',
  'preview artifact provenance exists'
);
select extensions.has_function(
  'app',
  'request_document_preview_job',
  array['uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'uuid'],
  'transactional preview request wrapper exists'
);
select extensions.has_function(
  'app',
  'complete_document_preview_artifact',
  array[
    'uuid', 'uuid', 'uuid', 'text', 'uuid', 'text', 'text', 'text',
    'text', 'bigint', 'text', 'text', 'text', 'uuid'
  ],
  'worker artifact completion wrapper exists'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'document_preview_jobs',
        'document_preview_artifacts'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  2::bigint,
  'T-DOC-JOB-006 both exposed pipeline tables have forced RLS'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.request_document_preview_job(uuid,text,uuid,uuid,text,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.request_document_preview(uuid,text,uuid,uuid,text,text,uuid)',
      'EXECUTE'
    ),
  'T-DOC-JOB-001 authenticated callers can use only the atomic request wrapper'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.complete_document_preview_artifact(uuid,uuid,uuid,text,uuid,text,text,text,text,bigint,text,text,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'service_role',
      'app.complete_document_preview(uuid,uuid,boolean,text,text,text,uuid)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.complete_document_preview_artifact(uuid,uuid,uuid,text,uuid,text,text,text,text,bigint,text,text,text,uuid)',
      'EXECUTE'
    ),
  'T-DOC-JOB-007 only the service artifact wrapper can complete previews'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.document_preview_jobs', 'INSERT'
  )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.document_preview_artifacts', 'UPDATE'
    )
    and not pg_catalog.has_table_privilege(
      'service_role', 'public.document_preview_artifacts', 'INSERT'
    ),
  'T-DOC-JOB-006 raw browser and worker mutations are prohibited'
);
select extensions.ok(
  (
    select relation.relrowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage'
      and relation.relname = 'objects'
  ),
  'T-DOC-JOB-006 storage objects retain RLS enforcement'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.policyname = 'document_preview_artifact_objects_select'
      and policy.cmd = 'SELECT'
      and 'authenticated' = any(policy.roles)
  ),
  'T-DOC-JOB-006 authenticated storage reads use the artifact-only policy'
);
select extensions.ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'storage.objects', 'SELECT'
  )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'storage.objects', 'INSERT'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'storage.objects', 'UPDATE'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'storage.objects', 'DELETE'
    ),
  'T-DOC-JOB-006 browser storage access is read-only'
);
select extensions.ok(
  (
    select policy.qual
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.policyname = 'document_preview_artifact_objects_select'
  ) ~ 'document_preview_artifacts'
    and (
      select policy.qual
      from pg_catalog.pg_policies policy
      where policy.schemaname = 'storage'
        and policy.tablename = 'objects'
        and policy.policyname = 'document_preview_artifact_objects_select'
    ) ~ 'storage_bucket'
    and (
      select policy.qual
      from pg_catalog.pg_policies policy
      where policy.schemaname = 'storage'
        and policy.tablename = 'objects'
        and policy.policyname = 'document_preview_artifact_objects_select'
    ) ~ 'storage_object_path',
  'T-DOC-JOB-006 storage policy matches exact visible bucket and object path'
);

insert into public.document_types (
  id, workspace_id, key, version, display_name, field_schema,
  official_generation_enabled, status
)
values
  (
    'a5100000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'pipeline_preview', 1, 'Pipeline preview', '{}', false, 'active'
  ),
  (
    'a5200000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'pipeline_preview', 1, 'Pipeline preview', '{}', false, 'active'
  );
insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_checksum, renderer_version, field_schema,
  production_approved, watermark, status
)
values
  (
    'a5300000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'a5100000-0000-4000-8000-000000000001',
    1, 'en-CA', 'synthetic_non_production',
    '<html><body>{{ deal.id }}</body></html>', repeat('1', 64),
    'synthetic-html-v1', '{}', false, 'DRAFT / NON-PRODUCTION', 'active'
  ),
  (
    'a5400000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'a5200000-0000-4000-8000-000000000001',
    1, 'fr-CA', 'synthetic_non_production',
    '<html><body>{{ deal.id }}</body></html>', repeat('2', 64),
    'synthetic-html-v1', '{}', false, 'DRAFT / NON-PRODUCTION', 'active'
  );
insert into public.deals (
  id, workspace_id, deal_type_key, status, currency_code,
  owner_membership_id, idempotency_key, command_fingerprint, created_by
)
values
  (
    'a5500000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'retail.cash', 'draft', 'CAD',
    '41000000-0000-4000-8000-000000000001',
    'pipeline-deal-a', repeat('3', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    'a5600000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'retail.cash', 'draft', 'CAD',
    '42000000-0000-4000-8000-000000000001',
    'pipeline-deal-b', repeat('4', 64),
    '32000000-0000-4000-8000-000000000001'
  );

create temporary table pg_temp.preview_pipeline_results (
  document_id uuid,
  preview_status text,
  watermark text,
  outbox_event_id uuid,
  job_id uuid,
  job_status text,
  replayed boolean,
  probe text
);
create temporary table pg_temp.claimed_preview_jobs (
  job_id uuid,
  workspace_id uuid,
  lease_token uuid,
  correlation_id uuid
);
create temporary table pg_temp.preview_completion_results (
  document_file_id uuid,
  document_status text,
  replayed boolean,
  probe text
);
grant all on pg_temp.preview_pipeline_results,
  pg_temp.claimed_preview_jobs,
  pg_temp.preview_completion_results
to authenticated, service_role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

select extensions.lives_ok(
  $$
    insert into pg_temp.preview_pipeline_results
    select result.*, 'workspace-a-initial'
    from app.request_document_preview_job(
      '10000000-0000-4000-8000-000000000001',
      'pipeline-preview-a',
      'a5500000-0000-4000-8000-000000000001',
      'a5300000-0000-4000-8000-000000000001',
      'en-CA',
      'request-pipeline-a',
      'aa000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'T-DOC-JOB-001 preview document and render job commit atomically'
);
select extensions.results_eq(
  $$
    select preview_status, watermark, job_status, replayed
    from pg_temp.preview_pipeline_results
    where probe = 'workspace-a-initial'
  $$,
  $$values ('queued'::text, 'DRAFT / NON-PRODUCTION'::text, 'queued'::text, false)$$,
  'T-DOC-JOB-001 first request returns queued non-production state'
);
select extensions.ok(
  exists (
    select 1
    from public.document_preview_jobs mapping
    join public.jobs job
      on job.workspace_id = mapping.workspace_id and job.id = mapping.job_id
    join public.outbox_events event
      on event.workspace_id = mapping.workspace_id
     and event.id = mapping.outbox_event_id
    where mapping.document_id = (
      select document_id from pg_temp.preview_pipeline_results
      where probe = 'workspace-a-initial'
    )
      and job.job_type = 'documents.render_preview'
      and job.entity_type = 'document'
      and job.entity_id = mapping.document_id
      and event.event_name = 'document.preview_requested'
      and event.aggregate_id = mapping.document_id
      and job.payload = event.payload
  ),
  'T-DOC-JOB-002 mapping binds the canonical job and outbox event'
);
select extensions.ok(
  (
    select pg_catalog.array_agg(payload_key order by payload_key)
    from public.jobs job,
      lateral pg_catalog.jsonb_object_keys(job.payload) payload_key
    where job.id = (
      select job_id from pg_temp.preview_pipeline_results
      where probe = 'workspace-a-initial'
    )
  ) = array[
    'document_id', 'locale', 'render_input_checksum', 'template_version_id'
  ]::text[],
  'T-DOC-JOB-003 render payload contains exactly the four approved keys'
);
select extensions.ok(
  (
    select job.payload = pg_catalog.jsonb_build_object(
      'document_id', document.id,
      'template_version_id', document.template_version_id,
      'render_input_checksum', document.render_input_checksum,
      'locale', document.locale
    )
      and not app.job_payload_contains_forbidden_key(job.payload)
      and not job.payload ?| array[
        'render_input_snapshot', 'participants', 'inventory_units',
        'source_html', 'credential', 'secret', 'token'
      ]
    from public.jobs job
    join public.documents document
      on document.workspace_id = job.workspace_id
     and document.id = job.entity_id
    where job.id = (
      select job_id from pg_temp.preview_pipeline_results
      where probe = 'workspace-a-initial'
    )
  ),
  'T-DOC-JOB-003 payload is server-derived and excludes snapshot, PII, and credentials'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where entity_id in (
      select document_id from pg_temp.preview_pipeline_results
      where probe = 'workspace-a-initial'
      union all
      select job_id from pg_temp.preview_pipeline_results
      where probe = 'workspace-a-initial'
    )
      and action in ('document.preview_requested', 'job.queued')
  ),
  2::bigint,
  'T-DOC-JOB-008 document request and durable job enqueue are audited'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'document.preview_job_queued'
      and entity_id = (
        select id from public.document_preview_jobs
        where document_id = (
          select document_id from pg_temp.preview_pipeline_results
          where probe = 'workspace-a-initial'
        )
      )
  ),
  1::bigint,
  'T-DOC-JOB-008 immutable pipeline linkage has its own audit event'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.preview_pipeline_results
    select result.*, 'workspace-a-replay'
    from app.request_document_preview_job(
      '10000000-0000-4000-8000-000000000001',
      'pipeline-preview-a',
      'a5500000-0000-4000-8000-000000000001',
      'a5300000-0000-4000-8000-000000000001',
      'en-CA',
      'request-pipeline-a-replay',
      'aa000000-0000-4000-8000-000000000002'
    ) result
  $$,
  'T-DOC-JOB-004 exact request replay succeeds'
);
select extensions.ok(
  (
    select initial.document_id = replay.document_id
      and initial.outbox_event_id = replay.outbox_event_id
      and initial.job_id = replay.job_id
      and replay.replayed
    from pg_temp.preview_pipeline_results initial
    cross join pg_temp.preview_pipeline_results replay
    where initial.probe = 'workspace-a-initial'
      and replay.probe = 'workspace-a-replay'
  ),
  'T-DOC-JOB-004 replay returns the same document, outbox event, and job'
);
select extensions.ok(
  (select pg_catalog.count(*) from public.document_preview_jobs where idempotency_key = 'pipeline-preview-a') = 1
    and (select pg_catalog.count(*) from public.jobs where job_type = 'documents.render_preview' and idempotency_key = 'pipeline-preview-a') = 1
    and (select pg_catalog.count(*) from public.audit_events where action = 'document.preview_job_queued') = 1,
  'T-DOC-JOB-004 replay creates no duplicate mapping, job, or audit event'
);
select extensions.throws_ok(
  $$
    select * from app.request_document_preview_job(
      '10000000-0000-4000-8000-000000000001',
      'pipeline-preview-a',
      'a5500000-0000-4000-8000-000000000001',
      'a5300000-0000-4000-8000-000000000001',
      'fr-CA', 'request-conflict', pg_catalog.gen_random_uuid()
    )
  $$,
  '23505',
  'preview idempotency key was used for a different request',
  'T-DOC-JOB-004 conflicting idempotency fingerprint fails closed'
);
select extensions.throws_ok(
  $$
    select * from app.request_document_preview(
      '10000000-0000-4000-8000-000000000001',
      'direct-base-denied',
      'a5500000-0000-4000-8000-000000000001',
      'a5300000-0000-4000-8000-000000000001',
      'en-CA', 'request-direct', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'permission denied for function request_document_preview',
  'T-DOC-JOB-001 callers cannot bypass atomic enqueue through the base RPC'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.throws_ok(
  $$
    select * from app.request_document_preview_job(
      '10000000-0000-4000-8000-000000000001', 'limited-preview-denied',
      'a5500000-0000-4000-8000-000000000001',
      'a5300000-0000-4000-8000-000000000001', 'en-CA',
      'request-limited', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-DOC-JOB-005 missing permission denies preview enqueue'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
select extensions.throws_ok(
  $$
    select * from app.request_document_preview_job(
      '10000000-0000-4000-8000-000000000001', 'aal1-preview-denied',
      'a5500000-0000-4000-8000-000000000001',
      'a5300000-0000-4000-8000-000000000001', 'en-CA',
      'request-aal1', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-DOC-JOB-005 MFA-required administrator cannot enqueue at AAL1'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from app.request_document_preview_job(
      '20000000-0000-4000-8000-000000000002', 'cross-workspace-denied',
      'a5600000-0000-4000-8000-000000000001',
      'a5400000-0000-4000-8000-000000000001', 'fr-CA',
      'request-cross', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-DOC-JOB-005 workspace context cannot be supplied without membership'
);

reset role;
create function pg_temp.reject_preview_job()
returns trigger
language plpgsql
as $$
begin
  if new.job_type = 'documents.render_preview'
    and new.idempotency_key = 'pipeline-atomic-failure' then
    raise exception 'synthetic preview enqueue failure';
  end if;
  return new;
end;
$$;
create trigger reject_preview_job
before insert on public.jobs
for each row execute function pg_temp.reject_preview_job();
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.request_document_preview_job(
      '10000000-0000-4000-8000-000000000001', 'pipeline-atomic-failure',
      'a5500000-0000-4000-8000-000000000001',
      'a5300000-0000-4000-8000-000000000001', 'en-CA',
      'request-atomic-failure', 'ac000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'synthetic preview enqueue failure',
  'T-DOC-JOB-001 downstream enqueue failure aborts the wrapper statement'
);
reset role;
drop trigger reject_preview_job on public.jobs;
drop function pg_temp.reject_preview_job();
select extensions.ok(
  not exists (select 1 from public.documents where idempotency_key = 'pipeline-atomic-failure')
    and not exists (select 1 from public.document_preview_jobs where idempotency_key = 'pipeline-atomic-failure')
    and not exists (select 1 from public.jobs where idempotency_key = 'pipeline-atomic-failure')
    and not exists (select 1 from public.outbox_events where correlation_id = 'ac000000-0000-4000-8000-000000000001')
    and not exists (select 1 from public.audit_events where correlation_id = 'ac000000-0000-4000-8000-000000000001'),
  'T-DOC-JOB-001 document, outbox, job, mapping, and audit all roll back together'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.preview_pipeline_results
    select result.*, 'workspace-b-initial'
    from app.request_document_preview_job(
      '20000000-0000-4000-8000-000000000002', 'pipeline-preview-b',
      'a5600000-0000-4000-8000-000000000001',
      'a5400000-0000-4000-8000-000000000001', 'fr-CA',
      'request-pipeline-b', 'bb000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'workspace B can create its own isolated pipeline mapping'
);

set local role service_role;
select extensions.throws_ok(
  $$
    select * from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'preview-worker', '00000000-0000-4000-8000-000000000001',
      'preview-artifacts',
      '10000000-0000-4000-8000-000000000001/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')::text ||
        '/preview/' || repeat('f', 64) || '.html',
      'preview.html', 'text/html; charset=utf-8', 512, repeat('f', 64),
      'synthetic-html-v1', 'request-before-claim',
      'aa000000-0000-4000-8000-000000000001'
    )
  $$,
  '55000',
  'only the matching active lease owner can record an artifact',
  'T-DOC-JOB-007 queued jobs cannot publish an artifact before claim'
);
select extensions.throws_ok(
  $$
    select * from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'preview-worker', '00000000-0000-4000-8000-000000000001',
      'preview-artifacts', 'public/unsafe.html', 'preview.html',
      'text/html; charset=utf-8', 512, repeat('f', 64),
      'synthetic-html-v1', 'request-invalid-path',
      'aa000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  'preview artifact object path is not the deterministic private key',
  'T-DOC-JOB-007 non-deterministic storage object paths fail closed'
);
select extensions.throws_ok(
  $$
    select * from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'preview-worker', '00000000-0000-4000-8000-000000000001',
      'preview-artifacts',
      '10000000-0000-4000-8000-000000000001/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')::text ||
        '/preview/' || repeat('f', 64) || '.html',
      'preview.html', 'application/pdf', 512, repeat('f', 64),
      'synthetic-html-v1', 'request-invalid-mime',
      'aa000000-0000-4000-8000-000000000001'
    )
  $$,
  '22023',
  'preview artifact MIME type must be text/html; charset=utf-8',
  'T-DOC-JOB-007 worker artifact media policy is enforced'
);
select extensions.throws_ok(
  $$
    select * from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'preview-worker', '00000000-0000-4000-8000-000000000001',
      'preview-artifacts',
      '10000000-0000-4000-8000-000000000001/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')::text ||
        '/preview/' || repeat('f', 64) || '.html',
      'preview.html', 'text/html; charset=utf-8', 0, repeat('f', 64),
      'synthetic-html-v1', 'request-invalid-bytes',
      'aa000000-0000-4000-8000-000000000001'
    )
  $$,
  '22023',
  'preview artifact byte size is outside the allowed range',
  'T-DOC-JOB-007 empty artifacts fail closed'
);

insert into pg_temp.claimed_preview_jobs
select claimed.job_id, claimed.workspace_id, claimed.lease_token, claimed.correlation_id
from app.claim_jobs(
  'preview-worker', 10, 60, array['documents.render_preview']
) claimed;
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.claimed_preview_jobs),
  2::bigint,
  'T-DOC-JOB-007 worker claims both isolated preview jobs through the durable queue'
);
select extensions.throws_ok(
  $$
    select * from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'stale-preview-worker',
      (select lease_token from pg_temp.claimed_preview_jobs where workspace_id = '10000000-0000-4000-8000-000000000001'),
      'preview-artifacts',
      '10000000-0000-4000-8000-000000000001/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')::text ||
        '/preview/' || repeat('f', 64) || '.html',
      'preview.html', 'text/html; charset=utf-8', 512, repeat('f', 64),
      'synthetic-html-v1', 'job:stale-worker',
      'aa000000-0000-4000-8000-000000000001'
    )
  $$,
  '55000',
  'only the matching active lease owner can record an artifact',
  'T-DOC-JOB-007 stale worker identity cannot publish under another worker lease'
);
select extensions.throws_ok(
  $$
    select * from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'preview-worker', '00000000-0000-4000-8000-000000000002',
      'preview-artifacts',
      '10000000-0000-4000-8000-000000000001/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')::text ||
        '/preview/' || repeat('f', 64) || '.html',
      'preview.html', 'text/html; charset=utf-8', 512, repeat('f', 64),
      'synthetic-html-v1', 'job:stale-lease',
      'aa000000-0000-4000-8000-000000000001'
    )
  $$,
  '55000',
  'only the matching active lease owner can record an artifact',
  'T-DOC-JOB-007 stale lease token cannot publish under a replacement lease'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.preview_completion_results
    select result.*, 'workspace-a-initial'
    from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'preview-worker',
      (select lease_token from pg_temp.claimed_preview_jobs where workspace_id = '10000000-0000-4000-8000-000000000001'),
      'preview-artifacts',
      '10000000-0000-4000-8000-000000000001/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')::text ||
        '/preview/' || repeat('f', 64) || '.html',
      'preview.html', 'text/html; charset=utf-8', 512, repeat('f', 64),
      'synthetic-html-v1', 'job:workspace-a',
      'aa000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'T-DOC-JOB-007 active worker records immutable artifact provenance'
);
select extensions.ok(
  exists (
    select 1
    from public.document_preview_artifacts artifact
    where artifact.id = (
      select document_file_id from pg_temp.preview_completion_results
      where probe = 'workspace-a-initial'
    )
      and artifact.storage_bucket = 'preview-artifacts'
      and artifact.filename = 'preview.html'
      and artifact.mime_type = 'text/html; charset=utf-8'
      and artifact.byte_size = 512
      and artifact.checksum = repeat('f', 64)
      and artifact.renderer_version = 'synthetic-html-v1'
  ),
  'T-DOC-JOB-007 artifact stores bucket, deterministic path, media, bytes, checksum, and renderer'
);
select extensions.results_eq(
  $$
    select status, generated_checksum
    from public.documents
    where id = (
      select document_id from pg_temp.preview_pipeline_results
      where probe = 'workspace-a-initial'
    )
  $$,
  $$values ('generated'::text, repeat('f', 64)::text)$$,
  'T-DOC-JOB-007 artifact RPC completes the document with the immutable checksum'
);
select extensions.is(
  (
    select status from public.jobs
    where id = (
      select job_id from pg_temp.preview_pipeline_results
      where probe = 'workspace-a-initial'
    )
  ),
  'running'::text,
  'worker runner retains responsibility for generic job completion'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.preview_completion_results
    select result.*, 'workspace-a-replay'
    from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'preview-worker',
      (select lease_token from pg_temp.claimed_preview_jobs where workspace_id = '10000000-0000-4000-8000-000000000001'),
      'preview-artifacts',
      '10000000-0000-4000-8000-000000000001/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')::text ||
        '/preview/' || repeat('f', 64) || '.html',
      'preview.html', 'text/html; charset=utf-8', 512, repeat('f', 64),
      'synthetic-html-v1', 'job:workspace-a-replay',
      'aa000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'T-DOC-JOB-009 exact artifact replay succeeds under the matching active lease'
);
select extensions.ok(
  (
    select initial.document_file_id = replay.document_file_id
      and replay.replayed
    from pg_temp.preview_completion_results initial
    cross join pg_temp.preview_completion_results replay
    where initial.probe = 'workspace-a-initial'
      and replay.probe = 'workspace-a-replay'
  ),
  'T-DOC-JOB-009 artifact replay returns the same immutable file ID'
);
select extensions.throws_ok(
  $$
    select * from app.complete_document_preview_artifact(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
      'preview-worker',
      (select lease_token from pg_temp.claimed_preview_jobs where workspace_id = '10000000-0000-4000-8000-000000000001'),
      'preview-artifacts',
      '10000000-0000-4000-8000-000000000001/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')::text ||
        '/preview/' || repeat('e', 64) || '.html',
      'preview.html', 'text/html; charset=utf-8', 512, repeat('e', 64),
      'synthetic-html-v1', 'job:workspace-a-conflict',
      'aa000000-0000-4000-8000-000000000001'
    )
  $$,
  '23505',
  'preview artifact completion conflicts with the immutable result',
  'T-DOC-JOB-009 conflicting artifact replay fails closed'
);
select extensions.ok(
  app.complete_job(
    (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial'),
    'preview-worker',
    (select lease_token from pg_temp.claimed_preview_jobs where workspace_id = '10000000-0000-4000-8000-000000000001'),
    pg_catalog.jsonb_build_object(
      'document_file_id', (
        select document_file_id from pg_temp.preview_completion_results
        where probe = 'workspace-a-initial'
      )
    ),
    null
  ),
  'generic worker lifecycle completes after lease-fenced artifact RPC succeeds'
);
select extensions.ok(
  (select pg_catalog.count(*) from public.audit_events where action = 'document.preview_generated' and entity_id = (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-a-initial')) = 1
    and (select pg_catalog.count(*) from public.audit_events where action = 'document.preview_artifact_recorded' and entity_id = (select document_file_id from pg_temp.preview_completion_results where probe = 'workspace-a-initial')) = 1,
  'T-DOC-JOB-008 document and artifact completion audits are exactly-once'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.preview_completion_results
    select result.*, 'workspace-b-initial'
    from app.complete_document_preview_artifact(
      '20000000-0000-4000-8000-000000000002',
      (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-b-initial'),
      (select job_id from pg_temp.preview_pipeline_results where probe = 'workspace-b-initial'),
      'preview-worker',
      (select lease_token from pg_temp.claimed_preview_jobs where workspace_id = '20000000-0000-4000-8000-000000000002'),
      'preview-artifacts',
      '20000000-0000-4000-8000-000000000002/documents/' ||
        (select document_id from pg_temp.preview_pipeline_results where probe = 'workspace-b-initial')::text ||
        '/preview/' || repeat('d', 64) || '.html',
      'preview.html', 'text/html; charset=utf-8', 384, repeat('d', 64),
      'synthetic-html-v1', 'job:workspace-b',
      'bb000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'workspace B worker completion preserves workspace context'
);

reset role;
select extensions.throws_ok(
  $$
    update public.document_preview_artifacts
    set byte_size = byte_size + 1
    where id = (
      select document_file_id from pg_temp.preview_completion_results
      where probe = 'workspace-a-initial'
    )
  $$,
  '55000',
  'document_preview_artifacts is append-only',
  'T-DOC-JOB-010 artifact provenance cannot be updated by trusted roles'
);
select extensions.throws_ok(
  $$
    delete from public.document_preview_jobs
    where document_id = (
      select document_id from pg_temp.preview_pipeline_results
      where probe = 'workspace-a-initial'
    )
  $$,
  '55000',
  'document_preview_jobs is append-only',
  'T-DOC-JOB-010 preview job mappings cannot be hard-deleted'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  (select pg_catalog.count(*) from public.document_preview_jobs where workspace_id = '10000000-0000-4000-8000-000000000001') = 1
    and (select pg_catalog.count(*) from public.document_preview_artifacts where workspace_id = '10000000-0000-4000-8000-000000000001') = 1,
  'T-DOC-JOB-006 workspace A requester can read its own pipeline records'
);
select extensions.ok(
  (select pg_catalog.count(*) from public.document_preview_jobs where workspace_id = '20000000-0000-4000-8000-000000000002') = 0
    and (select pg_catalog.count(*) from public.document_preview_artifacts where workspace_id = '20000000-0000-4000-8000-000000000002') = 0,
  'T-DOC-JOB-006 forced RLS hides workspace B mapping and artifact from A'
);
select extensions.throws_ok(
  $$
    update public.document_preview_jobs
    set idempotency_key = 'browser-tamper'
    where idempotency_key = 'pipeline-preview-a'
  $$,
  '42501',
  'permission denied for table document_preview_jobs',
  'T-DOC-JOB-006 browser cannot mutate visible pipeline history'
);

select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.request_document_preview_job(uuid,text,uuid,uuid,text,text,uuid)'::regprocedure
  ) ~* 'enqueue_outbox_job'
    and pg_catalog.pg_get_functiondef(
      'app.request_document_preview_job(uuid,text,uuid,uuid,text,text,uuid)'::regprocedure
    ) ~* 'documents\.render_preview',
  'T-DOC-JOB-002 wrapper is statically bound to generic enqueue and canonical job type'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.request_document_preview_job(uuid,text,uuid,uuid,text,text,uuid)'::regprocedure
  ) ~* 'pg_advisory_xact_lock|request_document_preview',
  'T-DOC-JOB-004 request path retains serialized idempotency enforcement'
);

select * from extensions.finish();
rollback;
