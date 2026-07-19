-- VYN-DOC-001, VYN-NUM-001, VYN-JOB-001, VYN-AUD-001
-- M4-DOC-AC-001 through M4-DOC-AC-010
-- M4-NUM-AC-001 through M4-NUM-AC-005
-- Forward-only upgrade of the Milestone 1 preview slice to the generic
-- document, permanent-number, immutable-file, and lineage model.

drop trigger document_types_immutable on public.document_types;
drop trigger document_template_versions_immutable on public.document_template_versions;
drop trigger documents_immutable on public.documents;
drop trigger documents_lifecycle_guard on public.documents;

alter table public.document_types
  drop constraint document_types_official_generation_enabled_check,
  add column labels jsonb,
  add column field_schema_checksum text,
  add column numbering_definition_version_id uuid,
  add column workflow_version_id uuid,
  add column tax_pack_version_id uuid,
  add column calculation_version_id uuid,
  add column preview_generation_enabled boolean not null default true,
  add column production_enabled boolean not null default false,
  add column activation_status text not null default 'test_passed' check (
    activation_status in (
      'draft', 'validated', 'test_passed', 'approved', 'active', 'retired'
    )
  ),
  add column activation_gates jsonb not null default '[]'::jsonb check (
    pg_catalog.jsonb_typeof(activation_gates) = 'array'
  ),
  add column checksum text,
  add column fixture_evidence jsonb,
  add column approval_record_id uuid,
  add column activated_at timestamptz,
  add column retired_at timestamptz,
  add column updated_at timestamptz not null default pg_catalog.statement_timestamp();

update public.document_types document_type
set
  labels = pg_catalog.jsonb_build_object(
    'en', document_type.display_name,
    'fr', document_type.display_name
  ),
  field_schema_checksum = pg_catalog.encode(
    extensions.digest(document_type.field_schema::text, 'sha256'), 'hex'
  ),
  checksum = pg_catalog.encode(
    extensions.digest(
      pg_catalog.jsonb_build_object(
        'key', document_type.key::text,
        'version', document_type.version,
        'fieldSchema', document_type.field_schema,
        'productionEnabled', false
      )::text,
      'sha256'
    ),
    'hex'
  ),
  fixture_evidence = pg_catalog.jsonb_build_object(
    'source', 'milestone_1_preview_compatibility',
    'productionApproved', false
  );

alter table public.document_types
  alter column labels set not null,
  alter column field_schema_checksum set not null,
  alter column checksum set not null,
  add constraint document_types_labels_check check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and labels ? 'en' and labels ? 'fr'
    and pg_catalog.btrim(labels ->> 'en') <> ''
    and pg_catalog.btrim(labels ->> 'fr') <> ''
  ),
  add constraint document_types_schema_checksum_check check (
    field_schema_checksum ~ '^[a-f0-9]{64}$'
  ),
  add constraint document_types_checksum_check check (checksum ~ '^[a-f0-9]{64}$'),
  add constraint document_types_official_activation_check check (
    not official_generation_enabled
    or (
      production_enabled
      and activation_status = 'active'
      and numbering_definition_version_id is not null
      and approval_record_id is not null
      and activated_at is not null
    )
  ),
  add constraint document_types_numbering_version_fk
    foreign key (workspace_id, numbering_definition_version_id)
    references public.numbering_definition_versions (workspace_id, id)
    on delete restrict,
  add constraint document_types_workflow_version_fk
    foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id) on delete restrict,
  add constraint document_types_tax_pack_version_fk
    foreign key (workspace_id, tax_pack_version_id)
    references public.tax_pack_versions (workspace_id, id) on delete restrict,
  add constraint document_types_calculation_version_fk
    foreign key (workspace_id, calculation_version_id)
    references public.calculation_versions (workspace_id, id) on delete restrict,
  add constraint document_types_approval_record_fk
    foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id) on delete restrict;

alter table public.document_template_versions
  drop constraint document_template_versions_template_class_check,
  drop constraint document_template_versions_production_approved_check,
  drop constraint document_template_versions_watermark_check,
  alter column watermark drop not null,
  add column source_css text not null default '',
  add column source_bundle_checksum text,
  add column asset_manifest jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(asset_manifest) = 'object'
  ),
  add column font_manifest jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(font_manifest) = 'object'
  ),
  add column field_schema_checksum text,
  add column activation_status text not null default 'test_passed' check (
    activation_status in (
      'draft', 'validated', 'test_passed', 'approved', 'active', 'retired'
    )
  ),
  add column fixture_evidence jsonb,
  add column approval_record_id uuid,
  add column activated_at timestamptz,
  add column retired_at timestamptz,
  add column updated_at timestamptz not null default pg_catalog.statement_timestamp();

update public.document_template_versions template
set
  source_bundle_checksum = pg_catalog.encode(
    extensions.digest(
      pg_catalog.jsonb_build_object(
        'htmlChecksum', template.source_checksum,
        'css', '',
        'assets', '{}'::jsonb,
        'fonts', '{}'::jsonb
      )::text,
      'sha256'
    ),
    'hex'
  ),
  field_schema_checksum = pg_catalog.encode(
    extensions.digest(template.field_schema::text, 'sha256'), 'hex'
  ),
  fixture_evidence = pg_catalog.jsonb_build_object(
    'source', 'milestone_1_preview_compatibility',
    'productionApproved', false
  );

alter table public.document_template_versions
  alter column source_bundle_checksum set not null,
  alter column field_schema_checksum set not null,
  add constraint document_template_versions_class_check check (
    template_class in ('synthetic_non_production', 'tenant_approved')
  ),
  add constraint document_template_versions_bundle_checksum_check check (
    source_bundle_checksum ~ '^[a-f0-9]{64}$'
  ),
  add constraint document_template_versions_schema_checksum_check check (
    field_schema_checksum ~ '^[a-f0-9]{64}$'
  ),
  add constraint document_template_versions_production_shape_check check (
    (
      template_class = 'synthetic_non_production'
      and not production_approved
      and watermark = 'DRAFT / NON-PRODUCTION'
      and activation_status in ('test_passed', 'retired')
    )
    or (
      template_class = 'tenant_approved'
      and production_approved
      and watermark is null
      and activation_status in ('approved', 'active', 'retired')
      and approval_record_id is not null
    )
  ),
  add constraint document_template_versions_approval_record_fk
    foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id) on delete restrict;

alter table public.documents
  drop constraint documents_mode_check,
  drop constraint documents_official_number_check,
  drop constraint documents_status_check,
  drop constraint documents_watermark_check,
  drop constraint documents_preview_state_check,
  alter column watermark drop not null,
  add column number_allocation_id uuid,
  add column document_date date not null default current_date,
  add column intended_signature_date date,
  add column numbering_version_id uuid,
  add column workflow_version_id uuid,
  add column tax_pack_version_id uuid,
  add column calculation_version_id uuid,
  add column calculation_snapshot_id uuid,
  add column tax_calculation_snapshot_id uuid,
  add column renderer_version text,
  add column version_snapshot jsonb,
  add column version_snapshot_checksum text,
  add column aggregate_version bigint not null default 1 check (aggregate_version > 0),
  add column supersedes_document_id uuid,
  add column supersedes_expected_version bigint check (supersedes_expected_version > 0),
  add column superseded_by_document_id uuid,
  add column signed_at timestamptz,
  add column completed_at timestamptz,
  add column void_reason text,
  add column voided_by uuid references auth.users (id) on delete restrict,
  add column voided_at timestamptz;

update public.documents document
set
  renderer_version = template.renderer_version,
  version_snapshot = pg_catalog.jsonb_build_object(
    'schemaVersion', 1,
    'documentTypeId', document.document_type_id,
    'templateVersionId', document.template_version_id,
    'rendererVersion', template.renderer_version,
    'previewCompatibility', true
  ),
  version_snapshot_checksum = pg_catalog.encode(
    extensions.digest(
      pg_catalog.jsonb_build_object(
        'schemaVersion', 1,
        'documentTypeId', document.document_type_id,
        'templateVersionId', document.template_version_id,
        'rendererVersion', template.renderer_version,
        'previewCompatibility', true
      )::text,
      'sha256'
    ),
    'hex'
  )
from public.document_template_versions template
where template.workspace_id = document.workspace_id
  and template.id = document.template_version_id;

alter table public.documents
  alter column renderer_version set not null,
  alter column version_snapshot set not null,
  alter column version_snapshot_checksum set not null,
  add constraint documents_mode_check check (mode in ('preview', 'official')),
  add constraint documents_status_check check (
    status in (
      'queued', 'generated', 'failed',
      'generating', 'generation_failed', 'signed_received', 'completed',
      'voided', 'superseded'
    )
  ),
  add constraint documents_renderer_version_check check (
    pg_catalog.btrim(renderer_version) <> ''
    and pg_catalog.char_length(renderer_version) <= 100
  ),
  add constraint documents_version_snapshot_check check (
    pg_catalog.jsonb_typeof(version_snapshot) = 'object'
    and version_snapshot_checksum ~ '^[a-f0-9]{64}$'
  ),
  add constraint documents_mode_number_shape_check check (
    (
      mode = 'preview'
      and official_number is null
      and number_allocation_id is null
      and watermark = 'DRAFT / NON-PRODUCTION'
      and status in ('queued', 'generated', 'failed')
    )
    or (
      mode = 'official'
      and pg_catalog.btrim(official_number) <> ''
      and number_allocation_id is not null
      and watermark is null
      and status in (
        'generating', 'generated', 'generation_failed', 'signed_received',
        'completed', 'voided', 'superseded'
      )
    )
  ),
  add constraint documents_generation_shape_check check (
    (status in ('queued', 'generating') and generated_checksum is null and failure_code is null)
    or (status in ('generated', 'signed_received', 'completed', 'voided', 'superseded') and generated_checksum is not null and failure_code is null)
    or (status in ('failed', 'generation_failed') and generated_checksum is null and failure_code is not null)
    or (status = 'voided' and generated_checksum is null and failure_code is not null)
  ),
  add constraint documents_void_shape_check check (
    (status = 'voided' and voided_by is not null and voided_at is not null and pg_catalog.btrim(void_reason) <> '')
    or (status <> 'voided' and voided_by is null and voided_at is null and void_reason is null)
  ),
  add constraint documents_number_allocation_fk
    foreign key (workspace_id, number_allocation_id)
    references public.number_allocations (workspace_id, id) on delete restrict,
  add constraint documents_numbering_version_fk
    foreign key (workspace_id, numbering_version_id)
    references public.numbering_definition_versions (workspace_id, id) on delete restrict,
  add constraint documents_workflow_version_fk
    foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id) on delete restrict,
  add constraint documents_tax_pack_version_fk
    foreign key (workspace_id, tax_pack_version_id)
    references public.tax_pack_versions (workspace_id, id) on delete restrict,
  add constraint documents_calculation_version_fk
    foreign key (workspace_id, calculation_version_id)
    references public.calculation_versions (workspace_id, id) on delete restrict,
  add constraint documents_supersedes_fk
    foreign key (workspace_id, supersedes_document_id)
    references public.documents (workspace_id, id) on delete restrict,
  add constraint documents_superseded_by_fk
    foreign key (workspace_id, superseded_by_document_id)
    references public.documents (workspace_id, id) on delete restrict,
  add constraint documents_supersession_shape_check check (
    (
      (supersedes_document_id is null and supersedes_expected_version is null)
      or (
        mode = 'official'
        and supersedes_document_id is not null
        and supersedes_expected_version is not null
      )
    )
    and (
      (status = 'superseded' and superseded_by_document_id is not null)
      or (status <> 'superseded' and superseded_by_document_id is null)
    )
  );

