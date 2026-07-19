-- VYN-EXP-001, VYN-JOB-001, VYN-STOR-001, VYN-API-001,
-- VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- M4-EXP-AC-001..005 / T-EXP-001..002, T-JOB-001..003,
-- T-STOR-001, T-API-002, T-TEN-001..003, T-RBAC-001, T-AUD-001.
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(53);

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  assurance text default 'aal2',
  factor_age_seconds integer default 0
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
        )::bigint - factor_age_seconds
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create function pg_temp.authenticate_service()
returns void
language plpgsql
as $$
declare
  claims jsonb;
begin
  claims := pg_catalog.jsonb_build_object(
    'sub', '31000000-0000-4000-8000-000000000001',
    'role', 'service_role',
    'aal', 'aal2',
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', 'service_role',
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config(
    'request.jwt.claim.sub', '31000000-0000-4000-8000-000000000001', true
  );
  perform pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.export_results (
  phase text primary key,
  export_run_id uuid,
  run_status text,
  job_id uuid,
  job_status text,
  expires_at timestamptz,
  audit_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.claimed_jobs (
  phase text primary key,
  job_id uuid,
  workspace_id uuid,
  lease_token uuid,
  correlation_id uuid
);
create temporary table pg_temp.export_receipts (
  phase text primary key,
  export_run_id uuid,
  checksum text,
  object_path text,
  receipt jsonb
);
create temporary table pg_temp.export_file_results (
  phase text primary key,
  export_file_id uuid,
  run_status text,
  row_count bigint,
  replayed boolean
);
create temporary table pg_temp.download_results (
  phase text primary key,
  authorization_id uuid,
  export_file_id uuid,
  filename text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  authorization_expires_at timestamptz,
  audit_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.snapshot_pages (
  phase text primary key,
  source_snapshot_id uuid,
  snapshot_captured_at timestamptz,
  source_row_count integer,
  source_snapshot_fingerprint text,
  next_ordinal integer,
  source_rows jsonb
);
grant all on
  pg_temp.export_results,
  pg_temp.claimed_jobs,
  pg_temp.export_receipts,
  pg_temp.export_file_results,
  pg_temp.download_results,
  pg_temp.snapshot_pages
to authenticated, service_role;

-- Report fixture: rounding each fractional line before summing distinguishes
-- the exact business rule from a single round after summation (2 versus 1).
insert into public.deals (
  id, workspace_id, deal_type_key, currency_code, owner_membership_id,
  notes, idempotency_key, command_fingerprint, created_by
) values (
  '36040000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001', 'retail.cash', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'Rolled-back fractional report fixture', 'm4-report-deal-fixture', repeat('4', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.deal_line_items (
  id, workspace_id, deal_id, key, item_type, label, quantity_text,
  unit_amount_minor, currency_code, sort_order, created_by, updated_by
) values
  (
    '36041000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '36040000-0000-4000-8000-000000000001', 'fraction.one', 'fee',
    'Fraction one', '0.5', 1, 'CAD', 10,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '36041000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '36040000-0000-4000-8000-000000000001', 'fraction.two', 'fee',
    'Fraction two', '0.5', 1, 'CAD', 20,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  );

-- Source fixture above JavaScript's safe-integer ceiling. The snapshot RPC
-- must serialize PostgreSQL bigint money as canonical decimal text.
insert into public.deals (
  id, workspace_id, deal_type_key, currency_code, owner_membership_id,
  notes, idempotency_key, command_fingerprint, created_by
) values (
  '36040000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001', 'retail.cash', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'Rolled-back bigint export fixture', 'm4-export-bigint-fixture', repeat('5', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.deal_line_items (
  id, workspace_id, deal_id, key, item_type, label, quantity_text,
  unit_amount_minor, currency_code, sort_order, created_by, updated_by
) values (
  '36041000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  '36040000-0000-4000-8000-000000000002', 'bigint.one', 'fee',
  'Bigint exact transport', '1', 9007199254740993, 'CAD', 10,
  '31000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001'
);

insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
  artifact_checksum, approval_type, decision, decided_by,
  professional_role, professional_organization, conditions,
  attachment_reference, idempotency_key, reason
) values (
  '36120000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'export_definition', 'export.fixture_deals', 1,
  '36110000-0000-4000-8000-000000000001', repeat('6', 64),
  'operational', 'approved', '31000000-0000-4000-8000-000000000001',
  'fixture_reviewer', 'Synthetic Review Lab', '{"fixture":true}',
  'fixture://export', 'm4-export-approval-036',
  'Rolled-back synthetic export approval'
);
insert into public.export_definitions (
  id, workspace_id, key, labels
) values (
  '36100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001', 'fixture_deals',
  '{"en":"Fixture deals","fr":"Dossiers fictifs"}'
);
insert into public.export_versions (
  id, workspace_id, export_definition_id, version, semantic_version, status,
  source_key, formats, columns, filter_schema, sort_specification,
  sensitivity, permission_key, step_up_required, maximum_rows,
  expires_after_seconds, checksum, validation_evidence, fixture_evidence,
  approval_record_id, created_by, activated_by, activated_at
) values (
  '36110000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '36100000-0000-4000-8000-000000000001', 1, '1.0.0', 'draft',
  'deals', array['csv', 'xlsx'],
  '[
    {
      "key":"reference",
      "labels":{"en":"Deal ID","fr":"ID du dossier"},
      "source":"deal.reference",
      "format":"text",
      "sensitive":false,
      "permission":"reports.read"
    },
    {
      "key":"total_minor",
      "labels":{"en":"Total (minor units)","fr":"Total (unites mineures)"},
      "source":"deal.total_minor",
      "format":"minor_units",
      "sensitive":true,
      "permission":"exports.run_sensitive"
    }
  ]',
  '{
    "type":"object",
    "additionalProperties":false,
    "properties":{
      "workflow_states":{"type":"array","maxItems":100,"items":{"type":"string","maxLength":200}},
      "deal_type_keys":{"type":"array","maxItems":100,"items":{"type":"string","maxLength":200}},
      "updated_from":{"type":"string","format":"date-time"},
      "updated_to":{"type":"string","format":"date-time"}
    }
  }',
  '[{"key":"reference","direction":"asc"}]',
  'sensitive', 'exports.run', true, 500, 3600, repeat('6', 64),
  null, null, null,
  '31000000-0000-4000-8000-000000000001',
  null, null
);

update public.export_versions version
set status = 'validated',
    validation_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'validator', 'fixture-export-validator-v1',
      'artifactChecksum', version.checksum
    )
where version.id = '36110000-0000-4000-8000-000000000001';
update public.export_versions version
set status = 'test_passed',
    fixture_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'runner', 'fixture-export-runner-v1',
      'artifactChecksum', version.checksum,
      'tests', pg_catalog.jsonb_build_array('fixture-export')
    )
where version.id = '36110000-0000-4000-8000-000000000001';
update public.export_versions version
set status = 'approved',
    approval_record_id = '36120000-0000-4000-8000-000000000001'
where version.id = '36110000-0000-4000-8000-000000000001';
update public.export_versions version
set status = 'active',
    activated_by = '31000000-0000-4000-8000-000000000001',
    activated_at = pg_catalog.statement_timestamp()
where version.id = '36110000-0000-4000-8000-000000000001';

select extensions.is(
  app.m4_resolve_export_sort_plan(
    '[{"key":"reference","source":"deal.reference"}]'::jsonb,
    '[]'::jsonb
  ),
  '[
    {"direction":"asc","source":"deal.reference"},
    {"direction":"asc","opaque":true,"source":"__vynlo_source_id"}
  ]'::jsonb,
  'M4-EXP-AC-001 empty approved sort resolves to an authorized field and opaque ID tie-breaker'
);

set local timezone to 'Pacific/Auckland';
select extensions.ok(
  app.m4_json_schema_value_valid(
    '{"type":"string","format":"date-time"}'::jsonb,
    '{"type":"string","format":"date-time"}'::jsonb,
    '"2026-07-16T12:30:00Z"'::jsonb
  ),
  'M4-EXP-AC-001 canonical RFC3339 Z timestamps validate outside UTC sessions'
);
set local timezone to 'America/Toronto';
select extensions.ok(
  app.m4_json_schema_value_valid(
    '{"type":"string","format":"date-time"}'::jsonb,
    '{"type":"string","format":"date-time"}'::jsonb,
    '"2026-07-16T12:30:00+05:30"'::jsonb
  ),
  'M4-EXP-AC-001 canonical RFC3339 numeric offsets validate deterministically across session zones'
);

-- 1. Export command, file, job, and authorization history is forced-RLS.
select extensions.is(
  (
    select pg_catalog.count(*) from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'export_definitions', 'export_versions', 'export_runs', 'export_files',
        'export_run_jobs', 'export_download_authorizations',
        'export_run_source_snapshots', 'export_run_source_snapshot_rows'
      ])
      and relation.relrowsecurity and relation.relforcerowsecurity
  ),
  8::bigint,
  'M4-EXP-AC-003 export definitions, runs, jobs, files, and grants are forced-RLS'
);

