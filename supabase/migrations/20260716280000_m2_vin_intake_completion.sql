-- VYN-INV-001, VYN-INV-002, VYN-NUM-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001, VYN-API-001, T-INV-001, T-INV-002,
-- T-INV-003, T-NUM-001, T-RBAC-001, T-AUD-001
-- M2-INV-AC-001, M2-INV-AC-002, M2-INV-AC-003, M2-INV-AC-004,
-- M2-INV-AC-005, M2-INV-AC-010, M2-INV-AC-011
-- Complete the canonical VIN intake boundary. Confirmed provider results and
-- dead-letter manual facts now require workspace configuration, consume one
-- request exactly once, and preserve reference-only provider failure lineage.

create table public.inventory_condition_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key text not null check (
    key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    and pg_catalog.char_length(key) <= 100
  ),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and pg_catalog.jsonb_object_length(labels) > 0
  ),
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key)
);

create index inventory_condition_definitions_workspace_status_idx
  on public.inventory_condition_definitions (workspace_id, status, key, id);

create table public.vin_inventory_intake_links (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vin_decode_request_id uuid not null,
  inventory_unit_id uuid not null,
  vehicle_id uuid not null,
  intake_kind text not null check (
    intake_kind in ('confirmed_decode', 'manual_dead_letter')
  ),
  linked_existing_open_unit boolean not null,
  location_id uuid not null,
  condition_key text not null,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  linked_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, vin_decode_request_id),
  foreign key (workspace_id, vin_decode_request_id)
    references public.vin_decode_requests (workspace_id, id) on delete restrict,
  foreign key (workspace_id, inventory_unit_id, vehicle_id)
    references public.inventory_units (workspace_id, id, vehicle_id)
    on delete restrict,
  foreign key (workspace_id, location_id)
    references public.locations (workspace_id, id) on delete restrict,
  foreign key (workspace_id, condition_key)
    references public.inventory_condition_definitions (workspace_id, key)
    on delete restrict
);

create table public.vin_manual_inventory_intakes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vin_decode_request_id uuid not null,
  terminal_job_id uuid not null,
  link_receipt_id uuid not null,
  inventory_unit_id uuid not null,
  vehicle_id uuid not null,
  location_id uuid not null,
  condition_key text not null,
  stock_definition_id uuid not null,
  manual_facts jsonb not null check (
    pg_catalog.jsonb_typeof(manual_facts) = 'object'
    and pg_catalog.octet_length(manual_facts::text) <= 16000
  ),
  manual_reason text not null check (
    pg_catalog.btrim(manual_reason) <> ''
    and pg_catalog.char_length(manual_reason) <= 2000
  ),
  duplicate_decision text check (
    duplicate_decision is null or duplicate_decision in (
      'reuse_existing_vehicle',
      'reacquire_existing_vehicle',
      'override_open_duplicate'
    )
  ),
  duplicate_reason text check (
    duplicate_reason is null or (
      pg_catalog.btrim(duplicate_reason) <> ''
      and pg_catalog.char_length(duplicate_reason) <= 2000
    )
  ),
  terminal_failure_snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(terminal_failure_snapshot) = 'object'
    and pg_catalog.octet_length(terminal_failure_snapshot::text) <= 8000
  ),
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
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
  unique (workspace_id, terminal_job_id),
  unique (workspace_id, link_receipt_id),
  unique (workspace_id, actor_user_id, idempotency_key),
  unique (workspace_id, audit_event_id),
  unique (workspace_id, outbox_event_id),
  foreign key (workspace_id, vin_decode_request_id)
    references public.vin_decode_requests (workspace_id, id) on delete restrict,
  foreign key (workspace_id, terminal_job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, link_receipt_id)
    references public.vin_inventory_intake_links (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, inventory_unit_id, vehicle_id)
    references public.inventory_units (workspace_id, id, vehicle_id)
    on delete restrict,
  foreign key (workspace_id, location_id)
    references public.locations (workspace_id, id) on delete restrict,
  foreign key (workspace_id, condition_key)
    references public.inventory_condition_definitions (workspace_id, key)
    on delete restrict,
  foreign key (workspace_id, stock_definition_id)
    references public.stock_number_definitions (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  check (
    (duplicate_decision is null and duplicate_reason is null)
    or (duplicate_decision is not null and duplicate_reason is not null)
  )
);

alter table public.vin_inventory_intakes
  drop constraint vin_inventory_intakes_workspace_id_inventory_unit_id_key,
  add column link_receipt_id uuid,
  add column location_id uuid,
  add column condition_key text,
  add column stock_definition_id uuid,
  add constraint vin_inventory_intakes_link_receipt_fk
    foreign key (workspace_id, link_receipt_id)
    references public.vin_inventory_intake_links (workspace_id, id)
    on delete restrict,
  add constraint vin_inventory_intakes_location_fk
    foreign key (workspace_id, location_id)
    references public.locations (workspace_id, id) on delete restrict,
  add constraint vin_inventory_intakes_condition_fk
    foreign key (workspace_id, condition_key)
    references public.inventory_condition_definitions (workspace_id, key)
    on delete restrict,
  add constraint vin_inventory_intakes_stock_definition_fk
    foreign key (workspace_id, stock_definition_id)
    references public.stock_number_definitions (workspace_id, id)
    on delete restrict;

alter table public.vin_decode_requests
  drop constraint vin_decode_requests_consumption_shape_check,
  add column consumed_by_manual_inventory_intake_id uuid,
  add constraint vin_decode_requests_consumption_shape_check check (
    (
      consumed_at is null
      and consumed_by_inventory_intake_id is null
      and consumed_by_manual_inventory_intake_id is null
    )
    or (
      consumed_at is not null
      and (consumed_by_inventory_intake_id is not null)::integer
        + (consumed_by_manual_inventory_intake_id is not null)::integer = 1
    )
  ),
  add constraint vin_decode_requests_manual_consumption_fk
    foreign key (workspace_id, consumed_by_manual_inventory_intake_id)
    references public.vin_manual_inventory_intakes (workspace_id, id)
    on delete restrict,
  add constraint vin_decode_requests_manual_consumption_unique
    unique (workspace_id, consumed_by_manual_inventory_intake_id);

