-- VYN-DOC-001, VYN-NUM-001, VYN-CALC-001, VYN-TAX-001, VYN-EXP-001
-- M4-CFG-AC-004, M4-DOC-AC-003..010, M4-EXP-AC-005.
-- Bounded authenticated projections, runtime-configuration loaders, reports,
-- and generic job-to-domain failure synchronization for Milestone 4.

create function app.m4_sync_domain_job_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_entity_id uuid;
  previous_run_status text;
begin
  if old.status = new.status
    or new.status not in ('retry_wait', 'dead_letter') then
    return new;
  end if;

  if new.job_type = 'documents.render_pdf' then
    update public.documents document set
      status = 'generation_failed',
      failure_code = coalesce(new.last_error_code, 'worker.unclassified_failure'),
      aggregate_version = document.aggregate_version + 1
    where document.workspace_id = new.workspace_id
      and document.id = new.entity_id
      and document.mode = 'official'
      and document.status = 'generating'
    returning document.id into changed_entity_id;

    if changed_entity_id is not null then
      perform app.write_audit_event(
        p_workspace_id => new.workspace_id,
        p_action => 'document.official_generation_failed',
        p_entity_type => 'document',
        p_entity_id => changed_entity_id,
        p_actor_type => 'worker',
        p_before_data => pg_catalog.jsonb_build_object('status', 'generating'),
        p_after_data => pg_catalog.jsonb_build_object(
          'status', 'generation_failed',
          'failureCode', coalesce(new.last_error_code, 'worker.unclassified_failure'),
          'jobStatus', new.status,
          'retryAt', case when new.status = 'retry_wait' then new.available_at else null end
        ),
        p_reason => coalesce(new.last_error_code, 'worker.unclassified_failure'),
        p_correlation_id => new.correlation_id,
        p_auth_assurance => 'service',
        p_metadata => pg_catalog.jsonb_build_object('jobId', new.id)
      );
    end if;
  elsif new.job_type = 'exports.generate' then
    select run.status into previous_run_status
    from public.export_runs run
    where run.workspace_id = new.workspace_id
      and run.id = new.entity_id
      and run.status in ('queued', 'running', 'retry_wait')
    for update;
    update public.export_runs run set
      status = new.status,
      failure_code = case
        when new.status = 'dead_letter'
          then coalesce(new.last_error_code, 'worker.unclassified_failure')
        else null
      end
    where run.workspace_id = new.workspace_id
      and run.id = new.entity_id
      and run.status in ('queued', 'running', 'retry_wait')
    returning run.id into changed_entity_id;

    if changed_entity_id is not null then
      perform app.write_audit_event(
        p_workspace_id => new.workspace_id,
        p_action => 'export.run_failed',
        p_entity_type => 'export_run',
        p_entity_id => changed_entity_id,
        p_actor_type => 'worker',
        p_before_data => pg_catalog.jsonb_build_object(
          'status', previous_run_status
        ),
        p_after_data => pg_catalog.jsonb_build_object(
          'status', new.status,
          'failureCode', new.last_error_code,
          'retryAt', case when new.status = 'retry_wait' then new.available_at else null end
        ),
        p_reason => coalesce(new.last_error_code, 'worker.unclassified_failure'),
        p_correlation_id => new.correlation_id,
        p_auth_assurance => 'service',
        p_metadata => pg_catalog.jsonb_build_object('jobId', new.id)
      );
    end if;
  end if;

  return new;
end;
$$;

create trigger jobs_m4_sync_domain_status
after update of status on public.jobs
for each row execute function app.m4_sync_domain_job_status();

create function app.m4_list_document_types(p_workspace_id uuid)
returns table (
  activation_status text,
  field_schema jsonb,
  field_schema_checksum text,
  id uuid,
  key text,
  labels jsonb,
  official_generation_enabled boolean,
  preview_generation_enabled boolean,
  production_enabled boolean,
  template_locales text[],
  version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'documents.read');
  return query
  select
    document_type.activation_status,
    document_type.field_schema,
    document_type.field_schema_checksum,
    document_type.id,
    document_type.key::text,
    document_type.labels,
    document_type.official_generation_enabled,
    document_type.preview_generation_enabled,
    document_type.production_enabled,
    coalesce((
      select pg_catalog.array_agg(distinct template.locale order by template.locale)
      from public.document_template_versions template
      where template.workspace_id = document_type.workspace_id
        and template.document_type_id = document_type.id
        and template.status = 'active'
        and template.activation_status <> 'retired'
    ), array[]::text[]),
    document_type.version::bigint
  from public.document_types document_type
  where document_type.workspace_id = p_workspace_id
    and document_type.status = 'active'
  order by document_type.key, document_type.version desc, document_type.id;
end;
$$;

