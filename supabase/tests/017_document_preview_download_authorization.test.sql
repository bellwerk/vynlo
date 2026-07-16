-- VYN-DOC-001, VYN-STOR-001, VYN-SEC-001, VYN-AUD-001, VYN-API-001
-- M1-DOC-AC-013, T-DOC-001, T-STOR-001, T-RBAC-001, T-AUD-001, T-API-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(20);

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  fixture_role text default 'authenticated'
)
returns void
language plpgsql
as $$
declare
  claims jsonb;
begin
  claims := pg_catalog.jsonb_build_object(
    'sub', fixture_user_id::text,
    'role', fixture_role,
    'aal', 'aal2',
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', 'totp',
        'timestamp', pg_catalog.floor(
          pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', fixture_role, true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

insert into public.deals (
  id, workspace_id, deal_type_key, status, currency_code,
  owner_membership_id, idempotency_key, command_fingerprint, created_by
) values (
  'd7100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'retail.cash', 'draft', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'preview-download-fixture-deal', repeat('1', 64),
  '31000000-0000-4000-8000-000000000001'
);

insert into public.documents (
  id, workspace_id, document_type_id, template_version_id, deal_id,
  status, locale, render_input_snapshot, render_input_checksum,
  generated_checksum, idempotency_key, command_fingerprint, created_by
) values (
  'd7200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001',
  'd7100000-0000-4000-8000-000000000001',
  'generated', 'en-CA', '{}', repeat('2', 64), repeat('f', 64),
  'preview-download-fixture-document', repeat('3', 64),
  '31000000-0000-4000-8000-000000000001'
);

insert into public.outbox_events (
  id, workspace_id, event_name, aggregate_type, aggregate_id,
  aggregate_version, payload_schema_version, payload, actor_user_id,
  correlation_id
) values (
  'd7300000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'document.preview_requested', 'document',
  'd7200000-0000-4000-8000-000000000001',
  1, 1, '{}', '31000000-0000-4000-8000-000000000001',
  'd7c00000-0000-4000-8000-000000000001'
);

insert into public.jobs (
  id, workspace_id, outbox_event_id, job_type, entity_type, entity_id,
  payload_schema_version, payload, idempotency_key, request_fingerprint,
  status, attempts_started, first_started_at, completed_at, correlation_id
) values (
  'd7400000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'd7300000-0000-4000-8000-000000000001',
  'documents.render_preview', 'document',
  'd7200000-0000-4000-8000-000000000001',
  1,
  pg_catalog.jsonb_build_object(
    'document_id', 'd7200000-0000-4000-8000-000000000001'
  ),
  'preview-download-fixture-job', repeat('4', 64),
  'succeeded', 1, pg_catalog.statement_timestamp(),
  pg_catalog.statement_timestamp(),
  'd7c00000-0000-4000-8000-000000000001'
);

insert into public.document_preview_jobs (
  id, workspace_id, document_id, outbox_event_id, job_id,
  idempotency_key, request_fingerprint, requested_by
) values (
  'd7500000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'd7200000-0000-4000-8000-000000000001',
  'd7300000-0000-4000-8000-000000000001',
  'd7400000-0000-4000-8000-000000000001',
  'preview-download-fixture-mapping', repeat('5', 64),
  '31000000-0000-4000-8000-000000000001'
);

insert into public.document_preview_artifacts (
  id, workspace_id, document_id, preview_job_id, job_id,
  storage_bucket, storage_object_path, filename, mime_type, byte_size,
  checksum, renderer_version, requested_by, correlation_id
) values (
  'd7600000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'd7200000-0000-4000-8000-000000000001',
  'd7500000-0000-4000-8000-000000000001',
  'd7400000-0000-4000-8000-000000000001',
  'document-previews',
  '10000000-0000-4000-8000-000000000001/documents/'
    || 'd7200000-0000-4000-8000-000000000001/preview/'
    || repeat('f', 64) || '.html',
  'preview.html', 'text/html; charset=utf-8', 512, repeat('f', 64),
  'synthetic-html-v1', '31000000-0000-4000-8000-000000000001',
  'd7c00000-0000-4000-8000-000000000001'
);

create temporary table pg_temp.preview_download_authorizations (
  authorization_id uuid,
  artifact_id uuid,
  document_id uuid,
  filename text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  authorization_expires_at timestamptz,
  replayed boolean,
  audit_event_id uuid,
  probe text
);
grant all on pg_temp.preview_download_authorizations
  to authenticated, service_role;

select extensions.has_table(
  'public',
  'document_preview_download_authorizations',
  'T-DOC-JOB-006 audited preview download authorizations exist'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'document_preview_download_authorizations'
  ),
  'T-DOC-JOB-006 authorization provenance enforces RLS'
);
select extensions.ok(
  pg_catalog.has_column_privilege(
    'authenticated', 'public.document_preview_artifacts', 'id', 'SELECT'
  )
    and pg_catalog.has_column_privilege(
      'authenticated', 'public.document_preview_artifacts', 'document_id', 'SELECT'
    )
    and not pg_catalog.has_column_privilege(
      'authenticated', 'public.document_preview_artifacts', 'storage_bucket', 'SELECT'
    )
    and not pg_catalog.has_column_privilege(
      'authenticated', 'public.document_preview_artifacts', 'storage_object_path', 'SELECT'
    ),
  'T-DOC-JOB-006 browser artifact projection excludes provider coordinates'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.document_preview_download_authorizations', 'SELECT'
  ),
  'T-DOC-JOB-006 authorization provenance is not browser-readable'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.authorize_document_preview_download(uuid,text,uuid,integer,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'service_role',
      'app.authorize_document_preview_download(uuid,text,uuid,integer,text,uuid)',
      'EXECUTE'
    ),
  'T-DOC-JOB-006 only authenticated users invoke the audited authorization command'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.load_document_preview_download_authorization(uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.load_document_preview_download_authorization(uuid)',
      'EXECUTE'
    ),
  'T-DOC-JOB-006 only the server loader can resolve provider coordinates'
);
select extensions.ok(
  pg_catalog.pg_get_function_result(
    'app.authorize_document_preview_download(uuid,text,uuid,integer,text,uuid)'::regprocedure
  ) not like '%storage_bucket%'
    and pg_catalog.pg_get_function_result(
      'app.authorize_document_preview_download(uuid,text,uuid,integer,text,uuid)'::regprocedure
    ) not like '%storage_object_path%',
  'T-DOC-JOB-006 user-facing authorization result contains no provider coordinates'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'storage.objects', 'SELECT'
  ),
  'T-DOC-JOB-006 browser sessions cannot read storage objects directly'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$select id, document_id from public.document_preview_artifacts$$,
  'T-DOC-JOB-006 authorized users can read only safe artifact identity'
);
select extensions.throws_ok(
  $$select storage_bucket from public.document_preview_artifacts$$,
  '42501',
  'permission denied for table document_preview_artifacts',
  'T-DOC-JOB-006 browser cannot request the hidden provider bucket'
);

