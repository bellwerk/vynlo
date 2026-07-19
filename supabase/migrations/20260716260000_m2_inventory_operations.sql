-- VYN-INV-001, VYN-COST-001, VYN-SEARCH-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001, M2-INV-AC-005 through M2-INV-AC-011.
-- Exact operator reads and controlled physical-vehicle fact correction. Reads
-- are workspace/permission scoped; decoded facts are never silently replaced.

create table public.vehicle_facts_override_history (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vehicle_id uuid not null,
  facts_version_before bigint not null check (facts_version_before > 0),
  facts_version_after bigint not null check (
    facts_version_after = facts_version_before + 1
  ),
  before_facts jsonb not null check (
    pg_catalog.jsonb_typeof(before_facts) = 'object'
  ),
  after_facts jsonb not null check (
    pg_catalog.jsonb_typeof(after_facts) = 'object'
  ),
  reason text not null check (
    pg_catalog.btrim(reason) <> ''
    and pg_catalog.char_length(reason) <= 2000
  ),
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  request_id text check (
    request_id is null or pg_catalog.char_length(request_id) <= 200
  ),
  correlation_id uuid not null,
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, vehicle_id, facts_version_after),
  foreign key (workspace_id, vehicle_id)
    references public.vehicles (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id)
    on delete restrict,
  check (before_facts <> after_facts)
);

create index vehicle_facts_override_history_vehicle_time_idx
  on public.vehicle_facts_override_history (
    workspace_id,
    vehicle_id,
    created_at desc,
    id desc
  );

create table public.vehicle_facts_override_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  command_fingerprint text not null check (
    command_fingerprint ~ '^[a-f0-9]{64}$'
  ),
  vehicle_id uuid not null,
  history_id uuid not null,
  facts_version bigint not null check (facts_version > 1),
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, idempotency_key),
  foreign key (workspace_id, vehicle_id)
    references public.vehicles (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, history_id)
    references public.vehicle_facts_override_history (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id)
    on delete restrict
);

create function app.prevent_vehicle_facts_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'vehicle fact correction history is append-only';
end;
$$;

create trigger vehicle_facts_override_history_append_only
before update or delete on public.vehicle_facts_override_history
for each row execute function app.prevent_vehicle_facts_history_mutation();

create trigger vehicle_facts_override_receipts_append_only
before update or delete on public.vehicle_facts_override_command_receipts
for each row execute function app.prevent_vehicle_facts_history_mutation();

