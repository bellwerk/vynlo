-- VYN-DOC-001, VYN-NUM-001, VYN-JOB-001, VYN-STOR-001,
-- VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- M4-DOC-AC-001..010, M4-NUM-AC-002..005 /
-- T-DOC-001..006, T-NUM-001..003, T-JOB-001..003,
-- T-STOR-001, T-TEN-001..003, T-RBAC-001, T-AUD-001.
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(82);

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

create temporary table pg_temp.document_results (
  phase text primary key,
  document_id uuid,
  official_number text,
  document_status text,
  number_allocation_id uuid,
  outbox_event_id uuid,
  job_id uuid,
  audit_event_id uuid,
  aggregate_version bigint,
  replayed boolean
);
create temporary table pg_temp.claimed_jobs (
  phase text primary key,
  job_id uuid,
  workspace_id uuid,
  lease_token uuid,
  correlation_id uuid
);
create temporary table pg_temp.render_receipts (
  phase text primary key,
  document_id uuid not null,
  job_id uuid not null,
  checksum text not null,
  object_path text not null,
  receipt jsonb not null
);
create temporary table pg_temp.file_results (
  phase text primary key,
  document_file_id uuid,
  document_status text,
  aggregate_version bigint,
  replayed boolean
);
create temporary table pg_temp.download_results (
  phase text primary key,
  authorization_id uuid,
  document_file_id uuid,
  document_id uuid,
  filename text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  authorization_expires_at timestamptz,
  audit_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.retry_results (
  phase text primary key,
  document_id uuid,
  document_status text,
  aggregate_version bigint,
  job_id uuid,
  job_status text,
  audit_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.void_results (
  phase text primary key,
  document_id uuid,
  document_status text,
  aggregate_version bigint,
  voided_at timestamptz,
  audit_event_id uuid,
  replayed boolean
);
grant all on
  pg_temp.document_results,
  pg_temp.claimed_jobs,
  pg_temp.render_receipts,
  pg_temp.file_results,
  pg_temp.download_results,
  pg_temp.retry_results,
  pg_temp.void_results
to authenticated, service_role;

-- A read-capable user without documents.preview proves the command checks the
-- immutable mutation permission rather than treating documents.read as write authority.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '35000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'm4-doc-reader@example.invalid',
  extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
  pg_catalog.statement_timestamp(),
  '{"provider":"email","providers":["email"]}', '{"fixture":true}',
  pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp(), '', '', '', ''
);
insert into public.workspace_memberships (
  id, workspace_id, user_id, status, invited_at, activated_at
) values (
  '35010000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '35000000-0000-4000-8000-000000000001', 'active',
  pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp()
);
insert into public.user_profiles (
  user_id, display_name, preferred_locale, status, last_workspace_id
) values (
  '35000000-0000-4000-8000-000000000001',
  'M4 document reader', 'en-CA', 'active',
  '10000000-0000-4000-8000-000000000001'
);
insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  '35020000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'm4_document_reader_035', 'M4 document reader', 'system', 'active', false
);
insert into public.role_permissions (workspace_id, role_id, permission_id, status)
select
  '10000000-0000-4000-8000-000000000001',
  '35020000-0000-4000-8000-000000000001', permission.id, 'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key = any(array[
    'documents.read', 'deals.read', 'crm.read', 'inventory.read'
  ]);
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '35030000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '35010000-0000-4000-8000-000000000001',
  '35020000-0000-4000-8000-000000000001', 'active'
);

-- This actor can generate an approved document but intentionally lacks the
-- independent documents.supersede capability.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '35000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'm4-doc-generator@example.invalid',
  extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
  pg_catalog.statement_timestamp(),
  '{"provider":"email","providers":["email"]}', '{"fixture":true}',
  pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp(), '', '', '', ''
);
insert into public.workspace_memberships (
  id, workspace_id, user_id, status, invited_at, activated_at
) values (
  '35010000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  '35000000-0000-4000-8000-000000000002', 'active',
  pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp()
);
insert into public.user_profiles (
  user_id, display_name, preferred_locale, status, last_workspace_id
) values (
  '35000000-0000-4000-8000-000000000002',
  'M4 document generator', 'en-CA', 'active',
  '10000000-0000-4000-8000-000000000001'
);
insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  '35020000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  'm4_document_generator_035', 'M4 document generator', 'system', 'active', false
);
insert into public.role_permissions (workspace_id, role_id, permission_id, status)
select
  '10000000-0000-4000-8000-000000000001',
  '35020000-0000-4000-8000-000000000002', permission.id, 'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key = any(array[
    'documents.generate_approved', 'documents.read', 'deals.read',
    'crm.read', 'inventory.read'
  ]);
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '35030000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  '35010000-0000-4000-8000-000000000002',
  '35020000-0000-4000-8000-000000000002', 'active'
);

-- A configured M3 deal gives preview and official snapshot builders a real,
-- workspace-owned authoritative aggregate. The insert trigger pins active
-- tenant-neutral starter deal/workflow versions.
insert into public.deals (
  id, workspace_id, deal_type_key, currency_code, owner_membership_id,
  notes, idempotency_key, command_fingerprint, created_by
) values (
  '35040000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001', 'retail.cash', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'Rolled-back M4 document fixture', 'm4-document-deal-fixture', repeat('1', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.deals (
  id, workspace_id, deal_type_key, currency_code, owner_membership_id,
  notes, idempotency_key, command_fingerprint, created_by
) values (
  '35040000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001', 'retail.cash', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'Rolled-back M4 evidence binding fixture',
  'm4-document-deal-binding-fixture', repeat('9', 64),
  '31000000-0000-4000-8000-000000000001'
);

-- Exact synthetic professional approvals for a production-shaped fixture.
insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
  artifact_checksum, approval_type, decision, decided_by,
  professional_role, professional_organization, conditions,
  attachment_reference, idempotency_key, reason
) values
  (
    '35120000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'numbering_definition', 'numbering.fixture_official', 1,
    '35110000-0000-4000-8000-000000000001', repeat('1', 64),
    'operational', 'approved', '31000000-0000-4000-8000-000000000001',
    'fixture_reviewer', 'Synthetic Review Lab', '{"fixture":true}',
    'fixture://numbering', 'm4-doc-numbering-approval',
    'Rolled-back synthetic numbering approval'
  ),
  (
    '35210000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'document_type', 'document.fixture_official', 1,
    '35200000-0000-4000-8000-000000000001', repeat('2', 64),
    'legal', 'approved', '31000000-0000-4000-8000-000000000001',
    'fixture_reviewer', 'Synthetic Review Lab', '{"fixture":true}',
    'fixture://document-type', 'm4-doc-type-approval',
    'Rolled-back synthetic document type approval'
  ),
  (
    '35310000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'document_template', 'template.fixture_official.en_ca', 1,
    '35300000-0000-4000-8000-000000000001', repeat('3', 64),
    'legal', 'approved', '31000000-0000-4000-8000-000000000001',
    'fixture_reviewer', 'Synthetic Review Lab', '{"fixture":true}',
    'fixture://template', 'm4-doc-template-approval',
    'Rolled-back synthetic template approval'
  ),
  (
    '35420000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'calculation', 'formula.fixture_total', 1,
    '35430000-0000-4000-8000-000000000001',
    app.m4_canonical_fingerprint(
      '{"key":"fixture_total","semantic_version":"1.0.0","input_schema":{"type":"object"},"output_schema":{"type":"object"},"expression_ast":{"type":"field","path":"subtotalMinor"},"rounding_policy":{"mode":"half_up","scale":0},"resource_limits":{"max_nodes":100},"fixtures":[],"engine_version":"fixture-calculation-v1"}'::jsonb
    ),
    'formula_review', 'approved', '31000000-0000-4000-8000-000000000001',
    'fixture_reviewer', 'Synthetic Review Lab', '{"fixture":true}',
    'fixture://calculation', 'm4-doc-calculation-approval',
    'Rolled-back synthetic calculation approval'
  );

-- Attach an exact immutable approval to the active deal workflow used by the
-- fixture deals. Starter workflows are activated by installation provenance,
-- so this rolled-back test setup supplies the stricter document dependency.
insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
  artifact_checksum, approval_type, decision, decided_by, conditions,
  idempotency_key, reason
)
select
  '35510000-0000-4000-8000-000000000001', workflow.workspace_id,
  'workflow_version', 'workflow.' || definition.key::text, workflow.revision,
  workflow.id, workflow.checksum, 'workflow.activation', 'approved',
  '31000000-0000-4000-8000-000000000001',
  pg_catalog.jsonb_build_object('fixture', true),
  'm4-doc-workflow-approval',
  'Rolled-back exact workflow approval for document dependency tests'
from public.deals deal
join public.workflow_versions workflow
  on workflow.workspace_id = deal.workspace_id
 and workflow.id = deal.workflow_version_id
join public.workflow_definitions definition
  on definition.workspace_id = workflow.workspace_id
 and definition.id = workflow.workflow_definition_id
where deal.workspace_id = '10000000-0000-4000-8000-000000000001'
  and deal.id = '35040000-0000-4000-8000-000000000001';

alter table public.workflow_versions
  disable trigger workflow_versions_protect_activated;
update public.workflow_versions workflow
set approval_record_id = approval.id,
    approved_by = approval.decided_by,
    approved_at = approval.decided_at
from public.approval_records approval,
     public.deals deal
where workflow.workspace_id = deal.workspace_id
  and workflow.id = deal.workflow_version_id
  and deal.id = '35040000-0000-4000-8000-000000000001'
  and approval.workspace_id = workflow.workspace_id
  and approval.id = '35510000-0000-4000-8000-000000000001';
alter table public.workflow_versions
  enable trigger workflow_versions_protect_activated;

insert into public.calculation_definitions (
  id, workspace_id, key, labels
) values (
  '35440000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture_total', '{"en":"Fixture total","fr":"Total fictif"}'
);

insert into public.calculation_versions (
  id, workspace_id, calculation_definition_id, version, semantic_version,
  status, input_schema, output_schema, expression_ast, rounding_policy,
  resource_limits, fixtures, engine_version, checksum, validation_evidence,
  fixture_evidence, approval_record_id, created_by, activated_by, activated_at
) values (
  '35430000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '35440000-0000-4000-8000-000000000001', 1, '1.0.0', 'draft',
  '{"type":"object"}', '{"type":"object"}',
  '{"type":"field","path":"subtotalMinor"}',
  '{"mode":"half_up","scale":0}', '{"max_nodes":100}', '[]',
  'fixture-calculation-v1',
  app.m4_canonical_fingerprint(
    '{"key":"fixture_total","semantic_version":"1.0.0","input_schema":{"type":"object"},"output_schema":{"type":"object"},"expression_ast":{"type":"field","path":"subtotalMinor"},"rounding_policy":{"mode":"half_up","scale":0},"resource_limits":{"max_nodes":100},"fixtures":[],"engine_version":"fixture-calculation-v1"}'::jsonb
  ),
  null, null, null,
  '31000000-0000-4000-8000-000000000001',
  null, null
);

update public.calculation_versions version
set status = 'validated',
    validation_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'validator', 'fixture-calculation-validator-v1',
      'artifactChecksum', version.checksum
    )
where version.id = '35430000-0000-4000-8000-000000000001';
update public.calculation_versions version
set status = 'test_passed',
    fixture_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'runner', 'fixture-calculation-runner-v1',
      'artifactChecksum', version.checksum,
      'tests', pg_catalog.jsonb_build_array('fixture-total')
    )
where version.id = '35430000-0000-4000-8000-000000000001';
update public.calculation_versions version
set status = 'approved',
    approval_record_id = '35420000-0000-4000-8000-000000000001'
where version.id = '35430000-0000-4000-8000-000000000001';
update public.calculation_versions version
set status = 'active',
    activated_by = '31000000-0000-4000-8000-000000000001',
    activated_at = pg_catalog.statement_timestamp()
where version.id = '35430000-0000-4000-8000-000000000001';