-- Consumption is a request lifecycle state, not a rewrite of the durable job.
-- A manually consumed request projects as terminal while retaining its latest
-- dead-letter job and safe failure metadata for support and audit review.
create or replace function app.get_vin_decode_request(
  p_workspace_id uuid,
  p_vin_decode_request_id uuid
)
returns table (
  vin_decode_request_id uuid,
  vin text,
  model_year_hint integer,
  aggregate_version bigint,
  requested_at timestamptz,
  completed_at timestamptz,
  status text,
  job_id uuid,
  job_status text,
  attempt_count integer,
  maximum_attempts integer,
  retry_at timestamptz,
  retryable boolean,
  last_error_classification text,
  last_error_code text,
  review_required boolean,
  raw_result_reference uuid,
  provider_key text,
  provider_version text,
  decoded_at timestamptz,
  warnings jsonb,
  model_year integer,
  make text,
  model text,
  body_type text,
  cylinders integer,
  drivetrain text,
  engine_liters text,
  fuel_type text,
  horsepower integer,
  transmission text,
  trim_name text,
  duplicate_candidates jsonb,
  duplicate_review jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_vertical_slice_permission(p_workspace_id, 'inventory.read');

  if not exists (
    select 1
    from public.vin_decode_requests request
    where request.workspace_id = p_workspace_id
      and request.id = p_vin_decode_request_id
  ) then
    raise exception using errcode = 'P0002', message = 'VIN request was not found';
  end if;

  return query
  select
    request.id,
    request.vin::text,
    request.model_year_hint::integer,
    request.version,
    request.requested_at,
    request.completed_at,
    case
      when request.consumed_at is not null then 'consumed'
      when result.id is not null then 'succeeded'
      else latest_job.status
    end,
    latest_job.id,
    latest_job.status,
    latest_job.attempts_started,
    latest_job.max_attempts,
    case when latest_job.status = 'retry_wait' then latest_job.available_at else null end,
    request.consumed_at is null
      and latest_job.status in ('retry_wait', 'dead_letter'),
    latest_job.last_error_classification,
    latest_job.last_error_code,
    request.consumed_at is null and latest_job.review_required,
    result.id,
    result.provider_key,
    result.provider_version,
    result.decoded_at,
    coalesce(result.warnings, '[]'::jsonb),
    result.model_year::integer,
    result.make,
    result.model,
    result.body_type,
    result.cylinders::integer,
    result.drivetrain,
    case
      when result.engine_displacement_liters is null then null
      else pg_catalog.trim_scale(result.engine_displacement_liters)::text
    end,
    result.fuel_type,
    result.horsepower,
    result.transmission,
    result.trim_name,
    coalesce(candidate_set.items, '[]'::jsonb),
    case
      when review.id is null then null
      else pg_catalog.jsonb_build_object(
        'id', review.id,
        'vehicle_id', review.vehicle_id,
        'decision', review.decision,
        'reason', review.reason,
        'reviewed_at', review.reviewed_at
      )
    end
  from public.vin_decode_requests request
  join lateral (
    select job.*
    from public.jobs job
    where job.workspace_id = request.workspace_id
      and job.job_type = 'inventory.vin_decode'
      and job.entity_type = 'vin_decode_request'
      and job.entity_id = request.id
    order by job.created_at desc, job.id desc
    limit 1
  ) latest_job on true
  left join public.vin_decode_results result
    on result.workspace_id = request.workspace_id
   and result.vin_decode_request_id = request.id
  left join lateral (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', candidate.id,
        'vehicle_id', candidate.vehicle_id,
        'inventory_unit_id', candidate.inventory_unit_id,
        'kind', candidate.candidate_kind,
        'inventory_status', candidate.inventory_status_snapshot,
        'stock_number', candidate.stock_number_snapshot,
        'observed_at', candidate.observed_at
      )
      order by candidate.observed_at, candidate.id
    ) items
    from public.vin_duplicate_candidates candidate
    where candidate.workspace_id = request.workspace_id
      and candidate.vin_decode_request_id = request.id
  ) candidate_set on true
  left join public.vin_duplicate_reviews review
    on review.workspace_id = request.workspace_id
   and review.vin_decode_request_id = request.id
  where request.workspace_id = p_workspace_id
    and request.id = p_vin_decode_request_id;
end;
$$;

create trigger vin_inventory_intake_links_immutable
before update or delete on public.vin_inventory_intake_links
for each row execute function app.prevent_vin_history_mutation();

create trigger vin_manual_inventory_intakes_immutable
before update or delete on public.vin_manual_inventory_intakes
for each row execute function app.prevent_vin_history_mutation();

-- The earlier compatibility projection marked a manager-approved open-unit
-- link as unapproved because that implementation could only create a second
-- holding. The completed command links the existing unit, so the durable
-- review and its audit projection are now truthfully approved for intake.
drop trigger if exists audit_events_correct_open_duplicate_review
  on public.audit_events;
drop function if exists app.enforce_open_duplicate_review_resolution();

create or replace function app.review_vin_duplicate_request(
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
    recorded.approved_for_intake,
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

create function app.resolve_inventory_unit_for_vin_intake(
  p_workspace_id uuid,
  p_vin_decode_request_id uuid,
  p_stock_definition_id uuid,
  p_location_id uuid,
  p_condition_key text,
  p_internal_allocation_key text,
  p_manual_path boolean,
  p_duplicate_decision text,
  p_duplicate_reason text,
  p_model_year integer,
  p_make text,
  p_model text,
  p_body_type text,
  p_cylinders integer,
  p_drivetrain text,
  p_engine_liters numeric,
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
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  inventory_version bigint,
  vin_duplicate_review_id uuid,
  duplicate_decision text,
  linked_existing_open_unit boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_request public.vin_decode_requests%rowtype;
  matching_vehicle public.vehicles%rowtype;
  target_review public.vin_duplicate_reviews%rowtype;
  open_unit public.inventory_units%rowtype;
  open_count integer := 0;
  historical_count integer := 0;
  inventory_history_count integer := 0;
  normalized_condition_key text := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_condition_key, ''))
  );
  normalized_duplicate_decision text := pg_catalog.nullif(
    pg_catalog.btrim(coalesce(p_duplicate_decision, '')),
    ''
  );
  normalized_duplicate_reason text := pg_catalog.nullif(
    pg_catalog.btrim(coalesce(p_duplicate_reason, '')),
    ''
  );
  created_inventory record;
  created_inventory_version bigint;