create function app.get_inventory_unit_operations(
  p_workspace_id uuid,
  p_inventory_unit_id uuid
)
returns table (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  canonical_status text,
  workflow_state_key text,
  aggregate_version bigint,
  workflow_instance_version bigint,
  workflow_configuration_version text,
  acquisition_date date,
  acquired_at timestamptz,
  available_at timestamptz,
  sold_at timestamptz,
  closed_at timestamptz,
  condition_key text,
  odometer_value text,
  odometer_unit text,
  currency_code text,
  advertised_price_minor text,
  expected_sale_price_minor text,
  public_notes text,
  internal_notes text,
  can_read_internal boolean,
  can_update_details boolean,
  can_update_internal boolean,
  can_transfer_location boolean,
  can_transition_workflow boolean,
  can_read_costs boolean,
  can_create_costs boolean,
  can_reverse_costs boolean,
  can_override_facts boolean,
  has_recent_strong_authentication boolean,
  location_id uuid,
  location_name text,
  vehicle_facts jsonb,
  posted_cost_minor text,
  estimated_gross_minor text,
  allowed_transitions jsonb,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target_unit public.inventory_units%rowtype;
  can_read_internal_value boolean;
  can_read_costs_value boolean;
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');

  if p_inventory_unit_id is null then
    raise exception using errcode = '22023', message = 'inventory unit ID is required';
  end if;

  select unit.*
    into target_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'inventory unit was not found';
  end if;

  can_read_internal_value := app.has_permission(
    p_workspace_id,
    'inventory.read_internal'
  );
  can_read_costs_value := app.has_permission(p_workspace_id, 'costs.read');

  return query
  select
    target_unit.id,
    target_unit.vehicle_id,
    target_unit.stock_number::text,
    target_unit.status,
    coalesce(target_unit.workflow_state_key, target_unit.status),
    target_unit.version,
    instance.version,
    workflow_version.version,
    target_unit.acquisition_date,
    target_unit.acquired_at,
    target_unit.available_at,
    target_unit.sold_at,
    target_unit.closed_at,
    target_unit.condition_key,
    target_unit.odometer_value::text,
    target_unit.odometer_unit,
    target_unit.currency_code::text,
    target_unit.advertised_price_minor::text,
    target_unit.expected_sale_price_minor::text,
    target_unit.public_notes,
    case when can_read_internal_value then internal_detail.internal_notes else null end,
    can_read_internal_value,
    app.has_permission(p_workspace_id, 'inventory.update'),
    app.has_permission(p_workspace_id, 'inventory.update_internal'),
    app.has_permission(p_workspace_id, 'inventory.update'),
    app.has_permission(p_workspace_id, 'inventory.transition'),
    can_read_costs_value,
    app.has_permission(p_workspace_id, 'costs.create'),
    app.has_permission(p_workspace_id, 'costs.reverse'),
    app.has_permission(p_workspace_id, 'inventory.facts_override'),
    app.has_recent_strong_auth(),
    location.id,
    location.name,
    pg_catalog.jsonb_build_object(
      'factsVersion', vehicle.facts_version,
      'vin', pg_catalog.upper(vehicle.vin::text),
      'modelYear', vehicle.model_year,
      'make', vehicle.make,
      'model', vehicle.model,
      'bodyType', vehicle.body_type,
      'cylinders', vehicle.cylinders,
      'drivetrain', vehicle.drivetrain,
      'engineLiters', case
        when vehicle.engine_displacement_liters is null then null
        else pg_catalog.trim_scale(vehicle.engine_displacement_liters)::text
      end,
      'fuelType', vehicle.fuel_type,
      'horsepower', vehicle.horsepower,
      'transmission', vehicle.transmission,
      'trimName', vehicle.trim_name
    ),
    case when can_read_costs_value then coalesce(metric.posted_cost_minor, 0)::text else null end,
    case when can_read_costs_value then metric.estimated_gross_minor::text else null end,
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', transition.key,
          'toStateKey', transition.to_state_key,
          'canonicalStatus', target_state.canonical_category,
          'labels', target_state.labels,
          'reasonRequired', transition.reason_required
        )
        order by target_state.sort_order, transition.key
      )
      from public.workflow_transitions transition
      join public.workflow_states target_state
        on target_state.workspace_id = transition.workspace_id
       and target_state.workflow_version_id = transition.workflow_version_id
       and target_state.key = transition.to_state_key
      where instance.id is not null
        and instance.lifecycle_status = 'active'
        and transition.workspace_id = p_workspace_id
        and transition.workflow_version_id = instance.workflow_version_id
        and transition.from_state_key = instance.current_state_key
        and app.has_permission(p_workspace_id, transition.permission_key)
        and (
          transition.guard_key is null
          or transition.guard_key = 'required_fields_complete' and (
            vehicle.model_year is not null
            and vehicle.make is not null
            and vehicle.model is not null
            and target_unit.location_id is not null
            and target_unit.acquisition_date is not null
            and target_unit.odometer_value is not null
            and target_unit.odometer_unit is not null
          )
          or transition.guard_key = 'sale_completion_requirements_met' and exists (
            select 1
            from public.deal_inventory_units inventory_link
            join public.deals deal
              on deal.workspace_id = inventory_link.workspace_id
             and deal.id = inventory_link.deal_id
            where inventory_link.workspace_id = p_workspace_id
              and inventory_link.inventory_unit_id = target_unit.id
              and inventory_link.role_key = 'sold'
              and inventory_link.status = 'active'
              and deal.status = 'completed'
          )
        )
    ), '[]'::jsonb),
    target_unit.updated_at
  from public.vehicles vehicle
  left join public.workflow_instances instance
    on instance.workspace_id = target_unit.workspace_id
   and instance.id = target_unit.workflow_instance_id
   and instance.entity_type = 'inventory_unit'
   and instance.entity_id = target_unit.id
   and instance.purpose_key = 'primary'
  left join public.workflow_versions workflow_version
    on workflow_version.workspace_id = instance.workspace_id
   and workflow_version.id = instance.workflow_version_id
  left join public.locations location
    on location.workspace_id = target_unit.workspace_id
   and location.id = target_unit.location_id
  left join public.inventory_unit_internal_details internal_detail
    on internal_detail.workspace_id = target_unit.workspace_id
   and internal_detail.inventory_unit_id = target_unit.id
  left join public.inventory_cost_metrics metric
    on metric.workspace_id = target_unit.workspace_id
   and metric.inventory_unit_id = target_unit.id
  where vehicle.workspace_id = target_unit.workspace_id
    and vehicle.id = target_unit.vehicle_id;