-- Resolve the optional workflow dependency once with fail-closed facts that
-- every document path can consume.  A workflow is usable only when the deal
-- is pinned to that exact immutable version, the version remains active, and
-- its exact approval has not expired or been revoked.
create function app.m4_document_workflow_dependency(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_workflow_version_id uuid,
  p_effective_at timestamptz default pg_catalog.statement_timestamp()
)
returns table (
  deal_matches boolean,
  workflow_active boolean,
  approval_valid boolean,
  workflow_version text,
  workflow_revision bigint,
  workflow_checksum text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    case
      when p_workflow_version_id is null then true
      else deal.workflow_version_id is not distinct from p_workflow_version_id
    end,
    case
      when p_workflow_version_id is null then true
      else version.status is not distinct from 'active'
    end,
    case
      when p_workflow_version_id is null then true
      else coalesce(app.workflow_version_has_valid_approval(
        p_workspace_id,
        p_workflow_version_id,
        p_effective_at
      ), false)
    end,
    version.version,
    version.revision,
    version.checksum
  from (values (true)) seed(present)
  left join public.deals deal
    on deal.workspace_id = p_workspace_id
   and deal.id = p_deal_id
  left join public.workflow_versions version
    on version.workspace_id = p_workspace_id
   and version.id = p_workflow_version_id;
$$;

-- Preserve the Milestone 1 preview command without weakening the Milestone 4
-- immutable version snapshot requirement.  The legacy command intentionally
-- omits these later columns, so a preview-only insert trigger derives them
-- from the exact template and document type before constraints are checked.
create function app.m4_fill_preview_version_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_template public.document_template_versions%rowtype;
  target_type public.document_types%rowtype;
  workflow_dependency record;
begin
  if new.mode <> 'preview'
    or (new.renderer_version is not null
      and new.version_snapshot is not null
      and new.version_snapshot_checksum is not null) then
    return new;
  end if;

  select template.* into target_template
  from public.document_template_versions template
  where template.workspace_id = new.workspace_id
    and template.id = new.template_version_id;
  if not found then
    raise exception using errcode = '23503', message = 'document.preview_template_missing';
  end if;
  select document_type.* into target_type
  from public.document_types document_type
  where document_type.workspace_id = new.workspace_id
    and document_type.id = new.document_type_id;
  if not found then
    raise exception using errcode = '23503', message = 'document.preview_type_missing';
  end if;

  select dependency.* into workflow_dependency
  from app.m4_document_workflow_dependency(
    new.workspace_id,
    new.deal_id,
    target_type.workflow_version_id
  ) dependency;
  if target_type.workflow_version_id is not null
    and not workflow_dependency.deal_matches then
    raise exception using errcode = '23514', message = 'document.preview_workflow_mismatch';
  end if;
  if target_type.workflow_version_id is not null
    and not workflow_dependency.workflow_active then
    raise exception using errcode = '23514', message = 'document.preview_workflow_inactive';
  end if;
  if target_type.workflow_version_id is not null
    and not workflow_dependency.approval_valid then
    raise exception using errcode = '23514', message = 'document.preview_workflow_approval_invalid';
  end if;

  new.renderer_version := target_template.renderer_version;
  new.version_snapshot := pg_catalog.jsonb_build_object(
    'schemaVersion', 3,
    'documentTypeId', target_type.id,
    'documentTypeChecksum', target_type.checksum,
    'templateVersionId', target_template.id,
    'templateBundleChecksum', target_template.source_bundle_checksum,
    'workflowVersionId', target_type.workflow_version_id,
    'workflowVersion', workflow_dependency.workflow_version,
    'workflowRevision', workflow_dependency.workflow_revision,
    'workflowChecksum', workflow_dependency.workflow_checksum,
    'rendererVersion', target_template.renderer_version,
    'previewCompatibility', true
  );
  new.version_snapshot_checksum := app.vertical_slice_fingerprint(new.version_snapshot);
  return new;
end;
$$;

create trigger documents_m4_fill_preview_version_snapshot
before insert on public.documents
for each row execute function app.m4_fill_preview_version_snapshot();

create unique index documents_official_number_uidx
  on public.documents (workspace_id, official_number)
  where mode = 'official';
create unique index documents_supersedes_uidx
  on public.documents (workspace_id, supersedes_document_id)
  where supersedes_document_id is not null and status <> 'voided';

create table public.document_files (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_id uuid not null,
  role text not null check (
    role in ('preview', 'generated_original', 'signed_scan', 'attachment', 'void_notice')
  ),
  version integer not null check (version > 0),
  media_file_id uuid,
  storage_bucket text not null check (storage_bucket ~ '^[a-z0-9][a-z0-9_-]{2,62}$'),
  storage_object_path text not null check (
    pg_catalog.char_length(storage_object_path) between 1 and 1000
    and storage_object_path = pg_catalog.btrim(storage_object_path)
    and storage_object_path !~ '[\\]'
    and storage_object_path !~ '(^|/)\.\.(/|$)'
    and storage_object_path !~* '^https?://'
  ),
  filename text not null check (
    pg_catalog.btrim(filename) <> '' and pg_catalog.char_length(filename) <= 255
  ),
  mime_type text not null check (
    mime_type in ('application/pdf', 'image/jpeg', 'image/png')
  ),
  byte_size bigint not null check (byte_size between 1 and 52428800),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  current boolean not null default true,
  generated_by_job_id uuid,
  recorded_by uuid not null references auth.users (id) on delete restrict,
  recorded_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, document_id, role, version),
  unique (workspace_id, storage_bucket, storage_object_path),
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, media_file_id)
    references public.media_files (workspace_id, id) on delete restrict,
  foreign key (workspace_id, generated_by_job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  check ((role = 'signed_scan') = (media_file_id is not null)),
  check ((role in ('preview', 'generated_original')) = (generated_by_job_id is not null))
);

create unique index document_files_current_role_uidx
  on public.document_files (workspace_id, document_id, role)
  where current;

create table public.document_render_jobs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_id uuid not null,
  outbox_event_id uuid not null,
  job_id uuid not null,
  render_mode text not null check (render_mode in ('preview', 'official')),
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  requested_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, document_id),
  unique (workspace_id, job_id),
  unique (workspace_id, outbox_event_id),
  unique (workspace_id, requested_by, idempotency_key),
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict
);

create table public.runtime_evidence_records (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  evidence_type text not null check (evidence_type in ('calculation', 'tax')),
  calculation_version_id uuid,
  tax_pack_version_id uuid,
  tax_assignment_id uuid,
  deal_id uuid,
  deal_context_checksum text,
  snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(snapshot) = 'object'
    and not app.job_payload_contains_forbidden_key(snapshot)
  ),
  snapshot_checksum text not null check (snapshot_checksum ~ '^[a-f0-9]{64}$'),
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, evidence_type, idempotency_key),
  foreign key (workspace_id, calculation_version_id)
    references public.calculation_versions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, tax_pack_version_id)
    references public.tax_pack_versions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, tax_assignment_id)
    references public.tax_pack_assignments (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  check (expires_at > created_at),
  check (
    (deal_id is null and deal_context_checksum is null)
    or (deal_id is not null and deal_context_checksum ~ '^[a-f0-9]{64}$')
  ),
  check (
    (evidence_type = 'calculation'
      and calculation_version_id is not null
      and tax_pack_version_id is null
      and tax_assignment_id is null)
    or (evidence_type = 'tax'
      and calculation_version_id is null
      and tax_pack_version_id is not null)
  )
);

create table public.runtime_evidence_consumptions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  evidence_id uuid not null,
  evidence_type text not null check (evidence_type in ('calculation', 'tax')),
  deal_id uuid not null,
  document_id uuid not null,
  deal_context_checksum text not null check (
    deal_context_checksum ~ '^[a-f0-9]{64}$'
  ),
  consumed_by uuid not null references auth.users (id) on delete restrict,
  consumed_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, evidence_id),
  foreign key (workspace_id, evidence_id)
    references public.runtime_evidence_records (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict
);

alter table public.calculation_snapshots
  add column runtime_evidence_id uuid,
  add column definition_snapshot jsonb,
  add column definition_checksum text,
  add column tax_component_snapshot jsonb,
  add constraint calculation_snapshots_runtime_evidence_fk
    foreign key (workspace_id, runtime_evidence_id)
    references public.runtime_evidence_records (workspace_id, id) on delete restrict,
  add constraint calculation_snapshots_official_evidence_check check (
    document_id is null or (
      runtime_evidence_id is not null
      and definition_snapshot is not null
      and pg_catalog.jsonb_typeof(definition_snapshot) = 'object'
      and definition_checksum is not null
      and definition_checksum ~ '^[a-f0-9]{64}$'
      and tax_component_snapshot is not null
      and pg_catalog.jsonb_typeof(tax_component_snapshot) = 'array'
    )
  );

alter table public.tax_calculation_snapshots
  add column runtime_evidence_id uuid,
  add column pack_snapshot jsonb,
  add column pack_checksum text,
  add column source_snapshot jsonb,
  add constraint tax_calculation_snapshots_runtime_evidence_fk
    foreign key (workspace_id, runtime_evidence_id)
    references public.runtime_evidence_records (workspace_id, id) on delete restrict,
  add constraint tax_calculation_snapshots_official_evidence_check check (
    document_id is null or (
      runtime_evidence_id is not null
      and pack_snapshot is not null
      and pg_catalog.jsonb_typeof(pack_snapshot) = 'object'
      and pack_checksum is not null
      and pack_checksum ~ '^[a-f0-9]{64}$'
      and source_snapshot is not null
      and pg_catalog.jsonb_typeof(source_snapshot) = 'array'
    )
  );

alter table public.documents
  add constraint documents_calculation_snapshot_fk
    foreign key (workspace_id, calculation_snapshot_id)
    references public.calculation_snapshots (workspace_id, id) on delete restrict,
  add constraint documents_tax_snapshot_fk
    foreign key (workspace_id, tax_calculation_snapshot_id)
    references public.tax_calculation_snapshots (workspace_id, id) on delete restrict;

create function app.m4_guard_document_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.mode = 'preview' then
    if new.mode <> 'preview'
      or new.official_number is not null
      or new.number_allocation_id is not null
      or new.render_input_snapshot is distinct from old.render_input_snapshot
      or new.version_snapshot is distinct from old.version_snapshot
      or new.status not in ('queued', 'generated', 'failed') then
      raise exception using errcode = '23514', message = 'preview document invariants are immutable';
    end if;
    return new;
  end if;

  -- A replacement is not authoritative until its immutable PDF exists.  Keep
  -- the prior aggregate stable while the successor is rendering so signing,
  -- voiding, or a second supersession cannot race the worker completion.
  if exists (
    select 1
    from public.documents successor
    where successor.workspace_id = old.workspace_id
      and successor.supersedes_document_id = old.id
      and successor.id <> old.id
      and successor.status = 'generating'
  ) then
    raise exception using
      errcode = '55000',
      message = 'document.supersession_pending';
  end if;

  if new.mode <> 'official'
    or new.official_number is distinct from old.official_number
    or new.number_allocation_id is distinct from old.number_allocation_id
    or new.render_input_snapshot is distinct from old.render_input_snapshot
    or new.render_input_checksum is distinct from old.render_input_checksum
    or new.version_snapshot is distinct from old.version_snapshot
    or new.version_snapshot_checksum is distinct from old.version_snapshot_checksum
    or new.supersedes_document_id is distinct from old.supersedes_document_id
    or new.supersedes_expected_version is distinct from old.supersedes_expected_version
    or new.template_version_id is distinct from old.template_version_id
    or new.numbering_version_id is distinct from old.numbering_version_id
    or new.tax_pack_version_id is distinct from old.tax_pack_version_id
    or new.calculation_version_id is distinct from old.calculation_version_id
    or (old.generated_checksum is not null
      and new.generated_checksum is distinct from old.generated_checksum)
    or (old.status = 'generation_failed' and new.status = 'voided'
      and new.failure_code is distinct from old.failure_code)
    or (old.calculation_snapshot_id is not null
      and new.calculation_snapshot_id is distinct from old.calculation_snapshot_id)
    or (old.tax_calculation_snapshot_id is not null
      and new.tax_calculation_snapshot_id is distinct from old.tax_calculation_snapshot_id)
    or (old.signed_at is not null and new.signed_at is distinct from old.signed_at)
    or (old.completed_at is not null and new.completed_at is distinct from old.completed_at)
    or (old.voided_at is not null and new.voided_at is distinct from old.voided_at)
    or (old.voided_by is not null and new.voided_by is distinct from old.voided_by)
    or (old.void_reason is not null and new.void_reason is distinct from old.void_reason)
    or (old.superseded_by_document_id is not null
      and new.superseded_by_document_id is distinct from old.superseded_by_document_id)
    or new.renderer_version is distinct from old.renderer_version then
    raise exception using errcode = '55000', message = 'official document snapshot and versions are immutable';
  end if;

  if not (
    (old.status = 'generating' and new.status in ('generated', 'generation_failed'))
    or (old.status = 'generation_failed' and new.status in ('generating', 'voided'))
    or (old.status = 'generated' and new.status in ('signed_received', 'completed', 'voided', 'superseded'))
    or (old.status = 'signed_received' and new.status in ('completed', 'voided', 'superseded'))
    or (old.status = 'completed' and new.status in ('voided', 'superseded'))
    or (old.status = new.status)
  ) then
    raise exception using errcode = '23514', message = 'invalid official document lifecycle transition';
  end if;
  if old.status = new.status and (
    new.generated_checksum is distinct from old.generated_checksum
    or new.failure_code is distinct from old.failure_code
    or new.signed_at is distinct from old.signed_at
    or new.completed_at is distinct from old.completed_at
    or new.void_reason is distinct from old.void_reason
    or new.voided_by is distinct from old.voided_by
    or new.voided_at is distinct from old.voided_at
    or new.superseded_by_document_id is distinct from old.superseded_by_document_id
  ) then
    raise exception using errcode = '55000', message = 'official lifecycle evidence requires a state transition';
  end if;
  if new.aggregate_version <> old.aggregate_version + 1 then
    raise exception using errcode = '40001', message = 'document aggregate version must advance exactly once';
  end if;
  return new;