insert into public.numbering_definitions (
  id, workspace_id, key, labels
) values (
  '35100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001', 'fixture_official',
  '{"en":"Fixture official","fr":"Officiel fictif"}'
);
insert into public.numbering_definition_versions (
  id, workspace_id, numbering_definition_id, version, semantic_version,
  status, scope_type, prefix, suffix, numeric_width, starting_value,
  increment_by, reset_policy, timezone_name, format_pattern, import_policy,
  reuse_policy, allocation_event, checksum, validation_evidence,
  fixture_evidence, approval_record_id, created_by, activated_by, activated_at
) values (
  '35110000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '35100000-0000-4000-8000-000000000001', 1, '1.0.0', 'draft',
  'workspace', 'FX-', '', 6, 1, 1, 'never', 'UTC',
  '{{prefix}}{{sequence}}{{suffix}}', 'authorized_reservation', 'never',
  'official_document_created', repeat('1', 64), null, null, null,
  '31000000-0000-4000-8000-000000000001',
  null, null
);

update public.numbering_definition_versions version
set status = 'validated',
    validation_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'validator', 'fixture-numbering-validator-v1',
      'artifactChecksum', version.checksum
    )
where version.id = '35110000-0000-4000-8000-000000000001';
update public.numbering_definition_versions version
set status = 'test_passed',
    fixture_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'runner', 'fixture-numbering-runner-v1',
      'artifactChecksum', version.checksum,
      'tests', pg_catalog.jsonb_build_array('fixture-official-number')
    )
where version.id = '35110000-0000-4000-8000-000000000001';
update public.numbering_definition_versions version
set status = 'approved',
    approval_record_id = '35120000-0000-4000-8000-000000000001'
where version.id = '35110000-0000-4000-8000-000000000001';
update public.numbering_definition_versions version
set status = 'active',
    activated_by = '31000000-0000-4000-8000-000000000001',
    activated_at = pg_catalog.statement_timestamp()
where version.id = '35110000-0000-4000-8000-000000000001';

insert into public.document_types (
  id, workspace_id, key, version, display_name, labels, field_schema,
  field_schema_checksum, numbering_definition_version_id,
  calculation_version_id, workflow_version_id,
  preview_generation_enabled, official_generation_enabled,
  production_enabled, activation_status, activation_gates, checksum,
  fixture_evidence, approval_record_id, activated_at, status
) values (
  '35200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001', 'fixture.official', 1,
  'Fixture official document',
  '{"en":"Fixture official document","fr":"Document officiel fictif"}',
  '{"type":"object","additionalProperties":false,"properties":{"memo":{"type":"string"}},"required":["memo"]}',
  repeat('4', 64), '35110000-0000-4000-8000-000000000001',
  '35430000-0000-4000-8000-000000000001',
  (select deal.workflow_version_id from public.deals deal
   where deal.id = '35040000-0000-4000-8000-000000000001'),
  false, true, true, 'active', '[]', repeat('2', 64),
  '{"passed":true,"tests":["fixture-official-document"]}',
  '35210000-0000-4000-8000-000000000001',
  pg_catalog.statement_timestamp(), 'active'
);

insert into public.document_types (
  id, workspace_id, key, version, display_name, labels, field_schema,
  field_schema_checksum, workflow_version_id,
  preview_generation_enabled, official_generation_enabled,
  production_enabled, activation_status, activation_gates, checksum,
  fixture_evidence, status
)
select
  '35200000-0000-4000-8000-000000000002', deal.workspace_id,
  'fixture.preview_workflow', 1, 'Fixture workflow preview',
  '{"en":"Fixture workflow preview","fr":"Apercu de processus fictif"}',
  '{"type":"object","additionalProperties":false,"properties":{}}',
  repeat('6', 64), deal.workflow_version_id,
  true, false, false, 'test_passed', '[]', repeat('7', 64),
  '{"passed":true,"tests":["fixture-workflow-preview"]}', 'active'
from public.deals deal
where deal.id = '35040000-0000-4000-8000-000000000001';

insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_css, source_checksum, source_bundle_checksum,
  asset_manifest, font_manifest, renderer_version, field_schema,
  field_schema_checksum, production_approved, watermark, activation_status,
  fixture_evidence, approval_record_id, activated_at, status
) values (
  '35300000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '35200000-0000-4000-8000-000000000001', 1, 'en-CA',
  'tenant_approved',
  '<!doctype html><html><body><h1>{{ document.fields.memo }}</h1></body></html>',
  'body { font-family: sans-serif; }', repeat('5', 64), repeat('3', 64),
  '{}', '{}', 'fixture-pdf-v1',
  '{"type":"object","additionalProperties":false,"properties":{"memo":{"type":"string"}},"required":["memo"]}',
  repeat('4', 64), true, null, 'active',
  '{"passed":true,"tests":["fixture-template"]}',
  '35310000-0000-4000-8000-000000000001',
  pg_catalog.statement_timestamp(), 'active'
);

insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_css, source_checksum, source_bundle_checksum,
  asset_manifest, font_manifest, renderer_version, field_schema,
  field_schema_checksum, production_approved, watermark, activation_status,
  fixture_evidence, status
) values (
  '35300000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  '35200000-0000-4000-8000-000000000002', 1, 'en-CA',
  'synthetic_non_production',
  '<!doctype html><html><body><h1>Workflow preview</h1></body></html>',
  'body { font-family: sans-serif; }', repeat('8', 64), repeat('9', 64),
  '{}', '{}', 'fixture-pdf-v1',
  '{"type":"object","additionalProperties":false,"properties":{}}',
  repeat('6', 64), false, 'DRAFT / NON-PRODUCTION', 'test_passed',
  '{"passed":true,"tests":["fixture-workflow-preview-template"]}', 'active'
);

-- 1. Documents, preview/render mappings, attempts, commands, files, and grants are forced-RLS.
select extensions.is(
  (
    select pg_catalog.count(*) from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'documents', 'document_files', 'document_preview_jobs',
        'document_render_jobs',
        'document_render_attempts', 'document_commands',
        'document_file_download_authorizations'
      ])
      and relation.relrowsecurity and relation.relforcerowsecurity
  ),
  7::bigint,
  'M4-DOC-AC-001 document lifecycle tables enforce forced RLS'
);

-- 2. Browser-safe file reads exclude provider coordinates and verification receipts.
select extensions.ok(
  not pg_catalog.has_column_privilege(
    'authenticated', 'public.document_files', 'storage_bucket', 'SELECT'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated', 'public.document_files', 'storage_object_path', 'SELECT'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated', 'public.document_files', 'verification_receipt', 'SELECT'
  ),
  'M4-DOC-AC-010 authenticated file projection never exposes provider coordinates'
);

-- 3. Preview and official commands are exposed, while worker loaders remain service-only.
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.m4_request_document_preview(uuid,text,uuid,uuid,uuid,text,date,date,jsonb,jsonb,jsonb,text,uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'app.request_official_document(uuid,text,uuid,uuid,uuid,text,date,date,jsonb,jsonb,jsonb,uuid,bigint,text,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app.m4_load_official_document_render(uuid,uuid,uuid,text,uuid)',
    'EXECUTE'
  ),
  'T-RBAC-001 user commands and worker-only render boundary have narrow grants'
);

select pg_temp.authenticate_as('35000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 4. A read-only actor cannot enqueue a preview without documents.preview.
select extensions.throws_ok(
  $$
    select * from app.m4_request_document_preview(
      '10000000-0000-4000-8000-000000000001', 'm4-preview-readonly-denied',
      '35040000-0000-4000-8000-000000000001',
      '81000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
      null, '{}', null, null, 'm4-preview-readonly-denied',
      '35400000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-RBAC-001 preview mutation requires its immutable permission key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.document_results
select 'preview-initial', result.*
from app.m4_request_document_preview(
  '10000000-0000-4000-8000-000000000001', 'm4-preview-initial-035',
  '35040000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
  null, '{}', null, null, 'm4-preview-initial-035',
  '35400000-0000-4000-8000-000000000002'
) result;

-- 5. Preview request atomically creates one queued document/job/outbox mapping.
select extensions.results_eq(
  $$select official_number, document_status, number_allocation_id, replayed
    from pg_temp.document_results where phase = 'preview-initial'$$,
  $$values (null::text, 'queued'::text, null::uuid, false)$$,
  'T-DOC-001 preview is queued, unnumbered, and non-official'
);

-- 6. Preview consumes no permanent allocation.
select extensions.is(
  (select pg_catalog.count(*) from public.number_allocations),
  0::bigint,
  'M4-DOC-AC-003 preview never consumes an official number'
);

-- 7. Preview pins the exact type/template/renderer snapshot and watermark.
select extensions.ok(
  exists (
    select 1 from public.documents document
    where document.id = (
      select document_id from pg_temp.document_results where phase = 'preview-initial'
    )
      and document.mode = 'preview'
      and document.watermark = 'DRAFT / NON-PRODUCTION'
      and document.version_snapshot ?& array[
        'documentTypeId', 'documentTypeChecksum', 'templateVersionId',
        'templateBundleChecksum', 'rendererVersion'
      ]
      and document.version_snapshot_checksum ~ '^[a-f0-9]{64}$'
  ),
  'M4-DOC-AC-003 preview preserves exact immutable rendering inputs'
);

insert into pg_temp.document_results
select 'preview-replay', result.*
from app.m4_request_document_preview(
  '10000000-0000-4000-8000-000000000001', 'm4-preview-initial-035',
  '35040000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
  null, '{}', null, null, 'm4-preview-replay-035',
  '35400000-0000-4000-8000-000000000002'
) result;

-- 8. Exact preview replay returns the original document and durable job.
select extensions.ok(
  (select document_id from pg_temp.document_results where phase = 'preview-replay')
    = (select document_id from pg_temp.document_results where phase = 'preview-initial')
  and (select job_id from pg_temp.document_results where phase = 'preview-replay')
    = (select job_id from pg_temp.document_results where phase = 'preview-initial')
  and (select replayed from pg_temp.document_results where phase = 'preview-replay'),
  'M4-DOC-AC-003 preview request is actor-idempotent'
);

insert into pg_temp.document_results
select 'preview-regenerated', result.*
from app.m4_request_document_preview(
  '10000000-0000-4000-8000-000000000001', 'm4-preview-workflow-035',
  '35040000-0000-4000-8000-000000000001',
  '35200000-0000-4000-8000-000000000002',
  '35300000-0000-4000-8000-000000000002', 'en-CA', date '2026-07-16',
  null, '{}', null, null, 'm4-preview-workflow-035',
  '35400000-0000-4000-8000-000000000003'
) result;

-- 9. A fresh key regenerates a preview with the exact approved deal workflow.
select extensions.ok(
  (select document_id from pg_temp.document_results where phase = 'preview-regenerated')
    <> (select document_id from pg_temp.document_results where phase = 'preview-initial')
  and (select official_number from pg_temp.document_results where phase = 'preview-regenerated') is null
  and (select pg_catalog.count(*) from public.number_allocations) = 0
  and exists (
    select 1
    from public.documents document
    join public.workflow_versions workflow
      on workflow.workspace_id = document.workspace_id
     and workflow.id = document.workflow_version_id
    where document.id = (
      select document_id from pg_temp.document_results
      where phase = 'preview-regenerated'
    )
      and document.render_input_snapshot -> 'deal' ->> 'workflow_version_id'
        = workflow.id::text
      and document.version_snapshot @> pg_catalog.jsonb_build_object(
        'schemaVersion', 3,
        'workflowVersionId', workflow.id,
        'workflowVersion', workflow.version,
        'workflowRevision', workflow.revision,
        'workflowChecksum', workflow.checksum
      )
  ),
  'T-DOC-001 preview remains unnumbered and pins its exact approved workflow'
);

savepoint preview_workflow_mismatch;
reset role;
alter table public.document_types disable trigger document_types_immutable;
update public.document_types document_type
set workflow_version_id = (
  select workflow.id
  from public.workflow_versions workflow
  where workflow.workspace_id = document_type.workspace_id
    and workflow.status = 'active'
    and workflow.id is distinct from (
      select deal.workflow_version_id
      from public.deals deal
      where deal.workspace_id = document_type.workspace_id
        and deal.id = '35040000-0000-4000-8000-000000000001'
    )
  order by workflow.id
  limit 1
)
where document_type.id = '35200000-0000-4000-8000-000000000002';
do $assert_mismatched_workflow_fixture$
begin
  if (
    select document_type.workflow_version_id
    from public.document_types document_type
    where document_type.id = '35200000-0000-4000-8000-000000000002'
  ) is null then
    raise exception 'mismatched active workflow fixture is unavailable';
  end if;
end;
$assert_mismatched_workflow_fixture$;
alter table public.document_types enable trigger document_types_immutable;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 9a. A type cannot preview a deal pinned to another workflow version.
select extensions.throws_ok(
  $$
    select * from app.m4_request_document_preview(
      '10000000-0000-4000-8000-000000000001', 'm4-preview-workflow-mismatch',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000002',
      '35300000-0000-4000-8000-000000000002', 'en-CA', date '2026-07-16',
      null, '{}', null, null, 'm4-preview-workflow-mismatch',
      '35400000-0000-4000-8000-000000000010'
    )
  $$,
  '23514',
  'document.preview_workflow_mismatch',
  'M4-DOC-AC-004 preview rejects a document workflow that differs from the deal'
);
reset role;
rollback to savepoint preview_workflow_mismatch;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

savepoint preview_workflow_retired;
reset role;
update public.workflow_versions workflow
set status = 'retired',
    retired_at = pg_catalog.statement_timestamp()
where workflow.id = (
  select document_type.workflow_version_id
  from public.document_types document_type
  where document_type.id = '35200000-0000-4000-8000-000000000002'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 9b. A retired workflow cannot be used for a new preview.
select extensions.throws_ok(
  $$
    select * from app.m4_request_document_preview(
      '10000000-0000-4000-8000-000000000001', 'm4-preview-workflow-retired',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000002',
      '35300000-0000-4000-8000-000000000002', 'en-CA', date '2026-07-16',
      null, '{}', null, null, 'm4-preview-workflow-retired',
      '35400000-0000-4000-8000-000000000011'
    )
  $$,
  '23514',
  'document.preview_workflow_inactive',
  'M4-DOC-AC-004 preview rejects a retired workflow version'
);
reset role;
rollback to savepoint preview_workflow_retired;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

savepoint preview_workflow_revoked;
reset role;
insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
  artifact_checksum, approval_type, decision, decided_by, conditions,
  supersedes_approval_id, idempotency_key, reason
)
select
  '35510000-0000-4000-8000-000000000002', approval.workspace_id,
  approval.artifact_type, approval.artifact_key, approval.artifact_version,
  approval.artifact_id, approval.artifact_checksum, approval.approval_type,
  'revoked', '31000000-0000-4000-8000-000000000001',
  pg_catalog.jsonb_build_object('fixture', true), approval.id,
  'm4-doc-workflow-revocation',
  'Rolled-back revocation for document dependency tests'
from public.approval_records approval
where approval.id = '35510000-0000-4000-8000-000000000001';
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 9c. An append-only revocation invalidates the formerly exact approval.
select extensions.throws_ok(
  $$
    select * from app.m4_request_document_preview(
      '10000000-0000-4000-8000-000000000001', 'm4-preview-workflow-revoked',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000002',
      '35300000-0000-4000-8000-000000000002', 'en-CA', date '2026-07-16',
      null, '{}', null, null, 'm4-preview-workflow-revoked',
      '35400000-0000-4000-8000-000000000012'
    )
  $$,
  '23514',
  'document.preview_workflow_approval_invalid',
  'M4-DOC-AC-004 preview rejects a revoked exact workflow approval'
);
reset role;
rollback to savepoint preview_workflow_revoked;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 10. The compatibility-only synthetic template can never be used officially.
select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001', 'm4-official-synthetic-denied',
      '35040000-0000-4000-8000-000000000001',
      '81000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
      null, '{}', null, null, null, null, 'Attempt synthetic official output',
      'm4-official-synthetic-denied',
      '35400000-0000-4000-8000-000000000004'
    )
  $$,
  '23514',
  'document.official_missing_document_type_approval',
  'M4-DOC-AC-004 production-disabled placeholders fail closed'
);

-- 11. A client assertion is not accepted in place of a trusted runtime receipt.
select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001', 'm4-official-fake-receipt',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
      null, '{"memo":"Fixture"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000001"}', null,
      null, null, 'Reject forged runtime evidence', 'm4-official-fake-receipt',
      '35400000-0000-4000-8000-000000000005'
    )
  $$,
  '23514',
  'document.official_calculation_receipt_invalid',
  'M4-DOC-AC-004 official generation consumes trusted receipts only'
);

