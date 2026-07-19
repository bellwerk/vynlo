-- VYN-JOB-001, VYN-OPS-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- M1-JOB-AC-001 through M1-JOB-AC-010
-- Forward-only transactional outbox and durable job foundation.

create function app.job_payload_contains_forbidden_key(candidate jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  item record;
  normalized_key text;
begin
  if pg_catalog.jsonb_typeof(candidate) = 'object' then
    for item in select entry.key, entry.value from pg_catalog.jsonb_each(candidate) entry loop
      normalized_key := pg_catalog.lower(
        pg_catalog.regexp_replace(item.key, '[^a-z0-9]', '', 'g')
      );

      if normalized_key ~ '(password|secret|token|apikey|credential|authorization|cookie|privatekey)' then
        return true;
      end if;

      if pg_catalog.jsonb_typeof(item.value) in ('object', 'array')
        and app.job_payload_contains_forbidden_key(item.value) then
        return true;
      end if;
    end loop;
  elsif pg_catalog.jsonb_typeof(candidate) = 'array' then
    for item in select element.value from pg_catalog.jsonb_array_elements(candidate) element loop
      if pg_catalog.jsonb_typeof(item.value) in ('object', 'array')
        and app.job_payload_contains_forbidden_key(item.value) then
        return true;
      end if;
    end loop;
  end if;

  return false;
end;
$$;

create function app.job_request_fingerprint(p_request jsonb)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(
      p_request::text,
      'sha256'
    ),
    'hex'
  );
$$;

create function app.job_retry_delay_seconds(
  failed_attempt_number integer,
  base_delay_seconds integer,
  maximum_delay_seconds integer,
  jitter_unit double precision
)
returns integer
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  delay_cap numeric;
begin
  if failed_attempt_number < 1
    or base_delay_seconds < 1
    or maximum_delay_seconds < base_delay_seconds
    or jitter_unit < 0
    or jitter_unit >= 1 then
    raise exception using
      errcode = '22023',
      message = 'invalid retry-backoff input';
  end if;

  delay_cap := least(
    maximum_delay_seconds::numeric,
    base_delay_seconds::numeric
      * pg_catalog.power(2::numeric, (failed_attempt_number - 1)::numeric)
  );

  -- Equal jitter keeps at least half the exponential delay while preventing a
  -- synchronized retry wave. The final value never exceeds the configured cap.
  return greatest(
    1,
    pg_catalog.floor((delay_cap / 2) + ((delay_cap / 2) * jitter_unit))::integer
  );
end;
$$;

create table public.outbox_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  event_name text not null
    check (event_name ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'),
  aggregate_type text not null
    check (aggregate_type ~ '^[a-z][a-z0-9_]*$'),
  aggregate_id uuid not null,
  aggregate_version bigint not null check (aggregate_version > 0),
  payload_schema_version integer not null check (payload_schema_version > 0),
  payload jsonb not null
    check (pg_catalog.jsonb_typeof(payload) = 'object'),
  actor_user_id uuid references auth.users (id) on delete restrict,
  correlation_id uuid not null,
  causation_id uuid,
  occurred_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  check (not app.job_payload_contains_forbidden_key(payload))
);

create index outbox_events_workspace_time_idx
  on public.outbox_events (workspace_id, occurred_at desc, id);
create index outbox_events_aggregate_idx
  on public.outbox_events (
    workspace_id,
    aggregate_type,
    aggregate_id,
    aggregate_version
  );
create index outbox_events_correlation_idx
  on public.outbox_events (workspace_id, correlation_id, occurred_at);

