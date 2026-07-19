-- VYN-INV-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-JOB-001,
-- VYN-API-001, T-INV-001, T-INV-003, T-TEN-001, T-RBAC-001, T-AUD-001
-- M2-INV-AC-001, M2-INV-AC-002, M2-INV-AC-003, M2-INV-AC-004,
-- M2-INV-AC-010, M2-INV-AC-011
-- Durable, provider-neutral VIN decoding. A decode request never allocates a
-- stock number or creates an inventory unit. Provider results are immutable
-- suggestions until a later, separately authorized inventory command applies
-- them.

alter table public.vehicles
  add column body_type text check (
    body_type is null or (
      pg_catalog.btrim(body_type) <> ''
      and pg_catalog.char_length(body_type) <= 200
    )
  ),
  add column cylinders smallint check (
    cylinders is null or cylinders between 1 and 64
  ),
  add column drivetrain text check (
    drivetrain is null or (
      pg_catalog.btrim(drivetrain) <> ''
      and pg_catalog.char_length(drivetrain) <= 100
    )
  ),
  add column engine_displacement_liters numeric(6, 3) check (
    engine_displacement_liters is null
    or engine_displacement_liters between 0.001 and 99.999
  ),
  add column fuel_type text check (
    fuel_type is null or (
      pg_catalog.btrim(fuel_type) <> ''
      and pg_catalog.char_length(fuel_type) <= 100
    )
  ),
  add column horsepower integer check (
    horsepower is null or horsepower between 1 and 10000
  ),
  add column transmission text check (
    transmission is null or (
      pg_catalog.btrim(transmission) <> ''
      and pg_catalog.char_length(transmission) <= 200
    )
  ),
  add column trim_name text check (
    trim_name is null or (
      pg_catalog.btrim(trim_name) <> ''
      and pg_catalog.char_length(trim_name) <= 200
    )
  );

create table public.vin_decode_requests (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vin extensions.citext not null,
  model_year_hint smallint check (model_year_hint between 1886 and 2200),
  status text not null default 'pending'
    check (status in ('pending', 'succeeded')),
  initial_job_id uuid not null,
  initial_outbox_event_id uuid not null,
  requested_by uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  command_fingerprint text not null
    check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  request_id text check (
    request_id is null or pg_catalog.char_length(request_id) <= 200
  ),
  correlation_id uuid not null,
  version bigint not null default 1 check (version > 0),
  requested_at timestamptz not null default pg_catalog.statement_timestamp(),
  completed_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, initial_job_id),
  unique (workspace_id, initial_outbox_event_id),
  unique (workspace_id, requested_by, idempotency_key),
  foreign key (workspace_id, initial_job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, initial_outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  constraint vin_decode_requests_vin_syntax_check check (
    pg_catalog.upper(vin::text) ~ '^[A-HJ-NPR-Z0-9]{17}$'
  ),
  constraint vin_decode_requests_status_shape_check check (
    (status = 'pending' and completed_at is null)
    or (status = 'succeeded' and completed_at is not null)
  )
);

create index vin_decode_requests_workspace_time_idx
  on public.vin_decode_requests (workspace_id, requested_at desc, id);
create index vin_decode_requests_workspace_vin_idx
  on public.vin_decode_requests (workspace_id, vin, requested_at desc, id);

create table public.vin_decode_results (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vin_decode_request_id uuid not null,
  provider_key text not null check (
    provider_key ~ '^[a-z][a-z0-9_]{1,63}$'
  ),
  provider_version text not null check (
    pg_catalog.btrim(provider_version) <> ''
    and pg_catalog.char_length(provider_version) <= 100
  ),
  decoded_at timestamptz not null,
  raw_response jsonb not null check (
    pg_catalog.jsonb_typeof(raw_response) = 'object'
    and pg_catalog.octet_length(raw_response::text) <= 1000000
  ),
  warnings jsonb not null default '[]'::jsonb
    check (pg_catalog.jsonb_typeof(warnings) = 'array'),
  model_year smallint check (model_year between 1886 and 2200),
  make text check (
    make is null or (
      pg_catalog.btrim(make) <> '' and pg_catalog.char_length(make) <= 100
    )
  ),
  model text check (
    model is null or (
      pg_catalog.btrim(model) <> '' and pg_catalog.char_length(model) <= 100
    )
  ),
  body_type text check (
    body_type is null or (
      pg_catalog.btrim(body_type) <> ''
      and pg_catalog.char_length(body_type) <= 200
    )
  ),
  cylinders smallint check (cylinders is null or cylinders between 1 and 64),
  drivetrain text check (
    drivetrain is null or (
      pg_catalog.btrim(drivetrain) <> ''
      and pg_catalog.char_length(drivetrain) <= 100
    )
  ),
  engine_displacement_liters numeric(6, 3) check (
    engine_displacement_liters is null
    or engine_displacement_liters between 0.001 and 99.999
  ),
  fuel_type text check (
    fuel_type is null or (
      pg_catalog.btrim(fuel_type) <> ''
      and pg_catalog.char_length(fuel_type) <= 100
    )
  ),
  horsepower integer check (
    horsepower is null or horsepower between 1 and 10000
  ),
  transmission text check (
    transmission is null or (
      pg_catalog.btrim(transmission) <> ''
      and pg_catalog.char_length(transmission) <= 200
    )
  ),
  trim_name text check (
    trim_name is null or (
      pg_catalog.btrim(trim_name) <> ''
      and pg_catalog.char_length(trim_name) <= 200
    )
  ),
  result_fingerprint text not null
    check (result_fingerprint ~ '^[a-f0-9]{64}$'),
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, vin_decode_request_id),
  unique (workspace_id, audit_event_id),
  unique (workspace_id, outbox_event_id),
  foreign key (workspace_id, vin_decode_request_id)
    references public.vin_decode_requests (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict
);