-- 12. Type, template, and numbering fixture approvals match exact IDs and checksums.
select extensions.ok(
  exists (
    select 1 from public.approval_records approval
    where approval.id = '35210000-0000-4000-8000-000000000001'
      and approval.artifact_type = 'document_type'
      and approval.artifact_key = 'document.fixture_official'
      and approval.artifact_id = '35200000-0000-4000-8000-000000000001'
      and approval.artifact_checksum = repeat('2', 64)
      and approval.decision = 'approved'
  )
  and exists (
    select 1 from public.approval_records approval
    where approval.id = '35310000-0000-4000-8000-000000000001'
      and approval.artifact_type = 'document_template'
      and approval.artifact_key = 'template.fixture_official.en_ca'
      and approval.artifact_id = '35300000-0000-4000-8000-000000000001'
      and approval.artifact_checksum = repeat('3', 64)
      and approval.decision = 'approved'
  ),
  'M4-DOC-AC-004 synthetic official fixture has exact rolled-back approvals'
);

reset role;
with definition as (
  select
    '{"key":"fixture_total","semantic_version":"1.0.0","input_schema":{"type":"object"},"output_schema":{"type":"object"},"expression_ast":{"type":"field","path":"subtotalMinor"},"rounding_policy":{"mode":"half_up","scale":0},"resource_limits":{"max_nodes":100},"fixtures":[],"engine_version":"fixture-calculation-v1"}'::jsonb as value
), deal_context as (
  select
    app.m4_deal_source_snapshot(
      '10000000-0000-4000-8000-000000000001',
      '35040000-0000-4000-8000-000000000001'
    ) as value
), unsigned_evidence as (
  select pg_catalog.jsonb_build_object(
    'versionId', '35430000-0000-4000-8000-000000000001',
    'definitionKey', 'fixture_total',
    'definitionVersion', '1.0.0',
    'definitionChecksum', app.m4_canonical_fingerprint(definition.value),
    'engineVersion', 'fixture-calculation-v1',
    'definition', definition.value,
    'input', deal_context.value,
    'inputBinding', pg_catalog.jsonb_build_object(
      'mapperVersion', 'deal-runtime-input-v1',
      'dealContextChecksum', app.m4_canonical_fingerprint(deal_context.value),
      'inputProjectionChecksum', app.m4_canonical_fingerprint(deal_context.value)
    ),
    'output', pg_catalog.jsonb_build_object('totalMinor', '10000'),
    'components', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('key', 'subtotal', 'amountMinor', '10000')
    ),
    'taxComponents', '[]'::jsonb,
    'rounding', pg_catalog.jsonb_build_object('mode', 'half_up', 'scale', 0)
  ) as value
  from definition
  cross join deal_context
), evidence as (
  select value || pg_catalog.jsonb_build_object(
    'checksum', app.m4_canonical_fingerprint(value)
  ) as value
  from unsigned_evidence
)
insert into public.runtime_evidence_records (
  id, workspace_id, evidence_type, calculation_version_id, deal_id,
  deal_context_checksum, snapshot, snapshot_checksum, actor_user_id,
  idempotency_key, command_fingerprint, created_at, expires_at,
  official_eligible
)
select
  '35410000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001', 'calculation',
  '35430000-0000-4000-8000-000000000001',
  '35040000-0000-4000-8000-000000000001',
  app.m4_canonical_fingerprint(app.m4_deal_source_snapshot(
    '10000000-0000-4000-8000-000000000001',
    '35040000-0000-4000-8000-000000000001'
  )),
  evidence.value, evidence.value ->> 'checksum',
  '31000000-0000-4000-8000-000000000001',
  'm4-doc-bound-calculation', repeat('e', 64),
  pg_catalog.statement_timestamp(),
  pg_catalog.statement_timestamp() + interval '5 seconds', true
from evidence;

-- Malformed-binding, foreign-actor, and expired copies exercise validation's
-- fail-closed receipt lookup without mutating the one valid receipt.
with source as (
  select evidence.*
  from public.runtime_evidence_records evidence
  where evidence.id = '35410000-0000-4000-8000-000000000002'
), unsigned as (
  select (source.snapshot - 'checksum') || pg_catalog.jsonb_build_object(
    'inputBinding', (source.snapshot -> 'inputBinding')
      || pg_catalog.jsonb_build_object('dealContextChecksum', repeat('0', 64))
  ) as value,
  source.*
  from source
), signed as (
  select unsigned.*, value || pg_catalog.jsonb_build_object(
    'checksum', app.m4_canonical_fingerprint(value)
  ) as changed_snapshot
  from unsigned
)
insert into public.runtime_evidence_records (
  id, workspace_id, evidence_type, calculation_version_id, deal_id,
  deal_context_checksum, snapshot, snapshot_checksum, actor_user_id,
  idempotency_key, command_fingerprint, created_at, expires_at,
  official_eligible
)
select
  '35410000-0000-4000-8000-000000000004', workspace_id, evidence_type,
  calculation_version_id, deal_id, deal_context_checksum, changed_snapshot,
  changed_snapshot ->> 'checksum', actor_user_id,
  'm4-doc-invalid-input-binding', repeat('4', 64), created_at, expires_at,
  official_eligible
from signed;

insert into public.runtime_evidence_records (
  id, workspace_id, evidence_type, calculation_version_id, deal_id,
  deal_context_checksum, snapshot, snapshot_checksum, actor_user_id,
  idempotency_key, command_fingerprint, created_at, expires_at,
  official_eligible
)
select
  '35410000-0000-4000-8000-000000000005', workspace_id, evidence_type,
  calculation_version_id, deal_id, deal_context_checksum, snapshot,
  snapshot_checksum, '35000000-0000-4000-8000-000000000002',
  'm4-doc-foreign-actor-receipt', repeat('5', 64), created_at, expires_at,
  official_eligible
from public.runtime_evidence_records
where id = '35410000-0000-4000-8000-000000000002';

insert into public.runtime_evidence_records (
  id, workspace_id, evidence_type, calculation_version_id, deal_id,
  deal_context_checksum, snapshot, snapshot_checksum, actor_user_id,
  idempotency_key, command_fingerprint, created_at, expires_at,
  official_eligible
)
select
  '35410000-0000-4000-8000-000000000006', workspace_id, evidence_type,
  calculation_version_id, deal_id, deal_context_checksum, snapshot,
  snapshot_checksum, actor_user_id, 'm4-doc-expired-receipt', repeat('6', 64),
  pg_catalog.statement_timestamp() - interval '2 hours',
  pg_catalog.statement_timestamp() - interval '1 hour', official_eligible