create table public.jobs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  outbox_event_id uuid not null,
  replay_of_job_id uuid,
  job_type text not null
    check (job_type ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'),
  entity_type text not null
    check (entity_type ~ '^[a-z][a-z0-9_]*$'),
  entity_id uuid not null,
  payload_schema_version integer not null check (payload_schema_version > 0),
  payload jsonb not null
    check (pg_catalog.jsonb_typeof(payload) = 'object'),
  idempotency_key text not null
    check (pg_catalog.btrim(idempotency_key) <> '')
    check (idempotency_key = pg_catalog.btrim(idempotency_key))
    check (pg_catalog.char_length(idempotency_key) <= 200),
  request_fingerprint text not null
    check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  status text not null default 'queued'
    check (status in (
      'queued',
      'running',
      'retry_wait',
      'succeeded',
      'dead_letter',
      'cancelled'
    )),
  priority smallint not null default 50 check (priority between 0 and 100),
  attempts_started integer not null default 0 check (attempts_started >= 0),
  max_attempts integer not null default 8 check (max_attempts between 1 and 32),
  backoff_base_seconds integer not null default 30
    check (backoff_base_seconds between 1 and 3600),
  backoff_max_seconds integer not null default 3600
    check (backoff_max_seconds between backoff_base_seconds and 86400),
  available_at timestamptz not null default pg_catalog.statement_timestamp(),
  lease_owner text,
  lease_token uuid,
  lease_expires_at timestamptz,
  heartbeat_at timestamptz,
  current_attempt_started_at timestamptz,
  first_started_at timestamptz,
  completed_at timestamptz,
  result_summary jsonb,
  last_error_classification text
    check (last_error_classification is null or last_error_classification in (
      'transient',
      'rate_limited',
      'permanent',
      'validation',
      'permission',
      'provider_auth',
      'unknown',
      'lease_expired'
    )),
  last_error_code text check (
    last_error_code is null or pg_catalog.char_length(last_error_code) <= 120
  ),
  last_error_detail_safe text check (
    last_error_detail_safe is null
    or pg_catalog.char_length(last_error_detail_safe) <= 2000
  ),
  last_provider_request_id text check (
    last_provider_request_id is null
    or pg_catalog.char_length(last_provider_request_id) <= 300
  ),
  review_required boolean not null default false,
  cancel_reason text check (
    cancel_reason is null or (
      pg_catalog.btrim(cancel_reason) <> ''
      and pg_catalog.char_length(cancel_reason) <= 1000
    )
  ),
  correlation_id uuid not null,
  causation_id uuid,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, job_type, idempotency_key),
  unique (workspace_id, outbox_event_id),
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, replay_of_job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  check (attempts_started <= max_attempts),
  check (not app.job_payload_contains_forbidden_key(payload)),
  check (
    result_summary is null
    or (
      pg_catalog.jsonb_typeof(result_summary) = 'object'
      and not app.job_payload_contains_forbidden_key(result_summary)
    )
  ),
  constraint jobs_state_shape_check check (
    (
      status = 'queued'
      and attempts_started = 0
      and lease_owner is null
      and lease_token is null
      and lease_expires_at is null
      and heartbeat_at is null
      and current_attempt_started_at is null
      and first_started_at is null
      and completed_at is null
      and review_required is false
      and cancel_reason is null
    )
    or (
      status = 'running'
      and attempts_started between 1 and max_attempts
      and pg_catalog.btrim(lease_owner) <> ''
      and lease_token is not null
      and lease_expires_at is not null
      and heartbeat_at is not null
      and current_attempt_started_at is not null
      and first_started_at is not null
      and heartbeat_at >= current_attempt_started_at
      and lease_expires_at > heartbeat_at
      and completed_at is null
      and review_required is false
      and cancel_reason is null
    )
    or (
      status = 'retry_wait'
      and attempts_started between 1 and max_attempts
      and lease_owner is null
      and lease_token is null
      and lease_expires_at is null
      and heartbeat_at is null
      and current_attempt_started_at is null
      and first_started_at is not null
      and completed_at is null
      and last_error_classification is not null
      and review_required is false
      and cancel_reason is null
    )
    or (
      status = 'succeeded'
      and attempts_started between 1 and max_attempts
      and lease_owner is null
      and lease_token is null
      and lease_expires_at is null
      and heartbeat_at is null
      and current_attempt_started_at is null
      and first_started_at is not null
      and completed_at is not null
      and review_required is false
      and cancel_reason is null
    )
    or (
      status = 'dead_letter'
      and attempts_started between 1 and max_attempts
      and lease_owner is null
      and lease_token is null
      and lease_expires_at is null
      and heartbeat_at is null
      and current_attempt_started_at is null
      and first_started_at is not null
      and completed_at is not null
      and last_error_classification is not null
      and cancel_reason is null
    )
    or (
      status = 'cancelled'
      and lease_owner is null
      and lease_token is null
      and lease_expires_at is null
      and heartbeat_at is null
      and current_attempt_started_at is null
      and completed_at is not null
      and review_required is false
      and cancel_reason is not null
    )
  )
);

create index jobs_claim_idx
  on public.jobs (priority desc, available_at, created_at, id)
  where status in ('queued', 'retry_wait');
create index jobs_expired_lease_idx
  on public.jobs (lease_expires_at, id)
  where status = 'running';
create index jobs_workspace_status_idx
  on public.jobs (workspace_id, status, updated_at desc, id);
create index jobs_workspace_entity_idx
  on public.jobs (workspace_id, entity_type, entity_id, created_at desc);
create index jobs_correlation_idx
  on public.jobs (workspace_id, correlation_id, created_at);

create table public.job_attempts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  job_id uuid not null,
  attempt_number integer not null check (attempt_number > 0),
  worker_id text not null
    check (pg_catalog.btrim(worker_id) <> '')
    check (pg_catalog.char_length(worker_id) <= 200),
  lease_token uuid not null unique,
  started_at timestamptz not null,
  finished_at timestamptz not null,
  outcome text not null
    check (outcome in (
      'succeeded',
      'retry_scheduled',
      'dead_lettered',
      'lease_expired'
    )),
  error_classification text
    check (error_classification is null or error_classification in (
      'transient',
      'rate_limited',
      'permanent',
      'validation',
      'permission',
      'provider_auth',
      'unknown',
      'lease_expired'
    )),
  error_code text check (
    error_code is null or pg_catalog.char_length(error_code) <= 120
  ),
  error_detail_safe text check (
    error_detail_safe is null
    or pg_catalog.char_length(error_detail_safe) <= 2000
  ),
  provider_request_id text check (
    provider_request_id is null
    or pg_catalog.char_length(provider_request_id) <= 300
  ),
  retry_at timestamptz,
  correlation_id uuid not null,
  causation_id uuid,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, job_id, attempt_number),
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  check (finished_at >= started_at),
  check (
    (outcome = 'succeeded' and error_classification is null and retry_at is null)
    or (
      outcome in ('retry_scheduled', 'dead_lettered', 'lease_expired')
      and error_classification is not null
    )
  ),
  check (outcome <> 'retry_scheduled' or retry_at is not null)
);

create index job_attempts_job_idx
  on public.job_attempts (workspace_id, job_id, attempt_number desc);
create index job_attempts_outcome_idx
  on public.job_attempts (workspace_id, outcome, finished_at desc);

create table public.job_admin_reviews (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  job_id uuid not null,
  reviewer_user_id uuid not null references auth.users (id) on delete restrict,
  decision text not null check (decision in ('acknowledged', 'replayed')),
  reason text not null
    check (pg_catalog.btrim(reason) <> '')
    check (pg_catalog.char_length(reason) <= 2000),
  replay_job_id uuid,
  correlation_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, replay_job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  check (
    (decision = 'acknowledged' and replay_job_id is null)
    or (decision = 'replayed' and replay_job_id is not null)
  )
);

create index job_admin_reviews_job_idx
  on public.job_admin_reviews (workspace_id, job_id, created_at desc);

create function app.prevent_job_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = pg_catalog.format('%I is append-only', tg_table_name);
end;
$$;