end;
$$;

create trigger document_types_immutable
before update on public.document_types
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'version', 'labels', 'field_schema',
  'field_schema_checksum', 'numbering_definition_version_id',
  'workflow_version_id', 'tax_pack_version_id', 'calculation_version_id',
  'preview_generation_enabled', 'production_enabled', 'activation_gates',
  'checksum', 'created_at'
);
create trigger document_template_versions_immutable
before update on public.document_template_versions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'document_type_id', 'version', 'locale',
  'template_class', 'source_html', 'source_css', 'source_checksum',
  'source_bundle_checksum', 'asset_manifest', 'font_manifest',
  'renderer_version', 'field_schema', 'field_schema_checksum', 'created_at'
);
create trigger documents_immutable
before update on public.documents
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'document_type_id', 'deal_id', 'mode',
  'official_number', 'locale', 'watermark', 'document_date',
  'intended_signature_date', 'idempotency_key', 'command_fingerprint',
  'supersedes_document_id', 'created_by', 'created_at'
);
create trigger documents_lifecycle_guard
before update on public.documents
for each row execute function app.m4_guard_document_update();
create trigger documents_no_delete
before delete on public.documents
for each row execute function app.m4_prevent_row_mutation();
create trigger document_types_no_delete
before delete on public.document_types
for each row execute function app.m4_prevent_row_mutation();
create trigger document_template_versions_no_delete
before delete on public.document_template_versions
for each row execute function app.m4_prevent_row_mutation();
create trigger document_files_immutable_content
before update on public.document_files
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'document_id', 'role', 'version', 'media_file_id',
  'storage_bucket', 'storage_object_path', 'filename', 'mime_type',
  'byte_size', 'checksum', 'generated_by_job_id', 'recorded_by', 'recorded_at'
);
create trigger document_files_no_delete
before delete on public.document_files
for each row execute function app.m4_prevent_row_mutation();
create trigger document_render_jobs_immutable
before update or delete on public.document_render_jobs
for each row execute function app.m4_prevent_row_mutation();
create trigger runtime_evidence_records_append_only
before update or delete on public.runtime_evidence_records
for each row execute function app.m4_prevent_row_mutation();
create trigger runtime_evidence_consumptions_append_only
before update or delete on public.runtime_evidence_consumptions
for each row execute function app.m4_prevent_row_mutation();

alter table public.document_files enable row level security;
alter table public.document_files force row level security;
alter table public.document_render_jobs enable row level security;
alter table public.document_render_jobs force row level security;
alter table public.runtime_evidence_records enable row level security;
alter table public.runtime_evidence_records force row level security;
alter table public.runtime_evidence_consumptions enable row level security;
alter table public.runtime_evidence_consumptions force row level security;

create policy document_files_select on public.document_files
for select to authenticated using (
  app.has_permission(workspace_id, 'documents.read')
  and (role <> 'signed_scan' or app.has_permission(workspace_id, 'files.read_restricted'))
);
create policy document_render_jobs_select on public.document_render_jobs
for select to authenticated using (
  app.has_permission(workspace_id, 'documents.read')
  and (requested_by = auth.uid() or app.has_permission(workspace_id, 'jobs.read'))
);

revoke all on table public.document_files, public.document_render_jobs,
  public.runtime_evidence_records, public.runtime_evidence_consumptions
from public, anon, authenticated;
grant select on table public.document_files, public.document_render_jobs
to authenticated;
grant select, insert, update, delete on table
  public.document_files, public.document_render_jobs,
  public.runtime_evidence_records, public.runtime_evidence_consumptions
to service_role;

