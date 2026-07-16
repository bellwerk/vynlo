-- VYN-INV-001, VYN-INV-002, VYN-NUM-001, VYN-CRM-001, VYN-DEAL-001,
-- VYN-DOC-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- M1-SLICE-AC-001 through M1-SLICE-AC-010
-- Forward-only minimal inventory -> party/deal draft -> preview foundation.

create table public.stock_number_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null
    check (key::text ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  version integer not null check (version > 0),
  prefix text not null default ''
    check (pg_catalog.char_length(prefix) <= 32),
  numeric_width smallint not null default 5
    check (numeric_width between 1 and 18),
  starting_value bigint not null default 1 check (starting_value > 0),
  increment_by bigint not null default 1 check (increment_by > 0),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key, version)
);

create unique index stock_number_definitions_active_key_uidx
  on public.stock_number_definitions (workspace_id, key)
  where status = 'active';

create table public.stock_number_counters (
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  definition_id uuid not null,
  next_sequence_value bigint not null check (next_sequence_value > 0),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  primary key (workspace_id, definition_id),
  foreign key (workspace_id, definition_id)
    references public.stock_number_definitions (workspace_id, id)
    on delete restrict
);

create table public.stock_number_allocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  definition_id uuid not null,
  inventory_unit_id uuid not null,
  sequence_value bigint not null check (sequence_value > 0),
  formatted_value extensions.citext not null
    check (pg_catalog.btrim(formatted_value::text) <> ''),
  idempotency_key text not null
    check (pg_catalog.char_length(idempotency_key) between 8 and 200),
  command_fingerprint text not null
    check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  allocated_by uuid not null references auth.users (id) on delete restrict,
  allocated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, formatted_value),
  unique (workspace_id, definition_id, sequence_value),
  unique (workspace_id, idempotency_key),
  foreign key (workspace_id, definition_id)
    references public.stock_number_definitions (workspace_id, id)
    on delete restrict
);

create table public.vehicles (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vin extensions.citext not null,
  model_year smallint check (model_year between 1886 and 2200),
  make text check (make is null or (
    pg_catalog.btrim(make) <> '' and pg_catalog.char_length(make) <= 100
  )),
  model text check (model is null or (
    pg_catalog.btrim(model) <> '' and pg_catalog.char_length(model) <= 100
  )),
  facts_version bigint not null default 1 check (facts_version > 0),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, vin),
  constraint vehicles_vin_syntax_check check (
    pg_catalog.upper(vin::text) ~ '^[A-HJ-NPR-Z0-9]{17}$'
  )
);

create index vehicles_workspace_model_idx
  on public.vehicles (workspace_id, model_year, make, model);

create table public.inventory_units (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vehicle_id uuid not null,
  stock_allocation_id uuid not null,
  stock_number extensions.citext not null
    check (pg_catalog.btrim(stock_number::text) <> ''),
  status text not null default 'active'
    check (status in ('draft', 'active', 'closed', 'archived')),
  acquisition_date date,
  odometer_value bigint check (odometer_value is null or odometer_value >= 0),
  odometer_unit text check (odometer_unit is null or odometer_unit in ('km', 'mi')),
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
  advertised_price_minor bigint
    check (advertised_price_minor is null or advertised_price_minor >= 0),
  public_notes text check (
    public_notes is null or pg_catalog.char_length(public_notes) <= 4000
  ),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, stock_number),
  unique (workspace_id, stock_allocation_id),
  foreign key (workspace_id, vehicle_id)
    references public.vehicles (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, stock_allocation_id)
    references public.stock_number_allocations (workspace_id, id)
    on delete restrict
    deferrable initially deferred
);

alter table public.stock_number_allocations
  add constraint stock_number_allocations_inventory_unit_fk
  foreign key (workspace_id, inventory_unit_id)
  references public.inventory_units (workspace_id, id)
  on delete restrict
  deferrable initially deferred;

create unique index inventory_units_active_vehicle_uidx
  on public.inventory_units (workspace_id, vehicle_id)
  where status in ('draft', 'active');
create index inventory_units_workspace_status_idx
  on public.inventory_units (workspace_id, status, created_at desc);

create table public.parties (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  party_type text not null check (party_type in ('person', 'organization')),
  display_name text not null check (
    pg_catalog.btrim(display_name) <> ''
    and pg_catalog.char_length(display_name) <= 200
  ),
  status text not null default 'active' check (status in ('active', 'archived')),
  version bigint not null default 1 check (version > 0),
  idempotency_key text not null
    check (pg_catalog.char_length(idempotency_key) between 8 and 200),
  command_fingerprint text not null
    check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, idempotency_key)
);

create index parties_workspace_name_idx
  on public.parties (workspace_id, pg_catalog.lower(display_name), status);

create table public.deals (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  deal_type_key text not null
    check (deal_type_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  status text not null default 'draft' check (status in ('draft', 'cancelled')),
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
  owner_membership_id uuid not null,
  notes text check (notes is null or pg_catalog.char_length(notes) <= 4000),
  version bigint not null default 1 check (version > 0),
  idempotency_key text not null
    check (pg_catalog.char_length(idempotency_key) between 8 and 200),
  command_fingerprint text not null
    check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, idempotency_key),
  foreign key (workspace_id, owner_membership_id)
    references public.workspace_memberships (workspace_id, id)
    on delete restrict
);