create table public.vin_duplicate_candidates (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vin_decode_request_id uuid not null,
  vehicle_id uuid not null,
  inventory_unit_id uuid,
  candidate_kind text not null check (
    candidate_kind in ('open_inventory', 'historical_inventory', 'vehicle_only')
  ),
  inventory_status_snapshot text check (
    inventory_status_snapshot is null
    or inventory_status_snapshot in ('draft', 'active', 'pending', 'closed', 'archived')
  ),
  stock_number_snapshot text check (
    stock_number_snapshot is null or (
      pg_catalog.btrim(stock_number_snapshot) <> ''
      and pg_catalog.char_length(stock_number_snapshot) <= 200
    )
  ),
  observed_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, vin_decode_request_id)
    references public.vin_decode_requests (workspace_id, id) on delete restrict,
  foreign key (workspace_id, vehicle_id)
    references public.vehicles (workspace_id, id) on delete restrict,
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id) on delete restrict,
  constraint vin_duplicate_candidates_shape_check check (
    (
      candidate_kind = 'vehicle_only'
      and inventory_unit_id is null
      and inventory_status_snapshot is null
      and stock_number_snapshot is null
    )
    or (
      candidate_kind = 'open_inventory'
      and inventory_unit_id is not null
      and inventory_status_snapshot in ('draft', 'active', 'pending')
      and stock_number_snapshot is not null
    )
    or (
      candidate_kind = 'historical_inventory'
      and inventory_unit_id is not null
      and inventory_status_snapshot in ('closed', 'archived')
      and stock_number_snapshot is not null
    )
  )
);

create index vin_duplicate_candidates_request_idx
  on public.vin_duplicate_candidates (
    workspace_id,
    vin_decode_request_id,
    candidate_kind,
    observed_at,
    id
  );

create table public.vin_duplicate_reviews (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  vin_decode_request_id uuid not null,
  vehicle_id uuid not null,
  decision text not null check (
    decision in (
      'reuse_existing_vehicle',
      'reacquire_existing_vehicle',
      'override_open_duplicate'
    )
  ),
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  strong_auth_used boolean not null,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  command_fingerprint text not null
    check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  request_id text check (
    request_id is null or pg_catalog.char_length(request_id) <= 200
  ),
  correlation_id uuid not null,
  reviewed_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, vin_decode_request_id),
  unique (workspace_id, actor_user_id, idempotency_key),
  unique (workspace_id, audit_event_id),
  unique (workspace_id, outbox_event_id),
  foreign key (workspace_id, vin_decode_request_id)
    references public.vin_decode_requests (workspace_id, id) on delete restrict,
  foreign key (workspace_id, vehicle_id)
    references public.vehicles (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  check (strong_auth_used = (decision = 'override_open_duplicate'))
);

create function app.prevent_vin_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'VIN decode result and review history is append-only';
end;
$$;

create trigger vin_decode_results_immutable
before update or delete on public.vin_decode_results
for each row execute function app.prevent_vin_history_mutation();
create trigger vin_duplicate_candidates_immutable
before update or delete on public.vin_duplicate_candidates
for each row execute function app.prevent_vin_history_mutation();
create trigger vin_duplicate_reviews_immutable
before update or delete on public.vin_duplicate_reviews
for each row execute function app.prevent_vin_history_mutation();

create function app.append_vin_outbox_event(
  p_workspace_id uuid,
  p_event_name text,
  p_vin_decode_request_id uuid,
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
  event_id uuid;
begin
  if p_correlation_id is null
    or p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or app.job_payload_contains_forbidden_key(p_payload) then
    raise exception using
      errcode = '23514',
      message = 'VIN outbox metadata is invalid';
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
    correlation_id,
    causation_id
  ) values (
    p_workspace_id,
    p_event_name,
    'vin_decode_request',
    p_vin_decode_request_id,
    p_aggregate_version,
    1,
    p_payload,
    p_actor_user_id,
    p_correlation_id,
    p_causation_id
  )
  returning id into event_id;

  return event_id;