create function app.m4_number_period_key(
  p_numbering_version_id uuid,
  p_allocation_date date
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  version_row public.numbering_definition_versions%rowtype;
  allocation_month integer;
  anchor_month integer;
  period_index integer;
begin
  select version.* into version_row
  from public.numbering_definition_versions version
  where version.id = p_numbering_version_id;
  if not found or p_allocation_date is null then
    raise exception using errcode = '23514', message = 'numbering period inputs are invalid';
  end if;

  if version_row.reset_policy = 'never' then return 'never'; end if;
  if version_row.reset_policy = 'yearly' then
    return pg_catalog.to_char(p_allocation_date, 'YYYY');
  end if;
  if version_row.reset_policy = 'monthly' then
    return pg_catalog.to_char(p_allocation_date, 'YYYY-MM');
  end if;

  allocation_month := pg_catalog.extract('year', p_allocation_date)::integer * 12
    + pg_catalog.extract('month', p_allocation_date)::integer - 1;
  anchor_month := pg_catalog.extract('year', version_row.period_anchor)::integer * 12
    + pg_catalog.extract('month', version_row.period_anchor)::integer - 1;
  if allocation_month < anchor_month then
    raise exception using errcode = '23514', message = 'allocation precedes configured numbering period';
  end if;
  period_index := (allocation_month - anchor_month) / version_row.period_months;
  return 'period-' || period_index::text;
end;
$$;

create function app.m4_format_number(
  p_numbering_version_id uuid,
  p_scope_key text,
  p_period_key text,
  p_sequence_value bigint,
  p_deterministic_suffix text default ''
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  version_row public.numbering_definition_versions%rowtype;
  normalized_scope text := pg_catalog.btrim(coalesce(p_scope_key, ''));
  padded_sequence text;
  result text;
begin
  select version.* into version_row
  from public.numbering_definition_versions version
  where version.id = p_numbering_version_id;
  if not found or p_sequence_value < 0
    or normalized_scope !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$' then
    raise exception using errcode = '23514', message = 'number formatting inputs are invalid';
  end if;
  if pg_catalog.char_length(p_sequence_value::text) > version_row.numeric_width then
    raise exception using errcode = '22003', message = 'numbering sequence exceeds configured width';
  end if;
  padded_sequence := pg_catalog.lpad(
    p_sequence_value::text,
    version_row.numeric_width,
    '0'
  );

  result := pg_catalog.replace(version_row.format_pattern, '{{prefix}}', version_row.prefix);
  result := pg_catalog.replace(result, '{{scope}}', normalized_scope);
  result := pg_catalog.replace(result, '{{sequence}}', padded_sequence);
  result := pg_catalog.replace(result, '{{suffix}}', version_row.suffix || coalesce(p_deterministic_suffix, ''));
  result := pg_catalog.replace(result, '{{period}}', p_period_key);
  if result ~ '\{\{' or result ~ '\}\}'
    or pg_catalog.btrim(result) = ''
    or pg_catalog.btrim(result) is distinct from result
    or result ~ '[[:cntrl:]]'
    or pg_catalog.char_length(result) > 128 then
    raise exception using errcode = '23514', message = 'numbering pattern contains unsupported placeholders';
  end if;
  return result;
end;
$$;

create function app.m4_allocate_number(
  p_workspace_id uuid,
  p_numbering_version_id uuid,
  p_scope_key text,
  p_allocation_date date,
  p_entity_type text,
  p_entity_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_actor_user_id uuid,
  p_deterministic_suffix text default ''
)
returns table (
  allocation_id uuid,
  formatted_value text,
  sequence_value bigint,
  period_key text,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_row public.numbering_definition_versions%rowtype;
  existing_allocation public.number_allocations%rowtype;
  normalized_scope text := pg_catalog.btrim(coalesce(p_scope_key, ''));
  normalized_idempotency text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_suffix text := coalesce(p_deterministic_suffix, '');
  calculated_period text;
  next_sequence bigint;
  next_counter bigint;
  generated_value text;
  new_allocation_id uuid := pg_catalog.gen_random_uuid();
begin
  if normalized_scope !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$'
    or pg_catalog.char_length(normalized_idempotency) not between 8 and 200
    or pg_catalog.btrim(coalesce(p_reason, '')) = ''
    or p_actor_user_id is null or p_entity_id is null
    or p_entity_type !~ '^[a-z][a-z0-9_]{0,127}$'
    or pg_catalog.char_length(normalized_suffix) > 64 then
    raise exception using errcode = '22023', message = 'invalid numbering allocation command';
  end if;

  select version.* into version_row
  from public.numbering_definition_versions version
  where version.workspace_id = p_workspace_id
    and version.id = p_numbering_version_id
    and version.status = 'active'
  for share;
  if not found then
    raise exception using errcode = '23514', message = 'active numbering version is required';
  end if;

  select allocation.* into existing_allocation
  from public.number_allocations allocation
  where allocation.workspace_id = p_workspace_id
    and allocation.numbering_version_id = p_numbering_version_id
    and allocation.idempotency_key = normalized_idempotency;
  if found then
    if existing_allocation.entity_type <> p_entity_type
      or existing_allocation.entity_id <> p_entity_id
      or existing_allocation.scope_key <> normalized_scope
      or existing_allocation.deterministic_suffix <> normalized_suffix then
      raise exception using errcode = '23505', message = 'numbering idempotency conflict';
    end if;
    return query select
      existing_allocation.id,
      existing_allocation.formatted_value::text,
      existing_allocation.sequence_value,
      existing_allocation.period_key,
      true;
    return;
  end if;

  calculated_period := app.m4_number_period_key(
    p_numbering_version_id,
    p_allocation_date
  );
  insert into public.numbering_counters (
    workspace_id, numbering_version_id, scope_key, period_key, next_value
  ) values (
    p_workspace_id, p_numbering_version_id, normalized_scope,
    calculated_period, version_row.starting_value
  ) on conflict on constraint numbering_counters_pkey do nothing;

  select counter.next_value into next_sequence
  from public.numbering_counters counter
  where counter.workspace_id = p_workspace_id
    and counter.numbering_version_id = p_numbering_version_id
    and counter.scope_key = normalized_scope
    and counter.period_key = calculated_period
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'numbering counter lock failed';
  end if;
  if next_sequence > 9223372036854775807 - version_row.increment_by then
    raise exception using errcode = '22003', message = 'numbering sequence overflow';
  end if;
  next_counter := next_sequence + version_row.increment_by;
  generated_value := app.m4_format_number(
    p_numbering_version_id,
    normalized_scope,
    calculated_period,
    next_sequence,
    normalized_suffix
  );

  insert into public.number_allocations (
    id, workspace_id, numbering_version_id, scope_key, period_key,
    sequence_value, deterministic_suffix, formatted_value, entity_type,
    entity_id, idempotency_key, allocation_reason, allocated_by
  ) values (
    new_allocation_id, p_workspace_id, p_numbering_version_id,
    normalized_scope, calculated_period, next_sequence, normalized_suffix,
    generated_value, p_entity_type, p_entity_id, normalized_idempotency,
    p_reason, p_actor_user_id
  );
  update public.numbering_counters counter
  set next_value = next_counter, updated_at = pg_catalog.statement_timestamp()
  where counter.workspace_id = p_workspace_id
    and counter.numbering_version_id = p_numbering_version_id
    and counter.scope_key = normalized_scope
    and counter.period_key = calculated_period;

  return query select
    new_allocation_id, generated_value, next_sequence, calculated_period, false;
end;
$$;

create function app.m4_exact_approval_valid(
  p_workspace_id uuid,
  p_approval_record_id uuid,
  p_artifact_type text,
  p_artifact_key text,
  p_artifact_version bigint,
  p_artifact_id uuid,
  p_artifact_checksum text,
  p_effective_at timestamptz default pg_catalog.statement_timestamp()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.approval_records approval
    where approval.workspace_id = p_workspace_id
      and approval.id = p_approval_record_id
      and approval.artifact_type = p_artifact_type
      and approval.artifact_key = p_artifact_key
      and approval.artifact_version = p_artifact_version
      and approval.artifact_id = p_artifact_id
      and approval.artifact_checksum = p_artifact_checksum
      and approval.decision = 'approved'
      and (approval.expires_at is null or approval.expires_at > p_effective_at)
      and not exists (
        select 1 from public.approval_records revocation
        where revocation.workspace_id = approval.workspace_id
          and revocation.supersedes_approval_id = approval.id
          and revocation.decision = 'revoked'
          and revocation.decided_at <= p_effective_at
      )
  );
$$;

create function app.m4_json_schema_type_matches(
  p_expected_type text,
  p_value jsonb
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_expected_type
    when 'object' then pg_catalog.jsonb_typeof(p_value) = 'object'
    when 'array' then pg_catalog.jsonb_typeof(p_value) = 'array'
    when 'string' then pg_catalog.jsonb_typeof(p_value) = 'string'
    when 'number' then pg_catalog.jsonb_typeof(p_value) = 'number'
    when 'integer' then pg_catalog.jsonb_typeof(p_value) = 'number'
      and p_value::text ~ '^-?(?:0|[1-9][0-9]*)$'
    when 'boolean' then pg_catalog.jsonb_typeof(p_value) = 'boolean'
    when 'null' then pg_catalog.jsonb_typeof(p_value) = 'null'
    else false
  end;
$$;

create function app.m4_json_schema_value_valid(
  p_root_schema jsonb,
  p_schema jsonb,
  p_value jsonb,
  p_depth integer default 0
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  schema_key text;
  field_key text;
  required_key text;
  expected_type text;
  actual_type text := pg_catalog.jsonb_typeof(p_value);
  type_matches boolean := false;
  format_name text;
  string_value text;
  numeric_value numeric;
  item_value jsonb;
  item_count integer;
  property_count integer;
  ref_key text;
  additional_schema jsonb;
begin
  if p_depth > 16
    or p_root_schema is null
    or pg_catalog.jsonb_typeof(p_root_schema) <> 'object'
    or p_schema is null
    or pg_catalog.jsonb_typeof(p_schema) <> 'object' then
    return false;
  end if;

  -- Only this bounded Draft 2020-12 subset is executable. Unknown keywords
  -- fail closed instead of being silently ignored.
  for schema_key in select pg_catalog.jsonb_object_keys(p_schema) loop
    if not (schema_key = any (array[
      '$schema', '$defs', '$ref', 'type', 'nullable', 'enum', 'const',
      'format', 'pattern', 'minLength', 'maxLength', 'minimum', 'maximum',
      'exclusiveMinimum', 'exclusiveMaximum', 'minItems', 'maxItems',
      'items', 'minProperties', 'maxProperties', 'required', 'properties',
      'additionalProperties', 'title', 'description', 'default', 'examples'
    ]::text[])) then
      return false;
    end if;
  end loop;

  if p_schema ? '$ref' then
    if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_schema)) <> 1
      or pg_catalog.jsonb_typeof(p_schema -> '$ref') <> 'string'
      or p_schema ->> '$ref' !~ '^#/\$defs/[A-Za-z0-9_.-]{1,100}$' then
      return false;
    end if;
    ref_key := substring(p_schema ->> '$ref' from 9);
    if pg_catalog.jsonb_typeof(p_root_schema -> '$defs' -> ref_key) <> 'object' then
      return false;
    end if;
    return app.m4_json_schema_value_valid(
      p_root_schema,
      p_root_schema -> '$defs' -> ref_key,
      p_value,
      p_depth + 1
    );
  end if;

  if p_schema ? 'enum' then
    if pg_catalog.jsonb_typeof(p_schema -> 'enum') <> 'array'
      or pg_catalog.jsonb_array_length(p_schema -> 'enum') = 0
      or pg_catalog.jsonb_array_length(p_schema -> 'enum') > 100
      or not exists (
        select 1
        from pg_catalog.jsonb_array_elements(p_schema -> 'enum') candidate(value)
        where candidate.value = p_value
      ) then
      return false;
    end if;
  end if;
  if p_schema ? 'const' and p_schema -> 'const' <> p_value then
    return false;
  end if;

  if p_schema ? 'type' then
    if pg_catalog.jsonb_typeof(p_schema -> 'type') = 'string' then
      type_matches := app.m4_json_schema_type_matches(p_schema ->> 'type', p_value);
    elsif pg_catalog.jsonb_typeof(p_schema -> 'type') = 'array' then
      if pg_catalog.jsonb_array_length(p_schema -> 'type') = 0
        or pg_catalog.jsonb_array_length(p_schema -> 'type') > 7
        or exists (
          select 1 from pg_catalog.jsonb_array_elements(p_schema -> 'type') entry(value)
          where pg_catalog.jsonb_typeof(entry.value) <> 'string'
        ) then
        return false;
      end if;
      select coalesce(pg_catalog.bool_or(
        app.m4_json_schema_type_matches(entry.value #>> '{}', p_value)
      ), false) into type_matches
      from pg_catalog.jsonb_array_elements(p_schema -> 'type') entry(value);
    else
      return false;
    end if;
    if not type_matches
      and not (actual_type = 'null'
        and coalesce((p_schema ->> 'nullable')::boolean, false)) then
      return false;
    end if;
  elsif p_schema ? 'nullable'
    and pg_catalog.jsonb_typeof(p_schema -> 'nullable') <> 'boolean' then
    return false;
  end if;

  if actual_type = 'null' then
    return not (p_schema ? 'type')
      or type_matches
      or coalesce((p_schema ->> 'nullable')::boolean, false);
  end if;

  if actual_type = 'object' then
    select pg_catalog.count(*)::integer into property_count
    from pg_catalog.jsonb_object_keys(p_value);
    if p_schema ? 'minProperties' and (
      pg_catalog.jsonb_typeof(p_schema -> 'minProperties') <> 'number'
      or (p_schema ->> 'minProperties')::integer < 0
      or property_count < (p_schema ->> 'minProperties')::integer
    ) then return false; end if;
    if p_schema ? 'maxProperties' and (
      pg_catalog.jsonb_typeof(p_schema -> 'maxProperties') <> 'number'
      or (p_schema ->> 'maxProperties')::integer < 0
      or property_count > (p_schema ->> 'maxProperties')::integer
    ) then return false; end if;
    if p_schema ? 'properties'
      and pg_catalog.jsonb_typeof(p_schema -> 'properties') <> 'object' then
      return false;
    end if;
    if p_schema ? 'required' then
      if pg_catalog.jsonb_typeof(p_schema -> 'required') <> 'array'
        or exists (
          select 1 from pg_catalog.jsonb_array_elements(p_schema -> 'required') entry(value)
          where pg_catalog.jsonb_typeof(entry.value) <> 'string'
        ) then return false; end if;
      for required_key in
        select pg_catalog.jsonb_array_elements_text(p_schema -> 'required')
      loop
        if not p_value ? required_key then return false; end if;
      end loop;
    end if;
    if p_schema ? 'additionalProperties'
      and pg_catalog.jsonb_typeof(p_schema -> 'additionalProperties')
        not in ('boolean', 'object') then
      return false;
    end if;
    for field_key in select pg_catalog.jsonb_object_keys(p_value) loop
      if coalesce(p_schema -> 'properties', '{}'::jsonb) ? field_key then
        if not app.m4_json_schema_value_valid(
          p_root_schema,
          p_schema -> 'properties' -> field_key,
          p_value -> field_key,
          p_depth + 1
        ) then return false; end if;
      elsif p_schema ? 'additionalProperties' then
        additional_schema := p_schema -> 'additionalProperties';
        if additional_schema = 'false'::jsonb then
          return false;
        elsif pg_catalog.jsonb_typeof(additional_schema) = 'object'
          and not app.m4_json_schema_value_valid(
            p_root_schema, additional_schema, p_value -> field_key, p_depth + 1
          ) then
          return false;
        end if;
      end if;
    end loop;
  elsif actual_type = 'array' then
    item_count := pg_catalog.jsonb_array_length(p_value);
    if p_schema ? 'minItems' and (
      pg_catalog.jsonb_typeof(p_schema -> 'minItems') <> 'number'
      or (p_schema ->> 'minItems')::integer < 0
      or item_count < (p_schema ->> 'minItems')::integer
    ) then return false; end if;
    if p_schema ? 'maxItems' and (
      pg_catalog.jsonb_typeof(p_schema -> 'maxItems') <> 'number'
      or (p_schema ->> 'maxItems')::integer < 0
      or item_count > (p_schema ->> 'maxItems')::integer
    ) then return false; end if;
    if p_schema ? 'items' then
      if pg_catalog.jsonb_typeof(p_schema -> 'items') <> 'object' then
        return false;
      end if;
      for item_value in select value from pg_catalog.jsonb_array_elements(p_value)
      loop
        if not app.m4_json_schema_value_valid(
          p_root_schema, p_schema -> 'items', item_value, p_depth + 1
        ) then return false; end if;
      end loop;
    end if;
  elsif actual_type = 'string' then
    string_value := p_value #>> '{}';
    if p_schema ? 'minLength' and (
      pg_catalog.jsonb_typeof(p_schema -> 'minLength') <> 'number'
      or (p_schema ->> 'minLength')::integer < 0
      or pg_catalog.char_length(string_value) < (p_schema ->> 'minLength')::integer
    ) then return false; end if;
    if p_schema ? 'maxLength' and (
      pg_catalog.jsonb_typeof(p_schema -> 'maxLength') <> 'number'
      or (p_schema ->> 'maxLength')::integer < 0
      or pg_catalog.char_length(string_value) > (p_schema ->> 'maxLength')::integer
    ) then return false; end if;
    if p_schema ? 'pattern' then
      if pg_catalog.jsonb_typeof(p_schema -> 'pattern') <> 'string'
        or pg_catalog.char_length(p_schema ->> 'pattern') > 256
        or string_value !~ (p_schema ->> 'pattern') then
        return false;
      end if;
    end if;
    if p_schema ? 'format' then
      if pg_catalog.jsonb_typeof(p_schema -> 'format') <> 'string' then return false; end if;
      format_name := p_schema ->> 'format';
      if format_name = 'uuid' then
        if string_value !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
      elsif format_name = 'date' then
        if string_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          or (string_value::date)::text <> string_value then return false; end if;
      elsif format_name = 'date-time' then
        if string_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,6})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$'
          or string_value::timestamptz is null then return false; end if;
      else
        return false;
      end if;
    end if;
  elsif actual_type = 'number' then
    numeric_value := (p_value #>> '{}')::numeric;
    if p_schema ? 'minimum' and (
      pg_catalog.jsonb_typeof(p_schema -> 'minimum') <> 'number'
      or numeric_value < (p_schema ->> 'minimum')::numeric
    ) then return false; end if;
    if p_schema ? 'maximum' and (
      pg_catalog.jsonb_typeof(p_schema -> 'maximum') <> 'number'
      or numeric_value > (p_schema ->> 'maximum')::numeric
    ) then return false; end if;
    if p_schema ? 'exclusiveMinimum' and (
      pg_catalog.jsonb_typeof(p_schema -> 'exclusiveMinimum') <> 'number'
      or numeric_value <= (p_schema ->> 'exclusiveMinimum')::numeric
    ) then return false; end if;
    if p_schema ? 'exclusiveMaximum' and (
      pg_catalog.jsonb_typeof(p_schema -> 'exclusiveMaximum') <> 'number'
      or numeric_value >= (p_schema ->> 'exclusiveMaximum')::numeric
    ) then return false; end if;
  end if;
  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range
    or invalid_regular_expression or datetime_field_overflow then
    return false;
end;
$$;

create function app.m4_validate_document_fields(
  p_field_schema jsonb,
  p_fields jsonb
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_field_schema is null or pg_catalog.jsonb_typeof(p_field_schema) <> 'object'
    or p_fields is null or pg_catalog.jsonb_typeof(p_fields) <> 'object'
    or pg_catalog.octet_length(p_field_schema::text) > 262144
    or pg_catalog.octet_length(p_fields::text) > 262144
    or not app.m3_inert_json_is_safe(p_fields) then
    return false;
  end if;
  return app.m4_json_schema_value_valid(p_field_schema, p_field_schema, p_fields, 0);
exception when others then
  return false;
end;
$$;

create function app.m4_deal_source_snapshot(
  p_workspace_id uuid,
  p_deal_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'schema_version', 4,
    'deal', pg_catalog.jsonb_build_object(
      'id', deal.id,
      'deal_type_key', deal.deal_type_key,
      'currency_code', deal.currency_code,
      'status', deal.status,
      'lifecycle_status', deal.lifecycle_status,
      'workflow_version_id', deal.workflow_version_id,
      'workflow_state_key', deal.workflow_state_key,
      'location_id', deal.location_id,
      'legal_entity_id', deal.legal_entity_id,
      'version', deal.version
    ),
    'participants', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'participant_id', participant.id,
        'party_id', party.id,
        'party_type', party.party_type,
        'display_name', party.display_name,
        'role_key', participant.role_key,
        'is_primary', participant.is_primary,
        'status', participant.status
      ) order by participant.id)
      from public.deal_participants participant
      join public.parties party
        on party.workspace_id = participant.workspace_id
       and party.id = participant.party_id
      where participant.workspace_id = p_workspace_id
        and participant.deal_id = p_deal_id
        and participant.status = 'active'
    ), '[]'::jsonb),
    'inventory_units', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'link_id', link.id,
        'inventory_unit_id', inventory.id,
        'vehicle_id', vehicle.id,
        'vin', vehicle.vin::text,
        'stock_number', inventory.stock_number::text,
        'advertised_price_minor', inventory.advertised_price_minor::text,
        'currency_code', inventory.currency_code,
        'role_key', link.role_key,
        'status', link.status
      ) order by link.id)
      from public.deal_inventory_units link
      join public.inventory_units inventory
        on inventory.workspace_id = link.workspace_id
       and inventory.id = link.inventory_unit_id
      join public.vehicles vehicle
        on vehicle.workspace_id = inventory.workspace_id
       and vehicle.id = inventory.vehicle_id
      where link.workspace_id = p_workspace_id
        and link.deal_id = p_deal_id
        and link.status = 'active'
    ), '[]'::jsonb),
    'line_items', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', item.id,
        'key', item.key,
        'item_type', item.item_type,
        'label', item.label,
        'quantity', item.quantity_text,
        'unit_amount_minor', item.unit_amount_minor::text,
        'currency_code', item.currency_code,
        'tax_classification_key', item.tax_classification_key,
        'sort_order', item.sort_order,
        'status', item.status,
        'version', item.version
      ) order by item.sort_order, item.id)
      from public.deal_line_items item
      where item.workspace_id = p_workspace_id
        and item.deal_id = p_deal_id
        and item.status = 'active'
    ), '[]'::jsonb),
    'trade_ins', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', trade.id,
        'allowance_minor', trade.allowance_minor::text,
        'lien_amount_minor', trade.lien_amount_minor::text,
        'payoff_amount_minor', trade.payoff_amount_minor::text,
        'currency_code', trade.currency_code,
        'tax_eligibility_inputs', trade.tax_eligibility_inputs
      ) order by trade.id)
      from public.trade_ins trade
      where trade.workspace_id = p_workspace_id
        and trade.deal_id = p_deal_id
        and trade.status <> 'cancelled'
    ), '[]'::jsonb)
  )
  from public.deals deal
  where deal.workspace_id = p_workspace_id
    and deal.id = p_deal_id
    and deal.lifecycle_status = 'active';
