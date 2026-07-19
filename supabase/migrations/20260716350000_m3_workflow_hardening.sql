-- VYN-WF-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- M3-WF-AC-001 through M3-WF-AC-004
-- T-WF-001 through T-WF-004
-- Workflow definitions remain tenant-neutral configuration. This migration adds
-- the approval, snapshot, RLS, and command controls needed by later lead/deal
-- adapters without implementing those aggregates or any provider side effect.

create function app.workflow_required_fields_valid(candidate text[])
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.cardinality(candidate) <= 100
    and pg_catalog.cardinality(candidate) = (
      select pg_catalog.count(distinct field.value)
      from pg_catalog.unnest(candidate) field(value)
    )
    and not exists (
      select 1
      from pg_catalog.unnest(candidate) field(value)
      where field.value is null
        or field.value !~ '^[a-z][a-z0-9_.-]{0,127}$'
        or pg_catalog.string_to_array(field.value, '.')
          && array['__proto__', 'constructor', 'prototype']::text[]
    );
$$;

create function app.workflow_guard_allowed_for_entity(
  p_entity_type text,
  p_guard_key text
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_guard_key is null then true
    when p_guard_key = 'required_fields_complete' then true
    when p_entity_type = 'inventory_unit'
      then p_guard_key = 'sale_completion_requirements_met'
    when p_entity_type = 'lead'
      then p_guard_key = 'lead_conversion_requirements_met'
    when p_entity_type = 'deal'
      then p_guard_key in (
        'lender_approval_recorded',
        'required_documents_generated',
        'completion_requirements_met'
      )
    else false
  end;
$$;

create function app.workflow_effect_allowed_for_entity(
  p_entity_type text,
  p_effect_key text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select case p_entity_type
    when 'inventory_unit' then p_effect_key in (
      'listing.publish',
      'listing.unpublish',
      'listing.refresh',
      'media.retention_review'
    )
    when 'lead' then p_effect_key in (
      'lead.follow_up_review',
      'lead.conversion_review'
    )
    when 'deal' then p_effect_key in (
      'deal.document_readiness_review',
      'deal.inventory_release_review'
    )
    else false
  end;
$$;

-- M3-WF-AC-001: SQL and TypeScript share dotted definition keys with a
-- 128-character total limit. State, transition, entity, and purpose keys stay
-- simple immutable identifiers.
alter table public.workflow_definitions
  drop constraint workflow_definitions_key_check;
alter table public.workflow_definitions
  add constraint workflow_definitions_key_check check (
    pg_catalog.char_length(key::text) <= 128
    and key::text ~ '^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})*$'
  );

alter table public.workflow_versions
  add column revision bigint;

with ranked_versions as (
  select
    version.id,
    pg_catalog.row_number() over (
      partition by version.workspace_id, version.workflow_definition_id
      order by version.created_at, version.id
    ) as revision
  from public.workflow_versions version
)
update public.workflow_versions version
set revision = ranked.revision
from ranked_versions ranked
where ranked.id = version.id;

alter table public.workflow_versions
  alter column revision set not null,
  add constraint workflow_versions_revision_check check (revision > 0),
  add constraint workflow_versions_definition_revision_key
    unique (workspace_id, workflow_definition_id, revision),
  add column approval_record_id uuid,
  add column approved_by uuid references auth.users (id) on delete restrict,
  add column approved_at timestamptz,
  add constraint workflow_versions_approval_metadata_check check (
    (approval_record_id is null and approved_by is null and approved_at is null)
    or
    (approval_record_id is not null and approved_by is not null and approved_at is not null)
  ),
  add constraint workflow_versions_approval_record_fk
    foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id)
    on delete restrict;

-- M3-WF-AC-003: required fields are persisted on both states and transitions.
alter table public.workflow_states
  add column required_fields text[] not null default '{}'::text[],
  add constraint workflow_states_required_fields_check
    check (app.workflow_required_fields_valid(required_fields));

alter table public.workflow_transitions
  add column required_fields text[] not null default '{}'::text[],
  add constraint workflow_transitions_required_fields_check
    check (app.workflow_required_fields_valid(required_fields));

alter table public.workflow_transitions
  drop constraint workflow_transitions_guard_key_check;
alter table public.workflow_transitions
  add constraint workflow_transitions_guard_key_check check (
    guard_key is null or guard_key in (
      'required_fields_complete',
      'sale_completion_requirements_met',
      'lead_conversion_requirements_met',
      'lender_approval_recorded',
      'required_documents_generated',
      'completion_requirements_met'
    )
  );

-- M3-WF-AC-004: event snapshots are append-only decision metadata. Triggered
-- population below deliberately excludes entity values and customer data.
alter table public.workflow_events
  add column input_snapshot jsonb not null default '{}'::jsonb,
  add column effect_snapshot jsonb not null default '{}'::jsonb,
  add constraint workflow_events_input_snapshot_check check (
    pg_catalog.jsonb_typeof(input_snapshot) = 'object'
    and pg_catalog.octet_length(input_snapshot::text) <= 65536
    and not app.job_payload_contains_forbidden_key(input_snapshot)
  ),
  add constraint workflow_events_effect_snapshot_check check (
    pg_catalog.jsonb_typeof(effect_snapshot) = 'object'
    and pg_catalog.octet_length(effect_snapshot::text) <= 65536
    and not app.job_payload_contains_forbidden_key(effect_snapshot)
  );

-- M3-WF-AC-004: actor-scoped receipts make create, approve, and
-- activate retries deterministic while rejecting key reuse with changed input.
create table public.workflow_admin_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  command_type text not null check (
    command_type in (
      'create_workflow_version',
      'approve_workflow_version',
      'activate_workflow_version'
    )
  ),
  idempotency_key text not null check (
    pg_catalog.char_length(pg_catalog.btrim(idempotency_key)) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[0-9a-f]{64}$'),
  workflow_definition_id uuid not null,
  workflow_version_id uuid not null,
  result jsonb not null check (
    pg_catalog.jsonb_typeof(result) = 'object'
    and not app.job_payload_contains_forbidden_key(result)
  ),
  audit_event_id uuid,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, command_type, idempotency_key),
  foreign key (workspace_id, workflow_definition_id)
    references public.workflow_definitions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict
);

create index workflow_admin_command_receipts_version_idx
  on public.workflow_admin_command_receipts (
    workspace_id,
    workflow_version_id,
    created_at desc
  );

create function app.prevent_workflow_admin_receipt_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'workflow administration receipts are append-only';
end;
$$;

create trigger workflow_admin_command_receipts_append_only
before update or delete on public.workflow_admin_command_receipts
for each row execute function app.prevent_workflow_admin_receipt_mutation();

alter table public.workflow_admin_command_receipts enable row level security;
alter table public.workflow_admin_command_receipts force row level security;

-- The canonical checksum input is intentionally public-data-only and pure.
-- State order is sortOrder/key; transition order is key.
create function app.workflow_configuration_artifact(
  p_definition_key text,
  p_entity_type text,
  p_purpose_key text,
  p_semantic_version text,
  p_schema_version integer,
  p_initial_state_key text,
  p_states jsonb,
  p_transitions jsonb
)
returns jsonb
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'key', p_definition_key,
    'entityType', p_entity_type,
    'purposeKey', p_purpose_key,
    'semanticVersion', p_semantic_version,
    'schemaVersion', p_schema_version,
    'initialStateKey', p_initial_state_key,
    'states', coalesce((
      select pg_catalog.jsonb_agg(state.value order by
        case
          when state.value ->> 'sortOrder' ~ '^-?[0-9]+$'
            then (state.value ->> 'sortOrder')::bigint
          else 9223372036854775807
        end,
        state.value ->> 'key'
      )
      from pg_catalog.jsonb_array_elements(p_states) state(value)
    ), '[]'::jsonb),
    'transitions', coalesce((
      select pg_catalog.jsonb_agg(transition.value order by transition.value ->> 'key')
      from pg_catalog.jsonb_array_elements(p_transitions) transition(value)
    ), '[]'::jsonb)
  );
$$;

create function app.workflow_configuration_checksum(
  p_definition_key text,
  p_entity_type text,
  p_purpose_key text,
  p_semantic_version text,
  p_schema_version integer,
  p_initial_state_key text,
  p_states jsonb,
  p_transitions jsonb
)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select app.configuration_payload_checksum(
    app.workflow_configuration_artifact(
      p_definition_key,
      p_entity_type,
      p_purpose_key,
      p_semantic_version,
      p_schema_version,
      p_initial_state_key,
      p_states,
      p_transitions
    )
  );