end;
$$;

create function app.request_vin_decode_job(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_vin text,
  p_model_year_hint integer,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  vin_decode_request_id uuid,
  job_id uuid,
  outbox_event_id uuid,
  job_status text,
  duplicate_candidate_count integer,
  aggregate_version bigint,
  audit_event_id uuid,
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
  request_fingerprint text;
  existing_request public.vin_decode_requests%rowtype;
  existing_job public.jobs%rowtype;
  new_request_id uuid := pg_catalog.gen_random_uuid();
  new_job_id uuid;
  new_outbox_event_id uuid;
  new_job_status text;
  job_created boolean;
  candidate_count integer;
  new_audit_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.create'
  );
  normalized_idempotency_key := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
  normalized_vin := pg_catalog.upper(pg_catalog.btrim(coalesce(p_vin, '')));

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid VIN idempotency key';
  end if;
  if normalized_vin !~ '^[A-HJ-NPR-Z0-9]{17}$' then
    raise exception using errcode = '22023', message = 'invalid VIN';
  end if;
  if p_model_year_hint is not null
    and p_model_year_hint not between 1886 and 2200 then
    raise exception using errcode = '22023', message = 'invalid VIN model-year hint';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'invalid request ID';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'vin', normalized_vin,
      'model_year_hint', p_model_year_hint
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fvin_decode\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select request.*
    into existing_request
  from public.vin_decode_requests request
  where request.workspace_id = p_workspace_id
    and request.requested_by = actor_user_id
    and request.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_request.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'VIN idempotency key was used for a different request';
    end if;

    select queued.*
      into existing_job
    from public.jobs queued
    where queued.workspace_id = p_workspace_id
      and queued.id = existing_request.initial_job_id;

    return query
    select
      existing_request.id,
      existing_request.initial_job_id,
      existing_request.initial_outbox_event_id,
      existing_job.status,
      (
        select pg_catalog.count(*)::integer
        from public.vin_duplicate_candidates candidate
        where candidate.workspace_id = p_workspace_id
          and candidate.vin_decode_request_id = existing_request.id
      ),
      existing_request.version,
      (
        select audit.id
        from public.audit_events audit
        where audit.workspace_id = p_workspace_id
          and audit.entity_type = 'vin_decode_request'
          and audit.entity_id = existing_request.id
          and audit.action = 'inventory.vin_decode_requested'
        order by audit.occurred_at, audit.id
        limit 1
      ),
      true;
    return;
  end if;

  select queued.outbox_event_id, queued.job_id, queued.created, queued.job_status
    into new_outbox_event_id, new_job_id, job_created, new_job_status
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'inventory.vin_decode_requested',
    p_aggregate_type => 'vin_decode_request',
    p_aggregate_id => new_request_id,
    p_aggregate_version => 1,
    p_job_type => 'inventory.vin_decode',
    p_entity_type => 'vin_decode_request',
    p_entity_id => new_request_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'request_id', new_request_id,
      'vin', normalized_vin,
      'model_year_hint', p_model_year_hint
    ),
    p_idempotency_key => 'vin-decode:' || new_request_id::text,
    p_correlation_id => p_correlation_id,
    p_actor_user_id => actor_user_id,
    p_priority => 60,
    p_max_attempts => 8,
    p_backoff_base_seconds => 30,
    p_backoff_max_seconds => 3600,
    p_request_id => p_request_id
  ) queued;

  if not job_created or new_job_status <> 'queued' then
    raise exception using errcode = '55000', message = 'VIN job enqueue invariant failed';
  end if;

  insert into public.vin_decode_requests (
    id,
    workspace_id,
    vin,
    model_year_hint,
    initial_job_id,
    initial_outbox_event_id,
    requested_by,
    idempotency_key,
    command_fingerprint,
    request_id,
    correlation_id
  ) values (
    new_request_id,
    p_workspace_id,
    normalized_vin,
    p_model_year_hint,
    new_job_id,
    new_outbox_event_id,
    actor_user_id,
    normalized_idempotency_key,
    request_fingerprint,
    p_request_id,
    p_correlation_id
  );

  insert into public.vin_duplicate_candidates (
    workspace_id,
    vin_decode_request_id,
    vehicle_id,
    inventory_unit_id,
    candidate_kind,
    inventory_status_snapshot,
    stock_number_snapshot
  )
  select
    p_workspace_id,
    new_request_id,
    vehicle.id,
    unit.id,
    case
      when unit.id is null then 'vehicle_only'
      when unit.status in ('draft', 'active', 'pending') then 'open_inventory'
      else 'historical_inventory'
    end,
    unit.status,
    unit.stock_number::text
  from public.vehicles vehicle
  left join public.inventory_units unit
    on unit.workspace_id = vehicle.workspace_id
   and unit.vehicle_id = vehicle.id
  where vehicle.workspace_id = p_workspace_id
    and vehicle.vin = normalized_vin;

  get diagnostics candidate_count = row_count;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory.vin_decode_requested',
    p_entity_type => 'vin_decode_request',
    p_entity_id => new_request_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'pending',
      'duplicate_candidate_count', candidate_count
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_metadata => pg_catalog.jsonb_build_object(
      'job_id', new_job_id,
      'outbox_event_id', new_outbox_event_id,
      'model_year_hint_supplied', p_model_year_hint is not null
    )
  );

  return query
  select
    new_request_id,
    new_job_id,
    new_outbox_event_id,
    new_job_status,
    candidate_count,
    1::bigint,
    new_audit_event_id,
    false;