create index deals_workspace_status_idx
  on public.deals (workspace_id, status, created_at desc);

create table public.deal_participants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  deal_id uuid not null,
  party_id uuid not null,
  role_key text not null
    check (role_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  is_primary boolean not null default true,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, deal_id, party_id, role_key),
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict
);

create table public.deal_inventory_units (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  deal_id uuid not null,
  inventory_unit_id uuid not null,
  role_key text not null
    check (role_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  status text not null default 'active' check (status in ('active', 'released')),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, deal_id, inventory_unit_id, role_key),
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id) on delete restrict
);

create unique index deal_inventory_units_active_sold_uidx
  on public.deal_inventory_units (workspace_id, inventory_unit_id)
  where role_key = 'sold' and status = 'active';

create table public.document_types (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null
    check (key::text ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  version integer not null check (version > 0),
  display_name text not null check (
    pg_catalog.btrim(display_name) <> ''
    and pg_catalog.char_length(display_name) <= 200
  ),
  field_schema jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(field_schema) = 'object'),
  official_generation_enabled boolean not null default false
    check (not official_generation_enabled),
  status text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key, version)
);

create table public.document_template_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_type_id uuid not null,
  version integer not null check (version > 0),
  locale text not null
    check (locale ~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'),
  template_class text not null default 'synthetic_non_production'
    check (template_class = 'synthetic_non_production'),
  source_html text not null check (
    pg_catalog.btrim(source_html) <> ''
    and pg_catalog.strpos(pg_catalog.lower(source_html), '<script') = 0
    and pg_catalog.strpos(pg_catalog.lower(source_html), 'javascript:') = 0
  ),
  source_checksum text not null check (source_checksum ~ '^[a-f0-9]{64}$'),
  renderer_version text not null check (pg_catalog.btrim(renderer_version) <> ''),
  field_schema jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(field_schema) = 'object'),
  production_approved boolean not null default false check (not production_approved),
  watermark text not null default 'DRAFT / NON-PRODUCTION'
    check (watermark = 'DRAFT / NON-PRODUCTION'),
  status text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, document_type_id, version, locale),
  foreign key (workspace_id, document_type_id)
    references public.document_types (workspace_id, id) on delete restrict
);

create table public.documents (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_type_id uuid not null,
  template_version_id uuid not null,
  deal_id uuid not null,
  mode text not null default 'preview' check (mode = 'preview'),
  official_number text check (official_number is null),
  status text not null default 'queued'
    check (status in ('queued', 'generated', 'failed')),
  locale text not null
    check (locale ~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'),
  watermark text not null default 'DRAFT / NON-PRODUCTION'
    check (watermark = 'DRAFT / NON-PRODUCTION'),
  render_input_snapshot jsonb not null
    check (pg_catalog.jsonb_typeof(render_input_snapshot) = 'object'),
  render_input_checksum text not null check (render_input_checksum ~ '^[a-f0-9]{64}$'),
  generated_checksum text
    check (generated_checksum is null or generated_checksum ~ '^[a-f0-9]{64}$'),
  failure_code text check (
    failure_code is null or (
      pg_catalog.btrim(failure_code) <> ''
      and pg_catalog.char_length(failure_code) <= 100
    )
  ),
  idempotency_key text not null
    check (pg_catalog.char_length(idempotency_key) between 8 and 200),
  command_fingerprint text not null
    check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, idempotency_key),
  foreign key (workspace_id, document_type_id)
    references public.document_types (workspace_id, id) on delete restrict,
  foreign key (workspace_id, template_version_id)
    references public.document_template_versions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  constraint documents_preview_state_check check (
    (status = 'queued' and generated_checksum is null and failure_code is null)
    or (status = 'generated' and generated_checksum is not null and failure_code is null)
    or (status = 'failed' and generated_checksum is null and failure_code is not null)
  )
);

create index documents_workspace_status_idx
  on public.documents (workspace_id, status, created_at desc);
create index documents_workspace_deal_idx
  on public.documents (workspace_id, deal_id, created_at desc);

create function app.vertical_slice_fingerprint(payload jsonb)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(payload::text, 'sha256'),
    'hex'
  );
$$;