from public.runtime_evidence_records
where id = '35410000-0000-4000-8000-000000000002';

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- Validation and submission apply identical ownership, deal, expiry, and
-- canonical-input gates to the opaque calculation receipt.
select extensions.ok(
  (select calculation_ready from app.m4_validate_document(
    '10000000-0000-4000-8000-000000000001',
    '35040000-0000-4000-8000-000000000001',
    '35200000-0000-4000-8000-000000000001',
    '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
    null, '{"memo":"Fixture"}',
    '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
  ))
  and not (select calculation_ready from app.m4_validate_document(
    '10000000-0000-4000-8000-000000000001',
    '35040000-0000-4000-8000-000000000002',
    '35200000-0000-4000-8000-000000000001',
    '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
    null, '{"memo":"Fixture"}',
    '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
  ))
  and not (select calculation_ready from app.m4_validate_document(
    '10000000-0000-4000-8000-000000000001',
    '35040000-0000-4000-8000-000000000001',
    '35200000-0000-4000-8000-000000000001',
    '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
    null, '{"memo":"Fixture"}',
    '{"evidenceId":"35410000-0000-4000-8000-000000000004"}', null
  ))
  and not (select calculation_ready from app.m4_validate_document(
    '10000000-0000-4000-8000-000000000001',
    '35040000-0000-4000-8000-000000000001',
    '35200000-0000-4000-8000-000000000001',
    '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
    null, '{"memo":"Fixture"}',
    '{"evidenceId":"35410000-0000-4000-8000-000000000005"}', null
  ))
  and not (select calculation_ready from app.m4_validate_document(
    '10000000-0000-4000-8000-000000000001',
    '35040000-0000-4000-8000-000000000001',
    '35200000-0000-4000-8000-000000000001',
    '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
    null, '{"memo":"Fixture"}',
    '{"evidenceId":"35410000-0000-4000-8000-000000000006"}', null
  )),
  'M4-DOC-AC-004 validation rejects cross-deal, forged, foreign, and expired receipts'
);

-- 12a. Live validation uses the same exact approvals as official submission.
select extensions.ok(
  (
    select validation.document_type_ready
      and validation.template_ready
      and validation.numbering_ready
      and validation.calculation_ready
      and validation.tax_ready
      and validation.official_ready
    from app.m4_validate_document(
      '10000000-0000-4000-8000-000000000001',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001',
      'en-CA', date '2026-07-16', null,
      '{"memo":"Fixture official one"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
    ) validation
  ),
  'M4-DOC-AC-004 validation reports exact type template and numbering readiness'
);

-- Validation and the direct command reject the same impossible signature
-- chronology before a permanent number or durable side effect can exist.
select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001', 'm4-official-invalid-date',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
      date '2026-07-15', '{"memo":"Invalid signature chronology"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null,
      null, null, 'Reject impossible signature chronology',
      'm4-official-invalid-date',
      '35400000-0000-4000-8000-000000000020'
    )
  $$,
  '23514',
  'document.date_invalid',
  'M4-DOC-AC-004 direct issuance rejects the validation date blocker'
);

select extensions.ok(
  not exists (
    select 1 from public.documents document
    where document.idempotency_key = 'm4-official-invalid-date'
  )
  and not exists (
    select 1 from public.outbox_events event
    where event.correlation_id = '35400000-0000-4000-8000-000000000020'
  )
  and (select pg_catalog.count(*) from public.number_allocations) = 0,
  'M4-NUM-AC-002 invalid dates consume no document, official number, or outbox event'
);

savepoint validate_retired_calculation;
reset role;
update public.calculation_versions
set status = 'retired',
    retired_by = '31000000-0000-4000-8000-000000000001',
    retired_at = pg_catalog.statement_timestamp()
where id = '35430000-0000-4000-8000-000000000001';
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

select extensions.ok(
  (
    select not validation.calculation_ready
      and not validation.official_ready
      and validation.errors @>
        array['document.calculation_version_unavailable']::text[]
    from app.m4_validate_document(
      '10000000-0000-4000-8000-000000000001',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001',
      'en-CA', date '2026-07-16', null,
      '{"memo":"Retired calculation"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
    ) validation
  ),
  'M4-CALC-AC-004 retired calculation versions block validation explicitly'
);

select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001', 'm4-official-retired-calc',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
      null, '{"memo":"Retired calculation"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null,
      null, null, 'Reject retired calculation version',
      'm4-official-retired-calc',
      '35400000-0000-4000-8000-000000000021'
    )
  $$,
  '23514',
  'document.official_calculation_version_unapproved',
  'M4-CALC-AC-004 issuance and validation both require an active calculation'
);
reset role;
rollback to savepoint validate_retired_calculation;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

savepoint validate_deal_scope;
reset role;
update public.locations location
set status = 'inactive'
where location.id = (
  select deal.location_id from public.deals deal
  where deal.id = '35040000-0000-4000-8000-000000000001'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

select extensions.ok(
  (
    select not validation.official_ready
      and validation.errors @> array['document.deal_scope_unavailable']::text[]
    from app.m4_validate_document(
      '10000000-0000-4000-8000-000000000001',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001',
      'en-CA', date '2026-07-16', null,
      '{"memo":"Inactive scope"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
    ) validation
  ),
  'M4-DOC-AC-004 validation rejects an inactive deal location'
);

select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001', 'm4-official-inactive-scope',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
      null, '{"memo":"Inactive scope"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null,
      null, null, 'Reject inactive deal scope',
      'm4-official-inactive-scope',
      '35400000-0000-4000-8000-000000000022'
    )
  $$,
  '23514',
  'document.official_deal_scope_unavailable',
  'M4-DOC-AC-004 issuance and validation require the same active deal scope'
);
reset role;
rollback to savepoint validate_deal_scope;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

savepoint validate_type_approval_revoked;
reset role;
insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
  artifact_checksum, approval_type, decision, decided_by, conditions,
  supersedes_approval_id, idempotency_key, reason
)
select
  '35600000-0000-4000-8000-000000000001', approval.workspace_id,
  approval.artifact_type, approval.artifact_key, approval.artifact_version,
  approval.artifact_id, approval.artifact_checksum, approval.approval_type,
  'revoked', '31000000-0000-4000-8000-000000000001', '{"fixture":true}',
  approval.id, 'm4-validate-type-revoked',
  'Rolled-back validation type approval revocation'
from public.approval_records approval
where approval.id = '35210000-0000-4000-8000-000000000001';
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 12b. Revoking the exact type approval immediately removes readiness.
select extensions.ok(
  (
    select not validation.document_type_ready
      and validation.template_ready
      and validation.numbering_ready
      and not validation.official_ready
      and validation.errors @> array['document.type_approval_invalid']::text[]
    from app.m4_validate_document(
      '10000000-0000-4000-8000-000000000001',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001',
      'en-CA', date '2026-07-16', null,
      '{"memo":"Fixture official one"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
    ) validation
  ),
  'M4-DOC-AC-004 validation fails closed on revoked document type approval'
);
reset role;
rollback to savepoint validate_type_approval_revoked;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

savepoint validate_template_approval_revoked;
reset role;
insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
  artifact_checksum, approval_type, decision, decided_by, conditions,
  supersedes_approval_id, idempotency_key, reason
)
select
  '35600000-0000-4000-8000-000000000002', approval.workspace_id,
  approval.artifact_type, approval.artifact_key, approval.artifact_version,
  approval.artifact_id, approval.artifact_checksum, approval.approval_type,
  'revoked', '31000000-0000-4000-8000-000000000001', '{"fixture":true}',
  approval.id, 'm4-validate-template-revoked',
  'Rolled-back validation template approval revocation'
from public.approval_records approval
where approval.id = '35310000-0000-4000-8000-000000000001';
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 12c. Revoking the exact template approval cannot leave template readiness true.
select extensions.ok(
  (
    select validation.document_type_ready
      and not validation.template_ready
      and validation.numbering_ready
      and not validation.official_ready
      and validation.errors @> array['document.template_approval_invalid']::text[]
    from app.m4_validate_document(
      '10000000-0000-4000-8000-000000000001',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001',
      'en-CA', date '2026-07-16', null,
      '{"memo":"Fixture official one"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
    ) validation
  ),
  'M4-DOC-AC-004 validation fails closed on revoked template approval'
);
reset role;
rollback to savepoint validate_template_approval_revoked;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

savepoint validate_numbering_approval_revoked;
reset role;
insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
  artifact_checksum, approval_type, decision, decided_by, conditions,
  supersedes_approval_id, idempotency_key, reason
)
select
  '35600000-0000-4000-8000-000000000003', approval.workspace_id,
  approval.artifact_type, approval.artifact_key, approval.artifact_version,
  approval.artifact_id, approval.artifact_checksum, approval.approval_type,
  'revoked', '31000000-0000-4000-8000-000000000001', '{"fixture":true}',
  approval.id, 'm4-validate-numbering-revoked',
  'Rolled-back validation numbering approval revocation'
from public.approval_records approval
where approval.id = '35120000-0000-4000-8000-000000000001';
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 12d. Active status alone cannot substitute for exact numbering approval.
select extensions.ok(
  (
    select validation.document_type_ready
      and validation.template_ready
      and not validation.numbering_ready
      and not validation.official_ready
      and validation.errors @> array['document.numbering_unavailable']::text[]
      and validation.warnings @> array['document.numbering_unavailable']::text[]
    from app.m4_validate_document(
      '10000000-0000-4000-8000-000000000001',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001',
      'en-CA', date '2026-07-16', null,
      '{"memo":"Fixture official one"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
    ) validation
  ),
  'M4-NUM-AC-001 validation fails closed on revoked numbering approval'
);
reset role;
rollback to savepoint validate_numbering_approval_revoked;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 13. A trusted receipt is bound to the authoritative deal snapshot it evaluated.
select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001', 'm4-official-wrong-deal-receipt',
      '35040000-0000-4000-8000-000000000002',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
      null, '{"memo":"Wrong deal receipt"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null,
      null, null, 'Reject a receipt evaluated for another deal',
      'm4-official-wrong-deal-receipt',
      '35400000-0000-4000-8000-000000000015'
    )
  $$,
  '23514',
  'document.official_calculation_receipt_invalid',
  'M4-DOC-AC-004 runtime evidence is deal and source-checksum bound'
);

insert into pg_temp.document_results
select 'official-initial', result.*
from app.request_official_document(
  '10000000-0000-4000-8000-000000000001', 'm4-official-initial-035',
  '35040000-0000-4000-8000-000000000001',
  '35200000-0000-4000-8000-000000000001',
  '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
  null, '{"memo":"Fixture official one"}',
  '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null,
  null, null,
  'Issue first rolled-back official fixture', 'm4-official-initial-035',
  '35400000-0000-4000-8000-000000000006'
) result;

-- Once issuance consumes the opaque receipt, validation immediately reports
-- the same one-time-use failure that a second non-replay submission would.
select extensions.ok(
  exists (
    select 1 from app.m4_validate_document(
      '10000000-0000-4000-8000-000000000001',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
      null, '{"memo":"Fixture official one"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null
    ) validation
    where not validation.calculation_ready
      and validation.errors @> array['document.calculation_missing']::text[]
  ),
  'M4-DOC-AC-004 validation rejects an already-consumed runtime receipt'
);

-- 14. Official request allocates one permanent number and enters generating.
select extensions.ok(
  (select official_number from pg_temp.document_results where phase = 'official-initial') = 'FX-000001'
  and (select document_status from pg_temp.document_results where phase = 'official-initial') = 'generating'
  and (select number_allocation_id from pg_temp.document_results where phase = 'official-initial') is not null
  and not (select replayed from pg_temp.document_results where phase = 'official-initial'),
  'T-DOC-002 official generation allocates one permanent number'
);

-- 15. Document, allocation, outbox, durable job, mapping, and initial attempt commit together.
select extensions.ok(
  exists (
    select 1 from public.number_allocations allocation
    where allocation.id = (
      select number_allocation_id from pg_temp.document_results where phase = 'official-initial'
    )
  )
  and exists (
    select 1 from public.outbox_events event
    where event.id = (
      select outbox_event_id from pg_temp.document_results where phase = 'official-initial'
    )
      and event.event_name = 'document.official_requested'
  )
  and exists (
    select 1 from public.jobs job
    where job.id = (
      select job_id from pg_temp.document_results where phase = 'official-initial'
    )
      and job.job_type = 'documents.render_pdf'
      and job.status = 'queued'
  )
  and exists (
    select 1 from public.document_render_jobs mapping
    where mapping.document_id = (
      select document_id from pg_temp.document_results where phase = 'official-initial'
    )
      and mapping.job_id = (
        select job_id from pg_temp.document_results where phase = 'official-initial'
      )
  )
  and exists (
    select 1 from public.document_render_attempts attempt
    where attempt.document_id = (
      select document_id from pg_temp.document_results where phase = 'official-initial'
    ) and attempt.attempt_number = 1
  ),
  'M4-DOC-AC-004 authoritative document and durable render state commit atomically'
);