-- 2. Browser-safe export file projection excludes provider coordinates and receipts.
select extensions.ok(
  not pg_catalog.has_column_privilege('authenticated', 'public.export_files', 'storage_bucket', 'SELECT')
  and not pg_catalog.has_column_privilege('authenticated', 'public.export_files', 'storage_object_path', 'SELECT')
  and not pg_catalog.has_column_privilege('authenticated', 'public.export_files', 'storage_generation', 'SELECT')
  and not pg_catalog.has_column_privilege('authenticated', 'public.export_files', 'verification_receipt', 'SELECT'),
  'M4-EXP-AC-004 export provider coordinates are never browser-readable'
);

-- 3. Worker load/completion/coordinate resolution functions are service-only.
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role', 'app.m4_load_export_run(uuid,uuid,uuid,text,uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated', 'app.m4_load_export_run(uuid,uuid,uuid,text,uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'service_role',
    'app.m4_read_export_source_snapshot_page(uuid,uuid,uuid,text,uuid,integer,integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app.m4_read_export_source_snapshot_page(uuid,uuid,uuid,text,uuid,integer,integer)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'service_role', 'app.m4_load_export_download_authorization(uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated', 'app.m4_load_export_download_authorization(uuid)', 'EXECUTE'
  ),
  'T-RBAC-001 export worker and download resolution boundaries are service-only'
);

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001', 'aal2', 1000
);
set local role authenticated;

