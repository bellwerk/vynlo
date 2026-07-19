-- VYN-INV-001, VYN-INV-002, VYN-NUM-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-API-001, T-INV-001, T-INV-002, T-INV-003,
-- T-NUM-001, T-NUM-002, T-NUM-003, T-TEN-001, T-RBAC-001, T-AUD-001
-- Canonical inventory intake consumes one immutable successful VIN decode.
-- The legacy allocation primitive remains callable by the function owner only;
-- browser callers cannot bypass decode confirmation or duplicate review.

create table public.vin_inventory_intakes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vin_decode_request_id uuid not null,
  vin_decode_result_id uuid not null,
  vin_duplicate_review_id uuid,
  inventory_unit_id uuid not null,
  vehicle_id uuid not null,
  confirmed_facts jsonb not null check (
    pg_catalog.jsonb_typeof(confirmed_facts) = 'object'
    and pg_catalog.octet_length(confirmed_facts::text) <= 16000
  ),
  decode_result_fingerprint text not null check (
    decode_result_fingerprint ~ '^[a-f0-9]{64}$'
  ),
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  command_fingerprint text not null check (
    command_fingerprint ~ '^[a-f0-9]{64}$'
  ),
  consumed_request_version bigint not null check (consumed_request_version > 0),
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  request_id text check (
    request_id is null or pg_catalog.char_length(request_id) <= 200
  ),
  correlation_id uuid not null,
  consumed_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, vin_decode_request_id),
  unique (workspace_id, vin_decode_result_id),
  unique (workspace_id, inventory_unit_id),
  unique (workspace_id, actor_user_id, idempotency_key),
  unique (workspace_id, audit_event_id),
  unique (workspace_id, outbox_event_id),
  foreign key (workspace_id, vin_decode_request_id)
    references public.vin_decode_requests (workspace_id, id) on delete restrict,
  foreign key (workspace_id, vin_decode_result_id)
    references public.vin_decode_results (workspace_id, id) on delete restrict,
  foreign key (workspace_id, vin_duplicate_review_id)
    references public.vin_duplicate_reviews (workspace_id, id) on delete restrict,
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id) on delete restrict,
  foreign key (workspace_id, vehicle_id)
    references public.vehicles (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict
);

-- Redundant candidate keys make the cross-aggregate lineage enforceable by
-- composite foreign keys instead of relying only on command implementation.
alter table public.vin_decode_results
  add constraint vin_decode_results_intake_lineage_unique
  unique (workspace_id, vin_decode_request_id, id);
alter table public.vin_duplicate_reviews
  add constraint vin_duplicate_reviews_intake_lineage_unique
  unique (workspace_id, vin_decode_request_id, id);
alter table public.inventory_units
  add constraint inventory_units_intake_lineage_unique
  unique (workspace_id, id, vehicle_id);
alter table public.vin_inventory_intakes
  add constraint vin_inventory_intakes_result_lineage_fk
    foreign key (workspace_id, vin_decode_request_id, vin_decode_result_id)
    references public.vin_decode_results (
      workspace_id,
      vin_decode_request_id,
      id
    )
    on delete restrict,
  add constraint vin_inventory_intakes_review_lineage_fk
    foreign key (workspace_id, vin_decode_request_id, vin_duplicate_review_id)
    references public.vin_duplicate_reviews (
      workspace_id,
      vin_decode_request_id,
      id
    )
    on delete restrict,
  add constraint vin_inventory_intakes_inventory_vehicle_fk
    foreign key (workspace_id, inventory_unit_id, vehicle_id)
    references public.inventory_units (workspace_id, id, vehicle_id)
    on delete restrict;

alter table public.vin_decode_requests
  add column consumed_at timestamptz,
  add column consumed_by_inventory_intake_id uuid,
  add constraint vin_decode_requests_consumption_shape_check check (
    (consumed_at is null and consumed_by_inventory_intake_id is null)
    or (consumed_at is not null and consumed_by_inventory_intake_id is not null)
  ),
  add constraint vin_decode_requests_consumption_fk
    foreign key (workspace_id, consumed_by_inventory_intake_id)
    references public.vin_inventory_intakes (workspace_id, id)
    on delete restrict,
  add constraint vin_decode_requests_consumption_unique
    unique (workspace_id, consumed_by_inventory_intake_id);