-- 16. Official snapshot pins every exact source/version/checksum used for rendering.
select extensions.ok(
  exists (
    select 1
    from public.documents document
    join public.workflow_versions workflow
      on workflow.workspace_id = document.workspace_id
     and workflow.id = document.workflow_version_id
    where document.id = (
      select document_id from pg_temp.document_results where phase = 'official-initial'
    )
      and document.version_snapshot @> pg_catalog.jsonb_build_object(
        'schemaVersion', 3,
        'documentTypeId', '35200000-0000-4000-8000-000000000001',
        'documentTypeChecksum', repeat('2', 64),
        'templateVersionId', '35300000-0000-4000-8000-000000000001',
        'templateBundleChecksum', repeat('3', 64),
        'numberingVersionId', '35110000-0000-4000-8000-000000000001',
        'numberingChecksum', repeat('1', 64),
        'workflowVersionId', workflow.id,
        'workflowVersion', workflow.version,
        'workflowRevision', workflow.revision,
        'workflowChecksum', workflow.checksum,
        'calculationVersionId', '35430000-0000-4000-8000-000000000001',
        'calculationEvidenceId', '35410000-0000-4000-8000-000000000002',
        'rendererVersion', 'fixture-pdf-v1'
      )
      and document.render_input_snapshot -> 'deal' ->> 'workflow_version_id'
        = workflow.id::text
      and document.version_snapshot ?& array[
        'calculationVersionId', 'calculationChecksum', 'calculationEvidenceId',
        'taxPackVersionId', 'taxPackChecksum', 'taxEvidenceId'
      ]
  ),
  'M4-DOC-AC-004 immutable official snapshot includes exact nullable dependency slots'
);

do $wait_for_runtime_receipt_expiry$
begin
  perform pg_catalog.pg_sleep(5.1);
end;
$wait_for_runtime_receipt_expiry$;

insert into pg_temp.document_results
select 'official-replay', result.*
from app.request_official_document(
  '10000000-0000-4000-8000-000000000001', 'm4-official-initial-035',
  '35040000-0000-4000-8000-000000000001',
  '35200000-0000-4000-8000-000000000001',
  '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-16',
  null, '{"memo":"Fixture official one"}',
  '{"evidenceId":"35410000-0000-4000-8000-000000000002"}', null,
  null, null,
  'Issue first rolled-back official fixture', 'm4-official-replay-035',
  '35400000-0000-4000-8000-000000000006'
) result;

reset role;

-- 17. Official replay returns the same document after its one-time receipt expires.
select extensions.ok(
  (select document_id from pg_temp.document_results where phase = 'official-replay')
    = (select document_id from pg_temp.document_results where phase = 'official-initial')
  and (select official_number from pg_temp.document_results where phase = 'official-replay')
    = (select official_number from pg_temp.document_results where phase = 'official-initial')
  and (select job_id from pg_temp.document_results where phase = 'official-replay')
    = (select job_id from pg_temp.document_results where phase = 'official-initial')
  and (select replayed from pg_temp.document_results where phase = 'official-replay')
  and (select expires_at from public.runtime_evidence_records
       where id = '35410000-0000-4000-8000-000000000002')
      < pg_catalog.statement_timestamp()
  and (select pg_catalog.count(*) from public.runtime_evidence_consumptions
       where evidence_id = '35410000-0000-4000-8000-000000000002') = 1,
  'M4-NUM-AC-003 official replay precedes expiry checks and cannot consume twice'
);

-- 17. Preview and official replays leave exactly one official allocation.
select extensions.is(
  (select pg_catalog.count(*) from public.number_allocations),
  1::bigint,
  'T-NUM-003 permanent allocation count is unchanged by document replays'
);

-- 18. Completion and coordinate loaders are executable only by service_role.
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.m4_complete_official_document_render(uuid,uuid,uuid,text,uuid,text,text,text,bigint,text,text,jsonb,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app.m4_complete_official_document_render(uuid,uuid,uuid,text,uuid,text,text,text,bigint,text,text,jsonb,text,uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'service_role', 'app.m4_load_document_file_download_authorization(uuid)', 'EXECUTE'
  ),
  'M4-DOC-AC-005 worker completion and coordinate resolution are service-only'
);

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.claimed_jobs
select
  'official-initial', claimed.job_id, claimed.workspace_id,
  claimed.lease_token, claimed.correlation_id
from app.claim_jobs('m4-doc-worker', 10, 300, array['documents.render_pdf']) claimed
where claimed.job_id = (
  select job_id from pg_temp.document_results where phase = 'official-initial'
);

-- 19. An active lease loads the exact immutable official render contract.
select extensions.ok(
  exists (
    select 1 from app.m4_load_official_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
      'm4-doc-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial')
    ) loaded
    where loaded.official_number = 'FX-000001'
      and loaded.renderer_version = 'fixture-pdf-v1'
      and loaded.version_snapshot_checksum = (
        select version_snapshot_checksum from public.documents
        where id = (select document_id from pg_temp.document_results where phase = 'official-initial')
      )
  ),
  'M4-DOC-AC-005 lease-fenced loader returns pinned source and input checksums'
);

reset role;
savepoint official_job_payload_omission;
alter table public.jobs disable trigger jobs_immutable_fields;
update public.jobs job
set payload = job.payload - 'render_input_checksum'
where job.id = (select job_id from pg_temp.claimed_jobs where phase = 'official-initial');
alter table public.jobs enable trigger jobs_immutable_fields;
select pg_temp.authenticate_service();
set local role service_role;
select extensions.throws_ok(
  $$
    select * from app.m4_load_official_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
      'm4-doc-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial')
    )
  $$,
  '23514',
  'official render snapshot or job linkage is invalid',
  'M4-DOC-AC-005 official loader rejects a missing required job payload key'
);
rollback to savepoint official_job_payload_omission;
select pg_temp.authenticate_service();
set local role service_role;

insert into pg_temp.render_receipts
select
  'official-initial', document.id,
  (select job_id from pg_temp.document_results where phase = 'official-initial'),
  repeat('a', 64),
  document.workspace_id::text || '/documents/' || document.id::text
    || '/generated_original/v1/' || repeat('a', 64) || '.pdf',
  pg_catalog.jsonb_build_object(
    'storage', pg_catalog.jsonb_build_object(
      'bucket', 'documents-private',
      'objectKey', document.workspace_id::text || '/documents/' || document.id::text
        || '/generated_original/v1/' || repeat('a', 64) || '.pdf',
      'generation', 'fixture-generation-1', 'byteSize', 2048,
      'checksumSha256', repeat('a', 64)
    ),
    'renderer', pg_catalog.jsonb_build_object('version', document.renderer_version),
    'officialNumber', document.official_number,
    'sourceBundleChecksum', document.version_snapshot ->> 'templateBundleChecksum',
    'renderInputChecksum', document.render_input_checksum,
    'versionSnapshotChecksum', document.version_snapshot_checksum
  )
from public.documents document
where document.id = (select document_id from pg_temp.document_results where phase = 'official-initial');

-- 20. A stale worker identity cannot publish a generated original.
select extensions.throws_ok(
  $$
    select * from app.m4_complete_official_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
      'stale-doc-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial'),
      'documents-private',
      (select object_path from pg_temp.render_receipts where phase = 'official-initial'),
      'fixture-generation-1', 2048, repeat('a', 64), 'fixture-pdf-v1',
      (select receipt from pg_temp.render_receipts where phase = 'official-initial'),
      'm4-official-stale-worker',
      '35400000-0000-4000-8000-000000000007'
    )
  $$,
  '55000',
  'only the active official render lease may complete',
  'M4-DOC-AC-005 stale worker completion is lease-fenced'
);

-- 21. Provider receipt drift is rejected against the immutable source/input snapshot.
select extensions.throws_ok(
  $$
    select * from app.m4_complete_official_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
      'm4-doc-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial'),
      'documents-private',
      (select object_path from pg_temp.render_receipts where phase = 'official-initial'),
      'fixture-generation-1', 2048, repeat('a', 64), 'fixture-pdf-v1',
      (select receipt || '{"renderInputChecksum":"drifted"}'::jsonb
       from pg_temp.render_receipts where phase = 'official-initial'),
      'm4-official-drifted-receipt',
      '35400000-0000-4000-8000-000000000008'
    )
  $$,
  '23514',
  'official render receipt does not match the immutable snapshot',
  'M4-DOC-AC-005 source or storage receipt drift fails closed'
);

-- Empty objects cannot exploit SQL NULL semantics to bypass required keys.
select extensions.throws_ok(
  $$
    select * from app.m4_complete_official_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
      'm4-doc-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial'),
      'documents-private',
      (select object_path from pg_temp.render_receipts where phase = 'official-initial'),
      'fixture-generation-1', 2048, repeat('a', 64), 'fixture-pdf-v1',
      '{}'::jsonb,
      'm4-official-empty-receipt',
      '35400000-0000-4000-8000-000000000050'
    )
  $$,
  '23514',
  'official render receipt does not match the immutable snapshot',
  'M4-DOC-AC-005 empty official render receipt fails closed'
);

-- A nearly valid receipt still fails when any immutable binding is absent.
select extensions.throws_ok(
  $$
    select * from app.m4_complete_official_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
      'm4-doc-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial'),
      'documents-private',
      (select object_path from pg_temp.render_receipts where phase = 'official-initial'),
      'fixture-generation-1', 2048, repeat('a', 64), 'fixture-pdf-v1',
      (select receipt - 'versionSnapshotChecksum'
       from pg_temp.render_receipts where phase = 'official-initial'),
      'm4-official-partial-receipt',
      '35400000-0000-4000-8000-000000000051'
    )
  $$,
  '23514',
  'official render receipt does not match the immutable snapshot',
  'M4-DOC-AC-005 partial official render receipt fails closed'
);