$$;

create function app.workflow_version_artifact(
  p_workspace_id uuid,
  p_workflow_version_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'key', definition.key::text,
    'entityType', definition.entity_type,
    'purposeKey', definition.purpose_key,
    'semanticVersion', version.version,
    'schemaVersion', version.schema_version,
    'initialStateKey', version.initial_state_key,
    'states', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', state.key,
          'canonicalCategory', state.canonical_category,
          'labels', state.labels,
          'behaviorFlags', state.behavior_flags,
          'requiredFields', pg_catalog.to_jsonb(state.required_fields),
          'sortOrder', state.sort_order
        ) order by state.sort_order, state.key
      )
      from public.workflow_states state
      where state.workspace_id = version.workspace_id
        and state.workflow_version_id = version.id
    ), '[]'::jsonb),
    'transitions', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', transition.key,
          'fromStateKey', transition.from_state_key,
          'toStateKey', transition.to_state_key,
          'permissionKey', transition.permission_key,
          'guardKey', transition.guard_key,
          'reasonRequired', transition.reason_required,
          'requiredFields', pg_catalog.to_jsonb(transition.required_fields),
          'effectKeys', transition.effect_keys
        ) order by transition.key
      )
      from public.workflow_transitions transition
      where transition.workspace_id = version.workspace_id
        and transition.workflow_version_id = version.id
    ), '[]'::jsonb)
  )
  from public.workflow_versions version
  join public.workflow_definitions definition
    on definition.workspace_id = version.workspace_id
   and definition.id = version.workflow_definition_id
  where version.workspace_id = p_workspace_id
    and version.id = p_workflow_version_id;
$$;

create function app.assert_workflow_semantic_flags(
  p_entity_type text,
  p_states jsonb,
  p_transitions jsonb
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_states) state(value)
    where (
      coalesce((state.value -> 'behaviorFlags' ->> 'conversion_eligible')::boolean, false)
      or coalesce((state.value -> 'behaviorFlags' ->> 'conversion_target')::boolean, false)
      or coalesce((state.value -> 'behaviorFlags' ->> 'loss_terminal')::boolean, false)
    ) and p_entity_type <> 'lead'
  ) or exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_states) state(value)
    where coalesce(
      (state.value -> 'behaviorFlags' ->> 'cancellation')::boolean,
      false
    ) and p_entity_type <> 'deal'
  ) then
    raise exception using
      errcode = '22023',
      message = 'workflow semantic flags do not match the entity type';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_states) state(value)
    where (
      coalesce((state.value -> 'behaviorFlags' ->> 'conversion_target')::boolean, false)
      or coalesce((state.value -> 'behaviorFlags' ->> 'loss_terminal')::boolean, false)
      or coalesce((state.value -> 'behaviorFlags' ->> 'cancellation')::boolean, false)
    ) and not (
      state.value ->> 'canonicalCategory' in ('closed', 'archived')
      or coalesce((state.value -> 'behaviorFlags' ->> 'terminal')::boolean, false)
    )
  ) or exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_states) state(value)
    where coalesce(
      (state.value -> 'behaviorFlags' ->> 'conversion_eligible')::boolean,
      false
    ) and (
      state.value ->> 'canonicalCategory' in ('closed', 'archived')
      or coalesce((state.value -> 'behaviorFlags' ->> 'terminal')::boolean, false)
    )
  ) or exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_states) state(value)
    where coalesce((state.value -> 'behaviorFlags' ->> 'conversion_target')::boolean, false)
      and coalesce((state.value -> 'behaviorFlags' ->> 'loss_terminal')::boolean, false)
  ) then
    raise exception using
      errcode = '22023',
      message = 'workflow semantic flags have an invalid lifecycle shape';
  end if;

  if p_entity_type = 'lead' then
    if (
      select pg_catalog.count(*)
      from pg_catalog.jsonb_array_elements(p_states) state(value)
      where coalesce(
        (state.value -> 'behaviorFlags' ->> 'conversion_target')::boolean,
        false
      )
    ) > 1 then
      raise exception using
        errcode = '22023',
        message = 'lead workflow has multiple conversion targets';
    end if;
    if exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_states) source_state(value)
      where coalesce(
        (source_state.value -> 'behaviorFlags' ->> 'conversion_eligible')::boolean,
        false
      ) and 1 <> (
        select pg_catalog.count(*)
        from pg_catalog.jsonb_array_elements(p_transitions) transition(value)
        join pg_catalog.jsonb_array_elements(p_states) target_state(value)
          on target_state.value ->> 'key' = transition.value ->> 'toStateKey'
        where transition.value ->> 'fromStateKey' = source_state.value ->> 'key'
          and coalesce(
            (target_state.value -> 'behaviorFlags' ->> 'conversion_target')::boolean,
            false
          )
      )
    ) or exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_transitions) transition(value)
      join pg_catalog.jsonb_array_elements(p_states) source_state(value)
        on source_state.value ->> 'key' = transition.value ->> 'fromStateKey'
      join pg_catalog.jsonb_array_elements(p_states) target_state(value)
        on target_state.value ->> 'key' = transition.value ->> 'toStateKey'
      where (
        coalesce(
          (target_state.value -> 'behaviorFlags' ->> 'conversion_target')::boolean,
          false
        ) and not coalesce(
          (source_state.value -> 'behaviorFlags' ->> 'conversion_eligible')::boolean,
          false
        )
      ) or (
        coalesce(
          (target_state.value -> 'behaviorFlags' ->> 'loss_terminal')::boolean,
          false
        ) and not coalesce(
          (transition.value ->> 'reasonRequired')::boolean,
          false
        )
      )
    ) then
      raise exception using
        errcode = '22023',
        message = 'lead workflow semantic transitions are invalid';
    end if;
  end if;

  if p_entity_type = 'deal' and exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_transitions) transition(value)
    join pg_catalog.jsonb_array_elements(p_states) target_state(value)
      on target_state.value ->> 'key' = transition.value ->> 'toStateKey'
    where coalesce(
      (target_state.value -> 'behaviorFlags' ->> 'cancellation')::boolean,
      false
    ) and not coalesce(
      (transition.value ->> 'reasonRequired')::boolean,
      false
    )
  ) then
    raise exception using
      errcode = '22023',
      message = 'deal cancellation transitions require reasons';
  end if;
end;
$$;