create index vin_inventory_intakes_workspace_time_idx
  on public.vin_inventory_intakes (workspace_id, consumed_at desc, id);

create function app.protect_consumed_vin_decode_request()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.consumed_at is not null and new is distinct from old then
    raise exception using
      errcode = '55000',
      message = 'consumed VIN decode requests are immutable';
  end if;
  return new;
end;
$$;

create function app.reject_review_after_vin_intake()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.vin_decode_requests request
    where request.workspace_id = new.workspace_id
      and request.id = new.vin_decode_request_id
      and request.consumed_at is not null
  ) then
    raise exception using
      errcode = '55000',
      message = 'consumed VIN decode requests cannot be reviewed';
  end if;
  return new;
end;
$$;

create trigger vin_decode_requests_protect_consumption
before update on public.vin_decode_requests
for each row execute function app.protect_consumed_vin_decode_request();

create trigger vin_duplicate_reviews_reject_after_intake
before insert on public.vin_duplicate_reviews
for each row execute function app.reject_review_after_vin_intake();

create trigger vin_inventory_intakes_immutable
before update or delete on public.vin_inventory_intakes
for each row execute function app.prevent_vin_history_mutation();

-- The original review command recorded every valid review as approved for
-- intake, even though the one-open-holding invariant means an acknowledged
-- open duplicate still requires resolution. Keep its append-only record and
-- audit behavior as an internal primitive, then expose a corrected projection.
alter function app.review_vin_duplicate_request(
  uuid, uuid, text, text, text, text, uuid
) rename to record_vin_duplicate_review;

create function app.enforce_open_duplicate_review_resolution()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.action = 'inventory.vin_duplicate_reviewed'
    and new.entity_type = 'vin_decode_request'
    and new.after_data ->> 'decision' = 'override_open_duplicate' then
    new.after_data := pg_catalog.jsonb_set(
      new.after_data,
      '{approved_for_intake}',
      'false'::jsonb,
      true
    );
  end if;
  return new;
end;
$$;

create trigger audit_events_correct_open_duplicate_review
before insert on public.audit_events
for each row execute function app.enforce_open_duplicate_review_resolution();