create function app.m4_validate_document(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_document_type_id uuid,
  p_template_version_id uuid,
  p_locale text,
  p_document_date date,
  p_intended_signature_date date,
  p_document_fields jsonb,
  p_calculation_evidence jsonb,
  p_tax_evidence jsonb
)
returns table (
  calculation_ready boolean,
  document_type_ready boolean,
  errors text[],
  numbering_ready boolean,
  official_ready boolean,
  preview_ready boolean,
  tax_ready boolean,
  template_ready boolean,
  warnings text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target_type public.document_types%rowtype;
  target_template public.document_template_versions%rowtype;
  target_deal public.deals%rowtype;
  numbering_version public.numbering_definition_versions%rowtype;
  numbering_definition public.numbering_definitions%rowtype;
  trusted_calculation public.runtime_evidence_records%rowtype;
  trusted_tax public.runtime_evidence_records%rowtype;
  calculation_version public.calculation_versions%rowtype;
  tax_version public.tax_pack_versions%rowtype;
  tax_assignment public.tax_pack_assignments%rowtype;
  workflow_dependency record;
  current_deal_context jsonb;
  current_deal_context_checksum text;
  current_deal_currency_code text;
  expected_tax_input jsonb;
  expected_tax_input_checksum text;
  calculation_definition_key text;
  tax_pack_key text;
  calculation_receipt_ready boolean := false;
  calculation_artifact_ready boolean := false;
  tax_receipt_ready boolean := false;
  tax_artifact_ready boolean := false;
  tax_assignment_ready boolean := false;
  deal_scope_ready boolean := false;
  calculated_ready boolean;
  numbered_ready boolean;
  taxes_ready boolean;
  workflow_is_ready boolean := true;
  type_available boolean := false;
  type_ready boolean;
  template_available boolean := false;
  template_is_ready boolean;
  preview_is_ready boolean;
  official_is_ready boolean;
  validation_errors text[] := array[]::text[];
  validation_warnings text[] := array[]::text[];
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'documents.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'deals.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'crm.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');

  select deal.* into target_deal from public.deals deal
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id;
  if not found or target_deal.lifecycle_status <> 'active' then
    validation_errors := pg_catalog.array_append(validation_errors, 'document.deal_not_eligible');
  else
    current_deal_context := app.m4_deal_source_snapshot(p_workspace_id, p_deal_id);
    if current_deal_context is not null then
      current_deal_context_checksum := app.m4_canonical_fingerprint(
        current_deal_context
      );
      current_deal_currency_code := current_deal_context -> 'deal' ->> 'currency_code';
    end if;
    select exists (
      select 1
      from public.legal_entities entity
      join public.locations location
        on location.workspace_id = entity.workspace_id
       and location.id = target_deal.location_id
       and location.status = 'active'
      where entity.workspace_id = p_workspace_id
        and entity.id = target_deal.legal_entity_id
        and entity.status = 'active'
    ) into deal_scope_ready;
  end if;

  select document_type.* into target_type
  from public.document_types document_type
  where document_type.workspace_id = p_workspace_id
    and document_type.id = p_document_type_id
    and document_type.status = 'active';
  type_available := found;
  if not type_available then
    validation_errors := pg_catalog.array_append(validation_errors, 'document.type_unavailable');
    type_ready := false;
  else
    type_ready := target_type.official_generation_enabled
      and target_type.production_enabled
      and target_type.activation_status = 'active'
      and app.m4_exact_approval_valid(
        p_workspace_id,
        target_type.approval_record_id,
        'document_type',
        'document.' || pg_catalog.regexp_replace(
          pg_catalog.lower(target_type.key::text),
          '[^a-z0-9_]+',
          '_',
          'g'
        ),
        target_type.version,
        target_type.id,
        target_type.checksum
      );
    if target_type.official_generation_enabled
      and target_type.production_enabled
      and target_type.activation_status = 'active'
      and not type_ready then
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.type_approval_invalid'
      );
    end if;
  end if;

  if type_available then
    if target_type.official_generation_enabled
      and target_type.production_enabled
      and target_type.activation_status = 'active'
      and not deal_scope_ready then
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.deal_scope_unavailable'
      );
    end if;
    select dependency.* into workflow_dependency
    from app.m4_document_workflow_dependency(
      p_workspace_id,
      p_deal_id,
      target_type.workflow_version_id
    ) dependency;
    if target_type.workflow_version_id is not null
      and not workflow_dependency.deal_matches then
      workflow_is_ready := false;
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.workflow_mismatch'
      );
    elsif target_type.workflow_version_id is not null
      and not workflow_dependency.workflow_active then
      workflow_is_ready := false;
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.workflow_inactive'
      );
    elsif target_type.workflow_version_id is not null
      and not workflow_dependency.approval_valid then
      workflow_is_ready := false;
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.workflow_approval_invalid'
      );
    end if;
  end if;

  select template.* into target_template
  from public.document_template_versions template
  where template.workspace_id = p_workspace_id
    and template.id = p_template_version_id
    and template.document_type_id = p_document_type_id
    and template.locale = pg_catalog.btrim(coalesce(p_locale, ''))
    and template.status = 'active'
    and template.activation_status <> 'retired';
  template_available := coalesce(
    found and target_template.field_schema_checksum = target_type.field_schema_checksum,
    false
  );
  if not template_available then
    validation_errors := pg_catalog.array_append(validation_errors, 'document.template_unavailable');
    template_is_ready := false;
  else
    template_is_ready := target_template.template_class = 'tenant_approved'
      and target_template.production_approved
      and target_template.activation_status = 'active'
      and app.m4_exact_approval_valid(
        p_workspace_id,
        target_template.approval_record_id,
        'document_template',
        'template.' || pg_catalog.regexp_replace(
          pg_catalog.lower(target_type.key::text),
          '[^a-z0-9_]+',
          '_',
          'g'
        ) || '.' || pg_catalog.replace(
          pg_catalog.lower(target_template.locale),
          '-',
          '_'
        ),
        target_template.version,
        target_template.id,
        target_template.source_bundle_checksum
      );
    if target_template.template_class = 'tenant_approved'
      and target_template.production_approved
      and target_template.activation_status = 'active'
      and not template_is_ready then
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.template_approval_invalid'
      );
    end if;
  end if;

  if p_document_date is null
    or p_intended_signature_date is not null
      and p_intended_signature_date < p_document_date then
    validation_errors := pg_catalog.array_append(validation_errors, 'document.date_invalid');
  end if;
  if type_available and not app.m4_validate_document_fields(
    target_type.field_schema, p_document_fields
  ) then
    validation_errors := pg_catalog.array_append(validation_errors, 'document.fields_invalid');
  end if;

  -- Validation consumes the same server-authored receipt contract as the
  -- official command. Client-carried result objects are never treated as
  -- proof of execution; only their opaque evidenceId selects the immutable
  -- actor/deal/version-bound record.
  calculated_ready := coalesce(
    target_type.calculation_version_id is null
      and p_calculation_evidence is null,
    false
  );
  if type_available and target_type.calculation_version_id is not null then
    select version.* into calculation_version
    from public.calculation_versions version
    where version.workspace_id = p_workspace_id
      and version.id = target_type.calculation_version_id
      and version.status = 'active';
    calculation_artifact_ready := found;
    if not calculation_artifact_ready then
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.calculation_version_unavailable'
      );
    else
      select definition.key::text into calculation_definition_key
      from public.calculation_definitions definition
      where definition.workspace_id = calculation_version.workspace_id
        and definition.id = calculation_version.calculation_definition_id;
      calculation_artifact_ready := found and app.m4_exact_approval_valid(
        p_workspace_id,
        calculation_version.approval_record_id,
        'calculation',
        'formula.' || calculation_definition_key,
        calculation_version.version,
        calculation_version.id,
        calculation_version.checksum
      );
    end if;
  end if;
  if type_available
    and target_type.calculation_version_id is not null
    and current_deal_context is not null
    and pg_catalog.jsonb_typeof(p_calculation_evidence) is not distinct from 'object'
    and coalesce(p_calculation_evidence ->> 'evidenceId', '')
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select evidence.* into trusted_calculation
    from public.runtime_evidence_records evidence
    where evidence.workspace_id = p_workspace_id
      and evidence.id = (p_calculation_evidence ->> 'evidenceId')::uuid
      and evidence.evidence_type = 'calculation'
      and evidence.official_eligible
      and evidence.actor_user_id = app.current_user_id()
      and evidence.deal_id = p_deal_id
      and evidence.deal_context_checksum = current_deal_context_checksum
      and evidence.calculation_version_id = target_type.calculation_version_id
      and evidence.expires_at > pg_catalog.statement_timestamp()
      and not exists (
        select 1 from public.runtime_evidence_consumptions consumption
        where consumption.workspace_id = evidence.workspace_id
          and consumption.evidence_id = evidence.id
      );
    calculation_receipt_ready := found;

    if calculation_receipt_ready then
      calculated_ready := calculation_artifact_ready
        and trusted_calculation.snapshot_checksum is not distinct from
          app.m4_canonical_fingerprint(trusted_calculation.snapshot - 'checksum')
        and trusted_calculation.snapshot_checksum is not distinct from
          trusted_calculation.snapshot ->> 'checksum'
        and trusted_calculation.snapshot ->> 'versionId' is not distinct from
          calculation_version.id::text
        and trusted_calculation.snapshot ->> 'definitionChecksum' is not distinct from
          calculation_version.checksum
        and trusted_calculation.snapshot ->> 'engineVersion' is not distinct from
          calculation_version.engine_version
        and pg_catalog.jsonb_typeof(trusted_calculation.snapshot -> 'definition')
          is not distinct from 'object'
        and app.m4_canonical_fingerprint(
          (trusted_calculation.snapshot -> 'definition')
            - array['status', 'approval_refs']::text[]
        ) is not distinct from calculation_version.checksum
        and pg_catalog.jsonb_typeof(trusted_calculation.snapshot -> 'output')
          is not distinct from 'object'
        and pg_catalog.jsonb_typeof(trusted_calculation.snapshot -> 'components')
          is not distinct from 'array'
        and pg_catalog.jsonb_typeof(trusted_calculation.snapshot -> 'taxComponents')
          is not distinct from 'array'
        and pg_catalog.jsonb_typeof(trusted_calculation.snapshot -> 'rounding')
          is not distinct from 'object'
        and trusted_calculation.snapshot -> 'input' is not distinct from
          current_deal_context
        and trusted_calculation.snapshot -> 'inputBinding' is not distinct from
          pg_catalog.jsonb_build_object(
            'mapperVersion', 'deal-runtime-input-v1',
            'dealContextChecksum', current_deal_context_checksum,
            'inputProjectionChecksum', app.m4_canonical_fingerprint(
              current_deal_context
            )
          );
    end if;
  end if;

  taxes_ready := coalesce(
    target_type.tax_pack_version_id is null and p_tax_evidence is null,
    false
  );
  if type_available
    and target_type.tax_pack_version_id is not null
    and current_deal_context is not null
    and pg_catalog.jsonb_typeof(p_tax_evidence) is not distinct from 'object'
    and coalesce(p_tax_evidence ->> 'evidenceId', '')
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select evidence.* into trusted_tax
    from public.runtime_evidence_records evidence
    where evidence.workspace_id = p_workspace_id
      and evidence.id = (p_tax_evidence ->> 'evidenceId')::uuid
      and evidence.evidence_type = 'tax'
      and evidence.official_eligible
      and evidence.actor_user_id = app.current_user_id()
      and evidence.deal_id = p_deal_id
      and evidence.deal_context_checksum = current_deal_context_checksum
      and evidence.tax_pack_version_id = target_type.tax_pack_version_id
      and evidence.expires_at > pg_catalog.statement_timestamp()
      and not exists (
        select 1 from public.runtime_evidence_consumptions consumption
        where consumption.workspace_id = evidence.workspace_id
          and consumption.evidence_id = evidence.id
      );
    tax_receipt_ready := found;

    select version.* into tax_version
    from public.tax_pack_versions version
    where version.workspace_id = p_workspace_id
      and version.id = target_type.tax_pack_version_id
      and version.status = 'active';
    tax_artifact_ready := found;
    if tax_artifact_ready then
      select pack.key::text into tax_pack_key
      from public.tax_packs pack
      where pack.workspace_id = tax_version.workspace_id
        and pack.id = tax_version.tax_pack_id;
      tax_artifact_ready := found and app.m4_exact_approval_valid(
        p_workspace_id,
        tax_version.approval_record_id,
        'tax_pack',
        'tax.' || tax_pack_key,
        tax_version.version,
        tax_version.id,
        tax_version.checksum
      );
    end if;

    if tax_receipt_ready
      and trusted_tax.snapshot ->> 'currency' is not distinct from
        current_deal_currency_code then
      begin
        expected_tax_input := app.m4_deal_tax_input(
          current_deal_context,
          trusted_tax.snapshot ->> 'jurisdiction'
        );
        expected_tax_input_checksum := app.m4_canonical_fingerprint(
          expected_tax_input
        );
      exception when check_violation then
        expected_tax_input := null;
        expected_tax_input_checksum := null;
      end;
    end if;

    if tax_receipt_ready
      and coalesce(trusted_tax.snapshot ->> 'assignmentId', '')
        ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and coalesce(trusted_tax.snapshot ->> 'transactionDate', '')
        ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      begin
        select assignment.* into tax_assignment
        from public.tax_pack_assignments assignment
        where assignment.workspace_id = p_workspace_id
          and assignment.id = (trusted_tax.snapshot ->> 'assignmentId')::uuid
          and assignment.id = trusted_tax.tax_assignment_id
          and assignment.tax_pack_version_id = tax_version.id
          and assignment.approval_record_id = tax_version.approval_record_id
          and assignment.jurisdiction_code = trusted_tax.snapshot ->> 'jurisdiction'
          and assignment.context_key = trusted_tax.snapshot ->> 'context'
          and assignment.currency_code = trusted_tax.snapshot ->> 'currency'
          and assignment.effective_from <=
            (trusted_tax.snapshot ->> 'transactionDate')::date
          and (coalesce(
            assignment.superseded_effective_to,
            assignment.effective_to
          ) is null or coalesce(
            assignment.superseded_effective_to,
            assignment.effective_to
          ) >= (trusted_tax.snapshot ->> 'transactionDate')::date);
        tax_assignment_ready := found
          and (trusted_tax.snapshot ->> 'transactionDate')::date = p_document_date;
      exception
        when invalid_text_representation
          or invalid_datetime_format
          or datetime_field_overflow then
        tax_assignment_ready := false;
      end;
    end if;

    if tax_receipt_ready then
      taxes_ready := tax_artifact_ready
        and tax_assignment_ready
        and expected_tax_input is not null
        and trusted_tax.snapshot_checksum is not distinct from
          app.m4_canonical_fingerprint(trusted_tax.snapshot - 'checksum')
        and trusted_tax.snapshot_checksum is not distinct from
          trusted_tax.snapshot ->> 'checksum'
        and trusted_tax.snapshot ->> 'versionId' is not distinct from tax_version.id::text
        and trusted_tax.snapshot ->> 'packChecksum' is not distinct from tax_version.checksum
        and trusted_tax.snapshot ->> 'engineVersion' is not distinct from tax_version.engine_version
        and pg_catalog.jsonb_typeof(trusted_tax.snapshot -> 'pack')
          is not distinct from 'object'
        and pg_catalog.jsonb_typeof(trusted_tax.snapshot -> 'pack' -> 'sources')
          is not distinct from 'array'
        and app.m4_canonical_fingerprint(
          (trusted_tax.snapshot -> 'pack')
            - array['activation_status', 'approval_refs']::text[]
        ) is not distinct from tax_version.checksum
        and pg_catalog.jsonb_typeof(trusted_tax.snapshot -> 'output')
          is not distinct from 'object'
        and trusted_tax.snapshot -> 'input' is not distinct from expected_tax_input
        and trusted_tax.snapshot -> 'inputBinding' is not distinct from
          pg_catalog.jsonb_build_object(
            'mapperVersion', 'deal-runtime-input-v1',
            'dealContextChecksum', current_deal_context_checksum,
            'inputProjectionChecksum', expected_tax_input_checksum
          )
        and (
          not (trusted_tax.snapshot ? 'override')
          or app.m4_tax_override_evidence_valid(trusted_tax.snapshot)
          and app.m4_actor_has_permission(
              p_workspace_id,
              app.current_user_id(),
              'tax.override'
          )
        );
    end if;
    if tax_receipt_ready
      and trusted_tax.snapshot ? 'override'
      and not app.m4_tax_override_evidence_valid(trusted_tax.snapshot) then
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.tax_override_invalid'
      );
    end if;
  end if;
  numbered_ready := false;
  if type_available and target_type.numbering_definition_version_id is not null then
    select version.* into numbering_version
    from public.numbering_definition_versions version
    where version.workspace_id = p_workspace_id
      and version.id = target_type.numbering_definition_version_id
      and version.status = 'active';
    if found then
      select definition.* into numbering_definition
      from public.numbering_definitions definition
      where definition.workspace_id = numbering_version.workspace_id
        and definition.id = numbering_version.numbering_definition_id;
      numbered_ready := found and app.m4_exact_approval_valid(
        p_workspace_id,
        numbering_version.approval_record_id,
        'numbering_definition',
        'numbering.' || numbering_definition.key::text,
        numbering_version.version,
        numbering_version.id,
        numbering_version.checksum
      );
    end if;
  end if;
  preview_is_ready := coalesce(type_available and template_available
    and workflow_is_ready
    and target_type.preview_generation_enabled
    and target_template.template_class = 'synthetic_non_production'
    and not target_template.production_approved
    and target_template.watermark = 'DRAFT / NON-PRODUCTION', false);
  official_is_ready := coalesce(type_ready and template_is_ready
    and deal_scope_ready and workflow_is_ready and numbered_ready
    and calculated_ready and taxes_ready
    and pg_catalog.cardinality(validation_errors) = 0, false);

  if not calculated_ready then
    validation_errors := pg_catalog.array_append(validation_errors, 'document.calculation_missing');
  end if;
  if not taxes_ready then
    validation_errors := pg_catalog.array_append(validation_errors, 'document.tax_missing');
  end if;
  if not numbered_ready then
    validation_warnings := pg_catalog.array_append(validation_warnings, 'document.numbering_unavailable');
    if type_available
      and template_available
      and target_type.official_generation_enabled
      and target_type.production_enabled
      and target_type.activation_status = 'active'
      and target_template.template_class = 'tenant_approved'
      and target_template.production_approved
      and target_template.activation_status = 'active' then
      validation_errors := pg_catalog.array_append(
        validation_errors,
        'document.numbering_unavailable'
      );
    end if;
  end if;
  if preview_is_ready and not official_is_ready then
    validation_warnings := pg_catalog.array_append(validation_warnings, 'document.preview_only');
  end if;

  return query select
    calculated_ready, type_ready, validation_errors, numbered_ready,
    official_is_ready, preview_is_ready, taxes_ready, template_is_ready,
    validation_warnings;
