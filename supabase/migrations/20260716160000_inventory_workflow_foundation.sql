-- VYN-INV-001, VYN-WF-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001,
-- VYN-JOB-001, VYN-API-001, T-INV-004, T-TEN-001, T-RBAC-001, T-AUD-001
-- M2-INV-AC-005, M2-INV-AC-006, M2-INV-AC-010, M2-INV-AC-011
-- Forward-only inventory location and workflow foundation. Existing M1 create
-- commands remain compatible while new commands use optimistic concurrency,
-- idempotent receipts, audit, and the transactional outbox.

insert into public.permissions (key, description, source)
values
  (
    'inventory.duplicate_override',
    'Create a controlled duplicate VIN exception after review.',
    'platform'
  ),
  (
    'inventory.facts_override',
    'Correct authoritative physical-vehicle facts with provenance.',
    'platform'
  ),
  (
    'inventory.read_internal',
    'Read internal inventory notes and restricted operational detail.',
    'platform'
  ),
  (
    'inventory.update_internal',
    'Update internal inventory notes and restricted operational detail.',
    'platform'
  )
on conflict do nothing;

create table public.locations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null
    check (key::text ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  name text not null check (
    pg_catalog.btrim(name) <> '' and pg_catalog.char_length(name) <= 200
  ),
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  locale text check (
    locale is null or (
      pg_catalog.btrim(locale) <> '' and pg_catalog.char_length(locale) <= 64
    )
  ),
  timezone text check (
    timezone is null or (
      pg_catalog.btrim(timezone) <> '' and pg_catalog.char_length(timezone) <= 100
    )
  ),
  address jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(address) = 'object'),
  contact jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(contact) = 'object'),
  version bigint not null default 1 check (version > 0),
  created_by uuid references auth.users (id) on delete restrict,
  updated_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key)
);

create index locations_workspace_status_idx
  on public.locations (workspace_id, status, name, id);

create table public.workflow_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null
    check (key::text ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  entity_type text not null
    check (entity_type ~ '^[a-z][a-z0-9_]*$'),
  purpose_key text not null default 'primary'
    check (purpose_key ~ '^[a-z][a-z0-9_]*$'),
  status text not null default 'active'
    check (status in ('active', 'retired')),
  created_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key)
);

create table public.workflow_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  workflow_definition_id uuid not null,
  version text not null check (
    pg_catalog.char_length(version) between 5 and 64
    and version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'
  ),
  schema_version integer not null default 1 check (schema_version > 0),
  initial_state_key text not null
    check (initial_state_key ~ '^[a-z][a-z0-9_]*$'),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  source text not null default 'configuration'
    check (source in ('configuration', 'starter_pack', 'migration_compatibility')),
  created_by uuid references auth.users (id) on delete restrict,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, workflow_definition_id, version),
  foreign key (workspace_id, workflow_definition_id)
    references public.workflow_definitions (workspace_id, id)
    on delete restrict,
  check (
    (status = 'draft' and activated_at is null and retired_at is null)
    or (status = 'active' and activated_at is not null and retired_at is null)
    or (status = 'retired' and activated_at is not null and retired_at is not null)
  )
);

create unique index workflow_versions_active_definition_uidx
  on public.workflow_versions (workspace_id, workflow_definition_id)
  where status = 'active';

create table public.workflow_states (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  workflow_version_id uuid not null,
  key text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  canonical_category text not null
    check (canonical_category in ('draft', 'active', 'pending', 'closed', 'archived')),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(labels, '$.keyvalue()')) > 0
  ),
  behavior_flags jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(behavior_flags) = 'object'),
  sort_order integer not null default 0,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, workflow_version_id, key),
  foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id)
    on delete restrict
);

create table public.workflow_transitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  workflow_version_id uuid not null,
  key text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  from_state_key text not null check (from_state_key ~ '^[a-z][a-z0-9_]*$'),
  to_state_key text not null check (to_state_key ~ '^[a-z][a-z0-9_]*$'),
  permission_key text not null
    check (permission_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'),
  guard_key text check (
    guard_key is null or guard_key in (
      'required_fields_complete',
      'sale_completion_requirements_met'
    )
  ),
  reason_required boolean not null default false,
  effect_keys jsonb not null default '[]'::jsonb
    check (pg_catalog.jsonb_typeof(effect_keys) = 'array'),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, workflow_version_id, key),
  foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, workflow_version_id, from_state_key)
    references public.workflow_states (workspace_id, workflow_version_id, key)
    on delete restrict,
  foreign key (workspace_id, workflow_version_id, to_state_key)
    references public.workflow_states (workspace_id, workflow_version_id, key)
    on delete restrict,
  check (from_state_key <> to_state_key)
);

create table public.workflow_instances (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  workflow_version_id uuid not null,
  entity_type text not null check (entity_type ~ '^[a-z][a-z0-9_]*$'),
  entity_id uuid not null,
  purpose_key text not null default 'primary'
    check (purpose_key ~ '^[a-z][a-z0-9_]*$'),
  current_state_key text not null check (current_state_key ~ '^[a-z][a-z0-9_]*$'),
  canonical_status text not null
    check (canonical_status in ('draft', 'active', 'pending', 'closed', 'archived')),
  lifecycle_status text not null default 'active'
    check (lifecycle_status in ('active', 'completed')),
  version bigint not null default 1 check (version > 0),
  started_at timestamptz not null default pg_catalog.statement_timestamp(),
  completed_at timestamptz,
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, entity_type, entity_id, purpose_key),
  foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, workflow_version_id, current_state_key)
    references public.workflow_states (workspace_id, workflow_version_id, key)
    on delete restrict,
  check (
    (lifecycle_status = 'active' and completed_at is null)
    or (lifecycle_status = 'completed' and completed_at is not null)
  )
);

create index workflow_instances_workspace_state_idx
  on public.workflow_instances (
    workspace_id,
    entity_type,
    canonical_status,
    current_state_key,
    updated_at desc,
    id
  );

create table public.workflow_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  workflow_instance_id uuid not null,
  transition_id uuid not null,
  entity_type text not null check (entity_type ~ '^[a-z][a-z0-9_]*$'),
  entity_id uuid not null,
  from_state_key text not null,
  to_state_key text not null,
  aggregate_version bigint not null check (aggregate_version > 0),
  reason text check (
    reason is null or (
      pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
    )
  ),
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  request_id text check (
    request_id is null or pg_catalog.char_length(request_id) <= 200
  ),
  correlation_id uuid not null,
  occurred_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, workflow_instance_id)
    references public.workflow_instances (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, transition_id)
    references public.workflow_transitions (workspace_id, id)
    on delete restrict
);

create index workflow_events_entity_time_idx
  on public.workflow_events (
    workspace_id,
    entity_type,
    entity_id,
    occurred_at desc,
    id
  );

alter table public.inventory_units
  drop constraint inventory_units_status_check;
alter table public.inventory_units
  add constraint inventory_units_status_check
  check (status in ('draft', 'active', 'pending', 'closed', 'archived'));