end;
$$;

create function app.complete_vin_decode_request(
  p_workspace_id uuid,
  p_vin_decode_request_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_provider_key text,
  p_provider_version text,
  p_decoded_at timestamptz,
  p_raw_response jsonb,
  p_warnings jsonb,
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
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  vin_decode_result_id uuid,
  decode_status text,
  duplicate_candidate_count integer,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_request public.vin_decode_requests%rowtype;
  target_job public.jobs%rowtype;
  existing_result public.vin_decode_results%rowtype;
  normalized_engine_liters numeric(6, 3);
  normalized_warnings jsonb := coalesce(p_warnings, '[]'::jsonb);
  result_fingerprint text;
  new_result_id uuid := pg_catalog.gen_random_uuid();
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  candidate_count integer;
  next_version bigint;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_lease_token is null then
    raise exception using
      errcode = '22023',
      message = 'valid VIN worker lease identifiers are required';
  end if;
  if p_provider_key is distinct from 'nhtsa_vpic'
    or pg_catalog.btrim(coalesce(p_provider_version, '')) = ''
    or pg_catalog.char_length(p_provider_version) > 100 then
    raise exception using errcode = '22023', message = 'invalid VIN provider identity';
  end if;
  if p_decoded_at is null or p_correlation_id is null then
    raise exception using
      errcode = '23502',
      message = 'VIN decode time and correlation ID are required';
  end if;
  if p_raw_response is null
    or pg_catalog.jsonb_typeof(p_raw_response) <> 'object'
    or pg_catalog.octet_length(p_raw_response::text) > 1000000 then
    raise exception using errcode = '23514', message = 'invalid VIN raw response';
  end if;
  if pg_catalog.jsonb_typeof(normalized_warnings) <> 'array'
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(normalized_warnings) warning(value)
      where pg_catalog.jsonb_typeof(warning.value) <> 'string'
        or pg_catalog.char_length(warning.value #>> '{}') > 1000
    ) then
    raise exception using errcode = '23514', message = 'invalid VIN warning list';
  end if;
  if p_model_year is not null and p_model_year not between 1886 and 2200 then
    raise exception using errcode = '22023', message = 'invalid decoded model year';
  end if;
  if p_cylinders is not null and p_cylinders not between 1 and 64 then
    raise exception using errcode = '22023', message = 'invalid decoded cylinder count';
  end if;
  if p_horsepower is not null and p_horsepower not between 1 and 10000 then
    raise exception using errcode = '22023', message = 'invalid decoded horsepower';
  end if;
  if p_engine_liters is not null then
    if pg_catalog.btrim(p_engine_liters) !~ '^\d{1,2}(?:\.\d{1,3})?$' then
      raise exception using errcode = '22023', message = 'invalid decoded engine displacement';
    end if;
    normalized_engine_liters := pg_catalog.btrim(p_engine_liters)::numeric(6, 3);
    if normalized_engine_liters not between 0.001 and 99.999 then
      raise exception using errcode = '22023', message = 'invalid decoded engine displacement';
    end if;
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'invalid request ID';
  end if;

  select request.*
    into target_request
  from public.vin_decode_requests request
  where request.workspace_id = p_workspace_id
    and request.id = p_vin_decode_request_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'VIN request is unavailable';
  end if;

  select queued.*
    into target_job
  from public.jobs queued
  where queued.workspace_id = p_workspace_id
    and queued.id = p_job_id
  for update;

  if not found
    or target_job.job_type is distinct from 'inventory.vin_decode'
    or target_job.entity_type is distinct from 'vin_decode_request'
    or target_job.entity_id is distinct from target_request.id
    or target_job.payload_schema_version is distinct from 1
    or target_job.payload is distinct from pg_catalog.jsonb_build_object(
      'request_id', target_request.id,
      'vin', target_request.vin::text,
      'model_year_hint', target_request.model_year_hint
    )
    or target_job.correlation_id is distinct from p_correlation_id then
    raise exception using errcode = '23514', message = 'VIN job contract is invalid';
  end if;

  if target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp() then
    raise exception using
      errcode = '55000',
      message = 'only the matching active lease owner can record a VIN result';
  end if;

  select result.*
    into existing_result
  from public.vin_decode_results result
  where result.workspace_id = p_workspace_id
    and result.vin_decode_request_id = target_request.id;

  select pg_catalog.count(*)::integer
    into candidate_count
  from public.vin_duplicate_candidates candidate
  where candidate.workspace_id = p_workspace_id
    and candidate.vin_decode_request_id = target_request.id;

  if found and existing_result.id is not null then
    return query
    select
      existing_result.id,
      'succeeded'::text,
      candidate_count,
      target_request.version,
      existing_result.audit_event_id,
      existing_result.outbox_event_id,
      true;
    return;
  end if;

  result_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'provider_key', p_provider_key,
      'provider_version', p_provider_version,
      'decoded_at', p_decoded_at,
      'raw_response', p_raw_response,
      'warnings', normalized_warnings,
      'model_year', p_model_year,
      'make', p_make,
      'model', p_model,
      'body_type', p_body_type,
      'cylinders', p_cylinders,
      'drivetrain', p_drivetrain,
      'engine_displacement_liters', normalized_engine_liters,
      'fuel_type', p_fuel_type,
      'horsepower', p_horsepower,
      'transmission', p_transmission,
      'trim_name', p_trim_name
    )
  );
  next_version := target_request.version + 1;

  new_outbox_event_id := app.append_vin_outbox_event(
    p_workspace_id => p_workspace_id,
    p_event_name => 'inventory.vin_decode_succeeded',
    p_vin_decode_request_id => target_request.id,
    p_aggregate_version => next_version,
    p_payload => pg_catalog.jsonb_build_object(
      'vin_decode_request_id', target_request.id,
      'vin_decode_result_id', new_result_id,
      'provider_key', p_provider_key,
      'duplicate_candidate_count', candidate_count
    ),
    p_actor_user_id => null,
    p_correlation_id => p_correlation_id,
    p_causation_id => target_job.outbox_event_id
  );

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory.vin_decode_succeeded',
    p_entity_type => 'vin_decode_request',
    p_entity_id => target_request.id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object('status', target_request.status),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'succeeded',
      'provider_key', p_provider_key,
      'duplicate_candidate_count', candidate_count
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'job_id', target_job.id,
      'lease_owner', p_worker_id,
      'outbox_event_id', new_outbox_event_id,
      'mapped_fact_count',
        pg_catalog.num_nonnulls(
          p_model_year, p_make, p_model, p_body_type, p_cylinders,
          p_drivetrain, normalized_engine_liters, p_fuel_type,
          p_horsepower, p_transmission, p_trim_name
        )
    )
  );

  insert into public.vin_decode_results (
    id,
    workspace_id,
    vin_decode_request_id,
    provider_key,
    provider_version,
    decoded_at,
    raw_response,
    warnings,
    model_year,
    make,
    model,
    body_type,
    cylinders,
    drivetrain,
    engine_displacement_liters,
    fuel_type,
    horsepower,
    transmission,
    trim_name,
    result_fingerprint,
    audit_event_id,
    outbox_event_id
  ) values (
    new_result_id,
    p_workspace_id,
    target_request.id,
    p_provider_key,
    p_provider_version,
    p_decoded_at,
    p_raw_response,
    normalized_warnings,
    p_model_year,
    nullif(pg_catalog.btrim(p_make), ''),
    nullif(pg_catalog.btrim(p_model), ''),
    nullif(pg_catalog.btrim(p_body_type), ''),
    p_cylinders,
    nullif(pg_catalog.btrim(p_drivetrain), ''),
    normalized_engine_liters,
    nullif(pg_catalog.btrim(p_fuel_type), ''),
    p_horsepower,
    nullif(pg_catalog.btrim(p_transmission), ''),
    nullif(pg_catalog.btrim(p_trim_name), ''),
    result_fingerprint,
    new_audit_event_id,
    new_outbox_event_id
  );

  update public.vin_decode_requests request
  set status = 'succeeded',
      version = next_version,
      completed_at = pg_catalog.statement_timestamp()
  where request.workspace_id = p_workspace_id
    and request.id = target_request.id;

  return query
  select
    new_result_id,
    'succeeded'::text,
    candidate_count,
    next_version,
    new_audit_event_id,
    new_outbox_event_id,
    false;