insert into pg_temp.file_results
select 'official-initial', result.*
from app.m4_complete_official_document_render(
  '10000000-0000-4000-8000-000000000001',
  (select document_id from pg_temp.document_results where phase = 'official-initial'),
  (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
  'm4-doc-worker',
  (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial'),
  'documents-private',
  (select object_path from pg_temp.render_receipts where phase = 'official-initial'),
  'fixture-generation-1', 2048, repeat('a', 64), 'fixture-pdf-v1',
  (select receipt from pg_temp.render_receipts where phase = 'official-initial'),
  'm4-official-complete', '35400000-0000-4000-8000-000000000009'
) result;

-- 22. Matching receipt appends one generated-original file and marks the document generated.
select extensions.ok(
  (select document_status from pg_temp.file_results where phase = 'official-initial') = 'generated'
  and exists (
    select 1 from public.document_files file
    where file.id = (select document_file_id from pg_temp.file_results where phase = 'official-initial')
      and file.role = 'generated_original' and file.version = 1 and file.current
      and file.checksum = repeat('a', 64)
      and file.storage_generation = 'fixture-generation-1'
  ),
  'M4-DOC-AC-005 verified completion creates immutable generated original'
);

insert into pg_temp.file_results
select 'official-initial-replay', result.*
from app.m4_complete_official_document_render(
  '10000000-0000-4000-8000-000000000001',
  (select document_id from pg_temp.document_results where phase = 'official-initial'),
  (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
  'm4-doc-worker',
  (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial'),
  'documents-private',
  (select object_path from pg_temp.render_receipts where phase = 'official-initial'),
  'fixture-generation-1', 2048, repeat('a', 64), 'fixture-pdf-v1',
  (select receipt from pg_temp.render_receipts where phase = 'official-initial'),
  'm4-official-complete-replay', '35400000-0000-4000-8000-000000000009'
) result;

-- 23. Exact completion replay returns the same file without another aggregate transition.
select extensions.ok(
  (select document_file_id from pg_temp.file_results where phase = 'official-initial-replay')
    = (select document_file_id from pg_temp.file_results where phase = 'official-initial')
  and (select replayed from pg_temp.file_results where phase = 'official-initial-replay')
  and (select aggregate_version from pg_temp.file_results where phase = 'official-initial-replay')
    = (select aggregate_version from pg_temp.file_results where phase = 'official-initial'),
  'T-DOC-003 renderer replay cannot duplicate official files'
);
reset role;

-- 24. Generated file bytes and provenance cannot be rewritten.
select extensions.throws_ok(
  $$
    update public.document_files set checksum = repeat('b', 64)
    where id = (select document_file_id from pg_temp.file_results where phase = 'official-initial')
  $$,
  '23514',
  'document_files.checksum is immutable',
  'M4-DOC-AC-005 generated-original content is immutable'
);

select pg_temp.authenticate_service();
set local role service_role;
select extensions.ok(
  app.complete_job(
    (select job_id from pg_temp.claimed_jobs where phase = 'official-initial'),
    'm4-doc-worker',
    (select lease_token from pg_temp.claimed_jobs where phase = 'official-initial'),
    pg_catalog.jsonb_build_object(
      'document_file_id',
      (select document_file_id from pg_temp.file_results where phase = 'official-initial')
    ),
    null
  ),
  'T-JOB-001 durable runner remains the sole generic job settler'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 25. Mark-signed cannot advance without an independently verified signed scan.
select extensions.throws_ok(
  $$
    select * from app.m4_mark_document_signed(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select aggregate_version from public.documents where id = (
        select document_id from pg_temp.document_results where phase = 'official-initial'
      )),
      'm4-mark-signed-without-scan', 'Require verified signed scan',
      'm4-mark-signed-without-scan',
      '35400000-0000-4000-8000-000000000010'
    )
  $$,
  '23514',
  'verified signed file and generated official document are required',
  'M4-DOC-AC-007 signed lifecycle requires a current immutable signed scan'
);

insert into pg_temp.download_results
select 'initial', result.*
from app.m4_authorize_document_file_download(
  '10000000-0000-4000-8000-000000000001',
  (select document_file_id from pg_temp.file_results where phase = 'official-initial'),
  'm4-document-download-initial', 120,
  'Authorize rolled-back generated document download',
  'm4-document-download-initial',
  '35400000-0000-4000-8000-000000000011'
) result;

-- 26. Authenticated download response contains safe identity, checksum, and bounded expiry only.
select extensions.ok(
  exists (
    select 1 from pg_temp.download_results result
    where result.phase = 'initial'
      and result.document_id = (
        select document_id from pg_temp.document_results where phase = 'official-initial'
      )
      and result.checksum_sha256 = repeat('a', 64)
      and result.authorization_expires_at > pg_catalog.statement_timestamp()
      and result.authorization_expires_at <= pg_catalog.statement_timestamp() + interval '2 minutes 1 second'
      and not result.replayed
  ),
  'T-STOR-001 document download authorization is opaque and short-lived'
);

insert into pg_temp.download_results
select 'replay', result.*
from app.m4_authorize_document_file_download(
  '10000000-0000-4000-8000-000000000001',
  (select document_file_id from pg_temp.file_results where phase = 'official-initial'),
  'm4-document-download-initial', 120,
  'Authorize rolled-back generated document download',
  'm4-document-download-replay',
  '35400000-0000-4000-8000-000000000011'
) result;

-- 27. Exact download replay returns the same authorization and audit evidence.
select extensions.ok(
  (select authorization_id from pg_temp.download_results where phase = 'replay')
    = (select authorization_id from pg_temp.download_results where phase = 'initial')
  and (select audit_event_id from pg_temp.download_results where phase = 'replay')
    = (select audit_event_id from pg_temp.download_results where phase = 'initial')
  and (select replayed from pg_temp.download_results where phase = 'replay'),
  'M4-DOC-AC-010 download authorization is actor-idempotent'
);

-- 28. Browser cannot resolve provider coordinates even after receiving an opaque authorization.
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'app.m4_load_document_file_download_authorization(uuid)', 'EXECUTE'
  ),
  'M4-DOC-AC-010 opaque authorization does not grant coordinate-loader access'
);
reset role;

select pg_temp.authenticate_service();
set local role service_role;
-- 29. Service loader resolves the one exact, unexpired file receipt for byte verification.
select extensions.ok(
  exists (
    select 1 from app.m4_load_document_file_download_authorization(
      (select authorization_id from pg_temp.download_results where phase = 'initial')
    ) loaded
    where loaded.storage_bucket = 'documents-private'
      and loaded.storage_object_path = (
        select object_path from pg_temp.render_receipts where phase = 'official-initial'
      )
      and loaded.checksum_sha256 = repeat('a', 64)
      and loaded.verification_receipt = (
        select receipt from pg_temp.render_receipts where phase = 'official-initial'
      )
  ),
  'M4-DOC-AC-010 service verifies exact provider bytes before signing a short URL'
);
reset role;

insert into public.runtime_evidence_records (
  id, workspace_id, evidence_type, calculation_version_id, deal_id,
  deal_context_checksum, snapshot, snapshot_checksum, actor_user_id,
  idempotency_key, command_fingerprint, created_at, expires_at,
  official_eligible
)
select
  '35410000-0000-4000-8000-000000000003', workspace_id, evidence_type,
  calculation_version_id, deal_id, deal_context_checksum, snapshot,
  snapshot_checksum, actor_user_id, 'm4-doc-supersede-calculation',
  repeat('d', 64), pg_catalog.statement_timestamp(),
  pg_catalog.statement_timestamp() + interval '30 seconds', official_eligible
from public.runtime_evidence_records
where id = '35410000-0000-4000-8000-000000000002';

select pg_temp.authenticate_as('35000000-0000-4000-8000-000000000002');
set local role authenticated;

-- Generation authority does not implicitly grant supersession authority.
select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001', 'm4-official-supersede-denied',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-17',
      null, '{"memo":"Unauthorized correction"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000003"}', null,
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select aggregate_version from public.documents where id = (
        select document_id from pg_temp.document_results where phase = 'official-initial'
      )),
      'Attempt supersession without its immutable permission',
      'm4-official-supersede-denied',
      '35400000-0000-4000-8000-000000000016'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'M4-DOC-AC-009 supersession requires documents.supersede independently'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- A stale expected aggregate cannot start a replacement render.
select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001', 'm4-official-supersede-stale',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-17',
      null, '{"memo":"Stale correction"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000003"}', null,
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select aggregate_version + 1 from public.documents where id = (
        select document_id from pg_temp.document_results where phase = 'official-initial'
      )),
      'Attempt supersession from a stale aggregate',
      'm4-official-supersede-stale',
      '35400000-0000-4000-8000-000000000017'
    )
  $$,
  '40001',
  'document.aggregate_version_conflict',
  'M4-DOC-AC-009 replacement creation uses optimistic concurrency'
);

insert into pg_temp.document_results
select 'official-superseding', result.*
from app.request_official_document(
  '10000000-0000-4000-8000-000000000001', 'm4-official-superseding-035',
  '35040000-0000-4000-8000-000000000001',
  '35200000-0000-4000-8000-000000000001',
  '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-17',
  null, '{"memo":"Fixture official corrected"}',
  '{"evidenceId":"35410000-0000-4000-8000-000000000003"}', null,
  (select document_id from pg_temp.document_results where phase = 'official-initial'),
  (select aggregate_version from public.documents where id = (
    select document_id from pg_temp.document_results where phase = 'official-initial'
  )),
  'Issue corrected document and supersede the original',
  'm4-official-superseding-035',
  '35400000-0000-4000-8000-000000000012'
) result;

-- 30. Changed official data creates a new document and a distinct permanent number.
select extensions.ok(
  (select document_id from pg_temp.document_results where phase = 'official-superseding')
    <> (select document_id from pg_temp.document_results where phase = 'official-initial')
  and (select official_number from pg_temp.document_results where phase = 'official-superseding')
    = 'FX-000002'
  and (select official_number from pg_temp.document_results where phase = 'official-superseding')
    <> (select official_number from pg_temp.document_results where phase = 'official-initial'),
  'T-DOC-004 superseding correction allocates a new permanent number'
);

-- 31. Requesting a replacement preserves the usable original until verification succeeds.
select extensions.ok(
  exists (
    select 1 from public.documents original
    where original.id = (select document_id from pg_temp.document_results where phase = 'official-initial')
      and original.status = 'generated'
      and original.superseded_by_document_id is null
  )
  and exists (
    select 1 from public.documents replacement
    where replacement.id = (
      select document_id from pg_temp.document_results where phase = 'official-superseding'
    )
      and replacement.supersedes_document_id = (
        select document_id from pg_temp.document_results where phase = 'official-initial'
      )
  )
  and exists (
    select 1 from public.document_files file
    where file.id = (select document_file_id from pg_temp.file_results where phase = 'official-initial')
      and file.current and file.checksum = repeat('a', 64)
  ),
  'M4-DOC-AC-009 replacement request does not prematurely supersede the original'
);
reset role;

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.claimed_jobs
select
  'official-superseding', claimed.job_id, claimed.workspace_id,
  claimed.lease_token, claimed.correlation_id
from app.claim_jobs('m4-doc-worker', 10, 300, array['documents.render_pdf']) claimed
where claimed.job_id = (
  select job_id from pg_temp.document_results where phase = 'official-superseding'
);

-- 32. Domain failure validation leaves settlement ownership with the durable runner.
select extensions.results_eq(
  $$
    select document_status, job_status
    from app.m4_fail_official_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-superseding'),
      (select job_id from pg_temp.claimed_jobs where phase = 'official-superseding'),
      'm4-doc-worker',
      (select lease_token from pg_temp.claimed_jobs where phase = 'official-superseding'),
      'permanent', 'fixture.render_failed', 'Synthetic renderer failure', null,
      'm4-official-failure-validate',
      '35400000-0000-4000-8000-000000000013'
    )
  $$,
  $$values ('generating'::text, 'running'::text)$$,
  'M4-DOC-AC-006 domain handler validates failure while the runner retains the active lease'
);

do $settle_failed_render$
begin
  perform * from app.fail_job(
    (select job_id from pg_temp.claimed_jobs where phase = 'official-superseding'),
    'm4-doc-worker',
    (select lease_token from pg_temp.claimed_jobs where phase = 'official-superseding'),
    'permanent', 'fixture.render_failed', 'Synthetic renderer failure', null, null
  );
end;
$settle_failed_render$;

-- 33. Generic dead-letter settlement synchronizes the document to generation_failed.
select extensions.results_eq(
  $$
    select document.status, document.failure_code, job.status, job.review_required
    from public.documents document
    join public.jobs job on job.workspace_id = document.workspace_id and job.entity_id = document.id
    where document.id = (
      select document_id from pg_temp.document_results where phase = 'official-superseding'
    ) and job.id = (
      select job_id from pg_temp.claimed_jobs where phase = 'official-superseding'
    )
  $$,
  $$values ('generation_failed'::text, 'fixture.render_failed'::text, 'dead_letter'::text, true)$$,
  'T-JOB-003 durable settlement makes render failure reviewable'
);

-- 34. Render failure changes no official number, input, or exact version checksum.
select extensions.ok(
  exists (
    select 1 from public.documents document
    where document.id = (
      select document_id from pg_temp.document_results where phase = 'official-superseding'
    )
      and document.official_number = (
        select official_number from pg_temp.document_results where phase = 'official-superseding'
      )
      and document.render_input_checksum = (
        select job.payload ->> 'render_input_checksum'
        from public.jobs job
        where job.id = (select job_id from pg_temp.claimed_jobs where phase = 'official-superseding')
      )
      and document.version_snapshot_checksum = (
        select job.payload ->> 'version_snapshot_checksum'
        from public.jobs job
        where job.id = (select job_id from pg_temp.claimed_jobs where phase = 'official-superseding')
      )
  )
  and exists (
    select 1 from public.documents original
    where original.id = (select document_id from pg_temp.document_results where phase = 'official-initial')
      and original.status = 'generated'
      and original.superseded_by_document_id is null
  )
  and exists (
    select 1 from public.document_files file
    where file.id = (select document_file_id from pg_temp.file_results where phase = 'official-initial')
      and file.current
  ),
  'M4-DOC-AC-006 failed replacement retains its exact snapshot while the original remains usable'
);
reset role;

