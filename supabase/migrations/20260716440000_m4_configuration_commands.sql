-- VYN-APP-001, VYN-DOC-001, VYN-NUM-001, VYN-CALC-001, VYN-TAX-001, VYN-EXP-001
-- M4-CFG-AC-001 through M4-CFG-AC-005, M4-DOC-AC-001, M4-DOC-AC-004,
-- and M4-NUM-AC-001.
-- Exact-version approvals and lifecycle commands for Milestone 4 artifacts.

-- Workspace/pack import is the creation boundary for document artifacts. It
-- must persist the exact validation and fixture evidence with the immutable
-- source row; authenticated users can only approve and activate that row.
alter table public.document_types
  add column validation_evidence jsonb,
  add column activated_by uuid references auth.users (id) on delete restrict,
  add column retired_by uuid references auth.users (id) on delete restrict,
  add constraint document_types_validation_evidence_check check (
    validation_evidence is null
    or pg_catalog.jsonb_typeof(validation_evidence) = 'object'
  );

alter table public.document_template_versions
  add column validation_evidence jsonb,
  add column activated_by uuid references auth.users (id) on delete restrict,
  add column retired_by uuid references auth.users (id) on delete restrict,
  add constraint document_templates_validation_evidence_check check (
    validation_evidence is null
    or pg_catalog.jsonb_typeof(validation_evidence) = 'object'
  ),
  drop constraint document_template_versions_production_shape_check,
  add constraint document_template_versions_production_shape_check check (
    (
      template_class = 'synthetic_non_production'
      and not production_approved
      and watermark = 'DRAFT / NON-PRODUCTION'
      and activation_status in ('test_passed', 'retired')
    )
    or (
      template_class = 'tenant_approved'
      and watermark is null
      and (
        (
          activation_status in ('draft', 'validated', 'test_passed')
          and not production_approved
          and approval_record_id is null
        )
        or (
          activation_status in ('approved', 'active', 'retired')
          and production_approved
          and approval_record_id is not null
        )
      )
    )
  );

-- Imported evidence is part of the immutable artifact. Lifecycle metadata is
-- intentionally excluded because only the audited commands below may change
-- it after import.
drop trigger document_types_immutable on public.document_types;
create trigger document_types_immutable
before update on public.document_types
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'version', 'display_name', 'labels',
  'field_schema', 'field_schema_checksum', 'numbering_definition_version_id',
  'workflow_version_id', 'tax_pack_version_id', 'calculation_version_id',
  'preview_generation_enabled', 'production_enabled', 'activation_gates',
  'checksum', 'validation_evidence', 'fixture_evidence', 'created_at'
);

drop trigger document_template_versions_immutable
on public.document_template_versions;
create trigger document_template_versions_immutable
before update on public.document_template_versions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'document_type_id', 'version', 'locale',
  'template_class', 'source_html', 'source_css', 'source_checksum',
  'source_bundle_checksum', 'asset_manifest', 'font_manifest',
  'renderer_version', 'field_schema', 'field_schema_checksum', 'watermark',
  'validation_evidence', 'fixture_evidence', 'created_at'
);

create table public.configuration_artifact_commands (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  artifact_type text not null check (
    artifact_type in (
      'numbering_definition', 'calculation', 'tax_pack', 'export_definition',
      'document_type', 'document_template'
    )
  ),
  artifact_id uuid not null,
  action text not null check (
    action in ('create_version', 'validate', 'test', 'approve', 'activate', 'retire')
  ),
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  result jsonb not null check (pg_catalog.jsonb_typeof(result) = 'object'),
  audit_event_id uuid,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, idempotency_key)
);

create trigger configuration_artifact_commands_immutable
before update or delete on public.configuration_artifact_commands
for each row execute function app.m4_prevent_row_mutation();

alter table public.configuration_artifact_commands enable row level security;
alter table public.configuration_artifact_commands force row level security;

create policy configuration_artifact_commands_select
on public.configuration_artifact_commands
for select to authenticated using (
  app.has_permission(workspace_id, 'configuration.read')
  or app.has_permission(workspace_id, 'approvals.read')
);

revoke all on table public.configuration_artifact_commands
from public, anon, authenticated;
grant select on table public.configuration_artifact_commands
to authenticated;
grant select, insert, update, delete on table public.configuration_artifact_commands
to service_role;