end;
$$;

create function app.m4_request_document_preview(
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
  normalized_locale text := pg_catalog.btrim(coalesce(p_locale, ''));
  request_fingerprint text;
  existing_document public.documents%rowtype;
  existing_mapping public.document_preview_jobs%rowtype;
  target_type public.document_types%rowtype;
  target_template public.document_template_versions%rowtype;
  workflow_dependency record;
  validation record;
  input_snapshot jsonb;
  input_checksum text;
  version_snapshot jsonb;
  version_checksum text;
  new_document_id uuid := pg_catalog.gen_random_uuid();
  new_mapping_id uuid := pg_catalog.gen_random_uuid();
  queued_job record;
  audit_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id, 'documents.preview'
  );
  perform app.require_vertical_slice_permission(p_workspace_id, 'documents.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'deals.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'crm.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');

  if pg_catalog.char_length(normalized_idempotency) not between 8 and 200
    or normalized_locale !~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'
    or p_document_date is null
    or pg_catalog.jsonb_typeof(p_document_fields) <> 'object'
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'document.preview_command_invalid';
  end if;

  request_fingerprint := app.m4_canonical_fingerprint(
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'documentTypeId', p_document_type_id,
      'templateVersionId', p_template_version_id,
      'locale', normalized_locale,
      'documentDate', p_document_date,
      'intendedSignatureDate', p_intended_signature_date,
      'documentFields', p_document_fields,
      'calculationEvidence', p_calculation_evidence,
      'taxEvidence', p_tax_evidence
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fpreview_document\x1f' || normalized_idempotency,
    0
  ));

  select document.* into existing_document
  from public.documents document
  where document.workspace_id = p_workspace_id
    and document.idempotency_key = normalized_idempotency;
  if found then
    if existing_document.mode <> 'preview'
      or existing_document.command_fingerprint <> request_fingerprint
      or existing_document.created_by <> actor_user_id then
      raise exception using errcode = '23505', message = 'document.preview_idempotency_conflict';
    end if;
    select mapping.* into existing_mapping
    from public.document_preview_jobs mapping
    where mapping.workspace_id = p_workspace_id
      and mapping.document_id = existing_document.id;
    if not found then
      raise exception using errcode = '55000', message = 'document.preview_job_link_missing';
    end if;
    select event.id into audit_id
    from public.audit_events event
    where event.workspace_id = p_workspace_id
      and event.entity_type = 'document'
      and event.entity_id = existing_document.id
      and event.action = 'document.preview_requested'
    order by event.occurred_at, event.id
    limit 1;
    if audit_id is null then
      raise exception using errcode = '55000', message = 'document.preview_audit_missing';
    end if;
    return query select
      existing_document.id,
      null::text,
      existing_document.status,
      null::uuid,
      existing_mapping.outbox_event_id,
      existing_mapping.job_id,
      audit_id,
      existing_document.aggregate_version,
      true;
    return;
  end if;

  select document_type.* into target_type
  from public.document_types document_type
  where document_type.workspace_id = p_workspace_id
    and document_type.id = p_document_type_id
    and document_type.status = 'active'
    and document_type.preview_generation_enabled;
  if not found then
    raise exception using errcode = '23514', message = 'document.preview_type_unavailable';
  end if;
  select template.* into target_template
  from public.document_template_versions template
  where template.workspace_id = p_workspace_id
    and template.id = p_template_version_id
    and template.document_type_id = target_type.id
    and template.locale = normalized_locale
    and template.status = 'active'
    and template.activation_status <> 'retired'
    and template.template_class = 'synthetic_non_production'
    and not template.production_approved
    and template.watermark = 'DRAFT / NON-PRODUCTION';
  if not found
    or target_template.field_schema_checksum <> target_type.field_schema_checksum then
    raise exception using errcode = '23514', message = 'document.preview_template_unavailable';
  end if;

  select dependency.* into workflow_dependency
  from app.m4_document_workflow_dependency(
    p_workspace_id,
    p_deal_id,
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

  select checked.* into validation
  from app.m4_validate_document(
    p_workspace_id, p_deal_id, p_document_type_id, p_template_version_id,
    normalized_locale, p_document_date, p_intended_signature_date,
    p_document_fields, p_calculation_evidence, p_tax_evidence
  ) checked;
  if not found or not validation.preview_ready
    or pg_catalog.cardinality(validation.errors) <> 0 then
    raise exception using errcode = '23514', message = 'document.preview_validation_failed';
  end if;

  input_snapshot := app.m4_document_input_snapshot(
    p_workspace_id, p_deal_id, p_document_date, p_intended_signature_date,
    normalized_locale, p_document_fields, p_calculation_evidence, p_tax_evidence
  );
  if input_snapshot is null then
    raise exception using errcode = '23514', message = 'document.preview_snapshot_unavailable';
  end if;
  input_checksum := app.m4_canonical_fingerprint(input_snapshot);
  version_snapshot := pg_catalog.jsonb_build_object(
    'schemaVersion', 3,
    'documentTypeId', target_type.id,
    'documentTypeChecksum', target_type.checksum,
    'templateVersionId', target_template.id,
    'templateBundleChecksum', target_template.source_bundle_checksum,
    'workflowVersionId', target_type.workflow_version_id,
    'workflowVersion', workflow_dependency.workflow_version,
    'workflowRevision', workflow_dependency.workflow_revision,
    'workflowChecksum', workflow_dependency.workflow_checksum,
    'numberingVersionId', target_type.numbering_definition_version_id,
    'calculationVersionId', target_type.calculation_version_id,
    'taxPackVersionId', target_type.tax_pack_version_id,
    'rendererVersion', target_template.renderer_version,
    'preview', true
  );
  version_checksum := app.m4_canonical_fingerprint(version_snapshot);

  insert into public.documents (
    id, workspace_id, document_type_id, template_version_id, deal_id, mode,
    official_number, status, locale, watermark, render_input_snapshot,
    render_input_checksum, idempotency_key, command_fingerprint, created_by,
    document_date, intended_signature_date, workflow_version_id,
    tax_pack_version_id, calculation_version_id, renderer_version,
    version_snapshot, version_snapshot_checksum
  ) values (
    new_document_id, p_workspace_id, target_type.id, target_template.id,
    p_deal_id, 'preview', null, 'queued', normalized_locale,
    'DRAFT / NON-PRODUCTION', input_snapshot, input_checksum,
    normalized_idempotency, request_fingerprint, actor_user_id,
    p_document_date, p_intended_signature_date, target_type.workflow_version_id,
    target_type.tax_pack_version_id, target_type.calculation_version_id,
    target_template.renderer_version, version_snapshot, version_checksum
  );

  select queued.* into queued_job
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'document.preview_requested',
    p_aggregate_type => 'document',
    p_aggregate_id => new_document_id,
    p_aggregate_version => 1,
    p_job_type => 'documents.render_preview',
    p_entity_type => 'document',
    p_entity_id => new_document_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'document_id', new_document_id,
      'template_version_id', target_template.id,
      'render_input_checksum', input_checksum,
      'locale', normalized_locale
    ),
    p_idempotency_key => normalized_idempotency,
    p_correlation_id => p_correlation_id,
    p_actor_user_id => actor_user_id,
    p_request_id => p_request_id
  ) queued;
  insert into public.document_preview_jobs (
    id, workspace_id, document_id, outbox_event_id, job_id, idempotency_key,
    request_fingerprint, requested_by
  ) values (
    new_mapping_id, p_workspace_id, new_document_id, queued_job.outbox_event_id,
    queued_job.job_id, normalized_idempotency, request_fingerprint, actor_user_id
  );
  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.preview_requested',
    p_entity_type => 'document',
    p_entity_id => new_document_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'mode', 'preview',
      'status', 'queued',
      'watermark', 'DRAFT / NON-PRODUCTION',
      'renderInputChecksum', input_checksum,
      'versionSnapshotChecksum', version_checksum,
      'jobId', queued_job.job_id
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotencyKey', normalized_idempotency,
      'officialNumberAllocated', false
    )
  );

  return query select
    new_document_id, null::text, 'queued'::text, null::uuid,
    queued_job.outbox_event_id, queued_job.job_id, audit_id, 1::bigint, false;