create function app.require_vertical_slice_permission(
  target_workspace_id uuid,
  permission_key text,
  require_recent_step_up boolean default false
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
      message = 'active workspace membership and permission are required';
  end if;

  if require_recent_step_up and not app.has_recent_strong_auth() then
    raise exception using
      errcode = '42501',
      message = 'recent strong authentication is required';
  end if;

  return actor_user_id;
end;
$$;

create function app.guard_preview_document_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status <> 'queued' or new.status not in ('generated', 'failed') then
    raise exception using
      errcode = '55000',
      message = 'preview documents only transition once from queued to generated or failed';
  end if;
  return new;
end;
$$;

create function app.create_inventory_unit(
  p_workspace_id uuid,
  p_stock_definition_id uuid,
  p_idempotency_key text,
  p_vin text,
  p_model_year integer,
  p_make text,
  p_model text,
  p_acquisition_date date,
  p_odometer_value bigint,
  p_odometer_unit text,
  p_currency_code text,
  p_advertised_price_minor bigint,
  p_public_notes text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_vin text;
  normalized_make text;
  normalized_model text;
  normalized_currency text;
  normalized_public_notes text;
  request_fingerprint text;
  existing_fingerprint text;
  existing_inventory_unit_id uuid;
  existing_vehicle_id uuid;
  existing_stock_number text;
  existing_vehicle public.vehicles%rowtype;
  definition_prefix text;
  definition_width smallint;
  definition_increment bigint;
  allocated_sequence_value bigint;
  allocated_stock_number text;
  new_inventory_unit_id uuid;
  new_vehicle_id uuid;
  new_allocation_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.create'
  );

  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_vin := pg_catalog.upper(pg_catalog.btrim(coalesce(p_vin, '')));
  normalized_make := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_make, '')), '');
  normalized_model := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_model, '')), '');
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_public_notes := pg_catalog.nullif(
    pg_catalog.btrim(coalesce(p_public_notes, '')),
    ''
  );

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid inventory idempotency key';
  end if;
  if normalized_vin !~ '^[A-HJ-NPR-Z0-9]{17}$' then
    raise exception using errcode = '22023', message = 'VIN must contain 17 valid typed or pasted characters';
  end if;
  if p_model_year is not null and p_model_year not between 1886 and 2200 then
    raise exception using errcode = '22023', message = 'invalid vehicle model year';
  end if;
  if normalized_make is not null and pg_catalog.char_length(normalized_make) > 100
    or normalized_model is not null and pg_catalog.char_length(normalized_model) > 100 then
    raise exception using errcode = '22023', message = 'vehicle make or model is too long';
  end if;
  if p_odometer_value is not null and p_odometer_value < 0
    or p_odometer_value is not null and p_odometer_unit not in ('km', 'mi')
    or p_odometer_value is null and p_odometer_unit is not null then
    raise exception using errcode = '22023', message = 'invalid odometer value or unit';
  end if;
  if normalized_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'currency must be an ISO-style three-letter code';
  end if;
  if p_advertised_price_minor is not null and p_advertised_price_minor < 0 then
    raise exception using errcode = '22023', message = 'advertised price minor units cannot be negative';
  end if;
  if normalized_public_notes is not null
    and pg_catalog.char_length(normalized_public_notes) > 4000 then
    raise exception using errcode = '22023', message = 'public notes are too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'stock_definition_id', p_stock_definition_id,
      'vin', normalized_vin,
      'model_year', p_model_year,
      'make', normalized_make,
      'model', normalized_model,
      'acquisition_date', p_acquisition_date,
      'odometer_value', p_odometer_value,
      'odometer_unit', p_odometer_unit,
      'currency_code', normalized_currency,
      'advertised_price_minor', p_advertised_price_minor,
      'public_notes', normalized_public_notes
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fcreate_inventory\x1f' || normalized_idempotency_key,
      0
    )
  );

  select
    iu.id,
    iu.vehicle_id,
    iu.stock_number::text,
    allocation.command_fingerprint
    into
      existing_inventory_unit_id,
      existing_vehicle_id,
      existing_stock_number,
      existing_fingerprint
  from public.stock_number_allocations allocation
  join public.inventory_units iu
    on iu.workspace_id = allocation.workspace_id
   and iu.id = allocation.inventory_unit_id
  where allocation.workspace_id = p_workspace_id
    and allocation.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'inventory idempotency key was used for a different request';
    end if;
    return query
    select
      existing_inventory_unit_id,
      existing_vehicle_id,
      existing_stock_number,
      true;
    return;
  end if;

  select
    definition.prefix,
    definition.numeric_width,
    definition.increment_by,
    counter.next_sequence_value
    into
      definition_prefix,
      definition_width,
      definition_increment,
      allocated_sequence_value
  from public.stock_number_definitions definition
  join public.stock_number_counters counter
    on counter.workspace_id = definition.workspace_id
   and counter.definition_id = definition.id
  where definition.workspace_id = p_workspace_id
    and definition.id = p_stock_definition_id
    and definition.status = 'active'
  for update of counter;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'an active stock definition and counter are required in the workspace';
  end if;

  allocated_stock_number := definition_prefix || pg_catalog.lpad(
    allocated_sequence_value::text,
    definition_width,
    '0'
  );

  select vehicle.*
    into existing_vehicle
  from public.vehicles vehicle
  where vehicle.workspace_id = p_workspace_id
    and vehicle.vin = normalized_vin
  for update;

  if found then
    if (p_model_year is not null and existing_vehicle.model_year is not null
        and p_model_year is distinct from existing_vehicle.model_year)
      or (normalized_make is not null and existing_vehicle.make is not null
        and pg_catalog.lower(normalized_make) <> pg_catalog.lower(existing_vehicle.make))
      or (normalized_model is not null and existing_vehicle.model is not null
        and pg_catalog.lower(normalized_model) <> pg_catalog.lower(existing_vehicle.model)) then
      raise exception using
        errcode = '23514',
        message = 'duplicate VIN facts require controlled review';
    end if;
    new_vehicle_id := existing_vehicle.id;
  else
    new_vehicle_id := pg_catalog.gen_random_uuid();
    insert into public.vehicles (
      id,
      workspace_id,
      vin,
      model_year,
      make,
      model
    ) values (
      new_vehicle_id,
      p_workspace_id,
      normalized_vin,
      p_model_year,
      normalized_make,
      normalized_model
    );
  end if;

  new_inventory_unit_id := pg_catalog.gen_random_uuid();
  new_allocation_id := pg_catalog.gen_random_uuid();

  insert into public.stock_number_allocations (
    id,
    workspace_id,
    definition_id,
    inventory_unit_id,
    sequence_value,
    formatted_value,
    idempotency_key,
    command_fingerprint,
    allocated_by
  ) values (
    new_allocation_id,
    p_workspace_id,
    p_stock_definition_id,
    new_inventory_unit_id,
    allocated_sequence_value,
    allocated_stock_number,
    normalized_idempotency_key,
    request_fingerprint,
    actor_user_id
  );

  insert into public.inventory_units (
    id,
    workspace_id,
    vehicle_id,
    stock_allocation_id,
    stock_number,
    status,
    acquisition_date,
    odometer_value,
    odometer_unit,
    currency_code,
    advertised_price_minor,
    public_notes,
    created_by
  ) values (
    new_inventory_unit_id,
    p_workspace_id,
    new_vehicle_id,
    new_allocation_id,
    allocated_stock_number,
    'active',
    p_acquisition_date,
    p_odometer_value,
    p_odometer_unit,
    normalized_currency,
    p_advertised_price_minor,
    normalized_public_notes,
    actor_user_id
  );

  update public.stock_number_counters
  set next_sequence_value = allocated_sequence_value + definition_increment,
      updated_at = pg_catalog.statement_timestamp()
  where workspace_id = p_workspace_id
    and definition_id = p_stock_definition_id;

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_unit.created',
    p_entity_type => 'inventory_unit',
    p_entity_id => new_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'vehicle_id', new_vehicle_id,
      'stock_number', allocated_stock_number,
      'status', 'active'
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'stock_allocation_id', new_allocation_id,
      'idempotency_key', normalized_idempotency_key
    )
  );

  return query
  select new_inventory_unit_id, new_vehicle_id, allocated_stock_number, false;