end;
$$;

create function app.get_vin_decode_request(
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
    case when result.id is not null then 'succeeded' else latest_job.status end,
    latest_job.id,
    latest_job.status,
    latest_job.attempts_started,
    latest_job.max_attempts,
    case when latest_job.status = 'retry_wait' then latest_job.available_at else null end,
    latest_job.status in ('retry_wait', 'dead_letter'),
    latest_job.last_error_classification,
    latest_job.last_error_code,
    latest_job.review_required,
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

create function app.retry_vin_decode_job(
  p_workspace_id uuid,
  p_vin_decode_request_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  vin_decode_request_id uuid,
  job_id uuid,
  outbox_event_id uuid,
  job_status text,
  aggregate_version bigint,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_request public.vin_decode_requests%rowtype;
  source_job public.jobs%rowtype;
  existing_retry_job public.jobs%rowtype;
  existing_retry_audit public.audit_events%rowtype;
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  new_job_id uuid;
  new_outbox_event_id uuid;
  new_job_status text;
  job_created boolean;
  next_version bigint;
  new_audit_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.create'
  );
  if pg_catalog.char_length(normalized_reason) not between 1 and 2000
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, '')))
      not between 8 and 200
    or p_correlation_id is null then
    raise exception using
      errcode = '22023',
      message = 'VIN retry requires a safe reason and correlation ID';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fvin_retry\x1f'
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
  if target_request.consumed_at is not null then
    raise exception using errcode = '55000', message = 'consumed VIN requests cannot be retried';
  end if;

  select job.*
    into existing_retry_job
  from public.jobs job
  join public.outbox_events event
    on event.workspace_id = job.workspace_id
   and event.id = job.outbox_event_id
  where job.workspace_id = p_workspace_id
    and job.job_type = 'inventory.vin_decode'
    and job.idempotency_key = pg_catalog.btrim(p_idempotency_key)
    and event.actor_user_id = app.current_user_id();

  if found then
    select audit.*
      into existing_retry_audit
    from public.audit_events audit
    where audit.workspace_id = p_workspace_id
      and audit.entity_type = 'vin_decode_request'
      and audit.entity_id = p_vin_decode_request_id
      and audit.action = 'inventory.vin_decode_retry_requested'
      and audit.metadata ->> 'job_id' = existing_retry_job.id::text
    order by audit.occurred_at desc, audit.id desc
    limit 1;

    if existing_retry_job.entity_type <> 'vin_decode_request'
      or existing_retry_job.entity_id is distinct from p_vin_decode_request_id
      or not found
      or existing_retry_audit.reason is distinct from normalized_reason then
      raise exception using
        errcode = '23505',
        message = 'VIN retry idempotency key was used for a different request';
    end if;

    return query
    select
      p_vin_decode_request_id,
      existing_retry_job.id,
      existing_retry_job.outbox_event_id,
      existing_retry_job.status,
      (
        select request.version
        from public.vin_decode_requests request
        where request.workspace_id = p_workspace_id
          and request.id = p_vin_decode_request_id
      ),
      existing_retry_audit.id,
      true;
    return;
  end if;

  if target_request.status = 'succeeded' then
    raise exception using errcode = '55000', message = 'successful VIN requests cannot be retried';
  end if;

  select job.*
    into source_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.job_type = 'inventory.vin_decode'
    and job.entity_type = 'vin_decode_request'
    and job.entity_id = target_request.id
  order by job.created_at desc, job.id desc
  limit 1;

  if not found or source_job.status <> 'dead_letter' then
    raise exception using
      errcode = '55000',
      message = 'only a dead-letter VIN job can be manually retried';
  end if;

  next_version := target_request.version + 1;
  select queued.outbox_event_id, queued.job_id, queued.created, queued.job_status
    into new_outbox_event_id, new_job_id, job_created, new_job_status
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'inventory.vin_decode_retry_requested',
    p_aggregate_type => 'vin_decode_request',
    p_aggregate_id => target_request.id,
    p_aggregate_version => next_version,
    p_job_type => 'inventory.vin_decode',
    p_entity_type => 'vin_decode_request',
    p_entity_id => target_request.id,
    p_payload_schema_version => 1,
    p_payload => source_job.payload,
    p_idempotency_key => p_idempotency_key,
    p_correlation_id => p_correlation_id,
    p_causation_id => source_job.outbox_event_id,
    p_actor_user_id => actor_user_id,
    p_priority => source_job.priority,
    p_max_attempts => source_job.max_attempts,
    p_backoff_base_seconds => source_job.backoff_base_seconds,
    p_backoff_max_seconds => source_job.backoff_max_seconds,
    p_replay_of_job_id => source_job.id,
    p_request_id => p_request_id
  ) queued;

  if job_created then
    update public.vin_decode_requests request
    set version = next_version
    where request.workspace_id = p_workspace_id
      and request.id = target_request.id;

    new_audit_event_id := app.write_audit_event(
      p_workspace_id => p_workspace_id,
      p_action => 'inventory.vin_decode_retry_requested',
      p_entity_type => 'vin_decode_request',
      p_entity_id => target_request.id,
      p_actor_user_id => actor_user_id,
      p_actor_type => 'user',
      p_before_data => pg_catalog.jsonb_build_object('job_status', source_job.status),
      p_after_data => pg_catalog.jsonb_build_object('job_status', new_job_status),
      p_reason => normalized_reason,
      p_request_id => p_request_id,
      p_correlation_id => p_correlation_id,
      p_metadata => pg_catalog.jsonb_build_object(
        'source_job_id', source_job.id,
        'job_id', new_job_id,
        'outbox_event_id', new_outbox_event_id
      )
    );
  else
    select audit.id
      into new_audit_event_id
    from public.audit_events audit
    where audit.workspace_id = p_workspace_id
      and audit.entity_type = 'vin_decode_request'
      and audit.entity_id = target_request.id
      and audit.action = 'inventory.vin_decode_retry_requested'
      and audit.metadata ->> 'job_id' = new_job_id::text
    order by audit.occurred_at desc, audit.id desc
    limit 1;
    next_version := target_request.version;
  end if;

  return query
  select
    target_request.id,
    new_job_id,
    new_outbox_event_id,
    new_job_status,
    next_version,
    new_audit_event_id,
    not job_created;