create function app.m4_artifact_descriptor(
  p_workspace_id uuid,
  p_artifact_type text,
  p_artifact_id uuid
)
returns table (
  artifact_type text,
  artifact_key text,
  artifact_version bigint,
  artifact_id uuid,
  artifact_checksum text,
  artifact_status text,
  validation_evidence jsonb,
  fixture_evidence jsonb,
  approval_record_id uuid,
  definition_id uuid,
  activation_permission text,
  activation_eligible boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_artifact_type = 'numbering_definition' then
    return query
    select
      'numbering_definition'::text,
      'numbering.' || definition.key::text,
      version.version,
      version.id,
      version.checksum,
      version.status,
      version.validation_evidence,
      version.fixture_evidence,
      version.approval_record_id,
      version.numbering_definition_id,
      'numbering.activate'::text,
      true
    from public.numbering_definition_versions version
    join public.numbering_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.numbering_definition_id
    where version.workspace_id = p_workspace_id and version.id = p_artifact_id;
  elsif p_artifact_type = 'calculation' then
    return query
    select
      'calculation'::text,
      'formula.' || definition.key::text,
      version.version,
      version.id,
      version.checksum,
      version.status,
      version.validation_evidence,
      version.fixture_evidence,
      version.approval_record_id,
      version.calculation_definition_id,
      'formula.activate'::text,
      true
    from public.calculation_versions version
    join public.calculation_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.calculation_definition_id
    where version.workspace_id = p_workspace_id and version.id = p_artifact_id;
  elsif p_artifact_type = 'tax_pack' then
    return query
    select
      'tax_pack'::text,
      'tax.' || pack.key::text,
      version.version,
      version.id,
      version.checksum,
      version.status,
      version.validation_evidence,
      version.fixture_evidence,
      version.approval_record_id,
      version.tax_pack_id,
      'tax.activate'::text,
      true
    from public.tax_pack_versions version
    join public.tax_packs pack
      on pack.workspace_id = version.workspace_id
     and pack.id = version.tax_pack_id
    where version.workspace_id = p_workspace_id and version.id = p_artifact_id;
  elsif p_artifact_type = 'export_definition' then
    return query
    select
      'export_definition'::text,
      'export.' || definition.key::text,
      version.version,
      version.id,
      version.checksum,
      version.status,
      version.validation_evidence,
      version.fixture_evidence,
      version.approval_record_id,
      version.export_definition_id,
      'configuration.manage'::text,
      true
    from public.export_versions version
    join public.export_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.export_definition_id
    where version.workspace_id = p_workspace_id and version.id = p_artifact_id;
  elsif p_artifact_type = 'document_type' then
    return query
    select
      'document_type'::text,
      'document.' || pg_catalog.regexp_replace(
        pg_catalog.lower(document_type.key::text),
        '[^a-z0-9_]+',
        '_',
        'g'
      ),
      document_type.version::bigint,
      document_type.id,
      document_type.checksum,
      document_type.activation_status,
      document_type.validation_evidence,
      document_type.fixture_evidence,
      document_type.approval_record_id,
      pg_catalog.md5(
        document_type.workspace_id::text || ':document_type:'
          || pg_catalog.lower(document_type.key::text)
      )::uuid,
      'configuration.manage'::text,
      coalesce(
        document_type.production_enabled
          and document_type.numbering_definition_version_id is not null,
        false
      )
    from public.document_types document_type
    where document_type.workspace_id = p_workspace_id
      and document_type.id = p_artifact_id;
  elsif p_artifact_type = 'document_template' then
    return query
    select
      'document_template'::text,
      'template.' || pg_catalog.regexp_replace(
        pg_catalog.lower(document_type.key::text),
        '[^a-z0-9_]+',
        '_',
        'g'
      ) || '.' || pg_catalog.replace(pg_catalog.lower(template.locale), '-', '_'),
      template.version::bigint,
      template.id,
      template.source_bundle_checksum,
      template.activation_status,
      template.validation_evidence,
      template.fixture_evidence,
      template.approval_record_id,
      pg_catalog.md5(
        template.workspace_id::text || ':document_template:'
          || template.document_type_id::text || ':'
          || pg_catalog.lower(template.locale)
      )::uuid,
      'configuration.manage'::text,
      coalesce(
        template.template_class = 'tenant_approved'
          and template.watermark is null
          and document_type.production_enabled
          and template.field_schema_checksum = document_type.field_schema_checksum,
        false
      )
    from public.document_template_versions template
    join public.document_types document_type
      on document_type.workspace_id = template.workspace_id
     and document_type.id = template.document_type_id
    where template.workspace_id = p_workspace_id
      and template.id = p_artifact_id;
  else
    raise exception using errcode = '22023', message = 'unsupported configuration artifact type';
  end if;
end;
$$;

create function app.m4_record_artifact_approval(
  p_workspace_id uuid,
  p_artifact_type text,
  p_artifact_id uuid,
  p_expected_checksum text,
  p_approval_type text,
  p_decision text,
  p_idempotency_key text,
  p_reason text,
  p_professional_role text default null,
  p_professional_organization text default null,
  p_conditions jsonb default '{}'::jsonb,
  p_attachment_reference text default null,
  p_expires_at timestamptz default null,
  p_review_due_at timestamptz default null,
  p_supersedes_approval_id uuid default null,
  p_request_id text default null,
  p_correlation_id uuid default null
)
returns table (
  approval_record_id uuid,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  descriptor record;
  existing public.approval_records%rowtype;
  superseded public.approval_records%rowtype;
  new_approval_id uuid := pg_catalog.gen_random_uuid();
  new_audit_id uuid;
  existing_audit_id uuid;
  normalized_idempotency text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id, 'approvals.create', true
  );
  if pg_catalog.char_length(normalized_idempotency) not between 8 and 200
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_expected_checksum !~ '^[a-f0-9]{64}$'
    or p_approval_type !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or p_decision not in ('approved', 'rejected', 'revoked')
    or pg_catalog.jsonb_typeof(coalesce(p_conditions, '{}'::jsonb)) <> 'object'
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid artifact approval command';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fapproval\x1f' || normalized_idempotency,
    0
  ));
  select approval.* into existing
  from public.approval_records approval
  where approval.workspace_id = p_workspace_id
    and approval.idempotency_key = normalized_idempotency;
  if found then
    if existing.artifact_type <> p_artifact_type
      or existing.artifact_id <> p_artifact_id
      or existing.artifact_checksum <> p_expected_checksum
      or existing.approval_type <> p_approval_type
      or existing.decision <> p_decision
      or existing.decided_by <> actor_user_id
      or existing.professional_role is distinct from p_professional_role
      or existing.professional_organization is distinct from p_professional_organization
      or existing.conditions <> coalesce(p_conditions, '{}'::jsonb)
      or existing.attachment_reference is distinct from p_attachment_reference
      or existing.expires_at is distinct from p_expires_at
      or existing.review_due_at is distinct from p_review_due_at
      or existing.supersedes_approval_id is distinct from p_supersedes_approval_id
      or existing.reason <> normalized_reason then
      raise exception using errcode = '23505', message = 'approval idempotency conflict';
    end if;
    select event.id into existing_audit_id
    from public.audit_events event
    where event.workspace_id = existing.workspace_id
      and event.action = 'configuration.artifact_approval_recorded'
      and event.entity_type = existing.artifact_type
      and event.entity_id = existing.artifact_id
      and event.after_data ->> 'approvalRecordId' = existing.id::text
    order by event.occurred_at, event.id
    limit 1;
    if existing_audit_id is null then
      raise exception using errcode = '55000', message = 'approval audit evidence is missing';
    end if;
    return query select existing.id, existing_audit_id, true;
    return;
  end if;

  -- Approval mutations take the exclusive side of the same per-artifact lock
  -- that official issuance holds shared while validating exact approvals.
  -- Keep this key byte-for-byte aligned with request_official_document:
  -- workspace, "configuration_artifact", artifact type, artifact id.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fconfiguration_artifact\x1f'
      || p_artifact_type || E'\x1f' || p_artifact_id::text,
    0
  ));

  select * into descriptor
  from app.m4_artifact_descriptor(p_workspace_id, p_artifact_type, p_artifact_id);
  if not found then
    raise exception using errcode = '23503', message = 'configuration artifact version does not exist';
  end if;
  if descriptor.artifact_checksum is distinct from p_expected_checksum then
    raise exception using errcode = '23514', message = 'configuration artifact checksum mismatch';
  end if;
  if p_decision = 'approved' and not descriptor.activation_eligible then
    raise exception using errcode = '23514', message = 'configuration artifact is production-disabled';
  end if;
  if p_decision = 'approved' and descriptor.artifact_status <> 'test_passed' then
    raise exception using errcode = '23514', message = 'only a test-passed artifact may be approved';
  end if;
  if p_decision = 'rejected'
    and descriptor.artifact_status not in ('validated', 'test_passed') then
    raise exception using errcode = '23514', message = 'artifact is not reviewable';
  end if;
  if p_decision = 'revoked' then
    select approval.* into superseded
    from public.approval_records approval
    where approval.workspace_id = p_workspace_id
      and approval.id = p_supersedes_approval_id;
    if not found or superseded.decision <> 'approved'
      or superseded.artifact_type <> descriptor.artifact_type
      or superseded.artifact_id <> descriptor.artifact_id
      or superseded.artifact_checksum <> descriptor.artifact_checksum then
      raise exception using errcode = '23514', message = 'approval revocation must reference the exact approval';
    end if;
    if descriptor.artifact_status = 'active' then
      raise exception using errcode = '23514', message = 'active artifact must be retired before approval revocation';
    end if;
  elsif p_supersedes_approval_id is not null then
    raise exception using errcode = '23514', message = 'only revocation may supersede an approval';
  end if;

  perform pg_catalog.set_config('app.configuration_reason', normalized_reason, true);
  insert into public.approval_records (
    id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
    artifact_checksum, approval_type, decision, decided_by, professional_role,
    professional_organization, conditions, attachment_reference, expires_at,
    review_due_at, supersedes_approval_id, idempotency_key, reason
  ) values (
    new_approval_id, p_workspace_id, descriptor.artifact_type,
    descriptor.artifact_key, descriptor.artifact_version, descriptor.artifact_id,
    descriptor.artifact_checksum, p_approval_type, p_decision, actor_user_id,
    nullif(pg_catalog.btrim(coalesce(p_professional_role, '')), ''),
    nullif(pg_catalog.btrim(coalesce(p_professional_organization, '')), ''),
    coalesce(p_conditions, '{}'::jsonb), p_attachment_reference, p_expires_at,
    p_review_due_at, p_supersedes_approval_id, normalized_idempotency,
    normalized_reason
  );
  new_audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'configuration.artifact_approval_recorded',
    p_entity_type => descriptor.artifact_type,
    p_entity_id => descriptor.artifact_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'approvalRecordId', new_approval_id,
      'artifactKey', descriptor.artifact_key,
      'artifactVersion', descriptor.artifact_version,
      'decision', p_decision,
      'checksum', descriptor.artifact_checksum
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2'
  );
  return query select new_approval_id, new_audit_id, false;