insert into pg_temp.preview_download_authorizations
select result.*, 'initial'
from app.authorize_document_preview_download(
  '10000000-0000-4000-8000-000000000001',
  'preview-download-authorization-001',
  'd7600000-0000-4000-8000-000000000001',
  60,
  'request-preview-download-001',
  'd7c00000-0000-4000-8000-000000000002'
) result;
select extensions.ok(
  exists (
    select 1
    from pg_temp.preview_download_authorizations result
    where result.probe = 'initial'
      and result.artifact_id = 'd7600000-0000-4000-8000-000000000001'
      and result.document_id = 'd7200000-0000-4000-8000-000000000001'
      and result.filename = 'preview.html'
      and result.mime_type = 'text/html; charset=utf-8'
      and result.byte_size = 512
      and result.checksum_sha256 = repeat('f', 64)
      and not result.replayed
  ),
  'T-DOC-JOB-006 authorization returns immutable public provenance only'
);
reset role;
select extensions.ok(
  exists (
    select 1
    from public.audit_events audit
    join pg_temp.preview_download_authorizations result
      on result.audit_event_id = audit.id
    where result.probe = 'initial'
      and audit.workspace_id = '10000000-0000-4000-8000-000000000001'
      and audit.action = 'document_preview.download_authorized'
      and audit.entity_id = 'd7600000-0000-4000-8000-000000000001'
  ),
  'T-DOC-JOB-006 sensitive preview download authorization is audited'
);

