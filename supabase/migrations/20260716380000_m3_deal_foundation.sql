-- VYN-DEAL-001, VYN-WF-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001,
-- VYN-JOB-001, VYN-API-001, STD-DEAL-001
-- M3-DEAL-AC-001, M3-DEAL-AC-002, M3-DEAL-AC-004
-- T-DEAL-001, T-TEN-001, T-RBAC-001, T-AUD-001
--
-- Configurable deal foundation. This migration deliberately stops before
-- trade-in detail, finance applications, payment transactions, calculation,
-- tax, official documents, exports, or any recurring servicing behavior.

create function app.deal_configuration_keys_valid(candidate text[])
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.cardinality(candidate) between 1 and 64
    and pg_catalog.cardinality(candidate) = (
      select pg_catalog.count(distinct entry.value)
      from pg_catalog.unnest(candidate) entry(value)
    )
    and not exists (
      select 1
      from pg_catalog.unnest(candidate) entry(value)
      where entry.value is null
        or entry.value !~ '^[a-z][a-z0-9_.-]{0,127}$'
        or pg_catalog.string_to_array(entry.value, '.')
          && array['__proto__', 'constructor', 'prototype']::text[]
    );
$$;

create function app.deal_type_configuration_artifact(
  p_key text,
  p_version text,
  p_schema_version integer,
  p_labels jsonb,
  p_option_labels jsonb,
  p_sections jsonb,
  p_field_schema jsonb,
  p_allowed_participant_roles text[],
  p_allowed_inventory_roles text[],
  p_behavior_flags jsonb,
  p_workflow_definition_key text,
  p_workflow_version text,
  p_workflow_checksum text
)
returns jsonb
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'key', p_key,
    'version', p_version,
    'schemaVersion', p_schema_version,
    'labels', p_labels,
    'optionLabels', p_option_labels,
    'sections', p_sections,
    'fields', p_field_schema,
    'allowedParticipantRoles', (
      select pg_catalog.to_jsonb(pg_catalog.array_agg(role_key order by role_key))
      from pg_catalog.unnest(p_allowed_participant_roles) role(role_key)
    ),
    'allowedInventoryRoles', (
      select pg_catalog.to_jsonb(pg_catalog.array_agg(role_key order by role_key))
      from pg_catalog.unnest(p_allowed_inventory_roles) role(role_key)
    ),
    'behavior', p_behavior_flags,
    'workflow', pg_catalog.jsonb_build_object(
      'key', p_workflow_definition_key,
      'version', p_workflow_version,
      'checksum', p_workflow_checksum
    )
  );
$$;

create function app.deal_type_configuration_checksum(
  p_key text,
  p_version text,
  p_schema_version integer,
  p_labels jsonb,
  p_option_labels jsonb,
  p_sections jsonb,
  p_field_schema jsonb,
  p_allowed_participant_roles text[],
  p_allowed_inventory_roles text[],
  p_behavior_flags jsonb,
  p_workflow_definition_key text,
  p_workflow_version text,
  p_workflow_checksum text
)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select app.configuration_payload_checksum(
    app.deal_type_configuration_artifact(
      p_key,
      p_version,
      p_schema_version,
      p_labels,
      p_option_labels,
      p_sections,
      p_field_schema,
      p_allowed_participant_roles,
      p_allowed_inventory_roles,
      p_behavior_flags,
      p_workflow_definition_key,
      p_workflow_version,
      p_workflow_checksum
    )
  );
$$;

create table public.deal_type_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null check (
    pg_catalog.char_length(key::text) <= 128
    and key::text ~ '^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})*$'
  ),
  status text not null default 'active' check (status in ('active', 'retired')),
  created_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key)
);

create table public.deal_type_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  deal_type_definition_id uuid not null,
  version text not null check (
    pg_catalog.char_length(version) between 5 and 64
    and version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'
  ),
  revision bigint not null check (revision > 0),
  schema_version integer not null default 1 check (schema_version > 0),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and labels ?& array['en', 'fr']
    and pg_catalog.jsonb_typeof(labels -> 'en') = 'string'
    and pg_catalog.jsonb_typeof(labels -> 'fr') = 'string'
    and pg_catalog.btrim(labels ->> 'en') <> ''
    and pg_catalog.btrim(labels ->> 'fr') <> ''
    and pg_catalog.char_length(labels ->> 'en') <= 200
    and pg_catalog.char_length(labels ->> 'fr') <= 200
  ),
  option_labels jsonb not null check (
    pg_catalog.jsonb_typeof(option_labels) = 'object'
    and option_labels ?& array[
      'participant_roles', 'inventory_roles', 'one_time_event_types'
    ]
    and pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(option_labels, '$.keyvalue()')) = 3
    and pg_catalog.octet_length(option_labels::text) <= 65536
    and not app.custom_field_json_has_executable_key(option_labels)
  ),
  sections jsonb not null default '[]'::jsonb check (
    pg_catalog.jsonb_typeof(sections) = 'array'
    and pg_catalog.jsonb_array_length(sections) <= 64
    and pg_catalog.octet_length(sections::text) <= 65536
    and not app.custom_field_json_has_executable_key(sections)
  ),
  field_schema jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(field_schema) = 'object'
    and pg_catalog.octet_length(field_schema::text) <= 65536
    and not app.custom_field_json_has_executable_key(field_schema)
  ),
  allowed_participant_roles text[] not null check (
    app.deal_configuration_keys_valid(allowed_participant_roles)
  ),
  allowed_inventory_roles text[] not null check (
    app.deal_configuration_keys_valid(allowed_inventory_roles)
  ),
  behavior_flags jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(behavior_flags) = 'object'
    and pg_catalog.octet_length(behavior_flags::text) <= 16384
    and not app.custom_field_json_has_executable_key(behavior_flags)
    and coalesce(behavior_flags ->> 'finance_mode', 'none') in (
      'none', 'external_lender_tracking'
    )
    and coalesce(behavior_flags ->> 'money_mode', 'one_time') = 'one_time'
    and coalesce(behavior_flags ->> 'inventory_direction', 'mixed') in (
      'inbound', 'outbound', 'mixed'
    )
    and coalesce(behavior_flags ->> 'inventory_creation', 'none') in (
      'none', 'explicit_confirmation'
    )
  ),
  workflow_version_id uuid not null,
  status text not null default 'draft' check (status in ('draft', 'active', 'retired')),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  source text not null default 'configuration' check (
    source in ('configuration', 'starter_pack', 'migration_compatibility')
  ),
  created_by uuid references auth.users (id) on delete restrict,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, deal_type_definition_id, version),
  unique (workspace_id, deal_type_definition_id, revision),
  foreign key (workspace_id, deal_type_definition_id)
    references public.deal_type_definitions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id) on delete restrict,
  check (
    (status = 'draft' and activated_at is null and retired_at is null)
    or (status = 'active' and activated_at is not null and retired_at is null)
    or (status = 'retired' and retired_at is not null)
  )
);

create unique index deal_type_versions_active_definition_uidx
  on public.deal_type_versions (workspace_id, deal_type_definition_id)
  where status = 'active';

create index deal_type_versions_workflow_idx
  on public.deal_type_versions (workspace_id, workflow_version_id, status);

create function app.deal_type_version_artifact(
  p_workspace_id uuid,
  p_deal_type_version_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select app.deal_type_configuration_artifact(
    definition.key::text,
    version.version,
    version.schema_version,
    version.labels,
    version.option_labels,
    version.sections,
    version.field_schema,
    version.allowed_participant_roles,
    version.allowed_inventory_roles,
    version.behavior_flags,
    workflow_definition.key::text,
    workflow_version.version,
    workflow_version.checksum
  )
  from public.deal_type_versions version
  join public.deal_type_definitions definition
    on definition.workspace_id = version.workspace_id
   and definition.id = version.deal_type_definition_id
  join public.workflow_versions workflow_version
    on workflow_version.workspace_id = version.workspace_id
   and workflow_version.id = version.workflow_version_id
  join public.workflow_definitions workflow_definition
    on workflow_definition.workspace_id = workflow_version.workspace_id
   and workflow_definition.id = workflow_version.workflow_definition_id
  where version.workspace_id = p_workspace_id
    and version.id = p_deal_type_version_id;
$$;

create function app.validate_deal_type_version_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_revision bigint;
  current_artifact jsonb;
  workflow_entity_type text;
  workflow_status text;
begin
  if tg_op = 'INSERT' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'deal_type_revision:' || new.workspace_id::text || ':'
          || new.deal_type_definition_id::text,
        0
      )
    );
    select coalesce(pg_catalog.max(version.revision), 0) + 1
      into expected_revision
    from public.deal_type_versions version
    where version.workspace_id = new.workspace_id
      and version.deal_type_definition_id = new.deal_type_definition_id;
    if new.revision <> expected_revision then
      raise exception using errcode = '23514', message = 'deal type revision is not the next immutable revision';
    end if;
    if new.source = 'migration_compatibility'
      and app.configuration_invoker_role() in ('postgres', 'supabase_admin')
      and new.status = 'retired'
      and new.activated_at is null
      and new.retired_at is not null then
      return new;
    end if;
    if new.status <> 'draft' or new.activated_at is not null or new.retired_at is not null then
      raise exception using errcode = '23514', message = 'deal type version must start as a draft';
    end if;
    return new;
  end if;

  if old.status = 'draft' and new.status = 'draft' then
    if new.activated_at is not null or new.retired_at is not null then
      raise exception using errcode = '23514', message = 'draft deal type timestamps are invalid';
    end if;
    return new;
  end if;

  if old.status = 'draft' and new.status = 'active' then
    if new.activated_at is null or new.retired_at is not null then
      raise exception using errcode = '23514', message = 'deal type activation timestamps are invalid';
    end if;
    if not exists (
      select 1 from public.deal_type_definitions definition
      where definition.workspace_id = new.workspace_id
        and definition.id = new.deal_type_definition_id
        and definition.status = 'active'
    ) then
      raise exception using errcode = '23514', message = 'deal type definition must be active';
    end if;
    select workflow_definition.entity_type, workflow_version.status
      into workflow_entity_type, workflow_status
    from public.workflow_versions workflow_version
    join public.workflow_definitions workflow_definition
      on workflow_definition.workspace_id = workflow_version.workspace_id
     and workflow_definition.id = workflow_version.workflow_definition_id
    where workflow_version.workspace_id = new.workspace_id
      and workflow_version.id = new.workflow_version_id
      and workflow_definition.status = 'active';
    if workflow_entity_type is distinct from 'deal' or workflow_status is distinct from 'active' then
      raise exception using errcode = '23514', message = 'deal type must pin an active deal workflow version';
    end if;
    current_artifact := app.deal_type_version_artifact(new.workspace_id, new.id);
    if current_artifact is null
      or app.configuration_payload_checksum(current_artifact) <> new.checksum then
      raise exception using errcode = '23514', message = 'deal type checksum does not match persisted configuration';
    end if;
    return new;
  end if;

  if old.status = 'active' and new.status = 'retired' then
    if new.activated_at is distinct from old.activated_at
      or new.retired_at is null
      or new.retired_at < old.activated_at then
      raise exception using errcode = '23514', message = 'deal type retirement timestamps are invalid';
    end if;
    if pg_catalog.to_jsonb(new) - array['status', 'retired_at']::text[]
      is distinct from pg_catalog.to_jsonb(old) - array['status', 'retired_at']::text[] then
      raise exception using errcode = '55000', message = 'activated deal type configuration is immutable';
    end if;
    return new;
  end if;

  raise exception using errcode = '23514', message = 'deal type lifecycle transition is not allowed';
end;
$$;

create function app.protect_deal_type_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and old.status in ('active', 'retired') then
    raise exception using errcode = '55000', message = 'activated deal type configuration is immutable';
  end if;
  if tg_op = 'UPDATE' and old.status = 'retired' then
    raise exception using errcode = '55000', message = 'retired deal type configuration is immutable';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger deal_type_versions_validate_lifecycle
before insert or update on public.deal_type_versions
for each row execute function app.validate_deal_type_version_lifecycle();

create trigger deal_type_versions_protect_activated
before update or delete on public.deal_type_versions
for each row execute function app.protect_deal_type_version();

create trigger deal_type_definitions_immutable
before update on public.deal_type_definitions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'created_by', 'created_at'
);

create trigger deal_type_definitions_prevent_hard_delete
before delete on public.deal_type_definitions
for each row execute function app.prevent_hard_delete();

-- Exact deal context. The lead migration adds the composite originating-lead
-- foreign key after public.leads exists; this column is intentionally passive
-- here and commands only preserve caller-supplied same-workspace provenance.
alter table public.deals
  drop constraint deals_status_check;

alter table public.deals
  add constraint deals_status_check check (
    status in ('draft', 'active', 'pending', 'closed', 'archived')
  ) not valid,
  add column lifecycle_status text not null default 'active' check (
    lifecycle_status in ('active', 'completed')
  ),
  add column deal_type_definition_id uuid,
  add column deal_type_version_id uuid,
  add column workflow_version_id uuid,
  add column workflow_instance_id uuid,
  add column workflow_state_key text check (
    workflow_state_key is null or workflow_state_key ~ '^[a-z][a-z0-9_]{0,127}$'
  ),
  add column location_id uuid,
  add column legal_entity_id uuid,
  add column originating_lead_id uuid,
  add column effective_at timestamptz,
  add column completed_at timestamptz,
  add column cancelled_at timestamptz,
  add column closed_reason text check (
    closed_reason is null or (
      pg_catalog.btrim(closed_reason) <> ''
      and pg_catalog.char_length(closed_reason) <= 2000
    )
  ),
  add constraint deals_deal_type_definition_fk
    foreign key (workspace_id, deal_type_definition_id)
    references public.deal_type_definitions (workspace_id, id) on delete restrict,
  add constraint deals_deal_type_version_fk
    foreign key (workspace_id, deal_type_version_id)
    references public.deal_type_versions (workspace_id, id) on delete restrict,
  add constraint deals_workflow_version_fk
    foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id) on delete restrict,
  add constraint deals_workflow_instance_fk
    foreign key (workspace_id, workflow_instance_id)
    references public.workflow_instances (workspace_id, id) on delete restrict,
  add constraint deals_location_fk
    foreign key (workspace_id, location_id)
    references public.locations (workspace_id, id) on delete restrict,
  add constraint deals_legal_entity_fk
    foreign key (workspace_id, legal_entity_id)
    references public.legal_entities (workspace_id, id) on delete restrict,
  add constraint deals_lifecycle_check check (
    (lifecycle_status = 'active' and completed_at is null)
    or (lifecycle_status = 'completed' and completed_at is not null)
  ),
  add constraint deals_cancelled_timestamp_check check (
    cancelled_at is null or lifecycle_status = 'completed'
  );

create index deals_workspace_type_state_idx
  on public.deals (
    workspace_id, deal_type_version_id, status, workflow_state_key,
    updated_at desc, id
  );

create index deals_workspace_owner_idx
  on public.deals (workspace_id, owner_membership_id, updated_at desc, id);

create index deals_originating_lead_idx
  on public.deals (workspace_id, originating_lead_id)
  where originating_lead_id is not null;