-- A permanently failed replacement must not strand the otherwise usable
-- prior document. The existing void command is the audited recovery boundary:
-- it preserves the failed artifact and number while releasing only its active
-- successor claim.
savepoint failed_supersession_recovery;
insert into public.runtime_evidence_records (
  id, workspace_id, evidence_type, calculation_version_id, deal_id,
  deal_context_checksum, snapshot, snapshot_checksum, actor_user_id,
  idempotency_key, command_fingerprint, created_at, expires_at,
  official_eligible
)
select
  seed.id, evidence.workspace_id, evidence.evidence_type,
  evidence.calculation_version_id, evidence.deal_id,
  evidence.deal_context_checksum, evidence.snapshot,
  evidence.snapshot_checksum, evidence.actor_user_id,
  seed.idempotency_key, seed.command_fingerprint,
  pg_catalog.statement_timestamp(),
  pg_catalog.statement_timestamp() + interval '30 seconds',
  evidence.official_eligible
from public.runtime_evidence_records evidence
cross join (
  values
    (
      '35410000-0000-4000-8000-000000000007'::uuid,
      'm4-doc-recovery-calculation', pg_catalog.repeat('e', 64)
    ),
    (
      '35410000-0000-4000-8000-000000000008'::uuid,
      'm4-doc-recovery-conflict-calculation', pg_catalog.repeat('f', 64)
    )
) seed(id, idempotency_key, command_fingerprint)
where evidence.id = '35410000-0000-4000-8000-000000000002';

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.void_results
select 'failed-initial', result.*
from app.m4_void_document(
  '10000000-0000-4000-8000-000000000001',
  (select document_id from pg_temp.document_results where phase = 'official-superseding'),
  (select aggregate_version from public.documents where id = (
    select document_id from pg_temp.document_results where phase = 'official-superseding'
  )),
  'm4-official-failed-void-035',
  'Abandon the failed replacement without erasing its evidence',
  'm4-official-failed-void-035',
  '35400000-0000-4000-8000-000000000053'
) result;

select extensions.ok(
  exists (
    select 1
    from public.documents failed
    where failed.id = (
      select document_id from pg_temp.document_results where phase = 'official-superseding'
    )
      and failed.status = 'voided'
      and failed.failure_code = 'fixture.render_failed'
      and failed.generated_checksum is null
      and failed.official_number = 'FX-000002'
      and failed.number_allocation_id = (
        select number_allocation_id
        from pg_temp.document_results
        where phase = 'official-superseding'
      )
  )
  and exists (
    select 1
    from public.documents prior
    where prior.id = (
      select document_id from pg_temp.document_results where phase = 'official-initial'
    )
      and prior.status = 'generated'
      and prior.superseded_by_document_id is null
  ),
  'M4-DOC-AC-006 failed replacement void preserves failure, number, and usable prior'
);

select extensions.ok(
  exists (
    select 1
    from public.audit_events event
    where event.id = (
      select audit_event_id from pg_temp.void_results where phase = 'failed-initial'
    )
      and event.action = 'document.voided'
      and event.auth_assurance = 'aal2'
      and event.before_data ->> 'status' = 'generation_failed'
      and event.before_data ->> 'failureCode' = 'fixture.render_failed'
      and event.after_data ->> 'status' = 'voided'
      and event.after_data ->> 'failureCode' = 'fixture.render_failed'
  ),
  'T-AUD-001 failed replacement recovery records immutable AAL2 failure evidence'
);

insert into pg_temp.void_results
select 'failed-replay', result.*
from app.m4_void_document(
  '10000000-0000-4000-8000-000000000001',
  (select document_id from pg_temp.document_results where phase = 'official-superseding'),
  (select aggregate_version - 1 from public.documents where id = (
    select document_id from pg_temp.document_results where phase = 'official-superseding'
  )),
  'm4-official-failed-void-035',
  'Abandon the failed replacement without erasing its evidence',
  'm4-official-failed-void-replay-035',
  '35400000-0000-4000-8000-000000000053'
) result;

select extensions.ok(
  (select audit_event_id from pg_temp.void_results where phase = 'failed-replay')
    = (select audit_event_id from pg_temp.void_results where phase = 'failed-initial')
  and (select aggregate_version from pg_temp.void_results where phase = 'failed-replay')
    = (select aggregate_version from pg_temp.void_results where phase = 'failed-initial')
  and (select replayed from pg_temp.void_results where phase = 'failed-replay'),
  'M4-DOC-AC-008 failed replacement void recovery is actor-idempotent'
);

select extensions.throws_ok(
  $$
    select * from app.m4_retry_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-superseding'),
      (select aggregate_version from public.documents where id = (
        select document_id from pg_temp.document_results where phase = 'official-superseding'
      )),
      'm4-official-failed-retry-after-void',
      'A retry must lose once the failed replacement is voided',
      'm4-official-failed-retry-after-void',
      '35400000-0000-4000-8000-000000000054'
    )
  $$,
  '23514',
  'only a failed official render may be retried',
  'M4-DOC-AC-006 retry and void serialize with one terminal winner'
);

insert into pg_temp.document_results
select 'official-recovered', result.*
from app.request_official_document(
  '10000000-0000-4000-8000-000000000001',
  'm4-official-recovered-successor-035',
  '35040000-0000-4000-8000-000000000001',
  '35200000-0000-4000-8000-000000000001',
  '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-17',
  null, '{"memo":"Recovered successor"}',
  '{"evidenceId":"35410000-0000-4000-8000-000000000007"}', null,
  (select document_id from pg_temp.document_results where phase = 'official-initial'),
  (select aggregate_version from public.documents where id = (
    select document_id from pg_temp.document_results where phase = 'official-initial'
  )),
  'Create a fresh successor after preserving the failed attempt',
  'm4-official-recovered-successor-035',
  '35400000-0000-4000-8000-000000000055'
) result;

select extensions.ok(
  exists (
    select 1
    from public.documents recovered
    where recovered.id = (
      select document_id from pg_temp.document_results where phase = 'official-recovered'
    )
      and recovered.status = 'generating'
      and recovered.official_number = 'FX-000003'
      and recovered.supersedes_document_id = (
        select document_id from pg_temp.document_results where phase = 'official-initial'
      )
      and recovered.supersedes_expected_version = (
        select aggregate_version from public.documents where id = (
          select document_id from pg_temp.document_results where phase = 'official-initial'
        )
      )
  )
  and (select pg_catalog.count(*) from public.number_allocations) = 3,
  'M4-NUM-AC-004 fresh recovery uses the current prior version and a new number'
);

select extensions.throws_ok(
  $$
    select * from app.request_official_document(
      '10000000-0000-4000-8000-000000000001',
      'm4-official-recovered-conflict-035',
      '35040000-0000-4000-8000-000000000001',
      '35200000-0000-4000-8000-000000000001',
      '35300000-0000-4000-8000-000000000001', 'en-CA', date '2026-07-17',
      null, '{"memo":"Conflicting successor"}',
      '{"evidenceId":"35410000-0000-4000-8000-000000000008"}', null,
      (select document_id from pg_temp.document_results where phase = 'official-initial'),
      (select aggregate_version from public.documents where id = (
        select document_id from pg_temp.document_results where phase = 'official-initial'
      )),
      'Reject a second active successor against the same prior version',
      'm4-official-recovered-conflict-035',
      '35400000-0000-4000-8000-000000000056'
    )
  $$,
  '40001',
  'document.supersession_in_progress',
  'M4-DOC-AC-009 concurrent replacement claims serialize and fail closed'
);

select extensions.ok(
  (select pg_catalog.count(*) from public.number_allocations) = 3
  and (
    select pg_catalog.count(*)
    from public.documents successor
    where successor.supersedes_document_id = (
      select document_id from pg_temp.document_results where phase = 'official-initial'
    )
      and successor.status <> 'voided'
  ) = 1
  and pg_catalog.pg_get_indexdef(
    'public.documents_supersedes_uidx'::pg_catalog.regclass
  ) ~ 'status <> ''voided''::text',
  'M4-DOC-AC-009 failed concurrent replacement consumes no number or lineage claim'
);
reset role;
rollback to savepoint failed_supersession_recovery;

-- A failed replacement cannot be retried after the prior aggregate advances.
-- Roll the synthetic drift back so the ordinary retry path below stays valid.
savepoint supersession_prior_drift;
update public.documents original
set aggregate_version = original.aggregate_version + 1
where original.id = (
  select document_id from pg_temp.document_results where phase = 'official-initial'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.m4_retry_document_render(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-superseding'),
      (select aggregate_version from public.documents where id = (
        select document_id from pg_temp.document_results where phase = 'official-superseding'
      )),
      'm4-official-retry-prior-drift',
      'Reject retry after prior aggregate changed',
      'm4-official-retry-prior-drift',
      '35400000-0000-4000-8000-000000000052'
    )
  $$,
  '40001',
  'document.supersession_prior_changed',
  'M4-DOC-AC-009 failed replacement retry revalidates the prior aggregate'
);
rollback to savepoint supersession_prior_drift;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  exists (
    select 1
    from app.m4_get_document_detail(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.document_results where phase = 'official-superseding')
    ) detail
    where detail.status = 'generation_failed'
      and detail.job_status = 'dead_letter'
      and detail.jobs @> '[{"status": "dead_letter", "review_required": true}]'::jsonb
  ),
  'M4-DOC-AC-006 detail query exposes the exact dead-letter retry eligibility state'
);
insert into pg_temp.retry_results
select 'initial', result.*
from app.m4_retry_document_render(
  '10000000-0000-4000-8000-000000000001',
  (select document_id from pg_temp.document_results where phase = 'official-superseding'),
  (select aggregate_version from public.documents where id = (
    select document_id from pg_temp.document_results where phase = 'official-superseding'
  )),
  'm4-official-retry-035', 'Retry reviewed synthetic render failure',
  'm4-official-retry-035',
  '35400000-0000-4000-8000-000000000014'
) result;

-- 35. Reasoned retry requeues one job against the same document and number.
select extensions.ok(
  (select document_status from pg_temp.retry_results where phase = 'initial') = 'generating'
  and (select job_status from pg_temp.retry_results where phase = 'initial') = 'queued'
  and (select document_id from pg_temp.retry_results where phase = 'initial')
    = (select document_id from pg_temp.document_results where phase = 'official-superseding')
  and (select official_number from public.documents where id = (
    select document_id from pg_temp.retry_results where phase = 'initial'
  )) = 'FX-000002',
  'T-DOC-003 retry reuses the same authoritative document and number'
);

insert into pg_temp.retry_results
select 'replay', result.*
from app.m4_retry_document_render(
  '10000000-0000-4000-8000-000000000001',
  (select document_id from pg_temp.document_results where phase = 'official-superseding'),
  (select aggregate_version - 1 from public.documents where id = (
    select document_id from pg_temp.document_results where phase = 'official-superseding'
  )),
  'm4-official-retry-035', 'Retry reviewed synthetic render failure',
  'm4-official-retry-replay-035',
  '35400000-0000-4000-8000-000000000014'
) result;

-- 36. Retry replay returns the same queued job and transition evidence.
select extensions.ok(
  (select job_id from pg_temp.retry_results where phase = 'replay')
    = (select job_id from pg_temp.retry_results where phase = 'initial')
  and (select audit_event_id from pg_temp.retry_results where phase = 'replay')
    = (select audit_event_id from pg_temp.retry_results where phase = 'initial')
  and (select replayed from pg_temp.retry_results where phase = 'replay'),
  'M4-DOC-AC-006 retry command is actor-idempotent'
);

