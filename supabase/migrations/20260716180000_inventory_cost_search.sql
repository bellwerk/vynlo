-- VYN-COST-001, VYN-SEARCH-001, VYN-INV-001, VYN-TEN-001, VYN-AUD-001
-- T-COST-001, T-COST-002, T-SEARCH-001, T-TEN-001, T-RBAC-001
-- Forward-only M2 inventory cost ledger, metrics, bounded search, and saved views.

create extension if not exists pg_trgm with schema extensions;

create table public.inventory_cost_category_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key text not null check (
    key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
  ),
  version integer not null check (version > 0),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and pg_catalog.jsonb_object_length(labels) > 0
  ),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  created_by uuid references auth.users (id) on delete restrict,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key, version),
  check (
    (status = 'draft' and activated_at is null and retired_at is null)
    or (status = 'active' and activated_at is not null and retired_at is null)
    or (status = 'retired' and activated_at is not null and retired_at is not null)
  )
);

create unique index inventory_cost_category_active_uidx
  on public.inventory_cost_category_definitions (workspace_id, key)
  where status = 'active';

create table public.inventory_cost_entries (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  inventory_unit_id uuid not null,
  category_definition_id uuid not null,
  entry_kind text not null check (entry_kind in ('cost', 'reversal')),
  reversal_of_id uuid,
  amount_minor bigint not null check (amount_minor >= 0),
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
  incurred_on date not null,
  vendor_party_id uuid,
  description text check (
    description is null or (
      pg_catalog.btrim(description) <> ''
      and pg_catalog.char_length(description) <= 2000
    )
  ),
  supporting_file_id uuid,
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  aggregate_version bigint not null check (aggregate_version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, idempotency_key),
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, category_definition_id)
    references public.inventory_cost_category_definitions (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, reversal_of_id)
    references public.inventory_cost_entries (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, vendor_party_id)
    references public.parties (workspace_id, id)
    on delete restrict,
  check (
    (entry_kind = 'cost' and reversal_of_id is null)
    or (entry_kind = 'reversal' and reversal_of_id is not null)
  )
);

create unique index inventory_cost_entries_reversal_uidx
  on public.inventory_cost_entries (workspace_id, reversal_of_id)
  where entry_kind = 'reversal';
create index inventory_cost_entries_unit_date_idx
  on public.inventory_cost_entries (
    workspace_id,
    inventory_unit_id,
    incurred_on desc,
    created_at desc,
    id
  );
create index inventory_cost_entries_category_date_idx
  on public.inventory_cost_entries (
    workspace_id,
    category_definition_id,
    incurred_on desc,
    id
  );

create view public.inventory_cost_entry_history
with (security_invoker = true)
as
select
  entry.*,
  case
    when entry.entry_kind = 'reversal' then 'reversal'
    when exists (
      select 1
      from public.inventory_cost_entries reversal
      where reversal.workspace_id = entry.workspace_id
        and reversal.reversal_of_id = entry.id
        and reversal.entry_kind = 'reversal'
    ) then 'reversed'
    else 'posted'
  end as effective_status
from public.inventory_cost_entries entry;

create table public.inventory_cost_metrics (
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  inventory_unit_id uuid not null,
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
  posted_cost_minor bigint not null default 0 check (posted_cost_minor >= 0),
  estimated_gross_minor bigint,
  posted_entry_count integer not null default 0 check (posted_entry_count >= 0),
  last_cost_at timestamptz,
  recalculated_at timestamptz not null default pg_catalog.statement_timestamp(),
  primary key (workspace_id, inventory_unit_id),
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id)
    on delete restrict
);

create table public.inventory_search_documents (
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  inventory_unit_id uuid not null,
  stock_number text not null,
  vin text not null,
  model_year integer,
  make text,
  model text,
  vehicle_trim text,
  location_name text,
  workflow_state_key text,
  search_text text not null,
  search_vector tsvector generated always as (
    pg_catalog.to_tsvector('simple'::regconfig, search_text)
  ) stored,
  refreshed_at timestamptz not null default pg_catalog.statement_timestamp(),
  primary key (workspace_id, inventory_unit_id),
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id)
    on delete cascade
);

create index inventory_search_documents_vector_idx
  on public.inventory_search_documents using gin (search_vector);
create index inventory_search_documents_trigram_idx
  on public.inventory_search_documents using gin (
    search_text extensions.gin_trgm_ops
  );

create table public.inventory_saved_views (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  owner_user_id uuid not null references auth.users (id) on delete restrict,
  name text not null check (
    pg_catalog.btrim(name) <> '' and pg_catalog.char_length(name) <= 120
  ),
  entity_type text not null default 'inventory_unit'
    check (entity_type = 'inventory_unit'),
  filters jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(filters) = 'object'),
  sort jsonb not null default '{"key":"updated_at","direction":"desc"}'::jsonb
    check (pg_catalog.jsonb_typeof(sort) = 'object'),
  visible_columns jsonb not null default '["stock","vehicle","state","price"]'::jsonb
    check (pg_catalog.jsonb_typeof(visible_columns) = 'array'),
  layout text not null default 'responsive' check (layout in ('responsive', 'cards', 'table')),
  density text not null default 'comfortable' check (density in ('comfortable', 'compact')),
  share_scope text not null default 'private' check (share_scope in ('private', 'workspace')),
  status text not null default 'active' check (status in ('active', 'archived')),
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, owner_user_id, name)
);

create index inventory_saved_views_visible_idx
  on public.inventory_saved_views (
    workspace_id,
    status,
    share_scope,
    owner_user_id,
    updated_at desc,
    id
  );

create table public.inventory_saved_view_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  saved_view_id uuid not null,
  saved_view_version bigint not null check (saved_view_version > 0),
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  audit_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  -- A workspace-shared view changes read visibility, not command ownership.
  -- Scope every replay receipt to its actor so a private or shared command can
  -- never return another user's durable result.
  unique (workspace_id, actor_user_id, idempotency_key),
  foreign key (workspace_id, saved_view_id)
    references public.inventory_saved_views (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id)
    on delete restrict
);

create function app.prevent_cost_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'posted inventory cost history is append-only';
end;
$$;