begin
  select request.*
    into target_request
  from public.vin_decode_requests request
  where request.workspace_id = p_workspace_id
    and request.id = p_vin_decode_request_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'VIN request was not found';
  end if;
  if not exists (
    select 1
    from public.locations location
    where location.workspace_id = p_workspace_id
      and location.id = p_location_id
      and location.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'an active location is required in the workspace';
  end if;
  if not exists (
    select 1
    from public.inventory_condition_definitions condition
    where condition.workspace_id = p_workspace_id
      and condition.key = normalized_condition_key
      and condition.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'an active inventory condition is required in the workspace';
  end if;
  if not exists (
    select 1
    from public.stock_number_definitions definition
    join public.stock_number_counters counter
      on counter.workspace_id = definition.workspace_id
     and counter.definition_id = definition.id
    where definition.workspace_id = p_workspace_id
      and definition.id = p_stock_definition_id
      and definition.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'an active stock definition and counter are required in the workspace';
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

  if matching_vehicle.id is not null then
    perform 1
    from public.inventory_units unit
    where unit.workspace_id = p_workspace_id
      and unit.vehicle_id = matching_vehicle.id
    for update;

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
  end if;

  if p_manual_path then
    if matching_vehicle.id is null then
      if normalized_duplicate_decision is not null
        or normalized_duplicate_reason is not null then
        raise exception using
          errcode = '23514',
          message = 'manual duplicate decision no longer matches current vehicle state';
      end if;
    else
      if normalized_duplicate_reason is null then
        raise exception using
          errcode = '22023',
          message = 'manual duplicate decisions require a reason';
      end if;
      if open_count > 0 then
        if normalized_duplicate_decision <> 'override_open_duplicate' then
          raise exception using
            errcode = '55000',
            message = 'open VIN duplicate state requires a manager override decision';
        end if;
      elsif historical_count > 0 then
        if normalized_duplicate_decision <> 'reacquire_existing_vehicle' then
          raise exception using
            errcode = '55000',
            message = 'historical VIN state requires a reacquisition decision';
        end if;
      elsif inventory_history_count = 0
        and normalized_duplicate_decision <> 'reuse_existing_vehicle' then
        raise exception using
          errcode = '55000',
          message = 'vehicle-only VIN state requires a reuse decision';
      end if;
    end if;
  else
    select review.*
      into target_review
    from public.vin_duplicate_reviews review
    where review.workspace_id = p_workspace_id
      and review.vin_decode_request_id = p_vin_decode_request_id;

    if matching_vehicle.id is null then
      if target_review.id is not null then
        raise exception using
          errcode = '23514',
          message = 'VIN duplicate review no longer matches current vehicle state';
      end if;
    else
      if target_review.id is null
        or target_review.vehicle_id <> matching_vehicle.id then
        raise exception using
          errcode = '55000',
          message = 'current VIN duplicate state requires a completed review';
      end if;
      normalized_duplicate_decision := target_review.decision;
      normalized_duplicate_reason := target_review.reason;
      if open_count > 0
        and target_review.decision <> 'override_open_duplicate' then
        raise exception using
          errcode = '55000',
          message = 'open VIN duplicate state requires an override review';
      elsif open_count = 0 and historical_count > 0
        and target_review.decision <> 'reacquire_existing_vehicle' then
        raise exception using
          errcode = '55000',
          message = 'historical VIN state requires a reacquisition review';
      elsif open_count = 0 and historical_count = 0 and inventory_history_count = 0
        and target_review.decision <> 'reuse_existing_vehicle' then
        raise exception using
          errcode = '55000',
          message = 'vehicle-only VIN state requires a reuse review';
      end if;
    end if;
  end if;

  -- Open-unit linkage must prove the same fact compatibility as a new holding
  -- before any receipt can claim that the operator-confirmed snapshot matches
  -- the authoritative vehicle. This check intentionally precedes the early
  -- return used by the no-second-stock linkage branch.
  if matching_vehicle.id is not null and (
    (p_model_year is not null and matching_vehicle.model_year is not null
      and p_model_year <> matching_vehicle.model_year)
    or (p_make is not null and matching_vehicle.make is not null
      and pg_catalog.lower(p_make) <> pg_catalog.lower(matching_vehicle.make))
    or (p_model is not null and matching_vehicle.model is not null
      and pg_catalog.lower(p_model) <> pg_catalog.lower(matching_vehicle.model))
    or (p_body_type is not null and matching_vehicle.body_type is not null
      and pg_catalog.lower(p_body_type) <> pg_catalog.lower(matching_vehicle.body_type))
    or (p_cylinders is not null and matching_vehicle.cylinders is not null
      and p_cylinders <> matching_vehicle.cylinders)
    or (p_drivetrain is not null and matching_vehicle.drivetrain is not null
      and pg_catalog.lower(p_drivetrain) <> pg_catalog.lower(matching_vehicle.drivetrain))
    or (p_engine_liters is not null
      and matching_vehicle.engine_displacement_liters is not null
      and p_engine_liters <> matching_vehicle.engine_displacement_liters)
    or (p_fuel_type is not null and matching_vehicle.fuel_type is not null
      and pg_catalog.lower(p_fuel_type) <> pg_catalog.lower(matching_vehicle.fuel_type))
    or (p_horsepower is not null and matching_vehicle.horsepower is not null
      and p_horsepower <> matching_vehicle.horsepower)
    or (p_transmission is not null and matching_vehicle.transmission is not null
      and pg_catalog.lower(p_transmission) <> pg_catalog.lower(matching_vehicle.transmission))
    or (p_trim_name is not null and matching_vehicle.trim_name is not null
      and pg_catalog.lower(p_trim_name) <> pg_catalog.lower(matching_vehicle.trim_name))
  ) then
    raise exception using
      errcode = '23514',
      message = 'confirmed VIN facts conflict with authoritative vehicle facts';
  end if;

  if open_count > 0 then
    if not app.has_permission(p_workspace_id, 'inventory.duplicate_override') then
      raise exception using
        errcode = '42501',
        message = 'inventory duplicate override permission is required';
    end if;
    if not app.has_recent_strong_auth() then
      raise exception using
        errcode = '42501',
        message = 'recent strong authentication is required for duplicate override';
    end if;
    if normalized_duplicate_reason is null then
      raise exception using
        errcode = '22023',
        message = 'duplicate override requires a reason';
    end if;
    if p_acquisition_date is not null
      or p_odometer_value is not null
      or p_odometer_unit is not null
      or p_advertised_price_minor is not null
      or p_public_notes is not null then
      raise exception using
        errcode = '22023',
        message = 'open VIN linkage cannot change inventory-unit details';
    end if;

    select unit.*
      into open_unit
    from public.inventory_units unit
    where unit.workspace_id = p_workspace_id
      and unit.vehicle_id = matching_vehicle.id
      and unit.status in ('draft', 'active', 'pending')
    order by unit.created_at desc, unit.id desc
    limit 1
    for update;

    if open_unit.location_id is distinct from p_location_id
      or open_unit.condition_key is distinct from normalized_condition_key then
      raise exception using
        errcode = '23514',
        message = 'open VIN linkage must confirm the existing unit location and condition';
    end if;

    -- Compatible confirmed values are authoritative intake facts. Persist any
    -- currently-null vehicle fields before the immutable link receipt and its
    -- audit event are returned, while never overwriting a non-null fact.
    update public.vehicles vehicle
    set model_year = coalesce(vehicle.model_year, p_model_year),
        make = coalesce(vehicle.make, p_make),
        model = coalesce(vehicle.model, p_model),
        body_type = coalesce(vehicle.body_type, p_body_type),
        cylinders = coalesce(vehicle.cylinders, p_cylinders),
        drivetrain = coalesce(vehicle.drivetrain, p_drivetrain),
        engine_displacement_liters = coalesce(
          vehicle.engine_displacement_liters,
          p_engine_liters
        ),
        fuel_type = coalesce(vehicle.fuel_type, p_fuel_type),
        horsepower = coalesce(vehicle.horsepower, p_horsepower),
        transmission = coalesce(vehicle.transmission, p_transmission),
        trim_name = coalesce(vehicle.trim_name, p_trim_name),
        facts_version = vehicle.facts_version + 1,
        updated_at = pg_catalog.statement_timestamp()
    where vehicle.workspace_id = p_workspace_id
      and vehicle.id = matching_vehicle.id
      and (
        vehicle.model_year is null and p_model_year is not null
        or vehicle.make is null and p_make is not null
        or vehicle.model is null and p_model is not null
        or vehicle.body_type is null and p_body_type is not null
        or vehicle.cylinders is null and p_cylinders is not null
        or vehicle.drivetrain is null and p_drivetrain is not null
        or vehicle.engine_displacement_liters is null and p_engine_liters is not null
        or vehicle.fuel_type is null and p_fuel_type is not null
        or vehicle.horsepower is null and p_horsepower is not null
        or vehicle.transmission is null and p_transmission is not null
        or vehicle.trim_name is null and p_trim_name is not null
      );

    return query
    select
      open_unit.id,
      open_unit.vehicle_id,
      open_unit.stock_number::text,
      open_unit.version,
      target_review.id,
      normalized_duplicate_decision,
      true;
    return;
  end if;

  select created.*
    into created_inventory
  from app.create_inventory_unit(
    p_workspace_id,
    p_stock_definition_id,
    p_internal_allocation_key,
    target_request.vin::text,
    p_model_year,
    p_make,
    p_model,
    p_acquisition_date,
    p_odometer_value,
    p_odometer_unit,
    p_currency_code,
    p_advertised_price_minor,
    p_public_notes,
    p_request_id,
    p_correlation_id
  ) created;

  update public.vehicles vehicle
  set model_year = coalesce(vehicle.model_year, p_model_year),
      make = coalesce(vehicle.make, p_make),
      model = coalesce(vehicle.model, p_model),
      body_type = coalesce(vehicle.body_type, p_body_type),
      cylinders = coalesce(vehicle.cylinders, p_cylinders),
      drivetrain = coalesce(vehicle.drivetrain, p_drivetrain),
      engine_displacement_liters = coalesce(
        vehicle.engine_displacement_liters,
        p_engine_liters
      ),
      fuel_type = coalesce(vehicle.fuel_type, p_fuel_type),
      horsepower = coalesce(vehicle.horsepower, p_horsepower),
      transmission = coalesce(vehicle.transmission, p_transmission),
      trim_name = coalesce(vehicle.trim_name, p_trim_name),
      facts_version = vehicle.facts_version + 1,
      updated_at = pg_catalog.statement_timestamp()
  where vehicle.workspace_id = p_workspace_id
    and vehicle.id = created_inventory.vehicle_id
    and (
      vehicle.model_year is null and p_model_year is not null
      or vehicle.make is null and p_make is not null
      or vehicle.model is null and p_model is not null
      or vehicle.body_type is null and p_body_type is not null
      or vehicle.cylinders is null and p_cylinders is not null
      or vehicle.drivetrain is null and p_drivetrain is not null
      or vehicle.engine_displacement_liters is null and p_engine_liters is not null
      or vehicle.fuel_type is null and p_fuel_type is not null
      or vehicle.horsepower is null and p_horsepower is not null
      or vehicle.transmission is null and p_transmission is not null
      or vehicle.trim_name is null and p_trim_name is not null
    );

  update public.inventory_units unit
  set location_id = p_location_id,
      condition_key = normalized_condition_key,
      updated_at = pg_catalog.statement_timestamp()
  where unit.workspace_id = p_workspace_id
    and unit.id = created_inventory.inventory_unit_id
  returning unit.version into created_inventory_version;

  return query
  select
    created_inventory.inventory_unit_id,
    created_inventory.vehicle_id,
    created_inventory.stock_number::text,
    created_inventory_version,
    target_review.id,
    normalized_duplicate_decision,
    false;
end;
$$;

-- The old 26-argument signature did not require location or condition and is
-- deliberately retained only for owner-level migration compatibility.
revoke all on function app.create_inventory_unit_from_vin_decode(
  uuid, uuid, uuid, bigint, uuid, text, boolean, integer, text, text, text,
  integer, text, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) from public, anon, authenticated, service_role;

create function app.create_inventory_unit_from_vin_decode(
  p_workspace_id uuid,
  p_vin_decode_request_id uuid,
  p_vin_decode_result_id uuid,
  p_expected_request_version bigint,
  p_stock_definition_id uuid,
  p_location_id uuid,
  p_condition_key text,
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
  linked_existing_open_unit boolean,
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
  existing_intake public.vin_inventory_intakes%rowtype;
  normalized_idempotency_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_condition_key text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_condition_key, '')));
  normalized_make text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_make, '')), '');
  normalized_model text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_model, '')), '');
  normalized_body_type text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_body_type, '')), '');
  normalized_drivetrain text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_drivetrain, '')), '');
  normalized_engine_liters numeric(6, 3);
  normalized_fuel_type text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_fuel_type, '')), '');
  normalized_transmission text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_transmission, '')), '');
  normalized_trim_name text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_trim_name, '')), '');
  normalized_currency text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_public_notes text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_public_notes, '')), '');
  confirmed_facts_snapshot jsonb;
  request_fingerprint text;
  resolved_inventory record;
  new_intake_id uuid := pg_catalog.gen_random_uuid();
  new_link_receipt_id uuid := pg_catalog.gen_random_uuid();
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  next_request_version bigint;
begin
  actor_user_id := app.require_vertical_slice_permission(p_workspace_id, 'inventory.create');

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_vin_decode_request_id is null
    or p_vin_decode_result_id is null
    or p_stock_definition_id is null
    or p_location_id is null
    or p_expected_request_version is null
    or p_expected_request_version < 1 then
    raise exception using errcode = '22023', message = 'invalid confirmed VIN inventory intake';
  end if;
  if p_facts_confirmed is not true then
    raise exception using errcode = '22023', message = 'normalized VIN facts require explicit confirmation';
  end if;
  if normalized_condition_key !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or pg_catalog.char_length(normalized_condition_key) > 100 then
    raise exception using errcode = '22023', message = 'invalid inventory condition key';
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
  if normalized_currency !~ '^[A-Z]{3}$'
    or p_advertised_price_minor is not null and p_advertised_price_minor < 0 then
    raise exception using errcode = '22023', message = 'invalid exact advertised money';
  end if;
  if normalized_public_notes is not null and pg_catalog.char_length(normalized_public_notes) > 4000
    or p_request_id is not null and pg_catalog.char_length(p_request_id) > 200
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid confirmed intake metadata';
  end if;

  confirmed_facts_snapshot := pg_catalog.jsonb_build_object(
    'model_year', p_model_year,
    'make', normalized_make,
    'model', normalized_model,
    'body_type', normalized_body_type,
    'cylinders', p_cylinders,
    'drivetrain', normalized_drivetrain,
    'engine_liters', case when normalized_engine_liters is null then null
      else pg_catalog.trim_scale(normalized_engine_liters)::text end,
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
      'location_id', p_location_id,
      'condition_key', normalized_condition_key,
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

  select intake.* into existing_intake
  from public.vin_inventory_intakes intake
  where intake.workspace_id = p_workspace_id
    and intake.actor_user_id = actor_user_id
    and intake.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_intake.command_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505', message = 'inventory intake idempotency key was used for a different request';
    end if;
    return query
    select existing_intake.id, existing_intake.vin_decode_request_id,
      existing_intake.consumed_request_version, existing_intake.inventory_unit_id,
      existing_intake.vehicle_id, unit.stock_number::text,
      existing_intake.audit_event_id, existing_intake.outbox_event_id,
      coalesce(link.linked_existing_open_unit, false), true
    from public.inventory_units unit
    left join public.vin_inventory_intake_links link
      on link.workspace_id = existing_intake.workspace_id
     and link.id = existing_intake.link_receipt_id
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
  select request.* into target_request
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

  select result.* into target_result
  from public.vin_decode_results result
  where result.workspace_id = p_workspace_id
    and result.id = p_vin_decode_result_id
    and result.vin_decode_request_id = target_request.id;
  if not found then
    raise exception using errcode = '23514', message = 'confirmed VIN result does not belong to the request';
  end if;

  select resolved.* into resolved_inventory
  from app.resolve_inventory_unit_for_vin_intake(
    p_workspace_id, target_request.id, p_stock_definition_id, p_location_id,
    normalized_condition_key, 'vin-intake/' || target_request.id::text,
    false, null, null, p_model_year, normalized_make, normalized_model,
    normalized_body_type, p_cylinders, normalized_drivetrain,
    normalized_engine_liters, normalized_fuel_type, p_horsepower,
    normalized_transmission, normalized_trim_name, p_acquisition_date,
    p_odometer_value, p_odometer_unit, normalized_currency,
    p_advertised_price_minor, normalized_public_notes, p_request_id,
    p_correlation_id
  ) resolved;

  insert into public.vin_inventory_intake_links (
    id, workspace_id, vin_decode_request_id, inventory_unit_id, vehicle_id,
    intake_kind, linked_existing_open_unit, location_id, condition_key,
    actor_user_id
  ) values (
    new_link_receipt_id, p_workspace_id, target_request.id,
    resolved_inventory.inventory_unit_id, resolved_inventory.vehicle_id,
    'confirmed_decode', resolved_inventory.linked_existing_open_unit,
    p_location_id, normalized_condition_key, actor_user_id
  );

  next_request_version := target_request.version + 1;
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    case when resolved_inventory.linked_existing_open_unit
      then 'inventory_unit.vin_link_confirmed'
      else 'inventory_unit.intake_confirmed' end,
    resolved_inventory.inventory_unit_id,
    resolved_inventory.inventory_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', resolved_inventory.inventory_unit_id,
      'vehicleId', resolved_inventory.vehicle_id,
      'vinDecodeRequestId', target_request.id,
      'vinDecodeResultId', target_result.id,
      'vinInventoryIntakeId', new_intake_id,
      'vinInventoryIntakeLinkId', new_link_receipt_id
    ),
    actor_user_id,
    p_correlation_id
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => case when resolved_inventory.linked_existing_open_unit
      then 'inventory_unit.vin_link_confirmed'
      else 'inventory_unit.intake_confirmed' end,
    p_entity_type => 'inventory_unit',
    p_entity_id => resolved_inventory.inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'vehicle_id', resolved_inventory.vehicle_id,
      'stock_number', resolved_inventory.stock_number,
      'location_id', p_location_id,
      'condition_key', normalized_condition_key,
      'confirmed_facts', confirmed_facts_snapshot,
      'linked_existing_open_unit', resolved_inventory.linked_existing_open_unit,
      'approved_for_intake', true
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'vin_inventory_intake_id', new_intake_id,
      'vin_inventory_intake_link_id', new_link_receipt_id,
      'vin_decode_request_id', target_request.id,
      'vin_decode_result_id', target_result.id,
      'vin_duplicate_review_id', resolved_inventory.vin_duplicate_review_id,
      'decode_result_fingerprint', target_result.result_fingerprint,
      'outbox_event_id', new_outbox_event_id
    )
  );

  insert into public.vin_inventory_intakes (
    id, workspace_id, vin_decode_request_id, vin_decode_result_id,
    vin_duplicate_review_id, inventory_unit_id, vehicle_id, confirmed_facts,
    decode_result_fingerprint, idempotency_key, command_fingerprint,
    consumed_request_version, actor_user_id, audit_event_id, outbox_event_id,
    request_id, correlation_id, link_receipt_id, location_id, condition_key,
    stock_definition_id
  ) values (
    new_intake_id, p_workspace_id, target_request.id, target_result.id,
    resolved_inventory.vin_duplicate_review_id, resolved_inventory.inventory_unit_id,
    resolved_inventory.vehicle_id, confirmed_facts_snapshot,
    target_result.result_fingerprint, normalized_idempotency_key,
    request_fingerprint, next_request_version, actor_user_id,
    new_audit_event_id, new_outbox_event_id, p_request_id, p_correlation_id,
    new_link_receipt_id, p_location_id, normalized_condition_key,
    p_stock_definition_id
  );

  update public.vin_decode_requests request
  set consumed_at = pg_catalog.statement_timestamp(),
      consumed_by_inventory_intake_id = new_intake_id,
      version = next_request_version
  where request.workspace_id = p_workspace_id
    and request.id = target_request.id;

  return query select new_intake_id, target_request.id, next_request_version,
    resolved_inventory.inventory_unit_id, resolved_inventory.vehicle_id,
    resolved_inventory.stock_number, new_audit_event_id,
    new_outbox_event_id, resolved_inventory.linked_existing_open_unit, false;