-- 37. Retry appends attempt two with explicit dead-letter causation.
select extensions.ok(
  exists (
    select 1 from public.document_render_attempts attempt
    where attempt.document_id = (
      select document_id from pg_temp.document_results where phase = 'official-superseding'
    )
      and attempt.attempt_number = 2
      and attempt.job_id = (select job_id from pg_temp.retry_results where phase = 'initial')
      and attempt.replay_of_job_id = (
        select job_id from pg_temp.claimed_jobs where phase = 'official-superseding'
      )
  ),
  'M4-DOC-AC-006 retry preserves durable attempt lineage'
);
reset role;

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.claimed_jobs
select
  'official-retry', claimed.job_id, claimed.workspace_id,
  claimed.lease_token, claimed.correlation_id
from app.claim_jobs('m4-doc-worker', 10, 300, array['documents.render_pdf']) claimed
where claimed.job_id = (select job_id from pg_temp.retry_results where phase = 'initial');

insert into pg_temp.render_receipts
select
  'official-retry', document.id,
  (select job_id from pg_temp.retry_results where phase = 'initial'),
  repeat('b', 64),
  document.workspace_id::text || '/documents/' || document.id::text
    || '/generated_original/v1/' || repeat('b', 64) || '.pdf',
  pg_catalog.jsonb_build_object(
    'storage', pg_catalog.jsonb_build_object(
      'bucket', 'documents-private',
      'objectKey', document.workspace_id::text || '/documents/' || document.id::text
        || '/generated_original/v1/' || repeat('b', 64) || '.pdf',
      'generation', 'fixture-generation-2', 'byteSize', 4096,
      'checksumSha256', repeat('b', 64)
    ),
    'renderer', pg_catalog.jsonb_build_object('version', document.renderer_version),
    'officialNumber', document.official_number,
    'sourceBundleChecksum', document.version_snapshot ->> 'templateBundleChecksum',
    'renderInputChecksum', document.render_input_checksum,
    'versionSnapshotChecksum', document.version_snapshot_checksum
  )
from public.documents document
where document.id = (select document_id from pg_temp.retry_results where phase = 'initial');

insert into pg_temp.file_results
select 'official-retry', result.*
from app.m4_complete_official_document_render(
  '10000000-0000-4000-8000-000000000001',
  (select document_id from pg_temp.retry_results where phase = 'initial'),
  (select job_id from pg_temp.claimed_jobs where phase = 'official-retry'),
  'm4-doc-worker',
  (select lease_token from pg_temp.claimed_jobs where phase = 'official-retry'),
  'documents-private',
  (select object_path from pg_temp.render_receipts where phase = 'official-retry'),
  'fixture-generation-2', 4096, repeat('b', 64), 'fixture-pdf-v1',
  (select receipt from pg_temp.render_receipts where phase = 'official-retry'),
  'm4-official-retry-complete',
  '35400000-0000-4000-8000-000000000015'
) result;
do $settle_retry_render$
begin
  perform app.complete_job(
    (select job_id from pg_temp.claimed_jobs where phase = 'official-retry'),
    'm4-doc-worker',
    (select lease_token from pg_temp.claimed_jobs where phase = 'official-retry'),
    pg_catalog.jsonb_build_object(
      'document_file_id',
      (select document_file_id from pg_temp.file_results where phase = 'official-retry')
    ), null
  );
end;
$settle_retry_render$;

-- 38. Reviewed retry completes one generated-original for the same numbered document.
select extensions.ok(
  (select document_status from pg_temp.file_results where phase = 'official-retry') = 'generated'
  and (select pg_catalog.count(*) from public.document_files
       where document_id = (select document_id from pg_temp.retry_results where phase = 'initial')
         and role = 'generated_original') = 1
  and exists (
    select 1 from public.documents original
    where original.id = (select document_id from pg_temp.document_results where phase = 'official-initial')
      and original.status = 'superseded'
      and original.superseded_by_document_id = (
        select document_id from pg_temp.retry_results where phase = 'initial'
      )
  )
  and (select pg_catalog.count(*) from public.number_allocations) = 2,
  'T-DOC-003 successful verified retry supersedes the original without duplicate file or number'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.void_results
select 'initial', result.*
from app.m4_void_document(
  '10000000-0000-4000-8000-000000000001',
  (select document_id from pg_temp.retry_results where phase = 'initial'),
  (select aggregate_version from public.documents where id = (
    select document_id from pg_temp.retry_results where phase = 'initial'
  )),
  'm4-official-void-035', 'Void rolled-back corrected fixture document',
  'm4-official-void-035',
  '35400000-0000-4000-8000-000000000016'
) result;

-- 39. Void requires an eligible generated official, recent step-up, reason, and version.
select extensions.ok(
  (select document_status from pg_temp.void_results where phase = 'initial') = 'voided'
  and (select voided_at from pg_temp.void_results where phase = 'initial') is not null
  and not (select replayed from pg_temp.void_results where phase = 'initial'),
  'M4-DOC-AC-008 reasoned void advances the lifecycle exactly once'
);

-- 40. Voiding preserves the permanent number, exact snapshots, and generated file.
select extensions.ok(
  exists (
    select 1 from public.documents document
    where document.id = (select document_id from pg_temp.void_results where phase = 'initial')
      and document.official_number = 'FX-000002'
      and document.number_allocation_id = (
        select number_allocation_id from pg_temp.document_results where phase = 'official-superseding'
      )
      and document.version_snapshot_checksum = (
        select receipt ->> 'versionSnapshotChecksum'
        from pg_temp.render_receipts
        where phase = 'official-retry'
      )
  )
  and exists (
    select 1 from public.document_files file
    where file.document_id = (select document_id from pg_temp.void_results where phase = 'initial')
      and file.role = 'generated_original' and file.current
  ),
  'M4-NUM-AC-004 void never returns a committed number to reuse'
);

-- 41. Browser sessions cannot mutate visible document or file history.
select extensions.throws_ok(
  $$
    update public.documents set locale = 'fr-CA'
    where id = (select document_id from pg_temp.document_results where phase = 'official-initial')
  $$,
  '42501',
  'permission denied for table documents',
  'T-RBAC-001 browser cannot bypass document commands with raw DML'
);

-- 42. Northstar actor cannot select Harbour documents through forced RLS.
select extensions.is(
  (select pg_catalog.count(*) from public.documents
   where workspace_id = '20000000-0000-4000-8000-000000000002'),
  0::bigint,
  'T-TEN-001 document history is workspace-isolated'
);
reset role;

-- 43. Every privileged lifecycle phase emits append-only audit evidence.
select extensions.ok(
  exists (
    select 1 from public.audit_events event
    where event.entity_id = (select document_id from pg_temp.document_results where phase = 'official-initial')
      and event.action = 'document.number_allocated'
  )
  and exists (
    select 1 from public.audit_events event
    where event.entity_id = (select document_id from pg_temp.document_results where phase = 'official-initial')
      and event.action = 'document.official_generated'
  )
  and exists (
    select 1 from public.audit_events event
    where event.entity_id = (select document_id from pg_temp.document_results where phase = 'official-superseding')
      and event.action = 'document.render_retried'
  )
  and exists (
    select 1 from public.audit_events event
    where event.entity_id = (select document_id from pg_temp.document_results where phase = 'official-superseding')
      and event.action = 'document.voided'
  ),
  'T-AUD-001 allocation, generation, retry, and void are all audited'
);

-- 44. Append-only constraints keep original and corrected documents, files, numbers, and attempts.
select extensions.ok(
  (select pg_catalog.count(*) from public.documents where mode = 'official') = 2
  and (select pg_catalog.count(*) from public.number_allocations) = 2
  and (select pg_catalog.count(*) from public.document_files where role = 'generated_original') = 2
  and (select pg_catalog.count(*) from public.document_render_attempts) = 3,
  'M4-DOC-AC-009 complete lineage remains available after supersession, failure, retry, and void'
);

-- 48. The bounded schema subset enforces nested types, enum, pattern, and limits.
select extensions.ok(
  app.m4_validate_document_fields(
    '{
      "type":"object",
      "additionalProperties":false,
      "required":["memo","kind","count","lines"],
      "properties":{
        "memo":{"type":"string","minLength":3,"maxLength":20,"pattern":"^[A-Z]"},
        "kind":{"type":"string","enum":["sale","purchase"]},
        "count":{"type":"integer","minimum":1,"maximum":10},
        "lines":{"type":"array","minItems":1,"maxItems":2,"items":{
          "type":"object","additionalProperties":false,"required":["amountMinor"],
          "properties":{"amountMinor":{"type":"integer","minimum":0}}
        }}
      }
    }'::jsonb,
    '{"memo":"Fixture","kind":"sale","count":2,"lines":[{"amountMinor":100}]}'::jsonb
  )
  and not app.m4_validate_document_fields(
    '{"type":"object","properties":{"kind":{"enum":["sale"]}},"required":["kind"]}'::jsonb,
    '{"kind":"lease"}'::jsonb
  )
  and not app.m4_validate_document_fields(
    '{"type":"object","properties":{"memo":{"type":"string","pattern":"^[A-Z]"}},"required":["memo"]}'::jsonb,
    '{"memo":"lowercase"}'::jsonb
  )
  and not app.m4_validate_document_fields(
    '{"type":"object","properties":{"count":{"type":"integer","maximum":10}},"required":["count"]}'::jsonb,
    '{"count":11}'::jsonb
  ),
  'M4-DOC-AC-002 document fields satisfy the full supported nested schema subset'
);

-- 49. Schema constructs outside the deliberately small validator subset fail closed.
select extensions.is(
  app.m4_validate_document_fields(
    '{"type":"object","oneOf":[{"required":["memo"]}]}'::jsonb,
    '{"memo":"Fixture"}'::jsonb
  ),
  false,
  'M4-DOC-AC-002 unsupported field-schema keywords cannot be silently ignored'
);

-- 63. Hostile Unicode/path characters produce one deterministic safe name
-- while the immutable legal number itself remains unchanged.
select extensions.is(
  app.m4_official_document_filename('LEGAL/2026/échange'),
  'LEGAL-2026-change-4e8ca26ffeeec1ee.pdf',
  'M4-DOC-AC-005 hostile official numbers map to the exact portable filename'
);

-- 64. Reserved device names and sanitizer collisions retain distinct hashes.
select extensions.ok(
  app.m4_official_document_filename('CON')
    ~ '^CON-[a-f0-9]{16}\.pdf$'
  and app.m4_official_document_filename('LEGAL/2026')
    <> app.m4_official_document_filename('LEGAL:2026')
  and app.m4_official_document_filename('LEGAL/2026')
    ~ '^LEGAL-2026-[a-f0-9]{16}\.pdf$',
  'M4-DOC-AC-005 reserved and colliding stems remain portable and collision-safe'
);

-- 65. Both ASCII and astral legal numbers are accepted at 128 code points.
select extensions.ok(
  app.m4_official_document_filename(pg_catalog.repeat('A', 128))
    = pg_catalog.repeat('A', 128) || '.pdf'
  and app.m4_official_document_filename(
    pg_catalog.repeat(pg_catalog.chr(128512), 128)
  ) ~ '^document-[a-f0-9]{16}\.pdf$',
  'M4-DOC-AC-005 filename validation uses the 128-code-point legal-number boundary'
);

-- 66. One code point over the immutable legal-number limit fails closed.
select extensions.throws_ok(
  $$select app.m4_official_document_filename(
    pg_catalog.repeat(pg_catalog.chr(128512), 129)
  )$$,
  '22023',
  'invalid official document number',
  'M4-DOC-AC-005 129 astral code points cannot enter artifact storage'
);

-- 67. Official issuance holds shared approval locks for every M4 dependency;
-- the approval command holds the identical key exclusively.
select extensions.is(
  pg_catalog.regexp_count(
    pg_catalog.pg_get_functiondef(
      'app.request_official_document(uuid,text,uuid,uuid,uuid,text,date,date,jsonb,jsonb,jsonb,uuid,bigint,text,text,uuid)'::pg_catalog.regprocedure
    ),
    'pg_advisory_xact_lock_shared'
  ),
  5,
  'M4-DOC-AC-004 official issuance locks all exact approval dependencies'
);

select * from extensions.finish();
rollback;