create function app.protect_inventory_cost_category_definition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'draft' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    if new.status in ('draft', 'active') then
      return new;
    end if;
  elsif old.status = 'active'
    and tg_op = 'UPDATE'
    and new.status = 'retired'
    and old.retired_at is null
    and new.retired_at is not null
    and row(
      new.id,
      new.workspace_id,
      new.key,
      new.version,
      new.labels,
      new.checksum,
      new.created_by,
      new.activated_at,
      new.created_at
    ) is not distinct from row(
      old.id,
      old.workspace_id,
      old.key,
      old.version,
      old.labels,
      old.checksum,
      old.created_by,
      old.activated_at,
      old.created_at
    ) then
    return new;
  end if;

  raise exception using
    errcode = '55000',
    message = 'activated inventory cost category configuration is immutable';
end;
$$;

create trigger inventory_cost_categories_immutable_ownership
before update on public.inventory_cost_category_definitions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'version', 'created_at'
);

create trigger inventory_cost_categories_immutable_configuration
before update or delete on public.inventory_cost_category_definitions
for each row execute function app.protect_inventory_cost_category_definition();

create trigger inventory_cost_entries_append_only
before update or delete on public.inventory_cost_entries
for each row execute function app.prevent_cost_history_mutation();

create trigger inventory_saved_view_receipts_append_only
before update or delete on public.inventory_saved_view_command_receipts
for each row execute function app.prevent_cost_history_mutation();

create trigger inventory_saved_views_updated_at
before update on public.inventory_saved_views
for each row execute function app.set_updated_at();