end;
$$;

create function app.create_inventory_unit_from_failed_vin_decode(
  p_workspace_id uuid,
  p_vin_decode_request_id uuid,
  p_expected_request_version bigint,
  p_stock_definition_id uuid,
  p_location_id uuid,
  p_condition_key text,
  p_idempotency_key text,
  p_facts_confirmed boolean,
  p_manual_reason text,
  p_duplicate_decision text,
  p_duplicate_reason text,
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
  vin_manual_inventory_intake_id uuid,
  vin_decode_request_id uuid,
  vin_decode_request_version bigint,
  terminal_job_id uuid,
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  audit_event_id uuid,
  outbox_event_id uuid,
  linked_existing_open_unit boolean,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_request public.vin_decode_requests%rowtype;
  terminal_job public.jobs%rowtype;
  existing_intake public.vin_manual_inventory_intakes%rowtype;
  normalized_idempotency_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_condition_key text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_condition_key, '')));
  normalized_manual_reason text := pg_catalog.btrim(coalesce(p_manual_reason, ''));
  normalized_duplicate_decision text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_duplicate_decision, '')), '');
  normalized_duplicate_reason text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_duplicate_reason, '')), '');
  normalized_make text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_make, '')), '');
  normalized_model text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_model, '')), '');
  normalized_body_type text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_body_type, '')), '');
  normalized_drivetrain text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_drivetrain, '')), '');
  normalized_engine_liters numeric(6, 3);
  normalized_fuel_type text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_fuel_type, '')), '');
  normalized_transmission text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_transmission, '')), '');
  normalized_trim_name text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_trim_name, '')), '');
  normalized_currency text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_public_notes text := pg_catalog.nullif(pg_catalog.btrim(coalesce(p_public_notes, '')), '');
  manual_facts_snapshot jsonb;
  failure_snapshot jsonb;
  request_fingerprint text;
  resolved_inventory record;
  new_intake_id uuid := pg_catalog.gen_random_uuid();
  new_link_receipt_id uuid := pg_catalog.gen_random_uuid();
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  next_request_version bigint;
begin
  actor_user_id := app.require_vertical_slice_permission(p_workspace_id, 'inventory.create');

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_vin_decode_request_id is null
    or p_stock_definition_id is null
    or p_location_id is null
    or p_expected_request_version is null
    or p_expected_request_version < 1
    or pg_catalog.char_length(normalized_manual_reason) not between 1 and 2000
    or p_facts_confirmed is not true then
    raise exception using errcode = '22023', message = 'invalid manual VIN inventory intake';
  end if;
  if normalized_condition_key !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or pg_catalog.char_length(normalized_condition_key) > 100 then
    raise exception using errcode = '22023', message = 'invalid inventory condition key';
  end if;
  if (normalized_duplicate_decision is null) <> (normalized_duplicate_reason is null)
    or normalized_duplicate_reason is not null
      and pg_catalog.char_length(normalized_duplicate_reason) > 2000 then
    raise exception using errcode = '22023', message = 'invalid manual duplicate decision';
  end if;
  if normalized_duplicate_decision is not null and normalized_duplicate_decision not in (
    'reuse_existing_vehicle', 'reacquire_existing_vehicle', 'override_open_duplicate'
  ) then
    raise exception using errcode = '22023', message = 'invalid manual duplicate decision';
  end if;
  if p_model_year is not null and p_model_year not between 1886 and 2200
    or p_cylinders is not null and p_cylinders not between 1 and 64
    or p_horsepower is not null and p_horsepower not between 1 and 10000 then
    raise exception using errcode = '22023', message = 'invalid manual vehicle fact';
  end if;
  if p_model_year is null or normalized_make is null or normalized_model is null then
    raise exception using
      errcode = '22023',
      message = 'manual intake requires model year, make, and model';
  end if;
  if normalized_make is not null and pg_catalog.char_length(normalized_make) > 100
    or normalized_model is not null and pg_catalog.char_length(normalized_model) > 100
    or normalized_body_type is not null and pg_catalog.char_length(normalized_body_type) > 200
    or normalized_drivetrain is not null and pg_catalog.char_length(normalized_drivetrain) > 100
    or normalized_fuel_type is not null and pg_catalog.char_length(normalized_fuel_type) > 100
    or normalized_transmission is not null and pg_catalog.char_length(normalized_transmission) > 200
    or normalized_trim_name is not null and pg_catalog.char_length(normalized_trim_name) > 200 then
    raise exception using errcode = '22023', message = 'manual vehicle text is too long';
  end if;
  if p_engine_liters is not null then
    if pg_catalog.btrim(p_engine_liters) !~ '^\d{1,2}(?:\.\d{1,3})?$' then
      raise exception using errcode = '22023', message = 'invalid manual engine displacement';
    end if;
    normalized_engine_liters := pg_catalog.btrim(p_engine_liters)::numeric(6, 3);
    if normalized_engine_liters not between 0.001 and 99.999 then
      raise exception using errcode = '22023', message = 'invalid manual engine displacement';
    end if;
  end if;
  if (p_odometer_value is null) <> (p_odometer_unit is null)
    or p_odometer_value is not null and p_odometer_value < 0
    or p_odometer_unit is not null and p_odometer_unit not in ('km', 'mi')
    or normalized_currency !~ '^[A-Z]{3}$'
    or p_advertised_price_minor is not null and p_advertised_price_minor < 0 then
    raise exception using errcode = '22023', message = 'invalid manual inventory details';
  end if;
  if normalized_public_notes is not null and pg_catalog.char_length(normalized_public_notes) > 4000
    or p_request_id is not null and pg_catalog.char_length(p_request_id) > 200
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid manual intake metadata';
  end if;

  manual_facts_snapshot := pg_catalog.jsonb_build_object(
    'model_year', p_model_year, 'make', normalized_make, 'model', normalized_model,
    'body_type', normalized_body_type, 'cylinders', p_cylinders,
    'drivetrain', normalized_drivetrain,
    'engine_liters', case when normalized_engine_liters is null then null
      else pg_catalog.trim_scale(normalized_engine_liters)::text end,
    'fuel_type', normalized_fuel_type, 'horsepower', p_horsepower,
    'transmission', normalized_transmission, 'trim_name', normalized_trim_name
  );
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'vin_decode_request_id', p_vin_decode_request_id,
      'expected_request_version', p_expected_request_version,
      'stock_definition_id', p_stock_definition_id,
      'location_id', p_location_id,
      'condition_key', normalized_condition_key,
      'facts_confirmed', p_facts_confirmed,
      'manual_reason', normalized_manual_reason,
      'duplicate_decision', normalized_duplicate_decision,
      'duplicate_reason', normalized_duplicate_reason,
      'manual_facts', manual_facts_snapshot,
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
      p_workspace_id::text || E'\x1fvin_manual_inventory_intake_key\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );
  select intake.* into existing_intake
  from public.vin_manual_inventory_intakes intake
  where intake.workspace_id = p_workspace_id
    and intake.actor_user_id = actor_user_id
    and intake.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_intake.command_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505', message = 'manual VIN intake idempotency key was used for a different request';
    end if;
    return query
    select existing_intake.id, existing_intake.vin_decode_request_id,
      existing_intake.consumed_request_version, existing_intake.terminal_job_id,
      existing_intake.inventory_unit_id, existing_intake.vehicle_id,
      unit.stock_number::text, existing_intake.audit_event_id,
      existing_intake.outbox_event_id,
      coalesce(link.linked_existing_open_unit, false), true
    from public.inventory_units unit
    left join public.vin_inventory_intake_links link
      on link.workspace_id = existing_intake.workspace_id
     and link.id = existing_intake.link_receipt_id
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
  select request.* into target_request
  from public.vin_decode_requests request
  where request.workspace_id = p_workspace_id
    and request.id = p_vin_decode_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'VIN request was not found';
  end if;
  if target_request.status <> 'pending' then
    raise exception using errcode = '55000', message = 'successful VIN requests require confirmed-result intake';
  end if;
  if target_request.consumed_at is not null then
    raise exception using errcode = '23505', message = 'VIN request was already consumed';
  end if;
  if target_request.version <> p_expected_request_version then
    raise exception using errcode = '40001', message = 'VIN request version conflict';
  end if;
  if exists (
    select 1 from public.vin_decode_results result
    where result.workspace_id = p_workspace_id
      and result.vin_decode_request_id = target_request.id
  ) then
    raise exception using errcode = '55000', message = 'manual intake cannot replace a provider result';
  end if;

  select job.* into terminal_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.job_type = 'inventory.vin_decode'
    and job.entity_type = 'vin_decode_request'
    and job.entity_id = target_request.id
  order by job.created_at desc, job.id desc
  limit 1
  for update;
  if not found or terminal_job.status <> 'dead_letter' then
    raise exception using
      errcode = '55000',
      message = 'manual intake requires the authoritative latest VIN job to be dead letter';
  end if;

  failure_snapshot := pg_catalog.jsonb_build_object(
    'job_id', terminal_job.id,
    'attempts_started', terminal_job.attempts_started,
    'max_attempts', terminal_job.max_attempts,
    'last_error_classification', terminal_job.last_error_classification,
    'last_error_code', terminal_job.last_error_code,
    'completed_at', terminal_job.completed_at,
    'job_version', terminal_job.version
  );

  select resolved.* into resolved_inventory
  from app.resolve_inventory_unit_for_vin_intake(
    p_workspace_id, target_request.id, p_stock_definition_id, p_location_id,
    normalized_condition_key, 'vin-manual-intake/' || target_request.id::text,
    true, normalized_duplicate_decision, normalized_duplicate_reason,
    p_model_year, normalized_make, normalized_model, normalized_body_type,
    p_cylinders, normalized_drivetrain, normalized_engine_liters,
    normalized_fuel_type, p_horsepower, normalized_transmission,
    normalized_trim_name, p_acquisition_date, p_odometer_value,
    p_odometer_unit, normalized_currency, p_advertised_price_minor,
    normalized_public_notes, p_request_id, p_correlation_id
  ) resolved;

  insert into public.vin_inventory_intake_links (
    id, workspace_id, vin_decode_request_id, inventory_unit_id, vehicle_id,
    intake_kind, linked_existing_open_unit, location_id, condition_key,
    actor_user_id
  ) values (
    new_link_receipt_id, p_workspace_id, target_request.id,
    resolved_inventory.inventory_unit_id, resolved_inventory.vehicle_id,
    'manual_dead_letter', resolved_inventory.linked_existing_open_unit,
    p_location_id, normalized_condition_key, actor_user_id
  );

  next_request_version := target_request.version + 1;
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    case when resolved_inventory.linked_existing_open_unit
      then 'inventory_unit.manual_vin_link_confirmed'
      else 'inventory_unit.manual_intake_confirmed' end,
    resolved_inventory.inventory_unit_id,
    resolved_inventory.inventory_version,
    -- Reference-only payload: no manual facts, provider error, or reason.
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', resolved_inventory.inventory_unit_id,
      'vehicleId', resolved_inventory.vehicle_id,
      'vinDecodeRequestId', target_request.id,
      'vinManualInventoryIntakeId', new_intake_id,
      'vinInventoryIntakeLinkId', new_link_receipt_id,
      'terminalJobId', terminal_job.id
    ),
    actor_user_id,
    p_correlation_id
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => case when resolved_inventory.linked_existing_open_unit
      then 'inventory_unit.manual_vin_link_confirmed'
      else 'inventory_unit.manual_intake_confirmed' end,
    p_entity_type => 'inventory_unit',
    p_entity_id => resolved_inventory.inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'vehicle_id', resolved_inventory.vehicle_id,
      'stock_number', resolved_inventory.stock_number,
      'location_id', p_location_id,
      'condition_key', normalized_condition_key,
      'manual_facts_confirmed', true,
      'duplicate_decision', resolved_inventory.duplicate_decision,
      'linked_existing_open_unit', resolved_inventory.linked_existing_open_unit,
      'approved_for_intake', true
    ),
    p_reason => normalized_manual_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'vin_manual_inventory_intake_id', new_intake_id,
      'vin_inventory_intake_link_id', new_link_receipt_id,
      'vin_decode_request_id', target_request.id,
      'terminal_job_id', terminal_job.id,
      'outbox_event_id', new_outbox_event_id
    )
  );

  insert into public.vin_manual_inventory_intakes (
    id, workspace_id, vin_decode_request_id, terminal_job_id, link_receipt_id,
    inventory_unit_id, vehicle_id, location_id, condition_key,
    stock_definition_id, manual_facts, manual_reason, duplicate_decision,
    duplicate_reason, terminal_failure_snapshot, idempotency_key,
    command_fingerprint, consumed_request_version, actor_user_id,
    audit_event_id, outbox_event_id, request_id, correlation_id
  ) values (
    new_intake_id, p_workspace_id, target_request.id, terminal_job.id,
    new_link_receipt_id, resolved_inventory.inventory_unit_id,
    resolved_inventory.vehicle_id, p_location_id, normalized_condition_key,
    p_stock_definition_id, manual_facts_snapshot, normalized_manual_reason,
    resolved_inventory.duplicate_decision, normalized_duplicate_reason,
    failure_snapshot, normalized_idempotency_key, request_fingerprint,
    next_request_version, actor_user_id, new_audit_event_id,
    new_outbox_event_id, p_request_id, p_correlation_id
  );

  update public.vin_decode_requests request
  set consumed_at = pg_catalog.statement_timestamp(),
      consumed_by_manual_inventory_intake_id = new_intake_id,
      version = next_request_version
  where request.workspace_id = p_workspace_id
    and request.id = target_request.id;

  return query select new_intake_id, target_request.id, next_request_version,
    terminal_job.id, resolved_inventory.inventory_unit_id,
    resolved_inventory.vehicle_id, resolved_inventory.stock_number,
    new_audit_event_id, new_outbox_event_id,
    resolved_inventory.linked_existing_open_unit, false;