create function app.job_actor_has_permission(
  target_workspace_id uuid,
  target_user_id uuid,
  permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspace_memberships wm
    join public.user_profiles up
      on up.user_id = wm.user_id
     and up.status = 'active'
    join public.workspaces w
      on w.id = wm.workspace_id
     and w.status = 'active'
    join public.organizations o
      on o.id = w.organization_id
     and o.status = 'active'
    join public.membership_roles mr
      on mr.workspace_id = wm.workspace_id
     and mr.membership_id = wm.id
     and mr.status = 'active'
    join public.roles r
      on r.workspace_id = mr.workspace_id
     and r.id = mr.role_id
     and r.status = 'active'
    join public.role_permissions rp
      on rp.workspace_id = r.workspace_id
     and rp.role_id = r.id
     and rp.status = 'active'
    join public.permissions p
      on p.id = rp.permission_id
     and p.status = 'active'
    where wm.workspace_id = target_workspace_id
      and wm.user_id = target_user_id
      and wm.status = 'active'
      and p.key = permission_key
      and (p.workspace_id is null or p.workspace_id = target_workspace_id)
  );
$$;

create trigger outbox_events_immutable
before update or delete on public.outbox_events
for each row execute function app.prevent_job_history_mutation();

create trigger jobs_immutable_fields
before update on public.jobs
for each row execute function app.enforce_immutable_columns(
  'id',
  'workspace_id',
  'outbox_event_id',
  'replay_of_job_id',
  'job_type',
  'entity_type',
  'entity_id',
  'payload_schema_version',
  'payload',
  'idempotency_key',
  'request_fingerprint',
  'priority',
  'max_attempts',
  'backoff_base_seconds',
  'backoff_max_seconds',
  'correlation_id',
  'causation_id',
  'created_at'
);

create trigger jobs_prevent_hard_delete
before delete on public.jobs
for each row execute function app.prevent_hard_delete();

create trigger job_attempts_immutable
before update or delete on public.job_attempts
for each row execute function app.prevent_job_history_mutation();

create trigger job_admin_reviews_immutable
before update or delete on public.job_admin_reviews
for each row execute function app.prevent_job_history_mutation();

create function app.enqueue_outbox_job(
  p_workspace_id uuid,
  p_event_name text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_aggregate_version bigint,
  p_job_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload_schema_version integer,
  p_payload jsonb,
  p_idempotency_key text,
  p_correlation_id uuid,
  p_causation_id uuid default null,
  p_actor_user_id uuid default null,
  p_priority integer default 50,
  p_max_attempts integer default 8,
  p_available_at timestamptz default pg_catalog.statement_timestamp(),
  p_backoff_base_seconds integer default 30,
  p_backoff_max_seconds integer default 3600,
  p_replay_of_job_id uuid default null,
  p_request_id text default null
)
returns table (
  outbox_event_id uuid,
  job_id uuid,
  created boolean,
  job_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_job public.jobs%rowtype;
  new_outbox_event_id uuid;
  new_job_id uuid;
  fingerprint text;
  normalized_idempotency_key text;
begin
  normalized_idempotency_key := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );

  if normalized_idempotency_key = ''
    or pg_catalog.char_length(normalized_idempotency_key) > 200 then
    raise exception using
      errcode = '22023',
      message = 'invalid job idempotency key';
  end if;

  if not exists (
    select 1
    from public.workspaces w
    join public.organizations o on o.id = w.organization_id
    where w.id = p_workspace_id
      and w.status = 'active'
      and o.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'job workspace must be active';
  end if;

  if p_actor_user_id is not null and not exists (
    select 1
    from public.workspace_memberships wm
    join public.user_profiles up on up.user_id = wm.user_id
    where wm.workspace_id = p_workspace_id
      and wm.user_id = p_actor_user_id
      and wm.status = 'active'
      and up.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'job actor must be an active workspace member';
  end if;

  if p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or app.job_payload_contains_forbidden_key(p_payload) then
    raise exception using
      errcode = '23514',
      message = 'job payload must be an object without credential-bearing keys';
  end if;

  if p_priority not between 0 and 100
    or p_max_attempts not between 1 and 32
    or p_backoff_base_seconds not between 1 and 3600
    or p_backoff_max_seconds not between p_backoff_base_seconds and 86400 then
    raise exception using
      errcode = '22023',
      message = 'invalid job scheduling policy';
  end if;

  if p_available_at is null or p_correlation_id is null then
    raise exception using
      errcode = '23502',
      message = 'job availability and correlation ID are required';
  end if;

  if p_replay_of_job_id is not null and not exists (
    select 1
    from public.jobs original
    where original.workspace_id = p_workspace_id
      and original.id = p_replay_of_job_id
      and original.status = 'dead_letter'
  ) then
    raise exception using
      errcode = '23514',
      message = 'replay source must be a dead-letter job in the same workspace';
  end if;

  fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'event_name', p_event_name,
      'aggregate_type', p_aggregate_type,
      'aggregate_id', p_aggregate_id,
      'aggregate_version', p_aggregate_version,
      'job_type', p_job_type,
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'payload_schema_version', p_payload_schema_version,
      'payload', p_payload,
      'priority', p_priority,
      'max_attempts', p_max_attempts,
      'backoff_base_seconds', p_backoff_base_seconds,
      'backoff_max_seconds', p_backoff_max_seconds,
      'replay_of_job_id', p_replay_of_job_id
    )
  );

  -- Serialize only competing requests for the same logical idempotency scope.
  -- Hash collisions can delay unrelated work but cannot weaken correctness.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1f' || p_job_type || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select existing.*
    into existing_job
  from public.jobs existing
  where existing.workspace_id = p_workspace_id
    and existing.job_type = p_job_type
    and existing.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_job.request_fingerprint <> fingerprint then
      raise exception using
        errcode = '23505',
        message = 'idempotency key was already used for a different job request';
    end if;

    return query
    select
      existing_job.outbox_event_id,
      existing_job.id,
      false,
      existing_job.status;
    return;
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
    p_aggregate_type,
    p_aggregate_id,
    p_aggregate_version,
    p_payload_schema_version,
    p_payload,
    p_actor_user_id,
    p_correlation_id,
    p_causation_id
  )
  returning id into new_outbox_event_id;

  insert into public.jobs (
    workspace_id,
    outbox_event_id,
    replay_of_job_id,
    job_type,
    entity_type,
    entity_id,
    payload_schema_version,
    payload,
    idempotency_key,
    request_fingerprint,
    priority,
    max_attempts,
    backoff_base_seconds,
    backoff_max_seconds,
    available_at,
    correlation_id,
    causation_id
  ) values (
    p_workspace_id,
    new_outbox_event_id,
    p_replay_of_job_id,
    p_job_type,
    p_entity_type,
    p_entity_id,
    p_payload_schema_version,
    p_payload,
    normalized_idempotency_key,
    fingerprint,
    p_priority,
    p_max_attempts,
    p_backoff_base_seconds,
    p_backoff_max_seconds,
    p_available_at,
    p_correlation_id,
    p_causation_id
  )
  returning id into new_job_id;

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'job.queued',
    p_entity_type => 'job',
    p_entity_id => new_job_id,
    p_actor_user_id => p_actor_user_id,
    p_actor_type => case when p_actor_user_id is null then 'service' else 'user' end,
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'queued',
      'job_type', p_job_type,
      'max_attempts', p_max_attempts,
      'available_at', p_available_at
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    -- This API is service-only. Never reuse pooled request JWT claims to
    -- describe a separately validated actor supplied by the application layer.
    p_auth_assurance => case
      when p_actor_user_id is null then 'system'
      else 'server_validated'
    end,
    p_metadata => pg_catalog.jsonb_build_object(
      'outbox_event_id', new_outbox_event_id,
      'causation_id', p_causation_id,
      'replay_of_job_id', p_replay_of_job_id
    )
  );

  return query select new_outbox_event_id, new_job_id, true, 'queued'::text;