create function app.assert_workflow_configuration_payload(
  p_entity_type text,
  p_states jsonb,
  p_transitions jsonb
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  state_entry jsonb;
  transition_entry jsonb;
  required_fields text[];
  effect_keys text[];
begin
  if pg_catalog.jsonb_typeof(p_states) <> 'array'
    or pg_catalog.jsonb_array_length(p_states) = 0
    or pg_catalog.jsonb_array_length(p_states) > 100 then
    raise exception using
      errcode = '22023',
      message = 'workflow states must be a non-empty array of at most 100 entries';
  end if;
  if pg_catalog.jsonb_typeof(p_transitions) <> 'array'
    or pg_catalog.jsonb_array_length(p_transitions) > 250 then
    raise exception using
      errcode = '22023',
      message = 'workflow transitions must be an array of at most 250 entries';
  end if;

  for state_entry in
    select entry.value from pg_catalog.jsonb_array_elements(p_states) entry(value)
  loop
    if pg_catalog.jsonb_typeof(state_entry) <> 'object'
      or not state_entry ?& array[
        'key', 'canonicalCategory', 'labels', 'behaviorFlags',
        'requiredFields', 'sortOrder'
      ]::text[]
      or exists (
        select 1
        from pg_catalog.jsonb_object_keys(state_entry) property(key)
        where property.key <> all(array[
          'key', 'canonicalCategory', 'labels', 'behaviorFlags',
          'requiredFields', 'sortOrder'
        ]::text[])
      ) then
      raise exception using errcode = '22023', message = 'invalid workflow state shape';
    end if;
    if coalesce(state_entry ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,127}$'
      or state_entry ->> 'canonicalCategory' not in (
        'draft', 'active', 'pending', 'closed', 'archived'
      ) then
      raise exception using errcode = '22023', message = 'invalid workflow state identifier';
    end if;
    if pg_catalog.jsonb_typeof(state_entry -> 'labels') <> 'object'
      or pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(state_entry -> 'labels', '$.keyvalue()')) = 0
      or exists (
        select 1
        from pg_catalog.jsonb_each(state_entry -> 'labels') label(locale, value)
        where pg_catalog.btrim(label.locale) = ''
          or pg_catalog.jsonb_typeof(label.value) <> 'string'
          or pg_catalog.btrim(label.value #>> '{}') = ''
          or pg_catalog.char_length(label.value #>> '{}') > 200
      ) then
      raise exception using errcode = '22023', message = 'invalid workflow state labels';
    end if;
    if pg_catalog.jsonb_typeof(state_entry -> 'behaviorFlags') <> 'object'
      or exists (
        select 1
        from pg_catalog.jsonb_each(state_entry -> 'behaviorFlags') flag(key, value)
        where pg_catalog.jsonb_typeof(flag.value) <> 'boolean'
      ) then
      raise exception using errcode = '22023', message = 'invalid workflow behavior flags';
    end if;
    if pg_catalog.jsonb_typeof(state_entry -> 'requiredFields') <> 'array'
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(state_entry -> 'requiredFields') field(value)
        where pg_catalog.jsonb_typeof(field.value) <> 'string'
      ) then
      raise exception using errcode = '22023', message = 'invalid workflow state required fields';
    end if;
    select coalesce(pg_catalog.array_agg(field.value), '{}'::text[])
      into required_fields
    from pg_catalog.jsonb_array_elements_text(state_entry -> 'requiredFields') field(value);
    if not app.workflow_required_fields_valid(required_fields) then
      raise exception using errcode = '22023', message = 'invalid workflow state required fields';
    end if;
    if pg_catalog.jsonb_typeof(state_entry -> 'sortOrder') <> 'number'
      or coalesce(state_entry ->> 'sortOrder', '') !~ '^-?[0-9]+$'
      or (state_entry ->> 'sortOrder')::numeric not between -2147483648 and 2147483647 then
      raise exception using errcode = '22023', message = 'invalid workflow state sort order';
    end if;
  end loop;

  for transition_entry in
    select entry.value from pg_catalog.jsonb_array_elements(p_transitions) entry(value)
  loop
    if pg_catalog.jsonb_typeof(transition_entry) <> 'object'
      or not transition_entry ?& array[
        'key', 'fromStateKey', 'toStateKey', 'permissionKey', 'guardKey',
        'reasonRequired', 'requiredFields', 'effectKeys'
      ]::text[]
      or exists (
        select 1
        from pg_catalog.jsonb_object_keys(transition_entry) property(key)
        where property.key <> all(array[
          'key', 'fromStateKey', 'toStateKey', 'permissionKey', 'guardKey',
          'reasonRequired', 'requiredFields', 'effectKeys'
        ]::text[])
      ) then
      raise exception using errcode = '22023', message = 'invalid workflow transition shape';
    end if;
    if coalesce(transition_entry ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,127}$'
      or coalesce(transition_entry ->> 'fromStateKey', '') !~ '^[a-z][a-z0-9_]{0,127}$'
      or coalesce(transition_entry ->> 'toStateKey', '') !~ '^[a-z][a-z0-9_]{0,127}$'
      or transition_entry ->> 'fromStateKey' = transition_entry ->> 'toStateKey'
      or coalesce(transition_entry ->> 'permissionKey', '')
        !~ '^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})+$' then
      raise exception using errcode = '22023', message = 'invalid workflow transition identifier';
    end if;
    if pg_catalog.jsonb_typeof(transition_entry -> 'guardKey') not in ('string', 'null')
      or not app.workflow_guard_allowed_for_entity(
        p_entity_type,
        transition_entry ->> 'guardKey'
      ) then
      raise exception using errcode = '22023', message = 'workflow guard is not allowlisted for entity';
    end if;
    if pg_catalog.jsonb_typeof(transition_entry -> 'reasonRequired') <> 'boolean' then
      raise exception using errcode = '22023', message = 'invalid workflow reason requirement';
    end if;
    if pg_catalog.jsonb_typeof(transition_entry -> 'requiredFields') <> 'array'
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(transition_entry -> 'requiredFields') field(value)
        where pg_catalog.jsonb_typeof(field.value) <> 'string'
      ) then
      raise exception using errcode = '22023', message = 'invalid workflow transition required fields';
    end if;
    select coalesce(pg_catalog.array_agg(field.value), '{}'::text[])
      into required_fields
    from pg_catalog.jsonb_array_elements_text(transition_entry -> 'requiredFields') field(value);
    if not app.workflow_required_fields_valid(required_fields) then
      raise exception using errcode = '22023', message = 'invalid workflow transition required fields';
    end if;
    if pg_catalog.jsonb_typeof(transition_entry -> 'effectKeys') <> 'array'
      or pg_catalog.jsonb_array_length(transition_entry -> 'effectKeys') > 32
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(transition_entry -> 'effectKeys') effect(value)
        where pg_catalog.jsonb_typeof(effect.value) <> 'string'
      ) then
      raise exception using errcode = '22023', message = 'invalid workflow effects';
    end if;
    select coalesce(pg_catalog.array_agg(effect.value), '{}'::text[])
      into effect_keys
    from pg_catalog.jsonb_array_elements_text(transition_entry -> 'effectKeys') effect(value);
    if pg_catalog.cardinality(effect_keys) <> (
      select pg_catalog.count(distinct effect.value)
      from pg_catalog.unnest(effect_keys) effect(value)
    ) or exists (
      select 1
      from pg_catalog.unnest(effect_keys) effect(value)
      where not app.workflow_effect_allowed_for_entity(p_entity_type, effect.value)
    ) then
      raise exception using errcode = '22023', message = 'workflow effect is not allowlisted for entity';
    end if;
  end loop;
  perform app.assert_workflow_semantic_flags(
    p_entity_type,
    p_states,
    p_transitions
  );
end;
$$;