end;
$$;

create function app.create_party(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_type text,
  p_display_name text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (party_id uuid, replayed boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_display_name text;
  request_fingerprint text;
  existing_party_id uuid;
  existing_fingerprint text;
  new_party_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(p_workspace_id, 'crm.create');
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_display_name := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_display_name, '')),
    '\s+',
    ' ',
    'g'
  );

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid party idempotency key';
  end if;
  if p_party_type not in ('person', 'organization') then
    raise exception using errcode = '22023', message = 'invalid party type';
  end if;
  if normalized_display_name = '' or pg_catalog.char_length(normalized_display_name) > 200 then
    raise exception using errcode = '22023', message = 'invalid party display name';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'party_type', p_party_type,
      'display_name', normalized_display_name
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fcreate_party\x1f' || normalized_idempotency_key,
      0
    )
  );

  select party.id, party.command_fingerprint
    into existing_party_id, existing_fingerprint
  from public.parties party
  where party.workspace_id = p_workspace_id
    and party.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'party idempotency key was used for a different request';
    end if;
    return query select existing_party_id, true;
    return;
  end if;

  new_party_id := pg_catalog.gen_random_uuid();
  insert into public.parties (
    id,
    workspace_id,
    party_type,
    display_name,
    idempotency_key,
    command_fingerprint,
    created_by
  ) values (
    new_party_id,
    p_workspace_id,
    p_party_type,
    normalized_display_name,
    normalized_idempotency_key,
    request_fingerprint,
    actor_user_id
  );

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'party.created',
    p_entity_type => 'party',
    p_entity_id => new_party_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'party_type', p_party_type,
      'display_name', normalized_display_name,
      'status', 'active'
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );

  return query select new_party_id, false;
end;
$$;