-- 4. Sensitive export requires recent step-up even when the actor has permissions.
select extensions.throws_ok(
  $$
    select * from app.m4_request_export_run(
      '10000000-0000-4000-8000-000000000001', 'fixture_deals',
      'csv', 'en-CA', '{}', 'm4-export-stale-stepup',
      'Attempt sensitive export with stale strong authentication',
      'm4-export-stale-stepup', '36200000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'recent strong authentication is required',
  'T-EXP-002 sensitive export rejects stale assurance'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.export_results
select 'csv-initial', result.*
from app.m4_request_export_run(
  '10000000-0000-4000-8000-000000000001', 'fixture_deals',
  'csv', 'en-CA', '{}', 'm4-export-csv-initial',
  'Generate rolled-back sensitive CSV fixture',
  'm4-export-csv-initial', '36200000-0000-4000-8000-000000000002'
) result;

-- 5. Authorized request creates one queued run pinned to the active version.
select extensions.ok(
  exists (
    select 1 from public.export_runs run
    where run.id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
      and run.export_version_id = '36110000-0000-4000-8000-000000000001'
      and run.requested_format = 'csv' and run.status = 'queued'
      and run.requested_by = '31000000-0000-4000-8000-000000000001'
      and run.authorized_sort_plan = '[
        {"direction":"asc","source":"deal.reference"},
        {"direction":"asc","opaque":true,"source":"__vynlo_source_id"}
      ]'::jsonb
  )
  and not (select replayed from pg_temp.export_results where phase = 'csv-initial'),
  'M4-EXP-AC-003 export run pins actor, active exact version, format, and status'
);

-- 6. Authorized plan retains bilingual typed columns and exact minor-unit semantics.
select extensions.ok(
  exists (
    select 1 from public.export_runs run
    where run.id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
      and pg_catalog.jsonb_array_length(run.authorized_column_plan) = 2
      and run.authorized_column_plan @> '[{"key":"total_minor","format":"minor_units","source":"deal.total_minor"}]'::jsonb
  )
  and (select formats from public.export_versions where id = '36110000-0000-4000-8000-000000000001')
    = array['csv', 'xlsx'],
  'T-EXP-001 CSV and XLSX share one exact authorized column definition'
);

-- 7. Run, outbox, durable job, mapping, and audit evidence commit atomically.
select extensions.ok(
  exists (
    select 1
    from app.m4_get_export_run(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
    ) projection
    where projection.export_version_id = '36110000-0000-4000-8000-000000000001'
      and projection.job_id = (select job_id from pg_temp.export_results where phase = 'csv-initial')
      and projection.outbox_event_id is not null
      and projection.status = 'queued'
  )
  and (select job_status from pg_temp.export_results where phase = 'csv-initial') = 'queued'
  and exists (
    select 1 from public.audit_events event
    where event.id = (select audit_event_id from pg_temp.export_results where phase = 'csv-initial')
      and event.action = 'export.run_requested'
  ),
  'T-JOB-001 export authoritative state and durable execution commit together'
);

insert into pg_temp.export_results
select 'csv-replay', result.*
from app.m4_request_export_run(
  '10000000-0000-4000-8000-000000000001', 'fixture_deals',
  'csv', 'en-CA', '{}', 'm4-export-csv-initial',
  '  Generate rolled-back sensitive CSV fixture  ',
  'm4-export-csv-replay', '36200000-0000-4000-8000-000000000002'
) result;

-- 8. Exact export replay returns the same run, job, expiry, and audit evidence.
select extensions.ok(
  (select export_run_id from pg_temp.export_results where phase = 'csv-replay')
    = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
  and (select job_id from pg_temp.export_results where phase = 'csv-replay')
    = (select job_id from pg_temp.export_results where phase = 'csv-initial')
  and (select audit_event_id from pg_temp.export_results where phase = 'csv-replay')
    = (select audit_event_id from pg_temp.export_results where phase = 'csv-initial')
  and (select replayed from pg_temp.export_results where phase = 'csv-replay'),
  'M4-EXP-AC-003 export request is actor-idempotent'
);

-- 9. A reused actor key cannot change format or filters.
select extensions.throws_ok(
  $$
    select * from app.m4_request_export_run(
      '10000000-0000-4000-8000-000000000001', 'fixture_deals',
      'xlsx', 'en-CA', '{}', 'm4-export-csv-initial',
      'Conflict with existing CSV run', 'm4-export-conflict',
      '36200000-0000-4000-8000-000000000003'
    )
  $$,
  '23505',
  'export run idempotency conflict',
  'M4-EXP-AC-003 conflicting export replay fails closed'
);

select extensions.throws_ok(
  $$
    select * from app.m4_request_export_run(
      '10000000-0000-4000-8000-000000000001', 'fixture_deals',
      'csv', 'en-CA', '{}', 'm4-export-csv-initial',
      'A materially different audit reason', 'm4-export-reason-conflict',
      '36200000-0000-4000-8000-000000000003'
    )
  $$,
  '23505',
  'export run idempotency conflict',
  'M4-EXP-AC-003 export idempotency binds the normalized audit reason'
);

-- 10. Undeclared filters cannot alter an approved export query.
select extensions.throws_ok(
  $$
    select * from app.m4_request_export_run(
      '10000000-0000-4000-8000-000000000001', 'fixture_deals',
      'csv', 'en-CA', '{"provider_sql":"select *"}',
      'm4-export-unknown-filter', 'Reject undeclared export filter',
      'm4-export-unknown-filter', '36200000-0000-4000-8000-000000000004'
    )
  $$,
  '23514',
  'export filter is not declared',
  'M4-EXP-AC-001 approved filter schema fails closed'
);

select extensions.throws_ok(
  $$
    select * from app.m4_request_export_run(
      '10000000-0000-4000-8000-000000000001', 'fixture_deals',
      'csv', 'en-CA', '{"workflow_states":"draft"}',
      'm4-export-invalid-filter-type', 'Reject mistyped export filter',
      'm4-export-invalid-filter-type', '36200000-0000-4000-8000-000000000014'
    )
  $$,
  '23514',
  'export filters do not match the approved schema',
  'M4-EXP-AC-001 approved filter types and constraints are enforced'
);

select extensions.throws_ok(
  $$
    select * from app.m4_request_export_run(
      '10000000-0000-4000-8000-000000000001', 'fixture_deals',
      'csv', 'en-CA', '{"updated_from":"2026-07-16T12:30:00"}',
      'm4-export-offsetless-filter', 'Reject timezone-ambiguous export filter',
      'm4-export-offsetless-filter', '36200000-0000-4000-8000-000000000016'
    )
  $$,
  '23514',
  'export filters do not match the approved schema',
  'M4-EXP-AC-001 offset-less date-time filters fail closed regardless of session timezone'
);
reset role;
set local timezone to 'UTC';
savepoint reports_sort_permission_revocation;

set local role service_role;
update public.role_permissions assignment
set status = 'revoked',
    revoked_by = '31000000-0000-4000-8000-000000000001',
    revoked_at = pg_catalog.statement_timestamp()
from public.permissions permission
where assignment.workspace_id = '10000000-0000-4000-8000-000000000001'
  and assignment.role_id = '51000000-0000-4000-8000-000000000001'
  and assignment.permission_id = permission.id
  and permission.workspace_id is null
  and permission.key = 'reports.read';
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.m4_request_export_run(
      '10000000-0000-4000-8000-000000000001', 'fixture_deals',
      'csv', 'en-CA', '{}', 'm4-export-unauthorized-sort',
      'Reject an explicit sort whose column was removed by authorization',
      'm4-export-unauthorized-sort', '36200000-0000-4000-8000-000000000017'
    )
  $$,
  '42501',
  'export sort references an unauthorized column',
  'M4-EXP-AC-001 unauthorized explicit sort is rejected before enqueue'
);
reset role;
rollback to savepoint reports_sort_permission_revocation;
reset role;