alter table public.inventory_units
  add column location_id uuid,
  add column condition_key text check (
    condition_key is null
    or condition_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
  ),
  add column expected_sale_price_minor bigint check (
    expected_sale_price_minor is null or expected_sale_price_minor >= 0
  ),
  add column expected_sale_price_currency_code char(3) check (
    expected_sale_price_currency_code is null
    or expected_sale_price_currency_code ~ '^[A-Z]{3}$'
  ),
  add column acquired_at timestamptz,
  add column available_at timestamptz,
  add column sold_at timestamptz,
  add column closed_at timestamptz,
  add column workflow_instance_id uuid,
  add column workflow_state_key text check (
    workflow_state_key is null or workflow_state_key ~ '^[a-z][a-z0-9_]*$'
  ),
  add constraint inventory_units_location_fk
    foreign key (workspace_id, location_id)
    references public.locations (workspace_id, id)
    on delete restrict,
  add constraint inventory_units_workflow_instance_fk
    foreign key (workspace_id, workflow_instance_id)
    references public.workflow_instances (workspace_id, id)
    on delete restrict
    deferrable initially deferred,
  add constraint inventory_units_expected_price_pair_check check (
    (expected_sale_price_minor is null and expected_sale_price_currency_code is null)
    or (
      expected_sale_price_minor is not null
      and expected_sale_price_currency_code is not null
      and expected_sale_price_currency_code = currency_code
    )
  ),
  add constraint inventory_units_lifecycle_time_check check (
    (available_at is null or acquired_at is null or available_at >= acquired_at)
    and (sold_at is null or acquired_at is null or sold_at >= acquired_at)
    and (closed_at is null or acquired_at is null or closed_at >= acquired_at)
    and (closed_at is null or sold_at is null or closed_at >= sold_at)
  ),
  add constraint inventory_units_available_location_check check (
    available_at is null or location_id is not null
  );

drop index public.inventory_units_active_vehicle_uidx;
create unique index inventory_units_open_vehicle_uidx
  on public.inventory_units (workspace_id, vehicle_id)
  where status in ('draft', 'active', 'pending');
create index inventory_units_workspace_location_status_idx
  on public.inventory_units (workspace_id, location_id, status, updated_at desc, id);
create index inventory_units_workspace_workflow_state_idx
  on public.inventory_units (
    workspace_id,
    workflow_state_key,
    status,
    updated_at desc,
    id
  );

create table public.inventory_unit_internal_details (
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  inventory_unit_id uuid not null,
  internal_notes text check (
    internal_notes is null or pg_catalog.char_length(internal_notes) <= 8000
  ),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  primary key (workspace_id, inventory_unit_id),
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id)
    on delete restrict
);

create table public.inventory_location_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  inventory_unit_id uuid not null,
  from_location_id uuid,
  to_location_id uuid not null,
  aggregate_version bigint not null check (aggregate_version > 0),
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  request_id text check (
    request_id is null or pg_catalog.char_length(request_id) <= 200
  ),
  correlation_id uuid not null,
  effective_at timestamptz not null default pg_catalog.statement_timestamp(),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, from_location_id)
    references public.locations (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, to_location_id)
    references public.locations (workspace_id, id)
    on delete restrict,
  check (from_location_id is null or from_location_id <> to_location_id)
);

create index inventory_location_events_unit_time_idx
  on public.inventory_location_events (
    workspace_id,
    inventory_unit_id,
    effective_at desc,
    id
  );

create table public.inventory_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  command_type text not null check (command_type in (
    'update_inventory_unit_details',
    'transfer_inventory_unit_location',
    'transition_inventory_workflow'
  )),
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  command_fingerprint text not null
    check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  inventory_unit_id uuid not null,
  result jsonb not null check (pg_catalog.jsonb_typeof(result) = 'object'),
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, command_type, idempotency_key),
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id)
    on delete restrict
);

create function app.prevent_inventory_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'inventory and workflow history is append-only';
end;
$$;

create function app.validate_workflow_transition_configuration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(new.effect_keys) effect(effect_key)
    where effect.effect_key not in (
      'listing.publish',
      'listing.unpublish',
      'listing.refresh',
      'media.retention_review'
    )
  ) then
    raise exception using
      errcode = '23514',
      message = 'workflow transition effect is not allowlisted';
  end if;

  return new;
end;
$$;

create function app.protect_activated_workflow_configuration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_status text;
begin
  if tg_table_name = 'workflow_versions' then
    if tg_op = 'INSERT' then
      return new;
    end if;

    if old.status = 'draft' then
      return case when tg_op = 'DELETE' then old else new end;
    end if;

    -- Retirement is the only lifecycle change permitted on an active version.
    -- Its definition, semantic version, checksum, provenance, and activation
    -- timestamp remain byte-for-byte immutable so existing instances stay
    -- pinned to the exact configuration that was executed.
    if tg_op = 'UPDATE'
      and old.status = 'active'
      and new.status = 'retired'
      and old.retired_at is null
      and new.retired_at is not null
      and row(
        new.id,
        new.workspace_id,
        new.workflow_definition_id,
        new.version,
        new.schema_version,
        new.initial_state_key,
        new.checksum,
        new.source,
        new.created_by,
        new.activated_at,
        new.created_at
      ) is not distinct from row(
        old.id,
        old.workspace_id,
        old.workflow_definition_id,
        old.version,
        old.schema_version,
        old.initial_state_key,
        old.checksum,
        old.source,
        old.created_by,
        old.activated_at,
        old.created_at
      ) then
      return new;
    end if;

    version_status := old.status;
  else
    select version.status
      into version_status
    from public.workflow_versions version
    where version.workspace_id = case
        when tg_op = 'INSERT' then new.workspace_id else old.workspace_id
      end
      and version.id = case
        when tg_op = 'INSERT' then new.workflow_version_id else old.workflow_version_id
      end
    for update;
  end if;

  if version_status in ('active', 'retired') then
    raise exception using
      errcode = '55000',
      message = 'activated workflow configuration is immutable';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create function app.validate_workflow_version_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
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
      cross join lateral pg_catalog.jsonb_each(state.labels) label
      where state.workspace_id = new.workspace_id
        and state.workflow_version_id = new.id
        and pg_catalog.jsonb_typeof(label.value) <> 'string'
    ) then
      raise exception using
        errcode = '23514',
        message = 'workflow state labels must be localized strings';
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

create function app.assert_inventory_workflow_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  linked_instance public.workflow_instances%rowtype;
begin
  if new.workflow_instance_id is null then
    if new.workflow_state_key is not null then
      raise exception using
        errcode = '23514',
        message = 'inventory workflow state requires a workflow instance';
    end if;
    return new;
  end if;

  select instance.*
    into linked_instance
  from public.workflow_instances instance
  where instance.workspace_id = new.workspace_id
    and instance.id = new.workflow_instance_id;

  if not found
    or linked_instance.entity_type <> 'inventory_unit'
    or linked_instance.entity_id <> new.id
    or linked_instance.purpose_key <> 'primary'
    or linked_instance.current_state_key <> new.workflow_state_key
    or linked_instance.canonical_status <> new.status
    or linked_instance.version <> new.version then
    raise exception using
      errcode = '23514',
      message = 'inventory workflow link must match the workspace-owned aggregate state';
  end if;

  return new;