create function app.create_deal_draft(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_type_key text,
  p_currency_code text,
  p_party_id uuid,
  p_participant_role_key text,
  p_inventory_unit_id uuid,
  p_inventory_role_key text,
  p_notes text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  deal_id uuid,
  participant_id uuid,
  inventory_link_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  actor_membership_id uuid;
  normalized_idempotency_key text;
  normalized_deal_type_key text;
  normalized_currency text;
  normalized_participant_role_key text;
  normalized_inventory_role_key text;
  normalized_notes text;
  inventory_currency text;
  request_fingerprint text;
  existing_fingerprint text;
  existing_deal_id uuid;
  existing_participant_id uuid;
  existing_inventory_link_id uuid;
  new_deal_id uuid;
  new_participant_id uuid;
  new_inventory_link_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(p_workspace_id, 'deals.create');
  perform app.require_vertical_slice_permission(p_workspace_id, 'crm.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');

  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_deal_type_key := pg_catalog.lower(pg_catalog.btrim(coalesce(p_deal_type_key, '')));
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_participant_role_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_participant_role_key, ''))
  );
  normalized_inventory_role_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_inventory_role_key, ''))
  );
  normalized_notes := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_notes, '')), '');

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid deal idempotency key';
  end if;
  if normalized_deal_type_key !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$' then
    raise exception using errcode = '22023', message = 'invalid deal type key';
  end if;
  if normalized_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'invalid deal currency';
  end if;
  if normalized_participant_role_key !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or normalized_inventory_role_key !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$' then
    raise exception using errcode = '22023', message = 'invalid deal relationship role key';
  end if;
  if normalized_notes is not null and pg_catalog.char_length(normalized_notes) > 4000 then
    raise exception using errcode = '22023', message = 'deal notes are too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  select membership.id
    into actor_membership_id
  from public.workspace_memberships membership
  where membership.workspace_id = p_workspace_id
    and membership.user_id = actor_user_id
    and membership.status = 'active';

  if actor_membership_id is null then
    raise exception using errcode = '42501', message = 'active owner membership is required';
  end if;

  if not exists (
    select 1
    from public.parties party
    where party.workspace_id = p_workspace_id
      and party.id = p_party_id
      and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active participant party must belong to the workspace';
  end if;

  select inventory.currency_code::text
    into inventory_currency
  from public.inventory_units inventory
  where inventory.workspace_id = p_workspace_id
    and inventory.id = p_inventory_unit_id
    and inventory.status = 'active'
  for update;

  if inventory_currency is null then
    raise exception using errcode = '23514', message = 'active inventory unit must belong to the workspace';
  end if;
  if inventory_currency <> normalized_currency then
    raise exception using
      errcode = '23514',
      message = 'deal and inventory currency must match without an explicit conversion';
  end if;
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'deal_type_key', normalized_deal_type_key,
      'currency_code', normalized_currency,
      'party_id', p_party_id,
      'participant_role_key', normalized_participant_role_key,
      'inventory_unit_id', p_inventory_unit_id,
      'inventory_role_key', normalized_inventory_role_key,
      'notes', normalized_notes
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fcreate_deal\x1f' || normalized_idempotency_key,
      0
    )
  );

  select deal.id, deal.command_fingerprint
    into existing_deal_id, existing_fingerprint
  from public.deals deal
  where deal.workspace_id = p_workspace_id
    and deal.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'deal idempotency key was used for a different request';
    end if;

    select participant.id
      into existing_participant_id
    from public.deal_participants participant
    where participant.workspace_id = p_workspace_id
      and participant.deal_id = existing_deal_id
      and participant.party_id = p_party_id
      and participant.role_key = normalized_participant_role_key;

    select inventory_link.id
      into existing_inventory_link_id
    from public.deal_inventory_units inventory_link
    where inventory_link.workspace_id = p_workspace_id
      and inventory_link.deal_id = existing_deal_id
      and inventory_link.inventory_unit_id = p_inventory_unit_id
      and inventory_link.role_key = normalized_inventory_role_key;

    if existing_participant_id is null or existing_inventory_link_id is null then
      raise exception using
        errcode = '55000',
        message = 'idempotent deal draft is missing its required relationships';
    end if;

    return query
    select
      existing_deal_id,
      existing_participant_id,
      existing_inventory_link_id,
      true;
    return;
  end if;

  if normalized_inventory_role_key = 'sold' and exists (
    select 1
    from public.deal_inventory_units inventory_link
    where inventory_link.workspace_id = p_workspace_id
      and inventory_link.inventory_unit_id = p_inventory_unit_id
      and inventory_link.role_key = 'sold'
      and inventory_link.status = 'active'
  ) then
    raise exception using
      errcode = '23505',
      message = 'active sold inventory unit is already linked to a deal';
  end if;

  new_deal_id := pg_catalog.gen_random_uuid();
  new_participant_id := pg_catalog.gen_random_uuid();
  new_inventory_link_id := pg_catalog.gen_random_uuid();

  insert into public.deals (
    id,
    workspace_id,
    deal_type_key,
    status,
    currency_code,
    owner_membership_id,
    notes,
    idempotency_key,
    command_fingerprint,
    created_by
  ) values (
    new_deal_id,
    p_workspace_id,
    normalized_deal_type_key,
    'draft',
    normalized_currency,
    actor_membership_id,
    normalized_notes,
    normalized_idempotency_key,
    request_fingerprint,
    actor_user_id
  );

  insert into public.deal_participants (
    id,
    workspace_id,
    deal_id,
    party_id,
    role_key,
    is_primary
  ) values (
    new_participant_id,
    p_workspace_id,
    new_deal_id,
    p_party_id,
    normalized_participant_role_key,
    true
  );

  insert into public.deal_inventory_units (
    id,
    workspace_id,
    deal_id,
    inventory_unit_id,
    role_key,
    status
  ) values (
    new_inventory_link_id,
    p_workspace_id,
    new_deal_id,
    p_inventory_unit_id,
    normalized_inventory_role_key,
    'active'
  );

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.created',
    p_entity_type => 'deal',
    p_entity_id => new_deal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'draft',
      'deal_type_key', normalized_deal_type_key,
      'party_id', p_party_id,
      'participant_role_key', normalized_participant_role_key,
      'inventory_unit_id', p_inventory_unit_id,
      'inventory_role_key', normalized_inventory_role_key
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key,
      'owner_membership_id', actor_membership_id
    )
  );

  return query
  select new_deal_id, new_participant_id, new_inventory_link_id, false;
end;
$$;