create function app.validate_workflow_state_configuration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from pg_catalog.jsonb_each(new.labels) label(locale, value)
    where pg_catalog.btrim(label.locale) = ''
      or pg_catalog.jsonb_typeof(label.value) <> 'string'
      or pg_catalog.btrim(label.value #>> '{}') = ''
      or pg_catalog.char_length(label.value #>> '{}') > 200
  ) or exists (
    select 1
    from pg_catalog.jsonb_each(new.behavior_flags) flag(key, value)
    where pg_catalog.jsonb_typeof(flag.value) <> 'boolean'
  ) then
    raise exception using
      errcode = '23514',
      message = 'workflow state labels and behavior flags must be declarative scalars';
  end if;
  return new;
end;
$$;

create or replace function app.validate_workflow_transition_configuration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  definition_entity_type text;
begin
  if not exists (
    select 1
    from public.permissions permission
    where permission.key = new.permission_key
      and permission.status = 'active'
      and (
        permission.workspace_id is null
        or permission.workspace_id = new.workspace_id
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'workflow transition permission must be an active immutable permission key';
  end if;

  select definition.entity_type
    into definition_entity_type
  from public.workflow_versions version
  join public.workflow_definitions definition
    on definition.workspace_id = version.workspace_id
   and definition.id = version.workflow_definition_id
  where version.workspace_id = new.workspace_id
    and version.id = new.workflow_version_id;

  if not found then
    raise exception using errcode = '23503', message = 'workflow version is unavailable';
  end if;
  if not app.workflow_guard_allowed_for_entity(definition_entity_type, new.guard_key) then
    raise exception using
      errcode = '23514',
      message = 'workflow transition guard is not allowlisted for entity';
  end if;
  if pg_catalog.jsonb_typeof(new.effect_keys) <> 'array'
    or pg_catalog.jsonb_array_length(new.effect_keys) > 32
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(new.effect_keys) effect(value)
      where pg_catalog.jsonb_typeof(effect.value) <> 'string'
    )
    or (
      select pg_catalog.count(*)
      from pg_catalog.jsonb_array_elements_text(new.effect_keys) effect(value)
    ) <> (
      select pg_catalog.count(distinct effect.value)
      from pg_catalog.jsonb_array_elements_text(new.effect_keys) effect(value)
    )
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements_text(new.effect_keys) effect(value)
      where not app.workflow_effect_allowed_for_entity(
        definition_entity_type,
        effect.value
      )
    ) then
    raise exception using
      errcode = '23514',
      message = 'workflow transition effect is not allowlisted for entity';
  end if;
  return new;
end;
$$;

create function app.workflow_version_has_valid_approval(
  p_workspace_id uuid,
  p_workflow_version_id uuid,
  p_effective_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workflow_versions version
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    join public.approval_records approval
      on approval.workspace_id = version.workspace_id
     and approval.id = version.approval_record_id
    where version.workspace_id = p_workspace_id
      and version.id = p_workflow_version_id
      and approval.artifact_type = 'workflow_version'
      and approval.artifact_key = 'workflow.' || definition.key::text
      and approval.artifact_version = version.revision
      and approval.artifact_id = version.id
      and approval.artifact_checksum = version.checksum
      and approval.approval_type = 'workflow.activation'
      and approval.decision = 'approved'
      and approval.decided_by = version.approved_by
      and approval.decided_at = version.approved_at
      and (approval.expires_at is null or approval.expires_at > p_effective_at)
      and not exists (
        select 1
        from public.approval_records revocation
        where revocation.workspace_id = approval.workspace_id
          and revocation.decision = 'revoked'
          and revocation.supersedes_approval_id = approval.id
      )
  );
$$;

create function app.workspace_entitlement_is_enabled(
  p_workspace_id uuid,
  p_entitlement_key text,
  p_effective_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.count(*) = 1
    and coalesce(pg_catalog.bool_and(
      entitlement.enabled
      and entitlement.effective_from <= p_effective_at
      and (
        entitlement.effective_until is null
        or p_effective_at < entitlement.effective_until
      )
    ), false)
  from public.workspace_feature_entitlements entitlement
  where entitlement.workspace_id = p_workspace_id
    and entitlement.entitlement_key = p_entitlement_key
    and entitlement.status = 'active';
$$;

create or replace function app.protect_activated_workflow_configuration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_status text;
  version_approval_id uuid;
begin
  if tg_table_name = 'workflow_versions' then
    if tg_op = 'INSERT' then
      return new;
    end if;

    if tg_op = 'DELETE' then
      if old.status = 'draft' and old.approval_record_id is null then
        return old;
      end if;
      raise exception using
        errcode = '55000',
        message = 'approved or activated workflow configuration is immutable';
    end if;

    if old.status = 'draft' and row(
      new.id,
      new.workspace_id,
      new.workflow_definition_id,
      new.revision,
      new.created_by,
      new.created_at
    ) is distinct from row(
      old.id,
      old.workspace_id,
      old.workflow_definition_id,
      old.revision,
      old.created_by,
      old.created_at
    ) then
      raise exception using
        errcode = '55000',
        message = 'workflow version identity is immutable';
    end if;

    if old.status = 'draft' and old.approval_record_id is null
      and new.status = 'draft' then
      if new.approval_record_id is null then
        return new;
      end if;
      if (pg_catalog.to_jsonb(new) - array[
        'approval_record_id', 'approved_by', 'approved_at'
      ]::text[]) is distinct from (pg_catalog.to_jsonb(old) - array[
        'approval_record_id', 'approved_by', 'approved_at'
      ]::text[])
        or not exists (
          select 1
          from public.workflow_definitions definition
          join public.approval_records approval
            on approval.workspace_id = new.workspace_id
           and approval.id = new.approval_record_id
          where definition.workspace_id = new.workspace_id
            and definition.id = new.workflow_definition_id
            and approval.artifact_type = 'workflow_version'
            and approval.artifact_key = 'workflow.' || definition.key::text
            and approval.artifact_version = new.revision
            and approval.artifact_id = new.id
            and approval.artifact_checksum = new.checksum
            and approval.approval_type = 'workflow.activation'
            and approval.decision = 'approved'
            and approval.decided_by = new.approved_by
            and approval.decided_at = new.approved_at
            and (
              approval.expires_at is null
              or approval.expires_at > pg_catalog.statement_timestamp()
            )
        ) then
        raise exception using
          errcode = '23514',
          message = 'workflow approval must match the exact immutable draft';
      end if;
      return new;
    end if;

    if old.status = 'draft' and old.approval_record_id is not null
      and new.status = 'active'
      and new.activated_at is not null
      and new.retired_at is null
      and (pg_catalog.to_jsonb(new) - array['status', 'activated_at']::text[])
        is not distinct from
        (pg_catalog.to_jsonb(old) - array['status', 'activated_at']::text[]) then
      return new;
    end if;

    -- Starter installation is a distinct migration/seed path. It is limited to
    -- the database owner running declarative pack SQL; service-role requests and
    -- authenticated workflow-admin commands cannot claim starter provenance.
    if old.status = 'draft' and old.approval_record_id is null
      and old.source = 'starter_pack'
      and app.configuration_invoker_role() in ('postgres', 'supabase_admin')
      and new.status = 'active'
      and new.activated_at is not null
      and new.retired_at is null
      and (pg_catalog.to_jsonb(new) - array['status', 'activated_at']::text[])
        is not distinct from
        (pg_catalog.to_jsonb(old) - array['status', 'activated_at']::text[]) then
      return new;
    end if;

    if old.status = 'active' and new.status = 'retired'
      and old.retired_at is null
      and new.retired_at is not null
      and (pg_catalog.to_jsonb(new) - array['status', 'retired_at']::text[])
        is not distinct from
        (pg_catalog.to_jsonb(old) - array['status', 'retired_at']::text[]) then
      return new;
    end if;

    raise exception using
      errcode = '55000',
      message = 'approved or activated workflow configuration is immutable';
  end if;

  if tg_op = 'UPDATE' and row(new.workspace_id, new.workflow_version_id)
    is distinct from row(old.workspace_id, old.workflow_version_id) then
    raise exception using
      errcode = '55000',
      message = 'workflow configuration ownership is immutable';
  end if;

  select version.status, version.approval_record_id
    into version_status, version_approval_id
  from public.workflow_versions version
  where version.workspace_id = case
      when tg_op = 'INSERT' then new.workspace_id else old.workspace_id
    end
    and version.id = case
      when tg_op = 'INSERT' then new.workflow_version_id else old.workflow_version_id
    end
  for update;

  if version_status in ('active', 'retired') or version_approval_id is not null then
    raise exception using
      errcode = '55000',
      message = 'approved or activated workflow configuration is immutable';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function app.validate_workflow_version_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_artifact jsonb;
  definition_entity_type text;
begin
  if tg_op = 'INSERT' then
    if new.revision is null then
      perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
          'workflow_revision:' || new.workspace_id::text || ':'
            || new.workflow_definition_id::text,
          0
        )
      );
      select coalesce(pg_catalog.max(version.revision), 0) + 1
        into new.revision
      from public.workflow_versions version
      where version.workspace_id = new.workspace_id
        and version.workflow_definition_id = new.workflow_definition_id;
    end if;
    if new.status <> 'draft'
      or new.activated_at is not null
      or new.retired_at is not null then
      raise exception using
        errcode = '23514',
        message = 'workflow version must start as a draft';
    end if;
    return new;
  end if;

  if old.status = 'draft' and new.status = 'draft' then
    if new.activated_at is not null or new.retired_at is not null then
      raise exception using
        errcode = '23514',
        message = 'draft workflow versions cannot have lifecycle timestamps';
    end if;
    return new;
  end if;

  if old.status = 'draft' and new.status = 'active' then
    if new.activated_at is null or new.retired_at is not null then
      raise exception using
        errcode = '23514',
        message = 'workflow activation timestamps are invalid';
    end if;
    if not exists (
      select 1
      from public.workflow_definitions definition
      where definition.workspace_id = new.workspace_id
        and definition.id = new.workflow_definition_id
        and definition.status = 'active'
    ) then
      raise exception using
        errcode = '23514',
        message = 'workflow definition must be active before version activation';
    end if;
    select definition.entity_type into definition_entity_type
    from public.workflow_definitions definition
    where definition.workspace_id = new.workspace_id
      and definition.id = new.workflow_definition_id;
    if not exists (
      select 1
      from public.workflow_states state
      where state.workspace_id = new.workspace_id
        and state.workflow_version_id = new.id
        and state.key = new.initial_state_key
    ) then
      raise exception using
        errcode = '23514',
        message = 'workflow initial state must exist before version activation';
    end if;
    if exists (
      select 1
      from public.workflow_states state
      join public.workflow_transitions transition
        on transition.workspace_id = state.workspace_id
       and transition.workflow_version_id = state.workflow_version_id
       and transition.from_state_key = state.key
      where state.workspace_id = new.workspace_id
        and state.workflow_version_id = new.id
        and (
          state.canonical_category in ('closed', 'archived')
          or state.behavior_flags @> '{"terminal":true}'::jsonb
        )
    ) then
      raise exception using
        errcode = '23514',
        message = 'terminal workflow states cannot have outgoing transitions';
    end if;
    current_artifact := app.workflow_version_artifact(new.workspace_id, new.id);
    perform app.assert_workflow_semantic_flags(
      definition_entity_type,
      current_artifact -> 'states',
      current_artifact -> 'transitions'
    );
    if new.source = 'starter_pack'
      and app.configuration_invoker_role() in ('postgres', 'supabase_admin') then
      return new;
    end if;
    if app.configuration_payload_checksum(current_artifact) <> new.checksum then
      raise exception using
        errcode = '23514',
        message = 'workflow checksum does not match the persisted artifact';
    end if;
    if not app.workflow_version_has_valid_approval(
      new.workspace_id,
      new.id,
      pg_catalog.statement_timestamp()
    ) then
      raise exception using
        errcode = '23514',
        message = 'workflow activation requires an exact current approval';
    end if;
    return new;
  end if;

  if old.status = 'active' and new.status = 'retired' then
    if new.activated_at is distinct from old.activated_at
      or new.retired_at is null
      or new.retired_at < new.activated_at then
      raise exception using
        errcode = '23514',
        message = 'workflow retirement timestamps are invalid';
    end if;
    return new;
  end if;

  raise exception using
    errcode = '23514',
    message = 'workflow version lifecycle transition is not allowed';