end;
$$;

create function app.list_active_inventory_locations(p_workspace_id uuid)
returns table (
  location_id uuid,
  location_key text,
  name text,
  locale text,
  timezone text,
  version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');

  return query
  select
    location.id,
    location.key::text,
    location.name,
    location.locale,
    location.timezone,
    location.version
  from public.locations location
  where location.workspace_id = p_workspace_id
    and location.status = 'active'
  order by location.name, location.id
  limit 200;
end;
$$;

create function app.get_inventory_unit_costs(
  p_workspace_id uuid,
  p_inventory_unit_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_page_size integer default 100
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  currency_code text,
  posted_cost_minor text,
  estimated_gross_minor text,
  posted_entry_count integer,
  last_cost_at timestamptz,
  can_create boolean,
  can_reverse boolean,
  has_recent_strong_authentication boolean,
  categories jsonb,
  entries jsonb,
  next_cursor jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target_unit public.inventory_units%rowtype;
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'costs.read');

  if p_inventory_unit_id is null
    or p_page_size is null
    or p_page_size not between 1 and 200
    or (p_before_created_at is null) <> (p_before_id is null) then
    raise exception using errcode = '22023', message = 'invalid cost-ledger query';
  end if;

  select unit.*
    into target_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'inventory unit was not found';
  end if;

  return query
  with bounded_entries as (
    select
      history.id,
      history.entry_kind,
      history.reversal_of_id,
      history.amount_minor,
      history.currency_code,
      history.incurred_on,
      history.vendor_party_id,
      history.description,
      history.supporting_file_id,
      history.aggregate_version,
      history.created_at,
      history.effective_status,
      category.id as category_definition_id,
      category.key as category_key,
      category.labels as category_labels
    from public.inventory_cost_entry_history history
    join public.inventory_cost_category_definitions category
      on category.workspace_id = history.workspace_id
     and category.id = history.category_definition_id
    where history.workspace_id = p_workspace_id
      and history.inventory_unit_id = target_unit.id
      and (
        p_before_created_at is null
        or (history.created_at, history.id) < (p_before_created_at, p_before_id)
      )
    order by history.created_at desc, history.id desc
    limit p_page_size + 1
  ),
  visible_entries as (
    select entry.*
    from bounded_entries entry
    order by entry.created_at desc, entry.id desc
    limit p_page_size
  ),
  cursor_row as (
    select entry.created_at, entry.id
    from visible_entries entry
    order by entry.created_at, entry.id
    limit 1
  )
  select
    target_unit.id,
    target_unit.version,
    target_unit.currency_code::text,
    coalesce(metric.posted_cost_minor, 0)::text,
    metric.estimated_gross_minor::text,
    coalesce(metric.posted_entry_count, 0),
    metric.last_cost_at,
    app.has_permission(p_workspace_id, 'costs.create'),
    app.has_permission(p_workspace_id, 'costs.reverse'),
    app.has_recent_strong_auth(),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', category.id,
          'key', category.key,
          'version', category.version,
          'labels', category.labels
        )
        order by category.key
      )
      from public.inventory_cost_category_definitions category
      where category.workspace_id = p_workspace_id
        and category.status = 'active'
    ), '[]'::jsonb),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', entry.id,
          'entryKind', entry.entry_kind,
          'reversalOfId', entry.reversal_of_id,
          'amountMinor', entry.amount_minor::text,
          'currencyCode', entry.currency_code::text,
          'incurredOn', entry.incurred_on,
          'vendorPartyId', entry.vendor_party_id,
          'description', entry.description,
          'supportingFileId', entry.supporting_file_id,
          'aggregateVersion', entry.aggregate_version,
          'effectiveStatus', entry.effective_status,
          'categoryDefinitionId', entry.category_definition_id,
          'categoryKey', entry.category_key,
          'categoryLabels', entry.category_labels,
          'createdAt', entry.created_at
        )
        order by entry.created_at desc, entry.id desc
      )
      from visible_entries entry
    ), '[]'::jsonb),
    case when (select pg_catalog.count(*) from bounded_entries) > p_page_size then (
      select pg_catalog.jsonb_build_object(
        'createdAt', cursor.created_at,
        'id', cursor.id
      )
      from cursor_row cursor
    ) else null end
  from (select 1) singleton
  left join public.inventory_cost_metrics metric
    on metric.workspace_id = p_workspace_id
   and metric.inventory_unit_id = target_unit.id;