end;
$$;

create function app.attach_configured_inventory_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  configured_version_id uuid;
  configured_state_key text;
  configured_category text;
  new_instance_id uuid;
begin
  if new.workflow_instance_id is not null then
    return new;
  end if;

  select
    version.id,
    state.key,
    state.canonical_category
    into
      configured_version_id,
      configured_state_key,
      configured_category
  from public.workflow_definitions definition
  join public.workflow_versions version
    on version.workspace_id = definition.workspace_id
   and version.workflow_definition_id = definition.id
   and version.status = 'active'
  join public.workflow_states state
    on state.workspace_id = version.workspace_id
   and state.workflow_version_id = version.id
  where definition.workspace_id = new.workspace_id
    and definition.key = 'inventory.standard'
    and definition.entity_type = 'inventory_unit'
    and definition.purpose_key = 'primary'
    and definition.status = 'active'
    and (
      state.key = new.status
      or state.canonical_category = new.status
    )
  order by
    case when state.key = new.status then 0 else 1 end,
    state.sort_order,
    state.key
  limit 1;

  -- A workspace may legitimately have no configured workflow during a rolling
  -- M1-to-M2 deployment. The old create contract remains valid and nullable
  -- linkage is removed only in a later contract migration.
  if not found then
    return new;
  end if;

  new_instance_id := pg_catalog.gen_random_uuid();
  insert into public.workflow_instances (
    id,
    workspace_id,
    workflow_version_id,
    entity_type,
    entity_id,
    purpose_key,
    current_state_key,
    canonical_status,
    lifecycle_status,
    version,
    completed_at
  ) values (
    new_instance_id,
    new.workspace_id,
    configured_version_id,
    'inventory_unit',
    new.id,
    'primary',
    configured_state_key,
    configured_category,
    case when configured_category in ('closed', 'archived')
      then 'completed' else 'active' end,
    new.version,
    case when configured_category in ('closed', 'archived')
      then pg_catalog.statement_timestamp() else null end
  );

  new.workflow_instance_id := new_instance_id;
  new.workflow_state_key := configured_state_key;
  new.status := configured_category;
  return new;
end;
$$;

create trigger locations_updated_at
before update on public.locations
for each row execute function app.set_updated_at();
create trigger workflow_instances_updated_at
before update on public.workflow_instances
for each row execute function app.set_updated_at();
create trigger inventory_unit_internal_details_updated_at
before update on public.inventory_unit_internal_details
for each row execute function app.set_updated_at();

create trigger locations_immutable_ownership
before update on public.locations
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'created_by', 'created_at'
);
create trigger workflow_definitions_immutable_ownership
before update on public.workflow_definitions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'entity_type', 'purpose_key', 'created_by', 'created_at'
);
create trigger workflow_instances_immutable_ownership
before update on public.workflow_instances
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'workflow_version_id', 'entity_type', 'entity_id',
  'purpose_key', 'started_at'
);
create trigger inventory_unit_internal_details_immutable_ownership
before update on public.inventory_unit_internal_details
for each row execute function app.enforce_immutable_columns(
  'workspace_id', 'inventory_unit_id', 'created_by', 'created_at'
);

create trigger workflow_versions_protect_activated
before update or delete on public.workflow_versions
for each row execute function app.protect_activated_workflow_configuration();
create trigger workflow_versions_validate_lifecycle
before insert or update of status, activated_at, retired_at
on public.workflow_versions
for each row execute function app.validate_workflow_version_lifecycle();
create trigger workflow_states_protect_activated
before insert or update or delete on public.workflow_states
for each row execute function app.protect_activated_workflow_configuration();
create trigger workflow_transitions_protect_activated
before insert or update or delete on public.workflow_transitions
for each row execute function app.protect_activated_workflow_configuration();
create trigger workflow_transitions_validate_configuration
before insert or update on public.workflow_transitions
for each row execute function app.validate_workflow_transition_configuration();

create trigger workflow_events_append_only
before update or delete on public.workflow_events
for each row execute function app.prevent_inventory_history_mutation();
create trigger inventory_location_events_append_only
before update or delete on public.inventory_location_events
for each row execute function app.prevent_inventory_history_mutation();
create trigger inventory_command_receipts_append_only
before update or delete on public.inventory_command_receipts
for each row execute function app.prevent_inventory_history_mutation();
create trigger locations_prevent_hard_delete
before delete on public.locations
for each row execute function app.prevent_hard_delete();
create trigger workflow_definitions_prevent_hard_delete
before delete on public.workflow_definitions
for each row execute function app.prevent_hard_delete();
create trigger workflow_instances_prevent_hard_delete
before delete on public.workflow_instances
for each row execute function app.prevent_hard_delete();
create trigger inventory_unit_internal_details_prevent_hard_delete
before delete on public.inventory_unit_internal_details
for each row execute function app.prevent_hard_delete();

create trigger inventory_units_attach_configured_workflow
before insert on public.inventory_units
for each row execute function app.attach_configured_inventory_workflow();
create trigger inventory_units_validate_workflow_link
after insert or update of
  workspace_id,
  workflow_instance_id,
  workflow_state_key,
  status,
  version
on public.inventory_units
for each row execute function app.assert_inventory_workflow_link();

-- Existing M1 rows receive an immutable, tenant-neutral compatibility workflow.
-- It preserves the four canonical M1 statuses without pretending that a starter
-- pack had already been installed in a workspace.
insert into public.workflow_definitions (
  id,
  workspace_id,
  key,
  entity_type,
  purpose_key,
  status
)
select distinct
  pg_catalog.md5(unit.workspace_id::text || ':m1-inventory-compat-definition')::uuid,
  unit.workspace_id,
  'm1.inventory_compat',
  'inventory_unit',
  'primary',
  'active'
from public.inventory_units unit
on conflict (workspace_id, key) do nothing;

insert into public.workflow_versions (
  id,
  workspace_id,
  workflow_definition_id,
  version,
  schema_version,
  initial_state_key,
  status,
  checksum,
  source,
  activated_at
)
select
  pg_catalog.md5(definition.workspace_id::text || ':m1-inventory-compat-version')::uuid,
  definition.workspace_id,
  definition.id,
  '1.0.0',
  1,
  'draft',
  'draft',
  pg_catalog.encode(
    extensions.digest(
      'm1.inventory_compat|1.0.0|draft|active|closed|archived',
      'sha256'
    ),
    'hex'
  ),
  'migration_compatibility',
  null
from public.workflow_definitions definition
where definition.key = 'm1.inventory_compat'
on conflict (workspace_id, workflow_definition_id, version) do nothing;

insert into public.workflow_states (
  id,
  workspace_id,
  workflow_version_id,
  key,
  canonical_category,
  labels,
  behavior_flags,
  sort_order
)
select
  pg_catalog.md5(
    version.workspace_id::text || ':m1-inventory-compat-state:' || fixture.key
  )::uuid,
  version.workspace_id,
  version.id,
  fixture.key,
  fixture.category,
  pg_catalog.jsonb_build_object('en', fixture.label_en, 'fr', fixture.label_fr),
  pg_catalog.jsonb_build_object('terminal', fixture.terminal),
  fixture.sort_order