alter table public.deal_participants
  add column status text not null default 'active' check (status in ('active', 'released')),
  add column version bigint not null default 1 check (version > 0),
  add column created_by uuid references auth.users (id) on delete restrict,
  add column released_by uuid references auth.users (id) on delete restrict,
  add column released_at timestamptz,
  add constraint deal_participants_release_check check (
    (status = 'active' and released_by is null and released_at is null)
    or (status = 'released' and released_by is not null and released_at is not null)
  );

create unique index deal_participants_active_primary_role_uidx
  on public.deal_participants (workspace_id, deal_id, role_key)
  where status = 'active' and is_primary;

alter table public.deal_inventory_units
  add column amount_minor bigint,
  add column currency_code char(3) check (
    currency_code is null or currency_code ~ '^[A-Z]{3}$'
  ),
  add column metadata jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(metadata) = 'object'
    and not app.job_payload_contains_forbidden_key(metadata)
  ),
  add column version bigint not null default 1 check (version > 0),
  add column created_by uuid references auth.users (id) on delete restrict,
  add column released_by uuid references auth.users (id) on delete restrict,
  add column released_at timestamptz;

create table public.deal_line_items (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  deal_id uuid not null,
  key text not null check (key ~ '^[a-z][a-z0-9_.-]{0,127}$'),
  item_type text not null check (
    item_type in ('vehicle', 'fee', 'discount', 'accessory', 'service', 'other')
  ),
  label text not null check (
    pg_catalog.btrim(label) <> '' and pg_catalog.char_length(label) <= 200
  ),
  quantity_text text not null check (
    quantity_text ~ '^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$'
    and quantity_text::numeric > 0
  ),
  quantity numeric(18, 6) generated always as (quantity_text::numeric) stored,
  unit_amount_minor bigint not null,
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
  tax_classification_key text check (
    tax_classification_key is null
    or tax_classification_key ~ '^[a-z][a-z0-9_.-]{0,127}$'
  ),
  payment_timing_key text check (
    payment_timing_key is null
    or payment_timing_key ~ '^[a-z][a-z0-9_.-]{0,127}$'
  ),
  sort_order integer not null default 0 check (sort_order >= 0),
  source_key text check (
    source_key is null or source_key ~ '^[a-z][a-z0-9_.-]{0,127}$'
  ),
  source_reference text check (
    source_reference is null or pg_catalog.char_length(source_reference) <= 500
  ),
  status text not null default 'active' check (status in ('active', 'released')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_by uuid not null references auth.users (id) on delete restrict,
  released_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  released_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, deal_id, key),
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  check (
    (status = 'active' and released_by is null and released_at is null)
    or (status = 'released' and released_by is not null and released_at is not null)
  )
);

create index deal_line_items_deal_order_idx
  on public.deal_line_items (workspace_id, deal_id, status, sort_order, id);

create table public.deal_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  command_type text not null check (command_type in (
    'm3_create_deal', 'm3_update_deal', 'm3_transition_deal',
    'm3_add_deal_participant', 'm3_release_deal_participant',
    'm3_add_deal_inventory', 'm3_release_deal_inventory',
    'm3_add_deal_line_item', 'm3_update_deal_line_item'
  )),
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  deal_id uuid not null,
  aggregate_version bigint not null check (aggregate_version > 0),
  result jsonb not null check (
    pg_catalog.jsonb_typeof(result) = 'object'
    and not app.job_payload_contains_forbidden_key(result)
  ),
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, command_type, idempotency_key),
  unique (workspace_id, audit_event_id),
  unique (workspace_id, outbox_event_id),
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict
);

create index deal_command_receipts_deal_idx
  on public.deal_command_receipts (workspace_id, deal_id, created_at desc);

create function app.prevent_deal_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'deal command history is append-only';
end;
$$;

create trigger deal_command_receipts_append_only
before update or delete on public.deal_command_receipts
for each row execute function app.prevent_deal_history_mutation();

create trigger deal_line_items_updated_at
before update on public.deal_line_items
for each row execute function app.set_updated_at();

create trigger deal_line_items_immutable_ownership
before update on public.deal_line_items
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'deal_id', 'key', 'created_by', 'created_at'
);

create trigger deal_line_items_prevent_hard_delete
before delete on public.deal_line_items
for each row execute function app.prevent_hard_delete();

create function app.require_deal_permission(
  p_workspace_id uuid,
  p_permission_key text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
begin
  actor_user_id := auth.uid();
  if actor_user_id is null
    or not app.is_feature_entitled(
      p_workspace_id, 'deals', pg_catalog.statement_timestamp()
    )
    or not app.has_permission(p_workspace_id, p_permission_key) then
    raise exception using
      errcode = '42501',
      message = 'active deals entitlement, membership, and permission are required';
  end if;
  return actor_user_id;
end;
$$;

create function app.can_read_deal_workspace(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.is_feature_entitled(
      p_workspace_id, 'deals', pg_catalog.statement_timestamp()
    )
    and app.has_permission(p_workspace_id, 'deals.read');
$$;

create function app.deal_command_fingerprint(payload jsonb)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select app.configuration_payload_checksum(payload);
$$;

create function app.assert_deal_command_metadata(
  p_idempotency_key text,
  p_correlation_id uuid
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  normalized_key text;
begin
  normalized_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  if normalized_key <> coalesce(p_idempotency_key, '')
    or pg_catalog.char_length(normalized_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid deal idempotency key';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  return normalized_key;
end;
$$;

create function app.lock_deal_command(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_command_type text,
  p_idempotency_key text
)
returns void
language sql
volatile
set search_path = ''
as $$
  select pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1f' || p_actor_user_id::text || E'\x1f'
        || p_command_type || E'\x1f' || p_idempotency_key,
      0
    )
  );
$$;

create function app.append_deal_outbox_event(
  p_workspace_id uuid,
  p_event_name text,
  p_deal_id uuid,
  p_aggregate_version bigint,
  p_payload jsonb,
  p_actor_user_id uuid,
  p_correlation_id uuid,
  p_causation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_event_id uuid;
begin
  if p_event_name !~ '^deal\.[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or p_aggregate_version < 1
    or p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or app.job_payload_contains_forbidden_key(p_payload)
    or p_correlation_id is null then
    raise exception using errcode = '23514', message = 'deal outbox metadata is invalid';
  end if;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, actor_user_id,
    correlation_id, causation_id
  ) values (
    p_workspace_id, p_event_name, 'deal', p_deal_id,
    p_aggregate_version, 1, p_payload, p_actor_user_id,
    p_correlation_id, p_causation_id
  )
  returning id into new_event_id;
  return new_event_id;
end;
$$;

create function app.record_deal_command_receipt(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_command_type text,
  p_idempotency_key text,
  p_command_fingerprint text,
  p_deal_id uuid,
  p_aggregate_version bigint,
  p_result jsonb,
  p_audit_event_id uuid,
  p_outbox_event_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.deal_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, deal_id, aggregate_version, result,
    audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, p_actor_user_id, p_command_type, p_idempotency_key,
    p_command_fingerprint, p_deal_id, p_aggregate_version, p_result,
    p_audit_event_id, p_outbox_event_id
  );
$$;

create function app.assert_deal_type_configuration()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  required_entry jsonb;
  optional_entry jsonb;
  event_entry jsonb;
  configured_keys text[];
  option_entry record;
  option_group text;
begin
  if exists (
    select 1
    from pg_catalog.jsonb_object_keys(new.field_schema) property(key)
    where property.key not in ('required', 'optional')
  ) then
    raise exception using errcode = '23514', message = 'deal type field schema has unsupported properties';
  end if;
  if coalesce(pg_catalog.jsonb_typeof(new.field_schema -> 'required'), 'array') <> 'array'
    or coalesce(pg_catalog.jsonb_typeof(new.field_schema -> 'optional'), 'array') <> 'array' then
    raise exception using errcode = '23514', message = 'deal type fields must be arrays';
  end if;
  if pg_catalog.jsonb_array_length(
      coalesce(new.field_schema -> 'required', '[]'::jsonb)
    ) > 128
    or pg_catalog.jsonb_array_length(
      coalesce(new.field_schema -> 'optional', '[]'::jsonb)
    ) > 128 then
    raise exception using errcode = '23514', message = 'deal type field arrays exceed the configured limit';
  end if;
  for required_entry in
    select entry.value
    from pg_catalog.jsonb_array_elements(coalesce(new.field_schema -> 'required', '[]'::jsonb)) entry(value)
  loop
    if pg_catalog.jsonb_typeof(required_entry) <> 'string'
      or required_entry #>> '{}' !~ '^[a-z][a-z0-9_.-]{0,127}$' then
      raise exception using errcode = '23514', message = 'invalid required deal field key';
    end if;
  end loop;
  for optional_entry in
    select entry.value
    from pg_catalog.jsonb_array_elements(coalesce(new.field_schema -> 'optional', '[]'::jsonb)) entry(value)
  loop
    if pg_catalog.jsonb_typeof(optional_entry) <> 'string'
      or optional_entry #>> '{}' !~ '^[a-z][a-z0-9_.-]{0,127}$' then
      raise exception using errcode = '23514', message = 'invalid optional deal field key';
    end if;
  end loop;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(coalesce(new.field_schema -> 'required', '[]'::jsonb)) required_field(value)
    join pg_catalog.jsonb_array_elements_text(coalesce(new.field_schema -> 'optional', '[]'::jsonb)) optional_field(value)
      on optional_field.value = required_field.value
  ) then
    raise exception using errcode = '23514', message = 'deal fields cannot be both required and optional';
  end if;
  if exists (
    select 1
    from (
      select field.value
      from pg_catalog.jsonb_array_elements_text(
        coalesce(new.field_schema -> 'required', '[]'::jsonb)
      ) field(value)
      group by field.value
      having pg_catalog.count(*) > 1
      union all
      select field.value
      from pg_catalog.jsonb_array_elements_text(
        coalesce(new.field_schema -> 'optional', '[]'::jsonb)
      ) field(value)
      group by field.value
      having pg_catalog.count(*) > 1
    ) duplicate_field
  ) then
    raise exception using errcode = '23514', message = 'deal type fields must be unique';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_object_keys(new.behavior_flags) property(key)
    where property.key not in (
      'inventory_direction', 'inventory_creation', 'finance_mode',
      'money_mode', 'one_time_event_types'
    )
  ) then
    raise exception using errcode = '23514', message = 'deal type behavior has unsupported properties';
  end if;
  if new.behavior_flags ? 'one_time_event_types' then
    if pg_catalog.jsonb_typeof(new.behavior_flags -> 'one_time_event_types') <> 'array' then
      raise exception using errcode = '23514', message = 'one-time event types must be a bounded array';
    end if;
    if pg_catalog.jsonb_array_length(new.behavior_flags -> 'one_time_event_types') > 32 then
      raise exception using errcode = '23514', message = 'one-time event types must be a bounded array';
    end if;
    for event_entry in
      select entry.value
      from pg_catalog.jsonb_array_elements(new.behavior_flags -> 'one_time_event_types') entry(value)
    loop
      if pg_catalog.jsonb_typeof(event_entry) <> 'string'
        or event_entry #>> '{}' !~ '^[a-z][a-z0-9_.-]{0,127}$'
        or pg_catalog.lower(event_entry #>> '{}') ~ '(recurr|installment|repayment|interest|principal|servic|late_fee|collection|repossession)' then
        raise exception using errcode = '23514', message = 'deal type permits only one-time money event keys';
      end if;
    end loop;
    if exists (
      select 1
      from pg_catalog.jsonb_array_elements_text(
        new.behavior_flags -> 'one_time_event_types'
      ) event_type(value)
      group by event_type.value
      having pg_catalog.count(*) > 1
    ) then
      raise exception using errcode = '23514', message = 'one-time event types must be unique';
    end if;
  end if;
  foreach option_group in array array[
    'participant_roles', 'inventory_roles', 'one_time_event_types'
  ]::text[]
  loop
    if pg_catalog.jsonb_typeof(new.option_labels -> option_group) <> 'object' then
      raise exception using errcode = '23514', message = 'deal option labels must be grouped objects';
    end if;
    configured_keys := case option_group
      when 'participant_roles' then new.allowed_participant_roles
      when 'inventory_roles' then new.allowed_inventory_roles
      else array(
        select event_type.value
        from pg_catalog.jsonb_array_elements_text(
          coalesce(new.behavior_flags -> 'one_time_event_types', '[]'::jsonb)
        ) with ordinality event_type(value, position)
        order by event_type.position
      )
    end;
    if pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(new.option_labels -> option_group, '$.keyvalue()'))
        <> pg_catalog.cardinality(configured_keys)
      or exists (
        select 1
        from pg_catalog.unnest(configured_keys) configured(key)
        where not (new.option_labels -> option_group ? configured.key)
      )
      or exists (
        select 1
        from pg_catalog.jsonb_object_keys(
          new.option_labels -> option_group
        ) configured_label(key)
        where not (configured_label.key = any(configured_keys))
      ) then
      raise exception using errcode = '23514', message = 'deal option labels must exactly match configured keys';
    end if;
    for option_entry in
      select localized.key, localized.value
      from pg_catalog.jsonb_each(
        new.option_labels -> option_group
      ) localized(key, value)
    loop
      if pg_catalog.jsonb_typeof(option_entry.value) <> 'object'
        or pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(option_entry.value, '$.keyvalue()')) <> 2
        or not (option_entry.value ?& array['en', 'fr'])
        or pg_catalog.jsonb_typeof(option_entry.value -> 'en') <> 'string'
        or pg_catalog.jsonb_typeof(option_entry.value -> 'fr') <> 'string'
        or pg_catalog.btrim(option_entry.value ->> 'en') = ''
        or pg_catalog.btrim(option_entry.value ->> 'fr') = ''
        or pg_catalog.char_length(option_entry.value ->> 'en') > 200
        or pg_catalog.char_length(option_entry.value ->> 'fr') > 200 then
        raise exception using errcode = '23514', message = 'deal option labels require exact bounded English and French text';
      end if;
    end loop;
  end loop;
  return new;
end;
$$;

create trigger deal_type_versions_validate_configuration
before insert or update on public.deal_type_versions
for each row execute function app.assert_deal_type_configuration();

-- Migration compatibility for any M1 deal rows that predate versioned deal
-- types. They are pinned to retired configuration and a draft compatibility
-- workflow; new commands can select only active versions.
insert into public.workflow_definitions (
  id, workspace_id, key, entity_type, purpose_key, status
)
select
  pg_catalog.md5(deal.workspace_id::text || ':m3-deal-compatibility')::uuid,
  deal.workspace_id,
  'm3_deal_compatibility',
  'deal',
  'primary',
  'active'
from public.deals deal
group by deal.workspace_id
on conflict (workspace_id, key) do nothing;

insert into public.workflow_versions (
  id, workspace_id, workflow_definition_id, version, schema_version,
  initial_state_key, status, checksum, source
)
select
  pg_catalog.md5(definition.workspace_id::text || ':m3-deal-compatibility:1.0.0')::uuid,
  definition.workspace_id,
  definition.id,
  '1.0.0',
  1,
  'draft',
  'draft',
  pg_catalog.repeat('0', 64),
  'migration_compatibility'