end;
$$;

create function app.list_inventory_saved_views(
  p_workspace_id uuid,
  p_include_archived boolean default false
)
returns table (
  saved_view_id uuid,
  name text,
  filters jsonb,
  sort jsonb,
  visible_columns jsonb,
  layout text,
  density text,
  share_scope text,
  status text,
  version bigint,
  is_owner boolean,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.read'
  );

  return query
  select
    saved_view.id,
    saved_view.name,
    saved_view.filters,
    saved_view.sort,
    saved_view.visible_columns,
    saved_view.layout,
    saved_view.density,
    saved_view.share_scope,
    saved_view.status,
    saved_view.version,
    saved_view.owner_user_id = actor_user_id,
    saved_view.updated_at
  from public.inventory_saved_views saved_view
  where saved_view.workspace_id = p_workspace_id
    and (
      saved_view.status = 'active'
      or (
        coalesce(p_include_archived, false)
        and saved_view.status = 'archived'
        and saved_view.owner_user_id = actor_user_id
      )
    )
    and (
      saved_view.owner_user_id = actor_user_id
      or saved_view.share_scope = 'workspace'
    )
  order by
    (saved_view.owner_user_id = actor_user_id) desc,
    saved_view.updated_at desc,
    saved_view.id
  limit 100;
end;
$$;

create function app.archive_inventory_saved_view(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_saved_view_id uuid,
  p_expected_version bigint,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  saved_view_id uuid,
  saved_view_version bigint,
  replayed boolean,
  audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  request_fingerprint text;
  existing_receipt public.inventory_saved_view_command_receipts%rowtype;
  target_view public.inventory_saved_views%rowtype;
  next_version bigint;
  new_audit_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.read'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_saved_view_id is null
    or p_expected_version is null
    or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'invalid saved-view archive command';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'request ID is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'operation', 'archive',
      'saved_view_id', p_saved_view_id,
      'expected_version', p_expected_version
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1finventory_saved_view\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.inventory_saved_view_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'saved-view idempotency key was used for another command';
    end if;
    return query select
      existing_receipt.saved_view_id,
      existing_receipt.saved_view_version,
      true,
      existing_receipt.audit_event_id;
    return;
  end if;

  select saved_view.*
    into target_view
  from public.inventory_saved_views saved_view
  where saved_view.workspace_id = p_workspace_id
    and saved_view.id = p_saved_view_id
    and saved_view.owner_user_id = actor_user_id
    and saved_view.status = 'active'
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'saved view is unavailable';
  end if;
  if target_view.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'saved-view version conflict';
  end if;

  next_version := target_view.version + 1;
  update public.inventory_saved_views
  set status = 'archived',
      version = next_version
  where workspace_id = p_workspace_id
    and id = target_view.id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_saved_view.archived',
    p_entity_type => 'inventory_saved_view',
    p_entity_id => target_view.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_view.status,
      'version', target_view.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'archived',
      'version', next_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => '{}'::jsonb
  );

  insert into public.inventory_saved_view_command_receipts (
    workspace_id,
    idempotency_key,
    command_fingerprint,
    saved_view_id,
    saved_view_version,
    actor_user_id,
    audit_event_id
  ) values (
    p_workspace_id,
    normalized_idempotency_key,
    request_fingerprint,
    target_view.id,
    next_version,
    actor_user_id,
    new_audit_event_id
  );

  return query select target_view.id, next_version, false, new_audit_event_id;