end;
$$;

create function app.populate_workflow_event_snapshots()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  transition_row public.workflow_transitions%rowtype;
  target_required_fields text[];
  snapshot_required_fields text[];
begin
  select transition.*
    into transition_row
  from public.workflow_transitions transition
  where transition.workspace_id = new.workspace_id
    and transition.id = new.transition_id;
  if not found then
    raise exception using errcode = '23503', message = 'workflow transition is unavailable';
  end if;

  select state.required_fields
    into target_required_fields
  from public.workflow_states state
  where state.workspace_id = new.workspace_id
    and state.workflow_version_id = transition_row.workflow_version_id
    and state.key = transition_row.to_state_key;

  select coalesce(pg_catalog.array_agg(required_field.value order by required_field.first_position), '{}'::text[])
    into snapshot_required_fields
  from (
    select field.value, pg_catalog.min(field.position) as first_position
    from pg_catalog.unnest(
      transition_row.required_fields || coalesce(target_required_fields, '{}'::text[])
    ) with ordinality field(value, position)
    group by field.value
  ) required_field;

  new.input_snapshot := pg_catalog.jsonb_build_object(
    'requiredFieldKeys', pg_catalog.to_jsonb(snapshot_required_fields),
    'guardKey', transition_row.guard_key,
    'guardSatisfied', case when transition_row.guard_key is null then null else true end,
    'reasonProvided', new.reason is not null
  );
  new.effect_snapshot := pg_catalog.jsonb_build_object(
    'effectKeys', transition_row.effect_keys
  );
  return new;
end;
$$;

drop trigger workflow_versions_validate_lifecycle on public.workflow_versions;
create trigger workflow_versions_validate_lifecycle
before insert or update of status, activated_at, retired_at
on public.workflow_versions
for each row execute function app.validate_workflow_version_lifecycle();

create trigger workflow_states_validate_configuration
before insert or update on public.workflow_states
for each row execute function app.validate_workflow_state_configuration();

create trigger workflow_events_populate_snapshots
before insert on public.workflow_events
for each row execute function app.populate_workflow_event_snapshots();

-- M3-WF-AC-004: reusable workflow metadata no longer lets inventory readers
-- observe lead/deal definitions, instances, or events. workflow.read remains
-- the explicit cross-domain administration permission.
create function app.workflow_entity_read_permission(p_entity_type text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case p_entity_type
    when 'inventory_unit' then 'inventory.read'
    when 'party' then 'crm.read'
    when 'lead' then 'crm.read'
    when 'deal' then 'deals.read'
    when 'finance_application' then 'finance_applications.read'
    when 'payment_transaction' then 'payments.read'
    when 'document' then 'documents.read'
    else null
  end;
$$;

create function app.can_read_workflow_entity(
  p_workspace_id uuid,
  p_entity_type text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  domain_permission text;
begin
  if app.has_permission(p_workspace_id, 'workflow.read') then
    return true;
  end if;
  domain_permission := app.workflow_entity_read_permission(p_entity_type);
  return domain_permission is not null
    and app.has_permission(p_workspace_id, domain_permission);
end;
$$;

create function app.can_read_workflow_definition(
  p_workspace_id uuid,
  p_workflow_definition_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workflow_definitions definition
    where definition.workspace_id = p_workspace_id
      and definition.id = p_workflow_definition_id
      and app.can_read_workflow_entity(
        definition.workspace_id,
        definition.entity_type
      )
  );
$$;

create function app.can_read_workflow_version(
  p_workspace_id uuid,
  p_workflow_version_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workflow_versions version
    where version.workspace_id = p_workspace_id
      and version.id = p_workflow_version_id
      and app.can_read_workflow_definition(
        version.workspace_id,
        version.workflow_definition_id
      )
  );
$$;

drop policy workflow_definitions_select on public.workflow_definitions;
create policy workflow_definitions_select
on public.workflow_definitions
for select to authenticated
using (app.can_read_workflow_entity(workspace_id, entity_type));

drop policy workflow_versions_select on public.workflow_versions;
create policy workflow_versions_select
on public.workflow_versions
for select to authenticated
using (app.can_read_workflow_definition(workspace_id, workflow_definition_id));

drop policy workflow_states_select on public.workflow_states;
create policy workflow_states_select
on public.workflow_states
for select to authenticated
using (app.can_read_workflow_version(workspace_id, workflow_version_id));

drop policy workflow_transitions_select on public.workflow_transitions;
create policy workflow_transitions_select
on public.workflow_transitions
for select to authenticated
using (app.can_read_workflow_version(workspace_id, workflow_version_id));

drop policy workflow_instances_select on public.workflow_instances;
create policy workflow_instances_select
on public.workflow_instances
for select to authenticated
using (app.can_read_workflow_entity(workspace_id, entity_type));

drop policy workflow_events_select on public.workflow_events;
create policy workflow_events_select
on public.workflow_events
for select to authenticated
using (app.can_read_workflow_entity(workspace_id, entity_type));

-- M3-WF-AC-004: the administration read model requires the explicit workflow
-- permission and an effective custom_workflows entitlement. Domain readers use
-- the entity-aware table policies above instead of this cross-domain RPC.
create function app.read_workflow_definition_admin(
  p_workspace_id uuid,
  p_workflow_definition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result_payload jsonb;
begin
  perform app.assert_configuration_command_authority(
    p_workspace_id,
    'workflow.read',
    false
  );
  if not app.workspace_entitlement_is_enabled(
    p_workspace_id,
    'custom_workflows',
    pg_catalog.statement_timestamp()
  ) then
    raise exception using
      errcode = '42501',
      message = 'custom workflows entitlement is not active';
  end if;

  select pg_catalog.jsonb_build_object(
    'definition', pg_catalog.jsonb_build_object(
      'id', definition.id,
      'workspaceId', definition.workspace_id,
      'key', definition.key::text,
      'entityType', definition.entity_type,
      'purposeKey', definition.purpose_key,
      'status', definition.status,
      'createdAt', definition.created_at
    ),
    'versions', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', version.id,
          'revision', version.revision,
          'semanticVersion', version.version,
          'status', version.status,
          'checksum', version.checksum,
          'source', version.source,
          'approvalRecordId', version.approval_record_id,
          'approvedAt', version.approved_at,
          'activatedAt', version.activated_at,
          'retiredAt', version.retired_at,
          'approvalCurrent', case
            when version.approval_record_id is null then false
            else app.workflow_version_has_valid_approval(
              version.workspace_id,
              version.id,
              pg_catalog.statement_timestamp()
            )
          end,
          'artifact', app.workflow_version_artifact(
            version.workspace_id,
            version.id
          )
        ) order by version.revision desc
      )
      from (
        select candidate.*
        from public.workflow_versions candidate
        where candidate.workspace_id = definition.workspace_id
          and candidate.workflow_definition_id = definition.id
        order by candidate.revision desc
        limit 100
      ) version
    ), '[]'::jsonb)
  )
    into result_payload
  from public.workflow_definitions definition
  where definition.workspace_id = p_workspace_id
    and definition.id = p_workflow_definition_id;

  if result_payload is null then
    raise exception using errcode = '23503', message = 'workflow definition does not exist';
  end if;
  return result_payload;