$$;

-- Tenant-neutral, versioned projection used by the trusted tax runtime. Every
-- amount comes from immutable deal source rows; unsupported classifications or
-- fractional minor-unit totals fail closed instead of accepting browser input.
-- Signed discount rows become separate nonnegative buckets; they never reduce
-- or disguise the corresponding positive fee bucket in the evidence snapshot.
create function app.m4_deal_tax_input(
  p_deal_context jsonb,
  p_jurisdiction_code text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  deal_currency text;
  line_item jsonb;
  trade_in jsonb;
  eligibility jsonb;
  item_type text;
  classification text;
  quantity_value numeric;
  unit_amount numeric;
  extended_amount numeric;
  vehicle_price numeric := 0;
  taxable_fees numeric := 0;
  taxable_discounts numeric := 0;
  non_taxable_fees numeric := 0;
  non_taxable_discounts numeric := 0;
  trade_credit numeric := 0;
  eligibility_confirmed boolean := false;
  review_reference text;
  bigint_max constant numeric := 9223372036854775807;
begin
  if pg_catalog.jsonb_typeof(p_deal_context) is distinct from 'object'
    or p_deal_context ->> 'schema_version' is distinct from '4'
    or pg_catalog.jsonb_typeof(p_deal_context -> 'deal') is distinct from 'object'
    or pg_catalog.jsonb_typeof(p_deal_context -> 'line_items') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_deal_context -> 'trade_ins') is distinct from 'array'
    or coalesce(p_jurisdiction_code, '') !~ '^[A-Z]{2}(?:-[A-Z0-9]{1,3})?$' then
    raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
  end if;
  deal_currency := p_deal_context -> 'deal' ->> 'currency_code';
  if coalesce(deal_currency, '') !~ '^[A-Z]{3}$' then
    raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
  end if;

  for line_item in
    select value from pg_catalog.jsonb_array_elements(p_deal_context -> 'line_items')
  loop
    if pg_catalog.jsonb_typeof(line_item) is distinct from 'object'
      or pg_catalog.jsonb_typeof(line_item -> 'item_type') is distinct from 'string'
      or pg_catalog.jsonb_typeof(line_item -> 'quantity') is distinct from 'string'
      or pg_catalog.jsonb_typeof(line_item -> 'unit_amount_minor') is distinct from 'string'
      or pg_catalog.jsonb_typeof(line_item -> 'currency_code') is distinct from 'string'
      or line_item ->> 'currency_code' is distinct from deal_currency
      or coalesce(line_item ->> 'quantity', '')
        !~ '^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$'
      or coalesce(line_item ->> 'unit_amount_minor', '')
        !~ '^-?(?:0|[1-9][0-9]{0,18})$' then
      raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
    end if;
    item_type := line_item ->> 'item_type';
    classification := line_item ->> 'tax_classification_key';
    quantity_value := (line_item ->> 'quantity')::numeric;
    unit_amount := (line_item ->> 'unit_amount_minor')::numeric;
    extended_amount := quantity_value * unit_amount;
    if extended_amount <> pg_catalog.trunc(extended_amount)
      or pg_catalog.abs(extended_amount) > bigint_max then
      raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
    end if;

    if item_type = 'vehicle' then
      if extended_amount < 0 then
        raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
      end if;
      vehicle_price := vehicle_price + extended_amount;
    elsif item_type in ('fee', 'accessory', 'service', 'other', 'discount') then
      if classification is null
        or classification not in ('taxable', 'non_taxable')
        or item_type = 'discount' and extended_amount > 0
        or item_type <> 'discount' and extended_amount < 0 then
        raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
      end if;
      if classification = 'taxable' then
        if item_type = 'discount' then
          taxable_discounts := taxable_discounts - extended_amount;
        else
          taxable_fees := taxable_fees + extended_amount;
        end if;
      else
        if item_type = 'discount' then
          non_taxable_discounts := non_taxable_discounts - extended_amount;
        else
          non_taxable_fees := non_taxable_fees + extended_amount;
        end if;
      end if;
    else
      raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
    end if;
  end loop;

  if vehicle_price < 0
    or taxable_fees < 0 or taxable_discounts < 0
    or non_taxable_fees < 0 or non_taxable_discounts < 0
    or vehicle_price > bigint_max
    or taxable_fees > bigint_max or taxable_discounts > bigint_max
    or non_taxable_fees > bigint_max or non_taxable_discounts > bigint_max then
    raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
  end if;

  for trade_in in
    select value from pg_catalog.jsonb_array_elements(p_deal_context -> 'trade_ins')
  loop
    eligibility := trade_in -> 'tax_eligibility_inputs';
    if pg_catalog.jsonb_typeof(trade_in) is distinct from 'object'
      or pg_catalog.jsonb_typeof(trade_in -> 'allowance_minor') is distinct from 'string'
      or pg_catalog.jsonb_typeof(trade_in -> 'currency_code') is distinct from 'string'
      or trade_in ->> 'currency_code' is distinct from deal_currency
      or coalesce(trade_in ->> 'allowance_minor', '') !~ '^(?:0|[1-9][0-9]{0,18})$'
      or pg_catalog.jsonb_typeof(eligibility) is distinct from 'object'
      or pg_catalog.jsonb_typeof(eligibility -> 'declaredEligible')
        is distinct from 'boolean' then
      raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
    end if;
    if (eligibility ->> 'declaredEligible')::boolean then
      if pg_catalog.jsonb_typeof(eligibility -> 'jurisdiction')
          is distinct from 'string'
        or eligibility ->> 'jurisdiction' is distinct from p_jurisdiction_code then
        raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
      end if;
      eligibility_confirmed := true;
      trade_credit := trade_credit + (trade_in ->> 'allowance_minor')::numeric;
    end if;
  end loop;
  if trade_credit > bigint_max then
    raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
  end if;
  if eligibility_confirmed then
    review_reference := 'deal-trade-in:' || pg_catalog.left(
      app.m4_canonical_fingerprint(p_deal_context -> 'trade_ins'), 32
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'vehicle_price_minor', vehicle_price::bigint::text,
    'taxable_fees_minor', taxable_fees::bigint::text,
    'taxable_discounts_minor', taxable_discounts::bigint::text,
    'non_taxable_fees_minor', non_taxable_fees::bigint::text,
    'non_taxable_discounts_minor', non_taxable_discounts::bigint::text,
    'eligible_trade_in_credit_minor', trade_credit::bigint::text,
    'trade_in_eligibility', case when eligibility_confirmed then
      pg_catalog.jsonb_build_object(
        'explicitly_confirmed', true,
        'review_reference', review_reference
      )
    else 'null'::jsonb end
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '23514', message = 'runtime_evidence.deal_tax_input_invalid';
end;
$$;

-- Build preview input from exactly one canonical deal-source read. Official
-- generation uses its already receipt-verified source value directly so a
-- later statement cannot mix changed rows into the immutable snapshot.
create function app.m4_document_input_snapshot(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_document_date date,
  p_intended_signature_date date,
  p_locale text,
  p_document_fields jsonb,
  p_calculation_evidence jsonb,
  p_tax_evidence jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select source.snapshot || pg_catalog.jsonb_build_object(
    'document', pg_catalog.jsonb_build_object(
      'document_date', p_document_date,
      'intended_signature_date', p_intended_signature_date,
      'locale', p_locale,
      'fields', p_document_fields
    ),
    'calculation', p_calculation_evidence,
    'tax', p_tax_evidence
  )
  from (
    select app.m4_deal_source_snapshot(p_workspace_id, p_deal_id) as snapshot
  ) source
  where source.snapshot is not null;
$$;

create function app.request_official_document(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_document_type_id uuid,
  p_template_version_id uuid,
  p_locale text,
  p_document_date date,
  p_intended_signature_date date,
  p_document_fields jsonb,
  p_calculation_evidence jsonb,
  p_tax_evidence jsonb,
  p_supersedes_document_id uuid,
  p_supersedes_expected_version bigint,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_id uuid,
  official_number text,
  document_status text,
  number_allocation_id uuid,
  outbox_event_id uuid,
  job_id uuid,
  audit_event_id uuid,
  aggregate_version bigint,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  normalized_locale text := pg_catalog.btrim(coalesce(p_locale, ''));
  request_fingerprint text;
  existing_document public.documents%rowtype;
  document_type public.document_types%rowtype;
  template public.document_template_versions%rowtype;
  numbering_version public.numbering_definition_versions%rowtype;
  numbering_definition public.numbering_definitions%rowtype;
  calculation_version public.calculation_versions%rowtype;
  calculation_definition_key text;
  tax_version public.tax_pack_versions%rowtype;
  tax_pack_key text;
  tax_assignment public.tax_pack_assignments%rowtype;
  trusted_calculation public.runtime_evidence_records%rowtype;
  trusted_tax public.runtime_evidence_records%rowtype;
  calculation_evidence_id uuid;
  tax_evidence_id uuid;
  current_deal_context jsonb;
  current_deal_context_checksum text;
  current_deal_currency_code text;
  expected_tax_input jsonb;
  expected_tax_input_checksum text;
  deal public.deals%rowtype;
  workflow_dependency record;
  legal_entity_key text;
  location_key text;
  prior_document public.documents%rowtype;
  prior_document_key text;
  scope_key text;
  new_document_id uuid := pg_catalog.gen_random_uuid();
  allocation record;
  input_snapshot jsonb;
  input_checksum text;
  exact_versions jsonb;
  exact_versions_checksum text;
  calculation_snapshot_id_value uuid;
  tax_snapshot_id_value uuid;
  queued_job record;
  number_audit_event_id uuid;
  official_audit_event_id uuid;
  result_version bigint := 1;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'documents.generate_approved',
    true
  );
  perform app.require_vertical_slice_permission(p_workspace_id, 'documents.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'deals.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'crm.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');
  if p_supersedes_document_id is not null then
    perform app.require_vertical_slice_permission(
      p_workspace_id,
      'documents.supersede',
      true
    );
  end if;

  if pg_catalog.char_length(normalized_idempotency) not between 8 and 200
    or normalized_reason = ''
    or pg_catalog.char_length(normalized_reason) > 2000
    or normalized_locale !~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'
    or p_document_date is null
    or (p_supersedes_document_id is null)
      <> (p_supersedes_expected_version is null)
    or p_supersedes_expected_version is not null
      and p_supersedes_expected_version <= 0
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid official document command';
  end if;
  if p_intended_signature_date is not null
    and p_intended_signature_date < p_document_date then
    raise exception using errcode = '23514', message = 'document.date_invalid';
  end if;

  if p_calculation_evidence is not null then
    if pg_catalog.jsonb_typeof(p_calculation_evidence) <> 'object'
      or coalesce(p_calculation_evidence ->> 'evidenceId', '')
        !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception using errcode = '23514', message = 'document.official_calculation_receipt_invalid';
    end if;
    calculation_evidence_id := (p_calculation_evidence ->> 'evidenceId')::uuid;
  end if;
  if p_tax_evidence is not null then
    if pg_catalog.jsonb_typeof(p_tax_evidence) <> 'object'
      or coalesce(p_tax_evidence ->> 'evidenceId', '')
        !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception using errcode = '23514', message = 'document.official_tax_receipt_invalid';
    end if;
    tax_evidence_id := (p_tax_evidence ->> 'evidenceId')::uuid;
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'documentTypeId', p_document_type_id,
      'templateVersionId', p_template_version_id,
      'locale', normalized_locale,
      'documentDate', p_document_date,
      'intendedSignatureDate', p_intended_signature_date,
      'fields', p_document_fields,
      'calculationEvidenceId', calculation_evidence_id,
      'taxEvidenceId', tax_evidence_id,
      'supersedesDocumentId', p_supersedes_document_id,
      'supersedesExpectedVersion', p_supersedes_expected_version,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fofficial_document\x1f' || actor_user_id::text
      || E'\x1f' || normalized_idempotency,
    0
  ));

  select document.* into existing_document
  from public.documents document
  where document.workspace_id = p_workspace_id
    and document.idempotency_key = normalized_idempotency;
  if found then
    if existing_document.mode <> 'official'
      or existing_document.command_fingerprint <> request_fingerprint
      or existing_document.created_by <> actor_user_id then
      raise exception using errcode = '23505', message = 'official document idempotency conflict';
    end if;
    return query
    select
      existing_document.id,
      existing_document.official_number,
      existing_document.status,
      existing_document.number_allocation_id,
      mapping.outbox_event_id,
      mapping.job_id,
      audit.id,
      existing_document.aggregate_version,
      true
    from public.document_render_jobs mapping
    join lateral (
      select event.id from public.audit_events event
      where event.workspace_id = existing_document.workspace_id
        and event.entity_type = 'document'
        and event.entity_id = existing_document.id
        and event.action = 'document.official_requested'
      order by event.occurred_at, event.id limit 1
    ) audit on true
    where mapping.workspace_id = existing_document.workspace_id
      and mapping.document_id = existing_document.id;
    return;
  end if;

  -- Every supported deal, line-item, participant, inventory-link, and trade-in
  -- mutation locks its parent deal first. Holding that same lock across source
  -- capture, evidence validation, and number allocation makes this command the
  -- serialization peer of those writers; the second checksum remains a
  -- defense-in-depth guard for any future source table.
  select candidate.* into deal
  from public.deals candidate
  where candidate.workspace_id = p_workspace_id
    and candidate.id = p_deal_id
  for update;
  if not found or deal.lifecycle_status <> 'active' then
    raise exception using errcode = '23514', message = 'document.official_deal_not_eligible';
  end if;

  -- The parent lock serializes supported child inserts. Lock every existing
  -- source row in a deterministic table/id order as well, including joined
  -- party, inventory, and vehicle facts that can change without updating the
  -- deal row. No source writer can now commit between capture and allocation.
  perform participant.id
  from public.deal_participants participant
  where participant.workspace_id = p_workspace_id
    and participant.deal_id = p_deal_id
    and participant.status = 'active'
  order by participant.id
  for share of participant;
  perform party.id
  from public.parties party
  join public.deal_participants participant
    on participant.workspace_id = party.workspace_id
   and participant.party_id = party.id
   and participant.deal_id = p_deal_id
   and participant.status = 'active'
  where party.workspace_id = p_workspace_id
  order by party.id
  for share of party;
  perform link.id
  from public.deal_inventory_units link
  where link.workspace_id = p_workspace_id
    and link.deal_id = p_deal_id
    and link.status = 'active'
  order by link.id
  for share of link;
  perform inventory.id
  from public.inventory_units inventory
  join public.deal_inventory_units link
    on link.workspace_id = inventory.workspace_id
   and link.inventory_unit_id = inventory.id
   and link.deal_id = p_deal_id
   and link.status = 'active'
  where inventory.workspace_id = p_workspace_id
  order by inventory.id
  for share of inventory;
  perform vehicle.id
  from public.vehicles vehicle
  join public.inventory_units inventory
    on inventory.workspace_id = vehicle.workspace_id
   and inventory.vehicle_id = vehicle.id
  join public.deal_inventory_units link
    on link.workspace_id = inventory.workspace_id
   and link.inventory_unit_id = inventory.id
   and link.deal_id = p_deal_id
   and link.status = 'active'
  where vehicle.workspace_id = p_workspace_id
  order by vehicle.id
  for share of vehicle;
  perform item.id
  from public.deal_line_items item
  where item.workspace_id = p_workspace_id
    and item.deal_id = p_deal_id
    and item.status = 'active'
  order by item.id
  for share of item;
  perform trade.id
  from public.trade_ins trade
  where trade.workspace_id = p_workspace_id
    and trade.deal_id = p_deal_id
    and trade.status <> 'cancelled'
  order by trade.id
  for share of trade;

  current_deal_context := app.m4_deal_source_snapshot(p_workspace_id, p_deal_id);
  if current_deal_context is null then
    raise exception using errcode = '23514', message = 'document.official_deal_not_eligible';
  end if;
  current_deal_context_checksum := app.m4_canonical_fingerprint(
    current_deal_context
  );
  current_deal_currency_code := current_deal_context -> 'deal' ->> 'currency_code';
  if coalesce(current_deal_currency_code, '') !~ '^[A-Z]{3}$' then
    raise exception using errcode = '23514', message = 'document.official_deal_not_eligible';
  end if;

  if calculation_evidence_id is not null then
    select evidence.* into trusted_calculation
    from public.runtime_evidence_records evidence
    where evidence.workspace_id = p_workspace_id
      and evidence.id = calculation_evidence_id
      and evidence.evidence_type = 'calculation'
      and evidence.official_eligible
      and evidence.actor_user_id = app.current_user_id()
      and evidence.deal_id = p_deal_id
      and evidence.deal_context_checksum = current_deal_context_checksum
      and evidence.expires_at > pg_catalog.statement_timestamp()
      and not exists (
        select 1 from public.runtime_evidence_consumptions consumption
        where consumption.workspace_id = evidence.workspace_id
          and consumption.evidence_id = evidence.id
      );
    if not found
      or trusted_calculation.snapshot_checksum is distinct from
        app.m4_canonical_fingerprint(trusted_calculation.snapshot - 'checksum')
      or trusted_calculation.snapshot_checksum is distinct from
        trusted_calculation.snapshot ->> 'checksum'
      or trusted_calculation.snapshot -> 'input' is distinct from current_deal_context
      or trusted_calculation.snapshot -> 'inputBinding' is distinct from
        pg_catalog.jsonb_build_object(
          'mapperVersion', 'deal-runtime-input-v1',
          'dealContextChecksum', current_deal_context_checksum,
          'inputProjectionChecksum', app.m4_canonical_fingerprint(current_deal_context)
        ) then
      raise exception using errcode = '23514', message = 'document.official_calculation_receipt_invalid';
    end if;
    p_calculation_evidence := trusted_calculation.snapshot;
  end if;
  if tax_evidence_id is not null then
    select evidence.* into trusted_tax
    from public.runtime_evidence_records evidence
    where evidence.workspace_id = p_workspace_id
      and evidence.id = tax_evidence_id
      and evidence.evidence_type = 'tax'
      and evidence.official_eligible
      and evidence.actor_user_id = app.current_user_id()
      and evidence.deal_id = p_deal_id
      and evidence.deal_context_checksum = current_deal_context_checksum
      and evidence.expires_at > pg_catalog.statement_timestamp()
      and not exists (
        select 1 from public.runtime_evidence_consumptions consumption
        where consumption.workspace_id = evidence.workspace_id
          and consumption.evidence_id = evidence.id
      );
    if not found
      or trusted_tax.snapshot_checksum is distinct from
        app.m4_canonical_fingerprint(trusted_tax.snapshot - 'checksum')
      or trusted_tax.snapshot_checksum is distinct from
        trusted_tax.snapshot ->> 'checksum' then
      raise exception using errcode = '23514', message = 'document.official_tax_receipt_invalid';
    end if;
    if trusted_tax.snapshot ->> 'currency' is distinct from current_deal_currency_code then
      raise exception using errcode = '23514', message = 'document.official_tax_receipt_invalid';
    end if;
    if not app.m4_tax_override_evidence_valid(trusted_tax.snapshot) then
      raise exception using errcode = '23514', message = 'document.official_tax_receipt_invalid';
    end if;
    begin
      expected_tax_input := app.m4_deal_tax_input(
        current_deal_context,
        trusted_tax.snapshot ->> 'jurisdiction'
      );
    exception when check_violation then
      raise exception using errcode = '23514', message = 'document.official_tax_receipt_invalid';
    end;
    expected_tax_input_checksum := app.m4_canonical_fingerprint(expected_tax_input);
    if trusted_tax.snapshot -> 'input' is distinct from expected_tax_input
      or trusted_tax.snapshot -> 'inputBinding' is distinct from
        pg_catalog.jsonb_build_object(
          'mapperVersion', 'deal-runtime-input-v1',
          'dealContextChecksum', current_deal_context_checksum,
          'inputProjectionChecksum', expected_tax_input_checksum
        ) then
      raise exception using errcode = '23514', message = 'document.official_tax_receipt_invalid';
    end if;
    p_tax_evidence := trusted_tax.snapshot;
  end if;

  select target.* into document_type
  from public.document_types target
  where target.workspace_id = p_workspace_id
    and target.id = p_document_type_id
    and target.status = 'active'
    and target.production_enabled
    and target.official_generation_enabled
    and target.activation_status = 'active'
  for share of target;
  if not found then
    raise exception using errcode = '23514', message = 'document.official_missing_document_type_approval';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fconfiguration_artifact\x1fdocument_type\x1f'
      || document_type.id::text,
    0
  ));
  if not app.m4_exact_approval_valid(
    p_workspace_id,
    document_type.approval_record_id,
    'document_type',
    'document.' || pg_catalog.regexp_replace(pg_catalog.lower(document_type.key::text), '[^a-z0-9_]+', '_', 'g'),
    document_type.version,
    document_type.id,
    document_type.checksum
  ) then
    raise exception using errcode = '23514', message = 'document.official_missing_document_type_approval';
  end if;

  select candidate.* into template
  from public.document_template_versions candidate
  where candidate.workspace_id = p_workspace_id
    and candidate.id = p_template_version_id
    and candidate.document_type_id = document_type.id
    and candidate.locale = normalized_locale
    and candidate.status = 'active'
    and candidate.template_class = 'tenant_approved'
    and candidate.production_approved
    and candidate.activation_status = 'active'
  for share of candidate;
  if not found or template.field_schema_checksum <> document_type.field_schema_checksum then
    raise exception using errcode = '23514', message = 'document.official_missing_template_approval';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fconfiguration_artifact\x1fdocument_template\x1f'
      || template.id::text,
    0
  ));
  if not app.m4_exact_approval_valid(
    p_workspace_id,
    template.approval_record_id,
    'document_template',
    'template.' || pg_catalog.regexp_replace(pg_catalog.lower(document_type.key::text), '[^a-z0-9_]+', '_', 'g')
      || '.' || pg_catalog.replace(pg_catalog.lower(template.locale), '-', '_'),
    template.version,
    template.id,
    template.source_bundle_checksum
  ) then
    raise exception using errcode = '23514', message = 'document.official_missing_template_approval';
  end if;
  if not app.m4_validate_document_fields(document_type.field_schema, p_document_fields) then
    raise exception using errcode = '23514', message = 'document.official_field_schema_invalid';
  end if;

  select version.* into numbering_version
  from public.numbering_definition_versions version
  where version.workspace_id = p_workspace_id
    and version.id = document_type.numbering_definition_version_id
    and version.status = 'active'
  for share of version;
  if found then
    select definition.* into numbering_definition
    from public.numbering_definitions definition
    where definition.workspace_id = numbering_version.workspace_id
      and definition.id = numbering_version.numbering_definition_id
    for share of definition;
  end if;
  if found then
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(
      p_workspace_id::text
        || E'\x1fconfiguration_artifact\x1fnumbering_definition\x1f'
        || numbering_version.id::text,
      0
    ));
  end if;
  if not found or not app.m4_exact_approval_valid(
    p_workspace_id,
    numbering_version.approval_record_id,
    'numbering_definition',
    'numbering.' || numbering_definition.key::text,
    numbering_version.version,
    numbering_version.id,
    numbering_version.checksum
  ) then
    raise exception using errcode = '23514', message = 'document.official_missing_numbering_approval';
  end if;

  if document_type.workflow_version_id is not null then
    perform version.id
    from public.workflow_versions version
    where version.workspace_id = p_workspace_id
      and version.id = document_type.workflow_version_id
      and version.status in ('active', 'retired')
    for share of version;
    if not found then
      raise exception using errcode = '23514', message = 'document.official_workflow_inactive';
    end if;
  end if;
  select dependency.* into workflow_dependency
  from app.m4_document_workflow_dependency(
    p_workspace_id,
    p_deal_id,
    document_type.workflow_version_id
  ) dependency;
  if document_type.workflow_version_id is not null
    and not workflow_dependency.deal_matches then
    raise exception using errcode = '23514', message = 'document.official_workflow_mismatch';
  end if;
  if document_type.workflow_version_id is not null
    and not workflow_dependency.workflow_active then
    raise exception using errcode = '23514', message = 'document.official_workflow_inactive';
  end if;
  if document_type.workflow_version_id is not null
    and not workflow_dependency.approval_valid then
    raise exception using errcode = '23514', message = 'document.official_workflow_approval_invalid';
  end if;
  select entity.key, location.key::text
    into legal_entity_key, location_key
  from public.legal_entities entity
  join public.locations location
    on location.workspace_id = entity.workspace_id
   and location.id = deal.location_id
   and location.status = 'active'
  where entity.workspace_id = p_workspace_id
    and entity.id = deal.legal_entity_id
    and entity.status = 'active'
  for share of entity, location;
  if not found then
    raise exception using errcode = '23514', message = 'document.official_deal_scope_unavailable';
  end if;

  if document_type.calculation_version_id is null then
    if p_calculation_evidence is not null then
      raise exception using errcode = '23514', message = 'document.official_unexpected_calculation';
    end if;
  else
    select version.*
      into calculation_version
    from public.calculation_versions version
    join public.calculation_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.calculation_definition_id
    where version.workspace_id = p_workspace_id
      and version.id = document_type.calculation_version_id
      and version.status = 'active'
    for share of version, definition;
    select definition.key::text into calculation_definition_key
    from public.calculation_definitions definition
    where definition.workspace_id = calculation_version.workspace_id
      and definition.id = calculation_version.calculation_definition_id;
    if found then
      perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(
        p_workspace_id::text
          || E'\x1fconfiguration_artifact\x1fcalculation\x1f'
          || calculation_version.id::text,
        0
      ));
    end if;
    if not found or not app.m4_exact_approval_valid(
      p_workspace_id,
      calculation_version.approval_record_id,
      'calculation',
      'formula.' || calculation_definition_key,
      calculation_version.version,
      calculation_version.id,
      calculation_version.checksum
    ) then
      raise exception using errcode = '23514', message = 'document.official_calculation_version_unapproved';
    end if;
    if p_calculation_evidence is null
      or pg_catalog.jsonb_typeof(p_calculation_evidence) is distinct from 'object'
      or trusted_calculation.calculation_version_id is distinct from calculation_version.id
      or p_calculation_evidence ->> 'versionId' is distinct from calculation_version.id::text
      or p_calculation_evidence ->> 'definitionChecksum' is distinct from calculation_version.checksum
      or pg_catalog.jsonb_typeof(p_calculation_evidence -> 'definition') is distinct from 'object'
      or p_calculation_evidence ->> 'engineVersion' is distinct from calculation_version.engine_version
      or pg_catalog.jsonb_typeof(p_calculation_evidence -> 'input') is distinct from 'object'
      or pg_catalog.jsonb_typeof(p_calculation_evidence -> 'output') is distinct from 'object'
      or pg_catalog.jsonb_typeof(p_calculation_evidence -> 'components') is distinct from 'array'
      or pg_catalog.jsonb_typeof(p_calculation_evidence -> 'rounding') is distinct from 'object'
      or coalesce(p_calculation_evidence ->> 'checksum', '') !~ '^[a-f0-9]{64}$'
      or app.m4_canonical_fingerprint(p_calculation_evidence - 'checksum') is distinct from
        p_calculation_evidence ->> 'checksum' then
      raise exception using errcode = '23514', message = 'document.official_calculation_evidence_invalid';
    end if;
  end if;
  if document_type.tax_pack_version_id is null then
    if p_tax_evidence is not null then
      raise exception using errcode = '23514', message = 'document.official_unexpected_tax';
    end if;
  else
    select version.* into tax_version
    from public.tax_pack_versions version
    join public.tax_packs pack
      on pack.workspace_id = version.workspace_id and pack.id = version.tax_pack_id
    where version.workspace_id = p_workspace_id
      and version.id = document_type.tax_pack_version_id
      and version.status = 'active'
    for share of version, pack;
    select pack.key::text into tax_pack_key
    from public.tax_packs pack
    where pack.workspace_id = tax_version.workspace_id
      and pack.id = tax_version.tax_pack_id;
    if found then
      perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(
        p_workspace_id::text
          || E'\x1fconfiguration_artifact\x1ftax_pack\x1f'
          || tax_version.id::text,
        0
      ));
    end if;
    if not found or not app.m4_exact_approval_valid(
      p_workspace_id,
      tax_version.approval_record_id,
      'tax_pack',
      'tax.' || tax_pack_key,
      tax_version.version,
      tax_version.id,
      tax_version.checksum
    ) then
      raise exception using errcode = '23514', message = 'document.official_tax_version_unapproved';
    end if;
    if p_tax_evidence is null
      or pg_catalog.jsonb_typeof(p_tax_evidence) is distinct from 'object'
      or trusted_tax.tax_pack_version_id is distinct from tax_version.id
      or p_tax_evidence ->> 'versionId' is distinct from tax_version.id::text
      or p_tax_evidence ->> 'packChecksum' is distinct from tax_version.checksum
      or pg_catalog.jsonb_typeof(p_tax_evidence -> 'pack') is distinct from 'object'
      or p_tax_evidence ->> 'engineVersion' is distinct from tax_version.engine_version
      or pg_catalog.jsonb_typeof(p_tax_evidence -> 'input') is distinct from 'object'
      or pg_catalog.jsonb_typeof(p_tax_evidence -> 'output') is distinct from 'object'
      or coalesce(p_tax_evidence ->> 'checksum', '') !~ '^[a-f0-9]{64}$'
      or app.m4_canonical_fingerprint(p_tax_evidence - 'checksum') is distinct from
        p_tax_evidence ->> 'checksum' then
      raise exception using errcode = '23514', message = 'document.official_tax_evidence_invalid';
    end if;
    select assignment.* into tax_assignment
    from public.tax_pack_assignments assignment
    where assignment.workspace_id = p_workspace_id
      and assignment.id = (p_tax_evidence ->> 'assignmentId')::uuid
      and assignment.id = trusted_tax.tax_assignment_id
      and assignment.tax_pack_version_id = tax_version.id
      and assignment.approval_record_id = tax_version.approval_record_id
      and assignment.jurisdiction_code = p_tax_evidence ->> 'jurisdiction'
      and assignment.context_key = p_tax_evidence ->> 'context'
      and assignment.currency_code = p_tax_evidence ->> 'currency'
      and assignment.effective_from <= (p_tax_evidence ->> 'transactionDate')::date
      and (coalesce(
        assignment.superseded_effective_to,
        assignment.effective_to
      ) is null or coalesce(
        assignment.superseded_effective_to,
        assignment.effective_to
      ) >= (p_tax_evidence ->> 'transactionDate')::date)
    for share of assignment;
    if not found or (p_tax_evidence ->> 'transactionDate')::date <> p_document_date then
      raise exception using errcode = '23514', message = 'document.official_tax_assignment_invalid';
    end if;
  end if;
  if p_tax_evidence ? 'override' then
    perform app.require_vertical_slice_permission(p_workspace_id, 'tax.override', true);
    if pg_catalog.btrim(coalesce(p_tax_evidence ->> 'overrideReason', '')) = '' then
      raise exception using errcode = '23514', message = 'tax override reason is required';
    end if;
  end if;

  -- Treat the second source read as the command's serialization point. Any
  -- source mutation committed while approvals/evidence were being checked
  -- aborts before a permanent number is allocated; the immutable input below
  -- is built from the same receipt-verified value captured above.
  if app.m4_canonical_fingerprint(
    app.m4_deal_source_snapshot(p_workspace_id, p_deal_id)
  ) is distinct from current_deal_context_checksum then
    raise exception using
      errcode = '40001',
      message = 'document.deal_context_changed';
  end if;

  scope_key := case numbering_version.scope_type
    when 'workspace' then 'workspace'
    when 'legal_entity' then legal_entity_key
    when 'location' then location_key
    when 'document_type' then document_type.key::text
    else legal_entity_key || '-' || location_key || '-' || document_type.key::text
  end;
  select allocated.* into allocation
  from app.m4_allocate_number(
    p_workspace_id,
    numbering_version.id,
    scope_key,
    p_document_date,
    'document',
    new_document_id,
    'document:' || normalized_idempotency,
    normalized_reason,
    actor_user_id,
    ''
  ) allocated;

  input_snapshot := current_deal_context || pg_catalog.jsonb_build_object(
    'document', pg_catalog.jsonb_build_object(
      'document_date', p_document_date,
      'intended_signature_date', p_intended_signature_date,
      'locale', normalized_locale,
      'fields', p_document_fields
    ),
    'calculation', p_calculation_evidence,
    'tax', p_tax_evidence
  );
  if input_snapshot is null then
    raise exception using errcode = '23514', message = 'document.official_snapshot_unavailable';
  end if;
  input_checksum := app.vertical_slice_fingerprint(input_snapshot);
  exact_versions := pg_catalog.jsonb_build_object(
    'schemaVersion', 3,
    'documentTypeId', document_type.id,
    'documentTypeChecksum', document_type.checksum,
    'templateVersionId', template.id,
    'templateBundleChecksum', template.source_bundle_checksum,
    'numberingVersionId', numbering_version.id,
    'numberingChecksum', numbering_version.checksum,
    'workflowVersionId', document_type.workflow_version_id,
    'workflowVersion', workflow_dependency.workflow_version,
    'workflowRevision', workflow_dependency.workflow_revision,
    'workflowChecksum', workflow_dependency.workflow_checksum,
    'calculationVersionId', document_type.calculation_version_id,
    'calculationChecksum', calculation_version.checksum,
    'calculationEvidenceId', trusted_calculation.id,
    'taxPackVersionId', document_type.tax_pack_version_id,
    'taxPackChecksum', tax_version.checksum,
    'taxEvidenceId', trusted_tax.id,
    'supersedesExpectedVersion', p_supersedes_expected_version,
    'rendererVersion', template.renderer_version
  );
  exact_versions_checksum := app.vertical_slice_fingerprint(exact_versions);

  if p_supersedes_document_id is not null then
    select prior.* into prior_document
    from public.documents prior
    where prior.workspace_id = p_workspace_id
      and prior.id = p_supersedes_document_id
      and prior.mode = 'official'
      and prior.status in ('generated', 'signed_received', 'completed')
    for update;
    if not found or prior_document.deal_id <> p_deal_id then
      raise exception using errcode = '23514', message = 'document.official_supersession_invalid';
    end if;
    if prior_document.aggregate_version <> p_supersedes_expected_version then
      raise exception using errcode = '40001', message = 'document.aggregate_version_conflict';
    end if;
    if exists (
      select 1
      from public.documents successor
      where successor.workspace_id = p_workspace_id
        and successor.supersedes_document_id = prior_document.id
        and successor.status <> 'voided'
    ) then
      raise exception using
        errcode = '40001',
        message = 'document.supersession_in_progress';
    end if;
    select prior_type.key::text into prior_document_key
    from public.document_types prior_type
    where prior_type.workspace_id = prior_document.workspace_id
      and prior_type.id = prior_document.document_type_id;
    if not found or prior_document_key <> document_type.key::text then
      raise exception using errcode = '23514', message = 'document.official_supersession_invalid';
    end if;
  end if;

  insert into public.documents (
    id, workspace_id, document_type_id, template_version_id, deal_id, mode,
    official_number, status, locale, watermark, render_input_snapshot,
    render_input_checksum, idempotency_key, command_fingerprint, created_by,
    number_allocation_id, document_date, intended_signature_date,
    numbering_version_id, workflow_version_id, tax_pack_version_id,
    calculation_version_id, renderer_version, version_snapshot,
    version_snapshot_checksum, supersedes_document_id,
    supersedes_expected_version
  ) values (
    new_document_id, p_workspace_id, document_type.id, template.id, p_deal_id,
    'official', allocation.formatted_value, 'generating', normalized_locale,
    null, input_snapshot, input_checksum, normalized_idempotency,
    request_fingerprint, actor_user_id, allocation.allocation_id,
    p_document_date, p_intended_signature_date, numbering_version.id,
    document_type.workflow_version_id, document_type.tax_pack_version_id,
    document_type.calculation_version_id, template.renderer_version,
    exact_versions, exact_versions_checksum, p_supersedes_document_id,
    p_supersedes_expected_version
  );

  if calculation_evidence_id is not null then
    insert into public.runtime_evidence_consumptions (
      workspace_id, evidence_id, evidence_type, deal_id, document_id,
      deal_context_checksum, consumed_by
    ) values (
      p_workspace_id, calculation_evidence_id, 'calculation', p_deal_id,
      new_document_id, current_deal_context_checksum, actor_user_id
    );
  end if;
  if tax_evidence_id is not null then
    insert into public.runtime_evidence_consumptions (
      workspace_id, evidence_id, evidence_type, deal_id, document_id,
      deal_context_checksum, consumed_by
    ) values (
      p_workspace_id, tax_evidence_id, 'tax', p_deal_id,
      new_document_id, current_deal_context_checksum, actor_user_id
    );
  end if;

  if p_calculation_evidence is not null then
    calculation_snapshot_id_value := pg_catalog.gen_random_uuid();
    insert into public.calculation_snapshots (
      id, workspace_id, calculation_version_id, document_id, deal_id,
      input_snapshot, output_snapshot, component_snapshot, rounding_snapshot,
      engine_version, checksum, runtime_evidence_id, definition_snapshot,
      definition_checksum, tax_component_snapshot, executed_by
    ) values (
      calculation_snapshot_id_value, p_workspace_id,
      document_type.calculation_version_id, new_document_id, p_deal_id,
      p_calculation_evidence -> 'input', p_calculation_evidence -> 'output',
      p_calculation_evidence -> 'components', p_calculation_evidence -> 'rounding',
      p_calculation_evidence ->> 'engineVersion',
      p_calculation_evidence ->> 'checksum', trusted_calculation.id,
      p_calculation_evidence -> 'definition',
      p_calculation_evidence ->> 'definitionChecksum',
      p_calculation_evidence -> 'taxComponents', actor_user_id
    );
  end if;
  if p_tax_evidence is not null then
    tax_snapshot_id_value := pg_catalog.gen_random_uuid();
    insert into public.tax_calculation_snapshots (
      id, workspace_id, tax_pack_version_id, assignment_id, document_id, deal_id,
      transaction_context, jurisdiction_code, currency_code, transaction_date,
      input_snapshot, output_snapshot, override_snapshot, override_reason,
      engine_version, checksum, runtime_evidence_id, pack_snapshot,
      pack_checksum, source_snapshot, executed_by
    ) values (
      tax_snapshot_id_value, p_workspace_id, document_type.tax_pack_version_id,
      (p_tax_evidence ->> 'assignmentId')::uuid, new_document_id, p_deal_id,
      p_tax_evidence ->> 'context', p_tax_evidence ->> 'jurisdiction',
      p_tax_evidence ->> 'currency', (p_tax_evidence ->> 'transactionDate')::date,
      p_tax_evidence -> 'input', p_tax_evidence -> 'output',
      p_tax_evidence -> 'override', p_tax_evidence ->> 'overrideReason',
      p_tax_evidence ->> 'engineVersion', p_tax_evidence ->> 'checksum',
      trusted_tax.id, p_tax_evidence -> 'pack',
      p_tax_evidence ->> 'packChecksum',
      p_tax_evidence -> 'pack' -> 'sources', actor_user_id
    );
  end if;
  if calculation_snapshot_id_value is not null or tax_snapshot_id_value is not null then
    update public.documents document set
      calculation_snapshot_id = calculation_snapshot_id_value,
      tax_calculation_snapshot_id = tax_snapshot_id_value,
      aggregate_version = document.aggregate_version + 1
    where document.workspace_id = p_workspace_id and document.id = new_document_id;
    result_version := 2;
  end if;

  select queued.* into queued_job
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'document.official_requested',
    p_aggregate_type => 'document',
    p_aggregate_id => new_document_id,
    p_aggregate_version => result_version,
    p_job_type => 'documents.render_pdf',
    p_entity_type => 'document',
    p_entity_id => new_document_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'document_id', new_document_id,
      'template_version_id', template.id,
      'render_input_checksum', input_checksum,
      'version_snapshot_checksum', exact_versions_checksum,
      'locale', normalized_locale,
      'mode', 'official'
    ),
    p_idempotency_key => 'render:' || normalized_idempotency,
    p_correlation_id => p_correlation_id,
    p_actor_user_id => actor_user_id,
    p_request_id => p_request_id
  ) queued;
  insert into public.document_render_jobs (
    workspace_id, document_id, outbox_event_id, job_id, render_mode,
    idempotency_key, request_fingerprint, requested_by
  ) values (
    p_workspace_id, new_document_id, queued_job.outbox_event_id,
    queued_job.job_id, 'official', normalized_idempotency,
    request_fingerprint, actor_user_id
  );

  number_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.number_allocated',
    p_entity_type => 'document',
    p_entity_id => new_document_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'numberAllocationId', allocation.allocation_id,
      'numberingVersionId', numbering_version.id,
      'officialNumber', allocation.formatted_value
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2'
  );
  official_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.official_requested',
    p_entity_type => 'document',
    p_entity_id => new_document_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'mode', 'official',
      'status', 'generating',
      'officialNumber', allocation.formatted_value,
      'renderInputChecksum', input_checksum,
      'versionSnapshotChecksum', exact_versions_checksum,
      'jobId', queued_job.job_id
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2',
    p_metadata => pg_catalog.jsonb_build_object(
      'numberAuditEventId', number_audit_event_id,
      'idempotencyKey', normalized_idempotency
    )
  );

  return query select
    new_document_id, allocation.formatted_value, 'generating'::text,
    allocation.allocation_id, queued_job.outbox_event_id, queued_job.job_id,
    official_audit_event_id, result_version, false;