end;
$$;

create function app.claim_jobs(
  p_worker_id text,
  p_limit integer default 10,
  p_lease_seconds integer default 60,
  p_job_types text[] default null
)
returns table (
  job_id uuid,
  workspace_id uuid,
  outbox_event_id uuid,
  job_type text,
  entity_type text,
  entity_id uuid,
  payload_schema_version integer,
  payload jsonb,
  idempotency_key text,
  attempt_number integer,
  max_attempts integer,
  lease_token uuid,
  lease_expires_at timestamptz,
  correlation_id uuid,
  causation_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed_job public.jobs%rowtype;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_limit not between 1 and 100
    or p_lease_seconds not between 5 and 900 then
    raise exception using
      errcode = '22023',
      message = 'invalid worker claim parameters';
  end if;

  for claimed_job in
    with candidates as (
      select candidate.id
      from public.jobs candidate
      join public.workspaces w
        on w.id = candidate.workspace_id
       and w.status = 'active'
      join public.organizations o
        on o.id = w.organization_id
       and o.status = 'active'
      where candidate.status in ('queued', 'retry_wait')
        and candidate.available_at <= pg_catalog.statement_timestamp()
        and (
          p_job_types is null
          or candidate.job_type = any(p_job_types)
        )
      order by
        candidate.priority desc,
        candidate.available_at,
        candidate.created_at,
        candidate.id
      for update of candidate skip locked
      limit p_limit
    )
    update public.jobs target
    set status = 'running',
        attempts_started = target.attempts_started + 1,
        lease_owner = p_worker_id,
        lease_token = pg_catalog.gen_random_uuid(),
        lease_expires_at = pg_catalog.statement_timestamp()
          + pg_catalog.make_interval(secs => p_lease_seconds),
        heartbeat_at = pg_catalog.statement_timestamp(),
        current_attempt_started_at = pg_catalog.statement_timestamp(),
        first_started_at = coalesce(
          target.first_started_at,
          pg_catalog.statement_timestamp()
        ),
        updated_at = pg_catalog.statement_timestamp(),
        version = target.version + 1
    from candidates
    where target.id = candidates.id
    returning target.*
  loop
    perform app.write_audit_event(
      p_workspace_id => claimed_job.workspace_id,
      p_action => 'job.started',
      p_entity_type => 'job',
      p_entity_id => claimed_job.id,
      p_actor_type => 'worker',
      p_after_data => pg_catalog.jsonb_build_object(
        'status', 'running',
        'attempt_number', claimed_job.attempts_started,
        'lease_expires_at', claimed_job.lease_expires_at
      ),
      p_correlation_id => claimed_job.correlation_id,
      p_auth_assurance => 'service',
      p_metadata => pg_catalog.jsonb_build_object(
        'worker_id', p_worker_id,
        'causation_id', claimed_job.causation_id
      )
    );

    job_id := claimed_job.id;
    workspace_id := claimed_job.workspace_id;
    outbox_event_id := claimed_job.outbox_event_id;
    job_type := claimed_job.job_type;
    entity_type := claimed_job.entity_type;
    entity_id := claimed_job.entity_id;
    payload_schema_version := claimed_job.payload_schema_version;
    payload := claimed_job.payload;
    idempotency_key := claimed_job.idempotency_key;
    attempt_number := claimed_job.attempts_started;
    max_attempts := claimed_job.max_attempts;
    lease_token := claimed_job.lease_token;
    lease_expires_at := claimed_job.lease_expires_at;
    correlation_id := claimed_job.correlation_id;
    causation_id := claimed_job.causation_id;
    return next;
  end loop;
end;
$$;

create function app.heartbeat_job(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_extend_seconds integer default 60
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  renewed_until timestamptz;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or p_extend_seconds not between 5 and 900 then
    raise exception using
      errcode = '22023',
      message = 'invalid heartbeat parameters';
  end if;

  update public.jobs target
  set heartbeat_at = pg_catalog.statement_timestamp(),
      lease_expires_at = pg_catalog.statement_timestamp()
        + pg_catalog.make_interval(secs => p_extend_seconds),
      updated_at = pg_catalog.statement_timestamp(),
      version = target.version + 1
  where target.id = p_job_id
    and target.status = 'running'
    and target.lease_owner = p_worker_id
    and target.lease_token = p_lease_token
    and target.lease_expires_at > pg_catalog.statement_timestamp()
  returning target.lease_expires_at into renewed_until;

  if renewed_until is null then
    raise exception using
      errcode = '55000',
      message = 'job lease is missing, expired, or owned by another worker';
  end if;

  return renewed_until;
end;
$$;

create function app.complete_job(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_result_summary jsonb default '{}'::jsonb,
  p_provider_request_id text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  finished_at timestamptz := pg_catalog.statement_timestamp();
begin
  if p_result_summary is null
    or pg_catalog.jsonb_typeof(p_result_summary) <> 'object'
    or app.job_payload_contains_forbidden_key(p_result_summary) then
    raise exception using
      errcode = '23514',
      message = 'job result summary must omit credential-bearing keys';
  end if;

  select target.*
    into target_job
  from public.jobs target
  where target.id = p_job_id
  for update;

  if not found
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= finished_at then
    raise exception using
      errcode = '55000',
      message = 'only the active lease owner can complete a job';
  end if;

  insert into public.job_attempts (
    workspace_id,
    job_id,
    attempt_number,
    worker_id,
    lease_token,
    started_at,
    finished_at,
    outcome,
    provider_request_id,
    correlation_id,
    causation_id
  ) values (
    target_job.workspace_id,
    target_job.id,
    target_job.attempts_started,
    target_job.lease_owner,
    target_job.lease_token,
    target_job.current_attempt_started_at,
    finished_at,
    'succeeded',
    p_provider_request_id,
    target_job.correlation_id,
    target_job.causation_id
  );

  update public.jobs target
  set status = 'succeeded',
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null,
      heartbeat_at = null,
      current_attempt_started_at = null,
      completed_at = finished_at,
      result_summary = p_result_summary,
      last_provider_request_id = p_provider_request_id,
      review_required = false,
      updated_at = finished_at,
      version = target.version + 1
  where target.id = target_job.id;

  perform app.write_audit_event(
    p_workspace_id => target_job.workspace_id,
    p_action => 'job.succeeded',
    p_entity_type => 'job',
    p_entity_id => target_job.id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object('status', 'running'),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'succeeded',
      'attempt_number', target_job.attempts_started
    ),
    p_correlation_id => target_job.correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'worker_id', p_worker_id,
      'provider_request_id', p_provider_request_id,
      'causation_id', target_job.causation_id
    )
  );

  return true;
end;
$$;

create function app.fail_job(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_error_classification text,
  p_error_code text,
  p_error_detail_safe text,
  p_provider_request_id text default null,
  p_retry_after_seconds integer default null
)
returns table (
  job_status text,
  retry_at timestamptz,
  review_required boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  finished_at timestamptz := pg_catalog.statement_timestamp();
  should_retry boolean;
  next_retry_at timestamptz;
  retry_delay integer;
  next_status text;
begin
  if p_error_classification is null or p_error_classification not in (
    'transient',
    'rate_limited',
    'permanent',
    'validation',
    'permission',
    'provider_auth',
    'unknown'
  ) then
    raise exception using
      errcode = '22023',
      message = 'unknown job error classification';
  end if;

  if pg_catalog.btrim(coalesce(p_error_code, '')) = ''
    or pg_catalog.char_length(p_error_code) > 120
    or pg_catalog.btrim(coalesce(p_error_detail_safe, '')) = ''
    or pg_catalog.char_length(p_error_detail_safe) > 2000
    or (
      p_retry_after_seconds is not null
      and p_retry_after_seconds not between 1 and 86400
    ) then
    raise exception using
      errcode = '22023',
      message = 'invalid safe job failure details';
  end if;

  select target.*
    into target_job
  from public.jobs target
  where target.id = p_job_id
  for update;

  if not found
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= finished_at then
    raise exception using
      errcode = '55000',
      message = 'only the active lease owner can fail a job';
  end if;

  should_retry := p_error_classification in ('transient', 'rate_limited', 'unknown')
    and target_job.attempts_started < target_job.max_attempts;

  if should_retry then
    retry_delay := app.job_retry_delay_seconds(
      target_job.attempts_started,
      target_job.backoff_base_seconds,
      target_job.backoff_max_seconds,
      pg_catalog.random()
    );
    if p_retry_after_seconds is not null then
      retry_delay := greatest(retry_delay, p_retry_after_seconds);
    end if;
    next_retry_at := finished_at + pg_catalog.make_interval(secs => retry_delay);
    next_status := 'retry_wait';
  else
    next_retry_at := null;
    next_status := 'dead_letter';
  end if;

  insert into public.job_attempts (
    workspace_id,
    job_id,
    attempt_number,
    worker_id,
    lease_token,
    started_at,
    finished_at,
    outcome,
    error_classification,
    error_code,
    error_detail_safe,
    provider_request_id,
    retry_at,
    correlation_id,
    causation_id
  ) values (
    target_job.workspace_id,
    target_job.id,
    target_job.attempts_started,
    target_job.lease_owner,
    target_job.lease_token,
    target_job.current_attempt_started_at,
    finished_at,
    case when should_retry then 'retry_scheduled' else 'dead_lettered' end,
    p_error_classification,
    p_error_code,
    p_error_detail_safe,
    p_provider_request_id,
    next_retry_at,
    target_job.correlation_id,
    target_job.causation_id
  );

  update public.jobs target
  set status = next_status,
      available_at = coalesce(next_retry_at, target.available_at),
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null,
      heartbeat_at = null,
      current_attempt_started_at = null,
      completed_at = case when should_retry then null else finished_at end,
      last_error_classification = p_error_classification,
      last_error_code = p_error_code,
      last_error_detail_safe = p_error_detail_safe,
      last_provider_request_id = p_provider_request_id,
      review_required = not should_retry,
      updated_at = finished_at,
      version = target.version + 1
  where target.id = target_job.id;

  perform app.write_audit_event(
    p_workspace_id => target_job.workspace_id,
    p_action => case
      when should_retry then 'job.retry_scheduled'
      else 'job.dead_lettered'
    end,
    p_entity_type => 'job',
    p_entity_id => target_job.id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object('status', 'running'),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', next_status,
      'attempt_number', target_job.attempts_started,
      'retry_at', next_retry_at,
      'review_required', not should_retry
    ),
    p_reason => p_error_code,
    p_correlation_id => target_job.correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'worker_id', p_worker_id,
      'classification', p_error_classification,
      'provider_request_id', p_provider_request_id,
      'causation_id', target_job.causation_id
    )
  );

  return query select next_status, next_retry_at, not should_retry;