end;
$$;

create function app.override_vehicle_facts(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_vehicle_id uuid,
  p_expected_facts_version bigint,
  p_model_year integer,
  p_make text,
  p_model text,
  p_body_type text,
  p_cylinders integer,
  p_drivetrain text,
  p_engine_liters text,
  p_fuel_type text,
  p_horsepower integer,
  p_transmission text,
  p_trim_name text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  vehicle_id uuid,
  facts_version bigint,
  history_id uuid,
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
  normalized_reason text;
  normalized_make text;
  normalized_model text;
  normalized_body_type text;
  normalized_drivetrain text;
  normalized_engine_liters numeric(6, 3);
  normalized_fuel_type text;
  normalized_transmission text;
  normalized_trim_name text;
  before_facts_value jsonb;
  after_facts_value jsonb;
  request_fingerprint text;
  target_vehicle public.vehicles%rowtype;
  existing_receipt public.vehicle_facts_override_command_receipts%rowtype;
  next_facts_version bigint;
  new_history_id uuid := pg_catalog.gen_random_uuid();
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.facts_override',
    true
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  normalized_make := nullif(pg_catalog.btrim(coalesce(p_make, '')), '');
  normalized_model := nullif(pg_catalog.btrim(coalesce(p_model, '')), '');
  normalized_body_type := nullif(pg_catalog.btrim(coalesce(p_body_type, '')), '');
  normalized_drivetrain := nullif(pg_catalog.btrim(coalesce(p_drivetrain, '')), '');
  normalized_fuel_type := nullif(pg_catalog.btrim(coalesce(p_fuel_type, '')), '');
  normalized_transmission := nullif(pg_catalog.btrim(coalesce(p_transmission, '')), '');
  normalized_trim_name := nullif(pg_catalog.btrim(coalesce(p_trim_name, '')), '');

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_vehicle_id is null
    or p_expected_facts_version is null
    or p_expected_facts_version < 1 then
    raise exception using errcode = '22023', message = 'invalid vehicle fact override contract';
  end if;
  if normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'vehicle fact override reason is required';
  end if;
  if p_model_year is not null and p_model_year not between 1886 and 2200
    or normalized_make is not null and pg_catalog.char_length(normalized_make) > 100
    or normalized_model is not null and pg_catalog.char_length(normalized_model) > 100
    or normalized_body_type is not null and pg_catalog.char_length(normalized_body_type) > 200
    or normalized_drivetrain is not null and pg_catalog.char_length(normalized_drivetrain) > 100
    or normalized_fuel_type is not null and pg_catalog.char_length(normalized_fuel_type) > 100
    or normalized_transmission is not null and pg_catalog.char_length(normalized_transmission) > 200
    or normalized_trim_name is not null and pg_catalog.char_length(normalized_trim_name) > 200
    or p_cylinders is not null and p_cylinders not between 1 and 64
    or p_horsepower is not null and p_horsepower not between 1 and 10000 then
    raise exception using errcode = '22023', message = 'invalid vehicle fact value';
  end if;
  if p_engine_liters is not null then
    if pg_catalog.btrim(p_engine_liters) !~ '^\d{1,2}(?:\.\d{1,3})?$' then
      raise exception using errcode = '22023', message = 'invalid engine displacement';
    end if;
    normalized_engine_liters := pg_catalog.btrim(p_engine_liters)::numeric(6, 3);
    if normalized_engine_liters not between 0.001 and 99.999 then
      raise exception using errcode = '22023', message = 'invalid engine displacement';
    end if;
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'request ID is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  after_facts_value := pg_catalog.jsonb_build_object(
    'modelYear', p_model_year,
    'make', normalized_make,
    'model', normalized_model,
    'bodyType', normalized_body_type,
    'cylinders', p_cylinders,
    'drivetrain', normalized_drivetrain,
    'engineLiters', case
      when normalized_engine_liters is null then null
      else pg_catalog.trim_scale(normalized_engine_liters)::text
    end,
    'fuelType', normalized_fuel_type,
    'horsepower', p_horsepower,
    'transmission', normalized_transmission,
    'trimName', normalized_trim_name
  );
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'vehicle_id', p_vehicle_id,
      'expected_facts_version', p_expected_facts_version,
      'facts', after_facts_value,
      'reason', normalized_reason
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fvehicle_facts_override\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.vehicle_facts_override_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'vehicle fact override idempotency key was reused';
    end if;
    return query select
      existing_receipt.vehicle_id,
      existing_receipt.facts_version,
      existing_receipt.history_id,
      true,
      existing_receipt.audit_event_id,
      existing_receipt.outbox_event_id;
    return;
  end if;

  select vehicle.*
    into target_vehicle
  from public.vehicles vehicle
  where vehicle.workspace_id = p_workspace_id
    and vehicle.id = p_vehicle_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'vehicle was not found';
  end if;
  if target_vehicle.facts_version <> p_expected_facts_version then
    raise exception using errcode = '40001', message = 'vehicle facts version conflict';
  end if;

  before_facts_value := pg_catalog.jsonb_build_object(
    'modelYear', target_vehicle.model_year,
    'make', target_vehicle.make,
    'model', target_vehicle.model,
    'bodyType', target_vehicle.body_type,
    'cylinders', target_vehicle.cylinders,
    'drivetrain', target_vehicle.drivetrain,
    'engineLiters', case
      when target_vehicle.engine_displacement_liters is null then null
      else pg_catalog.trim_scale(target_vehicle.engine_displacement_liters)::text
    end,
    'fuelType', target_vehicle.fuel_type,
    'horsepower', target_vehicle.horsepower,
    'transmission', target_vehicle.transmission,
    'trimName', target_vehicle.trim_name
  );

  if before_facts_value = after_facts_value then
    raise exception using errcode = '23514', message = 'vehicle facts did not change';
  end if;

  next_facts_version := target_vehicle.facts_version + 1;
  update public.vehicles
  set model_year = p_model_year,
      make = normalized_make,
      model = normalized_model,
      body_type = normalized_body_type,
      cylinders = p_cylinders,
      drivetrain = normalized_drivetrain,
      engine_displacement_liters = normalized_engine_liters,
      fuel_type = normalized_fuel_type,
      horsepower = p_horsepower,
      transmission = normalized_transmission,
      trim_name = normalized_trim_name,
      facts_version = next_facts_version,
      updated_at = pg_catalog.statement_timestamp()
  where workspace_id = p_workspace_id
    and id = target_vehicle.id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'vehicle.facts_overridden',
    p_entity_type => 'vehicle',
    p_entity_id => target_vehicle.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => before_facts_value || pg_catalog.jsonb_build_object(
      'factsVersion', target_vehicle.facts_version
    ),
    p_after_data => after_facts_value || pg_catalog.jsonb_build_object(
      'factsVersion', next_facts_version
    ),
    p_diff => pg_catalog.jsonb_build_object(
      'beforeFactsVersion', target_vehicle.facts_version,
      'afterFactsVersion', next_facts_version
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('command', 'override_vehicle_facts')
  );

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
    'vehicle.facts_overridden',
    'vehicle',
    target_vehicle.id,
    next_facts_version,
    1,
    pg_catalog.jsonb_build_object(
      'vehicle_id', target_vehicle.id,
      'facts_version', next_facts_version,
      'history_id', new_history_id
    ),
    actor_user_id,
    p_correlation_id
  ) returning id into new_outbox_event_id;

  insert into public.vehicle_facts_override_history (
    id,
    workspace_id,
    vehicle_id,
    facts_version_before,
    facts_version_after,
    before_facts,
    after_facts,
    reason,
    actor_user_id,
    request_id,
    correlation_id,
    audit_event_id,
    outbox_event_id
  ) values (
    new_history_id,
    p_workspace_id,
    target_vehicle.id,
    target_vehicle.facts_version,
    next_facts_version,
    before_facts_value,
    after_facts_value,
    normalized_reason,
    actor_user_id,
    p_request_id,
    p_correlation_id,
    new_audit_event_id,
    new_outbox_event_id
  );

  insert into public.vehicle_facts_override_command_receipts (
    workspace_id,
    actor_user_id,
    idempotency_key,
    command_fingerprint,
    vehicle_id,
    history_id,
    facts_version,
    audit_event_id,
    outbox_event_id
  ) values (
    p_workspace_id,
    actor_user_id,
    normalized_idempotency_key,
    request_fingerprint,
    target_vehicle.id,
    new_history_id,
    next_facts_version,
    new_audit_event_id,
    new_outbox_event_id
  );

  return query select
    target_vehicle.id,
    next_facts_version,
    new_history_id,
    false,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