set local role authenticated;
insert into pg_temp.preview_download_authorizations
select result.*, 'replay'
from app.authorize_document_preview_download(
  '10000000-0000-4000-8000-000000000001',
  'preview-download-authorization-001',
  'd7600000-0000-4000-8000-000000000001',
  60,
  'request-preview-download-replay',
  'd7c00000-0000-4000-8000-000000000003'
) result;
select extensions.ok(
  (
    select initial.authorization_id = replay.authorization_id
      and initial.audit_event_id = replay.audit_event_id
      and replay.replayed
    from pg_temp.preview_download_authorizations initial
    join pg_temp.preview_download_authorizations replay on replay.probe = 'replay'
    where initial.probe = 'initial'
  ),
  'T-DOC-JOB-006 exact idempotency replay returns original authorization evidence'
);
select extensions.throws_ok(
  $$select * from app.authorize_document_preview_download(
    '10000000-0000-4000-8000-000000000001',
    'preview-download-authorization-001',
    'd7600000-0000-4000-8000-000000000001',
    61,
    'request-preview-download-conflict',
    'd7c00000-0000-4000-8000-000000000004'
  )$$,
  '23505',
  'preview download idempotency key was reused',
  'T-DOC-JOB-006 changed idempotency replay fails closed'
);
reset role;

select extensions.throws_ok(
  $$update public.document_preview_download_authorizations
    set expires_at = expires_at + interval '1 second'$$,
  '55000',
  'document_preview_download_authorizations is append-only',
  'T-DOC-JOB-006 authorization provenance is append-only'
);

set local role authenticated;
select extensions.throws_ok(
  $$select * from public.document_preview_download_authorizations$$,
  '42501',
  'permission denied for table document_preview_download_authorizations',
  'T-DOC-JOB-006 browser cannot enumerate authorization receipts'
);
reset role;

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$select * from app.authorize_document_preview_download(
    '10000000-0000-4000-8000-000000000001',
    'foreign-preview-download-001',
    'd7600000-0000-4000-8000-000000000001',
    60,
    'request-foreign-preview-download',
    'd7c00000-0000-4000-8000-000000000005'
  )$$,
  '42501',
  'active workspace membership and document permission are required',
  'T-DOC-JOB-006 foreign workspace authorization is denied'
);
select extensions.is(
  (select pg_catalog.count(*) from public.document_preview_artifacts),
  0::bigint,
  'T-DOC-JOB-006 foreign workspace safe projection returns no artifact'
);
reset role;

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'service_role'
);
set local role service_role;
select extensions.ok(
  exists (
    select 1
    from app.load_document_preview_download_authorization(
      (
        select result.authorization_id
        from pg_temp.preview_download_authorizations result
        where result.probe = 'initial'
      )
    ) loaded
    where loaded.workspace_id = '10000000-0000-4000-8000-000000000001'
      and loaded.artifact_id = 'd7600000-0000-4000-8000-000000000001'
      and loaded.storage_bucket = 'document-previews'
      and loaded.storage_object_path like '%/' || repeat('f', 64) || '.html'
      and loaded.checksum_sha256 = repeat('f', 64)
      and loaded.signed_url_ttl_seconds = 60
  ),
  'T-DOC-JOB-006 service loader resolves one exact unexpired authorization'
);
select extensions.throws_ok(
  $$select * from app.load_document_preview_download_authorization(
    'd7f00000-0000-4000-8000-000000000001'
  )$$,
  'P0002',
  'preview download authorization was not found',
  'T-DOC-JOB-006 service loader fails closed for an unknown authorization'
);
reset role;

select extensions.finish();
rollback;