end;
$$;

create function app.reclaim_expired_job_leases(p_limit integer default 100)
returns table (
  job_id uuid,
  resulting_status text,
  retry_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  reclaimed_at timestamptz;
  next_retry_at timestamptz;
  should_retry boolean;
  retry_delay integer;
begin
  if p_limit not between 1 and 1000 then
    raise exception using
      errcode = '22023',
      message = 'invalid lease-reclaim limit';
  end if;

  for target_job in
    select candidate.*
    from public.jobs candidate
    where candidate.status = 'running'
      and candidate.lease_expires_at <= pg_catalog.statement_timestamp()
    order by candidate.lease_expires_at, candidate.id
    for update of candidate skip locked
    limit p_limit
  loop
    reclaimed_at := pg_catalog.statement_timestamp();
    should_retry := target_job.attempts_started < target_job.max_attempts;

    if should_retry then
      retry_delay := app.job_retry_delay_seconds(
        target_job.attempts_started,
        target_job.backoff_base_seconds,
        target_job.backoff_max_seconds,
        pg_catalog.random()
      );
      next_retry_at := reclaimed_at + pg_catalog.make_interval(secs => retry_delay);
    else
      next_retry_at := null;
    end if;

    insert into public.job_attempts (
      workspace_id,
      job_id,
      attempt_number,
      worker_id,
      lease_token,
      started_at,
      finished_at,
      outcome,
      error_classification,
      error_code,
      error_detail_safe,
      retry_at,
      correlation_id,
      causation_id
    ) values (
      target_job.workspace_id,
      target_job.id,
      target_job.attempts_started,
      target_job.lease_owner,
      target_job.lease_token,
      target_job.current_attempt_started_at,
      reclaimed_at,
      'lease_expired',
      'lease_expired',
      'worker_lease_expired',
      'Worker lease expired before a terminal attempt result was recorded.',
      next_retry_at,
      target_job.correlation_id,
      target_job.causation_id
    );

    update public.jobs target
    set status = case when should_retry then 'retry_wait' else 'dead_letter' end,
        available_at = coalesce(next_retry_at, target.available_at),
        lease_owner = null,
        lease_token = null,
        lease_expires_at = null,
        heartbeat_at = null,
        current_attempt_started_at = null,
        completed_at = case when should_retry then null else reclaimed_at end,
        last_error_classification = 'lease_expired',
        last_error_code = 'worker_lease_expired',
        last_error_detail_safe =
          'Worker lease expired before a terminal attempt result was recorded.',
        review_required = not should_retry,
        updated_at = reclaimed_at,
        version = target.version + 1
    where target.id = target_job.id;

    perform app.write_audit_event(
      p_workspace_id => target_job.workspace_id,
      p_action => case
        when should_retry then 'job.retry_scheduled'
        else 'job.dead_lettered'
      end,
      p_entity_type => 'job',
      p_entity_id => target_job.id,
      p_actor_type => 'worker',
      p_before_data => pg_catalog.jsonb_build_object(
        'status', 'running',
        'attempt_number', target_job.attempts_started
      ),
      p_after_data => pg_catalog.jsonb_build_object(
        'status', case when should_retry then 'retry_wait' else 'dead_letter' end,
        'retry_at', next_retry_at,
        'review_required', not should_retry
      ),
      p_reason => 'worker_lease_expired',
      p_correlation_id => target_job.correlation_id,
      p_auth_assurance => 'service',
      p_metadata => pg_catalog.jsonb_build_object(
        'worker_id', target_job.lease_owner,
        'causation_id', target_job.causation_id
      )
    );

    job_id := target_job.id;
    resulting_status := case when should_retry then 'retry_wait' else 'dead_letter' end;
    retry_at := next_retry_at;
    return next;
  end loop;
end;
$$;

create function app.cancel_job(
  p_job_id uuid,
  p_actor_user_id uuid,
  p_reason text,
  p_correlation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  cancelled_at timestamptz := pg_catalog.statement_timestamp();
begin
  if pg_catalog.btrim(coalesce(p_reason, '')) = ''
    or pg_catalog.char_length(p_reason) > 1000
    or p_correlation_id is null then
    raise exception using
      errcode = '22023',
      message = 'job cancellation requires a safe reason and correlation ID';
  end if;

  select target.*
    into target_job
  from public.jobs target
  where target.id = p_job_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'job was not found';
  end if;

  if target_job.status not in ('queued', 'retry_wait') then
    raise exception using
      errcode = '55000',
      message = 'only queued or retry-wait jobs can be cancelled safely';
  end if;

  if not app.job_actor_has_permission(
    target_job.workspace_id,
    p_actor_user_id,
    'jobs.manage'
  ) then
    raise exception using
      errcode = '42501',
      message = 'active jobs.manage permission is required';
  end if;

  update public.jobs target
  set status = 'cancelled',
      completed_at = cancelled_at,
      cancel_reason = p_reason,
      review_required = false,
      updated_at = cancelled_at,
      version = target.version + 1
  where target.id = target_job.id;

  perform app.write_audit_event(
    p_workspace_id => target_job.workspace_id,
    p_action => 'job.cancelled',
    p_entity_type => 'job',
    p_entity_id => target_job.id,
    p_actor_user_id => p_actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('status', target_job.status),
    p_after_data => pg_catalog.jsonb_build_object('status', 'cancelled'),
    p_reason => p_reason,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'server_validated',
    p_metadata => pg_catalog.jsonb_build_object(
      'job_correlation_id', target_job.correlation_id,
      'causation_id', target_job.causation_id
    )
  );

  return true;
end;
$$;

create function app.acknowledge_dead_letter_job(
  p_job_id uuid,
  p_reviewer_user_id uuid,
  p_reason text,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  review_id uuid;
begin
  if pg_catalog.btrim(coalesce(p_reason, '')) = ''
    or pg_catalog.char_length(p_reason) > 2000
    or p_correlation_id is null then
    raise exception using
      errcode = '22023',
      message = 'dead-letter review requires a safe reason and correlation ID';
  end if;

  select target.*
    into target_job
  from public.jobs target
  where target.id = p_job_id
  for update;

  if not found
    or target_job.status <> 'dead_letter'
    or target_job.review_required is false then
    raise exception using
      errcode = '55000',
      message = 'job is not awaiting dead-letter review';
  end if;

  if not app.job_actor_has_permission(
    target_job.workspace_id,
    p_reviewer_user_id,
    'jobs.manage'
  ) then
    raise exception using
      errcode = '42501',
      message = 'active jobs.manage permission is required';
  end if;

  insert into public.job_admin_reviews (
    workspace_id,
    job_id,
    reviewer_user_id,
    decision,
    reason,
    correlation_id
  ) values (
    target_job.workspace_id,
    target_job.id,
    p_reviewer_user_id,
    'acknowledged',
    p_reason,
    p_correlation_id
  )
  returning id into review_id;

  update public.jobs target
  set review_required = false,
      updated_at = pg_catalog.statement_timestamp(),
      version = target.version + 1
  where target.id = target_job.id;

  perform app.write_audit_event(
    p_workspace_id => target_job.workspace_id,
    p_action => 'job.dead_letter_reviewed',
    p_entity_type => 'job',
    p_entity_id => target_job.id,
    p_actor_user_id => p_reviewer_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('review_required', true),
    p_after_data => pg_catalog.jsonb_build_object(
      'review_required', false,
      'decision', 'acknowledged'
    ),
    p_reason => p_reason,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'server_validated',
    p_metadata => pg_catalog.jsonb_build_object(
      'review_id', review_id,
      'job_correlation_id', target_job.correlation_id
    )
  );

  return review_id;
end;
$$;

create function app.replay_dead_letter_job(
  p_job_id uuid,
  p_new_idempotency_key text,
  p_reviewer_user_id uuid,
  p_reason text,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  source_event public.outbox_events%rowtype;
  replay_job_id uuid;
  replay_outbox_event_id uuid;
  replay_created boolean;
  replay_status text;
  review_id uuid;
begin
  if pg_catalog.btrim(coalesce(p_reason, '')) = ''
    or pg_catalog.char_length(p_reason) > 2000
    or pg_catalog.btrim(coalesce(p_new_idempotency_key, '')) = ''
    or p_correlation_id is null then
    raise exception using
      errcode = '22023',
      message = 'dead-letter replay requires a new key, reason, and correlation ID';
  end if;

  select target.*
    into target_job
  from public.jobs target
  where target.id = p_job_id
  for update;

  if not found
    or target_job.status <> 'dead_letter'
    or target_job.review_required is false then
    raise exception using
      errcode = '55000',
      message = 'job is not awaiting dead-letter review';
  end if;

  if not app.job_actor_has_permission(
    target_job.workspace_id,
    p_reviewer_user_id,
    'jobs.manage'
  ) then
    raise exception using
      errcode = '42501',
      message = 'active jobs.manage permission is required';
  end if;

  select source.*
    into source_event
  from public.outbox_events source
  where source.workspace_id = target_job.workspace_id
    and source.id = target_job.outbox_event_id;

  select replay.outbox_event_id, replay.job_id, replay.created, replay.job_status
    into replay_outbox_event_id, replay_job_id, replay_created, replay_status
  from app.enqueue_outbox_job(
    p_workspace_id => target_job.workspace_id,
    p_event_name => 'job.replay_requested',
    p_aggregate_type => source_event.aggregate_type,
    p_aggregate_id => source_event.aggregate_id,
    p_aggregate_version => source_event.aggregate_version,
    p_job_type => target_job.job_type,
    p_entity_type => target_job.entity_type,
    p_entity_id => target_job.entity_id,
    p_payload_schema_version => target_job.payload_schema_version,
    p_payload => target_job.payload,
    p_idempotency_key => p_new_idempotency_key,
    p_correlation_id => p_correlation_id,
    p_causation_id => target_job.outbox_event_id,
    p_actor_user_id => p_reviewer_user_id,
    p_priority => target_job.priority,
    p_max_attempts => target_job.max_attempts,
    p_available_at => pg_catalog.statement_timestamp(),
    p_backoff_base_seconds => target_job.backoff_base_seconds,
    p_backoff_max_seconds => target_job.backoff_max_seconds,
    p_replay_of_job_id => target_job.id
  ) replay;

  if not replay_created or replay_status <> 'queued' then
    raise exception using
      errcode = '23505',
      message = 'replay idempotency key already exists';
  end if;

  insert into public.job_admin_reviews (
    workspace_id,
    job_id,
    reviewer_user_id,
    decision,
    reason,
    replay_job_id,
    correlation_id
  ) values (
    target_job.workspace_id,
    target_job.id,
    p_reviewer_user_id,
    'replayed',
    p_reason,
    replay_job_id,
    p_correlation_id
  )
  returning id into review_id;

  update public.jobs target
  set review_required = false,
      updated_at = pg_catalog.statement_timestamp(),
      version = target.version + 1
  where target.id = target_job.id;

  perform app.write_audit_event(
    p_workspace_id => target_job.workspace_id,
    p_action => 'job.dead_letter_reviewed',
    p_entity_type => 'job',
    p_entity_id => target_job.id,
    p_actor_user_id => p_reviewer_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('review_required', true),
    p_after_data => pg_catalog.jsonb_build_object(
      'review_required', false,
      'decision', 'replayed',
      'replay_job_id', replay_job_id
    ),
    p_reason => p_reason,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'server_validated',
    p_metadata => pg_catalog.jsonb_build_object(
      'review_id', review_id,
      'replay_outbox_event_id', replay_outbox_event_id,
      'job_correlation_id', target_job.correlation_id
    )
  );

  return replay_job_id;
end;
$$;

alter table public.outbox_events enable row level security;
alter table public.outbox_events force row level security;
alter table public.jobs enable row level security;
alter table public.jobs force row level security;
alter table public.job_attempts enable row level security;
alter table public.job_attempts force row level security;
alter table public.job_admin_reviews enable row level security;
alter table public.job_admin_reviews force row level security;

create policy outbox_events_select on public.outbox_events
for select to authenticated
using (app.has_permission(workspace_id, 'jobs.read'));

create policy jobs_select on public.jobs
for select to authenticated
using (app.has_permission(workspace_id, 'jobs.read'));

create policy job_attempts_select on public.job_attempts
for select to authenticated
using (app.has_permission(workspace_id, 'jobs.read'));

create policy job_admin_reviews_select on public.job_admin_reviews
for select to authenticated
using (app.has_permission(workspace_id, 'jobs.read'));

revoke all on table
  public.outbox_events,
  public.jobs,
  public.job_attempts,
  public.job_admin_reviews
from public, anon, authenticated, service_role;

grant select (
  id,
  workspace_id,
  event_name,
  aggregate_type,
  aggregate_id,
  aggregate_version,
  payload_schema_version,
  actor_user_id,
  correlation_id,
  causation_id,
  occurred_at
) on public.outbox_events to authenticated;

grant select (
  id,
  workspace_id,
  outbox_event_id,
  replay_of_job_id,
  job_type,
  entity_type,
  entity_id,
  payload_schema_version,
  idempotency_key,
  status,
  priority,
  attempts_started,
  max_attempts,
  available_at,
  lease_owner,
  lease_expires_at,
  heartbeat_at,
  first_started_at,
  completed_at,
  last_error_classification,
  last_error_code,
  last_error_detail_safe,
  last_provider_request_id,
  review_required,
  cancel_reason,
  correlation_id,
  causation_id,
  version,
  created_at,
  updated_at
) on public.jobs to authenticated;

grant select on public.job_attempts, public.job_admin_reviews to authenticated;

grant select on
  public.outbox_events,
  public.jobs,
  public.job_attempts,
  public.job_admin_reviews
to service_role;

revoke all on function app.job_payload_contains_forbidden_key(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.job_request_fingerprint(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.job_retry_delay_seconds(
  integer,
  integer,
  integer,
  double precision
) from public, anon, authenticated, service_role;
revoke all on function app.prevent_job_history_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.job_actor_has_permission(uuid, uuid, text)
  from public, anon, authenticated, service_role;

revoke all on function app.enqueue_outbox_job(
  uuid,
  text,
  text,
  uuid,
  bigint,
  text,
  text,
  uuid,
  integer,
  jsonb,
  text,
  uuid,
  uuid,
  uuid,
  integer,
  integer,
  timestamptz,
  integer,
  integer,
  uuid,
  text
) from public, anon, authenticated, service_role;
revoke all on function app.claim_jobs(text, integer, integer, text[])
  from public, anon, authenticated, service_role;
revoke all on function app.heartbeat_job(uuid, text, uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function app.complete_job(uuid, text, uuid, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function app.fail_job(
  uuid,
  text,
  uuid,
  text,
  text,
  text,
  text,
  integer
) from public, anon, authenticated, service_role;
revoke all on function app.reclaim_expired_job_leases(integer)
  from public, anon, authenticated, service_role;
revoke all on function app.cancel_job(uuid, uuid, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.acknowledge_dead_letter_job(uuid, uuid, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.replay_dead_letter_job(uuid, text, uuid, text, uuid)
  from public, anon, authenticated, service_role;

grant execute on function app.enqueue_outbox_job(
  uuid,
  text,
  text,
  uuid,
  bigint,
  text,
  text,
  uuid,
  integer,
  jsonb,
  text,
  uuid,
  uuid,
  uuid,
  integer,
  integer,
  timestamptz,
  integer,
  integer,
  uuid,
  text
) to service_role;
grant execute on function app.claim_jobs(text, integer, integer, text[])
  to service_role;
grant execute on function app.heartbeat_job(uuid, text, uuid, integer)
  to service_role;
grant execute on function app.complete_job(uuid, text, uuid, jsonb, text)
  to service_role;
grant execute on function app.fail_job(
  uuid,
  text,
  uuid,
  text,
  text,
  text,
  text,
  integer
) to service_role;
grant execute on function app.reclaim_expired_job_leases(integer)
  to service_role;
grant execute on function app.cancel_job(uuid, uuid, text, uuid)
  to service_role;
grant execute on function app.acknowledge_dead_letter_job(uuid, uuid, text, uuid)
  to service_role;
grant execute on function app.replay_dead_letter_job(uuid, text, uuid, text, uuid)
  to service_role;

comment on table public.outbox_events is
  'Append-only workspace outbox events committed with authoritative business writes.';
comment on table public.jobs is
  'Workspace-scoped durable delivery state; mutation is restricted to audited service functions.';
comment on table public.job_attempts is
  'Append-only terminal attempt telemetry, including retry, lease-expiry, and provider-safe errors.';
comment on table public.job_admin_reviews is
  'Append-only authorized acknowledgement/replay history for dead-letter jobs.';
comment on function app.enqueue_outbox_job(
  uuid,
  text,
  text,
  uuid,
  bigint,
  text,
  text,
  uuid,
  integer,
  jsonb,
  text,
  uuid,
  uuid,
  uuid,
  integer,
  integer,
  timestamptz,
  integer,
  integer,
  uuid,
  text
) is
  'Service-only transaction primitive that atomically appends one outbox event and idempotent job.';
comment on function app.claim_jobs(text, integer, integer, text[]) is
  'Service-only bounded worker claim using FOR UPDATE SKIP LOCKED and expiring leases.';