alter table public.vehicle_facts_override_history enable row level security;
alter table public.vehicle_facts_override_history force row level security;
alter table public.vehicle_facts_override_command_receipts enable row level security;
alter table public.vehicle_facts_override_command_receipts force row level security;

create policy vehicle_facts_override_history_select
on public.vehicle_facts_override_history
for select to authenticated
using (
  app.has_permission(workspace_id, 'inventory.read')
  and app.has_permission(workspace_id, 'inventory.facts_override')
);

create policy vehicle_facts_override_receipts_select
on public.vehicle_facts_override_command_receipts
for select to authenticated
using (
  actor_user_id = auth.uid()
  and app.has_permission(workspace_id, 'inventory.facts_override')
);

revoke all on public.vehicle_facts_override_history from anon, authenticated;
revoke all on public.vehicle_facts_override_command_receipts from anon, authenticated;
grant select on public.vehicle_facts_override_history to authenticated;
grant select on public.vehicle_facts_override_command_receipts to authenticated;

revoke all on function app.prevent_vehicle_facts_history_mutation() from public;
revoke all on function app.get_inventory_unit_operations(uuid, uuid) from public;
revoke all on function app.list_active_inventory_locations(uuid) from public;
revoke all on function app.get_inventory_unit_costs(
  uuid, uuid, timestamptz, uuid, integer
) from public;
revoke all on function app.list_inventory_saved_views(uuid, boolean) from public;
revoke all on function app.archive_inventory_saved_view(
  uuid, text, uuid, bigint, text, uuid
) from public;
revoke all on function app.override_vehicle_facts(
  uuid, text, uuid, bigint, integer, text, text, text, integer, text, text,
  text, integer, text, text, text, text, uuid
) from public;