end;
$$;

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
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_request public.vin_decode_requests%rowtype;
  existing_review public.vin_duplicate_reviews%rowtype;
  normalized_idempotency_key text := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
  normalized_decision text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_decision, '')));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  request_fingerprint text;
  matching_vehicle_id uuid;
  open_count integer;
  historical_count integer;
  total_inventory_count integer;
  new_review_id uuid := pg_catalog.gen_random_uuid();
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  next_version bigint;
  used_strong_auth boolean;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'inventory.create'
  );
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or pg_catalog.char_length(normalized_reason) not between 1 and 2000
    or normalized_decision not in (
      'reuse_existing_vehicle',
      'reacquire_existing_vehicle',
      'override_open_duplicate'
    )
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid VIN duplicate review';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'vin_decode_request_id', p_vin_decode_request_id,
      'decision', normalized_decision,
      'reason', normalized_reason
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fvin_duplicate_review\x1f'
        || p_vin_decode_request_id::text,
      0
    )
  );

  select review.*
    into existing_review
  from public.vin_duplicate_reviews review
  where review.workspace_id = p_workspace_id
    and review.actor_user_id = app.current_user_id()
    and review.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_review.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'VIN review idempotency key was used for a different decision';
    end if;
    return query
    select
      existing_review.id,
      existing_review.vin_decode_request_id,
      existing_review.vehicle_id,
      existing_review.decision,
      true,
      (
        select request.version
        from public.vin_decode_requests request
        where request.workspace_id = p_workspace_id
          and request.id = existing_review.vin_decode_request_id
      ),
      existing_review.audit_event_id,
      existing_review.outbox_event_id,
      true;
    return;
  end if;

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
    raise exception using
      errcode = '55000',
      message = 'VIN duplicate review requires a successful decode';
  end if;
  if exists (
    select 1
    from public.vin_duplicate_reviews review
    where review.workspace_id = p_workspace_id
      and review.vin_decode_request_id = target_request.id
  ) then
    raise exception using errcode = '23505', message = 'VIN request was already reviewed';
  end if;

  select vehicle.id
    into matching_vehicle_id
  from public.vehicles vehicle
  where vehicle.workspace_id = p_workspace_id
    and vehicle.vin = target_request.vin;

  if matching_vehicle_id is null then
    raise exception using errcode = '23514', message = 'VIN has no duplicate candidate';
  end if;

  select
    pg_catalog.count(*) filter (
      where unit.status in ('draft', 'active', 'pending')
    )::integer,
    pg_catalog.count(*) filter (
      where unit.status in ('closed', 'archived')
    )::integer,
    pg_catalog.count(*)::integer
    into open_count, historical_count, total_inventory_count
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.vehicle_id = matching_vehicle_id;

  if normalized_decision = 'reuse_existing_vehicle'
    and total_inventory_count <> 0 then
    raise exception using
      errcode = '23514',
      message = 'vehicle reuse decision requires a vehicle without inventory history';
  elsif normalized_decision = 'reacquire_existing_vehicle'
    and (open_count <> 0 or historical_count = 0) then
    raise exception using
      errcode = '23514',
      message = 'reacquisition requires historical inventory without an open unit';
  elsif normalized_decision = 'override_open_duplicate' then
    if open_count = 0 then
      raise exception using
        errcode = '23514',
        message = 'duplicate override requires an open inventory candidate';
    end if;
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
  end if;

  used_strong_auth := normalized_decision = 'override_open_duplicate';
  next_version := target_request.version + 1;
  new_outbox_event_id := app.append_vin_outbox_event(
    p_workspace_id => p_workspace_id,
    p_event_name => 'inventory.vin_duplicate_reviewed',
    p_vin_decode_request_id => target_request.id,
    p_aggregate_version => next_version,
    p_payload => pg_catalog.jsonb_build_object(
      'vin_decode_request_id', target_request.id,
      'vin_duplicate_review_id', new_review_id,
      'vehicle_id', matching_vehicle_id,
      'decision', normalized_decision
    ),
    p_actor_user_id => actor_user_id,
    p_correlation_id => p_correlation_id
  );

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory.vin_duplicate_reviewed',
    p_entity_type => 'vin_decode_request',
    p_entity_id => target_request.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'vehicle_id', matching_vehicle_id,
      'decision', normalized_decision,
      'approved_for_intake', true
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_metadata => pg_catalog.jsonb_build_object(
      'strong_auth_used', used_strong_auth,
      'outbox_event_id', new_outbox_event_id
    )
  );

  insert into public.vin_duplicate_reviews (
    id,
    workspace_id,
    vin_decode_request_id,
    vehicle_id,
    decision,
    reason,
    strong_auth_used,
    actor_user_id,
    idempotency_key,
    command_fingerprint,
    audit_event_id,
    outbox_event_id,
    request_id,
    correlation_id
  ) values (
    new_review_id,
    p_workspace_id,
    target_request.id,
    matching_vehicle_id,
    normalized_decision,
    normalized_reason,
    used_strong_auth,
    actor_user_id,
    normalized_idempotency_key,
    request_fingerprint,
    new_audit_event_id,
    new_outbox_event_id,
    p_request_id,
    p_correlation_id
  );

  update public.vin_decode_requests request
  set version = next_version
  where request.workspace_id = p_workspace_id
    and request.id = target_request.id;

  return query
  select
    new_review_id,
    target_request.id,
    matching_vehicle_id,
    normalized_decision,
    true,
    next_version,
    new_audit_event_id,
    new_outbox_event_id,
    false;