end;
$$;

create function app.m4_transition_artifact_version(
  p_workspace_id uuid,
  p_artifact_type text,
  p_artifact_id uuid,
  p_expected_checksum text,
  p_target_status text,
  p_evidence jsonb,
  p_idempotency_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  artifact_id uuid,
  artifact_status text,
  approval_record_id uuid,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  descriptor record;
  existing public.configuration_artifact_commands%rowtype;
  approval_id uuid;
  audit_id uuid;
  table_name text;
  definition_column text;
  expected_status text;
  action_name text;
  fingerprint text;
  normalized_idempotency text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  -- Validation and fixture execution are trusted import/runtime operations.
  -- This authenticated command may only govern approval, activation, and
  -- retirement of already immutable test-passed artifacts.
  if p_target_status not in ('approved', 'active', 'retired')
    or pg_catalog.char_length(normalized_idempotency) not between 8 and 200
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_expected_checksum !~ '^[a-f0-9]{64}$'
    or pg_catalog.jsonb_typeof(coalesce(p_evidence, '{}'::jsonb))
      is distinct from 'object'
    or pg_catalog.octet_length(coalesce(p_evidence, '{}'::jsonb)::text) > 65536
    or not app.m3_inert_json_is_safe(coalesce(p_evidence, '{}'::jsonb))
    or app.job_payload_contains_forbidden_key(coalesce(p_evidence, '{}'::jsonb))
    or pg_catalog.jsonb_typeof(p_evidence -> 'expectedVersion')
      is distinct from 'number'
    or coalesce(p_evidence ->> 'expectedVersion', '') !~ '^[1-9][0-9]*$'
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid artifact lifecycle command';
  end if;
  actor_user_id := auth.uid();
  if actor_user_id is null or not exists (
    select 1
    from public.workspace_memberships membership
    where membership.workspace_id = p_workspace_id
      and membership.user_id = actor_user_id
      and membership.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'active workspace membership is required';
  end if;
  select * into descriptor
  from app.m4_artifact_descriptor(p_workspace_id, p_artifact_type, p_artifact_id);
  if not found then
    raise exception using errcode = '23503', message = 'configuration artifact version does not exist';
  end if;
  if descriptor.artifact_checksum is distinct from p_expected_checksum then
    raise exception using errcode = '23514', message = 'configuration artifact checksum mismatch';
  end if;
  if p_target_status in ('approved', 'active')
    and not descriptor.activation_eligible then
    raise exception using errcode = '23514', message = 'configuration artifact is production-disabled';
  end if;
  if (p_evidence ->> 'expectedVersion')::bigint
    is distinct from descriptor.artifact_version then
    raise exception using errcode = '40001', message = 'configuration artifact version changed';
  end if;

  actor_user_id := case
    when p_target_status in ('active', 'retired') then
      app.require_vertical_slice_permission(
        p_workspace_id, descriptor.activation_permission, true
      )
    else app.require_vertical_slice_permission(p_workspace_id, 'configuration.manage')
  end;
  action_name := case p_target_status
    when 'approved' then 'approve'
    when 'active' then 'activate'
    else 'retire'
  end;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'artifactType', p_artifact_type,
    'artifactId', p_artifact_id,
    'checksum', p_expected_checksum,
    'targetStatus', p_target_status,
    'evidence', coalesce(p_evidence, '{}'::jsonb)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fconfiguration_command\x1f'
      || actor_user_id::text || E'\x1f' || normalized_idempotency,
    0
  ));
  select command.* into existing
  from public.configuration_artifact_commands command
  where command.workspace_id = p_workspace_id
    and command.actor_user_id = app.current_user_id()
    and command.idempotency_key = normalized_idempotency;
  if found then
    if existing.command_fingerprint <> fingerprint
      or existing.artifact_type <> p_artifact_type
      or existing.artifact_id <> p_artifact_id
      or existing.action <> action_name then
      raise exception using errcode = '23505', message = 'configuration command idempotency conflict';
    end if;
    return query select
      existing.artifact_id,
      existing.result ->> 'status',
      nullif(existing.result ->> 'approvalRecordId', '')::uuid,
      existing.audit_event_id,
      true;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fartifact\x1f' || p_artifact_type
      || E'\x1f' || descriptor.definition_id::text,
    0
  ));
  -- Serialize exact approval validation with approval mutation/revocation.
  -- This shared key is identical to the exclusive key in
  -- m4_record_artifact_approval and is acquired before the locked re-read.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fconfiguration_artifact\x1f'
      || p_artifact_type || E'\x1f' || p_artifact_id::text,
    0
  ));
  select * into descriptor
  from app.m4_artifact_descriptor(p_workspace_id, p_artifact_type, p_artifact_id);
  if descriptor.artifact_checksum is distinct from p_expected_checksum then
    raise exception using errcode = '40001', message = 'configuration artifact changed';
  end if;
  if descriptor.artifact_status = p_target_status then
    approval_id := descriptor.approval_record_id;
  else
    expected_status := case p_target_status
      when 'approved' then 'test_passed'
      when 'active' then 'approved'
      else descriptor.artifact_status
    end;
    if descriptor.artifact_status <> expected_status
      and not (
        p_target_status = 'active'
        and descriptor.artifact_status = 'test_passed'
      )
      or (p_target_status = 'retired'
        and descriptor.artifact_status not in ('approved', 'active')) then
      raise exception using errcode = '23514', message = 'invalid configuration artifact lifecycle transition';
    end if;
  end if;

  table_name := case p_artifact_type
    when 'numbering_definition' then 'numbering_definition_versions'
    when 'calculation' then 'calculation_versions'
    when 'tax_pack' then 'tax_pack_versions'
    when 'export_definition' then 'export_versions'
    when 'document_type' then 'document_types'
    when 'document_template' then 'document_template_versions'
  end;
  definition_column := case p_artifact_type
    when 'numbering_definition' then 'numbering_definition_id'
    when 'calculation' then 'calculation_definition_id'
    when 'tax_pack' then 'tax_pack_id'
    when 'export_definition' then 'export_definition_id'
  end;

  if descriptor.artifact_status <> p_target_status then
    if p_target_status = 'approved' then
      select approval.id into approval_id
      from public.approval_records approval
      where approval.workspace_id = p_workspace_id
        and approval.artifact_type = descriptor.artifact_type
        and approval.artifact_key = descriptor.artifact_key
        and approval.artifact_version = descriptor.artifact_version
        and approval.artifact_id = descriptor.artifact_id
        and approval.artifact_checksum = descriptor.artifact_checksum
        and approval.decision = 'approved'
        and (approval.expires_at is null
          or approval.expires_at > pg_catalog.statement_timestamp())
        and not exists (
          select 1 from public.approval_records revocation
          where revocation.workspace_id = approval.workspace_id
            and revocation.supersedes_approval_id = approval.id
            and revocation.decision = 'revoked'
        )
      order by approval.decided_at desc, approval.id desc
      limit 1;
      if approval_id is null then
        raise exception using errcode = '23514', message = 'exact unexpired approval is required';
      end if;
      if p_artifact_type = 'document_type' then
        update public.document_types
        set activation_status = 'approved',
            approval_record_id = approval_id
        where workspace_id = p_workspace_id and id = p_artifact_id;
      elsif p_artifact_type = 'document_template' then
        update public.document_template_versions
        set activation_status = 'approved',
            production_approved = true,
            approval_record_id = approval_id
        where workspace_id = p_workspace_id and id = p_artifact_id;
      else
        execute pg_catalog.format(
          'update public.%I set status = ''approved'', approval_record_id = $3 where workspace_id = $1 and id = $2',
          table_name
        ) using p_workspace_id, p_artifact_id, approval_id;
      end if;
    elsif p_target_status = 'active' then
      approval_id := descriptor.approval_record_id;
      if descriptor.artifact_status = 'test_passed' then
        select approval.id into approval_id
        from public.approval_records approval
        where approval.workspace_id = p_workspace_id
          and approval.artifact_type = descriptor.artifact_type
          and approval.artifact_key = descriptor.artifact_key
          and approval.artifact_version = descriptor.artifact_version
          and approval.artifact_id = descriptor.artifact_id
          and approval.artifact_checksum = descriptor.artifact_checksum
          and approval.decision = 'approved'
          and (approval.expires_at is null
            or approval.expires_at > pg_catalog.statement_timestamp())
          and not exists (
            select 1 from public.approval_records revocation
            where revocation.workspace_id = approval.workspace_id
              and revocation.supersedes_approval_id = approval.id
              and revocation.decision = 'revoked'
              and revocation.decided_at <= pg_catalog.statement_timestamp()
          )
        order by approval.decided_at desc, approval.id desc
        limit 1;
      end if;
      if pg_catalog.jsonb_typeof(descriptor.validation_evidence)
          is distinct from 'object'
        or descriptor.validation_evidence -> 'passed' is distinct from 'true'::jsonb
        or pg_catalog.jsonb_typeof(descriptor.validation_evidence -> 'validator')
          is distinct from 'string'
        or pg_catalog.btrim(coalesce(descriptor.validation_evidence ->> 'validator', '')) = ''
        or pg_catalog.jsonb_typeof(
          descriptor.validation_evidence -> 'artifactChecksum'
        ) is distinct from 'string'
        or descriptor.validation_evidence ->> 'artifactChecksum'
          is distinct from descriptor.artifact_checksum
        or pg_catalog.jsonb_typeof(descriptor.fixture_evidence)
          is distinct from 'object'
        or descriptor.fixture_evidence -> 'passed' is distinct from 'true'::jsonb
        or pg_catalog.jsonb_typeof(descriptor.fixture_evidence -> 'runner')
          is distinct from 'string'
        or pg_catalog.btrim(coalesce(descriptor.fixture_evidence ->> 'runner', '')) = ''
        or pg_catalog.jsonb_typeof(
          descriptor.fixture_evidence -> 'artifactChecksum'
        ) is distinct from 'string'
        or descriptor.fixture_evidence ->> 'artifactChecksum'
          is distinct from descriptor.artifact_checksum
        or pg_catalog.jsonb_typeof(descriptor.fixture_evidence -> 'tests')
          is distinct from 'array'
        or not app.m4_exact_approval_valid(
          p_workspace_id, approval_id, descriptor.artifact_type,
          descriptor.artifact_key, descriptor.artifact_version,
          descriptor.artifact_id, descriptor.artifact_checksum
      ) then
        raise exception using errcode = '23514', message = 'activation gates are incomplete';
      end if;
      if pg_catalog.jsonb_array_length(descriptor.fixture_evidence -> 'tests') = 0 then
        raise exception using errcode = '23514', message = 'activation gates are incomplete';
      end if;
      if descriptor.artifact_status = 'test_passed' then
        if p_artifact_type = 'document_type' then
          update public.document_types
          set activation_status = 'approved',
              approval_record_id = approval_id
          where workspace_id = p_workspace_id and id = p_artifact_id;
        elsif p_artifact_type = 'document_template' then
          update public.document_template_versions
          set activation_status = 'approved',
              production_approved = true,
              approval_record_id = approval_id
          where workspace_id = p_workspace_id and id = p_artifact_id;
        else
          execute pg_catalog.format(
            'update public.%I set status = ''approved'', approval_record_id = $3 where workspace_id = $1 and id = $2',
            table_name
          ) using p_workspace_id, p_artifact_id, approval_id;
        end if;
      end if;
      if p_artifact_type = 'document_type' then
        update public.document_types sibling
        set activation_status = 'retired',
            official_generation_enabled = false,
            status = 'retired',
            retired_by = actor_user_id,
            retired_at = pg_catalog.statement_timestamp()
        from public.document_types target
        where target.workspace_id = p_workspace_id
          and target.id = p_artifact_id
          and sibling.workspace_id = target.workspace_id
          and sibling.key = target.key
          and sibling.id <> target.id
          and sibling.activation_status = 'active';
        update public.document_types
        set activation_status = 'active',
            official_generation_enabled = true,
            status = 'active',
            activated_by = actor_user_id,
            activated_at = pg_catalog.statement_timestamp(),
            retired_by = null,
            retired_at = null
        where workspace_id = p_workspace_id and id = p_artifact_id;
      elsif p_artifact_type = 'document_template' then
        update public.document_template_versions sibling
        set activation_status = 'retired',
            status = 'retired',
            retired_by = actor_user_id,
            retired_at = pg_catalog.statement_timestamp()
        from public.document_template_versions target
        where target.workspace_id = p_workspace_id
          and target.id = p_artifact_id
          and sibling.workspace_id = target.workspace_id
          and sibling.document_type_id = target.document_type_id
          and sibling.locale = target.locale
          and sibling.id <> target.id
          and sibling.activation_status = 'active';
        update public.document_template_versions
        set activation_status = 'active',
            production_approved = true,
            status = 'active',
            activated_by = actor_user_id,
            activated_at = pg_catalog.statement_timestamp(),
            retired_by = null,
            retired_at = null
        where workspace_id = p_workspace_id and id = p_artifact_id;
      else
        execute pg_catalog.format(
          'update public.%I set status = ''retired'', retired_by = $3, retired_at = pg_catalog.statement_timestamp() where workspace_id = $1 and %I = $2 and status = ''active'' and id <> $4',
          table_name, definition_column
        ) using p_workspace_id, descriptor.definition_id, actor_user_id, p_artifact_id;
        execute pg_catalog.format(
          'update public.%I set status = ''active'', activated_by = $3, activated_at = pg_catalog.statement_timestamp() where workspace_id = $1 and id = $2',
          table_name
        ) using p_workspace_id, p_artifact_id, actor_user_id;
      end if;

      if p_artifact_type = 'tax_pack' then
        if exists (
          select 1
          from public.tax_pack_assignments assignment
          join public.tax_pack_versions version
            on version.workspace_id = assignment.workspace_id
           and version.id = p_artifact_id
          where assignment.workspace_id = p_workspace_id
            and assignment.retired_at is null
            and assignment.jurisdiction_code = version.jurisdiction_code
            and assignment.context_key = any(version.contexts)
            and assignment.currency_code = any(version.currency_codes)
            and assignment.effective_from >= version.effective_from
        ) then
          raise exception using
            errcode = '23514',
            message = 'successor tax assignment must begin after the current assignment';
        end if;
        update public.tax_pack_assignments assignment set
          superseded_effective_to = (
            select least(
              coalesce(assignment.effective_to, version.effective_from - 1),
              version.effective_from - 1
            )
            from public.tax_pack_versions version
            where version.workspace_id = p_workspace_id
              and version.id = p_artifact_id
          ),
          retired_at = pg_catalog.statement_timestamp()
        where assignment.workspace_id = p_workspace_id
          and assignment.retired_at is null
          and exists (
            select 1
            from public.tax_pack_versions version,
              pg_catalog.unnest(version.contexts) context_key,
              pg_catalog.unnest(version.currency_codes) currency_code
            where version.workspace_id = p_workspace_id
              and version.id = p_artifact_id
              and assignment.jurisdiction_code = version.jurisdiction_code
              and assignment.context_key = context_key
              and assignment.currency_code = currency_code
          );
        insert into public.tax_pack_assignments (
          workspace_id, tax_pack_version_id, jurisdiction_code, context_key,
          currency_code, effective_from, effective_to, approval_record_id,
          activated_by, activation_reason
        )
        select
          version.workspace_id, version.id, version.jurisdiction_code,
          context_key, currency_code, version.effective_from, version.effective_to,
          version.approval_record_id, actor_user_id, normalized_reason
        from public.tax_pack_versions version,
          pg_catalog.unnest(version.contexts) context_key,
          pg_catalog.unnest(version.currency_codes) currency_code
        where version.workspace_id = p_workspace_id and version.id = p_artifact_id;
      end if;
    else
      approval_id := descriptor.approval_record_id;
      if p_artifact_type = 'document_type' then
        update public.document_types
        set activation_status = 'retired',
            official_generation_enabled = false,
            status = 'retired',
            retired_by = actor_user_id,
            retired_at = pg_catalog.statement_timestamp()
        where workspace_id = p_workspace_id and id = p_artifact_id;
      elsif p_artifact_type = 'document_template' then
        update public.document_template_versions
        set activation_status = 'retired',
            status = 'retired',
            retired_by = actor_user_id,
            retired_at = pg_catalog.statement_timestamp()
        where workspace_id = p_workspace_id and id = p_artifact_id;
      else
        execute pg_catalog.format(
          'update public.%I set status = ''retired'', retired_by = $3, retired_at = pg_catalog.statement_timestamp() where workspace_id = $1 and id = $2',
          table_name
        ) using p_workspace_id, p_artifact_id, actor_user_id;
      end if;
      if p_artifact_type = 'tax_pack' then
        update public.tax_pack_assignments assignment set
          superseded_effective_to = greatest(
            assignment.effective_from,
            least(
              coalesce(assignment.effective_to, current_date),
              current_date
            )
          ),
          retired_at = pg_catalog.statement_timestamp()
        where assignment.workspace_id = p_workspace_id
          and assignment.tax_pack_version_id = p_artifact_id
          and assignment.retired_at is null;
      end if;
    end if;
  end if;

  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'configuration.artifact_' || action_name,
    p_entity_type => descriptor.artifact_type,
    p_entity_id => descriptor.artifact_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('status', descriptor.artifact_status),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', p_target_status,
      'checksum', descriptor.artifact_checksum,
      'approvalRecordId', approval_id,
      'evidence', coalesce(p_evidence, '{}'::jsonb)
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => case
      when p_target_status in ('active', 'retired') then 'aal2' else null
    end
  );
  insert into public.configuration_artifact_commands (
    workspace_id, actor_user_id, artifact_type, artifact_id, action,
    idempotency_key, command_fingerprint, reason, result, audit_event_id
  ) values (
    p_workspace_id, actor_user_id, p_artifact_type, p_artifact_id, action_name,
    normalized_idempotency, fingerprint, normalized_reason,
    pg_catalog.jsonb_build_object(
      'status', p_target_status,
      'approvalRecordId', approval_id
    ), audit_id
  );
  return query select p_artifact_id, p_target_status, approval_id, audit_id, false;