create function app.request_document_preview(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_template_version_id uuid,
  p_locale text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_id uuid,
  preview_status text,
  watermark text,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_locale text;
  request_fingerprint text;
  existing_document_id uuid;
  existing_status text;
  existing_watermark text;
  existing_fingerprint text;
  preview_document_type_id uuid;
  preview_template_locale text;
  preview_snapshot jsonb;
  preview_snapshot_checksum text;
  new_document_id uuid;
  deal_record public.deals%rowtype;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'documents.preview'
  );
  perform app.require_vertical_slice_permission(p_workspace_id, 'deals.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'crm.read');
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');

  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_locale := pg_catalog.btrim(coalesce(p_locale, ''));

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid preview idempotency key';
  end if;
  if normalized_locale !~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$' then
    raise exception using errcode = '22023', message = 'invalid preview locale';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'deal_id', p_deal_id,
      'template_version_id', p_template_version_id,
      'locale', normalized_locale
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fpreview_document\x1f' || normalized_idempotency_key,
      0
    )
  );

  select
    document.id,
    document.status,
    document.watermark,
    document.command_fingerprint
    into
      existing_document_id,
      existing_status,
      existing_watermark,
      existing_fingerprint
  from public.documents document
  where document.workspace_id = p_workspace_id
    and document.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'preview idempotency key was used for a different request';
    end if;
    return query
    select existing_document_id, existing_status, existing_watermark, true;
    return;
  end if;

  select deal.*
    into deal_record
  from public.deals deal
  where deal.workspace_id = p_workspace_id
    and deal.id = p_deal_id
    and deal.status = 'draft';

  if not found then
    raise exception using errcode = '23514', message = 'draft deal must belong to the workspace';
  end if;

  select template.document_type_id, template.locale
    into preview_document_type_id, preview_template_locale
  from public.document_template_versions template
  join public.document_types document_type
    on document_type.workspace_id = template.workspace_id
   and document_type.id = template.document_type_id
  where template.workspace_id = p_workspace_id
    and template.id = p_template_version_id
    and template.status = 'active'
    and template.template_class = 'synthetic_non_production'
    and not template.production_approved
    and template.watermark = 'DRAFT / NON-PRODUCTION'
    and document_type.status = 'active'
    and not document_type.official_generation_enabled;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'active synthetic non-production template must belong to the workspace';
  end if;
  if preview_template_locale <> normalized_locale then
    raise exception using errcode = '23514', message = 'preview locale must match the template version';
  end if;

  preview_snapshot := pg_catalog.jsonb_build_object(
    'schema_version', 1,
    'deal', pg_catalog.jsonb_build_object(
      'id', deal_record.id,
      'deal_type_key', deal_record.deal_type_key,
      'status', deal_record.status,
      'currency_code', deal_record.currency_code,
      'version', deal_record.version
    ),
    'participants', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'party_id', party.id,
          'party_type', party.party_type,
          'display_name', party.display_name,
          'role_key', participant.role_key,
          'is_primary', participant.is_primary
        ) order by participant.id
      )
      from public.deal_participants participant
      join public.parties party
        on party.workspace_id = participant.workspace_id
       and party.id = participant.party_id
      where participant.workspace_id = p_workspace_id
        and participant.deal_id = p_deal_id
    ), '[]'::jsonb),
    'inventory_units', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'inventory_unit_id', inventory.id,
          'vehicle_id', vehicle.id,
          'vin', vehicle.vin::text,
          'stock_number', inventory.stock_number::text,
          'currency_code', inventory.currency_code,
          'advertised_price_minor', inventory.advertised_price_minor,
          'role_key', inventory_link.role_key
        ) order by inventory_link.id
      )
      from public.deal_inventory_units inventory_link
      join public.inventory_units inventory
        on inventory.workspace_id = inventory_link.workspace_id
       and inventory.id = inventory_link.inventory_unit_id
      join public.vehicles vehicle
        on vehicle.workspace_id = inventory.workspace_id
       and vehicle.id = inventory.vehicle_id
      where inventory_link.workspace_id = p_workspace_id
        and inventory_link.deal_id = p_deal_id
        and inventory_link.status = 'active'
    ), '[]'::jsonb)
  );
  preview_snapshot_checksum := app.vertical_slice_fingerprint(preview_snapshot);
  new_document_id := pg_catalog.gen_random_uuid();

  insert into public.documents (
    id,
    workspace_id,
    document_type_id,
    template_version_id,
    deal_id,
    mode,
    official_number,
    status,
    locale,
    watermark,
    render_input_snapshot,
    render_input_checksum,
    idempotency_key,
    command_fingerprint,
    created_by
  ) values (
    new_document_id,
    p_workspace_id,
    preview_document_type_id,
    p_template_version_id,
    p_deal_id,
    'preview',
    null,
    'queued',
    normalized_locale,
    'DRAFT / NON-PRODUCTION',
    preview_snapshot,
    preview_snapshot_checksum,
    normalized_idempotency_key,
    request_fingerprint,
    actor_user_id
  );

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.preview_requested',
    p_entity_type => 'document',
    p_entity_id => new_document_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'deal_id', p_deal_id,
      'template_version_id', p_template_version_id,
      'status', 'queued',
      'mode', 'preview',
      'watermark', 'DRAFT / NON-PRODUCTION',
      'official_number', null
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key,
      'render_input_checksum', preview_snapshot_checksum,
      'outbox_enqueue_deferred', true
    )
  );

  return query
  select new_document_id, 'queued'::text, 'DRAFT / NON-PRODUCTION'::text, false;
end;
$$;