-- Trusted writes cannot skip the durable export lifecycle or forge an outcome.
select extensions.throws_ok(
  $$
    update public.export_runs
    set status = 'generated'
    where id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
  $$,
  '23514',
  'invalid export run lifecycle transition',
  'M4-EXP-AC-003 export lifecycle guard rejects queued-to-generated forgery'
);

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.claimed_jobs
select
  'csv-initial', claimed.job_id, claimed.workspace_id,
  claimed.lease_token, claimed.correlation_id
from app.claim_jobs('m4-export-worker', 10, 300, array['exports.generate']) claimed
where claimed.job_id = (select job_id from pg_temp.export_results where phase = 'csv-initial');

-- 11. Active lease loads exact filters, authorized plan, sort, version, and row bound.
select extensions.ok(
  exists (
    select 1 from app.m4_load_export_run(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'm4-export-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial')
    ) loaded
    where loaded.source_key = 'deals' and loaded.requested_format = 'csv'
      and loaded.maximum_rows = 500 and loaded.definition_key = 'fixture_deals'
      and loaded.semantic_version = '1.0.0'
      and loaded.definition_checksum = repeat('6', 64)
      and loaded.sort_specification = '[
        {"direction":"asc","source":"deal.reference"},
        {"direction":"asc","opaque":true,"source":"__vynlo_source_id"}
      ]'::jsonb
  ),
  'M4-EXP-AC-003 worker receives only the immutable authorized run contract'
);

reset role;
savepoint export_job_payload_type_mismatch;
alter table public.jobs disable trigger jobs_immutable_fields;
update public.jobs job
set payload = pg_catalog.jsonb_set(
  job.payload, '{filters_checksum}', '1'::jsonb, false
)
where job.id = (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial');
alter table public.jobs enable trigger jobs_immutable_fields;
select pg_temp.authenticate_service();
set local role service_role;
select extensions.throws_ok(
  $$
    select * from app.m4_load_export_run(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'm4-export-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial')
    )
  $$,
  '23514',
  'export job snapshot is inconsistent',
  'M4-EXP-AC-003 export loader rejects a wrong-typed required payload key'
);
rollback to savepoint export_job_payload_type_mismatch;
select pg_temp.authenticate_service();
set local role service_role;

-- 12. A stale worker cannot load an export even with the current lease token.
select extensions.throws_ok(
  $$
    select * from app.m4_load_export_run(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'stale-export-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial')
    )
  $$,
  '55000',
  'export worker lease is invalid or expired',
  'T-JOB-002 export loader is lease-fenced'
);