from public.workflow_versions version
join public.workflow_definitions definition
  on definition.workspace_id = version.workspace_id
 and definition.id = version.workflow_definition_id
cross join (values
  ('draft'::text, 'draft'::text, 'Draft'::text, 'Brouillon'::text, false, 10),
  ('active'::text, 'active'::text, 'Active'::text, 'Actif'::text, false, 20),
  ('closed'::text, 'closed'::text, 'Closed'::text, 'Fermé'::text, true, 30),
  ('archived'::text, 'archived'::text, 'Archived'::text, 'Archivé'::text, true, 40)
) fixture(key, category, label_en, label_fr, terminal, sort_order)
where definition.key = 'm1.inventory_compat'
on conflict (workspace_id, workflow_version_id, key) do nothing;

update public.workflow_versions version
set status = 'active',
    activated_at = pg_catalog.statement_timestamp()
from public.workflow_definitions definition
where definition.workspace_id = version.workspace_id
  and definition.id = version.workflow_definition_id
  and definition.key = 'm1.inventory_compat'
  and version.version = '1.0.0'
  and version.status = 'draft';

insert into public.workflow_instances (
  id,
  workspace_id,
  workflow_version_id,
  entity_type,
  entity_id,
  purpose_key,
  current_state_key,
  canonical_status,
  lifecycle_status,
  version,
  completed_at
)
select
  pg_catalog.md5(unit.id::text || ':m1-inventory-compat-instance')::uuid,
  unit.workspace_id,
  version.id,
  'inventory_unit',
  unit.id,
  'primary',
  unit.status,
  unit.status,
  case when unit.status in ('closed', 'archived') then 'completed' else 'active' end,
  unit.version,
  case when unit.status in ('closed', 'archived')
    then coalesce(unit.closed_at, unit.updated_at) else null end
from public.inventory_units unit
join public.workflow_definitions definition
  on definition.workspace_id = unit.workspace_id
 and definition.key = 'm1.inventory_compat'
join public.workflow_versions version
  on version.workspace_id = definition.workspace_id
 and version.workflow_definition_id = definition.id
 and version.version = '1.0.0'
where unit.workflow_instance_id is null
on conflict (workspace_id, entity_type, entity_id, purpose_key) do nothing;

update public.inventory_units unit
set workflow_instance_id = instance.id,
    workflow_state_key = instance.current_state_key
from public.workflow_instances instance
where instance.workspace_id = unit.workspace_id
  and instance.entity_type = 'inventory_unit'
  and instance.entity_id = unit.id
  and instance.purpose_key = 'primary'
  and unit.workflow_instance_id is null;