end;
$$;

-- M3-WF-AC-004: one authenticated administrator command creates the complete
-- draft graph. It never activates the version and cannot claim starter-pack or
-- migration provenance.
create function app.create_workflow_version_admin(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_definition_key text,
  p_entity_type text,
  p_purpose_key text,
  p_semantic_version text,
  p_schema_version integer,
  p_initial_state_key text,
  p_states jsonb,
  p_transitions jsonb,
  p_expected_checksum text,
  p_expected_latest_version_id uuid,
  p_reason text,
  p_request_id text default null,
  p_correlation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_reason text;
  definition_row public.workflow_definitions%rowtype;
  latest_version_id uuid;
  next_revision bigint;
  created_version_id uuid;
  state_entry jsonb;
  transition_entry jsonb;
  required_fields text[];
  expected_artifact jsonb;
  persisted_artifact jsonb;
  computed_checksum text;
  request_fingerprint text;
  existing_receipt public.workflow_admin_command_receipts%rowtype;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  perform app.assert_configuration_command_authority(
    p_workspace_id,
    'workflow.activate',
    true
  );
  if not app.workspace_entitlement_is_enabled(
    p_workspace_id,
    'custom_workflows',
    pg_catalog.statement_timestamp()
  ) then
    raise exception using
      errcode = '42501',
      message = 'custom workflows entitlement is not active';
  end if;

  actor_user_id := app.configuration_actor_id();
  if actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'workflow administration requires an authenticated human actor';
  end if;
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid workflow idempotency key';
  end if;
  if pg_catalog.char_length(normalized_reason) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'workflow administration reason is required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'workflow request ID is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'workflow correlation ID is required';
  end if;
  if p_definition_key is null
    or pg_catalog.char_length(p_definition_key) > 128
    or p_definition_key !~ '^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})*$'
    or coalesce(p_entity_type, '') !~ '^[a-z][a-z0-9_]{0,127}$'
    or coalesce(p_purpose_key, '') !~ '^[a-z][a-z0-9_]{0,127}$'
    or coalesce(p_semantic_version, '') !~ '^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$'
    or p_schema_version is null or p_schema_version < 1
    or coalesce(p_initial_state_key, '') !~ '^[a-z][a-z0-9_]{0,127}$'
    or coalesce(p_expected_checksum, '') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'invalid workflow version metadata';
  end if;

  perform app.assert_workflow_configuration_payload(
    p_entity_type,
    p_states,
    p_transitions
  );
  expected_artifact := app.workflow_configuration_artifact(
    p_definition_key,
    p_entity_type,
    p_purpose_key,
    p_semantic_version,
    p_schema_version,
    p_initial_state_key,
    p_states,
    p_transitions
  );
  computed_checksum := app.configuration_payload_checksum(expected_artifact);
  if computed_checksum <> p_expected_checksum then
    raise exception using errcode = '23514', message = 'workflow checksum mismatch';
  end if;

  request_fingerprint := app.configuration_payload_checksum(
    pg_catalog.jsonb_build_object(
      'command', 'create_workflow_version',
      'artifact', expected_artifact,
      'expectedChecksum', p_expected_checksum,
      'expectedLatestVersionId', p_expected_latest_version_id,
      'reason', normalized_reason,
      'requestId', p_request_id,
      'correlationId', p_correlation_id
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fcreate_workflow_version\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.workflow_admin_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'create_workflow_version'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'workflow idempotency key was used for different create input';
    end if;
    return existing_receipt.result || '{"replayed":true}'::jsonb;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workflow_definition:' || p_workspace_id::text || ':' || p_definition_key,
      0
    )
  );
  select definition.*
    into definition_row
  from public.workflow_definitions definition
  where definition.workspace_id = p_workspace_id
    and definition.key = p_definition_key
  for update;

  if not found then
    if p_expected_latest_version_id is not null then
      raise exception using errcode = '40001', message = 'workflow history advanced';
    end if;
    insert into public.workflow_definitions (
      workspace_id,
      key,
      entity_type,
      purpose_key,
      status,
      created_by
    ) values (
      p_workspace_id,
      p_definition_key,
      p_entity_type,
      p_purpose_key,
      'active',
      actor_user_id
    )
    returning * into definition_row;
  elsif definition_row.status <> 'active'
    or definition_row.entity_type <> p_entity_type
    or definition_row.purpose_key <> p_purpose_key then
    raise exception using
      errcode = '23514',
      message = 'workflow definition identity or lifecycle does not match';
  end if;

  select version.id
    into latest_version_id
  from public.workflow_versions version
  where version.workspace_id = p_workspace_id
    and version.workflow_definition_id = definition_row.id
  order by version.revision desc
  limit 1
  for update;

  if latest_version_id is distinct from p_expected_latest_version_id then
    raise exception using errcode = '40001', message = 'workflow history advanced';
  end if;
  select coalesce(pg_catalog.max(version.revision), 0) + 1
    into next_revision
  from public.workflow_versions version
  where version.workspace_id = p_workspace_id
    and version.workflow_definition_id = definition_row.id;

  insert into public.workflow_versions (
    workspace_id,
    workflow_definition_id,
    revision,
    version,
    schema_version,
    initial_state_key,
    status,
    checksum,
    source,
    created_by
  ) values (
    p_workspace_id,
    definition_row.id,
    next_revision,
    p_semantic_version,
    p_schema_version,
    p_initial_state_key,
    'draft',
    p_expected_checksum,
    'configuration',
    actor_user_id
  )
  returning id into created_version_id;

  for state_entry in
    select entry.value from pg_catalog.jsonb_array_elements(p_states) entry(value)
  loop
    select coalesce(pg_catalog.array_agg(field.value), '{}'::text[])
      into required_fields
    from pg_catalog.jsonb_array_elements_text(state_entry -> 'requiredFields') field(value);
    insert into public.workflow_states (
      workspace_id,
      workflow_version_id,
      key,
      canonical_category,
      labels,
      behavior_flags,
      required_fields,
      sort_order
    ) values (
      p_workspace_id,
      created_version_id,
      state_entry ->> 'key',
      state_entry ->> 'canonicalCategory',
      state_entry -> 'labels',
      state_entry -> 'behaviorFlags',
      required_fields,
      (state_entry ->> 'sortOrder')::integer
    );
  end loop;

  if not exists (
    select 1
    from public.workflow_states state
    where state.workspace_id = p_workspace_id
      and state.workflow_version_id = created_version_id
      and state.key = p_initial_state_key
  ) then
    raise exception using errcode = '23514', message = 'workflow initial state is missing';
  end if;

  for transition_entry in
    select entry.value from pg_catalog.jsonb_array_elements(p_transitions) entry(value)
  loop
    select coalesce(pg_catalog.array_agg(field.value), '{}'::text[])
      into required_fields
    from pg_catalog.jsonb_array_elements_text(
      transition_entry -> 'requiredFields'
    ) field(value);
    insert into public.workflow_transitions (
      workspace_id,
      workflow_version_id,
      key,
      from_state_key,
      to_state_key,
      permission_key,
      guard_key,
      reason_required,
      required_fields,
      effect_keys
    ) values (
      p_workspace_id,
      created_version_id,
      transition_entry ->> 'key',
      transition_entry ->> 'fromStateKey',
      transition_entry ->> 'toStateKey',
      transition_entry ->> 'permissionKey',
      transition_entry ->> 'guardKey',
      (transition_entry ->> 'reasonRequired')::boolean,
      required_fields,
      transition_entry -> 'effectKeys'
    );
  end loop;

  persisted_artifact := app.workflow_version_artifact(
    p_workspace_id,
    created_version_id
  );
  if persisted_artifact is distinct from expected_artifact
    or app.configuration_payload_checksum(persisted_artifact) <> p_expected_checksum then
    raise exception using
      errcode = '23514',
      message = 'persisted workflow artifact does not match expected checksum input';
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'workflow.version_created',
    p_entity_type => 'workflow_version',
    p_entity_id => created_version_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'definitionId', definition_row.id,
      'revision', next_revision,
      'semanticVersion', p_semantic_version,
      'checksum', p_expected_checksum,
      'status', 'draft'
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'definitionKey', p_definition_key,
      'idempotencyKey', normalized_idempotency_key
    )
  );
  result_payload := pg_catalog.jsonb_build_object(
    'workflowDefinitionId', definition_row.id,
    'workflowVersionId', created_version_id,
    'revision', next_revision,
    'checksum', p_expected_checksum,
    'replayed', false,
    'auditEventId', new_audit_event_id
  );
  insert into public.workflow_admin_command_receipts (
    workspace_id,
    actor_user_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    workflow_definition_id,
    workflow_version_id,
    result,
    audit_event_id
  ) values (
    p_workspace_id,
    actor_user_id,
    'create_workflow_version',
    normalized_idempotency_key,
    request_fingerprint,
    definition_row.id,
    created_version_id,
    result_payload,
    new_audit_event_id
  );
  return result_payload;