create function app.refresh_inventory_cost_metric(
  p_workspace_id uuid,
  p_inventory_unit_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_unit public.inventory_units%rowtype;
  total_cost bigint;
  entry_count integer;
  latest_cost_at timestamptz;
  gross_basis bigint;
begin
  select unit.*
    into target_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;

  select
    coalesce(sum(
      case entry.entry_kind when 'cost' then entry.amount_minor else -entry.amount_minor end
    ), 0)::bigint,
    count(*) filter (where entry.entry_kind = 'cost')::integer,
    max(entry.created_at)
    into total_cost, entry_count, latest_cost_at
  from public.inventory_cost_entries entry
  where entry.workspace_id = p_workspace_id
    and entry.inventory_unit_id = p_inventory_unit_id;

  if total_cost < 0 then
    raise exception using errcode = '23514', message = 'inventory cost total cannot be negative';
  end if;

  gross_basis := coalesce(
    target_unit.expected_sale_price_minor,
    target_unit.advertised_price_minor
  );

  insert into public.inventory_cost_metrics (
    workspace_id,
    inventory_unit_id,
    currency_code,
    posted_cost_minor,
    estimated_gross_minor,
    posted_entry_count,
    last_cost_at,
    recalculated_at
  ) values (
    p_workspace_id,
    p_inventory_unit_id,
    target_unit.currency_code,
    total_cost,
    case when gross_basis is null then null else gross_basis - total_cost end,
    entry_count,
    latest_cost_at,
    pg_catalog.statement_timestamp()
  )
  on conflict (workspace_id, inventory_unit_id) do update
  set currency_code = excluded.currency_code,
      posted_cost_minor = excluded.posted_cost_minor,
      estimated_gross_minor = excluded.estimated_gross_minor,
      posted_entry_count = excluded.posted_entry_count,
      last_cost_at = excluded.last_cost_at,
      recalculated_at = excluded.recalculated_at;
end;
$$;

create function app.refresh_inventory_cost_metric_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.refresh_inventory_cost_metric(new.workspace_id, new.inventory_unit_id);
  return new;
end;
$$;

create trigger inventory_cost_entries_refresh_metric
after insert on public.inventory_cost_entries
for each row execute function app.refresh_inventory_cost_metric_trigger();

create function app.refresh_inventory_price_metric_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.advertised_price_minor is distinct from old.advertised_price_minor
    or new.expected_sale_price_minor is distinct from old.expected_sale_price_minor then
    perform app.refresh_inventory_cost_metric(new.workspace_id, new.id);
  end if;
  return new;
end;
$$;

create trigger inventory_units_refresh_cost_metric
after update of advertised_price_minor, expected_sale_price_minor on public.inventory_units
for each row execute function app.refresh_inventory_price_metric_trigger();

create function app.refresh_inventory_search_document(
  p_workspace_id uuid,
  p_inventory_unit_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.inventory_search_documents (
    workspace_id,
    inventory_unit_id,
    stock_number,
    vin,
    model_year,
    make,
    model,
    vehicle_trim,
    location_name,
    workflow_state_key,
    search_text,
    refreshed_at
  )
  select
    unit.workspace_id,
    unit.id,
    unit.stock_number::text,
    vehicle.vin::text,
    vehicle.model_year,
    vehicle.make,
    vehicle.model,
    vehicle.trim_name,
    location.name,
    coalesce(unit.workflow_state_key, unit.status),
    pg_catalog.lower(pg_catalog.concat_ws(
      ' ',
      unit.stock_number::text,
      vehicle.vin::text,
      vehicle.model_year::text,
      vehicle.make,
      vehicle.model,
      vehicle.trim_name,
      location.name,
      coalesce(unit.workflow_state_key, unit.status)
    )),
    pg_catalog.statement_timestamp()
  from public.inventory_units unit
  join public.vehicles vehicle
    on vehicle.workspace_id = unit.workspace_id
   and vehicle.id = unit.vehicle_id
  left join public.locations location
    on location.workspace_id = unit.workspace_id
   and location.id = unit.location_id
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  on conflict (workspace_id, inventory_unit_id) do update
  set stock_number = excluded.stock_number,
      vin = excluded.vin,
      model_year = excluded.model_year,
      make = excluded.make,
      model = excluded.model,
      vehicle_trim = excluded.vehicle_trim,
      location_name = excluded.location_name,
      workflow_state_key = excluded.workflow_state_key,
      search_text = excluded.search_text,
      refreshed_at = excluded.refreshed_at;
end;
$$;

create function app.refresh_inventory_search_for_unit_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.refresh_inventory_search_document(new.workspace_id, new.id);
  return new;
end;
$$;

create trigger inventory_units_refresh_search_document
after insert or update of stock_number, vehicle_id, location_id, workflow_state_key, status
on public.inventory_units
for each row execute function app.refresh_inventory_search_for_unit_trigger();

create function app.refresh_inventory_search_for_vehicle_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  unit_id uuid;
begin
  for unit_id in
    select unit.id
    from public.inventory_units unit
    where unit.workspace_id = new.workspace_id
      and unit.vehicle_id = new.id
  loop
    perform app.refresh_inventory_search_document(new.workspace_id, unit_id);
  end loop;
  return new;
end;
$$;

create trigger vehicles_refresh_inventory_search
after update of vin, model_year, make, model, trim_name on public.vehicles
for each row execute function app.refresh_inventory_search_for_vehicle_trigger();

create function app.refresh_inventory_search_for_location_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  unit_id uuid;
begin
  for unit_id in
    select unit.id
    from public.inventory_units unit
    where unit.workspace_id = new.workspace_id
      and unit.location_id = new.id
  loop
    perform app.refresh_inventory_search_document(new.workspace_id, unit_id);
  end loop;
  return new;
end;
$$;

create trigger locations_refresh_inventory_search
after update of name on public.locations
for each row execute function app.refresh_inventory_search_for_location_trigger();

insert into public.inventory_cost_metrics (
  workspace_id,
  inventory_unit_id,
  currency_code,
  posted_cost_minor,
  estimated_gross_minor,
  posted_entry_count,
  recalculated_at
)
select
  unit.workspace_id,
  unit.id,
  unit.currency_code,
  0,
  coalesce(unit.expected_sale_price_minor, unit.advertised_price_minor),
  0,
  pg_catalog.statement_timestamp()
from public.inventory_units unit
on conflict (workspace_id, inventory_unit_id) do nothing;

select app.refresh_inventory_search_document(unit.workspace_id, unit.id)
from public.inventory_units unit;

create function app.post_inventory_cost_entry(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_category_definition_id uuid,
  p_amount_minor bigint,
  p_currency_code text,
  p_incurred_on date,
  p_vendor_party_id uuid,
  p_description text,
  p_supporting_file_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
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
  target_unit public.inventory_units%rowtype;
  linked_instance public.workflow_instances%rowtype;
  existing_entry public.inventory_cost_entries%rowtype;
  normalized_idempotency_key text;
  normalized_currency text;
  normalized_description text;
  request_fingerprint text;
  next_version bigint;
  new_entry_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'costs.create'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_description := pg_catalog.nullif(
    pg_catalog.btrim(coalesce(p_description, '')),
    ''
  );

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid cost idempotency key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception using errcode = '22023', message = 'cost amount must be positive minor units';
  end if;
  if normalized_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'invalid cost currency';
  end if;
  if p_incurred_on is null or p_incurred_on > current_date then
    raise exception using errcode = '22023', message = 'invalid cost incurred date';
  end if;
  if normalized_description is not null
    and pg_catalog.char_length(normalized_description) > 2000 then
    raise exception using errcode = '22023', message = 'cost description is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'request ID is too long';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_version', p_expected_version,
      'category_definition_id', p_category_definition_id,
      'amount_minor', p_amount_minor,
      'currency_code', normalized_currency,
      'incurred_on', p_incurred_on,
      'vendor_party_id', p_vendor_party_id,
      'description', normalized_description,
      'supporting_file_id', p_supporting_file_id
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1finventory_cost\x1f' || normalized_idempotency_key,
      0
    )
  );

  select entry.*
    into existing_entry
  from public.inventory_cost_entries entry
  where entry.workspace_id = p_workspace_id
    and entry.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_entry.command_fingerprint <> request_fingerprint
      or existing_entry.entry_kind <> 'cost' then
      raise exception using
        errcode = '23505',
        message = 'cost idempotency key was used for a different command';
    end if;
    select audit.id
      into new_audit_event_id
    from public.audit_events audit
    where audit.workspace_id = p_workspace_id
      and audit.entity_type = 'inventory_cost_entry'
      and audit.entity_id = existing_entry.id
      and audit.action = 'inventory_cost.posted'
    order by audit.occurred_at, audit.id
    limit 1;
    select event.id
      into new_outbox_event_id
    from public.outbox_events event
    where event.workspace_id = p_workspace_id
      and event.aggregate_type = 'inventory_unit'
      and event.aggregate_id = existing_entry.inventory_unit_id
      and event.aggregate_version = existing_entry.aggregate_version
      and event.event_name = 'inventory_cost.posted'
    order by event.created_at, event.id
    limit 1;
    if new_audit_event_id is null or new_outbox_event_id is null then
      raise exception using errcode = '55000', message = 'cost command receipt is incomplete';
    end if;
    return query select
      existing_entry.id,
      existing_entry.inventory_unit_id,
      existing_entry.aggregate_version,
      true,
      new_audit_event_id,
      new_outbox_event_id;
    return;
  end if;

  select unit.*
    into target_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if target_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if target_unit.workflow_instance_id is not null then
    select instance.*
      into linked_instance
    from public.workflow_instances instance
    where instance.workspace_id = p_workspace_id
      and instance.id = target_unit.workflow_instance_id
      and instance.entity_type = 'inventory_unit'
      and instance.entity_id = p_inventory_unit_id
      and instance.purpose_key = 'primary'
    for update;

    if not found then
      raise exception using errcode = '23514', message = 'inventory workflow is unavailable';
    end if;
    if linked_instance.version <> target_unit.version
      or linked_instance.current_state_key <> target_unit.workflow_state_key
      or linked_instance.canonical_status <> target_unit.status then
      raise exception using
        errcode = '40001',
        message = 'inventory workflow aggregate versions are inconsistent';
    end if;
  end if;
  if target_unit.currency_code <> normalized_currency then
    raise exception using errcode = '23514', message = 'cost currency must match inventory currency';
  end if;
  if not exists (
    select 1
    from public.inventory_cost_category_definitions category
    where category.workspace_id = p_workspace_id
      and category.id = p_category_definition_id
      and category.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'an active cost category is required';
  end if;
  if p_vendor_party_id is not null and not exists (
    select 1
    from public.parties party
    where party.workspace_id = p_workspace_id
      and party.id = p_vendor_party_id
      and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'cost vendor is unavailable';
  end if;
  if p_supporting_file_id is not null and not exists (
    select 1
    from public.media_files file
    join public.media_assets asset
      on asset.workspace_id = file.workspace_id
     and asset.id = file.media_id
    where file.workspace_id = p_workspace_id
      and file.id = p_supporting_file_id
      and file.file_class = 'legal_document_original'
      and file.variant = 'legal_original'
      and file.deleted_at is null
      and asset.status = 'ready'
      and asset.owner_entity_type = 'inventory_unit'
      and asset.owner_entity_id = p_inventory_unit_id
      and asset.media_kind in ('legal_document', 'attachment')
  ) then
    raise exception using
      errcode = '23514',
      message = 'cost supporting file is unavailable';
  end if;

  next_version := target_unit.version + 1;
  new_entry_id := pg_catalog.gen_random_uuid();
  insert into public.inventory_cost_entries (
    id,
    workspace_id,
    inventory_unit_id,
    category_definition_id,
    entry_kind,
    amount_minor,
    currency_code,
    incurred_on,
    vendor_party_id,
    description,
    supporting_file_id,
    idempotency_key,
    command_fingerprint,
    aggregate_version,
    created_by
  ) values (
    new_entry_id,
    p_workspace_id,
    p_inventory_unit_id,
    p_category_definition_id,
    'cost',
    p_amount_minor,
    normalized_currency,
    p_incurred_on,
    p_vendor_party_id,
    normalized_description,
    p_supporting_file_id,
    normalized_idempotency_key,
    request_fingerprint,
    next_version,
    actor_user_id
  );

  if target_unit.workflow_instance_id is not null then
    update public.workflow_instances
    set version = next_version
    where workspace_id = p_workspace_id
      and id = linked_instance.id;
  end if;

  update public.inventory_units
  set version = next_version
  where workspace_id = p_workspace_id
    and id = p_inventory_unit_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_cost.posted',
    p_entity_type => 'inventory_cost_entry',
    p_entity_id => new_entry_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'category_definition_id', p_category_definition_id,
      'amount_minor', p_amount_minor::text,
      'currency_code', normalized_currency,
      'aggregate_version', next_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'vendor_party_id', p_vendor_party_id,
      'supporting_file_id', p_supporting_file_id
    )
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_cost.posted',
    p_inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', p_inventory_unit_id,
      'costEntryId', new_entry_id,
      'amountMinor', p_amount_minor::text,
      'currencyCode', normalized_currency,
      'aggregateVersion', next_version
    ),
    actor_user_id,
    p_correlation_id
  );

  return query select
    new_entry_id,
    p_inventory_unit_id,
    next_version,
    false,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create function app.reverse_inventory_cost_entry(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_cost_entry_id uuid,
  p_expected_version bigint,
  p_reversed_on date,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  reversal_entry_id uuid,
  original_cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
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
  original_entry public.inventory_cost_entries%rowtype;
  existing_reversal public.inventory_cost_entries%rowtype;
  target_unit public.inventory_units%rowtype;
  linked_instance public.workflow_instances%rowtype;
  normalized_idempotency_key text;
  normalized_reason text;
  request_fingerprint text;
  next_version bigint;
  new_reversal_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'costs.reverse',
    true
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid reversal idempotency key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'cost reversal reason is required';
  end if;
  if p_reversed_on is null or p_reversed_on > current_date then
    raise exception using errcode = '22023', message = 'invalid reversal date';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'cost_entry_id', p_cost_entry_id,
      'expected_version', p_expected_version,
      'reversed_on', p_reversed_on,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1finventory_cost\x1f' || normalized_idempotency_key,
      0
    )
  );

  select entry.*
    into existing_reversal
  from public.inventory_cost_entries entry
  where entry.workspace_id = p_workspace_id
    and entry.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_reversal.command_fingerprint <> request_fingerprint
      or existing_reversal.entry_kind <> 'reversal' then
      raise exception using
        errcode = '23505',
        message = 'reversal idempotency key was used for a different command';
    end if;
    select audit.id
      into new_audit_event_id
    from public.audit_events audit
    where audit.workspace_id = p_workspace_id
      and audit.entity_type = 'inventory_cost_entry'
      and audit.entity_id = existing_reversal.id
      and audit.action = 'inventory_cost.reversed'
    order by audit.occurred_at, audit.id
    limit 1;
    select event.id
      into new_outbox_event_id
    from public.outbox_events event
    where event.workspace_id = p_workspace_id
      and event.aggregate_type = 'inventory_unit'
      and event.aggregate_id = existing_reversal.inventory_unit_id
      and event.aggregate_version = existing_reversal.aggregate_version
      and event.event_name = 'inventory_cost.reversed'
    order by event.created_at, event.id
    limit 1;
    if new_audit_event_id is null or new_outbox_event_id is null then
      raise exception using errcode = '55000', message = 'reversal command receipt is incomplete';
    end if;
    return query select
      existing_reversal.id,
      existing_reversal.reversal_of_id,
      existing_reversal.inventory_unit_id,
      existing_reversal.aggregate_version,
      true,
      new_audit_event_id,
      new_outbox_event_id;
    return;
  end if;

  select entry.*
    into original_entry
  from public.inventory_cost_entries entry
  where entry.workspace_id = p_workspace_id
    and entry.id = p_cost_entry_id
    and entry.entry_kind = 'cost';
  if not found then
    raise exception using errcode = '23514', message = 'posted cost entry is unavailable';
  end if;
  if p_reversed_on < original_entry.incurred_on then
    raise exception using errcode = '22023', message = 'invalid reversal date';
  end if;

  select unit.*
    into target_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = original_entry.inventory_unit_id
  for update;
  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if target_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if target_unit.workflow_instance_id is not null then
    select instance.*
      into linked_instance
    from public.workflow_instances instance
    where instance.workspace_id = p_workspace_id
      and instance.id = target_unit.workflow_instance_id
      and instance.entity_type = 'inventory_unit'
      and instance.entity_id = original_entry.inventory_unit_id
      and instance.purpose_key = 'primary'
    for update;

    if not found then
      raise exception using errcode = '23514', message = 'inventory workflow is unavailable';
    end if;
    if linked_instance.version <> target_unit.version
      or linked_instance.current_state_key <> target_unit.workflow_state_key
      or linked_instance.canonical_status <> target_unit.status then
      raise exception using
        errcode = '40001',
        message = 'inventory workflow aggregate versions are inconsistent';
    end if;
  end if;
  if exists (
    select 1
    from public.inventory_cost_entries reversal
    where reversal.workspace_id = p_workspace_id
      and reversal.reversal_of_id = original_entry.id
      and reversal.entry_kind = 'reversal'
  ) then
    raise exception using errcode = '23514', message = 'cost entry is already reversed';
  end if;

  next_version := target_unit.version + 1;
  new_reversal_id := pg_catalog.gen_random_uuid();
  insert into public.inventory_cost_entries (
    id,
    workspace_id,
    inventory_unit_id,
    category_definition_id,
    entry_kind,
    reversal_of_id,
    amount_minor,
    currency_code,
    incurred_on,
    vendor_party_id,
    description,
    supporting_file_id,
    idempotency_key,
    command_fingerprint,
    aggregate_version,
    created_by
  ) values (
    new_reversal_id,
    p_workspace_id,
    original_entry.inventory_unit_id,
    original_entry.category_definition_id,
    'reversal',
    original_entry.id,
    original_entry.amount_minor,
    original_entry.currency_code,
    p_reversed_on,
    original_entry.vendor_party_id,
    normalized_reason,
    original_entry.supporting_file_id,
    normalized_idempotency_key,
    request_fingerprint,
    next_version,
    actor_user_id
  );

  if target_unit.workflow_instance_id is not null then
    update public.workflow_instances
    set version = next_version
    where workspace_id = p_workspace_id
      and id = linked_instance.id;
  end if;

  update public.inventory_units
  set version = next_version
  where workspace_id = p_workspace_id
    and id = original_entry.inventory_unit_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_cost.reversed',
    p_entity_type => 'inventory_cost_entry',
    p_entity_id => new_reversal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'original_cost_entry_id', original_entry.id,
      'inventory_unit_id', original_entry.inventory_unit_id,
      'amount_minor', original_entry.amount_minor::text,
      'currency_code', original_entry.currency_code,
      'aggregate_version', next_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2',
    p_metadata => pg_catalog.jsonb_build_object('reason_recorded', true)
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_cost.reversed',
    original_entry.inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', original_entry.inventory_unit_id,
      'costEntryId', original_entry.id,
      'reversalEntryId', new_reversal_id,
      'amountMinor', original_entry.amount_minor::text,
      'currencyCode', original_entry.currency_code::text,
      'aggregateVersion', next_version
    ),
    actor_user_id,
    p_correlation_id
  );

  return query select
    new_reversal_id,
    original_entry.id,
    original_entry.inventory_unit_id,
    next_version,
    false,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create function app.inventory_saved_view_payload_valid(
  p_filters jsonb,
  p_sort jsonb,
  p_visible_columns jsonb
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  filter_value jsonb;
  minimum_price numeric;
  maximum_price numeric;
  minimum_age numeric;
  maximum_age numeric;
begin
  if p_filters is null
    or pg_catalog.jsonb_typeof(p_filters) <> 'object'
    or pg_catalog.octet_length(p_filters::text) > 10000
    or exists (
      select 1
      from pg_catalog.jsonb_object_keys(p_filters) filter_key
      where filter_key not in (
        'status', 'locationIds', 'make', 'model', 'minimumPriceMinor',
        'maximumPriceMinor', 'minimumDaysInStock', 'maximumDaysInStock',
        'missingFields'
      )
    ) then
    return false;
  end if;

  if p_filters ? 'status' then
    filter_value := p_filters -> 'status';
    if pg_catalog.jsonb_typeof(filter_value) <> 'array'
      or pg_catalog.jsonb_array_length(filter_value) > 5
      or exists (
        select 1 from pg_catalog.jsonb_array_elements(filter_value) item
        where pg_catalog.jsonb_typeof(item) <> 'string'
          or item #>> '{}' not in ('draft', 'active', 'pending', 'closed', 'archived')
      ) then
      return false;
    end if;
  end if;

  if p_filters ? 'locationIds' then
    filter_value := p_filters -> 'locationIds';
    if pg_catalog.jsonb_typeof(filter_value) <> 'array'
      or pg_catalog.jsonb_array_length(filter_value) > 20
      or exists (
        select 1 from pg_catalog.jsonb_array_elements(filter_value) item
        where pg_catalog.jsonb_typeof(item) <> 'string'
          or item #>> '{}' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      ) then
      return false;
    end if;
  end if;

  foreach filter_value in array array[p_filters -> 'make', p_filters -> 'model'] loop
    if filter_value is not null and (
      pg_catalog.jsonb_typeof(filter_value) <> 'string'
      or pg_catalog.btrim(filter_value #>> '{}') <> filter_value #>> '{}'
      or pg_catalog.char_length(filter_value #>> '{}') not between 1 and 100
    ) then
      return false;
    end if;
  end loop;

  if p_filters ? 'missingFields' then
    filter_value := p_filters -> 'missingFields';
    if pg_catalog.jsonb_typeof(filter_value) <> 'array'
      or pg_catalog.jsonb_array_length(filter_value) > 7
      or exists (
        select 1 from pg_catalog.jsonb_array_elements(filter_value) item
        where pg_catalog.jsonb_typeof(item) <> 'string'
          or item #>> '{}' not in (
            'vin', 'model_year', 'make', 'model', 'location', 'price', 'media'
          )
      ) then
      return false;
    end if;
  end if;

  if p_filters ? 'minimumPriceMinor' then
    filter_value := p_filters -> 'minimumPriceMinor';
    if pg_catalog.jsonb_typeof(filter_value) <> 'string'
      or filter_value #>> '{}' !~ '^(0|[1-9][0-9]{0,18})$'
      or (filter_value #>> '{}')::numeric > 9223372036854775807 then
      return false;
    end if;
    minimum_price := (filter_value #>> '{}')::numeric;
  end if;
  if p_filters ? 'maximumPriceMinor' then
    filter_value := p_filters -> 'maximumPriceMinor';
    if pg_catalog.jsonb_typeof(filter_value) <> 'string'
      or filter_value #>> '{}' !~ '^(0|[1-9][0-9]{0,18})$'
      or (filter_value #>> '{}')::numeric > 9223372036854775807 then
      return false;
    end if;
    maximum_price := (filter_value #>> '{}')::numeric;
  end if;
  if minimum_price is not null and maximum_price is not null
    and minimum_price > maximum_price then
    return false;
  end if;

  if p_filters ? 'minimumDaysInStock' then
    filter_value := p_filters -> 'minimumDaysInStock';
    if pg_catalog.jsonb_typeof(filter_value) <> 'number'
      or (filter_value #>> '{}')::numeric <> pg_catalog.trunc((filter_value #>> '{}')::numeric)
      or (filter_value #>> '{}')::numeric not between 0 and 100000 then
      return false;
    end if;
    minimum_age := (filter_value #>> '{}')::numeric;
  end if;
  if p_filters ? 'maximumDaysInStock' then
    filter_value := p_filters -> 'maximumDaysInStock';
    if pg_catalog.jsonb_typeof(filter_value) <> 'number'
      or (filter_value #>> '{}')::numeric <> pg_catalog.trunc((filter_value #>> '{}')::numeric)
      or (filter_value #>> '{}')::numeric not between 0 and 100000 then
      return false;
    end if;
    maximum_age := (filter_value #>> '{}')::numeric;
  end if;
  if minimum_age is not null and maximum_age is not null
    and minimum_age > maximum_age then
    return false;
  end if;

  if p_sort is null
    or pg_catalog.jsonb_typeof(p_sort) <> 'object'
    or pg_catalog.jsonb_object_length(p_sort) <> 2
    or pg_catalog.jsonb_typeof(p_sort -> 'key') <> 'string'
    or pg_catalog.jsonb_typeof(p_sort -> 'direction') <> 'string'
    or p_sort ->> 'key' not in (
      'updated_at', 'stock_number', 'advertised_price', 'days_in_stock',
      'estimated_gross'
    )
    or p_sort ->> 'direction' not in ('asc', 'desc') then
    return false;
  end if;

  if p_visible_columns is null
    or pg_catalog.jsonb_typeof(p_visible_columns) <> 'array'
    or pg_catalog.jsonb_array_length(p_visible_columns) not between 1 and 20
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_visible_columns) item
      where pg_catalog.jsonb_typeof(item) <> 'string'
        or item #>> '{}' not in (
          'cover', 'stock', 'vehicle', 'vin', 'price', 'location', 'state',
          'days_in_stock', 'media_readiness', 'listing_status', 'warnings',
          'posted_cost', 'estimated_gross'
        )
    )
    or (
      select count(*) <> count(distinct item #>> '{}')
      from pg_catalog.jsonb_array_elements(p_visible_columns) item
    ) then
    return false;
  end if;

  return true;
exception
  when others then
    return false;
end;
$$;

alter table public.inventory_saved_views
  add constraint inventory_saved_views_payload_check check (
    app.inventory_saved_view_payload_valid(filters, sort, visible_columns)
  );

create function app.save_inventory_view(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_saved_view_id uuid,
  p_expected_version bigint,
  p_name text,
  p_filters jsonb,
  p_sort jsonb,
  p_visible_columns jsonb,
  p_layout text,
  p_density text,
  p_share_scope text,
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
  existing_receipt public.inventory_saved_view_command_receipts%rowtype;
  target_view public.inventory_saved_views%rowtype;
  normalized_idempotency_key text;
  normalized_name text;
  request_fingerprint text;
  next_view_id uuid;
  next_version bigint;
  new_audit_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.read'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_name := pg_catalog.btrim(coalesce(p_name, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid saved-view idempotency key';
  end if;
  if normalized_name = '' or pg_catalog.char_length(normalized_name) > 120 then
    raise exception using errcode = '22023', message = 'invalid saved-view name';
  end if;
  if p_layout not in ('responsive', 'cards', 'table')
    or p_density not in ('comfortable', 'compact')
    or p_share_scope not in ('private', 'workspace')
    or not app.inventory_saved_view_payload_valid(
      p_filters,
      p_sort,
      p_visible_columns
    ) then
    raise exception using errcode = '22023', message = 'invalid saved-view configuration';
  end if;
  if p_saved_view_id is null and p_expected_version is not null
    or p_saved_view_id is not null and (p_expected_version is null or p_expected_version < 1) then
    raise exception using errcode = '22023', message = 'invalid saved-view version contract';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_share_scope = 'workspace' then
    perform app.require_vertical_slice_permission(
      p_workspace_id,
      'inventory.update'
    );
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'saved_view_id', p_saved_view_id,
      'expected_version', p_expected_version,
      'name', normalized_name,
      'filters', p_filters,
      'sort', p_sort,
      'visible_columns', p_visible_columns,
      'layout', p_layout,
      'density', p_density,
      'share_scope', p_share_scope
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
    and receipt.actor_user_id = actor_user_id
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

  if p_saved_view_id is null then
    next_view_id := pg_catalog.gen_random_uuid();
    next_version := 1;
    insert into public.inventory_saved_views (
      id,
      workspace_id,
      owner_user_id,
      name,
      filters,
      sort,
      visible_columns,
      layout,
      density,
      share_scope,
      version
    ) values (
      next_view_id,
      p_workspace_id,
      actor_user_id,
      normalized_name,
      p_filters,
      p_sort,
      p_visible_columns,
      p_layout,
      p_density,
      p_share_scope,
      next_version
    );
  else
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
    next_view_id := target_view.id;
    next_version := target_view.version + 1;
    update public.inventory_saved_views
    set name = normalized_name,
        filters = p_filters,
        sort = p_sort,
        visible_columns = p_visible_columns,
        layout = p_layout,
        density = p_density,
        share_scope = p_share_scope,
        version = next_version
    where workspace_id = p_workspace_id
      and id = target_view.id;
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => case when p_saved_view_id is null
      then 'inventory_saved_view.created'
      else 'inventory_saved_view.updated'
    end,
    p_entity_type => 'inventory_saved_view',
    p_entity_id => next_view_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'version', next_version,
      'share_scope', p_share_scope,
      'layout', p_layout,
      'density', p_density
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
    next_view_id,
    next_version,
    actor_user_id,
    new_audit_event_id
  );

  return query select next_view_id, next_version, false, new_audit_event_id;
end;
$$;

create function app.search_inventory_units(
  p_workspace_id uuid,
  p_query text default null,
  p_statuses text[] default null,
  p_location_ids uuid[] default null,
  p_minimum_price_minor bigint default null,
  p_maximum_price_minor bigint default null,
  p_minimum_days_in_stock integer default null,
  p_maximum_days_in_stock integer default null,
  p_before_rank real default null,
  p_before_updated_at timestamptz default null,
  p_before_id uuid default null,
  p_page_size integer default 50
)
returns table (
  inventory_unit_id uuid,
  stock_number text,
  vin text,
  model_year integer,
  make text,
  model text,
  vehicle_trim text,
  canonical_status text,
  workflow_state_key text,
  location_id uuid,
  location_name text,
  advertised_price_minor text,
  currency_code text,
  days_in_stock integer,
  posted_cost_minor text,
  estimated_gross_minor text,
  aggregate_version bigint,
  updated_at timestamptz,
  search_rank real
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_query text;
  can_read_costs boolean;
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');
  normalized_query := pg_catalog.nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_query, ''))),
    ''
  );
  can_read_costs := app.has_permission(p_workspace_id, 'costs.read');

  if normalized_query is not null and pg_catalog.char_length(normalized_query) > 200 then
    raise exception using errcode = '22023', message = 'inventory search query is too long';
  end if;
  if p_page_size is null or p_page_size not between 1 and 100 then
    raise exception using errcode = '22023', message = 'inventory page size must be from 1 to 100';
  end if;
  if p_statuses is not null and (
    pg_catalog.cardinality(p_statuses) > 5
    or pg_catalog.array_position(p_statuses, null) is not null
    or exists (
      select 1 from pg_catalog.unnest(p_statuses) status_key
      where status_key not in ('draft', 'active', 'pending', 'closed', 'archived')
    )
  ) then
    raise exception using errcode = '22023', message = 'invalid inventory status filter';
  end if;
  if p_location_ids is not null and (
    pg_catalog.cardinality(p_location_ids) > 20
    or pg_catalog.array_position(p_location_ids, null) is not null
  ) then
    raise exception using errcode = '22023', message = 'invalid inventory location filter';
  end if;
  if p_minimum_price_minor is not null and p_minimum_price_minor < 0
    or p_maximum_price_minor is not null and p_maximum_price_minor < 0
    or p_minimum_price_minor is not null and p_maximum_price_minor is not null
      and p_minimum_price_minor > p_maximum_price_minor then
    raise exception using errcode = '22023', message = 'invalid inventory price filter';
  end if;
  if p_minimum_days_in_stock is not null
      and p_minimum_days_in_stock not between 0 and 100000
    or p_maximum_days_in_stock is not null
      and p_maximum_days_in_stock not between 0 and 100000
    or p_minimum_days_in_stock is not null and p_maximum_days_in_stock is not null
      and p_minimum_days_in_stock > p_maximum_days_in_stock then
    raise exception using errcode = '22023', message = 'invalid inventory age filter';
  end if;
  if (p_before_rank is null) <> (p_before_updated_at is null)
    or (p_before_rank is null) <> (p_before_id is null) then
    raise exception using errcode = '22023', message = 'inventory search cursor is incomplete';
  end if;
  if p_before_rank is not null and (
    p_before_rank < 0
    or p_before_rank = 'NaN'::real
    or p_before_rank = 'Infinity'::real
    or p_before_rank = '-Infinity'::real
  ) then
    raise exception using errcode = '22023', message = 'inventory search cursor is invalid';
  end if;

  return query
  with ranked as (
    select
      unit.id,
      document.stock_number,
      document.vin,
      document.model_year,
      document.make,
      document.model,
      document.vehicle_trim,
      unit.status,
      coalesce(unit.workflow_state_key, unit.status) as state_key,
      unit.location_id,
      document.location_name,
      unit.advertised_price_minor,
      unit.currency_code::text,
      greatest(
        0,
        (
          current_date
          - coalesce(unit.acquisition_date, unit.created_at::date)
        )::integer
      ) as age_days,
      case when can_read_costs then metric.posted_cost_minor else null end as cost_minor,
      case when can_read_costs then metric.estimated_gross_minor else null end as gross_minor,
      unit.version,
      unit.updated_at,
      case
        when normalized_query is null then 0::real
        else pg_catalog.greatest(
          pg_catalog.ts_rank_cd(
            document.search_vector,
            pg_catalog.websearch_to_tsquery('simple'::regconfig, normalized_query)
          ),
          extensions.similarity(document.search_text, normalized_query)
        )::real
      end as rank
    from public.inventory_search_documents document
    join public.inventory_units unit
      on unit.workspace_id = document.workspace_id
     and unit.id = document.inventory_unit_id
    left join public.inventory_cost_metrics metric
      on metric.workspace_id = unit.workspace_id
     and metric.inventory_unit_id = unit.id
    where document.workspace_id = p_workspace_id
      and (
        normalized_query is null
        or document.search_vector @@ pg_catalog.websearch_to_tsquery(
          'simple'::regconfig,
          normalized_query
        )
        or document.search_text OPERATOR(extensions.%) normalized_query
        or pg_catalog.strpos(document.search_text, normalized_query) > 0
      )
      and (p_statuses is null or unit.status = any(p_statuses))
      and (p_location_ids is null or unit.location_id = any(p_location_ids))
      and (
        p_minimum_price_minor is null
        or unit.advertised_price_minor >= p_minimum_price_minor
      )
      and (
        p_maximum_price_minor is null
        or unit.advertised_price_minor <= p_maximum_price_minor
      )
  )
  select
    ranked.id,
    ranked.stock_number,
    ranked.vin,
    ranked.model_year,
    ranked.make,
    ranked.model,
    ranked.vehicle_trim,
    ranked.status,
    ranked.state_key,
    ranked.location_id,
    ranked.location_name,
    ranked.advertised_price_minor::text,
    ranked.currency_code,
    ranked.age_days,
    ranked.cost_minor::text,
    ranked.gross_minor::text,
    ranked.version,
    ranked.updated_at,
    ranked.rank
  from ranked
  where (p_minimum_days_in_stock is null or ranked.age_days >= p_minimum_days_in_stock)
    and (p_maximum_days_in_stock is null or ranked.age_days <= p_maximum_days_in_stock)
    and (
      p_before_rank is null
      or (ranked.rank, ranked.updated_at, ranked.id)
        < (p_before_rank, p_before_updated_at, p_before_id)
    )
  order by ranked.rank desc, ranked.updated_at desc, ranked.id desc
  limit p_page_size;
end;
$$;

alter table public.inventory_cost_category_definitions enable row level security;
alter table public.inventory_cost_category_definitions force row level security;
alter table public.inventory_cost_entries enable row level security;
alter table public.inventory_cost_entries force row level security;
alter table public.inventory_cost_metrics enable row level security;
alter table public.inventory_cost_metrics force row level security;
alter table public.inventory_search_documents enable row level security;
alter table public.inventory_search_documents force row level security;
alter table public.inventory_saved_views enable row level security;
alter table public.inventory_saved_views force row level security;
alter table public.inventory_saved_view_command_receipts enable row level security;
alter table public.inventory_saved_view_command_receipts force row level security;

create policy inventory_cost_categories_select on public.inventory_cost_category_definitions
for select to authenticated
using (
  app.has_permission(workspace_id, 'costs.read')
  or app.has_permission(workspace_id, 'costs.create')
);

create policy inventory_cost_entries_select on public.inventory_cost_entries
for select to authenticated
using (app.has_permission(workspace_id, 'costs.read'));

create policy inventory_cost_metrics_select on public.inventory_cost_metrics
for select to authenticated
using (app.has_permission(workspace_id, 'costs.read'));

create policy inventory_search_documents_select on public.inventory_search_documents
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));

create policy inventory_saved_views_select on public.inventory_saved_views
for select to authenticated
using (
  app.has_permission(workspace_id, 'inventory.read')
  and status = 'active'
  and (owner_user_id = auth.uid() or share_scope = 'workspace')
);

revoke all on public.inventory_cost_category_definitions from anon, authenticated;
revoke all on public.inventory_cost_entries from anon, authenticated;
revoke all on public.inventory_cost_entry_history from anon, authenticated;
revoke all on public.inventory_cost_metrics from anon, authenticated;
revoke all on public.inventory_search_documents from anon, authenticated;
revoke all on public.inventory_saved_views from anon, authenticated;
revoke all on public.inventory_saved_view_command_receipts from anon, authenticated;

grant select on public.inventory_cost_category_definitions to authenticated;
grant select on public.inventory_cost_entries to authenticated;
grant select on public.inventory_cost_entry_history to authenticated;
grant select on public.inventory_cost_metrics to authenticated;
grant select on public.inventory_search_documents to authenticated;
grant select on public.inventory_saved_views to authenticated;

revoke all on function app.prevent_cost_history_mutation()
from public, anon, authenticated;
revoke all on function app.protect_inventory_cost_category_definition()
from public, anon, authenticated;
revoke all on function app.refresh_inventory_cost_metric(uuid, uuid)
from public, anon, authenticated;
revoke all on function app.refresh_inventory_cost_metric_trigger()
from public, anon, authenticated;
revoke all on function app.refresh_inventory_price_metric_trigger()
from public, anon, authenticated;
revoke all on function app.refresh_inventory_search_document(uuid, uuid)
from public, anon, authenticated;
revoke all on function app.refresh_inventory_search_for_unit_trigger()
from public, anon, authenticated;
revoke all on function app.refresh_inventory_search_for_vehicle_trigger()
from public, anon, authenticated;
revoke all on function app.refresh_inventory_search_for_location_trigger()
from public, anon, authenticated;
revoke all on function app.inventory_saved_view_payload_valid(jsonb, jsonb, jsonb)
from public, anon, authenticated;

revoke all on function app.post_inventory_cost_entry(
  uuid, text, uuid, bigint, uuid, bigint, text, date, uuid, text, uuid, text, uuid
) from public, anon, authenticated;
revoke all on function app.reverse_inventory_cost_entry(
  uuid, text, uuid, bigint, date, text, text, uuid
) from public, anon, authenticated;
revoke all on function app.save_inventory_view(
  uuid, text, uuid, bigint, text, jsonb, jsonb, jsonb, text, text, text, text, uuid
) from public, anon, authenticated;
revoke all on function app.search_inventory_units(
  uuid, text, text[], uuid[], bigint, bigint, integer, integer, real, timestamptz, uuid, integer
) from public, anon, authenticated;

grant execute on function app.post_inventory_cost_entry(
  uuid, text, uuid, bigint, uuid, bigint, text, date, uuid, text, uuid, text, uuid
) to authenticated;
grant execute on function app.reverse_inventory_cost_entry(
  uuid, text, uuid, bigint, date, text, text, uuid
) to authenticated;
grant execute on function app.save_inventory_view(
  uuid, text, uuid, bigint, text, jsonb, jsonb, jsonb, text, text, text, text, uuid
) to authenticated;
grant execute on function app.search_inventory_units(
  uuid, text, text[], uuid[], bigint, bigint, integer, integer, real, timestamptz, uuid, integer
) to authenticated;

comment on table public.inventory_cost_entries is
  'Append-only integer-minor-unit cost ledger; corrections are linked reversal rows.';
comment on view public.inventory_cost_entry_history is
  'RLS-invoker cost history with effective status derived from immutable reversal links.';
comment on table public.inventory_search_documents is
  'Workspace-scoped materialized inventory search projection without restricted identifiers.';
comment on function app.search_inventory_units(
  uuid, text, text[], uuid[], bigint, bigint, integer, integer, real, timestamptz, uuid, integer
) is
  'Permission-aware bounded inventory search with deterministic rank/update/id cursor.';