create function app.require_inventory_command_permission(
  target_workspace_id uuid,
  permission_key text
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
    or not app.has_permission(target_workspace_id, permission_key) then
    raise exception using
      errcode = '42501',
      message = 'active workspace membership and inventory permission are required';
  end if;
  return actor_user_id;
end;
$$;

create function app.append_inventory_outbox_event(
  p_workspace_id uuid,
  p_event_name text,
  p_inventory_unit_id uuid,
  p_aggregate_version bigint,
  p_payload jsonb,
  p_actor_user_id uuid,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_id uuid;
begin
  if p_correlation_id is null
    or p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or app.job_payload_contains_forbidden_key(p_payload) then
    raise exception using
      errcode = '23514',
      message = 'inventory outbox metadata is invalid';
  end if;

  insert into public.outbox_events (
    workspace_id,
    event_name,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    payload_schema_version,
    payload,
    actor_user_id,
    correlation_id
  ) values (
    p_workspace_id,
    p_event_name,
    'inventory_unit',
    p_inventory_unit_id,
    p_aggregate_version,
    1,
    p_payload,
    p_actor_user_id,
    p_correlation_id
  )
  returning id into event_id;

  return event_id;
end;
$$;

create function app.update_inventory_unit_details(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_condition_key text,
  p_acquisition_date date,
  p_acquired_at timestamptz,
  p_available_at timestamptz,
  p_odometer_value bigint,
  p_odometer_unit text,
  p_advertised_price_minor bigint,
  p_expected_sale_price_minor bigint,
  p_expected_sale_price_currency_code text,
  p_public_notes text,
  p_update_internal_notes boolean,
  p_internal_notes text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
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
  existing_unit public.inventory_units%rowtype;
  linked_instance public.workflow_instances%rowtype;
  existing_receipt public.inventory_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_condition_key text;
  normalized_expected_currency text;
  normalized_public_notes text;
  normalized_internal_notes text;
  request_fingerprint text;
  next_version bigint;
  changed_keys jsonb;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_inventory_command_permission(
    p_workspace_id,
    'inventory.update'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_condition_key := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_condition_key, ''))),
    ''
  );
  normalized_expected_currency := nullif(
    pg_catalog.upper(
      pg_catalog.btrim(coalesce(p_expected_sale_price_currency_code, ''))
    ),
    ''
  );
  normalized_public_notes := nullif(
    pg_catalog.btrim(coalesce(p_public_notes, '')),
    ''
  );
  normalized_internal_notes := case
    when p_update_internal_notes then nullif(
      pg_catalog.btrim(coalesce(p_internal_notes, '')),
      ''
    )
    else null
  end;

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid inventory idempotency key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_update_internal_notes is null then
    raise exception using
      errcode = '23502',
      message = 'internal-note update presence flag is required';
  end if;
  if not p_update_internal_notes
    and nullif(pg_catalog.btrim(coalesce(p_internal_notes, '')), '') is not null then
    raise exception using
      errcode = '22023',
      message = 'internal notes require the explicit update presence flag';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'inventory request ID is too long';
  end if;
  if normalized_condition_key is not null
    and normalized_condition_key !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$' then
    raise exception using errcode = '22023', message = 'invalid inventory condition key';
  end if;
  if (p_odometer_value is null) <> (p_odometer_unit is null)
    or p_odometer_value is not null and p_odometer_value < 0
    or p_odometer_unit is not null and p_odometer_unit not in ('km', 'mi') then
    raise exception using errcode = '22023', message = 'invalid odometer value or unit';
  end if;
  if p_advertised_price_minor is not null and p_advertised_price_minor < 0
    or p_expected_sale_price_minor is not null and p_expected_sale_price_minor < 0 then
    raise exception using errcode = '22023', message = 'inventory money cannot be negative';
  end if;
  if (p_expected_sale_price_minor is null) <> (normalized_expected_currency is null)
    or normalized_expected_currency is not null
      and normalized_expected_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'invalid expected-sale money';
  end if;
  if normalized_public_notes is not null
    and pg_catalog.char_length(normalized_public_notes) > 4000
    or normalized_internal_notes is not null
      and pg_catalog.char_length(normalized_internal_notes) > 8000 then
    raise exception using errcode = '22023', message = 'inventory notes are too long';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_version', p_expected_version,
      'condition_key', normalized_condition_key,
      'acquisition_date', p_acquisition_date,
      'acquired_at', p_acquired_at,
      'available_at', p_available_at,
      'odometer_value', p_odometer_value,
      'odometer_unit', p_odometer_unit,
      'advertised_price_minor', p_advertised_price_minor,
      'expected_sale_price_minor', p_expected_sale_price_minor,
      'expected_sale_price_currency_code', normalized_expected_currency,
      'public_notes', normalized_public_notes,
      'update_internal_notes', p_update_internal_notes,
      'internal_notes', case when p_update_internal_notes
        then normalized_internal_notes else null end
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fupdate_inventory_unit_details\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.inventory_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.command_type = 'update_inventory_unit_details'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'inventory idempotency key was used for a different details command';
    end if;
    return query select
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      existing_receipt.result ->> 'canonical_status',
      existing_receipt.result ->> 'state_key',
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select unit.*
    into existing_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if existing_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if existing_unit.status in ('closed', 'archived') then
    raise exception using
      errcode = '23514',
      message = 'closed inventory details are immutable';
  end if;
  if existing_unit.workflow_instance_id is not null then
    select instance.*
      into linked_instance
    from public.workflow_instances instance
    where instance.workspace_id = p_workspace_id
      and instance.id = existing_unit.workflow_instance_id
      and instance.entity_type = 'inventory_unit'
      and instance.entity_id = p_inventory_unit_id
      and instance.purpose_key = 'primary'
    for update;

    if not found or linked_instance.lifecycle_status <> 'active' then
      raise exception using errcode = '23514', message = 'inventory workflow is not active';
    end if;
    if linked_instance.version <> existing_unit.version
      or linked_instance.current_state_key <> existing_unit.workflow_state_key
      or linked_instance.canonical_status <> existing_unit.status then
      raise exception using
        errcode = '40001',
        message = 'inventory workflow aggregate versions are inconsistent';
    end if;
  end if;
  if normalized_expected_currency is not null
    and normalized_expected_currency <> existing_unit.currency_code then
    raise exception using
      errcode = '23514',
      message = 'expected-sale currency must match inventory currency';
  end if;

  if p_update_internal_notes then
    if not app.has_permission(p_workspace_id, 'inventory.update_internal') then
      raise exception using
        errcode = '42501',
        message = 'internal inventory update permission is required';
    end if;
  end if;

  changed_keys := pg_catalog.to_jsonb(pg_catalog.array_remove(array[
    case when normalized_condition_key is distinct from existing_unit.condition_key
      then 'condition_key' end,
    case when p_acquisition_date is distinct from existing_unit.acquisition_date
      then 'acquisition_date' end,
    case when p_acquired_at is distinct from existing_unit.acquired_at
      then 'acquired_at' end,
    case when p_available_at is distinct from existing_unit.available_at
      then 'available_at' end,
    case when p_odometer_value is distinct from existing_unit.odometer_value
      then 'odometer_value' end,
    case when p_odometer_unit is distinct from existing_unit.odometer_unit
      then 'odometer_unit' end,
    case when p_advertised_price_minor is distinct from existing_unit.advertised_price_minor
      then 'advertised_price_minor' end,
    case when p_expected_sale_price_minor is distinct from existing_unit.expected_sale_price_minor
      then 'expected_sale_price_minor' end,
    case when normalized_expected_currency is distinct from existing_unit.expected_sale_price_currency_code
      then 'expected_sale_price_currency_code' end,
    case when normalized_public_notes is distinct from existing_unit.public_notes
      then 'public_notes' end,
    case when p_update_internal_notes then 'internal_notes' end
  ]::text[], null));

  if pg_catalog.jsonb_array_length(changed_keys) = 0 then
    raise exception using errcode = '23514', message = 'inventory details did not change';
  end if;

  next_version := existing_unit.version + 1;
  if existing_unit.workflow_instance_id is not null then
    update public.workflow_instances
    set version = next_version
    where workspace_id = p_workspace_id
      and id = linked_instance.id;
  end if;

  update public.inventory_units
  set condition_key = normalized_condition_key,
      acquisition_date = p_acquisition_date,
      acquired_at = p_acquired_at,
      available_at = p_available_at,
      odometer_value = p_odometer_value,
      odometer_unit = p_odometer_unit,
      advertised_price_minor = p_advertised_price_minor,
      expected_sale_price_minor = p_expected_sale_price_minor,
      expected_sale_price_currency_code = normalized_expected_currency,
      public_notes = normalized_public_notes,
      version = next_version
  where workspace_id = p_workspace_id
    and id = p_inventory_unit_id;

  if p_update_internal_notes then
    insert into public.inventory_unit_internal_details (
      workspace_id,
      inventory_unit_id,
      internal_notes,
      version,
      created_by,
      updated_by
    ) values (
      p_workspace_id,
      p_inventory_unit_id,
      normalized_internal_notes,
      1,
      actor_user_id,
      actor_user_id
    )
    on conflict (workspace_id, inventory_unit_id) do update
    set internal_notes = excluded.internal_notes,
        version = public.inventory_unit_internal_details.version + 1,
        updated_by = excluded.updated_by;
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_unit.updated',
    p_entity_type => 'inventory_unit',
    p_entity_id => p_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('version', existing_unit.version),
    p_after_data => pg_catalog.jsonb_build_object(
      'version', next_version,
      'changed_keys', changed_keys
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'internal_values_redacted', p_update_internal_notes
    )
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_unit.updated',
    p_inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', p_inventory_unit_id,
      'aggregateVersion', next_version,
      'changedKeys', changed_keys
    ),
    actor_user_id,
    p_correlation_id
  );

  result_payload := pg_catalog.jsonb_build_object(
    'inventory_unit_id', p_inventory_unit_id,
    'aggregate_version', next_version,
    'canonical_status', existing_unit.status,
    'state_key', coalesce(existing_unit.workflow_state_key, existing_unit.status),
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.inventory_command_receipts (
    workspace_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    inventory_unit_id,
    result,
    actor_user_id
  ) values (
    p_workspace_id,
    'update_inventory_unit_details',
    normalized_idempotency_key,
    request_fingerprint,
    p_inventory_unit_id,
    result_payload,
    actor_user_id
  );

  return query select
    p_inventory_unit_id,
    next_version,
    existing_unit.status,
    coalesce(existing_unit.workflow_state_key, existing_unit.status),
    false,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create function app.transfer_inventory_unit_location(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_to_location_id uuid,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  location_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  existing_unit public.inventory_units%rowtype;
  linked_instance public.workflow_instances%rowtype;
  existing_receipt public.inventory_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_reason text;
  request_fingerprint text;
  next_version bigint;
  new_location_event_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_inventory_command_permission(
    p_workspace_id,
    'inventory.update'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid inventory idempotency key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if normalized_reason is null or pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'location transfer reason is required';
  end if;
  if p_to_location_id is null or p_correlation_id is null then
    raise exception using errcode = '23502', message = 'location and correlation ID are required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'inventory request ID is too long';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_version', p_expected_version,
      'to_location_id', p_to_location_id,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1ftransfer_inventory_unit_location\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.inventory_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.command_type = 'transfer_inventory_unit_location'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'inventory idempotency key was used for a different location command';
    end if;
    return query select
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      existing_receipt.result ->> 'canonical_status',
      existing_receipt.result ->> 'state_key',
      true,
      (existing_receipt.result ->> 'location_event_id')::uuid,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select unit.*
    into existing_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if existing_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if existing_unit.status in ('closed', 'archived') then
    raise exception using
      errcode = '23514',
      message = 'closed inventory cannot transfer location';
  end if;
  if existing_unit.workflow_instance_id is not null then
    select instance.*
      into linked_instance
    from public.workflow_instances instance
    where instance.workspace_id = p_workspace_id
      and instance.id = existing_unit.workflow_instance_id
      and instance.entity_type = 'inventory_unit'
      and instance.entity_id = p_inventory_unit_id
      and instance.purpose_key = 'primary'
    for update;

    if not found or linked_instance.lifecycle_status <> 'active' then
      raise exception using errcode = '23514', message = 'inventory workflow is not active';
    end if;
    if linked_instance.version <> existing_unit.version
      or linked_instance.current_state_key <> existing_unit.workflow_state_key
      or linked_instance.canonical_status <> existing_unit.status then
      raise exception using
        errcode = '40001',
        message = 'inventory workflow aggregate versions are inconsistent';
    end if;
  end if;
  if existing_unit.location_id = p_to_location_id then
    raise exception using errcode = '23514', message = 'inventory is already at that location';
  end if;
  if not exists (
    select 1
    from public.locations location
    where location.workspace_id = p_workspace_id
      and location.id = p_to_location_id
      and location.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'destination location is unavailable';
  end if;

  next_version := existing_unit.version + 1;
  if existing_unit.workflow_instance_id is not null then
    update public.workflow_instances
    set version = next_version
    where workspace_id = p_workspace_id
      and id = linked_instance.id;
  end if;

  update public.inventory_units
  set location_id = p_to_location_id,
      version = next_version
  where workspace_id = p_workspace_id
    and id = p_inventory_unit_id;

  insert into public.inventory_location_events (
    workspace_id,
    inventory_unit_id,
    from_location_id,
    to_location_id,
    aggregate_version,
    reason,
    actor_user_id,
    request_id,
    correlation_id
  ) values (
    p_workspace_id,
    p_inventory_unit_id,
    existing_unit.location_id,
    p_to_location_id,
    next_version,
    normalized_reason,
    actor_user_id,
    p_request_id,
    p_correlation_id
  )
  returning id into new_location_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_unit.location_transferred',
    p_entity_type => 'inventory_unit',
    p_entity_id => p_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'location_id', existing_unit.location_id,
      'version', existing_unit.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'location_id', p_to_location_id,
      'version', next_version
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'location_event_id', new_location_event_id
    )
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_unit.location_transferred',
    p_inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', p_inventory_unit_id,
      'aggregateVersion', next_version,
      'fromLocationId', existing_unit.location_id,
      'toLocationId', p_to_location_id,
      'effectKeys', pg_catalog.jsonb_build_array('listing.refresh')
    ),
    actor_user_id,
    p_correlation_id
  );

  result_payload := pg_catalog.jsonb_build_object(
    'inventory_unit_id', p_inventory_unit_id,
    'aggregate_version', next_version,
    'canonical_status', existing_unit.status,
    'state_key', coalesce(existing_unit.workflow_state_key, existing_unit.status),
    'location_event_id', new_location_event_id,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.inventory_command_receipts (
    workspace_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    inventory_unit_id,
    result,
    actor_user_id
  ) values (
    p_workspace_id,
    'transfer_inventory_unit_location',
    normalized_idempotency_key,
    request_fingerprint,
    p_inventory_unit_id,
    result_payload,
    actor_user_id
  );

  return query select
    p_inventory_unit_id,
    next_version,
    existing_unit.status,
    coalesce(existing_unit.workflow_state_key, existing_unit.status),
    false,
    new_location_event_id,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create function app.transition_inventory_workflow(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_transition_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  workflow_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  existing_unit public.inventory_units%rowtype;
  existing_instance public.workflow_instances%rowtype;
  configured_transition public.workflow_transitions%rowtype;
  target_state public.workflow_states%rowtype;
  existing_receipt public.inventory_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_transition_key text;
  normalized_reason text;
  request_fingerprint text;
  next_version bigint;
  terminal_state boolean;
  new_workflow_event_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_inventory_command_permission(
    p_workspace_id,
    'inventory.transition'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_transition_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_transition_key, ''))
  );
  normalized_reason := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid inventory idempotency key';
  end if;
  if normalized_transition_key !~ '^[a-z][a-z0-9_]*$' then
    raise exception using errcode = '22023', message = 'invalid workflow transition key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if normalized_reason is not null and pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'workflow transition reason is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'inventory request ID is too long';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_version', p_expected_version,
      'transition_key', normalized_transition_key,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1ftransition_inventory_workflow\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.inventory_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.command_type = 'transition_inventory_workflow'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'inventory idempotency key was used for a different transition command';
    end if;
    return query select
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      existing_receipt.result ->> 'canonical_status',
      existing_receipt.result ->> 'state_key',
      true,
      (existing_receipt.result ->> 'workflow_event_id')::uuid,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select unit.*
    into existing_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if existing_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if existing_unit.workflow_instance_id is null then
    raise exception using errcode = '23514', message = 'inventory workflow is not configured';
  end if;

  select instance.*
    into existing_instance
  from public.workflow_instances instance
  where instance.workspace_id = p_workspace_id
    and instance.id = existing_unit.workflow_instance_id
    and instance.entity_type = 'inventory_unit'
    and instance.entity_id = p_inventory_unit_id
    and instance.purpose_key = 'primary'
  for update;

  if not found or existing_instance.lifecycle_status <> 'active' then
    raise exception using errcode = '23514', message = 'inventory workflow is not active';
  end if;
  if existing_instance.version <> existing_unit.version
    or existing_instance.current_state_key <> existing_unit.workflow_state_key
    or existing_instance.canonical_status <> existing_unit.status then
    raise exception using
      errcode = '40001',
      message = 'inventory workflow aggregate versions are inconsistent';
  end if;

  select transition.*
    into configured_transition
  from public.workflow_transitions transition
  where transition.workspace_id = p_workspace_id
    and transition.workflow_version_id = existing_instance.workflow_version_id
    and transition.key = normalized_transition_key
    and transition.from_state_key = existing_instance.current_state_key;

  if not found then
    raise exception using errcode = '23514', message = 'workflow transition is not allowed';
  end if;
  if not app.has_permission(p_workspace_id, configured_transition.permission_key) then
    raise exception using
      errcode = '42501',
      message = 'configured workflow transition permission is required';
  end if;
  if configured_transition.reason_required and normalized_reason is null then
    raise exception using errcode = '23514', message = 'workflow transition reason is required';
  end if;

  if configured_transition.guard_key = 'required_fields_complete' and not exists (
    select 1
    from public.vehicles vehicle
    where vehicle.workspace_id = existing_unit.workspace_id
      and vehicle.id = existing_unit.vehicle_id
      and vehicle.model_year is not null
      and vehicle.make is not null
      and vehicle.model is not null
      and existing_unit.location_id is not null
      and existing_unit.acquisition_date is not null
      and existing_unit.odometer_value is not null
      and existing_unit.odometer_unit is not null
  ) then
    raise exception using
      errcode = '23514',
      message = 'required inventory fields are incomplete';
  end if;
  if configured_transition.guard_key = 'sale_completion_requirements_met'
    and not exists (
      select 1
      from public.deal_inventory_units inventory_link
      join public.deals deal
        on deal.workspace_id = inventory_link.workspace_id
       and deal.id = inventory_link.deal_id
      where inventory_link.workspace_id = p_workspace_id
        and inventory_link.inventory_unit_id = p_inventory_unit_id
        and inventory_link.role_key = 'sold'
        and inventory_link.status = 'active'
        and deal.status = 'completed'
    ) then
    raise exception using
      errcode = '23514',
      message = 'sale completion requirements are not met';
  end if;

  select state.*
    into target_state
  from public.workflow_states state
  where state.workspace_id = p_workspace_id
    and state.workflow_version_id = existing_instance.workflow_version_id
    and state.key = configured_transition.to_state_key;

  if not found then
    raise exception using errcode = '23514', message = 'workflow target state is unavailable';
  end if;

  next_version := existing_unit.version + 1;
  terminal_state := target_state.behavior_flags @> '{"terminal":true}'::jsonb
    or target_state.canonical_category in ('closed', 'archived');

  update public.workflow_instances
  set current_state_key = target_state.key,
      canonical_status = target_state.canonical_category,
      lifecycle_status = case when terminal_state then 'completed' else 'active' end,
      completed_at = case when terminal_state
        then pg_catalog.statement_timestamp() else null end,
      version = next_version
  where workspace_id = p_workspace_id
    and id = existing_instance.id;

  update public.inventory_units
  set workflow_state_key = target_state.key,
      status = target_state.canonical_category,
      available_at = case
        when target_state.behavior_flags @> '{"available":true}'::jsonb
          then coalesce(available_at, pg_catalog.statement_timestamp())
        else available_at
      end,
      sold_at = case
        when target_state.key = 'sold'
          then coalesce(sold_at, pg_catalog.statement_timestamp())
        else sold_at
      end,
      closed_at = case
        when target_state.canonical_category in ('closed', 'archived')
          then coalesce(closed_at, pg_catalog.statement_timestamp())
        else closed_at
      end,
      version = next_version
  where workspace_id = p_workspace_id
    and id = p_inventory_unit_id;

  insert into public.workflow_events (
    workspace_id,
    workflow_instance_id,
    transition_id,
    entity_type,
    entity_id,
    from_state_key,
    to_state_key,
    aggregate_version,
    reason,
    actor_user_id,
    request_id,
    correlation_id
  ) values (
    p_workspace_id,
    existing_instance.id,
    configured_transition.id,
    'inventory_unit',
    p_inventory_unit_id,
    existing_instance.current_state_key,
    target_state.key,
    next_version,
    normalized_reason,
    actor_user_id,
    p_request_id,
    p_correlation_id
  )
  returning id into new_workflow_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_unit.transitioned',
    p_entity_type => 'inventory_unit',
    p_entity_id => p_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'state_key', existing_instance.current_state_key,
      'canonical_status', existing_instance.canonical_status,
      'version', existing_unit.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'state_key', target_state.key,
      'canonical_status', target_state.canonical_category,
      'version', next_version
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'workflow_event_id', new_workflow_event_id,
      'transition_key', configured_transition.key
    )
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_unit.transitioned',
    p_inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', p_inventory_unit_id,
      'aggregateVersion', next_version,
      'transitionKey', configured_transition.key,
      'fromStateKey', existing_instance.current_state_key,
      'toStateKey', target_state.key,
      'canonicalStatus', target_state.canonical_category,
      'effectKeys', configured_transition.effect_keys
    ),
    actor_user_id,
    p_correlation_id
  );

  result_payload := pg_catalog.jsonb_build_object(
    'inventory_unit_id', p_inventory_unit_id,
    'aggregate_version', next_version,
    'canonical_status', target_state.canonical_category,
    'state_key', target_state.key,
    'workflow_event_id', new_workflow_event_id,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.inventory_command_receipts (
    workspace_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    inventory_unit_id,
    result,
    actor_user_id
  ) values (
    p_workspace_id,
    'transition_inventory_workflow',
    normalized_idempotency_key,
    request_fingerprint,
    p_inventory_unit_id,
    result_payload,
    actor_user_id
  );

  return query select
    p_inventory_unit_id,
    next_version,
    target_state.canonical_category,
    target_state.key,
    false,
    new_workflow_event_id,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create function app.assert_sensitive_inventory_permission_mfa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  granted_permission_key text;
  role_requires_mfa boolean;
begin
  if new.status <> 'active' then
    return new;
  end if;

  select permission.key
    into granted_permission_key
  from public.permissions permission
  where permission.id = new.permission_id
    and permission.status = 'active'
  for share;

  if granted_permission_key is null or granted_permission_key not in (
    'inventory.duplicate_override',
    'inventory.facts_override'
  ) then
    return new;
  end if;

  select role.requires_mfa
    into role_requires_mfa
  from public.roles role
  where role.workspace_id = new.workspace_id
    and role.id = new.role_id
  for update;

  if role_requires_mfa is not true then
    raise exception using
      errcode = '23514',
      message = 'sensitive inventory override permissions require an MFA role';
  end if;
  return new;
end;
$$;

create function app.assert_sensitive_inventory_role_mfa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.requires_mfa
    and not new.requires_mfa
    and exists (
      select 1
      from public.role_permissions role_permission
      join public.permissions permission
        on permission.id = role_permission.permission_id
      where role_permission.workspace_id = new.workspace_id
        and role_permission.role_id = new.id
        and role_permission.status = 'active'
        and permission.status = 'active'
        and permission.key in (
          'inventory.duplicate_override',
          'inventory.facts_override'
        )
    ) then
    raise exception using
      errcode = '23514',
      message = 'MFA cannot be disabled while a role has sensitive inventory permissions';
  end if;
  return new;
end;
$$;

create function app.assert_sensitive_inventory_permission_activation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active'
    and old.status is distinct from new.status
    and new.key in (
      'inventory.duplicate_override',
      'inventory.facts_override'
    ) then
    perform 1
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.workspace_id = role.workspace_id
     and role_permission.role_id = role.id
    where role_permission.permission_id = new.id
      and role_permission.status = 'active'
    order by role.id
    for update of role;

    if exists (
      select 1
      from public.roles role
      join public.role_permissions role_permission
        on role_permission.workspace_id = role.workspace_id
       and role_permission.role_id = role.id
      where role_permission.permission_id = new.id
        and role_permission.status = 'active'
        and not role.requires_mfa
    ) then
      raise exception using
        errcode = '23514',
        message = 'sensitive inventory permissions cannot activate for a role without MFA';
    end if;
  end if;
  return new;
end;
$$;

create trigger role_permissions_sensitive_inventory_mfa
before insert or update on public.role_permissions
for each row execute function app.assert_sensitive_inventory_permission_mfa();
create trigger roles_sensitive_inventory_mfa
before update of requires_mfa on public.roles
for each row execute function app.assert_sensitive_inventory_role_mfa();
create trigger permissions_sensitive_inventory_mfa
before update of status on public.permissions
for each row execute function app.assert_sensitive_inventory_permission_activation();

alter table public.locations enable row level security;
alter table public.locations force row level security;
alter table public.workflow_definitions enable row level security;
alter table public.workflow_definitions force row level security;
alter table public.workflow_versions enable row level security;
alter table public.workflow_versions force row level security;
alter table public.workflow_states enable row level security;
alter table public.workflow_states force row level security;
alter table public.workflow_transitions enable row level security;
alter table public.workflow_transitions force row level security;
alter table public.workflow_instances enable row level security;
alter table public.workflow_instances force row level security;
alter table public.workflow_events enable row level security;
alter table public.workflow_events force row level security;
alter table public.inventory_unit_internal_details enable row level security;
alter table public.inventory_unit_internal_details force row level security;
alter table public.inventory_location_events enable row level security;
alter table public.inventory_location_events force row level security;
alter table public.inventory_command_receipts enable row level security;
alter table public.inventory_command_receipts force row level security;

create policy locations_select
on public.locations
for select to authenticated
using (
  app.has_permission(workspace_id, 'workspace.read')
  or app.has_permission(workspace_id, 'inventory.read')
);
create policy workflow_definitions_select
on public.workflow_definitions
for select to authenticated
using (
  app.has_permission(workspace_id, 'workflow.read')
  or app.has_permission(workspace_id, 'inventory.read')
);
create policy workflow_versions_select
on public.workflow_versions
for select to authenticated
using (
  app.has_permission(workspace_id, 'workflow.read')
  or app.has_permission(workspace_id, 'inventory.read')
);
create policy workflow_states_select
on public.workflow_states
for select to authenticated
using (
  app.has_permission(workspace_id, 'workflow.read')
  or app.has_permission(workspace_id, 'inventory.read')
);
create policy workflow_transitions_select
on public.workflow_transitions
for select to authenticated
using (
  app.has_permission(workspace_id, 'workflow.read')
  or app.has_permission(workspace_id, 'inventory.read')
);
create policy workflow_instances_select
on public.workflow_instances
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));
create policy workflow_events_select
on public.workflow_events
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));
create policy inventory_unit_internal_details_select
on public.inventory_unit_internal_details
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read_internal'));
create policy inventory_location_events_select
on public.inventory_location_events
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));