-- First execution captures all selected source rows once. Every later page and
-- retry reads this append-only manifest rather than mutable operational tables.
insert into pg_temp.snapshot_pages
select 'initial', page.*
from app.m4_read_export_source_snapshot_page(
  '10000000-0000-4000-8000-000000000001',
  (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
  (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
  'm4-export-worker',
  (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial'),
  0, 500
) page;

select extensions.ok(
  exists (
    select 1 from pg_temp.snapshot_pages page
    where page.phase = 'initial'
      and page.source_snapshot_id is not null
      and page.source_row_count = pg_catalog.jsonb_array_length(page.source_rows)
  ),
  'T-EXP-001 export paging is pinned to one immutable source snapshot'
);

select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.m4_read_export_source_snapshot_page(uuid,uuid,uuid,text,uuid,integer,integer)'
      ::pg_catalog.regprocedure
  ) ~ 'select job\.\* into target_job[^;]+and job\.id = p_job_id;'
  and pg_catalog.pg_get_functiondef(
    'app.m4_read_export_source_snapshot_page(uuid,uuid,uuid,text,uuid,integer,integer)'
      ::pg_catalog.regprocedure
  ) ~ 'select job\.\* into target_job[^;]+and job\.id = p_job_id[[:space:]]+for update;'
  and pg_catalog.regexp_count(
    pg_catalog.pg_get_functiondef(
      'app.m4_read_export_source_snapshot_page(uuid,uuid,uuid,text,uuid,integer,integer)'
        ::pg_catalog.regprocedure
    ),
    'select job\.\* into target_job'
  ) = 2,
  'T-JOB-003 snapshot capture permits heartbeats and locks only for final lease fencing'
);

select extensions.ok(
  exists (
    select 1
    from pg_temp.snapshot_pages page
    cross join lateral pg_catalog.jsonb_array_elements(page.source_rows) source(source_record)
    where page.phase = 'initial'
      and source.source_record ->> 'id' = '36040000-0000-4000-8000-000000000002'
      and source.source_record #>> '{line_items,0,unit_amount_minor}' = '9007199254740993'
  ),
  'M4-EXP-AC-002 source snapshots transport bigint minor units as exact text'
);

reset role;

select extensions.throws_ok(
  $$
    update public.export_run_source_snapshot_rows
    set source_record = source_record || '{"tampered":true}'::jsonb
    where export_run_id = (
      select export_run_id from pg_temp.export_results where phase = 'csv-initial'
    )
      and row_ordinal = 1
  $$,
  '55000',
  'export_run_source_snapshot_rows is append-only',
  'T-EXP-001 captured export source rows cannot drift between pages or retries'
);

select pg_temp.authenticate_service();
set local role service_role;

insert into pg_temp.export_receipts
select
  'csv-initial', run.id, repeat('c', 64),
  run.workspace_id::text || '/exports/' || run.id::text
    || '/v1/' || repeat('c', 64) || '.csv',
  pg_catalog.jsonb_build_object(
    'storage', pg_catalog.jsonb_build_object(
      'bucket', 'exports-private',
      'objectKey', run.workspace_id::text || '/exports/' || run.id::text
        || '/v1/' || repeat('c', 64) || '.csv',
      'generation', 'fixture-export-generation-1', 'byteSize', 1024,
      'checksumSha256', repeat('c', 64)
    ),
    'exportVersionId', run.export_version_id,
    'filtersChecksum', job.payload ->> 'filters_checksum',
    'columnPlanChecksum', job.payload ->> 'column_plan_checksum',
    'sortPlanChecksum', job.payload ->> 'sort_plan_checksum',
    'sourceSnapshotId', snapshot.source_snapshot_id,
    'sourceSnapshotCapturedAt', snapshot.snapshot_captured_at,
    'sourceSnapshotFingerprint', snapshot.source_snapshot_fingerprint,
    'sourceSnapshotRowCount', snapshot.source_row_count
  )
from public.export_runs run
join public.export_run_jobs mapping
  on mapping.workspace_id = run.workspace_id and mapping.export_run_id = run.id
join public.jobs job on job.workspace_id = mapping.workspace_id and job.id = mapping.job_id
join pg_temp.snapshot_pages snapshot on snapshot.phase = 'initial'
where run.id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial');

-- 13. Completion rejects provider bytes that drift from the authorized run receipt.
select extensions.throws_ok(
  $$
    select * from app.m4_complete_export_run(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'm4-export-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'exports-private',
      (select object_path from pg_temp.export_receipts where phase = 'csv-initial'),
      'fixture-export-generation-1', 'fixture-deals.csv',
      'text/csv; charset=utf-8', 1024, repeat('c', 64),
      (select source_row_count::bigint from pg_temp.snapshot_pages where phase = 'initial'),
      (select receipt || '{"columnPlanChecksum":"drifted"}'::jsonb
       from pg_temp.export_receipts where phase = 'csv-initial'),
      'm4-export-drifted-receipt',
      '36200000-0000-4000-8000-000000000005'
    )
  $$,
  '23514',
  'export receipt does not match the authorized run',
  'M4-EXP-AC-002 authorized row/column receipt drift fails closed'
);

-- Empty objects cannot exploit SQL NULL semantics to bypass required keys.
select extensions.throws_ok(
  $$
    select * from app.m4_complete_export_run(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'm4-export-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'exports-private',
      (select object_path from pg_temp.export_receipts where phase = 'csv-initial'),
      'fixture-export-generation-1', 'fixture-deals.csv',
      'text/csv; charset=utf-8', 1024, repeat('c', 64),
      (select source_row_count::bigint from pg_temp.snapshot_pages where phase = 'initial'),
      '{}'::jsonb,
      'm4-export-empty-receipt',
      '36200000-0000-4000-8000-000000000050'
    )
  $$,
  '23514',
  'export receipt does not match the authorized run',
  'M4-EXP-AC-003 empty export completion receipt fails closed'
);

-- The source-manifest trigger independently rejects a partial receipt even
-- when all common storage and authorized-run fields remain present.
select extensions.throws_ok(
  $$
    select * from app.m4_complete_export_run(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'm4-export-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial'),
      'exports-private',
      (select object_path from pg_temp.export_receipts where phase = 'csv-initial'),
      'fixture-export-generation-1', 'fixture-deals.csv',
      'text/csv; charset=utf-8', 1024, repeat('c', 64),
      (select source_row_count::bigint from pg_temp.snapshot_pages where phase = 'initial'),
      (select receipt - 'sourceSnapshotFingerprint'
       from pg_temp.export_receipts where phase = 'csv-initial'),
      'm4-export-partial-receipt',
      '36200000-0000-4000-8000-000000000051'
    )
  $$,
  '23514',
  'export file receipt is not bound to its immutable source snapshot',
  'M4-EXP-AC-003 partial source snapshot receipt fails closed'
);