end;
$$;

create function app.m4_list_documents(
  p_workspace_id uuid,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_deal_id uuid default null,
  p_document_type_key text default null,
  p_limit integer default 50,
  p_mode text default null,
  p_status text default null
)
returns table (
  aggregate_version bigint,
  created_at timestamptz,
  current_file_id uuid,
  preview_artifact_id uuid,
  deal_id uuid,
  document_type_key text,
  generated_at timestamptz,
  id uuid,
  job_status text,
  locale text,
  mode text,
  official_number text,
  status text,
  superseded_by_document_id uuid,
  supersedes_document_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'documents.read');
  if p_limit not between 1 and 200
    or (p_cursor_created_at is null) <> (p_cursor_id is null)
    or p_mode is not null and p_mode not in ('preview', 'official')
    or p_status is not null and p_status not in (
      'queued', 'generating', 'generated', 'failed', 'generation_failed',
      'signed_received', 'completed', 'voided', 'superseded'
    ) then
    raise exception using errcode = '22023', message = 'invalid document list query';
  end if;

  return query
  select
    document.aggregate_version,
    document.created_at,
    current_file.id,
    preview_file.id,
    document.deal_id,
    document_type.key::text,
    coalesce(current_file.recorded_at, preview_file.created_at),
    document.id,
    coalesce(official_job.status, preview_job.status),
    document.locale,
    document.mode,
    document.official_number,
    document.status,
    document.superseded_by_document_id,
    document.supersedes_document_id
  from public.documents document
  join public.document_types document_type
    on document_type.workspace_id = document.workspace_id
   and document_type.id = document.document_type_id
  left join lateral (
    select file.id, file.recorded_at
    from public.document_files file
    where file.workspace_id = document.workspace_id
      and file.document_id = document.id and file.current
      and (file.role <> 'signed_scan'
        or app.has_permission(document.workspace_id, 'files.read_restricted'))
    order by case file.role when 'signed_scan' then 0 else 1 end,
      file.version desc, file.id desc limit 1
  ) current_file on true
  left join lateral (
    select artifact.id, artifact.created_at
    from public.document_preview_artifacts artifact
    where artifact.workspace_id = document.workspace_id
      and artifact.document_id = document.id
    order by artifact.created_at desc, artifact.id desc
    limit 1
  ) preview_file on true
  left join lateral (
    select job.status
    from public.document_render_attempts attempt
    join public.jobs job
      on job.workspace_id = attempt.workspace_id
     and job.id = attempt.job_id
    where attempt.workspace_id = document.workspace_id
      and attempt.document_id = document.id
    order by attempt.attempt_number desc, attempt.id desc
    limit 1
  ) official_job on true
  left join public.document_preview_jobs preview_mapping
    on preview_mapping.workspace_id = document.workspace_id
   and preview_mapping.document_id = document.id
  left join public.jobs preview_job
    on preview_job.workspace_id = preview_mapping.workspace_id
   and preview_job.id = preview_mapping.job_id
  where document.workspace_id = p_workspace_id
    and (p_deal_id is null or document.deal_id = p_deal_id)
    and (p_document_type_key is null
      or document_type.key = pg_catalog.lower(pg_catalog.btrim(p_document_type_key)))
    and (p_mode is null or document.mode = p_mode)
    and (p_status is null or document.status = p_status)
    and (p_cursor_created_at is null
      or (document.created_at, document.id) < (p_cursor_created_at, p_cursor_id))
  order by document.created_at desc, document.id desc
  limit p_limit;