create function app.review_vin_duplicate_request(
  p_workspace_id uuid,
  p_vin_decode_request_id uuid,
  p_idempotency_key text,
  p_decision text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  vin_duplicate_review_id uuid,
  vin_decode_request_id uuid,
  vehicle_id uuid,
  decision text,
  approved_for_intake boolean,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language sql
security definer
set search_path = ''
as $$
  select
    recorded.vin_duplicate_review_id,
    recorded.vin_decode_request_id,
    recorded.vehicle_id,
    recorded.decision,
    case
      when recorded.decision = 'override_open_duplicate' then false
      else recorded.approved_for_intake
    end,
    recorded.aggregate_version,
    recorded.audit_event_id,
    recorded.outbox_event_id,
    recorded.replayed
  from app.record_vin_duplicate_review(
    p_workspace_id,
    p_vin_decode_request_id,
    p_idempotency_key,
    p_decision,
    p_reason,
    p_request_id,
    p_correlation_id
  ) recorded;
$$;

create function app.create_inventory_unit_from_vin_decode(
  p_workspace_id uuid,
  p_vin_decode_request_id uuid,
  p_vin_decode_result_id uuid,
  p_expected_request_version bigint,
  p_stock_definition_id uuid,
  p_idempotency_key text,
  p_facts_confirmed boolean,
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
  vin_inventory_intake_id uuid,
  vin_decode_request_id uuid,
  vin_decode_request_version bigint,
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_request public.vin_decode_requests%rowtype;
  target_result public.vin_decode_results%rowtype;
  target_review public.vin_duplicate_reviews%rowtype;
  existing_intake public.vin_inventory_intakes%rowtype;
  matching_vehicle public.vehicles%rowtype;
  normalized_idempotency_key text := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
  normalized_make text := nullif(
    pg_catalog.btrim(coalesce(p_make, '')),
    ''
  );
  normalized_model text := nullif(
    pg_catalog.btrim(coalesce(p_model, '')),
    ''
  );
  normalized_body_type text := nullif(
    pg_catalog.btrim(coalesce(p_body_type, '')),
    ''
  );
  normalized_drivetrain text := nullif(
    pg_catalog.btrim(coalesce(p_drivetrain, '')),
    ''
  );
  normalized_engine_liters numeric(6, 3);
  normalized_fuel_type text := nullif(
    pg_catalog.btrim(coalesce(p_fuel_type, '')),
    ''
  );
  normalized_transmission text := nullif(
    pg_catalog.btrim(coalesce(p_transmission, '')),
    ''
  );
  normalized_trim_name text := nullif(
    pg_catalog.btrim(coalesce(p_trim_name, '')),
    ''
  );
  normalized_currency text := pg_catalog.upper(
    pg_catalog.btrim(coalesce(p_currency_code, ''))
  );
  normalized_public_notes text := nullif(
    pg_catalog.btrim(coalesce(p_public_notes, '')),
    ''
  );
  confirmed_facts_snapshot jsonb;
  request_fingerprint text;
  internal_allocation_key text;
  open_count integer := 0;
  historical_count integer := 0;
  inventory_history_count integer := 0;
  created_inventory record;
  new_intake_id uuid := pg_catalog.gen_random_uuid();
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  next_request_version bigint;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.create'
  );

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid inventory intake idempotency key';
  end if;
  if p_vin_decode_request_id is null
    or p_vin_decode_result_id is null
    or p_stock_definition_id is null
    or p_expected_request_version is null
    or p_expected_request_version < 1 then
    raise exception using
      errcode = '22023',
      message = 'VIN request, result, version, and stock definition are required';
  end if;
  if p_facts_confirmed is not true then
    raise exception using
      errcode = '22023',
      message = 'normalized VIN facts require explicit confirmation';
  end if;
  if p_model_year is not null and p_model_year not between 1886 and 2200 then
    raise exception using errcode = '22023', message = 'invalid confirmed model year';
  end if;
  if normalized_make is not null and pg_catalog.char_length(normalized_make) > 100
    or normalized_model is not null and pg_catalog.char_length(normalized_model) > 100
    or normalized_body_type is not null and pg_catalog.char_length(normalized_body_type) > 200
    or normalized_drivetrain is not null and pg_catalog.char_length(normalized_drivetrain) > 100
    or normalized_fuel_type is not null and pg_catalog.char_length(normalized_fuel_type) > 100
    or normalized_transmission is not null and pg_catalog.char_length(normalized_transmission) > 200
    or normalized_trim_name is not null and pg_catalog.char_length(normalized_trim_name) > 200 then
    raise exception using errcode = '22023', message = 'confirmed vehicle text is too long';
  end if;
  if p_cylinders is not null and p_cylinders not between 1 and 64
    or p_horsepower is not null and p_horsepower not between 1 and 10000 then
    raise exception using errcode = '22023', message = 'invalid confirmed vehicle measurement';
  end if;
  if p_engine_liters is not null then
    if pg_catalog.btrim(p_engine_liters) !~ '^\d{1,2}(?:\.\d{1,3})?$' then
      raise exception using errcode = '22023', message = 'invalid confirmed engine displacement';
    end if;
    normalized_engine_liters := pg_catalog.btrim(p_engine_liters)::numeric(6, 3);
    if normalized_engine_liters not between 0.001 and 99.999 then
      raise exception using errcode = '22023', message = 'invalid confirmed engine displacement';
    end if;
  end if;
  if (p_odometer_value is null) <> (p_odometer_unit is null)
    or p_odometer_value is not null and p_odometer_value < 0
    or p_odometer_unit is not null and p_odometer_unit not in ('km', 'mi') then
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
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'inventory request ID is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;

  confirmed_facts_snapshot := pg_catalog.jsonb_build_object(
    'model_year', p_model_year,
    'make', normalized_make,
    'model', normalized_model,
    'body_type', normalized_body_type,
    'cylinders', p_cylinders,
    'drivetrain', normalized_drivetrain,
    'engine_liters', case
      when normalized_engine_liters is null then null
      else pg_catalog.trim_scale(normalized_engine_liters)::text
    end,
    'fuel_type', normalized_fuel_type,
    'horsepower', p_horsepower,
    'transmission', normalized_transmission,
    'trim_name', normalized_trim_name
  );
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'vin_decode_request_id', p_vin_decode_request_id,
      'vin_decode_result_id', p_vin_decode_result_id,
      'expected_request_version', p_expected_request_version,
      'stock_definition_id', p_stock_definition_id,
      'facts_confirmed', p_facts_confirmed,
      'confirmed_facts', confirmed_facts_snapshot,
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
      p_workspace_id::text || E'\x1fvin_inventory_intake_key\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select intake.*
    into existing_intake
  from public.vin_inventory_intakes intake
  where intake.workspace_id = p_workspace_id
    and intake.actor_user_id = app.current_user_id()
    and intake.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_intake.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'inventory intake idempotency key was used for a different request';
    end if;
    return query
    select
      existing_intake.id,
      existing_intake.vin_decode_request_id,
      existing_intake.consumed_request_version,
      existing_intake.inventory_unit_id,
      existing_intake.vehicle_id,
      unit.stock_number::text,
      existing_intake.audit_event_id,
      existing_intake.outbox_event_id,
      true
    from public.inventory_units unit
    where unit.workspace_id = existing_intake.workspace_id
      and unit.id = existing_intake.inventory_unit_id;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fvin_inventory_intake_request\x1f'
        || p_vin_decode_request_id::text,
      0
    )
  );

  select request.*
    into target_request
  from public.vin_decode_requests request
  where request.workspace_id = p_workspace_id
    and request.id = p_vin_decode_request_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'VIN request was not found';
  end if;
  if target_request.status <> 'succeeded' then
    raise exception using errcode = '55000', message = 'inventory intake requires a successful VIN decode';
  end if;
  if target_request.consumed_at is not null then
    raise exception using errcode = '23505', message = 'VIN request was already consumed';
  end if;
  if target_request.version <> p_expected_request_version then
    raise exception using errcode = '40001', message = 'VIN request version conflict';
  end if;

  select result.*
    into target_result
  from public.vin_decode_results result
  where result.workspace_id = p_workspace_id
    and result.id = p_vin_decode_result_id
    and result.vin_decode_request_id = target_request.id;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'confirmed VIN result does not belong to the request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fvin_inventory_intake_vin\x1f'
        || pg_catalog.upper(target_request.vin::text),
      0
    )
  );

  select vehicle.*
    into matching_vehicle
  from public.vehicles vehicle
  where vehicle.workspace_id = p_workspace_id
    and vehicle.vin = target_request.vin
  for update;

  select review.*
    into target_review
  from public.vin_duplicate_reviews review
  where review.workspace_id = p_workspace_id
    and review.vin_decode_request_id = target_request.id;

  if matching_vehicle.id is null then
    if target_review.id is not null then
      raise exception using
        errcode = '23514',
        message = 'VIN duplicate review no longer matches current vehicle state';
    end if;
  else
    select
      pg_catalog.count(*) filter (
        where unit.status in ('draft', 'active', 'pending')
      )::integer,
      pg_catalog.count(*) filter (
        where unit.status in ('closed', 'archived')
      )::integer,
      pg_catalog.count(*)::integer
      into open_count, historical_count, inventory_history_count
    from public.inventory_units unit
    where unit.workspace_id = p_workspace_id
      and unit.vehicle_id = matching_vehicle.id;

    if target_review.id is null
      or target_review.vehicle_id <> matching_vehicle.id then
      raise exception using
        errcode = '55000',
        message = 'current VIN duplicate state requires a completed review';
    end if;
    if open_count > 0 then
      if target_review.decision <> 'override_open_duplicate' then
        raise exception using
          errcode = '55000',
          message = 'open VIN duplicate state requires an override review';
      end if;
      raise exception using
        errcode = '23514',
        message = 'open VIN inventory must be resolved before a new holding episode';
    elsif historical_count > 0 then
      if target_review.decision <> 'reacquire_existing_vehicle' then
        raise exception using
          errcode = '55000',
          message = 'historical VIN state requires a reacquisition review';
      end if;
    elsif inventory_history_count = 0
      and target_review.decision <> 'reuse_existing_vehicle' then
      raise exception using
        errcode = '55000',
        message = 'vehicle-only VIN state requires a reuse review';
    end if;

    if (p_model_year is not null and matching_vehicle.model_year is not null
        and p_model_year <> matching_vehicle.model_year)
      or (normalized_make is not null and matching_vehicle.make is not null
        and pg_catalog.lower(normalized_make) <> pg_catalog.lower(matching_vehicle.make))
      or (normalized_model is not null and matching_vehicle.model is not null
        and pg_catalog.lower(normalized_model) <> pg_catalog.lower(matching_vehicle.model))
      or (normalized_body_type is not null and matching_vehicle.body_type is not null
        and pg_catalog.lower(normalized_body_type) <> pg_catalog.lower(matching_vehicle.body_type))
      or (p_cylinders is not null and matching_vehicle.cylinders is not null
        and p_cylinders <> matching_vehicle.cylinders)
      or (normalized_drivetrain is not null and matching_vehicle.drivetrain is not null
        and pg_catalog.lower(normalized_drivetrain) <> pg_catalog.lower(matching_vehicle.drivetrain))
      or (normalized_engine_liters is not null
        and matching_vehicle.engine_displacement_liters is not null
        and normalized_engine_liters <> matching_vehicle.engine_displacement_liters)
      or (normalized_fuel_type is not null and matching_vehicle.fuel_type is not null
        and pg_catalog.lower(normalized_fuel_type) <> pg_catalog.lower(matching_vehicle.fuel_type))
      or (p_horsepower is not null and matching_vehicle.horsepower is not null
        and p_horsepower <> matching_vehicle.horsepower)
      or (normalized_transmission is not null and matching_vehicle.transmission is not null
        and pg_catalog.lower(normalized_transmission) <> pg_catalog.lower(matching_vehicle.transmission))
      or (normalized_trim_name is not null and matching_vehicle.trim_name is not null
        and pg_catalog.lower(normalized_trim_name) <> pg_catalog.lower(matching_vehicle.trim_name)) then
      raise exception using
        errcode = '23514',
        message = 'confirmed VIN facts conflict with authoritative vehicle facts';
    end if;
  end if;

  internal_allocation_key := 'vin-intake/' || p_vin_decode_request_id::text;
  select created.*
    into created_inventory
  from app.create_inventory_unit(
    p_workspace_id,
    p_stock_definition_id,
    internal_allocation_key,
    target_request.vin::text,
    p_model_year,
    normalized_make,
    normalized_model,
    p_acquisition_date,
    p_odometer_value,
    p_odometer_unit,
    normalized_currency,
    p_advertised_price_minor,
    normalized_public_notes,
    p_request_id,
    p_correlation_id
  ) created;

  update public.vehicles vehicle
  set model_year = coalesce(vehicle.model_year, p_model_year),
      make = coalesce(vehicle.make, normalized_make),
      model = coalesce(vehicle.model, normalized_model),
      body_type = coalesce(vehicle.body_type, normalized_body_type),
      cylinders = coalesce(vehicle.cylinders, p_cylinders),
      drivetrain = coalesce(vehicle.drivetrain, normalized_drivetrain),
      engine_displacement_liters = coalesce(
        vehicle.engine_displacement_liters,
        normalized_engine_liters
      ),
      fuel_type = coalesce(vehicle.fuel_type, normalized_fuel_type),
      horsepower = coalesce(vehicle.horsepower, p_horsepower),
      transmission = coalesce(vehicle.transmission, normalized_transmission),
      trim_name = coalesce(vehicle.trim_name, normalized_trim_name)
  where vehicle.workspace_id = p_workspace_id
    and vehicle.id = created_inventory.vehicle_id;

  next_request_version := target_request.version + 1;
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_unit.intake_confirmed',
    created_inventory.inventory_unit_id,
    1,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', created_inventory.inventory_unit_id,
      'vehicleId', created_inventory.vehicle_id,
      'vinDecodeRequestId', target_request.id,
      'vinDecodeResultId', target_result.id,
      'vinDuplicateReviewId', target_review.id,
      'stockNumber', created_inventory.stock_number
    ),
    actor_user_id,
    p_correlation_id
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_unit.intake_confirmed',
    p_entity_type => 'inventory_unit',
    p_entity_id => created_inventory.inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'vehicle_id', created_inventory.vehicle_id,
      'stock_number', created_inventory.stock_number,
      'confirmed_facts', confirmed_facts_snapshot
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'vin_inventory_intake_id', new_intake_id,
      'vin_decode_request_id', target_request.id,
      'vin_decode_result_id', target_result.id,
      'vin_duplicate_review_id', target_review.id,
      'decode_result_fingerprint', target_result.result_fingerprint,
      'outbox_event_id', new_outbox_event_id
    )
  );

  insert into public.vin_inventory_intakes (
    id,
    workspace_id,
    vin_decode_request_id,
    vin_decode_result_id,
    vin_duplicate_review_id,
    inventory_unit_id,
    vehicle_id,
    confirmed_facts,
    decode_result_fingerprint,
    idempotency_key,
    command_fingerprint,
    consumed_request_version,
    actor_user_id,
    audit_event_id,
    outbox_event_id,
    request_id,
    correlation_id
  ) values (
    new_intake_id,
    p_workspace_id,
    target_request.id,
    target_result.id,
    target_review.id,
    created_inventory.inventory_unit_id,
    created_inventory.vehicle_id,
    confirmed_facts_snapshot,
    target_result.result_fingerprint,
    normalized_idempotency_key,
    request_fingerprint,
    next_request_version,
    actor_user_id,
    new_audit_event_id,
    new_outbox_event_id,
    p_request_id,
    p_correlation_id
  );

  update public.vin_decode_requests request
  set consumed_at = pg_catalog.statement_timestamp(),
      consumed_by_inventory_intake_id = new_intake_id,
      version = next_request_version
  where request.workspace_id = p_workspace_id
    and request.id = target_request.id;

  return query
  select
    new_intake_id,
    target_request.id,
    next_request_version,
    created_inventory.inventory_unit_id,
    created_inventory.vehicle_id,
    created_inventory.stock_number,
    new_audit_event_id,
    new_outbox_event_id,
    false;