end;
$$;

alter table public.inventory_condition_definitions enable row level security;
alter table public.inventory_condition_definitions force row level security;
alter table public.vin_inventory_intake_links enable row level security;
alter table public.vin_inventory_intake_links force row level security;
alter table public.vin_manual_inventory_intakes enable row level security;
alter table public.vin_manual_inventory_intakes force row level security;

create policy inventory_condition_definitions_select
on public.inventory_condition_definitions
for select to authenticated
using (
  app.has_permission(workspace_id, 'workspace.read')
  or app.has_permission(workspace_id, 'inventory.read')
);

revoke all on table
  public.inventory_condition_definitions,
  public.vin_inventory_intake_links,
  public.vin_manual_inventory_intakes
from public, anon, authenticated, service_role;
grant select on table public.inventory_condition_definitions to authenticated;
grant select on table
  public.inventory_condition_definitions,
  public.vin_inventory_intake_links,
  public.vin_manual_inventory_intakes
to service_role;

revoke all on function app.resolve_inventory_unit_for_vin_intake(
  uuid, uuid, uuid, uuid, text, text, boolean, text, text, integer, text,
  text, text, integer, text, numeric, text, integer, text, text, date,
  bigint, text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.create_inventory_unit_from_vin_decode(
  uuid, uuid, uuid, bigint, uuid, uuid, text, text, boolean, integer, text,
  text, text, integer, text, text, text, integer, text, text, date, bigint,
  text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.create_inventory_unit_from_vin_decode(
  uuid, uuid, uuid, bigint, uuid, uuid, text, text, boolean, integer, text,
  text, text, integer, text, text, text, integer, text, text, date, bigint,
  text, text, bigint, text, text, uuid
) to authenticated;
revoke all on function app.create_inventory_unit_from_failed_vin_decode(
  uuid, uuid, bigint, uuid, uuid, text, text, boolean, text, text, text,
  integer, text, text, text, integer, text, text, text, integer, text, text,
  date, bigint, text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.create_inventory_unit_from_failed_vin_decode(
  uuid, uuid, bigint, uuid, uuid, text, text, boolean, text, text, text,
  integer, text, text, text, integer, text, text, text, integer, text, text,
  date, bigint, text, text, bigint, text, text, uuid
) to authenticated;

comment on table public.inventory_condition_definitions is
  'Workspace-owned allowlist of inventory condition keys accepted by authoritative intake and detail commands.';
comment on table public.vin_inventory_intake_links is
  'Append-only one-request/one-unit VIN intake linkage; independently reviewed requests may reference the same open holding without another stock allocation.';
comment on table public.vin_manual_inventory_intakes is
  'Service-only append-only provenance for explicitly confirmed manual facts after the authoritative VIN job dead-letters.';
comment on function app.create_inventory_unit_from_vin_decode(
  uuid, uuid, uuid, bigint, uuid, uuid, text, text, boolean, integer, text,
  text, text, integer, text, text, text, integer, text, text, date, bigint,
  text, text, bigint, text, text, uuid
) is
  'Canonical confirmed-decode intake requiring active location, configured condition, current duplicate state, exact money, immutable provenance, audit, and outbox evidence.';
comment on function app.create_inventory_unit_from_failed_vin_decode(
  uuid, uuid, bigint, uuid, uuid, text, text, boolean, text, text, text,
  integer, text, text, text, integer, text, text, text, integer, text, text,
  date, bigint, text, text, bigint, text, text, uuid
) is
  'Canonical manual-facts intake available only after the latest durable VIN job dead-letters; preserves failure history and emits reference-only outbox evidence.';