end;
$$;

create function app.m4_get_document_detail(
  p_workspace_id uuid,
  p_document_id uuid
)
returns table (
  aggregate_version bigint,
  created_at timestamptz,
  current_file_id uuid,
  preview_artifact_id uuid,
  deal_id uuid,
  document_type_key text,
  generated_at timestamptz,
  id uuid,
  job_status text,
  locale text,
  mode text,
  official_number text,
  status text,
  superseded_by_document_id uuid,
  supersedes_document_id uuid,
  calculation_snapshot jsonb,
  document_date date,
  files jsonb,
  intended_signature_date date,
  jobs jsonb,
  render_input_checksum text,
  signed_at timestamptz,
  tax_snapshot jsonb,
  version_snapshot jsonb,
  version_snapshot_checksum text,
  void_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'documents.read');
  return query
  select
    document.aggregate_version,
    document.created_at,
    current_file.id,
    preview_file.id,
    document.deal_id,
    document_type.key::text,
    coalesce(current_file.recorded_at, preview_file.created_at),
    document.id,
    current_job.status,
    document.locale,
    document.mode,
    document.official_number,
    document.status,
    document.superseded_by_document_id,
    document.supersedes_document_id,
    case when document.calculation_snapshot_id is not null
      and app.has_permission(p_workspace_id, 'formula.read') then (
        select pg_catalog.to_jsonb(snapshot)
          - array['workspace_id', 'executed_by']::text[]
        from public.calculation_snapshots snapshot
        where snapshot.workspace_id = document.workspace_id
          and snapshot.id = document.calculation_snapshot_id
      ) else null end,
    document.document_date,
    coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', file.id,
        'role', file.role,
        'version', file.version,
        'filename', file.filename,
        'mime_type', file.mime_type,
        'byte_size', file.byte_size,
        'checksum_sha256', file.checksum,
        'current', file.current,
        'created_at', file.recorded_at
      ) order by file.recorded_at desc, file.id desc)
      from public.document_files file
      where file.workspace_id = document.workspace_id
        and file.document_id = document.id
        and (file.role <> 'signed_scan'
          or app.has_permission(p_workspace_id, 'files.read_restricted'))
    ), '[]'::jsonb),
    document.intended_signature_date,
    coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'job_id', job.id,
        'status', job.status,
        'attempt_count', job.attempts_started,
        'failure_code', job.last_error_code,
        'review_required', job.review_required,
        'updated_at', job.updated_at
      ) order by job.created_at desc, job.id desc)
      from public.jobs job
      where job.workspace_id = document.workspace_id
        and job.entity_type = 'document'
        and job.entity_id = document.id
        and job.job_type in ('documents.render_preview', 'documents.render_pdf')
    ), '[]'::jsonb),
    document.render_input_checksum,
    document.signed_at,
    case when document.tax_calculation_snapshot_id is not null
      and app.has_permission(p_workspace_id, 'tax.read') then (
        select pg_catalog.to_jsonb(snapshot)
          - array['workspace_id', 'executed_by']::text[]
        from public.tax_calculation_snapshots snapshot
        where snapshot.workspace_id = document.workspace_id
          and snapshot.id = document.tax_calculation_snapshot_id
      ) else null end,
    document.version_snapshot,
    document.version_snapshot_checksum,
    document.void_reason
  from public.documents document
  join public.document_types document_type
    on document_type.workspace_id = document.workspace_id
   and document_type.id = document.document_type_id
  left join lateral (
    select file.id, file.recorded_at
    from public.document_files file
    where file.workspace_id = document.workspace_id
      and file.document_id = document.id and file.current
      and (file.role <> 'signed_scan'
        or app.has_permission(document.workspace_id, 'files.read_restricted'))
    order by case file.role when 'signed_scan' then 0 else 1 end,
      file.version desc, file.id desc limit 1
  ) current_file on true
  left join lateral (
    select artifact.id, artifact.created_at
    from public.document_preview_artifacts artifact
    where artifact.workspace_id = document.workspace_id
      and artifact.document_id = document.id
    order by artifact.created_at desc, artifact.id desc
    limit 1
  ) preview_file on true
  left join lateral (
    select job.status from public.jobs job
    where job.workspace_id = document.workspace_id
      and job.entity_type = 'document' and job.entity_id = document.id
      and job.job_type in ('documents.render_preview', 'documents.render_pdf')
    order by job.created_at desc, job.id desc limit 1
  ) current_job on true
  where document.workspace_id = p_workspace_id and document.id = p_document_id;
end;
$$;

create function app.m4_list_numbering_definitions(p_workspace_id uuid)
returns table (
  active_version_id uuid,
  created_at timestamptz,
  id uuid,
  key text,
  labels jsonb,
  versions jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'numbering.read');
  return query
  select
    (
      select version.id from public.numbering_definition_versions version
      where version.workspace_id = definition.workspace_id
        and version.numbering_definition_id = definition.id
        and version.status = 'active'
      limit 1
    ),
    definition.created_at,
    definition.id,
    definition.key::text,
    definition.labels,
    coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', version.id,
        'version', version.version,
        'semantic_version', version.semantic_version,
        'status', version.status,
        'checksum', version.checksum,
        'approval_record_id', version.approval_record_id,
        'activated_at', version.activated_at
      ) order by version.version desc, version.id desc)
      from public.numbering_definition_versions version
      where version.workspace_id = definition.workspace_id
        and version.numbering_definition_id = definition.id
    ), '[]'::jsonb)
  from public.numbering_definitions definition
  where definition.workspace_id = p_workspace_id
  order by definition.key, definition.id;
end;
$$;

create function app.m4_list_approval_records(
  p_workspace_id uuid,
  p_artifact_key text default null,
  p_artifact_type text default null,
  p_current_only boolean default true,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  approval_type text,
  artifact_checksum text,
  artifact_id uuid,
  artifact_key text,
  artifact_type text,
  artifact_version bigint,
  attachment_reference text,
  conditions jsonb,
  decided_at timestamptz,
  decision text,
  expires_at timestamptz,
  id uuid,
  professional_organization text,
  professional_role text,
  review_due_at timestamptz,
  supersedes_approval_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'approvals.read');
  if p_limit not between 1 and 200
    or (p_cursor_created_at is null) <> (p_cursor_id is null) then
    raise exception using errcode = '22023', message = 'invalid approval list query';
  end if;
  return query
  select
    approval.approval_type,
    approval.artifact_checksum,
    approval.artifact_id,
    approval.artifact_key,
    approval.artifact_type,
    approval.artifact_version,
    approval.attachment_reference,
    approval.conditions,
    approval.decided_at,
    approval.decision,
    approval.expires_at,
    approval.id,
    approval.professional_organization,
    approval.professional_role,
    approval.review_due_at,
    approval.supersedes_approval_id
  from public.approval_records approval
  where approval.workspace_id = p_workspace_id
    and (p_artifact_key is null or approval.artifact_key = p_artifact_key)
    and (p_artifact_type is null or approval.artifact_type = p_artifact_type)
    and (not p_current_only or not exists (
      select 1 from public.approval_records later
      where later.workspace_id = approval.workspace_id
        and later.supersedes_approval_id = approval.id
    ))
    and (p_cursor_created_at is null
      or (approval.decided_at, approval.id) < (p_cursor_created_at, p_cursor_id))
  order by approval.decided_at desc, approval.id desc
  limit p_limit;