end;
$$;

-- M3-WF-AC-004: approval freezes the exact draft checksum. The approval row is
-- append-only and actor-scoped idempotency prevents one administrator from
-- replaying another administrator's logical key.
create function app.approve_workflow_version_admin(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_workflow_version_id uuid,
  p_expected_revision bigint,
  p_expected_checksum text,
  p_reason text,
  p_expires_at timestamptz default null,
  p_request_id text default null,
  p_correlation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_reason text;
  physical_approval_idempotency_key text;
  version_row public.workflow_versions%rowtype;
  definition_row public.workflow_definitions%rowtype;
  approval_row public.approval_records%rowtype;
  request_fingerprint text;
  existing_receipt public.workflow_admin_command_receipts%rowtype;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  perform app.assert_configuration_command_authority(
    p_workspace_id,
    'approvals.create',
    true
  );
  if not app.workspace_entitlement_is_enabled(
    p_workspace_id,
    'custom_workflows',
    pg_catalog.statement_timestamp()
  ) then
    raise exception using
      errcode = '42501',
      message = 'custom workflows entitlement is not active';
  end if;

  actor_user_id := app.configuration_actor_id();
  if actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'workflow approval requires an authenticated human actor';
  end if;
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid workflow idempotency key';
  end if;
  if pg_catalog.char_length(normalized_reason) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'workflow approval reason is required';
  end if;
  if p_expected_revision is null or p_expected_revision < 1
    or coalesce(p_expected_checksum, '') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'invalid expected workflow version';
  end if;
  if p_expires_at is not null
    and p_expires_at <= pg_catalog.statement_timestamp() then
    raise exception using errcode = '22023', message = 'workflow approval expiry must be future';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'workflow request ID is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'workflow correlation ID is required';
  end if;

  request_fingerprint := app.configuration_payload_checksum(
    pg_catalog.jsonb_build_object(
      'command', 'approve_workflow_version',
      'workflowVersionId', p_workflow_version_id,
      'expectedRevision', p_expected_revision,
      'expectedChecksum', p_expected_checksum,
      'reason', normalized_reason,
      'expiresAt', p_expires_at,
      'requestId', p_request_id,
      'correlationId', p_correlation_id
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fapprove_workflow_version\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );
  select receipt.*
    into existing_receipt
  from public.workflow_admin_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'approve_workflow_version'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'workflow idempotency key was used for different approval input';
    end if;
    return existing_receipt.result || '{"replayed":true}'::jsonb;
  end if;

  select version.*
    into version_row
  from public.workflow_versions version
  where version.workspace_id = p_workspace_id
    and version.id = p_workflow_version_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'workflow version does not exist';
  end if;
  select definition.*
    into definition_row
  from public.workflow_definitions definition
  where definition.workspace_id = version_row.workspace_id
    and definition.id = version_row.workflow_definition_id;

  if version_row.status <> 'draft'
    or version_row.approval_record_id is not null then
    raise exception using errcode = '23514', message = 'only an unapproved workflow draft can be approved';
  end if;
  if version_row.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'workflow revision conflict';
  end if;
  if version_row.checksum <> p_expected_checksum
    or app.configuration_payload_checksum(
      app.workflow_version_artifact(p_workspace_id, version_row.id)
    ) <> p_expected_checksum then
    raise exception using errcode = '23514', message = 'workflow checksum mismatch';
  end if;

  physical_approval_idempotency_key := 'workflow.approve:'
    || actor_user_id::text || ':' || normalized_idempotency_key;
  perform pg_catalog.set_config('app.configuration_reason', normalized_reason, true);
  insert into public.approval_records (
    workspace_id,
    artifact_type,
    artifact_key,
    artifact_version,
    artifact_id,
    artifact_checksum,
    approval_type,
    decision,
    decided_by,
    conditions,
    expires_at,
    idempotency_key,
    reason
  ) values (
    p_workspace_id,
    'workflow_version',
    'workflow.' || definition_row.key::text,
    version_row.revision,
    version_row.id,
    version_row.checksum,
    'workflow.activation',
    'approved',
    actor_user_id,
    pg_catalog.jsonb_build_object(
      'scope', 'workflow_activation',
      'workflowDefinitionId', definition_row.id
    ),
    p_expires_at,
    physical_approval_idempotency_key,
    normalized_reason
  )
  returning * into approval_row;

  update public.workflow_versions
  set approval_record_id = approval_row.id,
      approved_by = approval_row.decided_by,
      approved_at = approval_row.decided_at
  where workspace_id = p_workspace_id
    and id = version_row.id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'workflow.version_approved',
    p_entity_type => 'workflow_version',
    p_entity_id => version_row.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'revision', version_row.revision,
      'checksum', version_row.checksum,
      'approvalRecordId', null
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'revision', version_row.revision,
      'checksum', version_row.checksum,
      'approvalRecordId', approval_row.id
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'workflowDefinitionId', definition_row.id,
      'idempotencyKey', normalized_idempotency_key
    )
  );
  result_payload := pg_catalog.jsonb_build_object(
    'workflowDefinitionId', definition_row.id,
    'workflowVersionId', version_row.id,
    'revision', version_row.revision,
    'checksum', version_row.checksum,
    'approvalRecordId', approval_row.id,
    'approvedAt', approval_row.decided_at,
    'replayed', false,
    'auditEventId', new_audit_event_id
  );
  insert into public.workflow_admin_command_receipts (
    workspace_id,
    actor_user_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    workflow_definition_id,
    workflow_version_id,
    result,
    audit_event_id
  ) values (
    p_workspace_id,
    actor_user_id,
    'approve_workflow_version',
    normalized_idempotency_key,
    request_fingerprint,
    definition_row.id,
    version_row.id,
    result_payload,
    new_audit_event_id
  );
  return result_payload;
end;
$$;