end;
$$;

alter table public.vin_decode_requests enable row level security;
alter table public.vin_decode_requests force row level security;
alter table public.vin_decode_results enable row level security;
alter table public.vin_decode_results force row level security;
alter table public.vin_duplicate_candidates enable row level security;
alter table public.vin_duplicate_candidates force row level security;
alter table public.vin_duplicate_reviews enable row level security;
alter table public.vin_duplicate_reviews force row level security;

-- Browser reads and writes use the narrow security-definer RPC projections.
-- There are deliberately no authenticated table policies or table grants, so
-- provider raw responses, command fingerprints, and idempotency keys cannot be
-- selected accidentally.
revoke all on table
  public.vin_decode_requests,
  public.vin_decode_results,
  public.vin_duplicate_candidates,
  public.vin_duplicate_reviews
from public, anon, authenticated, service_role;

grant select on
  public.vin_decode_requests,
  public.vin_decode_results,
  public.vin_duplicate_candidates,
  public.vin_duplicate_reviews
to service_role;

revoke all on function app.prevent_vin_history_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.append_vin_outbox_event(
  uuid, text, uuid, bigint, jsonb, uuid, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.request_vin_decode_job(
  uuid, text, text, integer, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.complete_vin_decode_request(
  uuid, uuid, uuid, text, uuid, text, text, timestamptz, jsonb, jsonb,
  integer, text, text, text, integer, text, text, text, integer, text, text,
  text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.get_vin_decode_request(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.retry_vin_decode_job(
  uuid, uuid, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.review_vin_duplicate_request(
  uuid, uuid, text, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.request_vin_decode_job(
  uuid, text, text, integer, text, uuid
) to authenticated;
grant execute on function app.get_vin_decode_request(uuid, uuid)
  to authenticated;
grant execute on function app.retry_vin_decode_job(
  uuid, uuid, text, text, text, uuid
) to authenticated;
grant execute on function app.review_vin_duplicate_request(
  uuid, uuid, text, text, text, text, uuid
) to authenticated;
grant execute on function app.complete_vin_decode_request(
  uuid, uuid, uuid, text, uuid, text, text, timestamptz, jsonb, jsonb,
  integer, text, text, text, integer, text, text, text, integer, text, text,
  text, uuid
) to service_role;

comment on table public.vin_decode_requests is
  'Workspace VIN decode request aggregate linked to its original durable outbox job; it never allocates stock.';
comment on table public.vin_decode_results is
  'Immutable provider response and mapped vehicle suggestions; raw data is service-only and not a browser projection.';
comment on table public.vin_duplicate_candidates is
  'Immutable same-workspace duplicate and reacquisition snapshot observed before provider traffic.';
comment on table public.vin_duplicate_reviews is
  'Append-only authorized duplicate decision; open-inventory override requires recent strong authentication.';
comment on column public.vehicles.trim_name is
  'Tenant-neutral vehicle trim name. The non-keyword column name is used consistently by search and API mappings.';
comment on function app.complete_vin_decode_request(
  uuid, uuid, uuid, text, uuid, text, text, timestamptz, jsonb, jsonb,
  integer, text, text, text, integer, text, text, text, integer, text, text,
  text, uuid
) is
  'Exact worker/lease-fenced persistence for immutable VIN provider results; generic job completion remains a separate idempotent step.';