revoke all on table
  public.locations,
  public.workflow_definitions,
  public.workflow_versions,
  public.workflow_states,
  public.workflow_transitions,
  public.workflow_instances,
  public.workflow_events,
  public.inventory_unit_internal_details,
  public.inventory_location_events,
  public.inventory_command_receipts
from public, anon, authenticated, service_role;

grant select on
  public.locations,
  public.workflow_definitions,
  public.workflow_versions,
  public.workflow_states,
  public.workflow_transitions,
  public.workflow_instances,
  public.workflow_events,
  public.inventory_unit_internal_details,
  public.inventory_location_events
to authenticated;

grant select on
  public.locations,
  public.workflow_definitions,
  public.workflow_versions,
  public.workflow_states,
  public.workflow_transitions,
  public.workflow_instances,
  public.workflow_events,
  public.inventory_unit_internal_details,
  public.inventory_location_events,
  public.inventory_command_receipts
to service_role;

revoke all on function app.prevent_inventory_history_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.validate_workflow_transition_configuration()
  from public, anon, authenticated, service_role;
revoke all on function app.protect_activated_workflow_configuration()
  from public, anon, authenticated, service_role;
revoke all on function app.validate_workflow_version_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_inventory_workflow_link()
  from public, anon, authenticated, service_role;