end;
$$;

create function app.m4_list_tax_packs(p_workspace_id uuid)
returns table (
  active_versions uuid[],
  id uuid,
  key text,
  labels jsonb,
  source_kind text,
  versions jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'tax.read');
  return query
  select
    coalesce((
      select pg_catalog.array_agg(version.id order by version.id)
      from public.tax_pack_versions version
      where version.workspace_id = pack.workspace_id
        and version.tax_pack_id = pack.id and version.status = 'active'
    ), array[]::uuid[]),
    pack.id,
    pack.key::text,
    pack.labels,
    pack.source_kind,
    coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', version.id,
        'version', version.version,
        'semantic_version', version.semantic_version,
        'status', version.status,
        'checksum', version.checksum,
        'jurisdiction_code', version.jurisdiction_code,
        'contexts', version.contexts,
        'currency_codes', version.currency_codes,
        'effective_from', version.effective_from,
        'effective_to', version.effective_to
      ) order by version.version desc, version.id desc)
      from public.tax_pack_versions version
      where version.workspace_id = pack.workspace_id
        and version.tax_pack_id = pack.id
    ), '[]'::jsonb)
  from public.tax_packs pack
  where pack.workspace_id = p_workspace_id
  order by pack.key, pack.id;
end;
$$;

-- Load the one server-authored deal projection that a runtime may bind to an
-- official receipt. Browser-supplied calculation and tax inputs remain valid
-- for unbound previews, but a deal-bound preview always executes this exact
-- projection and records both portable canonical checksums.
create function app.m4_load_deal_runtime_input(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_jurisdiction_code text
)
returns table (
  calculation_input jsonb,
  calculation_input_checksum text,
  deal_context_checksum text,
  deal_currency_code text,
  tax_input jsonb,
  tax_input_checksum text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  source_snapshot jsonb;
  source_checksum text;
  projected_tax_input jsonb;
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'deals.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'crm.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');

  source_snapshot := app.m4_deal_source_snapshot(p_workspace_id, p_deal_id);
  if source_snapshot is null
    or pg_catalog.jsonb_typeof(source_snapshot -> 'deal') is distinct from 'object'
    or coalesce(source_snapshot -> 'deal' ->> 'currency_code', '') !~ '^[A-Z]{3}$' then
    raise exception using
      errcode = '23514',
      message = 'runtime_evidence.deal_context_invalid';
  end if;
  source_checksum := app.m4_canonical_fingerprint(source_snapshot);

  if p_jurisdiction_code is not null then
    projected_tax_input := app.m4_deal_tax_input(
      source_snapshot,
      p_jurisdiction_code
    );
  end if;

  return query select
    source_snapshot,
    source_checksum,
    source_checksum,
    source_snapshot -> 'deal' ->> 'currency_code',
    projected_tax_input,
    case when projected_tax_input is null then null
      else app.m4_canonical_fingerprint(projected_tax_input)
    end;
end;
$$;

create function app.m4_load_tax_preview_configuration(
  p_workspace_id uuid,
  p_jurisdiction_code text,
  p_context_key text,
  p_currency_code text,
  p_transaction_date date,
  p_override_requested boolean
)
returns table (
  assignment_id uuid,
  tax_pack_version_id uuid,
  definition jsonb,
  definition_checksum text,
  engine_version text,
  override_authorized boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  selected record;
  matching_count integer;
  runtime_definition jsonb;
  override_allowed boolean := false;
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'tax.read');
  if p_jurisdiction_code !~ '^[A-Z]{2}(?:-[A-Z0-9]{1,3})?$'
    or p_context_key !~ '^[a-z][a-z0-9_]{0,127}$'
    or p_currency_code !~ '^[A-Z]{3}$'
    or p_transaction_date is null then
    raise exception using errcode = '22023', message = 'invalid tax preview selector';
  end if;
  if coalesce(p_override_requested, false) then
    perform app.require_vertical_slice_permission(p_workspace_id, 'tax.override', true);
    override_allowed := true;
  end if;

  with eligible as (
    select
      assignment.id as assignment_id,
      version.*,
      pack.key::text as pack_key,
      row_number() over (
        order by (assignment.id is not null) desc,
          case version.status when 'active' then 0 when 'approved' then 1
            when 'test_passed' then 2 when 'validated' then 3 else 4 end,
          version.version desc, version.id desc
      ) as selection_order,
      count(*) over () as matching_count
    from public.tax_pack_versions version
    join public.tax_packs pack
      on pack.workspace_id = version.workspace_id and pack.id = version.tax_pack_id
    left join public.tax_pack_assignments assignment
      on assignment.workspace_id = version.workspace_id
     and assignment.tax_pack_version_id = version.id
     and assignment.jurisdiction_code = p_jurisdiction_code
     and assignment.context_key = p_context_key
     and assignment.currency_code = p_currency_code
     and assignment.effective_from <= p_transaction_date
     and (coalesce(
       assignment.superseded_effective_to,
       assignment.effective_to
     ) is null or coalesce(
       assignment.superseded_effective_to,
       assignment.effective_to
     ) >= p_transaction_date)
    where version.workspace_id = p_workspace_id
      and version.jurisdiction_code = p_jurisdiction_code
      and p_context_key = any(version.contexts)
      and p_currency_code = any(version.currency_codes)
      and version.effective_from <= p_transaction_date
      and (version.effective_to is null or version.effective_to >= p_transaction_date)
      and (version.status <> 'retired' or assignment.id is not null)
      and (
        assignment.id is not null
        or not exists (
          select 1 from public.tax_pack_assignments active_assignment
          where active_assignment.workspace_id = p_workspace_id
            and active_assignment.jurisdiction_code = p_jurisdiction_code
            and active_assignment.context_key = p_context_key
            and active_assignment.currency_code = p_currency_code
            and active_assignment.effective_from <= p_transaction_date
            and (coalesce(
              active_assignment.superseded_effective_to,
              active_assignment.effective_to
            ) is null or coalesce(
              active_assignment.superseded_effective_to,
              active_assignment.effective_to
            ) >= p_transaction_date)
        )
      )
  )
  select eligible.* into selected from eligible
  where eligible.selection_order = 1;
  if not found then
    raise exception using errcode = 'P0002', message = 'tax.tax_pack_unavailable';
  end if;
  matching_count := selected.matching_count;
  if selected.assignment_id is null and matching_count <> 1 then
    raise exception using errcode = '23514', message = 'tax.ambiguous_tax_pack';
  end if;

  runtime_definition := pg_catalog.jsonb_build_object(
    'key', selected.pack_key,
    'version', selected.semantic_version,
    'jurisdiction', selected.jurisdiction_code,
    'contexts', selected.contexts,
    'effective_from', selected.effective_from,
    'effective_to', selected.effective_to,
    'sources', coalesce(selected.source_metadata -> 'sources', selected.source_metadata),
    'rules', selected.rules,
    'golden_tests', selected.golden_fixtures,
    'activation_status', selected.status,
    'approval_refs', case when selected.approval_record_id is null
      then '[]'::jsonb
      else pg_catalog.jsonb_build_array(selected.approval_record_id::text) end
  );
  if app.m4_canonical_fingerprint(
    runtime_definition - array['activation_status', 'approval_refs']::text[]
  ) <> selected.checksum then
    raise exception using
      errcode = 'XX001',
      message = 'tax.tax_pack_checksum_mismatch';
  end if;
  return query select
    selected.assignment_id,
    selected.id,
    runtime_definition,
    selected.checksum,
    selected.engine_version,
    override_allowed;
end;
$$;

create function app.m4_list_calculation_definitions(p_workspace_id uuid)
returns table (
  active_version_id uuid,
  id uuid,
  key text,
  labels jsonb,
  versions jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'formula.read');
  return query
  select
    (
      select version.id from public.calculation_versions version
      where version.workspace_id = definition.workspace_id
        and version.calculation_definition_id = definition.id
        and version.status = 'active' limit 1
    ),
    definition.id,
    definition.key::text,
    definition.labels,
    coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', version.id,
        'version', version.version,
        'semantic_version', version.semantic_version,
        'status', version.status,
        'checksum', version.checksum,
        'engine_version', version.engine_version
      ) order by version.version desc, version.id desc)
      from public.calculation_versions version
      where version.workspace_id = definition.workspace_id
        and version.calculation_definition_id = definition.id
    ), '[]'::jsonb)
  from public.calculation_definitions definition
  where definition.workspace_id = p_workspace_id
  order by definition.key, definition.id;