create function app.complete_document_preview(
  p_workspace_id uuid,
  p_document_id uuid,
  p_succeeded boolean,
  p_generated_checksum text,
  p_failure_code text,
  p_request_id text,
  p_correlation_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_document public.documents%rowtype;
  normalized_checksum text;
  normalized_failure_code text;
  next_status text;
begin
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  normalized_checksum := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_generated_checksum, ''))
  );
  normalized_failure_code := pg_catalog.btrim(coalesce(p_failure_code, ''));

  if p_succeeded and normalized_checksum !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'generated preview checksum is required';
  end if;
  if not p_succeeded and (
    normalized_failure_code = '' or pg_catalog.char_length(normalized_failure_code) > 100
  ) then
    raise exception using errcode = '22023', message = 'safe preview failure code is required';
  end if;

  select document.*
    into existing_document
  from public.documents document
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'preview document must belong to the workspace';
  end if;

  if p_succeeded
    and existing_document.status = 'generated'
    and existing_document.generated_checksum = normalized_checksum then
    return 'generated';
  end if;
  if not p_succeeded
    and existing_document.status = 'failed'
    and existing_document.failure_code = normalized_failure_code then
    return 'failed';
  end if;
  if existing_document.status <> 'queued' then
    raise exception using
      errcode = '55000',
      message = 'terminal preview result cannot be replaced';
  end if;

  next_status := case when p_succeeded then 'generated' else 'failed' end;
  update public.documents
  set status = next_status,
      generated_checksum = case when p_succeeded then normalized_checksum else null end,
      failure_code = case when p_succeeded then null else normalized_failure_code end,
      updated_at = pg_catalog.statement_timestamp()
  where workspace_id = p_workspace_id
    and id = p_document_id;

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => case
      when p_succeeded then 'document.preview_generated'
      else 'document.preview_failed'
    end,
    p_entity_type => 'document',
    p_entity_id => p_document_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object('status', existing_document.status),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', next_status,
      'generated_checksum', case when p_succeeded then normalized_checksum else null end,
      'failure_code', case when p_succeeded then null else normalized_failure_code end
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => '{"source":"preview_worker_contract"}'::jsonb
  );

  return next_status;
end;
$$;

create trigger vehicles_updated_at
before update on public.vehicles
for each row execute function app.set_updated_at();
create trigger inventory_units_updated_at
before update on public.inventory_units
for each row execute function app.set_updated_at();
create trigger parties_updated_at
before update on public.parties
for each row execute function app.set_updated_at();
create trigger deals_updated_at
before update on public.deals
for each row execute function app.set_updated_at();
create trigger documents_updated_at
before update on public.documents
for each row execute function app.set_updated_at();

create trigger stock_number_definitions_immutable
before update on public.stock_number_definitions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'version', 'prefix', 'numeric_width',
  'starting_value', 'increment_by', 'checksum', 'created_at'
);
create trigger stock_number_counters_immutable
before update on public.stock_number_counters
for each row execute function app.enforce_immutable_columns(
  'workspace_id', 'definition_id'
);
create trigger stock_number_allocations_immutable
before update on public.stock_number_allocations
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'definition_id', 'inventory_unit_id',
  'sequence_value', 'formatted_value', 'idempotency_key',
  'command_fingerprint', 'allocated_by', 'allocated_at'
);
create trigger vehicles_immutable
before update on public.vehicles
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'vin', 'created_at'
);
create trigger inventory_units_immutable
before update on public.inventory_units
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'vehicle_id', 'stock_allocation_id',
  'stock_number', 'created_by', 'created_at'
);
create trigger parties_immutable
before update on public.parties
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'party_type', 'idempotency_key',
  'command_fingerprint', 'created_by', 'created_at'
);
create trigger deals_immutable
before update on public.deals
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'deal_type_key', 'currency_code',
  'owner_membership_id', 'idempotency_key', 'command_fingerprint',
  'created_by', 'created_at'
);
create trigger deal_participants_immutable
before update on public.deal_participants
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'deal_id', 'party_id', 'role_key', 'created_at'
);
create trigger deal_inventory_units_immutable
before update on public.deal_inventory_units
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'deal_id', 'inventory_unit_id', 'role_key', 'created_at'
);
create trigger document_types_immutable
before update on public.document_types
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'version', 'field_schema',
  'official_generation_enabled', 'created_at'
);
create trigger document_template_versions_immutable
before update on public.document_template_versions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'document_type_id', 'version', 'locale',
  'template_class', 'source_html', 'source_checksum', 'renderer_version',
  'field_schema', 'production_approved', 'watermark', 'created_at'
);
create trigger documents_immutable
before update on public.documents
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'document_type_id', 'template_version_id',
  'deal_id', 'mode', 'official_number', 'locale', 'watermark',
  'render_input_snapshot', 'render_input_checksum', 'idempotency_key',
  'command_fingerprint', 'created_by', 'created_at'
);
create trigger documents_lifecycle_guard
before update on public.documents
for each row execute function app.guard_preview_document_update();