grant execute on function app.get_inventory_unit_operations(uuid, uuid)
  to authenticated;
grant execute on function app.list_active_inventory_locations(uuid)
  to authenticated;
grant execute on function app.get_inventory_unit_costs(
  uuid, uuid, timestamptz, uuid, integer
) to authenticated;
grant execute on function app.list_inventory_saved_views(uuid, boolean)
  to authenticated;
grant execute on function app.archive_inventory_saved_view(
  uuid, text, uuid, bigint, text, uuid
) to authenticated;
grant execute on function app.override_vehicle_facts(
  uuid, text, uuid, bigint, integer, text, text, text, integer, text, text,
  text, integer, text, text, text, text, uuid
) to authenticated;

comment on function app.get_inventory_unit_operations(uuid, uuid) is
  'Workspace/permission-scoped inventory operator projection with masked internal and cost fields.';
comment on function app.get_inventory_unit_costs(
  uuid, uuid, timestamptz, uuid, integer
) is
  'Bounded exact-minor-unit ledger, metrics, active localized categories, and stable cursor.';
comment on function app.override_vehicle_facts(
  uuid, text, uuid, bigint, integer, text, text, text, integer, text, text,
  text, integer, text, text, text, text, uuid
) is
  'Recent-step-up, versioned, idempotent full facts replacement with immutable provenance.';