end;
$$;

alter table public.vin_inventory_intakes enable row level security;
alter table public.vin_inventory_intakes force row level security;

revoke all on table public.vin_inventory_intakes
  from public, anon, authenticated, service_role;
grant select on table public.vin_inventory_intakes to service_role;

revoke all on function app.protect_consumed_vin_decode_request()
  from public, anon, authenticated, service_role;
revoke all on function app.reject_review_after_vin_intake()
  from public, anon, authenticated, service_role;
revoke all on function app.enforce_open_duplicate_review_resolution()
  from public, anon, authenticated, service_role;
revoke all on function app.record_vin_duplicate_review(
  uuid, uuid, text, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.review_vin_duplicate_request(
  uuid, uuid, text, text, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.review_vin_duplicate_request(
  uuid, uuid, text, text, text, text, uuid
) to authenticated;

-- This is the security cutover. The old function is retained as an internal
-- transactional allocation primitive so the canonical intake can reuse its
-- proven numbering behavior, but no API role may execute it directly.
revoke all on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) from public, anon, authenticated, service_role;

revoke all on function app.create_inventory_unit_from_vin_decode(
  uuid, uuid, uuid, bigint, uuid, text, boolean, integer, text, text, text,
  integer, text, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.create_inventory_unit_from_vin_decode(
  uuid, uuid, uuid, bigint, uuid, text, boolean, integer, text, text, text,
  integer, text, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) to authenticated;

comment on table public.vin_inventory_intakes is
  'Append-only proof that one successful VIN decode and its required duplicate review were consumed by one inventory holding episode.';
comment on function app.record_vin_duplicate_review(
  uuid, uuid, text, text, text, text, uuid
) is
  'Internal append-only duplicate-review primitive; API callers use review_vin_duplicate_request.';
comment on function app.review_vin_duplicate_request(
  uuid, uuid, text, text, text, text, uuid
) is
  'Authenticated duplicate-review projection; unresolved open duplicates are acknowledged but not approved for intake.';
comment on function app.create_inventory_unit_from_vin_decode(
  uuid, uuid, uuid, bigint, uuid, text, boolean, integer, text, text, text,
  integer, text, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) is
  'Canonical authenticated VIN intake with explicit fact confirmation, duplicate-state recheck, immutable consumption, transactional stock allocation, audit, and outbox evidence.';
comment on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) is
  'Internal inventory allocation primitive; API roles must use create_inventory_unit_from_vin_decode.';
