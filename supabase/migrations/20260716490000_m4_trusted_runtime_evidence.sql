-- VYN-CALC-001, VYN-TAX-001, VYN-SEC-001, VYN-AUD-001
-- M4-CALC-AC-004 and M4-TAX-AC-002.
-- Runtime evidence is evaluated by the trusted application domain runtime,
-- recorded through a service-only boundary, and then consumed by official
-- document generation as an immutable actor/workspace/version-bound receipt.

alter table public.runtime_evidence_records
  add column official_eligible boolean not null default false,
  add constraint runtime_evidence_records_official_eligibility_check check (
    not official_eligible
    or deal_id is not null and (
      evidence_type = 'calculation' and calculation_version_id is not null
      or evidence_type = 'tax'
        and tax_pack_version_id is not null
        and tax_assignment_id is not null
    )
  );

comment on column public.runtime_evidence_records.official_eligible is
  'Immutable recording-time provenance. Candidate or unbound previews remain permanently ineligible even if their version is activated later.';

create function app.m4_tax_override_evidence_valid(p_evidence jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when pg_catalog.jsonb_typeof(p_evidence) is distinct from 'object' then false
    when not (p_evidence ? 'override') then not (p_evidence ? 'overrideReason')
    else coalesce(
      p_evidence ? 'overrideReason'
      and pg_catalog.jsonb_typeof(p_evidence -> 'override') = 'object'
      and pg_catalog.jsonb_typeof(p_evidence -> 'overrideReason') = 'string'
      and (
        select pg_catalog.count(*)
        from pg_catalog.jsonb_object_keys(p_evidence -> 'override') key
      ) = 6
      and p_evidence -> 'override' ->> 'kind' = 'trade_in_eligibility'
      and p_evidence -> 'override' ->> 'permissionKey' = 'tax.override'
      and p_evidence -> 'override' -> 'permissionGranted' = 'true'::jsonb
      and p_evidence -> 'override' -> 'recentStrongAuth' = 'true'::jsonb
      and pg_catalog.jsonb_typeof(
        p_evidence -> 'override' -> 'reviewReference'
      ) = 'string'
      and p_evidence -> 'override' ->> 'reviewReference'
        = pg_catalog.btrim(p_evidence -> 'override' ->> 'reviewReference')
      and pg_catalog.char_length(
        p_evidence -> 'override' ->> 'reviewReference'
      ) between 3 and 200
      and pg_catalog.jsonb_typeof(p_evidence -> 'override' -> 'reason') = 'string'
      and p_evidence -> 'override' ->> 'reason'
        = pg_catalog.btrim(p_evidence -> 'override' ->> 'reason')
      and pg_catalog.char_length(
        p_evidence -> 'override' ->> 'reason'
      ) between 3 and 2000
      and p_evidence -> 'override' ->> 'reason'
        = p_evidence ->> 'overrideReason'
    , false)
  end;
$$;

create function app.m4_actor_has_permission(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspace_memberships membership
    join public.membership_roles membership_role
      on membership_role.workspace_id = membership.workspace_id
     and membership_role.membership_id = membership.id
     and membership_role.status = 'active'
    join public.roles role
      on role.workspace_id = membership_role.workspace_id
     and role.id = membership_role.role_id
     and role.status = 'active'
    join public.role_permissions role_permission
      on role_permission.workspace_id = role.workspace_id
     and role_permission.role_id = role.id
     and role_permission.status = 'active'
    join public.permissions permission
      on permission.id = role_permission.permission_id
     and permission.status = 'active'
    where membership.workspace_id = p_workspace_id
      and membership.user_id = p_actor_user_id
      and membership.status = 'active'
      and permission.key = p_permission_key
      and (permission.workspace_id is null
        or permission.workspace_id = p_workspace_id)
  );
$$;

create function app.m4_record_runtime_evidence(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_kind text,
  p_version_id uuid,
  p_assignment_id uuid,
  p_deal_id uuid,
  p_evidence jsonb,
  p_idempotency_key text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (evidence_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_idempotency text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  evidence_checksum text;
  fingerprint text;
  existing public.runtime_evidence_records%rowtype;
  calculation_version public.calculation_versions%rowtype;
  calculation_key text;
  tax_version public.tax_pack_versions%rowtype;
  tax_key text;
  tax_assignment public.tax_pack_assignments%rowtype;
  deal_context jsonb;
  deal_context_checksum text;
  deal_currency_code text;
  expected_input jsonb;
  expected_input_checksum text;
  official_evidence_eligible boolean := false;
  new_evidence_id uuid := pg_catalog.gen_random_uuid();
begin
  if p_kind not in ('calculation', 'tax')
    or p_actor_user_id is null
    or p_version_id is null
    or pg_catalog.jsonb_typeof(p_evidence) is distinct from 'object'
    or app.job_payload_contains_forbidden_key(p_evidence)
    or pg_catalog.octet_length(p_evidence::text) > 524288
    or pg_catalog.char_length(normalized_idempotency) not between 8 and 200
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'runtime_evidence.command_invalid';
  end if;

  if p_deal_id is not null then
    if not app.m4_actor_has_permission(
      p_workspace_id, p_actor_user_id, 'deals.read'
    ) then
      raise exception using errcode = '42501', message = 'runtime_evidence.permission_denied';
    end if;
    deal_context := app.m4_deal_source_snapshot(p_workspace_id, p_deal_id);
    if deal_context is null then
      raise exception using errcode = '23514', message = 'runtime_evidence.deal_context_invalid';
    end if;
    deal_context_checksum := app.m4_canonical_fingerprint(deal_context);
    deal_currency_code := deal_context -> 'deal' ->> 'currency_code';
    if coalesce(deal_currency_code, '') !~ '^[A-Z]{3}$' then
      raise exception using errcode = '23514', message = 'runtime_evidence.deal_context_invalid';
    end if;
  elsif p_evidence ? 'inputBinding' then
    -- Arbitrary preview inputs are allowed only as explicitly unbound evidence.
    -- A client cannot manufacture an official-looking binding without a deal.
    raise exception using errcode = '23514', message = 'runtime_evidence.input_binding_invalid';
  end if;
  evidence_checksum := p_evidence ->> 'checksum';
  if coalesce(evidence_checksum, '') !~ '^[a-f0-9]{64}$'
    or app.m4_canonical_fingerprint(p_evidence - 'checksum') is distinct from evidence_checksum then
    raise exception using errcode = '23514', message = 'runtime_evidence.checksum_invalid';
  end if;

  if p_kind = 'calculation' then
    if not app.m4_actor_has_permission(
      p_workspace_id, p_actor_user_id, 'formula.read'
    ) then
      raise exception using errcode = '42501', message = 'runtime_evidence.permission_denied';
    end if;
    select version.*
      into calculation_version
    from public.calculation_versions version
    join public.calculation_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.calculation_definition_id
    where version.workspace_id = p_workspace_id
      and version.id = p_version_id
      and version.status in (
        'draft', 'validated', 'test_passed', 'approved', 'active'
      );
    select definition.key::text into calculation_key
    from public.calculation_definitions definition
    where definition.workspace_id = calculation_version.workspace_id
      and definition.id = calculation_version.calculation_definition_id;
    if not found
      or p_assignment_id is not null
      or p_evidence ->> 'versionId' is distinct from calculation_version.id::text
      or p_evidence ->> 'definitionKey' is distinct from calculation_key
      or p_evidence ->> 'definitionVersion' is distinct from calculation_version.semantic_version
      or p_evidence ->> 'definitionChecksum' is distinct from calculation_version.checksum
      or p_evidence ->> 'engineVersion' is distinct from calculation_version.engine_version
      or pg_catalog.jsonb_typeof(p_evidence -> 'definition') is distinct from 'object'
      or pg_catalog.jsonb_typeof(p_evidence -> 'input') is distinct from 'object'
      or pg_catalog.jsonb_typeof(p_evidence -> 'output') is distinct from 'object'
      or pg_catalog.jsonb_typeof(p_evidence -> 'components') is distinct from 'array'
      or pg_catalog.jsonb_typeof(p_evidence -> 'taxComponents') is distinct from 'array'
      or pg_catalog.jsonb_typeof(p_evidence -> 'rounding') is distinct from 'object'
      or app.m4_canonical_fingerprint(
        (p_evidence -> 'definition') - array['status', 'approval_refs']::text[]
      ) is distinct from calculation_version.checksum then
      raise exception using errcode = '23514', message = 'runtime_evidence.calculation_invalid';
    end if;
    official_evidence_eligible := calculation_version.status = 'active'
      and p_deal_id is not null;
    if p_deal_id is not null then
      expected_input := deal_context;
      expected_input_checksum := app.m4_canonical_fingerprint(expected_input);
      if p_evidence -> 'input' is distinct from expected_input
        or p_evidence -> 'inputBinding' is distinct from
          pg_catalog.jsonb_build_object(
            'mapperVersion', 'deal-runtime-input-v1',
            'dealContextChecksum', deal_context_checksum,
            'inputProjectionChecksum', expected_input_checksum
          ) then
        raise exception using errcode = '23514', message = 'runtime_evidence.calculation_input_binding_invalid';
      end if;
    end if;
  else
    if not app.m4_tax_override_evidence_valid(p_evidence) then
      raise exception using
        errcode = '23514',
        message = 'runtime_evidence.tax_override_invalid';
    end if;
    if not app.m4_actor_has_permission(
      p_workspace_id, p_actor_user_id, 'tax.read'
    ) or p_evidence ? 'override' and not app.m4_actor_has_permission(
      p_workspace_id, p_actor_user_id, 'tax.override'
    ) then
      raise exception using errcode = '42501', message = 'runtime_evidence.permission_denied';
    end if;
    select version.* into tax_version
    from public.tax_pack_versions version
    join public.tax_packs pack
      on pack.workspace_id = version.workspace_id and pack.id = version.tax_pack_id
    where version.workspace_id = p_workspace_id
      and version.id = p_version_id
      and (
        version.status = 'active'
        or version.status = 'retired' and p_assignment_id is not null
        or version.status in ('draft', 'validated', 'test_passed', 'approved')
          and p_assignment_id is null
      );
    select pack.key::text into tax_key
    from public.tax_packs pack
    where pack.workspace_id = tax_version.workspace_id
      and pack.id = tax_version.tax_pack_id;
    if not found
      or p_evidence ->> 'versionId' is distinct from tax_version.id::text
      or p_evidence ->> 'packKey' is distinct from tax_key
      or p_evidence ->> 'packVersion' is distinct from tax_version.semantic_version
      or p_evidence ->> 'packChecksum' is distinct from tax_version.checksum
      or p_evidence ->> 'engineVersion' is distinct from tax_version.engine_version
      or (p_evidence ->> 'assignmentId') is distinct from p_assignment_id::text
      or pg_catalog.jsonb_typeof(p_evidence -> 'pack') is distinct from 'object'
      or pg_catalog.jsonb_typeof(p_evidence -> 'pack' -> 'sources') is distinct from 'array'
      or pg_catalog.jsonb_typeof(p_evidence -> 'input') is distinct from 'object'
      or pg_catalog.jsonb_typeof(p_evidence -> 'output') is distinct from 'object'
      or app.m4_canonical_fingerprint(
        (p_evidence -> 'pack') - array['activation_status', 'approval_refs']::text[]
      ) is distinct from tax_version.checksum then
      raise exception using errcode = '23514', message = 'runtime_evidence.tax_invalid';
    end if;
    if p_deal_id is not null then
      if p_evidence ->> 'currency' is distinct from deal_currency_code then
        raise exception using errcode = '23514', message = 'runtime_evidence.tax_input_binding_invalid';
      end if;
      begin
        expected_input := app.m4_deal_tax_input(
          deal_context,
          p_evidence ->> 'jurisdiction'
        );
      exception when check_violation then
        raise exception using errcode = '23514', message = 'runtime_evidence.tax_input_binding_invalid';
      end;
      expected_input_checksum := app.m4_canonical_fingerprint(expected_input);
      if p_evidence -> 'input' is distinct from expected_input
        or p_evidence -> 'inputBinding' is distinct from
          pg_catalog.jsonb_build_object(
            'mapperVersion', 'deal-runtime-input-v1',
            'dealContextChecksum', deal_context_checksum,
            'inputProjectionChecksum', expected_input_checksum
          ) then
        raise exception using errcode = '23514', message = 'runtime_evidence.tax_input_binding_invalid';
      end if;
    end if;
    if p_assignment_id is not null then
      select assignment.* into tax_assignment
      from public.tax_pack_assignments assignment
      where assignment.workspace_id = p_workspace_id
        and assignment.id = p_assignment_id
        and assignment.tax_pack_version_id = tax_version.id
        and assignment.jurisdiction_code = p_evidence ->> 'jurisdiction'
        and assignment.context_key = p_evidence ->> 'context'
        and assignment.currency_code = p_evidence ->> 'currency'
        and assignment.effective_from <= (p_evidence ->> 'transactionDate')::date
        and (coalesce(
          assignment.superseded_effective_to,
          assignment.effective_to
        ) is null or coalesce(
          assignment.superseded_effective_to,
          assignment.effective_to
        ) >= (p_evidence ->> 'transactionDate')::date);
      if not found then
        raise exception using errcode = '23514', message = 'runtime_evidence.tax_assignment_invalid';
      end if;
      official_evidence_eligible := tax_version.status = 'active'
        and p_deal_id is not null;
    end if;
  end if;

  fingerprint := app.m4_canonical_fingerprint(pg_catalog.jsonb_build_object(
    'kind', p_kind,
    'versionId', p_version_id,
    'assignmentId', p_assignment_id,
    'dealId', p_deal_id,
    'dealContextChecksum', deal_context_checksum,
    'evidence', p_evidence
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fruntime_evidence\x1f'
      || p_actor_user_id::text || E'\x1f' || p_kind || E'\x1f'
      || normalized_idempotency,
    0
  ));
  select evidence.* into existing
  from public.runtime_evidence_records evidence
  where evidence.workspace_id = p_workspace_id
    and evidence.actor_user_id = p_actor_user_id
    and evidence.evidence_type = p_kind
    and evidence.idempotency_key = normalized_idempotency;
  if found then
    if existing.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'runtime_evidence.idempotency_conflict';
    end if;
    return query select existing.id;
    return;
  end if;

  insert into public.runtime_evidence_records (
    id, workspace_id, evidence_type, calculation_version_id,
    tax_pack_version_id, tax_assignment_id, deal_id, deal_context_checksum,
    snapshot, snapshot_checksum,
    actor_user_id, idempotency_key, command_fingerprint, expires_at,
    official_eligible
  ) values (
    new_evidence_id, p_workspace_id, p_kind,
    case when p_kind = 'calculation' then p_version_id else null end,
    case when p_kind = 'tax' then p_version_id else null end,
    p_assignment_id, p_deal_id, deal_context_checksum,
    p_evidence, evidence_checksum, p_actor_user_id,
    normalized_idempotency, fingerprint,
    pg_catalog.statement_timestamp() + interval '24 hours',
    official_evidence_eligible
  );
  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'runtime_evidence.recorded',
    p_entity_type => 'runtime_evidence',
    p_entity_id => new_evidence_id,
    p_actor_user_id => p_actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'kind', p_kind,
      'versionId', p_version_id,
      'assignmentId', p_assignment_id,
      'dealId', p_deal_id,
      'dealContextChecksum', deal_context_checksum,
      'checksum', evidence_checksum,
      'expiresInSeconds', 86400,
      'officialEligible', official_evidence_eligible
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'server_verified',
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotencyKey', normalized_idempotency,
      'serviceRecorded', true,
      'officialEligible', official_evidence_eligible
    )
  );
  return query select new_evidence_id;
exception
  when invalid_text_representation then
    raise exception using errcode = '23514', message = 'runtime_evidence.typed_value_invalid';
end;
$$;

revoke all on function app.m4_actor_has_permission(uuid, uuid, text)
from public, anon, authenticated, service_role;
revoke all on function app.m4_tax_override_evidence_valid(jsonb)
from public, anon, authenticated, service_role;
revoke all on function app.m4_record_runtime_evidence(
  uuid, uuid, text, uuid, uuid, uuid, jsonb, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.m4_record_runtime_evidence(
  uuid, uuid, text, uuid, uuid, uuid, jsonb, text, text, uuid
) to service_role;

comment on table public.runtime_evidence_records is
  'Append-only service-recorded calculation or tax execution evidence; official documents consume receipts, never client-asserted outputs.';