from public.workflow_definitions definition
where definition.key = 'm3_deal_compatibility'
  and definition.entity_type = 'deal'
  and exists (
    select 1 from public.deals deal where deal.workspace_id = definition.workspace_id
  )
on conflict (workspace_id, workflow_definition_id, version) do nothing;

insert into public.workflow_states (
  id, workspace_id, workflow_version_id, key, canonical_category,
  labels, behavior_flags, required_fields, sort_order
)
select
  pg_catalog.md5(version.workspace_id::text || ':m3-deal-compatibility:state:' || fixture.key)::uuid,
  version.workspace_id,
  version.id,
  fixture.key,
  fixture.category,
  pg_catalog.jsonb_build_object('en', fixture.label_en, 'fr', fixture.label_fr),
  pg_catalog.jsonb_build_object('terminal', fixture.terminal)
    || case when fixture.key = 'cancelled'
      then '{"cancellation":true}'::jsonb else '{}'::jsonb end,
  '{}'::text[],
  fixture.sort_order
from public.workflow_versions version
join public.workflow_definitions definition
  on definition.workspace_id = version.workspace_id
 and definition.id = version.workflow_definition_id
cross join (values
  ('draft'::text, 'draft'::text, 'Draft'::text, 'Brouillon'::text, false, 10),
  ('cancelled'::text, 'closed'::text, 'Cancelled'::text, 'Annule'::text, true, 20)
) fixture(key, category, label_en, label_fr, terminal, sort_order)
where definition.key = 'm3_deal_compatibility'
  and version.status = 'draft'
on conflict (workspace_id, workflow_version_id, key) do nothing;

-- The lifecycle trigger normally requires draft insertion. A retired
-- migration-only record is allowed solely for the database owner so existing
-- aggregates can retain exact historical context without becoming selectable
-- for new business commands.
create or replace function app.validate_deal_type_version_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_revision bigint;
  current_artifact jsonb;
  workflow_entity_type text;
  workflow_status text;
begin
  if tg_op = 'INSERT' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'deal_type_revision:' || new.workspace_id::text || ':'
          || new.deal_type_definition_id::text,
        0
      )
    );
    select coalesce(pg_catalog.max(version.revision), 0) + 1
      into expected_revision
    from public.deal_type_versions version
    where version.workspace_id = new.workspace_id
      and version.deal_type_definition_id = new.deal_type_definition_id;
    if new.revision <> expected_revision then
      raise exception using errcode = '23514', message = 'deal type revision is not the next immutable revision';
    end if;
    if new.source = 'migration_compatibility'
      and app.configuration_invoker_role() in ('postgres', 'supabase_admin')
      and new.status = 'retired'
      and new.activated_at is null
      and new.retired_at is not null then
      return new;
    end if;
    if new.status <> 'draft' or new.activated_at is not null or new.retired_at is not null then
      raise exception using errcode = '23514', message = 'deal type version must start as a draft';
    end if;
    return new;
  end if;

  if old.status = 'draft' and new.status = 'draft' then
    if new.activated_at is not null or new.retired_at is not null then
      raise exception using errcode = '23514', message = 'draft deal type timestamps are invalid';
    end if;
    return new;
  end if;
  if old.status = 'draft' and new.status = 'active' then
    if new.activated_at is null or new.retired_at is not null then
      raise exception using errcode = '23514', message = 'deal type activation timestamps are invalid';
    end if;
    if not exists (
      select 1 from public.deal_type_definitions definition
      where definition.workspace_id = new.workspace_id
        and definition.id = new.deal_type_definition_id
        and definition.status = 'active'
    ) then
      raise exception using errcode = '23514', message = 'deal type definition must be active';
    end if;
    select workflow_definition.entity_type, workflow_version.status
      into workflow_entity_type, workflow_status
    from public.workflow_versions workflow_version
    join public.workflow_definitions workflow_definition
      on workflow_definition.workspace_id = workflow_version.workspace_id
     and workflow_definition.id = workflow_version.workflow_definition_id
    where workflow_version.workspace_id = new.workspace_id
      and workflow_version.id = new.workflow_version_id
      and workflow_definition.status = 'active';
    if workflow_entity_type is distinct from 'deal' or workflow_status is distinct from 'active' then
      raise exception using errcode = '23514', message = 'deal type must pin an active deal workflow version';
    end if;
    current_artifact := app.deal_type_version_artifact(new.workspace_id, new.id);
    if current_artifact is null
      or app.configuration_payload_checksum(current_artifact) <> new.checksum then
      raise exception using errcode = '23514', message = 'deal type checksum does not match persisted configuration';
    end if;
    return new;
  end if;
  if old.status = 'active' and new.status = 'retired' then
    if new.activated_at is distinct from old.activated_at
      or new.retired_at is null
      or new.retired_at < old.activated_at then
      raise exception using errcode = '23514', message = 'deal type retirement timestamps are invalid';
    end if;
    if pg_catalog.to_jsonb(new) - array['status', 'retired_at']::text[]
      is distinct from pg_catalog.to_jsonb(old) - array['status', 'retired_at']::text[] then
      raise exception using errcode = '55000', message = 'activated deal type configuration is immutable';
    end if;
    return new;
  end if;
  raise exception using errcode = '23514', message = 'deal type lifecycle transition is not allowed';
end;
$$;

insert into public.deal_type_definitions (
  id, workspace_id, key, status, created_by
)
select
  pg_catalog.md5(deal.workspace_id::text || ':m3-deal-type:' || deal.deal_type_key)::uuid,
  deal.workspace_id,
  deal.deal_type_key,
  'active',
  pg_catalog.min(deal.created_by::text)::uuid
from public.deals deal
group by deal.workspace_id, deal.deal_type_key
on conflict (workspace_id, key) do nothing;

insert into public.deal_type_versions (
  id, workspace_id, deal_type_definition_id, version, revision,
  schema_version, labels, option_labels, sections, field_schema,
  allowed_participant_roles, allowed_inventory_roles, behavior_flags,
  workflow_version_id, status, checksum, source, retired_at
)
select
  pg_catalog.md5(definition.workspace_id::text || ':m3-deal-type:' || definition.key::text || ':1.0.0')::uuid,
  definition.workspace_id,
  definition.id,
  '1.0.0',
  1,
  1,
  pg_catalog.jsonb_build_object('en', definition.key::text, 'fr', definition.key::text),
  '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"},"lender":{"en":"Lender","fr":"Prêteur"},"trade_in_owner":{"en":"Trade-in owner","fr":"Propriétaire du véhicule d’échange"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"purchased":{"en":"Purchased vehicle","fr":"Véhicule acheté"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"},"wholesale":{"en":"Wholesale vehicle","fr":"Véhicule de gros"}},"one_time_event_types":{}}'::jsonb,
  '[]'::jsonb,
  pg_catalog.jsonb_build_object('required', '[]'::jsonb, 'optional', '[]'::jsonb),
  array['buyer', 'seller', 'lender', 'trade_in_owner', 'authorized_representative']::text[],
  array['sold', 'purchased', 'trade_in', 'wholesale']::text[],
  '{"inventory_direction":"mixed","inventory_creation":"none","finance_mode":"none","money_mode":"one_time","one_time_event_types":[]}'::jsonb,
  workflow_version.id,
  'retired',
  app.deal_type_configuration_checksum(
    definition.key::text,
    '1.0.0',
    1,
    pg_catalog.jsonb_build_object('en', definition.key::text, 'fr', definition.key::text),
    '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"},"lender":{"en":"Lender","fr":"Prêteur"},"trade_in_owner":{"en":"Trade-in owner","fr":"Propriétaire du véhicule d’échange"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"purchased":{"en":"Purchased vehicle","fr":"Véhicule acheté"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"},"wholesale":{"en":"Wholesale vehicle","fr":"Véhicule de gros"}},"one_time_event_types":{}}'::jsonb,
    '[]'::jsonb,
    pg_catalog.jsonb_build_object('required', '[]'::jsonb, 'optional', '[]'::jsonb),
    array['buyer', 'seller', 'lender', 'trade_in_owner', 'authorized_representative']::text[],
    array['sold', 'purchased', 'trade_in', 'wholesale']::text[],
    '{"inventory_direction":"mixed","inventory_creation":"none","finance_mode":"none","money_mode":"one_time","one_time_event_types":[]}'::jsonb,
    workflow_definition.key::text,
    workflow_version.version,
    workflow_version.checksum
  ),
  'migration_compatibility',
  pg_catalog.statement_timestamp()
from public.deal_type_definitions definition
join public.workflow_definitions workflow_definition
  on workflow_definition.workspace_id = definition.workspace_id
 and workflow_definition.key = 'm3_deal_compatibility'
join public.workflow_versions workflow_version
  on workflow_version.workspace_id = workflow_definition.workspace_id
 and workflow_version.workflow_definition_id = workflow_definition.id
 and workflow_version.version = '1.0.0'
where exists (
  select 1 from public.deals deal
  where deal.workspace_id = definition.workspace_id
    and deal.deal_type_key = definition.key::text
)
on conflict (workspace_id, deal_type_definition_id, version) do nothing;

insert into public.workflow_instances (
  id, workspace_id, workflow_version_id, entity_type, entity_id,
  purpose_key, current_state_key, canonical_status, lifecycle_status,
  version, completed_at
)
select
  pg_catalog.md5(deal.workspace_id::text || ':m3-deal-instance:' || deal.id::text)::uuid,
  deal.workspace_id,
  workflow_version.id,
  'deal',
  deal.id,
  'primary',
  case when deal.status = 'cancelled' then 'cancelled' else 'draft' end,
  case when deal.status = 'cancelled' then 'closed' else 'draft' end,
  case when deal.status = 'cancelled' then 'completed' else 'active' end,
  deal.version,
  case when deal.status = 'cancelled' then deal.updated_at else null end
from public.deals deal
join public.workflow_definitions workflow_definition
  on workflow_definition.workspace_id = deal.workspace_id
 and workflow_definition.key = 'm3_deal_compatibility'
join public.workflow_versions workflow_version
  on workflow_version.workspace_id = workflow_definition.workspace_id
 and workflow_version.workflow_definition_id = workflow_definition.id
 and workflow_version.version = '1.0.0'
on conflict (workspace_id, entity_type, entity_id, purpose_key) do nothing;

do $$
begin
  if exists (
    select 1
    from public.deals deal
    where (
      select pg_catalog.count(*)
      from public.locations location
      where location.workspace_id = deal.workspace_id
        and location.status = 'active'
    ) <> 1
      or (
        select pg_catalog.count(*)
        from public.legal_entities legal_entity
        where legal_entity.workspace_id = deal.workspace_id
          and legal_entity.status = 'active'
      ) <> 1
  ) then
    raise exception using
      errcode = '23514',
      message = 'existing M1 deals require exactly one active location and legal entity per workspace before M3 backfill';
  end if;
end;
$$;

update public.deals deal
set deal_type_definition_id = definition.id,
    deal_type_version_id = version.id,
    workflow_version_id = workflow_instance.workflow_version_id,
    workflow_instance_id = workflow_instance.id,
    workflow_state_key = workflow_instance.current_state_key,
    status = workflow_instance.canonical_status,
    lifecycle_status = workflow_instance.lifecycle_status,
    location_id = coalesce(deal.location_id, (
      select location.id from public.locations location
      where location.workspace_id = deal.workspace_id and location.status = 'active'
      order by location.key limit 1
    )),
    legal_entity_id = coalesce(deal.legal_entity_id, (
      select legal_entity.id from public.legal_entities legal_entity
      where legal_entity.workspace_id = deal.workspace_id and legal_entity.status = 'active'
      order by legal_entity.key limit 1
    )),
    completed_at = case when workflow_instance.lifecycle_status = 'completed'
      then coalesce(deal.completed_at, deal.updated_at) else null end,
    cancelled_at = case when workflow_instance.current_state_key = 'cancelled'
      then coalesce(deal.cancelled_at, deal.updated_at) else null end
from public.deal_type_definitions definition
join public.deal_type_versions version
  on version.workspace_id = definition.workspace_id
 and version.deal_type_definition_id = definition.id
 and version.source = 'migration_compatibility'
join public.workflow_instances workflow_instance
  on workflow_instance.workspace_id = definition.workspace_id
 and workflow_instance.entity_type = 'deal'
 and workflow_instance.purpose_key = 'primary'
where definition.workspace_id = deal.workspace_id
  and definition.key::text = deal.deal_type_key
  and workflow_instance.entity_id = deal.id;

do $$
begin
  if exists (
    select 1
    from public.deals deal
    left join public.deal_type_versions type_version
      on type_version.workspace_id = deal.workspace_id
     and type_version.id = deal.deal_type_version_id
    left join public.deal_type_definitions type_definition
      on type_definition.workspace_id = type_version.workspace_id
     and type_definition.id = type_version.deal_type_definition_id
    left join public.workflow_instances workflow_instance
      on workflow_instance.workspace_id = deal.workspace_id
     and workflow_instance.id = deal.workflow_instance_id
    where deal.deal_type_definition_id is null
      or deal.deal_type_version_id is null
      or deal.workflow_version_id is null
      or deal.workflow_instance_id is null
      or deal.workflow_state_key is null
      or deal.location_id is null
      or deal.legal_entity_id is null
      or type_version.deal_type_definition_id <> deal.deal_type_definition_id
      or type_definition.key::text is distinct from deal.deal_type_key
      or type_version.workflow_version_id <> deal.workflow_version_id
      or workflow_instance.workflow_version_id <> deal.workflow_version_id
      or workflow_instance.entity_type <> 'deal'
      or workflow_instance.entity_id <> deal.id
      or workflow_instance.current_state_key <> deal.workflow_state_key
      or workflow_instance.canonical_status <> deal.status
      or workflow_instance.version <> deal.version
  ) then
    raise exception using
      errcode = '23514',
      message = 'existing M1 deal configuration or workflow context could not be pinned safely';
  end if;
end;
$$;

alter table public.deals validate constraint deals_status_check;

alter table public.deals
  alter column deal_type_definition_id set not null,
  alter column deal_type_version_id set not null,
  alter column workflow_version_id set not null,
  alter column workflow_instance_id set not null,
  alter column workflow_state_key set not null,
  alter column location_id set not null,
  alter column legal_entity_id set not null;

update public.deal_participants participant
set created_by = deal.created_by
from public.deals deal
where deal.workspace_id = participant.workspace_id
  and deal.id = participant.deal_id
  and participant.created_by is null;

update public.deal_inventory_units inventory_link
set created_by = deal.created_by,
    currency_code = coalesce(inventory_link.currency_code, deal.currency_code),
    released_by = case when inventory_link.status = 'released'
      then coalesce(inventory_link.released_by, deal.created_by)
      else null end,
    released_at = case when inventory_link.status = 'released'
      then coalesce(inventory_link.released_at, inventory_link.created_at)
      else null end
from public.deals deal
where deal.workspace_id = inventory_link.workspace_id
  and deal.id = inventory_link.deal_id
  and (
    inventory_link.created_by is null
    or inventory_link.currency_code is null
    or (inventory_link.status = 'released' and inventory_link.released_by is null)
    or (inventory_link.status = 'released' and inventory_link.released_at is null)
  );