end;
$$;

create function app.m4_load_calculation_preview_configuration(
  p_workspace_id uuid,
  p_calculation_version_id uuid
)
returns table (
  calculation_version_id uuid,
  definition jsonb,
  definition_checksum text,
  engine_version text,
  resource_limits jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target_version public.calculation_versions%rowtype;
  definition_key text;
  runtime_definition jsonb;
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'formula.read');
  select version.* into target_version
  from public.calculation_versions version
  join public.calculation_definitions parent
    on parent.workspace_id = version.workspace_id
   and parent.id = version.calculation_definition_id
  where version.workspace_id = p_workspace_id
    and version.id = p_calculation_version_id
    and version.status <> 'retired';
  select parent.key::text into definition_key
  from public.calculation_definitions parent
  where parent.workspace_id = target_version.workspace_id
    and parent.id = target_version.calculation_definition_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'calculation.version_unavailable';
  end if;

  runtime_definition := pg_catalog.jsonb_build_object(
    'key', definition_key,
    'version', target_version.semantic_version,
    'status', target_version.status,
    'input_schema', target_version.input_schema,
    'outputs', target_version.expression_ast,
    'rounding', target_version.rounding_policy,
    'fixtures', target_version.fixtures,
    'approval_refs', case when target_version.approval_record_id is null
      then '[]'::jsonb
      else pg_catalog.jsonb_build_array(target_version.approval_record_id::text) end
  );
  if app.m4_canonical_fingerprint(
    runtime_definition - array['status', 'approval_refs']::text[]
  ) <> target_version.checksum then
    raise exception using
      errcode = 'XX001',
      message = 'calculation.definition_checksum_mismatch';
  end if;
  return query select
    target_version.id,
    runtime_definition,
    target_version.checksum,
    target_version.engine_version,
    target_version.resource_limits;
end;
$$;

create function app.m4_list_export_definitions(p_workspace_id uuid)
returns table (
  active_version_id uuid,
  columns jsonb,
  filter_schema jsonb,
  formats text[],
  id uuid,
  key text,
  labels jsonb,
  maximum_rows integer,
  permission_key text,
  sensitivity text,
  step_up_required boolean,
  version_checksum text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'exports.read');
  return query
  select
    version.id,
    version.columns,
    version.filter_schema,
    version.formats,
    definition.id,
    definition.key::text,
    definition.labels,
    version.maximum_rows,
    version.permission_key,
    version.sensitivity,
    version.step_up_required,
    version.checksum
  from public.export_definitions definition
  join public.export_versions version
    on version.workspace_id = definition.workspace_id
   and version.export_definition_id = definition.id
   and version.status = 'active'
  where definition.workspace_id = p_workspace_id
    and app.has_permission(p_workspace_id, version.permission_key)
  order by definition.key, definition.id;
end;
$$;

create function app.m4_get_export_run(
  p_workspace_id uuid,
  p_export_run_id uuid
)
returns table (
  created_at timestamptz,
  expires_at timestamptz,
  export_definition_key text,
  export_file_id uuid,
  export_run_id uuid,
  export_version_id uuid,
  failure_code text,
  generated_checksum text,
  job_id uuid,
  locale text,
  outbox_event_id uuid,
  replayed boolean,
  requested_format text,
  row_count bigint,
  status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'exports.read');
  return query
  select
    run.created_at,
    run.expires_at,
    definition.key::text,
    file.id,
    run.id,
    run.export_version_id,
    run.failure_code,
    run.generated_checksum,
    mapping.job_id,
    run.locale,
    mapping.outbox_event_id,
    false,
    run.requested_format,
    run.row_count,
    run.status
  from public.export_runs run
  join public.export_definitions definition
    on definition.workspace_id = run.workspace_id
   and definition.id = run.export_definition_id
  left join public.export_run_jobs mapping
    on mapping.workspace_id = run.workspace_id and mapping.export_run_id = run.id
  left join public.export_files file
    on file.workspace_id = run.workspace_id and file.export_run_id = run.id
   and file.current
  where run.workspace_id = p_workspace_id and run.id = p_export_run_id
    and (run.requested_by = auth.uid()
      or app.has_permission(p_workspace_id, 'exports.run_sensitive'));
end;
$$;