insert into pg_temp.export_file_results
select 'csv-initial', result.*
from app.m4_complete_export_run(
  '10000000-0000-4000-8000-000000000001',
  (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
  (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
  'm4-export-worker',
  (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial'),
  'exports-private',
  (select object_path from pg_temp.export_receipts where phase = 'csv-initial'),
  'fixture-export-generation-1', 'fixture-deals.csv',
  'text/csv; charset=utf-8', 1024, repeat('c', 64),
  (select source_row_count::bigint from pg_temp.snapshot_pages where phase = 'initial'),
  (select receipt from pg_temp.export_receipts where phase = 'csv-initial'),
  'm4-export-complete', '36200000-0000-4000-8000-000000000006'
) result;

-- 14. Matching completion records immutable file, row count, checksum, and expiry.
select extensions.ok(
  (select run_status from pg_temp.export_file_results where phase = 'csv-initial') = 'generated'
  and (select row_count from pg_temp.export_file_results where phase = 'csv-initial') =
    (select source_row_count::bigint from pg_temp.snapshot_pages where phase = 'initial')
  and exists (
    select 1 from public.export_files file
    where file.id = (select export_file_id from pg_temp.export_file_results where phase = 'csv-initial')
      and file.format = 'csv' and file.current and file.checksum = repeat('c', 64)
      and file.expires_at = (select expires_at from pg_temp.export_results where phase = 'csv-initial')
  ),
  'M4-EXP-AC-003 verified completion stores exact run evidence'
);

insert into pg_temp.export_file_results
select 'csv-replay', result.*
from app.m4_complete_export_run(
  '10000000-0000-4000-8000-000000000001',
  (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
  (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
  'm4-export-worker',
  (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial'),
  'exports-private',
  (select object_path from pg_temp.export_receipts where phase = 'csv-initial'),
  'fixture-export-generation-1', 'fixture-deals.csv',
  'text/csv; charset=utf-8', 1024, repeat('c', 64),
  (select source_row_count::bigint from pg_temp.snapshot_pages where phase = 'initial'),
  (select receipt from pg_temp.export_receipts where phase = 'csv-initial'),
  'm4-export-complete-replay', '36200000-0000-4000-8000-000000000006'
) result;

-- 15. Exact completion replay returns the same file without duplicating output.
select extensions.ok(
  (select export_file_id from pg_temp.export_file_results where phase = 'csv-replay')
    = (select export_file_id from pg_temp.export_file_results where phase = 'csv-initial')
  and (select replayed from pg_temp.export_file_results where phase = 'csv-replay')
  and (select pg_catalog.count(*) from public.export_files
       where export_run_id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')) = 1,
  'T-EXP-001 worker replay cannot duplicate an export file'
);
reset role;

-- 16. Export file coordinates and verification receipts are immutable.
select extensions.throws_ok(
  $$
    update public.export_files set storage_generation = 'rewritten'
    where id = (select export_file_id from pg_temp.export_file_results where phase = 'csv-initial')
  $$,
  '55000',
  'export_files is append-only',
  'M4-EXP-AC-003 completed export file is append-only'
);

select pg_temp.authenticate_service();
set local role service_role;
select extensions.ok(
  app.complete_job(
    (select job_id from pg_temp.claimed_jobs where phase = 'csv-initial'),
    'm4-export-worker',
    (select lease_token from pg_temp.claimed_jobs where phase = 'csv-initial'),
    pg_catalog.jsonb_build_object(
      'export_file_id',
      (select export_file_id from pg_temp.export_file_results where phase = 'csv-initial')
    ), null
  ),
  'T-JOB-001 generic runner settles the export job after domain completion'
);
reset role;

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001', 'aal2', 1000
);
set local role authenticated;

-- 18. Sensitive export download rechecks recent step-up.
select extensions.throws_ok(
  $$
    select * from app.m4_authorize_export_download(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
      'm4-export-download-stale', 120,
      'Attempt sensitive export download with stale assurance',
      'm4-export-download-stale',
      '36200000-0000-4000-8000-000000000007'
    )
  $$,
  '42501',
  'recent strong authentication is required',
  'T-EXP-002 sensitive download rejects stale assurance'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.download_results
select 'initial', result.*
from app.m4_authorize_export_download(
  '10000000-0000-4000-8000-000000000001',
  (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
  'm4-export-download-initial', 120,
  'Authorize rolled-back sensitive export download',
  'm4-export-download-initial',
  '36200000-0000-4000-8000-000000000008'
) result;

-- 19. Authorized response returns safe metadata and a short opaque grant only.
select extensions.ok(
  exists (
    select 1 from pg_temp.download_results result
    where result.phase = 'initial'
      and result.export_file_id = (
        select export_file_id from pg_temp.export_file_results where phase = 'csv-initial'
      )
      and result.checksum_sha256 = repeat('c', 64)
      and result.authorization_expires_at > pg_catalog.statement_timestamp()
      and result.authorization_expires_at <= pg_catalog.statement_timestamp() + interval '2 minutes 1 second'
      and not result.replayed
  ),
  'T-EXP-002 generated sensitive export returns bounded opaque authorization'
);

insert into pg_temp.download_results
select 'replay', result.*
from app.m4_authorize_export_download(
  '10000000-0000-4000-8000-000000000001',
  (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
  'm4-export-download-initial', 120,
  'Authorize rolled-back sensitive export download',
  'm4-export-download-replay',
  '36200000-0000-4000-8000-000000000008'
) result;

-- 20. Exact download replay returns the original authorization and audit evidence.
select extensions.ok(
  (select authorization_id from pg_temp.download_results where phase = 'replay')
    = (select authorization_id from pg_temp.download_results where phase = 'initial')
  and (select audit_event_id from pg_temp.download_results where phase = 'replay')
    = (select audit_event_id from pg_temp.download_results where phase = 'initial')
  and (select replayed from pg_temp.download_results where phase = 'replay'),
  'M4-EXP-AC-004 export download authorization is actor-idempotent'
);

-- 21. Opaque browser grant never permits direct provider-coordinate resolution.
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'app.m4_load_export_download_authorization(uuid)', 'EXECUTE'
  ),
  'M4-EXP-AC-004 browser cannot resolve export provider coordinates'
);
reset role;
savepoint reports_permission_revocation;

select pg_temp.authenticate_service();
set local role service_role;
update public.role_permissions assignment
set status = 'revoked',
    revoked_by = '31000000-0000-4000-8000-000000000001',
    revoked_at = pg_catalog.statement_timestamp()
from public.permissions permission
where assignment.workspace_id = '10000000-0000-4000-8000-000000000001'
  and assignment.role_id = '51000000-0000-4000-8000-000000000001'
  and assignment.permission_id = permission.id
  and permission.workspace_id is null
  and permission.key = 'reports.read';
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.m4_authorize_export_download(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'csv-initial'),
      'm4-export-download-revoked-column', 120,
      'Reject download after captured column permission revocation',
      'm4-export-download-revoked-column',
      '36200000-0000-4000-8000-000000000015'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-EXP-002 download reauthorizes every captured column permission'
);
reset role;
rollback to savepoint reports_permission_revocation;

select pg_temp.authenticate_service();
set local role service_role;

-- 22. Service resolution returns one exact unexpired provider receipt for byte verification.
select extensions.ok(
  exists (
    select 1 from app.m4_load_export_download_authorization(
      (select authorization_id from pg_temp.download_results where phase = 'initial')
    ) loaded
    where loaded.storage_bucket = 'exports-private'
      and loaded.storage_object_path = (
        select object_path from pg_temp.export_receipts where phase = 'csv-initial'
      )
      and loaded.checksum_sha256 = repeat('c', 64)
      and loaded.verification_receipt = (
        select receipt from pg_temp.export_receipts where phase = 'csv-initial'
      )
  ),
  'T-STOR-001 service verifies exact export bytes before signing a short URL'
);
reset role;

-- 23. Download authorization provenance is append-only.
select extensions.throws_ok(
  $$
    update public.export_download_authorizations
    set expires_at = expires_at + interval '1 minute'
    where id = (select authorization_id from pg_temp.download_results where phase = 'initial')
  $$,
  '55000',
  'export_download_authorizations is append-only',
  'M4-EXP-AC-004 download grant history cannot be rewritten'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.export_results
select 'xlsx-failure', result.*
from app.m4_request_export_run(
  '10000000-0000-4000-8000-000000000001', 'fixture_deals',
  'xlsx', 'fr-CA', '{}', 'm4-export-xlsx-failure',
  'Generate rolled-back XLSX failure fixture',
  'm4-export-xlsx-failure', '36200000-0000-4000-8000-000000000009'
) result;

-- 24. XLSX uses the same pinned definition while creating an independent run/job.
select extensions.ok(
  (select export_run_id from pg_temp.export_results where phase = 'xlsx-failure')
    <> (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
  and exists (
    select 1 from public.export_runs run
    where run.id = (select export_run_id from pg_temp.export_results where phase = 'xlsx-failure')
      and run.export_version_id = '36110000-0000-4000-8000-000000000001'
      and run.requested_format = 'xlsx'
      and run.authorized_column_plan = (
        select authorized_column_plan from public.export_runs
        where id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
      )
  ),
  'T-EXP-001 CSV/XLSX runs share exact authorized rows and columns'
);
reset role;

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.claimed_jobs
select
  'xlsx-failure', claimed.job_id, claimed.workspace_id,
  claimed.lease_token, claimed.correlation_id
from app.claim_jobs('m4-export-worker', 10, 300, array['exports.generate']) claimed
where claimed.job_id = (select job_id from pg_temp.export_results where phase = 'xlsx-failure');

-- Load transitions the run to running under the active lease.
do $load_failing_export$
begin
  perform * from app.m4_load_export_run(
    '10000000-0000-4000-8000-000000000001',
    (select export_run_id from pg_temp.export_results where phase = 'xlsx-failure'),
    (select job_id from pg_temp.claimed_jobs where phase = 'xlsx-failure'),
    'm4-export-worker',
    (select lease_token from pg_temp.claimed_jobs where phase = 'xlsx-failure')
  );
end;
$load_failing_export$;

-- 25. Domain failure handler validates the active lease but leaves settlement to the runner.
select extensions.results_eq(
  $$
    select run_status, job_status
    from app.m4_fail_export_run(
      '10000000-0000-4000-8000-000000000001',
      (select export_run_id from pg_temp.export_results where phase = 'xlsx-failure'),
      (select job_id from pg_temp.claimed_jobs where phase = 'xlsx-failure'),
      'm4-export-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'xlsx-failure'),
      'permanent', 'fixture.export_failed', 'Synthetic export generation failure', null,
      'm4-export-failure-validate',
      '36200000-0000-4000-8000-000000000010'
    )
  $$,
  $$values ('running'::text, 'running'::text)$$,
  'M4-EXP-AC-003 domain failure validation preserves one generic job settler'
);

do $settle_failed_export$
begin
  perform * from app.fail_job(
    (select job_id from pg_temp.claimed_jobs where phase = 'xlsx-failure'),
    'm4-export-worker',
    (select lease_token from pg_temp.claimed_jobs where phase = 'xlsx-failure'),
    'permanent', 'fixture.export_failed', 'Synthetic export generation failure', null, null
  );
end;
$settle_failed_export$;

-- 26. Generic dead-letter settlement synchronizes the export run and review state.
select extensions.results_eq(
  $$
    select run.status, run.failure_code, job.status, job.review_required
    from public.export_runs run
    join public.jobs job on job.workspace_id = run.workspace_id and job.entity_id = run.id
    where run.id = (select export_run_id from pg_temp.export_results where phase = 'xlsx-failure')
      and job.id = (select job_id from pg_temp.claimed_jobs where phase = 'xlsx-failure')
  $$,
  $$values ('dead_letter'::text, 'fixture.export_failed'::text, 'dead_letter'::text, true)$$,
  'T-JOB-003 failed export is durable and reviewable'
);
reset role;

-- 27. Export request, generation, download, and failure all emit audit evidence.
select extensions.ok(
  exists (
    select 1 from public.audit_events event
    where event.entity_id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
      and event.action = 'export.run_requested'
  )
  and exists (
    select 1 from public.audit_events event
    where event.entity_id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
      and event.action = 'export.run_generated'
  )
  and exists (
    select 1 from public.audit_events event
    where event.entity_id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
      and event.action = 'export.download_authorized'
  )
  and exists (
    select 1 from public.audit_events event
    where event.entity_id = (select export_run_id from pg_temp.export_results where phase = 'xlsx-failure')
      and event.action = 'export.run_failed'
  ),
  'T-AUD-001 export request, completion, download, and failure are audited'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 28. Browser cannot mutate visible export history directly.
select extensions.throws_ok(
  $$
    update public.export_runs set locale = 'fr-CA'
    where id = (select export_run_id from pg_temp.export_results where phase = 'csv-initial')
  $$,
  '42501',
  'permission denied for table export_runs',
  'T-RBAC-001 browser export access is command-only'
);

-- 29. Supplying a foreign workspace cannot cross the authoritative membership boundary.
select extensions.throws_ok(
  $$
    select * from app.m4_request_export_run(
      '20000000-0000-4000-8000-000000000002', 'fixture_deals',
      'csv', 'en-CA', '{}', 'm4-export-foreign-workspace',
      'Attempt foreign workspace export', 'm4-export-foreign-workspace',
      '36200000-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 export command derives workspace authority from membership'
);

-- 30. All four bounded core report functions are authenticated only.
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'app.m4_report_inventory_aging(uuid,timestamptz,uuid,date,date,integer,uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated', 'app.m4_report_inventory_gross(uuid,timestamptz,uuid,date,date,integer,uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated', 'app.m4_report_leads(uuid,timestamptz,uuid,date,date,integer,uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated', 'app.m4_report_deals(uuid,timestamptz,uuid,date,date,integer,uuid)', 'EXECUTE'
  ),
  'M4-EXP-AC-005 inventory, leads, and deals reports expose bounded authenticated contracts'
);

-- 31. Fractional line totals round independently before exact minor-unit summation.
select extensions.results_eq(
  $$
    select report.id, report.currency_code, report.total_amount_minor
    from app.m4_report_deals(
      '10000000-0000-4000-8000-000000000001', null, null, null, null, 50, null
    ) report
    where report.id = '36040000-0000-4000-8000-000000000001'
  $$,
  $$values ('36040000-0000-4000-8000-000000000001'::uuid, 'CAD'::text, '2'::text)$$,
  'M4-EXP-AC-002 report sums each rounded fractional line without binary floating point'
);

-- 32. Date filters deterministically exclude rows outside the requested interval.
select extensions.is(
  (
    select pg_catalog.count(*) from app.m4_report_deals(
      '10000000-0000-4000-8000-000000000001', null, null,
      date '2000-01-01', date '2000-01-02', 50, null
    ) report
    where report.id = '36040000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'T-API-002 report date filters are explicit and bounded'
);

-- 33. Cursor timestamp and ID must be supplied together.
select extensions.throws_ok(
  $$
    select * from app.m4_report_deals(
      '10000000-0000-4000-8000-000000000001',
      pg_catalog.statement_timestamp(), null, null, null, 50, null
    )
  $$,
  '22023',
  'report.query_invalid',
  'T-API-002 partial report cursor fails closed'
);

-- 34. Reversed date intervals fail with the stable report code.
select extensions.throws_ok(
  $$
    select * from app.m4_report_leads(
      '10000000-0000-4000-8000-000000000001', null, null,
      date '2026-07-17', date '2026-07-16', 50, null
    )
  $$,
  '22023',
  'report.query_invalid',
  'M4-EXP-AC-005 invalid report interval is rejected'
);

-- 35. Report page size is capped at 200 rows.
select extensions.throws_ok(
  $$
    select * from app.m4_report_inventory_aging(
      '10000000-0000-4000-8000-000000000001', null, null,
      null, null, 201, null
    )
  $$,
  '22023',
  'report.query_invalid',
  'T-API-002 report pagination limit is bounded'
);

-- 36. Report workspace spoofing is denied before any row is returned.
select extensions.throws_ok(
  $$
    select * from app.m4_report_inventory_gross(
      '20000000-0000-4000-8000-000000000002', null, null,
      null, null, 50, null
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-002 report workspace is verified from authenticated membership'
);

reset role;
select pg_temp.authenticate_service();
set local role service_role;
update public.export_versions
set status = 'retired',
    retired_by = '31000000-0000-4000-8000-000000000001',
    retired_at = pg_catalog.statement_timestamp()
where id = '36110000-0000-4000-8000-000000000001';
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  exists (
    select 1 from app.m4_request_export_run(
      '10000000-0000-4000-8000-000000000001', 'fixture_deals',
      'csv', 'en-CA', '{}', 'm4-export-csv-initial',
      'Generate rolled-back sensitive CSV fixture',
      'm4-export-replay-after-retirement',
      '36200000-0000-4000-8000-000000000016'
    ) replay
    where replay.export_run_id = (
      select export_run_id from pg_temp.export_results where phase = 'csv-initial'
    )
      and replay.replayed
  ),
  'M4-EXP-AC-003 exact idempotent replay precedes mutable activation and approval checks'
);

reset role;
select * from extensions.finish();
rollback;