alter table public.deal_inventory_units
  add constraint deal_inventory_units_release_check check (
    (status = 'active' and released_by is null and released_at is null)
    or (status = 'released' and released_by is not null and released_at is not null)
  );

alter table public.deal_participants
  alter column created_by set default auth.uid(),
  alter column created_by set not null;

alter table public.deal_inventory_units
  alter column created_by set default auth.uid(),
  alter column created_by set not null;

drop trigger deals_immutable on public.deals;
create trigger deals_immutable
before update on public.deals
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'deal_type_key', 'deal_type_definition_id',
  'deal_type_version_id', 'workflow_version_id', 'workflow_instance_id',
  'currency_code', 'originating_lead_id', 'idempotency_key',
  'command_fingerprint', 'created_by', 'created_at'
);

create function app.attach_configured_deal_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  configured_definition_id uuid;
  configured_version_id uuid;
  configured_workflow_version_id uuid;
  configured_state_key text;
  configured_category text;
  new_instance_id uuid;
begin
  if not app.is_feature_entitled(
    new.workspace_id, 'deals', pg_catalog.statement_timestamp()
  ) then
    raise exception using errcode = '42501', message = 'active deals entitlement is required';
  end if;

  select
    definition.id,
    version.id,
    version.workflow_version_id,
    state.key,
    state.canonical_category
  into
    configured_definition_id,
    configured_version_id,
    configured_workflow_version_id,
    configured_state_key,
    configured_category
  from public.deal_type_definitions definition
  join public.deal_type_versions version
    on version.workspace_id = definition.workspace_id
   and version.deal_type_definition_id = definition.id
   and version.status = 'active'
  join public.workflow_versions workflow_version
    on workflow_version.workspace_id = version.workspace_id
   and workflow_version.id = version.workflow_version_id
   and workflow_version.status = 'active'
  join public.workflow_states state
    on state.workspace_id = workflow_version.workspace_id
   and state.workflow_version_id = workflow_version.id
   and state.key = workflow_version.initial_state_key
  where definition.workspace_id = new.workspace_id
    and definition.key = new.deal_type_key
    and definition.status = 'active'
    and (new.deal_type_version_id is null or version.id = new.deal_type_version_id);

  if not found then
    raise exception using errcode = '23514', message = 'active configured deal type is required';
  end if;

  if new.location_id is null then
    select location.id into new.location_id
    from public.locations location
    where location.workspace_id = new.workspace_id
      and location.status = 'active'
      and not exists (
        select 1
        from public.locations sibling
        where sibling.workspace_id = location.workspace_id
          and sibling.status = 'active'
          and sibling.id <> location.id
      );
  end if;
  if new.legal_entity_id is null then
    select legal_entity.id into new.legal_entity_id
    from public.legal_entities legal_entity
    where legal_entity.workspace_id = new.workspace_id
      and legal_entity.status = 'active'
      and not exists (
        select 1
        from public.legal_entities sibling
        where sibling.workspace_id = legal_entity.workspace_id
          and sibling.status = 'active'
          and sibling.id <> legal_entity.id
      );
  end if;
  if new.location_id is null
    or new.legal_entity_id is null
    or not exists (
      select 1
      from public.locations location
      where location.workspace_id = new.workspace_id
        and location.id = new.location_id
        and location.status = 'active'
    )
    or not exists (
      select 1
      from public.legal_entities legal_entity
      where legal_entity.workspace_id = new.workspace_id
        and legal_entity.id = new.legal_entity_id
        and legal_entity.status = 'active'
    ) then
    raise exception using errcode = '23514', message = 'active deal location and legal entity are required';
  end if;

  new.deal_type_definition_id := configured_definition_id;
  new.deal_type_version_id := configured_version_id;
  new.workflow_version_id := configured_workflow_version_id;
  new.workflow_state_key := configured_state_key;
  new.status := configured_category;
  new.lifecycle_status := 'active';
  new.completed_at := null;
  new.cancelled_at := null;

  new_instance_id := pg_catalog.gen_random_uuid();
  insert into public.workflow_instances (
    id, workspace_id, workflow_version_id, entity_type, entity_id,
    purpose_key, current_state_key, canonical_status, lifecycle_status,
    version
  ) values (
    new_instance_id, new.workspace_id, configured_workflow_version_id,
    'deal', new.id, 'primary', configured_state_key, configured_category,
    'active', new.version
  );
  new.workflow_instance_id := new_instance_id;
  return new;
end;
$$;

create function app.assert_deal_workflow_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  linked_instance public.workflow_instances%rowtype;
  pinned_type_definition_id uuid;
  pinned_type_key text;
  pinned_workflow_version_id uuid;
begin
  select
    type_version.deal_type_definition_id,
    type_definition.key::text,
    type_version.workflow_version_id
  into pinned_type_definition_id, pinned_type_key, pinned_workflow_version_id
  from public.deal_type_versions type_version
  join public.deal_type_definitions type_definition
    on type_definition.workspace_id = type_version.workspace_id
   and type_definition.id = type_version.deal_type_definition_id
  where type_version.workspace_id = new.workspace_id
    and type_version.id = new.deal_type_version_id;
  select instance.* into linked_instance
  from public.workflow_instances instance
  where instance.workspace_id = new.workspace_id
    and instance.id = new.workflow_instance_id;
  if pinned_type_definition_id is null
    or pinned_type_definition_id <> new.deal_type_definition_id
    or pinned_type_key <> new.deal_type_key
    or pinned_workflow_version_id <> new.workflow_version_id
    or not found
    or linked_instance.workflow_version_id <> new.workflow_version_id
    or linked_instance.entity_type <> 'deal'
    or linked_instance.entity_id <> new.id
    or linked_instance.purpose_key <> 'primary'
    or linked_instance.current_state_key <> new.workflow_state_key
    or linked_instance.canonical_status <> new.status
    or linked_instance.lifecycle_status <> new.lifecycle_status
    or linked_instance.version <> new.version then
    raise exception using errcode = '23514', message = 'deal workflow pin must match aggregate state and version';
  end if;
  return new;
end;
$$;

create trigger deals_10_attach_configured_workflow
before insert on public.deals
for each row execute function app.attach_configured_deal_workflow();

create trigger deals_20_assert_workflow_link
before insert or update on public.deals
for each row execute function app.assert_deal_workflow_link();

create function app.assert_deal_participant_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowed_roles text[];
  deal_lifecycle text;