-- M3-WF-AC-004: activation is an optimistic, approved, recent-AAL2 command.
-- The previously active version retires in the same transaction; existing
-- instances remain pinned to that retired immutable version.
create function app.activate_workflow_version_admin(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_workflow_version_id uuid,
  p_expected_revision bigint,
  p_expected_checksum text,
  p_reason text,
  p_request_id text default null,
  p_correlation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_reason text;
  version_row public.workflow_versions%rowtype;
  definition_row public.workflow_definitions%rowtype;
  target_definition_key text;
  previous_active_version_id uuid;
  activated_at_value timestamptz;
  request_fingerprint text;
  existing_receipt public.workflow_admin_command_receipts%rowtype;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  perform app.assert_configuration_command_authority(
    p_workspace_id,
    'workflow.activate',
    true
  );
  if not app.workspace_entitlement_is_enabled(
    p_workspace_id,
    'custom_workflows',
    pg_catalog.statement_timestamp()
  ) then
    raise exception using
      errcode = '42501',
      message = 'custom workflows entitlement is not active';
  end if;

  actor_user_id := app.configuration_actor_id();
  if actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'workflow activation requires an authenticated human actor';
  end if;
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid workflow idempotency key';
  end if;
  if pg_catalog.char_length(normalized_reason) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'workflow activation reason is required';
  end if;
  if p_expected_revision is null or p_expected_revision < 1
    or coalesce(p_expected_checksum, '') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'invalid expected workflow version';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'workflow request ID is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'workflow correlation ID is required';
  end if;

  request_fingerprint := app.configuration_payload_checksum(
    pg_catalog.jsonb_build_object(
      'command', 'activate_workflow_version',
      'workflowVersionId', p_workflow_version_id,
      'expectedRevision', p_expected_revision,
      'expectedChecksum', p_expected_checksum,
      'reason', normalized_reason,
      'requestId', p_request_id,
      'correlationId', p_correlation_id
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1factivate_workflow_version\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );
  select receipt.*
    into existing_receipt
  from public.workflow_admin_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'activate_workflow_version'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'workflow idempotency key was used for different activation input';
    end if;
    return existing_receipt.result || '{"replayed":true}'::jsonb;
  end if;

  select definition.key::text
    into target_definition_key
  from public.workflow_versions version
  join public.workflow_definitions definition
    on definition.workspace_id = version.workspace_id
   and definition.id = version.workflow_definition_id
  where version.workspace_id = p_workspace_id
    and version.id = p_workflow_version_id;
  if not found then
    raise exception using errcode = '23503', message = 'workflow version does not exist';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workflow_definition:' || p_workspace_id::text || ':' || target_definition_key,
      0
    )
  );
  select version.*
    into version_row
  from public.workflow_versions version
  where version.workspace_id = p_workspace_id
    and version.id = p_workflow_version_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'workflow version does not exist';
  end if;
  select definition.*
    into definition_row
  from public.workflow_definitions definition
  where definition.workspace_id = version_row.workspace_id
    and definition.id = version_row.workflow_definition_id
  for update;

  if definition_row.status <> 'active' or version_row.status <> 'draft' then
    raise exception using errcode = '23514', message = 'only an active definition draft can activate';
  end if;
  if version_row.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'workflow revision conflict';
  end if;
  if version_row.checksum <> p_expected_checksum
    or app.configuration_payload_checksum(
      app.workflow_version_artifact(p_workspace_id, version_row.id)
    ) <> p_expected_checksum then
    raise exception using errcode = '23514', message = 'workflow checksum mismatch';
  end if;
  if not app.workflow_version_has_valid_approval(
    p_workspace_id,
    version_row.id,
    pg_catalog.statement_timestamp()
  ) then
    raise exception using
      errcode = '23514',
      message = 'workflow activation requires an exact current approval';
  end if;

  perform 1
  from public.workflow_versions version
  where version.workspace_id = p_workspace_id
    and version.workflow_definition_id = definition_row.id
  order by version.revision
  for update;

  select version.id
    into previous_active_version_id
  from public.workflow_versions version
  where version.workspace_id = p_workspace_id
    and version.workflow_definition_id = definition_row.id
    and version.status = 'active'
    and version.id <> version_row.id;

  activated_at_value := pg_catalog.statement_timestamp();
  if previous_active_version_id is not null then
    update public.workflow_versions
    set status = 'retired',
        retired_at = activated_at_value
    where workspace_id = p_workspace_id
      and id = previous_active_version_id;
  end if;
  update public.workflow_versions
  set status = 'active',
      activated_at = activated_at_value
  where workspace_id = p_workspace_id
    and id = version_row.id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'workflow.version_activated',
    p_entity_type => 'workflow_version',
    p_entity_id => version_row.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', version_row.status,
      'revision', version_row.revision,
      'checksum', version_row.checksum,
      'previousActiveVersionId', previous_active_version_id
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'active',
      'revision', version_row.revision,
      'checksum', version_row.checksum,
      'activatedAt', activated_at_value
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'workflowDefinitionId', definition_row.id,
      'approvalRecordId', version_row.approval_record_id,
      'idempotencyKey', normalized_idempotency_key
    )
  );
  result_payload := pg_catalog.jsonb_build_object(
    'workflowDefinitionId', definition_row.id,
    'workflowVersionId', version_row.id,
    'revision', version_row.revision,
    'checksum', version_row.checksum,
    'previousActiveVersionId', previous_active_version_id,
    'activatedAt', activated_at_value,
    'replayed', false,
    'auditEventId', new_audit_event_id
  );
  insert into public.workflow_admin_command_receipts (
    workspace_id,
    actor_user_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    workflow_definition_id,
    workflow_version_id,
    result,
    audit_event_id
  ) values (
    p_workspace_id,
    actor_user_id,
    'activate_workflow_version',
    normalized_idempotency_key,
    request_fingerprint,
    definition_row.id,
    version_row.id,
    result_payload,
    new_audit_event_id
  );
  return result_payload;
end;
$$;

revoke all on table public.workflow_admin_command_receipts
  from public, anon, authenticated, service_role;
grant select on table public.workflow_admin_command_receipts to service_role;

revoke all on function app.workflow_required_fields_valid(text[])
  from public, anon, authenticated, service_role;
revoke all on function app.workflow_guard_allowed_for_entity(text, text)
  from public, anon, authenticated, service_role;
revoke all on function app.workflow_effect_allowed_for_entity(text, text)
  from public, anon, authenticated, service_role;
revoke all on function app.prevent_workflow_admin_receipt_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.workflow_version_artifact(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.assert_workflow_configuration_payload(text, jsonb, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.assert_workflow_semantic_flags(text, jsonb, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.validate_workflow_state_configuration()
  from public, anon, authenticated, service_role;
revoke all on function app.validate_workflow_transition_configuration()
  from public, anon, authenticated, service_role;
revoke all on function app.workflow_version_has_valid_approval(uuid, uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function app.workspace_entitlement_is_enabled(uuid, text, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function app.protect_activated_workflow_configuration()
  from public, anon, authenticated, service_role;
revoke all on function app.validate_workflow_version_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app.populate_workflow_event_snapshots()
  from public, anon, authenticated, service_role;

revoke all on function app.workflow_entity_read_permission(text)
  from public, anon, authenticated, service_role;
revoke all on function app.can_read_workflow_entity(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.can_read_workflow_definition(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.can_read_workflow_version(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function app.can_read_workflow_entity(uuid, text)
  to authenticated;
grant execute on function app.can_read_workflow_definition(uuid, uuid)
  to authenticated;
grant execute on function app.can_read_workflow_version(uuid, uuid)
  to authenticated;

revoke all on function app.workflow_configuration_artifact(
  text, text, text, text, integer, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
revoke all on function app.workflow_configuration_checksum(
  text, text, text, text, integer, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function app.workflow_configuration_artifact(
  text, text, text, text, integer, text, jsonb, jsonb
) to authenticated;
grant execute on function app.workflow_configuration_checksum(
  text, text, text, text, integer, text, jsonb, jsonb
) to authenticated;

revoke all on function app.read_workflow_definition_admin(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.create_workflow_version_admin(
  uuid, text, text, text, text, text, integer, text, jsonb, jsonb,
  text, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.approve_workflow_version_admin(
  uuid, text, uuid, bigint, text, text, timestamptz, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.activate_workflow_version_admin(
  uuid, text, uuid, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.read_workflow_definition_admin(uuid, uuid)
  to authenticated;
grant execute on function app.create_workflow_version_admin(
  uuid, text, text, text, text, text, integer, text, jsonb, jsonb,
  text, uuid, text, text, uuid
) to authenticated;
grant execute on function app.approve_workflow_version_admin(
  uuid, text, uuid, bigint, text, text, timestamptz, text, uuid
) to authenticated;
grant execute on function app.activate_workflow_version_admin(
  uuid, text, uuid, bigint, text, text, text, uuid
) to authenticated;

comment on table public.workflow_admin_command_receipts is
  'M3 actor-scoped append-only idempotency receipts for workflow administration.';
comment on column public.workflow_versions.revision is
  'Monotonic approval version within a workspace workflow definition.';
comment on column public.workflow_states.required_fields is
  'Declarative field keys required when entering this state; never executable code.';
comment on column public.workflow_transitions.required_fields is
  'Declarative field keys required by this transition; never executable code.';
comment on column public.workflow_events.input_snapshot is
  'Non-sensitive immutable transition-decision metadata captured at event insertion.';
comment on column public.workflow_events.effect_snapshot is
  'Immutable allowlisted inert effect declarations captured at event insertion.';
comment on function app.create_workflow_version_admin(
  uuid, text, text, text, text, text, integer, text, jsonb, jsonb,
  text, uuid, text, text, uuid
) is 'M3-WF-AC-004 entitlement-gated recent-AAL2 atomic workflow draft creation.';
comment on function app.approve_workflow_version_admin(
  uuid, text, uuid, bigint, text, text, timestamptz, text, uuid
) is 'M3-WF-AC-004 entitlement-gated recent-AAL2 exact-checksum workflow approval.';
comment on function app.activate_workflow_version_admin(
  uuid, text, uuid, bigint, text, text, text, uuid
) is 'M3-WF-AC-004 entitlement-gated recent-AAL2 approved optimistic workflow activation.';