revoke all on function app.attach_configured_inventory_workflow()
  from public, anon, authenticated, service_role;
revoke all on function app.require_inventory_command_permission(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.append_inventory_outbox_event(
  uuid, text, uuid, bigint, jsonb, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.assert_sensitive_inventory_permission_mfa()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_sensitive_inventory_role_mfa()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_sensitive_inventory_permission_activation()
  from public, anon, authenticated, service_role;
revoke all on function app.update_inventory_unit_details(
  uuid, text, uuid, bigint, text, date, timestamptz, timestamptz, bigint,
  text, bigint, bigint, text, text, boolean, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.transfer_inventory_unit_location(
  uuid, text, uuid, bigint, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.transition_inventory_workflow(
  uuid, text, uuid, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.update_inventory_unit_details(
  uuid, text, uuid, bigint, text, date, timestamptz, timestamptz, bigint,
  text, bigint, bigint, text, text, boolean, text, text, uuid
) to authenticated;
grant execute on function app.transfer_inventory_unit_location(
  uuid, text, uuid, bigint, uuid, text, text, uuid
) to authenticated;
grant execute on function app.transition_inventory_workflow(
  uuid, text, uuid, bigint, text, text, text, uuid
) to authenticated;

comment on table public.locations is
  'Workspace-owned operational locations; synthetic defaults are seed data, not tenant branches in platform code.';
comment on table public.workflow_versions is
  'Versioned generic workflow configuration; activated and retired versions are immutable.';
comment on table public.workflow_instances is
  'Entity workflow instance pinned to the exact immutable version used when it started.';
comment on table public.workflow_events is
  'Append-only workflow transition history with aggregate version, reason, actor, and correlation.';
comment on table public.inventory_unit_internal_details is
  'Permission-separated internal inventory notes; values are excluded from outbox and audit payloads.';
comment on table public.inventory_location_events is
  'Append-only inventory location transfer history.';
comment on table public.inventory_command_receipts is
  'Append-only idempotency receipts returning the original aggregate and event IDs on replay.';
comment on function app.update_inventory_unit_details(
  uuid, text, uuid, bigint, text, date, timestamptz, timestamptz, bigint,
  text, bigint, bigint, text, text, boolean, text, text, uuid
) is
  'M2 detail command positional contract: workspace, idempotency, unit, expected version, condition, acquisition date/time, availability time, odometer value/unit, advertised minor, expected minor/currency, public notes, update-internal presence, internal notes, request, correlation.';
comment on function app.transfer_inventory_unit_location(
  uuid, text, uuid, bigint, uuid, text, text, uuid
) is
  'M2 transfer command positional contract: workspace, idempotency, unit, expected version, destination location, reason, request, correlation.';
comment on function app.transition_inventory_workflow(
  uuid, text, uuid, bigint, text, text, text, uuid
) is
  'M2 transition command positional contract: workspace, idempotency, unit, expected version, transition key, reason, request, correlation.';