begin
  select type_version.allowed_participant_roles, deal.lifecycle_status
    into allowed_roles, deal_lifecycle
  from public.deals deal
  join public.deal_type_versions type_version
    on type_version.workspace_id = deal.workspace_id
   and type_version.id = deal.deal_type_version_id
  where deal.workspace_id = new.workspace_id
    and deal.id = new.deal_id;
  if not found or deal_lifecycle <> 'active' then
    raise exception using errcode = '23514', message = 'active configured deal is required for participant links';
  end if;
  if not (new.role_key = any(allowed_roles)) then
    raise exception using errcode = '23514', message = 'participant role is not allowed by the pinned deal type';
  end if;
  if not exists (
    select 1
    from public.parties party
    where party.workspace_id = new.workspace_id
      and party.id = new.party_id
      and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  return new;
end;
$$;

create function app.assert_deal_inventory_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowed_roles text[];
  deal_currency text;
  deal_lifecycle text;
  inventory_currency text;
begin
  select
    type_version.allowed_inventory_roles,
    deal.currency_code::text,
    deal.lifecycle_status
  into allowed_roles, deal_currency, deal_lifecycle
  from public.deals deal
  join public.deal_type_versions type_version
    on type_version.workspace_id = deal.workspace_id
   and type_version.id = deal.deal_type_version_id
  where deal.workspace_id = new.workspace_id
    and deal.id = new.deal_id;
  if not found or deal_lifecycle <> 'active' then
    raise exception using errcode = '23514', message = 'active configured deal is required for inventory links';
  end if;
  if not (new.role_key = any(allowed_roles)) then
    raise exception using errcode = '23514', message = 'inventory role is not allowed by the pinned deal type';
  end if;
  select inventory.currency_code::text into inventory_currency
  from public.inventory_units inventory
  where inventory.workspace_id = new.workspace_id
    and inventory.id = new.inventory_unit_id
    and inventory.status not in ('closed', 'archived');
  if not found then
    raise exception using errcode = '23514', message = 'available workspace inventory unit is required';
  end if;
  if inventory_currency <> deal_currency
    or (new.currency_code is not null and new.currency_code::text <> deal_currency) then
    raise exception using errcode = '23514', message = 'deal, inventory, and link currencies must match';
  end if;
  new.currency_code := deal_currency;
  return new;
end;
$$;

create trigger deal_participants_validate_configuration
before insert on public.deal_participants
for each row execute function app.assert_deal_participant_link();

create trigger deal_inventory_units_validate_configuration
before insert on public.deal_inventory_units
for each row execute function app.assert_deal_inventory_link();

create function app.parse_deal_minor_units(candidate text)
returns bigint
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  exact_value numeric(20, 0);
begin
  if candidate !~ '^(?:0|-?[1-9][0-9]{0,18})$' then
    raise exception using errcode = '22023', message = 'money minor units must be a canonical integer string';
  end if;
  exact_value := candidate::numeric;
  if exact_value < -9223372036854775808::numeric
    or exact_value > 9223372036854775807::numeric then
    raise exception using errcode = '22003', message = 'money minor units exceed bigint range';
  end if;
  return exact_value::bigint;
end;
$$;

create function app.m3_create_deal(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_type_key text,
  p_currency_code text,
  p_location_id uuid,
  p_legal_entity_id uuid,
  p_owner_membership_id uuid,
  p_originating_lead_id uuid,
  p_notes text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  actor_membership_id uuid;
  normalized_idempotency_key text;
  normalized_type_key text;
  normalized_currency text;
  normalized_notes text;
  fingerprint text;
  legacy_idempotency_key text;
  existing_receipt public.deal_command_receipts%rowtype;
  new_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.create');
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_type_key := pg_catalog.lower(pg_catalog.btrim(coalesce(p_deal_type_key, '')));
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_notes := nullif(pg_catalog.btrim(coalesce(p_notes, '')), '');
  if normalized_type_key !~ '^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})*$' then
    raise exception using errcode = '22023', message = 'invalid deal type key';
  end if;
  if normalized_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'invalid deal currency';
  end if;
  if normalized_notes is not null and pg_catalog.char_length(normalized_notes) > 4000 then
    raise exception using errcode = '22023', message = 'deal notes are too long';
  end if;
  if p_location_id is null or p_legal_entity_id is null then
    raise exception using errcode = '23502', message = 'deal location and legal entity are required';
  end if;

  select membership.id into actor_membership_id
  from public.workspace_memberships membership
  where membership.workspace_id = p_workspace_id
    and membership.user_id = actor_user_id
    and membership.status = 'active';
  actor_membership_id := coalesce(p_owner_membership_id, actor_membership_id);
  if actor_membership_id is null or not exists (
    select 1 from public.workspace_memberships membership
    where membership.workspace_id = p_workspace_id
      and membership.id = actor_membership_id
      and membership.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace owner membership is required';
  end if;
  if not exists (
    select 1 from public.locations location
    where location.workspace_id = p_workspace_id
      and location.id = p_location_id
      and location.status = 'active'
  ) or not exists (
    select 1 from public.legal_entities legal_entity
    where legal_entity.workspace_id = p_workspace_id
      and legal_entity.id = p_legal_entity_id
      and legal_entity.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace location and legal entity are required';
  end if;

  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealTypeKey', normalized_type_key,
    'currencyCode', normalized_currency,
    'locationId', p_location_id,
    'legalEntityId', p_legal_entity_id,
    'ownerMembershipId', actor_membership_id,
    'originatingLeadId', p_originating_lead_id,
    'notes', normalized_notes
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_create_deal', normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_create_deal'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      existing_receipt.deal_id,
      existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey',
      true,
      existing_receipt.audit_event_id,
      existing_receipt.outbox_event_id;
    return;
  end if;

  legacy_idempotency_key := 'm3-' || app.deal_command_fingerprint(
    pg_catalog.jsonb_build_object(
      'actorUserId', actor_user_id,
      'idempotencyKey', normalized_idempotency_key
    )
  );
  insert into public.deals (
    workspace_id, deal_type_key, currency_code, owner_membership_id,
    location_id, legal_entity_id, originating_lead_id, notes,
    idempotency_key, command_fingerprint, created_by
  ) values (
    p_workspace_id, normalized_type_key, normalized_currency,
    actor_membership_id, p_location_id, p_legal_entity_id,
    p_originating_lead_id, normalized_notes, legacy_idempotency_key,
    fingerprint, actor_user_id
  ) returning * into new_deal;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.created',
    p_entity_type => 'deal',
    p_entity_id => new_deal.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'deal_type_key', new_deal.deal_type_key,
      'deal_type_version_id', new_deal.deal_type_version_id,
      'workflow_version_id', new_deal.workflow_version_id,
      'state_key', new_deal.workflow_state_key,
      'canonical_status', new_deal.status,
      'currency_code', new_deal.currency_code,
      'location_id', new_deal.location_id,
      'legal_entity_id', new_deal.legal_entity_id,
      'owner_membership_id', new_deal.owner_membership_id,
      'originating_lead_id', new_deal.originating_lead_id,
      'version', new_deal.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id,
    'deal.created',
    new_deal.id,
    new_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', new_deal.id,
      'dealTypeVersionId', new_deal.deal_type_version_id,
      'workflowVersionId', new_deal.workflow_version_id,
      'stateKey', new_deal.workflow_state_key,
      'canonicalStatus', new_deal.status
    ),
    actor_user_id,
    p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'dealId', new_deal.id,
    'aggregateVersion', new_deal.version,
    'canonicalStatus', new_deal.status,
    'stateKey', new_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_create_deal',
    normalized_idempotency_key, fingerprint, new_deal.id, new_deal.version,
    result_payload, new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_deal.id, new_deal.version, new_deal.status,
    new_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_update_deal(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_owner_membership_id uuid,
  p_location_id uuid,
  p_legal_entity_id uuid,
  p_notes text,
  p_clear_notes boolean,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_notes text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  existing_deal public.deals%rowtype;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected deal version must be positive';
  end if;
  normalized_notes := nullif(pg_catalog.btrim(coalesce(p_notes, '')), '');
  if normalized_notes is not null and pg_catalog.char_length(normalized_notes) > 4000 then
    raise exception using errcode = '22023', message = 'deal notes are too long';
  end if;
  if p_clear_notes and normalized_notes is not null then
    raise exception using errcode = '22023', message = 'clear-notes cannot include a replacement note';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'ownerMembershipId', p_owner_membership_id,
    'locationId', p_location_id,
    'legalEntityId', p_legal_entity_id,
    'notes', normalized_notes,
    'clearNotes', p_clear_notes
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_update_deal', normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_update_deal'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      existing_receipt.deal_id, existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;

  select deal.* into existing_deal
  from public.deals deal
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  if existing_deal.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale deal version';
  end if;
  if existing_deal.lifecycle_status <> 'active' then
    raise exception using errcode = '55000', message = 'completed deal cannot be updated';
  end if;
  if p_owner_membership_id is not null and not exists (
    select 1 from public.workspace_memberships membership
    where membership.workspace_id = p_workspace_id
      and membership.id = p_owner_membership_id
      and membership.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace owner membership is required';
  end if;
  if p_location_id is not null and not exists (
    select 1 from public.locations location
    where location.workspace_id = p_workspace_id
      and location.id = p_location_id and location.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace location is required';
  end if;
  if p_legal_entity_id is not null and not exists (
    select 1 from public.legal_entities legal_entity
    where legal_entity.workspace_id = p_workspace_id
      and legal_entity.id = p_legal_entity_id and legal_entity.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace legal entity is required';
  end if;

  update public.workflow_instances instance
  set version = existing_deal.version + 1,
      updated_at = pg_catalog.statement_timestamp()
  where instance.workspace_id = p_workspace_id
    and instance.id = existing_deal.workflow_instance_id;

  update public.deals deal
  set owner_membership_id = coalesce(p_owner_membership_id, deal.owner_membership_id),
      location_id = coalesce(p_location_id, deal.location_id),
      legal_entity_id = coalesce(p_legal_entity_id, deal.legal_entity_id),
      notes = case
        when p_clear_notes then null
        when normalized_notes is not null then normalized_notes
        else deal.notes
      end,
      version = deal.version + 1
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  returning * into updated_deal;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.updated',
    p_entity_type => 'deal',
    p_entity_id => p_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'owner_membership_id', existing_deal.owner_membership_id,
      'location_id', existing_deal.location_id,
      'legal_entity_id', existing_deal.legal_entity_id,
      'has_notes', existing_deal.notes is not null,
      'version', existing_deal.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'owner_membership_id', updated_deal.owner_membership_id,
      'location_id', updated_deal.location_id,
      'legal_entity_id', updated_deal.legal_entity_id,
      'has_notes', updated_deal.notes is not null,
      'version', updated_deal.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_idempotency_key)
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.updated', p_deal_id, updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'stateKey', updated_deal.workflow_state_key,
      'canonicalStatus', updated_deal.status
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_update_deal',
    normalized_idempotency_key, fingerprint, p_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    p_deal_id, updated_deal.version, updated_deal.status,
    updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.lock_active_deal(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_expected_version bigint
)
returns public.deals
language plpgsql
security definer
set search_path = ''
as $$
declare
  locked_deal public.deals%rowtype;
begin
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected deal version must be positive';
  end if;
  select deal.* into locked_deal
  from public.deals deal
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  if locked_deal.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale deal version';
  end if;
  if locked_deal.lifecycle_status <> 'active' then
    raise exception using errcode = '55000', message = 'completed deal cannot be changed';
  end if;
  return locked_deal;
end;
$$;

create function app.bump_deal_aggregate_version(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_workflow_instance_id uuid,
  p_current_version bigint
)
returns public.deals
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_deal public.deals%rowtype;
begin
  update public.workflow_instances instance
  set version = p_current_version + 1,
      updated_at = pg_catalog.statement_timestamp()
  where instance.workspace_id = p_workspace_id
    and instance.id = p_workflow_instance_id
    and instance.version = p_current_version;
  if not found then
    raise exception using errcode = '40001', message = 'stale deal workflow version';
  end if;
  update public.deals deal
  set version = p_current_version + 1
  where deal.workspace_id = p_workspace_id
    and deal.id = p_deal_id
    and deal.version = p_current_version
  returning * into updated_deal;
  if not found then
    raise exception using errcode = '40001', message = 'stale deal version';
  end if;
  return updated_deal;
end;
$$;

create function app.m3_add_deal_participant(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_party_id uuid,
  p_role_key text,
  p_is_primary boolean,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  participant_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_role text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  updated_deal public.deals%rowtype;
  new_participant_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  if not app.is_feature_entitled(
      p_workspace_id, 'crm', pg_catalog.statement_timestamp()
    ) or not app.has_permission(p_workspace_id, 'crm.read') then
    raise exception using errcode = '42501', message = 'active CRM entitlement and read permission are required for deal participants';
  end if;
  normalized_key := app.assert_deal_command_metadata(p_idempotency_key, p_correlation_id);
  normalized_role := pg_catalog.lower(pg_catalog.btrim(coalesce(p_role_key, '')));
  if normalized_role !~ '^[a-z][a-z0-9_.-]{0,127}$' then
    raise exception using errcode = '22023', message = 'invalid deal participant role';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'partyId', p_party_id,
    'roleKey', normalized_role,
    'isPrimary', coalesce(p_is_primary, false)
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_add_deal_participant', normalized_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_add_deal_participant'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'participantId')::uuid,
      existing_receipt.deal_id, existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  locked_deal := app.lock_active_deal(p_workspace_id, p_deal_id, p_expected_version);
  if not exists (
    select 1 from public.parties party
    where party.workspace_id = p_workspace_id
      and party.id = p_party_id and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  if not exists (
    select 1 from public.deal_type_versions version
    where version.workspace_id = p_workspace_id
      and version.id = locked_deal.deal_type_version_id
      and normalized_role = any(version.allowed_participant_roles)
  ) then
    raise exception using errcode = '23514', message = 'participant role is not allowed by the pinned deal type';
  end if;
  new_participant_id := pg_catalog.gen_random_uuid();
  insert into public.deal_participants (
    id, workspace_id, deal_id, party_id, role_key, is_primary, created_by
  ) values (
    new_participant_id, p_workspace_id, p_deal_id, p_party_id,
    normalized_role, coalesce(p_is_primary, false), actor_user_id
  );
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.participant_added',
    p_entity_type => 'deal',
    p_entity_id => p_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'participant_id', new_participant_id,
      'party_id', p_party_id,
      'role_key', normalized_role,
      'is_primary', coalesce(p_is_primary, false),
      'version', updated_deal.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.participant_added', p_deal_id, updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id, 'participantId', new_participant_id,
      'roleKey', normalized_role
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'participantId', new_participant_id,
    'dealId', p_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_add_deal_participant',
    normalized_key, fingerprint, p_deal_id, updated_deal.version,
    result_payload, new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_participant_id, p_deal_id, updated_deal.version,
    updated_deal.status, updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_release_deal_participant(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_participant_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  participant_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  updated_deal public.deals%rowtype;
  participant_role text;
  participant_party_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  if not app.is_feature_entitled(
      p_workspace_id, 'crm', pg_catalog.statement_timestamp()
    ) or not app.has_permission(p_workspace_id, 'crm.read') then
    raise exception using errcode = '42501', message = 'active CRM entitlement and read permission are required for deal participants';
  end if;
  normalized_key := app.assert_deal_command_metadata(p_idempotency_key, p_correlation_id);
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'participantId', p_participant_id
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_release_deal_participant', normalized_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_release_deal_participant'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'participantId')::uuid,
      existing_receipt.deal_id, existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  locked_deal := app.lock_active_deal(p_workspace_id, p_deal_id, p_expected_version);
  if locked_deal.status <> 'draft' then
    raise exception using errcode = '55000', message = 'deal participant can only be released while draft';
  end if;
  select participant.role_key, participant.party_id
    into participant_role, participant_party_id
  from public.deal_participants participant
  where participant.workspace_id = p_workspace_id
    and participant.deal_id = p_deal_id
    and participant.id = p_participant_id
    and participant.status = 'active'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'active deal participant not found';
  end if;
  update public.deal_participants participant
  set status = 'released', version = participant.version + 1,
      released_by = actor_user_id,
      released_at = pg_catalog.statement_timestamp()
  where participant.workspace_id = p_workspace_id
    and participant.id = p_participant_id;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.participant_released',
    p_entity_type => 'deal',
    p_entity_id => p_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'participant_id', p_participant_id,
      'party_id', participant_party_id,
      'role_key', participant_role,
      'status', 'active'
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'participant_id', p_participant_id,
      'status', 'released',
      'version', updated_deal.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.participant_released', p_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id, 'participantId', p_participant_id,
      'roleKey', participant_role
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'participantId', p_participant_id,
    'dealId', p_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_release_deal_participant',
    normalized_key, fingerprint, p_deal_id, updated_deal.version,
    result_payload, new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_participant_id, p_deal_id, updated_deal.version,
    updated_deal.status, updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_add_deal_inventory(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_inventory_unit_id uuid,
  p_role_key text,
  p_amount_minor text,
  p_currency_code text,
  p_metadata jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_link_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  normalized_role text;
  normalized_currency text;
  exact_amount bigint;
  safe_metadata jsonb;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  updated_deal public.deals%rowtype;
  inventory_currency text;
  new_inventory_link_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  if not app.has_permission(p_workspace_id, 'inventory.read') then
    raise exception using errcode = '42501', message = 'inventory read permission is required for deal inventory links';
  end if;
  normalized_key := app.assert_deal_command_metadata(p_idempotency_key, p_correlation_id);
  normalized_role := pg_catalog.lower(pg_catalog.btrim(coalesce(p_role_key, '')));
  if normalized_role !~ '^[a-z][a-z0-9_.-]{0,127}$' then
    raise exception using errcode = '22023', message = 'invalid deal inventory role';
  end if;
  if (p_amount_minor is null) <> (p_currency_code is null) then
    raise exception using errcode = '23514', message = 'inventory-link amount and currency must be supplied together';
  end if;
  if p_amount_minor is not null then
    exact_amount := app.parse_deal_minor_units(p_amount_minor);
    normalized_currency := pg_catalog.upper(pg_catalog.btrim(p_currency_code));
    if normalized_currency !~ '^[A-Z]{3}$' then
      raise exception using errcode = '22023', message = 'invalid deal inventory currency';
    end if;
  end if;
  safe_metadata := coalesce(p_metadata, '{}'::jsonb);
  if pg_catalog.jsonb_typeof(safe_metadata) <> 'object'
    or app.job_payload_contains_forbidden_key(safe_metadata)
    or pg_catalog.octet_length(safe_metadata::text) > 16384 then
    raise exception using errcode = '23514', message = 'invalid deal inventory metadata';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'inventoryUnitId', p_inventory_unit_id,
    'roleKey', normalized_role,
    'amountMinor', p_amount_minor,
    'currencyCode', normalized_currency,
    'metadata', safe_metadata
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_add_deal_inventory', normalized_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_add_deal_inventory'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'inventoryLinkId')::uuid,
      existing_receipt.deal_id, existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  locked_deal := app.lock_active_deal(p_workspace_id, p_deal_id, p_expected_version);
  if not exists (
    select 1 from public.deal_type_versions version
    where version.workspace_id = p_workspace_id
      and version.id = locked_deal.deal_type_version_id
      and normalized_role = any(version.allowed_inventory_roles)
  ) then
    raise exception using errcode = '23514', message = 'inventory role is not allowed by the pinned deal type';
  end if;
  select inventory.currency_code::text into inventory_currency
  from public.inventory_units inventory
  where inventory.workspace_id = p_workspace_id
    and inventory.id = p_inventory_unit_id
    and inventory.status not in ('closed', 'archived')
  for update;
  if not found then
    raise exception using errcode = '23514', message = 'available workspace inventory unit is required';
  end if;
  if inventory_currency <> locked_deal.currency_code::text
    or (normalized_currency is not null and normalized_currency <> locked_deal.currency_code::text) then
    raise exception using errcode = '23514', message = 'deal, inventory, and link currencies must match';
  end if;
  if normalized_role = 'sold' and exists (
    select 1 from public.deal_inventory_units inventory_link
    where inventory_link.workspace_id = p_workspace_id
      and inventory_link.inventory_unit_id = p_inventory_unit_id
      and inventory_link.role_key = 'sold'
      and inventory_link.status = 'active'
  ) then
    raise exception using errcode = '23505', message = 'inventory unit already has an active sold deal link';
  end if;
  new_inventory_link_id := pg_catalog.gen_random_uuid();
  insert into public.deal_inventory_units (
    id, workspace_id, deal_id, inventory_unit_id, role_key, status,
    amount_minor, currency_code, metadata, created_by
  ) values (
    new_inventory_link_id, p_workspace_id, p_deal_id, p_inventory_unit_id,
    normalized_role, 'active', exact_amount,
    coalesce(normalized_currency, locked_deal.currency_code::text),
    safe_metadata, actor_user_id
  );
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.inventory_added',
    p_entity_type => 'deal',
    p_entity_id => p_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'inventory_link_id', new_inventory_link_id,
      'inventory_unit_id', p_inventory_unit_id,
      'role_key', normalized_role,
      'has_amount', exact_amount is not null,
      'currency_code', coalesce(normalized_currency, locked_deal.currency_code::text),
      'version', updated_deal.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.inventory_added', p_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'inventoryLinkId', new_inventory_link_id,
      'inventoryUnitId', p_inventory_unit_id,
      'roleKey', normalized_role
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'inventoryLinkId', new_inventory_link_id,
    'dealId', p_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_add_deal_inventory',
    normalized_key, fingerprint, p_deal_id, updated_deal.version,
    result_payload, new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_inventory_link_id, p_deal_id, updated_deal.version,
    updated_deal.status, updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_release_deal_inventory(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_inventory_link_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_link_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  updated_deal public.deals%rowtype;
  link_role text;
  linked_inventory_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  if not app.has_permission(p_workspace_id, 'inventory.read') then
    raise exception using errcode = '42501', message = 'inventory read permission is required for deal inventory links';
  end if;
  normalized_key := app.assert_deal_command_metadata(p_idempotency_key, p_correlation_id);
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'inventoryLinkId', p_inventory_link_id
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_release_deal_inventory', normalized_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_release_deal_inventory'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'inventoryLinkId')::uuid,
      existing_receipt.deal_id, existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  locked_deal := app.lock_active_deal(p_workspace_id, p_deal_id, p_expected_version);
  if locked_deal.status <> 'draft' then
    raise exception using errcode = '55000', message = 'deal inventory link can only be released while draft';
  end if;
  select inventory_link.role_key, inventory_link.inventory_unit_id
    into link_role, linked_inventory_id
  from public.deal_inventory_units inventory_link
  where inventory_link.workspace_id = p_workspace_id
    and inventory_link.deal_id = p_deal_id
    and inventory_link.id = p_inventory_link_id
    and inventory_link.status = 'active'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'active deal inventory link not found';
  end if;
  update public.deal_inventory_units inventory_link
  set status = 'released', version = inventory_link.version + 1,
      released_by = actor_user_id,
      released_at = pg_catalog.statement_timestamp()
  where inventory_link.workspace_id = p_workspace_id
    and inventory_link.id = p_inventory_link_id;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.inventory_released',
    p_entity_type => 'deal',
    p_entity_id => p_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'inventory_link_id', p_inventory_link_id,
      'inventory_unit_id', linked_inventory_id,
      'role_key', link_role,
      'status', 'active'
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'inventory_link_id', p_inventory_link_id,
      'status', 'released',
      'version', updated_deal.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.inventory_released', p_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'inventoryLinkId', p_inventory_link_id,
      'inventoryUnitId', linked_inventory_id,
      'roleKey', link_role
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'inventoryLinkId', p_inventory_link_id,
    'dealId', p_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_release_deal_inventory',
    normalized_key, fingerprint, p_deal_id, updated_deal.version,
    result_payload, new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_inventory_link_id, p_deal_id, updated_deal.version,
    updated_deal.status, updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_add_deal_line_item(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_key text,
  p_item_type text,
  p_label text,
  p_quantity text,
  p_unit_amount_minor text,
  p_currency_code text,
  p_tax_classification_key text,
  p_payment_timing_key text,
  p_sort_order integer,
  p_source_key text,
  p_source_reference text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  line_item_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_key text;
  normalized_item_type text;
  normalized_label text;
  normalized_currency text;
  normalized_tax_key text;
  normalized_timing_key text;
  normalized_source_key text;
  normalized_source_reference text;
  exact_amount bigint;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  updated_deal public.deals%rowtype;
  new_line_item_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_key := pg_catalog.lower(pg_catalog.btrim(coalesce(p_key, '')));
  normalized_item_type := pg_catalog.lower(pg_catalog.btrim(coalesce(p_item_type, '')));
  normalized_label := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_label, '')), '[[:space:]]+', ' ', 'g'
  );
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_tax_key := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(p_tax_classification_key, ''))), '');
  normalized_timing_key := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(p_payment_timing_key, ''))), '');
  normalized_source_key := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(p_source_key, ''))), '');
  normalized_source_reference := nullif(pg_catalog.btrim(coalesce(p_source_reference, '')), '');
  if normalized_key !~ '^[a-z][a-z0-9_.-]{0,127}$'
    or normalized_item_type not in ('vehicle', 'fee', 'discount', 'accessory', 'service', 'other')
    or normalized_label = ''
    or pg_catalog.char_length(normalized_label) > 200
    or p_quantity !~ '^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$'
    or p_quantity::numeric <= 0
    or normalized_currency !~ '^[A-Z]{3}$'
    or p_sort_order is null or p_sort_order < 0 then
    raise exception using errcode = '22023', message = 'invalid exact deal line item';
  end if;
  if (normalized_tax_key is not null and normalized_tax_key !~ '^[a-z][a-z0-9_.-]{0,127}$')
    or (normalized_timing_key is not null and normalized_timing_key !~ '^[a-z][a-z0-9_.-]{0,127}$')
    or (normalized_source_key is not null and normalized_source_key !~ '^[a-z][a-z0-9_.-]{0,127}$')
    or (normalized_source_reference is not null and pg_catalog.char_length(normalized_source_reference) > 500) then
    raise exception using errcode = '22023', message = 'invalid deal line item classification';
  end if;
  exact_amount := app.parse_deal_minor_units(p_unit_amount_minor);
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'key', normalized_key,
    'itemType', normalized_item_type,
    'label', normalized_label,
    'quantity', p_quantity,
    'unitAmountMinor', p_unit_amount_minor,
    'currencyCode', normalized_currency,
    'taxClassificationKey', normalized_tax_key,
    'paymentTimingKey', normalized_timing_key,
    'sortOrder', p_sort_order,
    'sourceKey', normalized_source_key,
    'sourceReference', normalized_source_reference
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_add_deal_line_item', normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_add_deal_line_item'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'lineItemId')::uuid,
      existing_receipt.deal_id, existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  locked_deal := app.lock_active_deal(p_workspace_id, p_deal_id, p_expected_version);
  if normalized_currency <> locked_deal.currency_code::text then
    raise exception using errcode = '23514', message = 'line item currency must match deal currency';
  end if;
  new_line_item_id := pg_catalog.gen_random_uuid();
  insert into public.deal_line_items (
    id, workspace_id, deal_id, key, item_type, label, quantity_text,
    unit_amount_minor, currency_code, tax_classification_key,
    payment_timing_key, sort_order, source_key, source_reference,
    created_by, updated_by
  ) values (
    new_line_item_id, p_workspace_id, p_deal_id, normalized_key,
    normalized_item_type, normalized_label, p_quantity, exact_amount,
    normalized_currency, normalized_tax_key, normalized_timing_key,
    p_sort_order, normalized_source_key, normalized_source_reference,
    actor_user_id, actor_user_id
  );
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.line_item_added',
    p_entity_type => 'deal',
    p_entity_id => p_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'line_item_id', new_line_item_id,
      'key', normalized_key,
      'item_type', normalized_item_type,
      'quantity', p_quantity,
      'unit_amount_minor', p_unit_amount_minor,
      'currency_code', normalized_currency,
      'version', updated_deal.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_idempotency_key)
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.line_item_added', p_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'lineItemId', new_line_item_id,
      'key', normalized_key,
      'itemType', normalized_item_type
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'lineItemId', new_line_item_id,
    'dealId', p_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_add_deal_line_item',
    normalized_idempotency_key, fingerprint, p_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    new_line_item_id, p_deal_id, updated_deal.version,
    updated_deal.status, updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_update_deal_line_item(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_line_item_id uuid,
  p_expected_line_item_version bigint,
  p_item_type text,
  p_label text,
  p_quantity text,
  p_unit_amount_minor text,
  p_currency_code text,
  p_tax_classification_key text,
  p_payment_timing_key text,
  p_sort_order integer,
  p_source_key text,
  p_source_reference text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  line_item_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  line_item_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_item_type text;
  normalized_label text;
  normalized_currency text;
  normalized_tax_key text;
  normalized_timing_key text;
  normalized_source_key text;
  normalized_source_reference text;
  exact_amount bigint;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  existing_item public.deal_line_items%rowtype;
  updated_item public.deal_line_items%rowtype;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_line_item_version is null or p_expected_line_item_version < 1 then
    raise exception using errcode = '22023', message = 'expected line item version must be positive';
  end if;
  normalized_item_type := pg_catalog.lower(pg_catalog.btrim(coalesce(p_item_type, '')));
  normalized_label := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_label, '')), '[[:space:]]+', ' ', 'g'
  );
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_tax_key := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(p_tax_classification_key, ''))), '');
  normalized_timing_key := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(p_payment_timing_key, ''))), '');
  normalized_source_key := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(p_source_key, ''))), '');
  normalized_source_reference := nullif(pg_catalog.btrim(coalesce(p_source_reference, '')), '');
  if normalized_item_type not in ('vehicle', 'fee', 'discount', 'accessory', 'service', 'other')
    or normalized_label = ''
    or pg_catalog.char_length(normalized_label) > 200
    or p_quantity !~ '^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$'
    or p_quantity::numeric <= 0
    or normalized_currency !~ '^[A-Z]{3}$'
    or p_sort_order is null or p_sort_order < 0 then
    raise exception using errcode = '22023', message = 'invalid exact deal line item';
  end if;
  if (normalized_tax_key is not null and normalized_tax_key !~ '^[a-z][a-z0-9_.-]{0,127}$')
    or (normalized_timing_key is not null and normalized_timing_key !~ '^[a-z][a-z0-9_.-]{0,127}$')
    or (normalized_source_key is not null and normalized_source_key !~ '^[a-z][a-z0-9_.-]{0,127}$')
    or (normalized_source_reference is not null and pg_catalog.char_length(normalized_source_reference) > 500) then
    raise exception using errcode = '22023', message = 'invalid deal line item classification';
  end if;
  exact_amount := app.parse_deal_minor_units(p_unit_amount_minor);
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'lineItemId', p_line_item_id,
    'expectedLineItemVersion', p_expected_line_item_version,
    'itemType', normalized_item_type,
    'label', normalized_label,
    'quantity', p_quantity,
    'unitAmountMinor', p_unit_amount_minor,
    'currencyCode', normalized_currency,
    'taxClassificationKey', normalized_tax_key,
    'paymentTimingKey', normalized_timing_key,
    'sortOrder', p_sort_order,
    'sourceKey', normalized_source_key,
    'sourceReference', normalized_source_reference
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_update_deal_line_item', normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_update_deal_line_item'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'lineItemId')::uuid,
      existing_receipt.deal_id, existing_receipt.aggregate_version,
      (existing_receipt.result ->> 'lineItemVersion')::bigint,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  locked_deal := app.lock_active_deal(p_workspace_id, p_deal_id, p_expected_version);
  if locked_deal.status <> 'draft' then
    raise exception using errcode = '55000', message = 'deal line item can only be updated while draft';
  end if;
  if normalized_currency <> locked_deal.currency_code::text then
    raise exception using errcode = '23514', message = 'line item currency must match deal currency';
  end if;
  select line_item.* into existing_item
  from public.deal_line_items line_item
  where line_item.workspace_id = p_workspace_id
    and line_item.deal_id = p_deal_id
    and line_item.id = p_line_item_id
    and line_item.status = 'active'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'active deal line item not found';
  end if;
  if existing_item.version <> p_expected_line_item_version then
    raise exception using errcode = '40001', message = 'stale deal line item version';
  end if;
  update public.deal_line_items line_item
  set item_type = normalized_item_type,
      label = normalized_label,
      quantity_text = p_quantity,
      unit_amount_minor = exact_amount,
      currency_code = normalized_currency,
      tax_classification_key = normalized_tax_key,
      payment_timing_key = normalized_timing_key,
      sort_order = p_sort_order,
      source_key = normalized_source_key,
      source_reference = normalized_source_reference,
      version = line_item.version + 1,
      updated_by = actor_user_id
  where line_item.workspace_id = p_workspace_id
    and line_item.id = p_line_item_id
  returning * into updated_item;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.line_item_updated',
    p_entity_type => 'deal',
    p_entity_id => p_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'line_item_id', p_line_item_id,
      'item_type', existing_item.item_type,
      'quantity', existing_item.quantity_text,
      'unit_amount_minor', existing_item.unit_amount_minor::text,
      'currency_code', existing_item.currency_code,
      'line_item_version', existing_item.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'line_item_id', p_line_item_id,
      'item_type', updated_item.item_type,
      'quantity', updated_item.quantity_text,
      'unit_amount_minor', updated_item.unit_amount_minor::text,
      'currency_code', updated_item.currency_code,
      'line_item_version', updated_item.version,
      'version', updated_deal.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_idempotency_key)
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.line_item_updated', p_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'lineItemId', p_line_item_id,
      'key', updated_item.key,
      'itemType', updated_item.item_type,
      'lineItemVersion', updated_item.version
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'lineItemId', p_line_item_id,
    'dealId', p_deal_id,
    'aggregateVersion', updated_deal.version,
    'lineItemVersion', updated_item.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_update_deal_line_item',
    normalized_idempotency_key, fingerprint, p_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    p_line_item_id, p_deal_id, updated_deal.version,
    updated_item.version, updated_deal.status,
    updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.deal_field_is_present(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_field_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  deal_row public.deals%rowtype;
  required_role_key text;
begin
  select deal.* into deal_row
  from public.deals deal
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id;
  if not found then
    return false;
  end if;
  if p_field_key = 'currency_code' then return deal_row.currency_code is not null; end if;
  if p_field_key = 'location_id' then return deal_row.location_id is not null; end if;
  if p_field_key = 'legal_entity_id' then return deal_row.legal_entity_id is not null; end if;
  if p_field_key = 'owner_membership_id' then return deal_row.owner_membership_id is not null; end if;
  if p_field_key = 'notes' then return deal_row.notes is not null; end if;

  required_role_key := case p_field_key
    when 'buyer_party_id' then 'buyer'
    when 'seller_party_id' then 'seller'
    when 'dealer_buyer_party_id' then 'dealer_buyer'
    when 'lender_party_id' then 'lender'
    when 'trade_in_owner_party_id' then 'trade_in_owner'
    when 'authorized_representative_party_id' then 'authorized_representative'
    else null
  end;
  if required_role_key is not null then
    return exists (
      select 1 from public.deal_participants participant
      where participant.workspace_id = p_workspace_id
        and participant.deal_id = p_deal_id
        and participant.role_key = required_role_key
        and participant.status = 'active'
    );
  end if;

  required_role_key := case p_field_key
    when 'sold_inventory_unit_id' then 'sold'
    when 'purchased_inventory_unit_id' then 'purchased'
    when 'trade_in_inventory_unit_id' then 'trade_in'
    when 'wholesale_inventory_unit_id' then 'wholesale'
    else null
  end;
  if required_role_key is not null then
    return exists (
      select 1 from public.deal_inventory_units inventory_link
      where inventory_link.workspace_id = p_workspace_id
        and inventory_link.deal_id = p_deal_id
        and inventory_link.role_key = required_role_key
        and inventory_link.status = 'active'
    );
  end if;

  return exists (
    select 1
    from public.custom_field_values field_value
    join public.custom_field_definitions definition
      on definition.workspace_id = field_value.workspace_id
     and definition.id = field_value.custom_field_definition_id
     and definition.entity_type = 'deal'
     and definition.key = p_field_key
     and definition.status = 'active'
    join public.custom_field_versions version
      on version.workspace_id = field_value.workspace_id
     and version.id = field_value.custom_field_version_id
     and version.status = 'active'
    where field_value.workspace_id = p_workspace_id
      and field_value.entity_type = 'deal'
      and field_value.entity_id = p_deal_id
      and field_value.is_set
      and (
        version.visibility_permission_key is null
        or app.has_permission(p_workspace_id, version.visibility_permission_key)
      )
      and (
        version.value_type <> 'inventory_reference'
        or app.has_permission(p_workspace_id, 'inventory.read')
      )
  );
end;
$$;

create function app.deal_required_fields_complete(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_required_fields text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1
    from pg_catalog.unnest(coalesce(p_required_fields, '{}'::text[])) field(key)
    where not app.deal_field_is_present(p_workspace_id, p_deal_id, field.key)
  );
$$;

-- Replaced by the external-finance migration once its workspace-owned table
-- exists. Until then the lender guard fails closed and no provider behavior is
-- implied by a deal-type flag.
create function app.deal_external_finance_approved(
  p_workspace_id uuid,
  p_deal_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false;
$$;

create function app.deal_guard_is_satisfied(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_guard_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  required_fields text[];
  finance_mode text;
begin
  if p_guard_key is null then return true; end if;
  select
    coalesce((
      select pg_catalog.array_agg(field.value)
      from pg_catalog.jsonb_array_elements_text(
        coalesce(version.field_schema -> 'required', '[]'::jsonb)
      ) field(value)
    ), '{}'::text[]),
    coalesce(version.behavior_flags ->> 'finance_mode', 'none')
  into required_fields, finance_mode
  from public.deals deal
  join public.deal_type_versions version
    on version.workspace_id = deal.workspace_id
   and version.id = deal.deal_type_version_id
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id;
  if not found then return false; end if;

  if p_guard_key = 'required_fields_complete' then
    return app.deal_required_fields_complete(
      p_workspace_id, p_deal_id, required_fields
    );
  end if;
  if p_guard_key = 'lender_approval_recorded' then
    return finance_mode = 'external_lender_tracking'
      and app.deal_external_finance_approved(p_workspace_id, p_deal_id);
  end if;
  if p_guard_key = 'required_documents_generated' then
    return exists (
      select 1 from public.documents document
      where document.workspace_id = p_workspace_id
        and document.deal_id = p_deal_id
        and document.mode = 'preview'
        and document.status = 'generated'
    );
  end if;
  if p_guard_key = 'completion_requirements_met' then
    return app.deal_required_fields_complete(
        p_workspace_id, p_deal_id, required_fields
      )
      and exists (
        select 1 from public.deal_line_items line_item
        where line_item.workspace_id = p_workspace_id
          and line_item.deal_id = p_deal_id
          and line_item.status = 'active'
      )
      and (
        finance_mode <> 'external_lender_tracking'
        or app.deal_external_finance_approved(p_workspace_id, p_deal_id)
      );
  end if;
  return false;
end;
$$;

create function app.m3_transition_deal(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_transition_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  workflow_event_id uuid,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_transition_key text;
  normalized_reason text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  configured_transition public.workflow_transitions%rowtype;
  target_state public.workflow_states%rowtype;
  type_required_fields text[];
  combined_required_fields text[];
  new_version bigint;
  new_workflow_event_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.transition');
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_transition_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_transition_key, ''))
  );
  normalized_reason := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
  if normalized_transition_key !~ '^[a-z][a-z0-9_]{0,127}$' then
    raise exception using errcode = '22023', message = 'invalid deal transition key';
  end if;
  if normalized_reason is not null and pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'deal transition reason is too long';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'transitionKey', normalized_transition_key,
    'reason', normalized_reason
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_transition_deal',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_transition_deal'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      existing_receipt.deal_id, existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey',
      (existing_receipt.result ->> 'workflowEventId')::uuid,
      true, existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;

  locked_deal := app.lock_active_deal(p_workspace_id, p_deal_id, p_expected_version);
  if not exists (
    select 1 from public.deal_type_versions version
    where version.workspace_id = p_workspace_id
      and version.id = locked_deal.deal_type_version_id
  ) then
    raise exception using errcode = '55000', message = 'pinned deal type version is unavailable';
  end if;
  select transition.* into configured_transition
  from public.workflow_transitions transition
  where transition.workspace_id = p_workspace_id
    and transition.workflow_version_id = locked_deal.workflow_version_id
    and transition.key = normalized_transition_key
    and transition.from_state_key = locked_deal.workflow_state_key;
  if not found then
    raise exception using errcode = '23514', message = 'deal workflow transition is not allowed';
  end if;
  if not app.has_permission(p_workspace_id, configured_transition.permission_key) then
    raise exception using errcode = '42501', message = 'configured deal transition permission is required';
  end if;
  if configured_transition.reason_required and normalized_reason is null then
    raise exception using errcode = '23514', message = 'deal transition reason is required';
  end if;
  select state.* into target_state
  from public.workflow_states state
  where state.workspace_id = p_workspace_id
    and state.workflow_version_id = locked_deal.workflow_version_id
    and state.key = configured_transition.to_state_key;
  if not found then
    raise exception using errcode = '55000', message = 'configured target deal state is unavailable';
  end if;
  if target_state.behavior_flags @> '{"cancellation":true}'::jsonb
    and normalized_reason is null then
    raise exception using
      errcode = '23514',
      message = 'configured deal cancellation requires a reason';
  end if;
  select coalesce(
      pg_catalog.array_agg(field.value) filter (where field.value is not null),
      '{}'::text[]
    )
    into type_required_fields
  from public.deal_type_versions version
  left join lateral pg_catalog.jsonb_array_elements_text(
    coalesce(version.field_schema -> 'required', '[]'::jsonb)
  ) field(value) on true
  where version.workspace_id = p_workspace_id
    and version.id = locked_deal.deal_type_version_id;
  select coalesce(pg_catalog.array_agg(distinct field_key), '{}'::text[])
    into combined_required_fields
  from pg_catalog.unnest(
    coalesce(type_required_fields, '{}'::text[])
      || configured_transition.required_fields
      || target_state.required_fields
  ) required(field_key);
  if not app.deal_required_fields_complete(
    p_workspace_id, p_deal_id, combined_required_fields
  ) then
    raise exception using errcode = '23514', message = 'required deal fields are incomplete';
  end if;
  if not app.deal_guard_is_satisfied(
    p_workspace_id, p_deal_id, configured_transition.guard_key
  ) then
    raise exception using errcode = '23514', message = 'configured deal transition guard is not satisfied';
  end if;

  new_version := locked_deal.version + 1;
  update public.workflow_instances instance
  set current_state_key = target_state.key,
      canonical_status = target_state.canonical_category,
      lifecycle_status = case
        when target_state.canonical_category in ('closed', 'archived')
          or target_state.behavior_flags @> '{"terminal":true}'::jsonb
        then 'completed' else 'active' end,
      version = new_version,
      completed_at = case
        when target_state.canonical_category in ('closed', 'archived')
          or target_state.behavior_flags @> '{"terminal":true}'::jsonb
        then pg_catalog.statement_timestamp() else null end,
      updated_at = pg_catalog.statement_timestamp()
  where instance.workspace_id = p_workspace_id
    and instance.id = locked_deal.workflow_instance_id
    and instance.version = locked_deal.version;
  if not found then
    raise exception using errcode = '40001', message = 'stale deal workflow version';
  end if;

  update public.deals deal
  set workflow_state_key = target_state.key,
      status = target_state.canonical_category,
      lifecycle_status = case
        when target_state.canonical_category in ('closed', 'archived')
          or target_state.behavior_flags @> '{"terminal":true}'::jsonb
        then 'completed' else 'active' end,
      version = new_version,
      effective_at = case
        when deal.effective_at is null and target_state.canonical_category <> 'draft'
          then pg_catalog.statement_timestamp()
        else deal.effective_at end,
      completed_at = case
        when target_state.canonical_category in ('closed', 'archived')
          or target_state.behavior_flags @> '{"terminal":true}'::jsonb
        then pg_catalog.statement_timestamp() else null end,
      cancelled_at = case
        when target_state.behavior_flags @> '{"cancellation":true}'::jsonb
        then pg_catalog.statement_timestamp() else null end,
      closed_reason = case
        when target_state.canonical_category in ('closed', 'archived')
          or target_state.behavior_flags @> '{"terminal":true}'::jsonb
        then normalized_reason else null end
  where deal.workspace_id = p_workspace_id
    and deal.id = p_deal_id
    and deal.version = locked_deal.version;
  if not found then
    raise exception using errcode = '40001', message = 'stale deal version';
  end if;

  insert into public.workflow_events (
    workspace_id, workflow_instance_id, transition_id, entity_type,
    entity_id, from_state_key, to_state_key, aggregate_version,
    reason, actor_user_id, request_id, correlation_id
  ) values (
    p_workspace_id, locked_deal.workflow_instance_id,
    configured_transition.id, 'deal', p_deal_id,
    locked_deal.workflow_state_key, target_state.key, new_version,
    normalized_reason, actor_user_id, p_request_id, p_correlation_id
  ) returning id into new_workflow_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.transitioned',
    p_entity_type => 'deal',
    p_entity_id => p_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'state_key', locked_deal.workflow_state_key,
      'canonical_status', locked_deal.status,
      'version', locked_deal.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'state_key', target_state.key,
      'canonical_status', target_state.canonical_category,
      'version', new_version,
      'workflow_event_id', new_workflow_event_id
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key,
      'transition_key', configured_transition.key,
      'guard_key', configured_transition.guard_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.transitioned', p_deal_id, new_version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'workflowEventId', new_workflow_event_id,
      'transitionKey', configured_transition.key,
      'fromStateKey', locked_deal.workflow_state_key,
      'toStateKey', target_state.key,
      'canonicalStatus', target_state.canonical_category,
      'effectKeys', configured_transition.effect_keys
    ),
    actor_user_id, p_correlation_id, new_workflow_event_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'aggregateVersion', new_version,
    'canonicalStatus', target_state.canonical_category,
    'stateKey', target_state.key,
    'workflowEventId', new_workflow_event_id
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_transition_deal',
    normalized_idempotency_key, fingerprint, p_deal_id, new_version,
    result_payload, new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_deal_id, new_version, target_state.canonical_category,
    target_state.key, new_workflow_event_id, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create or replace function app.can_read_workflow_entity(
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
  if p_entity_type = 'deal' and not app.is_feature_entitled(
    p_workspace_id, 'deals', pg_catalog.statement_timestamp()
  ) then
    return false;
  end if;
  if app.has_permission(p_workspace_id, 'workflow.read') then
    return true;
  end if;
  domain_permission := app.workflow_entity_read_permission(p_entity_type);
  return domain_permission is not null
    and app.has_permission(p_workspace_id, domain_permission);
end;
$$;

alter table public.deal_type_definitions enable row level security;
alter table public.deal_type_definitions force row level security;
alter table public.deal_type_versions enable row level security;
alter table public.deal_type_versions force row level security;
alter table public.deal_line_items enable row level security;
alter table public.deal_line_items force row level security;
alter table public.deal_command_receipts enable row level security;
alter table public.deal_command_receipts force row level security;

drop policy deals_select on public.deals;
create policy deals_select
on public.deals
for select to authenticated
using (app.can_read_deal_workspace(workspace_id));

drop policy deal_participants_select on public.deal_participants;
create policy deal_participants_select
on public.deal_participants
for select to authenticated
using (
  app.can_read_deal_workspace(workspace_id)
  and app.is_feature_entitled(
    workspace_id, 'crm', pg_catalog.statement_timestamp()
  )
  and app.has_permission(workspace_id, 'crm.read')
);

drop policy deal_inventory_units_select on public.deal_inventory_units;
create policy deal_inventory_units_select
on public.deal_inventory_units
for select to authenticated
using (
  app.can_read_deal_workspace(workspace_id)
  and app.has_permission(workspace_id, 'inventory.read')
);

create policy deal_type_definitions_select
on public.deal_type_definitions
for select to authenticated
using (app.can_read_deal_workspace(workspace_id));

create policy deal_type_versions_select
on public.deal_type_versions
for select to authenticated
using (app.can_read_deal_workspace(workspace_id));

create policy deal_line_items_select
on public.deal_line_items
for select to authenticated
using (app.can_read_deal_workspace(workspace_id));

revoke all on table
  public.deal_type_definitions,
  public.deal_type_versions,
  public.deal_line_items,
  public.deal_command_receipts
from public, anon, authenticated, service_role;

grant select on
  public.deal_type_definitions,
  public.deal_type_versions,
  public.deal_line_items
to authenticated, service_role;

grant select on public.deal_command_receipts to service_role;

revoke all on function app.deal_configuration_keys_valid(text[])
  from public, anon, authenticated, service_role;
revoke all on function app.deal_type_configuration_artifact(
  text, text, integer, jsonb, jsonb, jsonb, jsonb, text[], text[], jsonb,
  text, text, text
) from public, anon, authenticated, service_role;
revoke all on function app.deal_type_configuration_checksum(
  text, text, integer, jsonb, jsonb, jsonb, jsonb, text[], text[], jsonb,
  text, text, text
) from public, anon, authenticated, service_role;
revoke all on function app.deal_type_version_artifact(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.validate_deal_type_version_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app.protect_deal_type_version()
  from public, anon, authenticated, service_role;
revoke all on function app.prevent_deal_history_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.require_deal_permission(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.can_read_deal_workspace(uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.deal_command_fingerprint(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.assert_deal_command_metadata(text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.lock_deal_command(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function app.append_deal_outbox_event(
  uuid, text, uuid, bigint, jsonb, uuid, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.record_deal_command_receipt(
  uuid, uuid, text, text, text, uuid, bigint, jsonb, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.assert_deal_type_configuration()
  from public, anon, authenticated, service_role;
revoke all on function app.attach_configured_deal_workflow()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_deal_workflow_link()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_deal_participant_link()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_deal_inventory_link()
  from public, anon, authenticated, service_role;
revoke all on function app.parse_deal_minor_units(text)
  from public, anon, authenticated, service_role;
revoke all on function app.lock_active_deal(uuid, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function app.bump_deal_aggregate_version(uuid, uuid, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function app.deal_field_is_present(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.deal_required_fields_complete(uuid, uuid, text[])
  from public, anon, authenticated, service_role;
revoke all on function app.deal_external_finance_approved(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.deal_guard_is_satisfied(uuid, uuid, text)
  from public, anon, authenticated, service_role;

grant execute on function app.deal_type_configuration_artifact(
  text, text, integer, jsonb, jsonb, jsonb, jsonb, text[], text[], jsonb,
  text, text, text
) to service_role;
grant execute on function app.can_read_deal_workspace(uuid) to authenticated;
grant execute on function app.deal_type_configuration_checksum(
  text, text, integer, jsonb, jsonb, jsonb, jsonb, text[], text[], jsonb,
  text, text, text
) to service_role;

revoke all on function app.m3_create_deal(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_update_deal(
  uuid, text, uuid, bigint, uuid, uuid, uuid, text, boolean, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_transition_deal(
  uuid, text, uuid, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_add_deal_participant(
  uuid, text, uuid, bigint, uuid, text, boolean, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_release_deal_participant(
  uuid, text, uuid, bigint, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_add_deal_inventory(
  uuid, text, uuid, bigint, uuid, text, text, text, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_release_deal_inventory(
  uuid, text, uuid, bigint, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_add_deal_line_item(
  uuid, text, uuid, bigint, text, text, text, text, text, text,
  text, text, integer, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_update_deal_line_item(
  uuid, text, uuid, bigint, uuid, bigint, text, text, text, text,
  text, text, text, integer, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.m3_create_deal(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, text, uuid
) to authenticated;
grant execute on function app.m3_update_deal(
  uuid, text, uuid, bigint, uuid, uuid, uuid, text, boolean, text, uuid
) to authenticated;
grant execute on function app.m3_transition_deal(
  uuid, text, uuid, bigint, text, text, text, uuid
) to authenticated;
grant execute on function app.m3_add_deal_participant(
  uuid, text, uuid, bigint, uuid, text, boolean, text, uuid
) to authenticated;
grant execute on function app.m3_release_deal_participant(
  uuid, text, uuid, bigint, uuid, text, uuid
) to authenticated;
grant execute on function app.m3_add_deal_inventory(
  uuid, text, uuid, bigint, uuid, text, text, text, jsonb, text, uuid
) to authenticated;
grant execute on function app.m3_release_deal_inventory(
  uuid, text, uuid, bigint, uuid, text, uuid
) to authenticated;
grant execute on function app.m3_add_deal_line_item(
  uuid, text, uuid, bigint, text, text, text, text, text, text,
  text, text, integer, text, text, text, uuid
) to authenticated;
grant execute on function app.m3_update_deal_line_item(
  uuid, text, uuid, bigint, uuid, bigint, text, text, text, text,
  text, text, text, integer, text, text, text, uuid
) to authenticated;

comment on table public.deal_type_versions is
  'Immutable versioned deal configuration with translated deal and option labels, exact checksum, allowed roles, behavior flags, and a pinned workflow version.';
comment on table public.deal_line_items is
  'Exact deal rows preserving caller canonical quantity strings and bigint minor-unit amounts without tax or calculation execution.';
comment on table public.deal_command_receipts is
  'Append-only actor-scoped idempotency evidence for M3 deal commands.';
comment on column public.deals.originating_lead_id is
  'Optional lead provenance; the lead migration adds its composite workspace foreign key after public.leads exists.';
comment on function app.m3_transition_deal(
  uuid, text, uuid, bigint, text, text, text, uuid
) is 'Atomic pinned-workflow deal transition with version, permission, required-field, guard, reason, workflow-event, audit, outbox, and actor-idempotency enforcement.';
create function app.m3_list_deals(
  p_workspace_id uuid,
  p_limit integer default 50,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_status text default null,
  p_owner_membership_id uuid default null
)
returns table (
  deal_id uuid,
  deal_type_key text,
  deal_type_version_id uuid,
  deal_type_labels jsonb,
  currency_code text,
  canonical_status text,
  state_key text,
  available_transitions jsonb,
  lifecycle_status text,
  owner_membership_id uuid,
  location_id uuid,
  legal_entity_id uuid,
  originating_lead_id uuid,
  notes text,
  aggregate_version bigint,
  active_participant_count bigint,
  active_inventory_count bigint,
  active_line_item_count bigint,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_deal_permission(p_workspace_id, 'deals.read');
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'deal list limit must be between 1 and 100';
  end if;
  if (p_cursor_updated_at is null) <> (p_cursor_id is null) then
    raise exception using errcode = '22023', message = 'deal list cursor is incomplete';
  end if;
  if p_status is not null and p_status not in ('draft', 'active', 'pending', 'closed', 'archived') then
    raise exception using errcode = '22023', message = 'invalid deal status filter';
  end if;
  return query
  select
    deal.id,
    deal.deal_type_key,
    deal.deal_type_version_id,
    version.labels,
    deal.currency_code::text,
    deal.status,
    deal.workflow_state_key,
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'transitionKey', available.transition_key,
          'toStateKey', available.to_state_key,
          'reasonRequired', available.reason_required,
          'labels', available.labels
        )
        order by available.sort_order, available.transition_key
      )
      from (
        select
          transition.key as transition_key,
          transition.to_state_key,
          transition.reason_required,
          target_state.labels,
          target_state.sort_order
        from public.workflow_transitions transition
        join public.workflow_states target_state
          on target_state.workspace_id = transition.workspace_id
         and target_state.workflow_version_id = transition.workflow_version_id
         and target_state.key = transition.to_state_key
        where deal.lifecycle_status = 'active'
          and transition.workspace_id = deal.workspace_id
          and transition.workflow_version_id = deal.workflow_version_id
          and transition.from_state_key = deal.workflow_state_key
          and app.has_permission(p_workspace_id, transition.permission_key)
        order by target_state.sort_order, transition.key
        limit 100
      ) available
    ), '[]'::jsonb),
    deal.lifecycle_status,
    deal.owner_membership_id,
    deal.location_id,
    deal.legal_entity_id,
    deal.originating_lead_id,
    deal.notes,
    deal.version,
    (select pg_catalog.count(*) from public.deal_participants participant
      where participant.workspace_id = deal.workspace_id
        and participant.deal_id = deal.id and participant.status = 'active'),
    (select pg_catalog.count(*) from public.deal_inventory_units inventory_link
      where inventory_link.workspace_id = deal.workspace_id
        and inventory_link.deal_id = deal.id and inventory_link.status = 'active'),
    (select pg_catalog.count(*) from public.deal_line_items line_item
      where line_item.workspace_id = deal.workspace_id
        and line_item.deal_id = deal.id and line_item.status = 'active'),
    deal.updated_at
  from public.deals deal
  join public.deal_type_versions version
    on version.workspace_id = deal.workspace_id
   and version.id = deal.deal_type_version_id
  where deal.workspace_id = p_workspace_id
    and (p_status is null or deal.status = p_status)
    and (p_owner_membership_id is null or deal.owner_membership_id = p_owner_membership_id)
    and (
      p_cursor_updated_at is null
      or (deal.updated_at, deal.id) < (p_cursor_updated_at, p_cursor_id)
    )
  order by deal.updated_at desc, deal.id desc
  limit p_limit;
end;
$$;

revoke all on function app.m3_list_deals(
  uuid, integer, timestamptz, uuid, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.m3_list_deals(
  uuid, integer, timestamptz, uuid, text, uuid
) to authenticated;
comment on function app.m3_list_deals(
  uuid, integer, timestamptz, uuid, text, uuid
) is 'Bounded entitlement- and permission-gated deal projection; no calculated totals, tax, official documents, exports, or servicing.';

create function app.m3_get_deal(
  p_workspace_id uuid,
  p_deal_id uuid
)
returns table (
  deal_id uuid,
  deal_type_key text,
  deal_type_definition_id uuid,
  deal_type_version_id uuid,
  deal_type_version text,
  deal_type_revision bigint,
  deal_type_checksum text,
  deal_type_source text,
  deal_type_labels jsonb,
  deal_type_field_schema jsonb,
  deal_type_behavior_flags jsonb,
  participant_role_options jsonb,
  inventory_role_options jsonb,
  one_time_event_type_options jsonb,
  workflow_version_id uuid,
  workflow_instance_id uuid,
  currency_code text,
  canonical_status text,
  state_key text,
  available_transitions jsonb,
  lifecycle_status text,
  owner_membership_id uuid,
  location_id uuid,
  legal_entity_id uuid,
  originating_lead_id uuid,
  notes text,
  effective_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  closed_reason text,
  aggregate_version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_deal_permission(p_workspace_id, 'deals.read');
  return query
  select
    deal.id,
    deal.deal_type_key,
    deal.deal_type_definition_id,
    deal.deal_type_version_id,
    type_version.version,
    type_version.revision,
    type_version.checksum,
    type_version.source,
    type_version.labels,
    type_version.field_schema,
    type_version.behavior_flags,
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', configured_role.key,
          'labels', type_version.option_labels -> 'participant_roles' -> configured_role.key
        )
        order by configured_role.position
      )
      from pg_catalog.unnest(
        type_version.allowed_participant_roles
      ) with ordinality configured_role(key, position)
    ), '[]'::jsonb),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', configured_role.key,
          'labels', type_version.option_labels -> 'inventory_roles' -> configured_role.key
        )
        order by configured_role.position
      )
      from pg_catalog.unnest(
        type_version.allowed_inventory_roles
      ) with ordinality configured_role(key, position)
    ), '[]'::jsonb),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', configured_event.key,
          'labels', type_version.option_labels -> 'one_time_event_types' -> configured_event.key
        )
        order by configured_event.position
      )
      from pg_catalog.jsonb_array_elements_text(
        coalesce(
          type_version.behavior_flags -> 'one_time_event_types',
          '[]'::jsonb
        )
      ) with ordinality configured_event(key, position)
    ), '[]'::jsonb),
    deal.workflow_version_id,
    deal.workflow_instance_id,
    deal.currency_code::text,
    deal.status,
    deal.workflow_state_key,
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'transitionKey', available.transition_key,
          'toStateKey', available.to_state_key,
          'reasonRequired', available.reason_required,
          'labels', available.labels
        )
        order by available.sort_order, available.transition_key
      )
      from (
        select
          transition.key as transition_key,
          transition.to_state_key,
          transition.reason_required,
          target_state.labels,
          target_state.sort_order
        from public.workflow_transitions transition
        join public.workflow_states target_state
          on target_state.workspace_id = transition.workspace_id
         and target_state.workflow_version_id = transition.workflow_version_id
         and target_state.key = transition.to_state_key
        where deal.lifecycle_status = 'active'
          and transition.workspace_id = deal.workspace_id
          and transition.workflow_version_id = deal.workflow_version_id
          and transition.from_state_key = deal.workflow_state_key
          and app.has_permission(p_workspace_id, transition.permission_key)
        order by target_state.sort_order, transition.key
        limit 100
      ) available
    ), '[]'::jsonb),
    deal.lifecycle_status,
    deal.owner_membership_id,
    deal.location_id,
    deal.legal_entity_id,
    deal.originating_lead_id,
    deal.notes,
    deal.effective_at,
    deal.completed_at,
    deal.cancelled_at,
    deal.closed_reason,
    deal.version,
    deal.created_at,
    deal.updated_at
  from public.deals deal
  join public.deal_type_versions type_version
    on type_version.workspace_id = deal.workspace_id
   and type_version.id = deal.deal_type_version_id
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
end;
$$;

create function app.m3_list_deal_participants(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_limit integer default 100,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null
)
returns table (
  participant_id uuid,
  party_id uuid,
  party_display_name text,
  role_key text,
  is_primary boolean,
  status text,
  version bigint,
  created_by uuid,
  released_by uuid,
  created_at timestamptz,
  released_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_deal_permission(p_workspace_id, 'deals.read');
  if not app.is_feature_entitled(
      p_workspace_id, 'crm', pg_catalog.statement_timestamp()
    ) or not app.has_permission(p_workspace_id, 'crm.read') then
    raise exception using errcode = '42501', message = 'active CRM entitlement and read permission are required for deal participants';
  end if;
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'deal participant list limit must be between 1 and 100';
  end if;
  if (p_cursor_created_at is null) <> (p_cursor_id is null) then
    raise exception using errcode = '22023', message = 'deal participant cursor is incomplete';
  end if;
  if not exists (
    select 1 from public.deals deal
    where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  ) then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  return query
  select
    participant.id,
    participant.party_id,
    party.display_name,
    participant.role_key,
    participant.is_primary,
    participant.status,
    participant.version,
    participant.created_by,
    participant.released_by,
    participant.created_at,
    participant.released_at
  from public.deal_participants participant
  join public.parties party
    on party.workspace_id = participant.workspace_id
   and party.id = participant.party_id
  where participant.workspace_id = p_workspace_id
    and participant.deal_id = p_deal_id
    and (
      p_cursor_created_at is null
      or (participant.created_at, participant.id)
        > (p_cursor_created_at, p_cursor_id)
    )
  order by participant.created_at, participant.id
  limit p_limit;
end;
$$;

create function app.m3_list_deal_inventory(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_limit integer default 100,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null
)
returns table (
  inventory_link_id uuid,
  inventory_unit_id uuid,
  stock_number text,
  inventory_status text,
  role_key text,
  amount_minor text,
  currency_code text,
  metadata jsonb,
  status text,
  version bigint,
  created_by uuid,
  released_by uuid,
  created_at timestamptz,
  released_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_deal_permission(p_workspace_id, 'deals.read');
  if not app.has_permission(p_workspace_id, 'inventory.read') then
    raise exception using errcode = '42501', message = 'inventory read permission is required for deal inventory links';
  end if;
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'deal inventory list limit must be between 1 and 100';
  end if;
  if (p_cursor_created_at is null) <> (p_cursor_id is null) then
    raise exception using errcode = '22023', message = 'deal inventory cursor is incomplete';
  end if;
  if not exists (
    select 1 from public.deals deal
    where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  ) then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  return query
  select
    inventory_link.id,
    inventory_link.inventory_unit_id,
    inventory.stock_number::text,
    inventory.status,
    inventory_link.role_key,
    inventory_link.amount_minor::text,
    inventory_link.currency_code::text,
    inventory_link.metadata,
    inventory_link.status,
    inventory_link.version,
    inventory_link.created_by,
    inventory_link.released_by,
    inventory_link.created_at,
    inventory_link.released_at
  from public.deal_inventory_units inventory_link
  join public.inventory_units inventory
    on inventory.workspace_id = inventory_link.workspace_id
   and inventory.id = inventory_link.inventory_unit_id
  where inventory_link.workspace_id = p_workspace_id
    and inventory_link.deal_id = p_deal_id
    and (
      p_cursor_created_at is null
      or (inventory_link.created_at, inventory_link.id)
        > (p_cursor_created_at, p_cursor_id)
    )
  order by inventory_link.created_at, inventory_link.id
  limit p_limit;
end;
$$;

create function app.m3_list_deal_line_items(
  p_workspace_id uuid,
  p_deal_id uuid,
  p_limit integer default 100,
  p_cursor_sort_order integer default null,
  p_cursor_id uuid default null
)
returns table (
  line_item_id uuid,
  key text,
  item_type text,
  label text,
  quantity text,
  unit_amount_minor text,
  currency_code text,
  tax_classification_key text,
  payment_timing_key text,
  sort_order integer,
  source_key text,
  source_reference text,
  status text,
  version bigint,
  created_by uuid,
  updated_by uuid,
  released_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  released_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_deal_permission(p_workspace_id, 'deals.read');
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'deal line-item list limit must be between 1 and 100';
  end if;
  if (p_cursor_sort_order is null) <> (p_cursor_id is null)
    or (p_cursor_sort_order is not null and p_cursor_sort_order < 0) then
    raise exception using errcode = '22023', message = 'deal line-item cursor is invalid';
  end if;
  if not exists (
    select 1 from public.deals deal
    where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  ) then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  return query
  select
    line_item.id,
    line_item.key,
    line_item.item_type,
    line_item.label,
    line_item.quantity_text,
    line_item.unit_amount_minor::text,
    line_item.currency_code::text,
    line_item.tax_classification_key,
    line_item.payment_timing_key,
    line_item.sort_order,
    line_item.source_key,
    line_item.source_reference,
    line_item.status,
    line_item.version,
    line_item.created_by,
    line_item.updated_by,
    line_item.released_by,
    line_item.created_at,
    line_item.updated_at,
    line_item.released_at
  from public.deal_line_items line_item
  where line_item.workspace_id = p_workspace_id
    and line_item.deal_id = p_deal_id
    and (
      p_cursor_sort_order is null
      or (line_item.sort_order, line_item.id)
        > (p_cursor_sort_order, p_cursor_id)
    )
  order by line_item.sort_order, line_item.id
  limit p_limit;
end;
$$;

revoke all on function app.m3_get_deal(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_list_deal_participants(
  uuid, uuid, integer, timestamptz, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_list_deal_inventory(
  uuid, uuid, integer, timestamptz, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_list_deal_line_items(
  uuid, uuid, integer, integer, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.m3_get_deal(uuid, uuid) to authenticated;
grant execute on function app.m3_list_deal_participants(
  uuid, uuid, integer, timestamptz, uuid
) to authenticated;
grant execute on function app.m3_list_deal_inventory(
  uuid, uuid, integer, timestamptz, uuid
) to authenticated;
grant execute on function app.m3_list_deal_line_items(
  uuid, uuid, integer, integer, uuid
) to authenticated;

comment on function app.m3_get_deal(uuid, uuid) is
  'Strict deal detail projection with exact pinned type/workflow identifiers, ordered bilingual role/event options, authorized transitions, and no calculated totals or M4 behavior.';
comment on function app.m3_list_deal_participants(
  uuid, uuid, integer, timestamptz, uuid
) is 'Bounded deal participant history requiring deals and CRM read authority.';
comment on function app.m3_list_deal_inventory(
  uuid, uuid, integer, timestamptz, uuid
) is 'Bounded deal inventory-link history requiring deals and inventory read authority; minor units are returned as exact text.';
comment on function app.m3_list_deal_line_items(
  uuid, uuid, integer, integer, uuid
) is 'Bounded exact line-item projection returning canonical quantities and bigint minor units as text without calculation or tax execution.';