exception
  when invalid_text_representation then
    raise exception using errcode = '23514', message = 'evidence passed must be boolean';
end;
$$;

create function app.m4_create_numbering_version(
  p_workspace_id uuid,
  p_definition_key text,
  p_labels jsonb,
  p_payload jsonb,
  p_expected_checksum text,
  p_expected_latest_version_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  numbering_definition_id uuid,
  numbering_version_id uuid,
  version bigint,
  artifact_status text,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  definition_id uuid;
  version_id uuid := pg_catalog.gen_random_uuid();
  next_version bigint;
  latest_version_id uuid;
  existing public.configuration_artifact_commands%rowtype;
  fingerprint text;
  audit_id uuid;
  fixture_scope_key text;
  fixture_period_key text;
  fixture_other_period_key text;
  fixture_first text;
  fixture_second text;
  fixture_cross_scope text;
  fixture_cross_period text;
  fixture_tests jsonb;
  normalized_key text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_definition_key, '')));
  normalized_idempotency text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id, 'configuration.manage'
  );
  if normalized_key !~ '^[a-z][a-z0-9_]{0,127}$'
    or pg_catalog.jsonb_typeof(p_labels) <> 'object'
    or not p_labels ?& array['en', 'fr']
    or pg_catalog.btrim(coalesce(p_labels ->> 'en', '')) = ''
    or pg_catalog.btrim(coalesce(p_labels ->> 'fr', '')) = ''
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or not p_payload ?& array[
      'allocationEvent', 'formatPattern', 'importPolicy', 'incrementBy',
      'numericWidth', 'periodAnchor', 'periodMonths', 'prefix', 'resetPolicy',
      'reusePolicy', 'scopeType', 'semanticVersion', 'startingValue', 'suffix',
      'timezone'
    ]
    or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_payload)) <> 15
    or coalesce(p_payload ->> 'scopeType', '') not in (
      'workspace', 'legal_entity', 'location', 'document_type', 'combined'
    )
    or coalesce(p_payload ->> 'resetPolicy', '') not in (
      'never', 'yearly', 'monthly', 'configured_period'
    )
    or (
      p_payload ->> 'scopeType' <> 'workspace'
      and coalesce(p_payload ->> 'formatPattern', '') not like '%{{scope}}%'
    )
    or (
      p_payload ->> 'resetPolicy' = 'never'
      and coalesce(p_payload ->> 'formatPattern', '') like '%{{period}}%'
    )
    or (
      p_payload ->> 'resetPolicy' <> 'never'
      and coalesce(p_payload ->> 'formatPattern', '') not like '%{{period}}%'
    )
    or coalesce(p_payload ->> 'timezone', 'UTC') <> 'UTC'
    or p_payload ->> 'allocationEvent' <> 'official_document_created'
    or not app.m3_inert_json_is_safe(p_payload)
    or pg_catalog.octet_length(p_payload::text) > 65536
    or pg_catalog.char_length(normalized_idempotency) not between 8 and 200
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_expected_checksum !~ '^[a-f0-9]{64}$'
    or app.m4_canonical_fingerprint(p_payload) <> p_expected_checksum
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid numbering version command';
  end if;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'key', normalized_key,
    'labels', p_labels,
    'payload', p_payload,
    'checksum', p_expected_checksum,
    'expectedLatestVersionId', p_expected_latest_version_id,
    'reason', normalized_reason
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fconfiguration_command\x1f'
      || actor_user_id::text || E'\x1f' || normalized_idempotency,
    0
  ));
  select command.* into existing
  from public.configuration_artifact_commands command
  where command.workspace_id = p_workspace_id
    and command.actor_user_id = app.current_user_id()
    and command.idempotency_key = normalized_idempotency;
  if found then
    if existing.action <> 'create_version'
      or existing.artifact_type <> 'numbering_definition'
      or existing.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'configuration command idempotency conflict';
    end if;
    return query select
      (existing.result ->> 'definitionId')::uuid,
      existing.artifact_id,
      (existing.result ->> 'version')::bigint,
      existing.result ->> 'status',
      existing.audit_event_id,
      true;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fnumbering_definition\x1f' || normalized_key,
    0
  ));
  select definition.id into definition_id
  from public.numbering_definitions definition
  where definition.workspace_id = p_workspace_id
    and definition.key = normalized_key;
  if not found then
    if p_expected_latest_version_id is not null then
      raise exception using errcode = '40001', message = 'numbering definition latest version changed';
    end if;
    insert into public.numbering_definitions (workspace_id, key, labels)
    values (p_workspace_id, normalized_key, p_labels)
    returning id into definition_id;
  else
    perform 1 from public.numbering_definitions definition
    where definition.workspace_id = p_workspace_id
      and definition.id = definition_id
      and definition.labels = p_labels;
    if not found then
      raise exception using errcode = '23514', message = 'numbering definition labels changed; create a new key';
    end if;
    select candidate.id into latest_version_id
    from public.numbering_definition_versions candidate
    where candidate.workspace_id = p_workspace_id
      and candidate.numbering_definition_id = definition_id
    order by candidate.version desc, candidate.id desc
    limit 1;
    if latest_version_id is distinct from p_expected_latest_version_id then
      raise exception using errcode = '40001', message = 'numbering definition latest version changed';
    end if;
  end if;
  select coalesce(pg_catalog.max(candidate.version), 0) + 1 into next_version
  from public.numbering_definition_versions candidate
  where candidate.workspace_id = p_workspace_id
    and candidate.numbering_definition_id = definition_id;

  insert into public.numbering_definition_versions (
    id, workspace_id, numbering_definition_id, version, semantic_version,
    scope_type, prefix, suffix, numeric_width, starting_value, increment_by,
    reset_policy, period_months, period_anchor, timezone_name, format_pattern,
    import_policy, reuse_policy, allocation_event, status, checksum,
    validation_evidence, fixture_evidence, created_by
  ) values (
    version_id, p_workspace_id, definition_id, next_version,
    p_payload ->> 'semanticVersion', p_payload ->> 'scopeType',
    coalesce(p_payload ->> 'prefix', ''), coalesce(p_payload ->> 'suffix', ''),
    (p_payload ->> 'numericWidth')::integer,
    (p_payload ->> 'startingValue')::bigint,
    coalesce((p_payload ->> 'incrementBy')::bigint, 1),
    coalesce(p_payload ->> 'resetPolicy', 'never'),
    (p_payload ->> 'periodMonths')::integer,
    (p_payload ->> 'periodAnchor')::date,
    coalesce(p_payload ->> 'timezone', 'UTC'),
    coalesce(p_payload ->> 'formatPattern', '{{prefix}}{{sequence}}{{suffix}}'),
    coalesce(p_payload ->> 'importPolicy', 'authorized_reservation'),
    coalesce(p_payload ->> 'reusePolicy', 'never'),
    p_payload ->> 'allocationEvent', 'draft', p_expected_checksum,
    null, null, actor_user_id
  );

  -- Validation and fixture evidence is generated by this trusted command from
  -- the immutable payload; callers cannot submit a self-attested `passed` bit.
  update public.numbering_definition_versions version set
    status = 'validated',
    validation_evidence = pg_catalog.jsonb_build_object(
      'passed', true,
      'validator', 'postgres-numbering-v1',
      'artifactChecksum', p_expected_checksum,
      'validatedAt', pg_catalog.statement_timestamp()
    )
  where version.workspace_id = p_workspace_id and version.id = version_id;

  fixture_scope_key := case p_payload ->> 'scopeType'
    when 'workspace' then 'workspace'
    else 'scope-a'
  end;
  fixture_period_key := case p_payload ->> 'resetPolicy'
    when 'never' then 'never'
    when 'yearly' then '2026'
    when 'monthly' then '2026-01'
    else 'period-0'
  end;
  fixture_first := app.m4_format_number(
    version_id,
    fixture_scope_key,
    fixture_period_key,
    (p_payload ->> 'startingValue')::bigint,
    ''
  );
  fixture_second := app.m4_format_number(
    version_id,
    fixture_scope_key,
    fixture_period_key,
    (p_payload ->> 'startingValue')::bigint
      + coalesce((p_payload ->> 'incrementBy')::bigint, 1),
    ''
  );
  if fixture_first = fixture_second then
    raise exception using errcode = '23514', message = 'numbering fixture outputs must be unique';
  end if;
  fixture_tests := pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'name', 'starting-value-format',
      'scope', fixture_scope_key,
      'period', fixture_period_key,
      'sequence', p_payload ->> 'startingValue',
      'output', fixture_first
    ),
    pg_catalog.jsonb_build_object(
      'name', 'increment-uniqueness',
      'scope', fixture_scope_key,
      'period', fixture_period_key,
      'sequence', (
        (p_payload ->> 'startingValue')::bigint
          + coalesce((p_payload ->> 'incrementBy')::bigint, 1)
      )::text,
      'output', fixture_second
    )
  );
  if p_payload ->> 'scopeType' <> 'workspace' then
    fixture_cross_scope := app.m4_format_number(
      version_id,
      'scope-b',
      fixture_period_key,
      (p_payload ->> 'startingValue')::bigint,
      ''
    );
    if fixture_cross_scope = fixture_first then
      raise exception using errcode = '23514', message = 'numbering scope fixture outputs must be unique';
    end if;
    fixture_tests := fixture_tests || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'name', 'scope-uniqueness',
        'scope', 'scope-b',
        'period', fixture_period_key,
        'sequence', p_payload ->> 'startingValue',
        'output', fixture_cross_scope
      )
    );
  end if;
  if p_payload ->> 'resetPolicy' <> 'never' then
    fixture_other_period_key := case p_payload ->> 'resetPolicy'
      when 'yearly' then '2027'
      when 'monthly' then '2026-02'
      else 'period-1'
    end;
    fixture_cross_period := app.m4_format_number(
      version_id,
      fixture_scope_key,
      fixture_other_period_key,
      (p_payload ->> 'startingValue')::bigint,
      ''
    );
    if fixture_cross_period = fixture_first then
      raise exception using errcode = '23514', message = 'numbering period fixture outputs must be unique';
    end if;
    fixture_tests := fixture_tests || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'name', 'period-uniqueness',
        'scope', fixture_scope_key,
        'period', fixture_other_period_key,
        'sequence', p_payload ->> 'startingValue',
        'output', fixture_cross_period
      )
    );
  end if;
  update public.numbering_definition_versions version set
    status = 'test_passed',
    fixture_evidence = pg_catalog.jsonb_build_object(
      'passed', true,
      'runner', 'postgres-numbering-v1',
      'tests', fixture_tests,
      'artifactChecksum', p_expected_checksum,
      'executedAt', pg_catalog.statement_timestamp()
    )
  where version.workspace_id = p_workspace_id and version.id = version_id;
  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'configuration.numbering_version_created',
    p_entity_type => 'numbering_definition',
    p_entity_id => version_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'definitionId', definition_id,
      'key', normalized_key,
      'version', next_version,
      'status', 'test_passed',
      'checksum', p_expected_checksum
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id
  );
  insert into public.configuration_artifact_commands (
    workspace_id, actor_user_id, artifact_type, artifact_id, action,
    idempotency_key, command_fingerprint, reason, result, audit_event_id
  ) values (
    p_workspace_id, actor_user_id, 'numbering_definition', version_id,
    'create_version', normalized_idempotency, fingerprint, normalized_reason,
    pg_catalog.jsonb_build_object(
      'definitionId', definition_id,
      'version', next_version,
      'status', 'test_passed'
    ), audit_id
  );
  return query select definition_id, version_id, next_version, 'test_passed'::text, audit_id, false;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'numbering payload contains an invalid typed value';
end;
$$;

revoke all on function app.m4_artifact_descriptor(uuid, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_record_artifact_approval(
  uuid, text, uuid, text, text, text, text, text, text, text, jsonb,
  text, timestamptz, timestamptz, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_transition_artifact_version(
  uuid, text, uuid, text, text, jsonb, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_create_numbering_version(
  uuid, text, jsonb, jsonb, text, uuid, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.m4_record_artifact_approval(
  uuid, text, uuid, text, text, text, text, text, text, text, jsonb,
  text, timestamptz, timestamptz, uuid, text, uuid
) to authenticated;
grant execute on function app.m4_transition_artifact_version(
  uuid, text, uuid, text, text, jsonb, text, text, text, uuid
) to authenticated;
grant execute on function app.m4_create_numbering_version(
  uuid, text, jsonb, jsonb, text, uuid, text, text, text, uuid
) to authenticated;

comment on table public.configuration_artifact_commands is
  'Append-only actor-scoped idempotency and audit results for exact-version Milestone 4 configuration commands.';