create function app.m4_validate_report_query(
  p_cursor_created_at timestamptz,
  p_cursor_id uuid,
  p_date_from date,
  p_date_to date,
  p_limit integer
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if (p_cursor_created_at is null) <> (p_cursor_id is null)
    or p_date_from is not null and p_date_to is not null and p_date_from > p_date_to
    or p_limit is null or p_limit not between 1 and 200 then
    raise exception using errcode = '22023', message = 'report.query_invalid';
  end if;
end;
$$;

create function app.m4_report_inventory_aging(
  p_workspace_id uuid,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 50,
  p_location_id uuid default null
)
returns table (
  acquired_on date,
  age_days integer,
  cost_amount_minor text,
  created_at timestamptz,
  currency_code text,
  inventory_unit_id uuid,
  location_id uuid,
  make text,
  model text,
  model_year integer,
  stock_number text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'reports.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'costs.read');
  perform app.m4_validate_report_query(
    p_cursor_created_at, p_cursor_id, p_date_from, p_date_to, p_limit
  );
  return query
  select
    acquired.value,
    greatest(current_date - acquired.value, 0),
    coalesce(cost.posted_cost_minor, 0)::text,
    inventory.created_at,
    inventory.currency_code::text,
    inventory.id,
    inventory.location_id,
    vehicle.make,
    vehicle.model,
    vehicle.model_year::integer,
    inventory.stock_number::text
  from public.inventory_units inventory
  join public.vehicles vehicle
    on vehicle.workspace_id = inventory.workspace_id
   and vehicle.id = inventory.vehicle_id
  cross join lateral (
    select coalesce(
      inventory.acquisition_date,
      inventory.acquired_at::date,
      inventory.created_at::date
    ) as value
  ) acquired
  left join public.inventory_cost_metrics cost
    on cost.workspace_id = inventory.workspace_id
   and cost.inventory_unit_id = inventory.id
  where inventory.workspace_id = p_workspace_id
    and inventory.status in ('draft', 'active', 'pending')
    and inventory.location_id is not null
    and vehicle.make is not null
    and vehicle.model is not null
    and vehicle.model_year is not null
    and (p_location_id is null or inventory.location_id = p_location_id)
    and (p_date_from is null or acquired.value >= p_date_from)
    and (p_date_to is null or acquired.value <= p_date_to)
    and (p_cursor_created_at is null
      or (inventory.created_at, inventory.id) < (p_cursor_created_at, p_cursor_id))
  order by inventory.created_at desc, inventory.id desc
  limit p_limit;
end;
$$;

create function app.m4_report_inventory_gross(
  p_workspace_id uuid,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 50,
  p_location_id uuid default null
)
returns table (
  closed_at timestamptz,
  cost_amount_minor text,
  currency_code text,
  deal_id uuid,
  gross_amount_minor text,
  inventory_unit_id uuid,
  revenue_amount_minor text,
  stock_number text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'reports.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'deals.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'costs.read');
  perform app.m4_validate_report_query(
    p_cursor_created_at, p_cursor_id, p_date_from, p_date_to, p_limit
  );
  if exists (
    select 1
    from public.deals candidate
    join public.deal_inventory_units candidate_link
      on candidate_link.workspace_id = candidate.workspace_id
     and candidate_link.deal_id = candidate.id
     and candidate_link.role_key = 'sold'
     and candidate_link.status = 'active'
    join public.inventory_units candidate_inventory
      on candidate_inventory.workspace_id = candidate_link.workspace_id
     and candidate_inventory.id = candidate_link.inventory_unit_id
    where candidate.workspace_id = p_workspace_id
      and candidate.lifecycle_status = 'completed'
      and candidate.completed_at is not null
      and (p_location_id is null
        or candidate_inventory.location_id = p_location_id)
      and (p_date_from is null
        or candidate.completed_at::date >= p_date_from)
      and (p_date_to is null
        or candidate.completed_at::date <= p_date_to)
    group by candidate.id
    having pg_catalog.count(*) > 1
  ) then
    raise exception using
      errcode = '23514',
      message = 'report.inventory_gross_multi_unit_attribution_required';
  end if;
  return query
  select
    deal.completed_at,
    coalesce(cost.posted_cost_minor, 0)::text,
    deal.currency_code::text,
    deal.id,
    (revenue.amount_minor - coalesce(cost.posted_cost_minor, 0)::numeric)::text,
    inventory.id,
    revenue.amount_minor::text,
    inventory.stock_number::text
  from public.deals deal
  join public.deal_inventory_units link
    on link.workspace_id = deal.workspace_id
   and link.deal_id = deal.id
   and link.role_key = 'sold'
   and link.status = 'active'
  join public.inventory_units inventory
    on inventory.workspace_id = link.workspace_id
   and inventory.id = link.inventory_unit_id
  cross join lateral (
    select coalesce(
      pg_catalog.sum(pg_catalog.round(
        item.unit_amount_minor::numeric * item.quantity
      )),
      0::numeric
    ) as amount_minor
    from public.deal_line_items item
    where item.workspace_id = deal.workspace_id
      and item.deal_id = deal.id
      and item.status = 'active'
  ) revenue
  left join public.inventory_cost_metrics cost
    on cost.workspace_id = inventory.workspace_id
   and cost.inventory_unit_id = inventory.id
  where deal.workspace_id = p_workspace_id
    and deal.lifecycle_status = 'completed'
    and deal.completed_at is not null
    and (p_location_id is null or inventory.location_id = p_location_id)
    and (p_date_from is null or deal.completed_at::date >= p_date_from)
    and (p_date_to is null or deal.completed_at::date <= p_date_to)
    and (p_cursor_created_at is null
      or (deal.completed_at, deal.id) < (p_cursor_created_at, p_cursor_id))
  order by deal.completed_at desc, deal.id desc
  limit p_limit;
end;
$$;

create function app.m4_report_leads(
  p_workspace_id uuid,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 50,
  p_location_id uuid default null
)
returns table (
  converted_deal_id uuid,
  created_at timestamptz,
  id uuid,
  last_activity_at timestamptz,
  owner_membership_id uuid,
  source_key text,
  status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'reports.read');
  perform app.m4_validate_report_query(
    p_cursor_created_at, p_cursor_id, p_date_from, p_date_to, p_limit
  );
  return query
  select
    lead.converted_deal_id,
    lead.created_at,
    lead.id,
    activity.last_activity_at,
    lead.assignee_membership_id,
    lead.source_key,
    lead.state_key
  from public.leads lead
  left join lateral (
    select pg_catalog.max(event.occurred_at) as last_activity_at
    from public.crm_activities event
    where event.workspace_id = lead.workspace_id and event.lead_id = lead.id
  ) activity on true
  left join public.inventory_units inventory
    on inventory.workspace_id = lead.workspace_id
   and inventory.id = lead.interested_inventory_unit_id
  where lead.workspace_id = p_workspace_id
    and (p_location_id is null or inventory.location_id = p_location_id)
    and (p_date_from is null or lead.created_at::date >= p_date_from)
    and (p_date_to is null or lead.created_at::date <= p_date_to)
    and (p_cursor_created_at is null
      or (lead.created_at, lead.id) < (p_cursor_created_at, p_cursor_id))
  order by lead.created_at desc, lead.id desc
  limit p_limit;
end;
$$;

create function app.m4_report_deals(
  p_workspace_id uuid,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 50,
  p_location_id uuid default null
)
returns table (
  created_at timestamptz,
  currency_code text,
  deal_type_key text,
  id uuid,
  owner_membership_id uuid,
  status text,
  total_amount_minor text,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'reports.read');
  perform app.m4_validate_report_query(
    p_cursor_created_at, p_cursor_id, p_date_from, p_date_to, p_limit
  );
  return query
  select
    deal.created_at,
    deal.currency_code::text,
    deal.deal_type_key,
    deal.id,
    deal.owner_membership_id,
    deal.status,
    totals.amount_minor::text,
    deal.updated_at
  from public.deals deal
  cross join lateral (
    select coalesce(
      pg_catalog.sum(pg_catalog.round(
        item.unit_amount_minor::numeric * item.quantity
      )),
      0::numeric
    ) as amount_minor
    from public.deal_line_items item
    where item.workspace_id = deal.workspace_id
      and item.deal_id = deal.id
      and item.status = 'active'
  ) totals
  where deal.workspace_id = p_workspace_id
    and (p_location_id is null or deal.location_id = p_location_id)
    and (p_date_from is null or deal.created_at::date >= p_date_from)
    and (p_date_to is null or deal.created_at::date <= p_date_to)
    and (p_cursor_created_at is null
      or (deal.created_at, deal.id) < (p_cursor_created_at, p_cursor_id))
  order by deal.created_at desc, deal.id desc
  limit p_limit;
end;
$$;

revoke all on function app.m4_sync_domain_job_status()
from public, anon, authenticated, service_role;
revoke all on function app.m4_validate_report_query(
  timestamptz, uuid, date, date, integer
) from public, anon, authenticated, service_role;
revoke all on function app.m4_list_document_types(uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_validate_document(
  uuid, uuid, uuid, uuid, text, date, date, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
revoke all on function app.m4_request_document_preview(
  uuid, text, uuid, uuid, uuid, text, date, date, jsonb, jsonb, jsonb,
  text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_list_documents(
  uuid, timestamptz, uuid, uuid, text, integer, text, text
) from public, anon, authenticated, service_role;
revoke all on function app.m4_get_document_detail(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_list_numbering_definitions(uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_list_approval_records(
  uuid, text, text, boolean, timestamptz, uuid, integer
) from public, anon, authenticated, service_role;
revoke all on function app.m4_list_tax_packs(uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_load_deal_runtime_input(uuid, uuid, text)
from public, anon, authenticated, service_role;
revoke all on function app.m4_load_tax_preview_configuration(
  uuid, text, text, text, date, boolean
) from public, anon, authenticated, service_role;
revoke all on function app.m4_list_calculation_definitions(uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_load_calculation_preview_configuration(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_list_export_definitions(uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_get_export_run(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_report_inventory_aging(
  uuid, timestamptz, uuid, date, date, integer, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_report_inventory_gross(
  uuid, timestamptz, uuid, date, date, integer, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_report_leads(
  uuid, timestamptz, uuid, date, date, integer, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_report_deals(
  uuid, timestamptz, uuid, date, date, integer, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.m4_list_document_types(uuid) to authenticated;
grant execute on function app.m4_validate_document(
  uuid, uuid, uuid, uuid, text, date, date, jsonb, jsonb, jsonb
) to authenticated;
grant execute on function app.m4_request_document_preview(
  uuid, text, uuid, uuid, uuid, text, date, date, jsonb, jsonb, jsonb,
  text, uuid
) to authenticated;
grant execute on function app.m4_list_documents(
  uuid, timestamptz, uuid, uuid, text, integer, text, text
) to authenticated;
grant execute on function app.m4_get_document_detail(uuid, uuid) to authenticated;
grant execute on function app.m4_list_numbering_definitions(uuid) to authenticated;
grant execute on function app.m4_list_approval_records(
  uuid, text, text, boolean, timestamptz, uuid, integer
) to authenticated;
grant execute on function app.m4_list_tax_packs(uuid) to authenticated;
grant execute on function app.m4_load_deal_runtime_input(uuid, uuid, text)
to authenticated;
grant execute on function app.m4_load_tax_preview_configuration(
  uuid, text, text, text, date, boolean
) to authenticated;
grant execute on function app.m4_list_calculation_definitions(uuid) to authenticated;
grant execute on function app.m4_load_calculation_preview_configuration(uuid, uuid)
to authenticated;
grant execute on function app.m4_list_export_definitions(uuid) to authenticated;
grant execute on function app.m4_get_export_run(uuid, uuid) to authenticated;
grant execute on function app.m4_report_inventory_aging(
  uuid, timestamptz, uuid, date, date, integer, uuid
) to authenticated;
grant execute on function app.m4_report_inventory_gross(
  uuid, timestamptz, uuid, date, date, integer, uuid
) to authenticated;
grant execute on function app.m4_report_leads(
  uuid, timestamptz, uuid, date, date, integer, uuid
) to authenticated;
grant execute on function app.m4_report_deals(
  uuid, timestamptz, uuid, date, date, integer, uuid
) to authenticated;

comment on function app.m4_request_document_preview(
  uuid, text, uuid, uuid, uuid, text, date, date, jsonb, jsonb, jsonb,
  text, uuid
) is 'Creates one watermarked, unnumbered, immutable preview snapshot and durable render job.';
comment on function app.m4_report_inventory_gross(
  uuid, timestamptz, uuid, date, date, integer, uuid
) is 'Returns exact-minor-unit inventory gross rows within the authenticated workspace boundary.';