end;
$$;

revoke all on function app.m4_number_period_key(uuid, date)
from public, anon, authenticated, service_role;
revoke all on function app.m4_format_number(uuid, text, text, bigint, text)
from public, anon, authenticated, service_role;
revoke all on function app.m4_allocate_number(
  uuid, uuid, text, date, text, uuid, text, text, uuid, text
) from public, anon, authenticated, service_role;
revoke all on function app.m4_exact_approval_valid(
  uuid, uuid, text, text, bigint, uuid, text, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function app.m4_validate_document_fields(jsonb, jsonb)
from public, anon, authenticated, service_role;
revoke all on function app.m4_json_schema_type_matches(text, jsonb)
from public, anon, authenticated, service_role;
revoke all on function app.m4_json_schema_value_valid(jsonb, jsonb, jsonb, integer)
from public, anon, authenticated, service_role;
revoke all on function app.m4_document_input_snapshot(
  uuid, uuid, date, date, text, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
revoke all on function app.m4_deal_source_snapshot(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_deal_tax_input(jsonb, text)
from public, anon, authenticated, service_role;
revoke all on function app.m4_document_workflow_dependency(
  uuid, uuid, uuid, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function app.m4_fill_preview_version_snapshot()
from public, anon, authenticated, service_role;
revoke all on function app.request_official_document(
  uuid, text, uuid, uuid, uuid, text, date, date, jsonb, jsonb, jsonb,
  uuid, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.request_official_document(
  uuid, text, uuid, uuid, uuid, text, date, date, jsonb, jsonb, jsonb,
  uuid, bigint, text, text, uuid
) to authenticated;

comment on table public.document_files is
  'Immutable generated, signed, attachment, and void file versions; current selection never deletes history.';
comment on table public.document_render_jobs is
  'One durable render-job mapping per immutable document snapshot and permanent official number.';