alter table public.stock_number_definitions enable row level security;
alter table public.stock_number_definitions force row level security;
alter table public.stock_number_counters enable row level security;
alter table public.stock_number_counters force row level security;
alter table public.stock_number_allocations enable row level security;
alter table public.stock_number_allocations force row level security;
alter table public.vehicles enable row level security;
alter table public.vehicles force row level security;
alter table public.inventory_units enable row level security;
alter table public.inventory_units force row level security;
alter table public.parties enable row level security;
alter table public.parties force row level security;
alter table public.deals enable row level security;
alter table public.deals force row level security;
alter table public.deal_participants enable row level security;
alter table public.deal_participants force row level security;
alter table public.deal_inventory_units enable row level security;
alter table public.deal_inventory_units force row level security;
alter table public.document_types enable row level security;
alter table public.document_types force row level security;
alter table public.document_template_versions enable row level security;
alter table public.document_template_versions force row level security;
alter table public.documents enable row level security;
alter table public.documents force row level security;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'stock_number_definitions',
    'stock_number_counters',
    'stock_number_allocations',
    'vehicles',
    'inventory_units',
    'parties',
    'deals',
    'deal_participants',
    'deal_inventory_units',
    'document_types',
    'document_template_versions',
    'documents'
  ] loop
    execute pg_catalog.format(
      'create trigger %I before delete on public.%I for each row execute function app.prevent_hard_delete()',
      table_name || '_prevent_hard_delete',
      table_name
    );
  end loop;
end;
$$;

create policy stock_number_definitions_select
on public.stock_number_definitions
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));
create policy stock_number_counters_select
on public.stock_number_counters
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));
create policy stock_number_allocations_select
on public.stock_number_allocations
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));
create policy vehicles_select
on public.vehicles
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));
create policy inventory_units_select
on public.inventory_units
for select to authenticated
using (app.has_permission(workspace_id, 'inventory.read'));

create policy parties_select
on public.parties
for select to authenticated
using (app.has_permission(workspace_id, 'crm.read'));

create policy deals_select
on public.deals
for select to authenticated
using (app.has_permission(workspace_id, 'deals.read'));
create policy deal_participants_select
on public.deal_participants
for select to authenticated
using (app.has_permission(workspace_id, 'deals.read'));
create policy deal_inventory_units_select
on public.deal_inventory_units
for select to authenticated
using (app.has_permission(workspace_id, 'deals.read'));

create policy document_types_select
on public.document_types
for select to authenticated
using (
  app.has_permission(workspace_id, 'documents.read')
  or app.has_permission(workspace_id, 'documents.preview')
);
create policy document_template_versions_select
on public.document_template_versions
for select to authenticated
using (
  app.has_permission(workspace_id, 'documents.read')
  or app.has_permission(workspace_id, 'documents.preview')
);
create policy documents_select
on public.documents
for select to authenticated
using (
  app.has_permission(workspace_id, 'documents.read')
  or (
    created_by = app.current_user_id()
    and app.has_permission(workspace_id, 'documents.preview')
  )
);

revoke all on table
  public.stock_number_definitions,
  public.stock_number_counters,
  public.stock_number_allocations,
  public.vehicles,
  public.inventory_units,
  public.parties,
  public.deals,
  public.deal_participants,
  public.deal_inventory_units,
  public.document_types,
  public.document_template_versions,
  public.documents
from public, anon, authenticated, service_role;

grant select on
  public.stock_number_definitions,
  public.stock_number_counters,
  public.stock_number_allocations,
  public.vehicles,
  public.inventory_units,
  public.parties,
  public.deals,
  public.deal_participants,
  public.deal_inventory_units,
  public.document_types,
  public.document_template_versions,
  public.documents
to authenticated, service_role;

revoke all on function app.vertical_slice_fingerprint(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.require_vertical_slice_permission(uuid, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function app.guard_preview_document_update()
  from public, anon, authenticated, service_role;
revoke all on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.create_party(uuid, text, text, text, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.create_deal_draft(
  uuid, text, text, text, uuid, text, uuid, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.request_document_preview(
  uuid, text, uuid, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.complete_document_preview(
  uuid, uuid, boolean, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) to authenticated;
grant execute on function app.create_party(uuid, text, text, text, text, uuid)
  to authenticated;
grant execute on function app.create_deal_draft(
  uuid, text, text, text, uuid, text, uuid, text, text, text, uuid
) to authenticated;
grant execute on function app.request_document_preview(
  uuid, text, uuid, uuid, text, text, uuid
) to authenticated;
grant execute on function app.complete_document_preview(
  uuid, uuid, boolean, text, text, text, uuid
) to service_role;

comment on table public.vehicles is
  'Workspace-owned physical vehicle identity; one vehicle may have multiple sequential holding episodes.';
comment on table public.inventory_units is
  'Workspace-owned inventory holding episode with a permanent transactional stock allocation.';
comment on table public.stock_number_allocations is
  'Append-only, idempotent, never-reused stock number history.';
comment on table public.documents is
  'Milestone 1 preview-only records; official numbers and production templates are prohibited.';
comment on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) is 'Authenticated inventory command with transactional allocation, idempotency, and audit.';
comment on function app.create_deal_draft(
  uuid, text, text, text, uuid, text, uuid, text, text, text, uuid
) is 'Authenticated draft command deriving owner membership and enforcing workspace-owned links.';
comment on function app.request_document_preview(
  uuid, text, uuid, uuid, text, text, uuid
) is 'Queues an unnumbered, watermarked synthetic preview record and audit event.';
