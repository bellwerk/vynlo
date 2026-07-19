-- VYN-CRM-001, VYN-WF-001, VYN-DEAL-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001 / M3-CRM-AC-002 through M3-CRM-AC-004.
-- Tenant-neutral leads, append-only CRM timeline, tasks, appointments, and
-- atomic configured-deal conversion. No tenant formulas or M4 behavior.

create table public.leads (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  source_key text not null check (
    source_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
  ),
  summary text not null check (
    pg_catalog.btrim(summary) <> '' and pg_catalog.char_length(summary) <= 2000
  ),
  prospect_party_id uuid,
  interested_inventory_unit_id uuid,
  assignee_membership_id uuid,
  next_action_at timestamptz,
  workflow_version_id uuid not null,
  workflow_instance_id uuid not null,
  state_key text not null check (state_key ~ '^[a-z][a-z0-9_]*$'),
  lost_reason text check (
    lost_reason is null or (
      pg_catalog.btrim(lost_reason) <> ''
      and pg_catalog.char_length(lost_reason) <= 2000
    )
  ),
  converted_deal_id uuid,
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, prospect_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, interested_inventory_unit_id)
    references public.inventory_units (workspace_id, id) on delete restrict,
  foreign key (workspace_id, assignee_membership_id)
    references public.workspace_memberships (workspace_id, id) on delete restrict,
  foreign key (workspace_id, workflow_version_id)
    references public.workflow_versions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, workflow_instance_id)
    references public.workflow_instances (workspace_id, id) on delete restrict,
  foreign key (workspace_id, converted_deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  constraint leads_terminal_metadata_check check (
    pg_catalog.num_nonnulls(lost_reason, converted_deal_id) <= 1
  )
);

create index leads_workspace_state_idx
  on public.leads (workspace_id, state_key, updated_at desc, id);
create index leads_workspace_assignee_idx
  on public.leads (workspace_id, assignee_membership_id, next_action_at, id);
create index leads_workspace_party_idx
  on public.leads (workspace_id, prospect_party_id, created_at desc, id);

alter table public.deals
  add constraint deals_originating_lead_fk
    foreign key (workspace_id, originating_lead_id)
    references public.leads (workspace_id, id) on delete restrict;

create unique index deals_originating_lead_uidx
  on public.deals (workspace_id, originating_lead_id)
  where originating_lead_id is not null;

create table public.crm_activities (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  party_id uuid,
  lead_id uuid,
  deal_id uuid,
  activity_type text not null check (activity_type in (
    'note', 'call', 'email_reference', 'text_reference', 'appointment',
    'assignment', 'status_change', 'document', 'deal_event'
  )),
  channel_key text check (
    channel_key is null
    or channel_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
  ),
  direction text not null check (direction in ('inbound', 'outbound', 'internal')),
  subject text not null check (
    pg_catalog.btrim(subject) <> '' and pg_catalog.char_length(subject) <= 200
  ),
  body text check (body is null or pg_catalog.char_length(body) <= 10000),
  provider_reference text check (
    provider_reference is null or (
      pg_catalog.btrim(provider_reference) <> ''
      and pg_catalog.char_length(provider_reference) <= 500
    )
  ),
  occurred_at timestamptz not null,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  version bigint not null default 1 check (version = 1),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, lead_id)
    references public.leads (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  check (pg_catalog.num_nonnulls(party_id, lead_id, deal_id) > 0),
  check (provider_reference is null or channel_key is not null)
);

create index crm_activities_workspace_time_idx
  on public.crm_activities (workspace_id, occurred_at desc, id desc);
create index crm_activities_lead_time_idx
  on public.crm_activities (workspace_id, lead_id, occurred_at desc, id desc)
  where lead_id is not null;
create index crm_activities_party_time_idx
  on public.crm_activities (workspace_id, party_id, occurred_at desc, id desc)
  where party_id is not null;
create index crm_activities_deal_time_idx
  on public.crm_activities (workspace_id, deal_id, occurred_at desc, id desc)
  where deal_id is not null;
create unique index crm_activities_provider_reference_uidx
  on public.crm_activities (workspace_id, channel_key, provider_reference)
  where provider_reference is not null;

create table public.crm_tasks (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  party_id uuid,
  lead_id uuid,
  deal_id uuid,
  assignee_membership_id uuid not null,
  title text not null check (
    pg_catalog.btrim(title) <> '' and pg_catalog.char_length(title) <= 200
  ),
  description text check (description is null or pg_catalog.char_length(description) <= 4000),
  priority text not null check (priority in ('low', 'normal', 'high', 'urgent')),
  due_at timestamptz not null,
  reminder_at timestamptz,
  state text not null default 'open' check (state in ('open', 'completed', 'cancelled')),
  completed_at timestamptz,
  completed_by uuid references auth.users (id) on delete restrict,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users (id) on delete restrict,
  cancellation_reason text check (
    cancellation_reason is null or (
      pg_catalog.btrim(cancellation_reason) <> ''
      and pg_catalog.char_length(cancellation_reason) <= 2000
    )
  ),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, lead_id)
    references public.leads (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, assignee_membership_id)
    references public.workspace_memberships (workspace_id, id) on delete restrict,
  check (pg_catalog.num_nonnulls(party_id, lead_id, deal_id) > 0),
  check (reminder_at is null or reminder_at <= due_at),
  check (
    (state = 'open' and completed_at is null and completed_by is null
      and cancelled_at is null and cancelled_by is null
      and cancellation_reason is null)
    or (state = 'completed' and completed_at is not null and completed_by is not null
      and cancelled_at is null and cancelled_by is null
      and cancellation_reason is null)
    or (state = 'cancelled' and completed_at is null and completed_by is null
      and cancelled_at is not null and cancelled_by is not null
      and cancellation_reason is not null)
  )
);

create index crm_tasks_workspace_state_due_idx
  on public.crm_tasks (workspace_id, state, due_at, priority, id);
create index crm_tasks_workspace_assignee_idx
  on public.crm_tasks (workspace_id, assignee_membership_id, state, due_at, id);

create table public.crm_appointments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  lead_id uuid,
  deal_id uuid,
  title text not null check (
    pg_catalog.btrim(title) <> '' and pg_catalog.char_length(title) <= 200
  ),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  timezone text not null check (
    pg_catalog.btrim(timezone) <> '' and pg_catalog.char_length(timezone) <= 100
  ),
  location_id uuid,
  remote_details text check (
    remote_details is null or pg_catalog.char_length(remote_details) <= 2000
  ),
  notes text check (notes is null or pg_catalog.char_length(notes) <= 4000),
  status text not null default 'scheduled'
    check (status in ('scheduled', 'completed', 'cancelled', 'no_show')),
  outcome text check (
    outcome is null or (
      pg_catalog.btrim(outcome) <> '' and pg_catalog.char_length(outcome) <= 4000
    )
  ),
  status_reason text check (
    status_reason is null or (
      pg_catalog.btrim(status_reason) <> ''
      and pg_catalog.char_length(status_reason) <= 2000
    )
  ),
  resolved_at timestamptz,
  resolved_by uuid references auth.users (id) on delete restrict,
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, lead_id)
    references public.leads (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, location_id)
    references public.locations (workspace_id, id) on delete restrict,
  check (pg_catalog.num_nonnulls(lead_id, deal_id) > 0),
  check (ends_at > starts_at),
  check (
    (status = 'scheduled' and outcome is null and status_reason is null
      and resolved_at is null and resolved_by is null)
    or (status = 'completed' and outcome is not null
      and resolved_at is not null and resolved_by is not null)
    or (status in ('cancelled', 'no_show')
      and status_reason is not null and resolved_at is not null
      and resolved_by is not null)
  )
);

create index crm_appointments_workspace_status_time_idx
  on public.crm_appointments (workspace_id, status, starts_at, id);

create table public.crm_appointment_attendees (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  appointment_id uuid not null,
  party_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, appointment_id, party_id),
  foreign key (workspace_id, appointment_id)
    references public.crm_appointments (workspace_id, id) on delete restrict,
  foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict
);

create table public.crm_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  command_type text not null check (command_type in (
    'm3_create_lead', 'm3_update_lead', 'm3_transition_lead',
    'm3_convert_lead', 'm3_create_activity', 'm3_create_task',
    'm3_complete_task', 'm3_cancel_task', 'm3_create_appointment',
    'm3_transition_appointment'
  )),
  idempotency_key text not null check (
    pg_catalog.char_length(pg_catalog.btrim(idempotency_key)) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[0-9a-f]{64}$'),
  entity_type text not null check (
    entity_type in ('lead', 'crm_activity', 'crm_task', 'crm_appointment')
  ),
  entity_id uuid not null,
  result jsonb not null check (
    pg_catalog.jsonb_typeof(result) = 'object'
    and not app.job_payload_contains_forbidden_key(result)
  ),
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, command_type, idempotency_key),
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict
);

create index crm_command_receipts_entity_idx
  on public.crm_command_receipts (
    workspace_id, entity_type, entity_id, created_at desc, id
  );

create function app.assert_m3_crm_command_metadata(
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
  if pg_catalog.char_length(normalized_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid CRM idempotency key';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  return normalized_key;
end;
$$;

create function app.replay_m3_crm_command(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_command_type text,
  p_idempotency_key text,
  p_command_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  receipt public.crm_command_receipts%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1f' || p_command_type || E'\x1f'
        || p_actor_user_id::text || E'\x1f' || p_idempotency_key,
      0
    )
  );
  select stored.* into receipt
  from public.crm_command_receipts stored
  where stored.workspace_id = p_workspace_id
    and stored.actor_user_id = p_actor_user_id
    and stored.command_type = p_command_type
    and stored.idempotency_key = p_idempotency_key;
  if not found then
    return null;
  end if;
  if receipt.command_fingerprint <> p_command_fingerprint then
    raise exception using
      errcode = '23505',
      message = 'CRM idempotency key was reused with different input';
  end if;
  return receipt.result;
end;
$$;

create function app.record_m3_crm_command(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_command_type text,
  p_idempotency_key text,
  p_command_fingerprint text,
  p_entity_type text,
  p_entity_id uuid,
  p_result jsonb,
  p_audit_event_id uuid,
  p_outbox_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.crm_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, entity_type, entity_id, result,
    audit_event_id, outbox_event_id
  ) values (
    p_workspace_id, p_actor_user_id, p_command_type, p_idempotency_key,
    p_command_fingerprint, p_entity_type, p_entity_id, p_result,
    p_audit_event_id, p_outbox_event_id
  );
end;
$$;

create function app.append_m3_crm_entity_outbox(
  p_workspace_id uuid,
  p_event_name text,
  p_entity_type text,
  p_entity_id uuid,
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
  if p_event_name !~ '^(lead|crm_activity|crm_task|crm_appointment)\.[a-z][a-z0-9_]*$'
    or p_entity_type not in ('lead', 'crm_activity', 'crm_task', 'crm_appointment')
    or p_aggregate_version < 1
    or p_correlation_id is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or app.job_payload_contains_forbidden_key(p_payload) then
    raise exception using errcode = '23514', message = 'invalid CRM outbox event';
  end if;
  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload,
    actor_user_id, correlation_id
  ) values (
    p_workspace_id, p_event_name, p_entity_type, p_entity_id,
    p_aggregate_version, 1, p_payload, p_actor_user_id, p_correlation_id
  ) returning id into event_id;
  return event_id;
end;
$$;

create function app.assert_m3_crm_links(
  p_workspace_id uuid,
  p_party_id uuid,
  p_lead_id uuid,
  p_deal_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_party_id is not null and not exists (
    select 1 from public.parties party
    where party.workspace_id = p_workspace_id
      and party.id = p_party_id and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace party is required';
  end if;
  if p_lead_id is not null and not exists (
    select 1 from public.leads lead
    where lead.workspace_id = p_workspace_id and lead.id = p_lead_id
  ) then
    raise exception using errcode = '23514', message = 'workspace lead is required';
  end if;
  if p_deal_id is not null and not exists (
    select 1 from public.deals deal
    where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  ) then
    raise exception using errcode = '23514', message = 'workspace deal is required';
  end if;
end;
$$;

create function app.assert_m3_crm_assignee(
  p_workspace_id uuid,
  p_assignee_membership_id uuid,
  p_actor_user_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  assignee_user_id uuid;
begin
  if p_assignee_membership_id is null then
    return;
  end if;
  select membership.user_id into assignee_user_id
  from public.workspace_memberships membership
  where membership.workspace_id = p_workspace_id
    and membership.id = p_assignee_membership_id
    and membership.status = 'active';
  if assignee_user_id is null then
    raise exception using errcode = '23514', message = 'active workspace assignee is required';
  end if;
  if assignee_user_id <> p_actor_user_id
    and not app.has_permission(p_workspace_id, 'crm.assign') then
    raise exception using errcode = '42501', message = 'CRM assignment permission is required';
  end if;
end;
$$;

create function app.m3_timezone_exists(p_timezone text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from pg_catalog.pg_timezone_names timezone
    where timezone.name = p_timezone
  );
$$;

create function app.m3_lead_state_is_terminal(
  p_workspace_id uuid,
  p_workflow_version_id uuid,
  p_state_key text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select state.canonical_category in ('closed', 'archived')
      or state.behavior_flags @> '{"terminal":true}'::jsonb
    from public.workflow_states state
    where state.workspace_id = p_workspace_id
      and state.workflow_version_id = p_workflow_version_id
      and state.key = p_state_key
  ), false);
$$;

create function app.validate_m3_lead_state_semantics()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  configured_entity_type text;
  is_terminal boolean;
  is_conversion_eligible boolean;
  is_conversion_target boolean;
  is_loss_terminal boolean;
begin
  select definition.entity_type into configured_entity_type
  from public.workflow_versions version
  join public.workflow_definitions definition
    on definition.workspace_id = version.workspace_id
   and definition.id = version.workflow_definition_id
  where version.workspace_id = new.workspace_id
    and version.id = new.workflow_version_id;
  if configured_entity_type is distinct from 'lead' then
    return new;
  end if;

  is_terminal := new.canonical_category in ('closed', 'archived')
    or new.behavior_flags @> '{"terminal":true}'::jsonb;
  is_conversion_eligible :=
    new.behavior_flags @> '{"conversion_eligible":true}'::jsonb;
  is_conversion_target :=
    new.behavior_flags @> '{"conversion_target":true}'::jsonb;
  is_loss_terminal :=
    new.behavior_flags @> '{"loss_terminal":true}'::jsonb;

  if (is_conversion_target or is_loss_terminal) and not is_terminal then
    raise exception using
      errcode = '23514',
      message = 'lead conversion and loss targets must be terminal workflow states';
  end if;
  if is_conversion_target and is_loss_terminal then
    raise exception using
      errcode = '23514',
      message = 'lead workflow state cannot be both conversion and loss target';
  end if;
  if is_conversion_eligible and is_terminal then
    raise exception using
      errcode = '23514',
      message = 'terminal lead workflow state cannot be conversion eligible';
  end if;
  return new;
end;
$$;

create function app.prevent_m3_crm_append_only_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'CRM history is append-only';
end;
$$;

create function app.guard_m3_lead_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'leads cannot be hard deleted';
  end if;
  if app.m3_lead_state_is_terminal(
    old.workspace_id, old.workflow_version_id, old.state_key
  ) then
    raise exception using errcode = '55000', message = 'terminal leads are immutable';
  end if;
  if new.id <> old.id
    or new.workspace_id <> old.workspace_id
    or new.source_key <> old.source_key
    or new.workflow_version_id <> old.workflow_version_id
    or new.workflow_instance_id <> old.workflow_instance_id
    or new.created_by <> old.created_by
    or new.created_at <> old.created_at
    or new.version <> old.version + 1 then
    raise exception using errcode = '55000', message = 'invalid lead version mutation';
  end if;
  return new;
end;
$$;

create function app.assert_m3_lead_workflow_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance public.workflow_instances%rowtype;
  configured_state public.workflow_states%rowtype;
begin
  select state.* into configured_state
  from public.workflow_states state
  where state.workspace_id = new.workspace_id
    and state.workflow_version_id = new.workflow_version_id
    and state.key = new.state_key;
  if not found then
    raise exception using errcode = '23514', message = 'lead workflow state is missing';
  end if;
  select workflow_instance.* into instance
  from public.workflow_instances workflow_instance
  where workflow_instance.workspace_id = new.workspace_id
    and workflow_instance.id = new.workflow_instance_id;
  if not found
    or instance.workflow_version_id <> new.workflow_version_id
    or instance.entity_type <> 'lead'
    or instance.entity_id <> new.id
    or instance.purpose_key <> 'primary'
    or instance.current_state_key <> new.state_key then
    raise exception using errcode = '23514', message = 'lead workflow link is inconsistent';
  end if;
  if configured_state.behavior_flags @> '{"conversion_target":true}'::jsonb then
    if new.converted_deal_id is null or new.lost_reason is not null then
      raise exception using
        errcode = '23514',
        message = 'lead conversion target requires converted deal provenance';
    end if;
  elsif configured_state.behavior_flags @> '{"loss_terminal":true}'::jsonb then
    if new.lost_reason is null or new.converted_deal_id is not null then
      raise exception using
        errcode = '23514',
        message = 'lead loss target requires reason provenance';
    end if;
  elsif new.lost_reason is not null or new.converted_deal_id is not null then
    raise exception using
      errcode = '23514',
      message = 'lead terminal provenance does not match configured state behavior';
  end if;
  return new;
end;
$$;

create function app.guard_m3_task_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'tasks cannot be hard deleted';
  end if;
  if old.state <> 'open' then
    raise exception using errcode = '55000', message = 'terminal tasks are immutable';
  end if;
  if new.state not in ('completed', 'cancelled')
    or new.version <> old.version + 1
    or (pg_catalog.to_jsonb(new) - array[
      'state', 'completed_at', 'completed_by', 'cancelled_at',
      'cancelled_by', 'cancellation_reason', 'version', 'updated_at'
    ]::text[]) is distinct from (pg_catalog.to_jsonb(old) - array[
      'state', 'completed_at', 'completed_by', 'cancelled_at',
      'cancelled_by', 'cancellation_reason', 'version', 'updated_at'
    ]::text[]) then
    raise exception using errcode = '55000', message = 'invalid task lifecycle mutation';
  end if;
  return new;
end;
$$;

create function app.guard_m3_appointment_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'appointments cannot be hard deleted';
  end if;
  if old.status <> 'scheduled' then
    raise exception using errcode = '55000', message = 'resolved appointments are immutable';
  end if;
  if new.status not in ('completed', 'cancelled', 'no_show')
    or new.version <> old.version + 1
    or (pg_catalog.to_jsonb(new) - array[
      'status', 'outcome', 'status_reason', 'resolved_at', 'resolved_by',
      'version', 'updated_at'
    ]::text[]) is distinct from (pg_catalog.to_jsonb(old) - array[
      'status', 'outcome', 'status_reason', 'resolved_at', 'resolved_by',
      'version', 'updated_at'
    ]::text[]) then
    raise exception using errcode = '55000', message = 'invalid appointment lifecycle mutation';
  end if;
  return new;
end;
$$;

create trigger leads_10_guard_mutation
before update or delete on public.leads
for each row execute function app.guard_m3_lead_mutation();
create trigger leads_20_assert_workflow
before insert or update on public.leads
for each row execute function app.assert_m3_lead_workflow_link();
create trigger leads_90_updated_at
before update on public.leads
for each row execute function app.set_updated_at();

create trigger workflow_states_validate_m3_lead_semantics
before insert or update on public.workflow_states
for each row execute function app.validate_m3_lead_state_semantics();

create trigger crm_activities_append_only
before update or delete on public.crm_activities
for each row execute function app.prevent_m3_crm_append_only_mutation();

create trigger crm_tasks_10_lifecycle
before update or delete on public.crm_tasks
for each row execute function app.guard_m3_task_lifecycle();
create trigger crm_tasks_90_updated_at
before update on public.crm_tasks
for each row execute function app.set_updated_at();

create trigger crm_appointments_10_lifecycle
before update or delete on public.crm_appointments
for each row execute function app.guard_m3_appointment_lifecycle();
create trigger crm_appointments_90_updated_at
before update on public.crm_appointments
for each row execute function app.set_updated_at();

create trigger crm_appointment_attendees_append_only
before update or delete on public.crm_appointment_attendees
for each row execute function app.prevent_m3_crm_append_only_mutation();
create trigger crm_command_receipts_append_only
before update or delete on public.crm_command_receipts
for each row execute function app.prevent_m3_crm_append_only_mutation();

alter table public.leads enable row level security;
alter table public.leads force row level security;
alter table public.crm_activities enable row level security;
alter table public.crm_activities force row level security;
alter table public.crm_tasks enable row level security;
alter table public.crm_tasks force row level security;
alter table public.crm_appointments enable row level security;
alter table public.crm_appointments force row level security;
alter table public.crm_appointment_attendees enable row level security;
alter table public.crm_appointment_attendees force row level security;
alter table public.crm_command_receipts enable row level security;
alter table public.crm_command_receipts force row level security;

create policy leads_select
on public.leads for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy crm_activities_select
on public.crm_activities for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy crm_tasks_select
on public.crm_tasks for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy crm_appointments_select
on public.crm_appointments for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));
create policy crm_appointment_attendees_select
on public.crm_appointment_attendees for select to authenticated
using (app.can_read_m3_crm(workspace_id, 'crm.read'));

revoke all on table
  public.leads,
  public.crm_activities,
  public.crm_tasks,
  public.crm_appointments,
  public.crm_appointment_attendees,
  public.crm_command_receipts
from public, anon, authenticated, service_role;

grant select on table
  public.leads,
  public.crm_activities,
  public.crm_tasks,
  public.crm_appointments,
  public.crm_appointment_attendees
to authenticated;

grant select on table
  public.leads,
  public.crm_activities,
  public.crm_tasks,
  public.crm_appointments,
  public.crm_appointment_attendees,
  public.crm_command_receipts
to service_role;

create function app.m3_list_leads(p_workspace_id uuid)
returns table (
  lead_id uuid,
  prospect_party_id uuid,
  source_key text,
  assignee_membership_id uuid,
  summary text,
  next_action_at timestamptz,
  state_key text,
  version bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_m3_crm_permission(p_workspace_id, 'crm.read', false);
  return query
  select
    lead.id, lead.prospect_party_id, lead.source_key,
    lead.assignee_membership_id, lead.summary, lead.next_action_at,
    lead.state_key, lead.version, lead.created_at
  from public.leads lead
  where lead.workspace_id = p_workspace_id
  order by lead.updated_at desc, lead.id desc
  limit 500;
end;
$$;

create function app.m3_get_lead(p_workspace_id uuid, p_lead_id uuid)
returns table (
  lead_id uuid,
  prospect_party_id uuid,
  source_key text,
  assignee_membership_id uuid,
  summary text,
  next_action_at timestamptz,
  state_key text,
  version bigint,
  created_at timestamptz,
  interested_inventory_unit_id uuid,
  lost_reason text,
  converted_deal_id uuid,
  workflow_instance_id uuid,
  conversion_eligible boolean,
  available_transitions jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_m3_crm_permission(p_workspace_id, 'crm.read', false);
  return query
  select
    lead.id, lead.prospect_party_id, lead.source_key,
    lead.assignee_membership_id, lead.summary, lead.next_action_at,
    lead.state_key, lead.version, lead.created_at,
    lead.interested_inventory_unit_id, lead.lost_reason,
    lead.converted_deal_id, lead.workflow_instance_id,
    coalesce((
      select state.behavior_flags @> '{"conversion_eligible":true}'::jsonb
      from public.workflow_states state
      where state.workspace_id = lead.workspace_id
        and state.workflow_version_id = lead.workflow_version_id
        and state.key = lead.state_key
    ), false),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'transitionKey', permitted.transition_key,
          'toStateKey', permitted.to_state_key,
          'reasonRequired', permitted.reason_required,
          'labels', permitted.labels
        ) order by permitted.sort_order, permitted.transition_key
      )
      from (
        select
          transition.key as transition_key,
          transition.to_state_key,
          transition.reason_required
            or target.behavior_flags @> '{"loss_terminal":true}'::jsonb
            as reason_required,
          target.labels,
          target.sort_order
        from public.workflow_instances instance
        join public.workflow_transitions transition
          on transition.workspace_id = instance.workspace_id
         and transition.workflow_version_id = instance.workflow_version_id
         and transition.from_state_key = instance.current_state_key
        join public.workflow_states target
          on target.workspace_id = transition.workspace_id
         and target.workflow_version_id = transition.workflow_version_id
         and target.key = transition.to_state_key
        where instance.workspace_id = lead.workspace_id
          and instance.id = lead.workflow_instance_id
          and instance.lifecycle_status = 'active'
          and not (
            target.behavior_flags @> '{"conversion_target":true}'::jsonb
          )
          and app.has_permission(lead.workspace_id, transition.permission_key)
        order by target.sort_order, transition.key
        limit 100
      ) permitted
    ), '[]'::jsonb)
  from public.leads lead
  where lead.workspace_id = p_workspace_id and lead.id = p_lead_id;
  if not found then
    raise exception using errcode = '23503', message = 'lead does not exist';
  end if;
end;
$$;

create function app.m3_list_crm_timeline(
  p_workspace_id uuid,
  p_party_id uuid,
  p_lead_id uuid,
  p_deal_id uuid
)
returns table (
  activity_id uuid,
  party_id uuid,
  lead_id uuid,
  deal_id uuid,
  activity_type text,
  direction text,
  subject text,
  body text,
  occurred_at timestamptz,
  actor_user_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_m3_crm_permission(p_workspace_id, 'crm.read', false);
  return query
  select
    activity.id, activity.party_id, activity.lead_id, activity.deal_id,
    activity.activity_type, activity.direction, activity.subject,
    activity.body, activity.occurred_at, activity.actor_user_id
  from public.crm_activities activity
  where activity.workspace_id = p_workspace_id
    and (p_party_id is null or activity.party_id = p_party_id)
    and (p_lead_id is null or activity.lead_id = p_lead_id)
    and (p_deal_id is null or activity.deal_id = p_deal_id)
  order by activity.occurred_at desc, activity.id desc
  limit 500;
end;
$$;

create function app.m3_list_tasks(p_workspace_id uuid)
returns table (
  task_id uuid,
  party_id uuid,
  lead_id uuid,
  deal_id uuid,
  assignee_membership_id uuid,
  title text,
  description text,
  priority text,
  due_at timestamptz,
  reminder_at timestamptz,
  state text,
  completed_at timestamptz,
  completed_by uuid,
  cancelled_at timestamptz,
  cancellation_reason text,
  version bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_m3_crm_permission(p_workspace_id, 'crm.read', false);
  return query
  select
    task.id, task.party_id, task.lead_id, task.deal_id,
    task.assignee_membership_id, task.title, task.description, task.priority,
    task.due_at, task.reminder_at, task.state, task.completed_at,
    task.completed_by, task.cancelled_at, task.cancellation_reason,
    task.version, task.created_at
  from public.crm_tasks task
  where task.workspace_id = p_workspace_id
  order by
    case task.state when 'open' then 0 else 1 end,
    task.due_at, task.id
  limit 500;
end;
$$;

create function app.m3_list_appointments(p_workspace_id uuid)
returns table (
  appointment_id uuid,
  lead_id uuid,
  deal_id uuid,
  title text,
  starts_at timestamptz,
  ends_at timestamptz,
  timezone text,
  location_id uuid,
  remote_details text,
  notes text,
  attendee_party_ids uuid[],
  status text,
  outcome text,
  status_reason text,
  resolved_at timestamptz,
  version bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_m3_crm_permission(p_workspace_id, 'crm.read', false);
  return query
  select
    appointment.id, appointment.lead_id, appointment.deal_id,
    appointment.title, appointment.starts_at, appointment.ends_at,
    appointment.timezone, appointment.location_id,
    appointment.remote_details, appointment.notes,
    coalesce((
      select pg_catalog.array_agg(attendee.party_id order by attendee.party_id)
      from public.crm_appointment_attendees attendee
      where attendee.workspace_id = appointment.workspace_id
        and attendee.appointment_id = appointment.id
    ), '{}'::uuid[]),
    appointment.status, appointment.outcome, appointment.status_reason,
    appointment.resolved_at, appointment.version, appointment.created_at
  from public.crm_appointments appointment
  where appointment.workspace_id = p_workspace_id
  order by appointment.starts_at, appointment.id
  limit 500;
end;
$$;

create function app.m3_create_lead(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_source_key text,
  p_summary text,
  p_prospect_party_id uuid,
  p_interested_inventory_unit_id uuid,
  p_assignee_membership_id uuid,
  p_next_action_at timestamptz,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  lead_id uuid,
  aggregate_version bigint,
  state_key text,
  workflow_event_id uuid,
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
  normalized_key text;
  normalized_source_key text;
  normalized_summary text;
  fingerprint text;
  replay_result jsonb;
  configured_workflow_version_id uuid;
  configured_initial_state text;
  configured_canonical_status text;
  new_lead_id uuid;
  new_workflow_instance_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.create', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_source_key := pg_catalog.lower(pg_catalog.btrim(coalesce(p_source_key, '')));
  normalized_summary := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_summary, '')), '\s+', ' ', 'g'
  );
  if normalized_source_key !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or normalized_summary = ''
    or pg_catalog.char_length(normalized_summary) > 2000
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid lead create command';
  end if;
  perform app.assert_m3_crm_links(
    p_workspace_id, p_prospect_party_id, null, null
  );
  if p_interested_inventory_unit_id is not null and not exists (
    select 1 from public.inventory_units inventory
    where inventory.workspace_id = p_workspace_id
      and inventory.id = p_interested_inventory_unit_id
      and inventory.status not in ('closed', 'archived')
  ) then
    raise exception using errcode = '23514', message = 'available workspace inventory interest is required';
  end if;
  perform app.assert_m3_crm_assignee(
    p_workspace_id, p_assignee_membership_id, actor_user_id
  );

  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'sourceKey', normalized_source_key,
    'summary', normalized_summary,
    'prospectPartyId', p_prospect_party_id,
    'interestedInventoryUnitId', p_interested_inventory_unit_id,
    'assigneeMembershipId', p_assignee_membership_id,
    'nextActionAt', p_next_action_at
  ));
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_create_lead', normalized_key, fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'lead_id')::uuid,
      (replay_result ->> 'aggregate_version')::bigint,
      replay_result ->> 'state_key',
      (replay_result ->> 'workflow_event_id')::uuid,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select version.id, version.initial_state_key, state.canonical_category
    into configured_workflow_version_id, configured_initial_state,
      configured_canonical_status
  from public.workflow_definitions definition
  join public.workflow_versions version
    on version.workspace_id = definition.workspace_id
   and version.workflow_definition_id = definition.id
   and version.status = 'active'
  join public.workflow_states state
    on state.workspace_id = version.workspace_id
   and state.workflow_version_id = version.id
   and state.key = version.initial_state_key
  where definition.workspace_id = p_workspace_id
    and definition.entity_type = 'lead'
    and definition.purpose_key = 'primary'
    and definition.status = 'active';
  if not found then
    raise exception using errcode = '23514', message = 'active primary lead workflow is required';
  end if;

  new_lead_id := pg_catalog.gen_random_uuid();
  new_workflow_instance_id := pg_catalog.gen_random_uuid();
  insert into public.workflow_instances (
    id, workspace_id, workflow_version_id, entity_type, entity_id,
    purpose_key, current_state_key, canonical_status, lifecycle_status, version
  ) values (
    new_workflow_instance_id, p_workspace_id, configured_workflow_version_id,
    'lead', new_lead_id, 'primary', configured_initial_state,
    configured_canonical_status, 'active', 1
  );
  insert into public.leads (
    id, workspace_id, source_key, summary, prospect_party_id,
    interested_inventory_unit_id, assignee_membership_id, next_action_at,
    workflow_version_id, workflow_instance_id, state_key, version, created_by
  ) values (
    new_lead_id, p_workspace_id, normalized_source_key, normalized_summary,
    p_prospect_party_id, p_interested_inventory_unit_id,
    p_assignee_membership_id, p_next_action_at,
    configured_workflow_version_id, new_workflow_instance_id,
    configured_initial_state, 1, actor_user_id
  );

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'lead.created',
    p_entity_type => 'lead',
    p_entity_id => new_lead_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'source_key', normalized_source_key,
      'prospect_party_id', p_prospect_party_id,
      'interested_inventory_unit_id', p_interested_inventory_unit_id,
      'assignee_membership_id', p_assignee_membership_id,
      'workflow_version_id', configured_workflow_version_id,
      'workflow_instance_id', new_workflow_instance_id,
      'state_key', configured_initial_state,
      'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'lead.created', 'lead', new_lead_id, 1,
    pg_catalog.jsonb_build_object(
      'leadId', new_lead_id,
      'workflowVersionId', configured_workflow_version_id,
      'stateKey', configured_initial_state,
      'aggregateVersion', 1
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'lead_id', new_lead_id,
    'aggregate_version', 1,
    'state_key', configured_initial_state,
    'workflow_event_id', null,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_create_lead', normalized_key,
    fingerprint, 'lead', new_lead_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_lead_id, 1::bigint, configured_initial_state, null::uuid,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_update_lead(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_lead_id uuid,
  p_expected_version bigint,
  p_update_summary boolean,
  p_summary text,
  p_update_interest boolean,
  p_interested_inventory_unit_id uuid,
  p_update_assignee boolean,
  p_assignee_membership_id uuid,
  p_update_next_action boolean,
  p_next_action_at timestamptz,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  lead_id uuid,
  aggregate_version bigint,
  state_key text,
  workflow_event_id uuid,
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
  normalized_key text;
  normalized_summary text;
  fingerprint text;
  replay_result jsonb;
  locked_lead public.leads%rowtype;
  next_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.update', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_version is null or p_expected_version < 1
    or p_update_summary is null or p_update_interest is null
    or p_update_assignee is null or p_update_next_action is null
    or not (p_update_summary or p_update_interest
      or p_update_assignee or p_update_next_action)
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid lead update command';
  end if;
  normalized_summary := case when p_update_summary then
    pg_catalog.regexp_replace(
      pg_catalog.btrim(coalesce(p_summary, '')), '\s+', ' ', 'g'
    ) else null end;
  if p_update_summary and (
    normalized_summary = '' or pg_catalog.char_length(normalized_summary) > 2000
  ) then
    raise exception using errcode = '22023', message = 'invalid lead summary';
  end if;
  if p_update_interest and p_interested_inventory_unit_id is not null
    and not exists (
      select 1 from public.inventory_units inventory
      where inventory.workspace_id = p_workspace_id
        and inventory.id = p_interested_inventory_unit_id
        and inventory.status not in ('closed', 'archived')
    ) then
    raise exception using errcode = '23514', message = 'available workspace inventory interest is required';
  end if;
  if p_update_assignee then
    perform app.assert_m3_crm_assignee(
      p_workspace_id, p_assignee_membership_id, actor_user_id
    );
  end if;

  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'leadId', p_lead_id,
    'expectedVersion', p_expected_version,
    'updateSummary', p_update_summary,
    'summary', case when p_update_summary then normalized_summary else null end,
    'updateInterest', p_update_interest,
    'interestedInventoryUnitId', case when p_update_interest
      then p_interested_inventory_unit_id else null end,
    'updateAssignee', p_update_assignee,
    'assigneeMembershipId', case when p_update_assignee
      then p_assignee_membership_id else null end,
    'updateNextAction', p_update_next_action,
    'nextActionAt', case when p_update_next_action then p_next_action_at else null end
  ));
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_update_lead', normalized_key, fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'lead_id')::uuid,
      (replay_result ->> 'aggregate_version')::bigint,
      replay_result ->> 'state_key',
      (replay_result ->> 'workflow_event_id')::uuid,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select lead.* into locked_lead
  from public.leads lead
  where lead.workspace_id = p_workspace_id and lead.id = p_lead_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'lead does not exist';
  end if;
  if app.m3_lead_state_is_terminal(
    locked_lead.workspace_id,
    locked_lead.workflow_version_id,
    locked_lead.state_key
  ) then
    raise exception using errcode = '23514', message = 'terminal lead cannot be updated';
  end if;
  if locked_lead.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'lead version conflict';
  end if;
  next_version := locked_lead.version + 1;
  update public.leads
  set summary = case when p_update_summary then normalized_summary else summary end,
      interested_inventory_unit_id = case when p_update_interest
        then p_interested_inventory_unit_id else interested_inventory_unit_id end,
      assignee_membership_id = case when p_update_assignee
        then p_assignee_membership_id else assignee_membership_id end,
      next_action_at = case when p_update_next_action
        then p_next_action_at else next_action_at end,
      version = next_version
  where workspace_id = p_workspace_id and id = p_lead_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'lead.updated',
    p_entity_type => 'lead',
    p_entity_id => p_lead_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'assignee_membership_id', locked_lead.assignee_membership_id,
      'interested_inventory_unit_id', locked_lead.interested_inventory_unit_id,
      'next_action_at', locked_lead.next_action_at,
      'version', locked_lead.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'assignee_membership_id', case when p_update_assignee
        then p_assignee_membership_id else locked_lead.assignee_membership_id end,
      'interested_inventory_unit_id', case when p_update_interest
        then p_interested_inventory_unit_id
        else locked_lead.interested_inventory_unit_id end,
      'next_action_at', case when p_update_next_action
        then p_next_action_at else locked_lead.next_action_at end,
      'summary_updated', p_update_summary,
      'version', next_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'lead.updated', 'lead', p_lead_id, next_version,
    pg_catalog.jsonb_build_object(
      'leadId', p_lead_id,
      'stateKey', locked_lead.state_key,
      'aggregateVersion', next_version
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'lead_id', p_lead_id,
    'aggregate_version', next_version,
    'state_key', locked_lead.state_key,
    'workflow_event_id', null,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_update_lead', normalized_key,
    fingerprint, 'lead', p_lead_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_lead_id, next_version, locked_lead.state_key, null::uuid,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_lead_field_is_present(
  p_workspace_id uuid,
  p_lead_id uuid,
  p_field_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lead_row public.leads%rowtype;
begin
  select lead.* into lead_row
  from public.leads lead
  where lead.workspace_id = p_workspace_id and lead.id = p_lead_id;
  if not found then
    return false;
  end if;

  if p_field_key = 'lead.summary' then
    return pg_catalog.btrim(lead_row.summary) <> '';
  end if;
  if p_field_key = 'lead.prospect_party_id' then
    return lead_row.prospect_party_id is not null;
  end if;
  if p_field_key = 'lead.interested_inventory_unit_id' then
    return lead_row.interested_inventory_unit_id is not null;
  end if;
  if p_field_key = 'lead.assignee_membership_id' then
    return lead_row.assignee_membership_id is not null;
  end if;
  if p_field_key = 'lead.next_action_at' then
    return lead_row.next_action_at is not null;
  end if;

  return exists (
    select 1
    from public.custom_field_values field_value
    join public.custom_field_definitions definition
      on definition.workspace_id = field_value.workspace_id
     and definition.id = field_value.custom_field_definition_id
     and definition.entity_type = 'lead'
     and definition.key = p_field_key
     and definition.status = 'active'
    join public.custom_field_versions version
      on version.workspace_id = field_value.workspace_id
     and version.id = field_value.custom_field_version_id
     and version.status = 'active'
    where field_value.workspace_id = p_workspace_id
      and field_value.entity_type = 'lead'
      and field_value.entity_id = p_lead_id
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

create function app.m3_lead_required_fields_satisfied(
  p_workspace_id uuid,
  p_lead_id uuid,
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
    where not app.m3_lead_field_is_present(
      p_workspace_id, p_lead_id, field.key
    )
  );
$$;

create function app.m3_transition_lead(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_lead_id uuid,
  p_expected_version bigint,
  p_transition_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  lead_id uuid,
  aggregate_version bigint,
  state_key text,
  workflow_event_id uuid,
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
  normalized_key text;
  normalized_transition_key text;
  normalized_reason text;
  fingerprint text;
  replay_result jsonb;
  locked_lead public.leads%rowtype;
  configured_transition public.workflow_transitions%rowtype;
  target_state public.workflow_states%rowtype;
  combined_required_fields text[];
  next_version bigint;
  new_workflow_event_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.update', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_transition_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_transition_key, ''))
  );
  normalized_reason := nullif(pg_catalog.btrim(p_reason), '');
  if p_expected_version is null or p_expected_version < 1
    or normalized_transition_key !~ '^[a-z][a-z0-9_]*$'
    or pg_catalog.char_length(normalized_reason) > 2000
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid lead transition command';
  end if;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'leadId', p_lead_id,
    'expectedVersion', p_expected_version,
    'transitionKey', normalized_transition_key,
    'reason', normalized_reason
  ));
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_transition_lead', normalized_key,
    fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'lead_id')::uuid,
      (replay_result ->> 'aggregate_version')::bigint,
      replay_result ->> 'state_key',
      (replay_result ->> 'workflow_event_id')::uuid,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select lead.* into locked_lead
  from public.leads lead
  where lead.workspace_id = p_workspace_id and lead.id = p_lead_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'lead does not exist';
  end if;
  if app.m3_lead_state_is_terminal(
    locked_lead.workspace_id,
    locked_lead.workflow_version_id,
    locked_lead.state_key
  ) then
    raise exception using errcode = '23514', message = 'terminal lead cannot transition';
  end if;
  if locked_lead.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'lead version conflict';
  end if;

  select transition.* into configured_transition
  from public.workflow_transitions transition
  where transition.workspace_id = p_workspace_id
    and transition.workflow_version_id = locked_lead.workflow_version_id
    and transition.key = normalized_transition_key
    and transition.from_state_key = locked_lead.state_key;
  if not found then
    raise exception using errcode = '23514', message = 'configured lead transition is unavailable';
  end if;
  select state.* into target_state
  from public.workflow_states state
  where state.workspace_id = p_workspace_id
    and state.workflow_version_id = locked_lead.workflow_version_id
    and state.key = configured_transition.to_state_key;
  if not found then
    raise exception using errcode = '23514', message = 'configured lead target state is missing';
  end if;
  if target_state.behavior_flags @> '{"conversion_target":true}'::jsonb then
    raise exception using errcode = '23514', message = 'lead conversion requires the conversion command';
  end if;
  if not app.has_permission(p_workspace_id, configured_transition.permission_key) then
    raise exception using errcode = '42501', message = 'configured transition permission is required';
  end if;
  if configured_transition.reason_required and normalized_reason is null then
    raise exception using errcode = '23514', message = 'lead transition reason is required';
  end if;
  if target_state.behavior_flags @> '{"loss_terminal":true}'::jsonb
    and normalized_reason is null then
    raise exception using errcode = '23514', message = 'lead loss reason is required';
  end if;
  combined_required_fields := configured_transition.required_fields
    || target_state.required_fields;
  if not app.m3_lead_required_fields_satisfied(
    p_workspace_id, p_lead_id, combined_required_fields
  ) then
    raise exception using errcode = '23514', message = 'lead transition required fields are incomplete';
  end if;
  if configured_transition.guard_key is not null
    and configured_transition.guard_key <> 'required_fields_complete' then
    raise exception using errcode = '23514', message = 'lead transition guard is not satisfied';
  end if;

  next_version := locked_lead.version + 1;
  update public.workflow_instances
  set current_state_key = configured_transition.to_state_key,
      canonical_status = target_state.canonical_category,
      lifecycle_status = case when target_state.canonical_category in ('closed', 'archived')
          or target_state.behavior_flags @> '{"terminal":true}'::jsonb
        then 'completed' else 'active' end,
      completed_at = case when target_state.canonical_category in ('closed', 'archived')
          or target_state.behavior_flags @> '{"terminal":true}'::jsonb
        then pg_catalog.statement_timestamp() else null end,
      version = version + 1
  where workspace_id = p_workspace_id and id = locked_lead.workflow_instance_id;
  update public.leads
  set state_key = configured_transition.to_state_key,
      lost_reason = case when
        target_state.behavior_flags @> '{"loss_terminal":true}'::jsonb
        then normalized_reason else null end,
      version = next_version
  where workspace_id = p_workspace_id and id = p_lead_id;

  new_workflow_event_id := pg_catalog.gen_random_uuid();
  insert into public.workflow_events (
    id, workspace_id, workflow_instance_id, transition_id, entity_type,
    entity_id, from_state_key, to_state_key, aggregate_version, reason,
    actor_user_id, request_id, correlation_id
  ) values (
    new_workflow_event_id, p_workspace_id, locked_lead.workflow_instance_id,
    configured_transition.id, 'lead', p_lead_id, locked_lead.state_key,
    configured_transition.to_state_key, next_version, normalized_reason,
    actor_user_id, p_request_id, p_correlation_id
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'lead.transitioned',
    p_entity_type => 'lead',
    p_entity_id => p_lead_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'state_key', locked_lead.state_key, 'version', locked_lead.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'state_key', configured_transition.to_state_key,
      'version', next_version,
      'workflow_event_id', new_workflow_event_id
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_key,
      'transition_key', normalized_transition_key
    )
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'lead.transitioned', 'lead', p_lead_id, next_version,
    pg_catalog.jsonb_build_object(
      'leadId', p_lead_id,
      'fromStateKey', locked_lead.state_key,
      'toStateKey', configured_transition.to_state_key,
      'workflowEventId', new_workflow_event_id,
      'aggregateVersion', next_version
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'lead_id', p_lead_id,
    'aggregate_version', next_version,
    'state_key', configured_transition.to_state_key,
    'workflow_event_id', new_workflow_event_id,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_transition_lead', normalized_key,
    fingerprint, 'lead', p_lead_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_lead_id, next_version, configured_transition.to_state_key,
    new_workflow_event_id, new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_convert_lead(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_lead_id uuid,
  p_expected_version bigint,
  p_deal_type_key text,
  p_currency_code text,
  p_location_id uuid,
  p_legal_entity_id uuid,
  p_owner_membership_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  lead_id uuid,
  deal_id uuid,
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
  normalized_key text;
  normalized_deal_type_key text;
  normalized_currency text;
  resolved_legal_entity_id uuid;
  resolved_owner_membership_id uuid;
  command_fingerprint text;
  conversion_fingerprint text;
  replay_result jsonb;
  prior_conversion public.crm_command_receipts%rowtype;
  locked_lead public.leads%rowtype;
  current_state public.workflow_states%rowtype;
  configured_transition public.workflow_transitions%rowtype;
  target_state public.workflow_states%rowtype;
  combined_required_fields text[];
  conversion_transition_count integer;
  created_deal record;
  participant_result record;
  next_version bigint;
  new_workflow_event_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
  deal_command_key text;
  participant_command_key text;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.update', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_deal_type_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_deal_type_key, ''))
  );
  normalized_currency := pg_catalog.upper(
    pg_catalog.btrim(coalesce(p_currency_code, ''))
  );
  if p_expected_version is null or p_expected_version < 1
    or normalized_deal_type_key
      !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'
    or normalized_currency !~ '^[A-Z]{3}$'
    or p_location_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid lead conversion command';
  end if;

  resolved_legal_entity_id := p_legal_entity_id;
  if resolved_legal_entity_id is null then
    select case
      when pg_catalog.count(*) = 1
        then pg_catalog.min(entity.id::text)::uuid
      else null
    end
      into resolved_legal_entity_id
    from public.legal_entities entity
    where entity.workspace_id = p_workspace_id and entity.status = 'active';
  end if;
  if resolved_legal_entity_id is null then
    raise exception using
      errcode = '23514',
      message = 'exactly one active legal entity is required when none is selected';
  end if;
  resolved_owner_membership_id := p_owner_membership_id;
  if resolved_owner_membership_id is null then
    select membership.id into resolved_owner_membership_id
    from public.workspace_memberships membership
    where membership.workspace_id = p_workspace_id
      and membership.user_id = actor_user_id
      and membership.status = 'active';
  end if;
  perform app.assert_m3_crm_assignee(
    p_workspace_id, resolved_owner_membership_id, actor_user_id
  );

  conversion_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'leadId', p_lead_id,
      'dealTypeKey', normalized_deal_type_key,
      'currencyCode', normalized_currency,
      'locationId', p_location_id,
      'legalEntityId', resolved_legal_entity_id,
      'ownerMembershipId', resolved_owner_membership_id
    )
  );
  command_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'conversionFingerprint', conversion_fingerprint,
      'expectedVersion', p_expected_version
    )
  );
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_convert_lead', normalized_key,
    command_fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'lead_id')::uuid,
      (replay_result ->> 'deal_id')::uuid,
      (replay_result ->> 'aggregate_version')::bigint,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select lead.* into locked_lead
  from public.leads lead
  where lead.workspace_id = p_workspace_id and lead.id = p_lead_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'lead does not exist';
  end if;
  if locked_lead.converted_deal_id is not null then
    select receipt.* into prior_conversion
    from public.crm_command_receipts receipt
    where receipt.workspace_id = p_workspace_id
      and receipt.command_type = 'm3_convert_lead'
      and receipt.entity_type = 'lead'
      and receipt.entity_id = p_lead_id
    order by receipt.created_at, receipt.id
    limit 1;
    if not found
      or prior_conversion.result ->> 'conversion_fingerprint'
        <> conversion_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'lead was already converted with different configured input';
    end if;
    perform app.record_m3_crm_command(
      p_workspace_id, actor_user_id, 'm3_convert_lead', normalized_key,
      command_fingerprint, 'lead', p_lead_id, prior_conversion.result,
      prior_conversion.audit_event_id, prior_conversion.outbox_event_id
    );
    return query select
      p_lead_id,
      locked_lead.converted_deal_id,
      locked_lead.version,
      prior_conversion.audit_event_id,
      prior_conversion.outbox_event_id,
      true;
    return;
  end if;
  if locked_lead.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'lead version conflict';
  end if;
  select state.* into current_state
  from public.workflow_states state
  where state.workspace_id = p_workspace_id
    and state.workflow_version_id = locked_lead.workflow_version_id
    and state.key = locked_lead.state_key;
  if not found
    or not (
      current_state.behavior_flags @> '{"conversion_eligible":true}'::jsonb
    )
    or locked_lead.prospect_party_id is null then
    raise exception using
      errcode = '23514',
      message = 'conversion-eligible lead with an active prospect party is required';
  end if;
  perform app.assert_m3_crm_links(
    p_workspace_id, locked_lead.prospect_party_id, p_lead_id, null
  );

  select pg_catalog.count(*)::integer into conversion_transition_count
  from public.workflow_transitions transition
  join public.workflow_states state
    on state.workspace_id = transition.workspace_id
   and state.workflow_version_id = transition.workflow_version_id
   and state.key = transition.to_state_key
  where transition.workspace_id = p_workspace_id
    and transition.workflow_version_id = locked_lead.workflow_version_id
    and transition.from_state_key = locked_lead.state_key
    and state.behavior_flags @> '{"conversion_target":true}'::jsonb;
  if conversion_transition_count <> 1 then
    raise exception using
      errcode = '23514',
      message = 'exactly one configured lead conversion transition is required';
  end if;
  select transition.* into configured_transition
  from public.workflow_transitions transition
  join public.workflow_states state
    on state.workspace_id = transition.workspace_id
   and state.workflow_version_id = transition.workflow_version_id
   and state.key = transition.to_state_key
  where transition.workspace_id = p_workspace_id
    and transition.workflow_version_id = locked_lead.workflow_version_id
    and transition.from_state_key = locked_lead.state_key
    and state.behavior_flags @> '{"conversion_target":true}'::jsonb;
  select state.* into target_state
  from public.workflow_states state
  where state.workspace_id = p_workspace_id
    and state.workflow_version_id = locked_lead.workflow_version_id
    and state.key = configured_transition.to_state_key;
  if not (
    target_state.behavior_flags @> '{"terminal":true}'::jsonb
    or target_state.canonical_category in ('closed', 'archived')
  ) then
    raise exception using
      errcode = '23514',
      message = 'configured lead conversion target must be terminal';
  end if;
  if not app.has_permission(p_workspace_id, configured_transition.permission_key) then
    raise exception using errcode = '42501', message = 'configured conversion permission is required';
  end if;
  combined_required_fields := configured_transition.required_fields
    || target_state.required_fields;
  if not app.m3_lead_required_fields_satisfied(
    p_workspace_id, p_lead_id, combined_required_fields
  ) then
    raise exception using errcode = '23514', message = 'lead conversion required fields are incomplete';
  end if;
  if configured_transition.guard_key is not null
    and configured_transition.guard_key <> 'lead_conversion_requirements_met' then
    raise exception using errcode = '23514', message = 'lead conversion guard is not satisfied';
  end if;
  if configured_transition.reason_required then
    raise exception using
      errcode = '23514',
      message = 'configured lead conversion transition cannot require a reason';
  end if;

  deal_command_key := 'lead-deal-' || conversion_fingerprint;
  select * into created_deal
  from app.m3_create_deal(
    p_workspace_id, deal_command_key, normalized_deal_type_key,
    normalized_currency, p_location_id, resolved_legal_entity_id,
    resolved_owner_membership_id, p_lead_id,
    'Created from configured CRM lead', p_request_id, p_correlation_id
  );
  participant_command_key := 'lead-buyer-' || conversion_fingerprint;
  select * into participant_result
  from app.m3_add_deal_participant(
    p_workspace_id, participant_command_key, created_deal.deal_id,
    created_deal.aggregate_version, locked_lead.prospect_party_id,
    'buyer', true, p_request_id, p_correlation_id
  );

  next_version := locked_lead.version + 1;
  update public.workflow_instances
  set current_state_key = configured_transition.to_state_key,
      canonical_status = target_state.canonical_category,
      lifecycle_status = 'completed',
      completed_at = pg_catalog.statement_timestamp(),
      version = version + 1
  where workspace_id = p_workspace_id and id = locked_lead.workflow_instance_id;
  update public.leads
  set state_key = configured_transition.to_state_key,
      converted_deal_id = created_deal.deal_id,
      version = next_version
  where workspace_id = p_workspace_id and id = p_lead_id;

  new_workflow_event_id := pg_catalog.gen_random_uuid();
  insert into public.workflow_events (
    id, workspace_id, workflow_instance_id, transition_id, entity_type,
    entity_id, from_state_key, to_state_key, aggregate_version, reason,
    actor_user_id, request_id, correlation_id
  ) values (
    new_workflow_event_id, p_workspace_id, locked_lead.workflow_instance_id,
    configured_transition.id, 'lead', p_lead_id, locked_lead.state_key,
    configured_transition.to_state_key, next_version, null,
    actor_user_id, p_request_id,
    p_correlation_id
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'lead.converted',
    p_entity_type => 'lead',
    p_entity_id => p_lead_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'state_key', locked_lead.state_key, 'version', locked_lead.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'state_key', configured_transition.to_state_key,
      'converted_deal_id', created_deal.deal_id,
      'workflow_event_id', new_workflow_event_id,
      'version', next_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'lead.converted', 'lead', p_lead_id, next_version,
    pg_catalog.jsonb_build_object(
      'leadId', p_lead_id,
      'dealId', created_deal.deal_id,
      'workflowEventId', new_workflow_event_id,
      'aggregateVersion', next_version
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'lead_id', p_lead_id,
    'deal_id', created_deal.deal_id,
    'aggregate_version', next_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id,
    'conversion_fingerprint', conversion_fingerprint
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_convert_lead', normalized_key,
    command_fingerprint, 'lead', p_lead_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_lead_id, created_deal.deal_id, next_version,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_create_activity(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_activity_type text,
  p_direction text,
  p_subject text,
  p_body text,
  p_channel_key text,
  p_occurred_at timestamptz,
  p_party_id uuid,
  p_lead_id uuid,
  p_deal_id uuid,
  p_provider_reference text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  activity_id uuid,
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
  normalized_key text;
  normalized_subject text;
  normalized_body text;
  normalized_channel_key text;
  normalized_provider_reference text;
  fingerprint text;
  replay_result jsonb;
  new_activity_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.update', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_subject := pg_catalog.btrim(coalesce(p_subject, ''));
  normalized_body := nullif(pg_catalog.btrim(p_body), '');
  normalized_channel_key := nullif(pg_catalog.lower(pg_catalog.btrim(p_channel_key)), '');
  normalized_provider_reference := nullif(pg_catalog.btrim(p_provider_reference), '');
  if p_activity_type not in (
      'note', 'call', 'email_reference', 'text_reference', 'appointment',
      'assignment', 'status_change', 'document', 'deal_event'
    )
    or p_direction not in ('inbound', 'outbound', 'internal')
    or normalized_subject = '' or pg_catalog.char_length(normalized_subject) > 200
    or pg_catalog.char_length(normalized_body) > 10000
    or (normalized_channel_key is not null and normalized_channel_key
      !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$')
    or pg_catalog.char_length(normalized_provider_reference) > 500
    or (normalized_provider_reference is not null and normalized_channel_key is null)
    or p_occurred_at is null
    or pg_catalog.num_nonnulls(p_party_id, p_lead_id, p_deal_id) = 0
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid CRM activity command';
  end if;
  perform app.assert_m3_crm_links(
    p_workspace_id, p_party_id, p_lead_id, p_deal_id
  );
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'activityType', p_activity_type,
    'direction', p_direction,
    'subject', normalized_subject,
    'body', normalized_body,
    'channelKey', normalized_channel_key,
    'occurredAt', p_occurred_at,
    'partyId', p_party_id,
    'leadId', p_lead_id,
    'dealId', p_deal_id,
    'providerReference', normalized_provider_reference
  ));
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_create_activity', normalized_key,
    fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'activity_id')::uuid,
      (replay_result ->> 'aggregate_version')::bigint,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  new_activity_id := pg_catalog.gen_random_uuid();
  insert into public.crm_activities (
    id, workspace_id, party_id, lead_id, deal_id, activity_type,
    channel_key, direction, subject, body, provider_reference,
    occurred_at, actor_user_id
  ) values (
    new_activity_id, p_workspace_id, p_party_id, p_lead_id, p_deal_id,
    p_activity_type, normalized_channel_key, p_direction,
    normalized_subject, normalized_body, normalized_provider_reference,
    p_occurred_at, actor_user_id
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'crm_activity.created',
    p_entity_type => 'crm_activity',
    p_entity_id => new_activity_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'activity_type', p_activity_type,
      'direction', p_direction,
      'party_id', p_party_id,
      'lead_id', p_lead_id,
      'deal_id', p_deal_id,
      'occurred_at', p_occurred_at,
      'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'crm_activity.created', 'crm_activity',
    new_activity_id, 1,
    pg_catalog.jsonb_build_object(
      'activityId', new_activity_id,
      'activityType', p_activity_type,
      'partyId', p_party_id,
      'leadId', p_lead_id,
      'dealId', p_deal_id,
      'aggregateVersion', 1
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'activity_id', new_activity_id,
    'aggregate_version', 1,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_create_activity', normalized_key,
    fingerprint, 'crm_activity', new_activity_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_activity_id, 1::bigint, new_audit_event_id,
    new_outbox_event_id, false;
end;
$$;

create function app.m3_create_task(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_party_id uuid,
  p_lead_id uuid,
  p_deal_id uuid,
  p_assignee_membership_id uuid,
  p_title text,
  p_description text,
  p_priority text,
  p_due_at timestamptz,
  p_reminder_at timestamptz,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  task_id uuid,
  task_state text,
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
  normalized_key text;
  normalized_title text;
  normalized_description text;
  fingerprint text;
  replay_result jsonb;
  new_task_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.update', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_title := pg_catalog.btrim(coalesce(p_title, ''));
  normalized_description := nullif(pg_catalog.btrim(p_description), '');
  if normalized_title = '' or pg_catalog.char_length(normalized_title) > 200
    or pg_catalog.char_length(normalized_description) > 4000
    or p_priority not in ('low', 'normal', 'high', 'urgent')
    or p_due_at is null
    or (p_reminder_at is not null and p_reminder_at > p_due_at)
    or pg_catalog.num_nonnulls(p_party_id, p_lead_id, p_deal_id) = 0
    or p_assignee_membership_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid CRM task command';
  end if;
  perform app.assert_m3_crm_links(
    p_workspace_id, p_party_id, p_lead_id, p_deal_id
  );
  perform app.assert_m3_crm_assignee(
    p_workspace_id, p_assignee_membership_id, actor_user_id
  );
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'partyId', p_party_id,
    'leadId', p_lead_id,
    'dealId', p_deal_id,
    'assigneeMembershipId', p_assignee_membership_id,
    'title', normalized_title,
    'description', normalized_description,
    'priority', p_priority,
    'dueAt', p_due_at,
    'reminderAt', p_reminder_at
  ));
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_create_task', normalized_key, fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'task_id')::uuid,
      replay_result ->> 'task_state',
      (replay_result ->> 'aggregate_version')::bigint,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  new_task_id := pg_catalog.gen_random_uuid();
  insert into public.crm_tasks (
    id, workspace_id, party_id, lead_id, deal_id,
    assignee_membership_id, title, description, priority,
    due_at, reminder_at, created_by
  ) values (
    new_task_id, p_workspace_id, p_party_id, p_lead_id, p_deal_id,
    p_assignee_membership_id, normalized_title, normalized_description,
    p_priority, p_due_at, p_reminder_at, actor_user_id
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'crm_task.created',
    p_entity_type => 'crm_task',
    p_entity_id => new_task_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'party_id', p_party_id, 'lead_id', p_lead_id, 'deal_id', p_deal_id,
      'assignee_membership_id', p_assignee_membership_id,
      'priority', p_priority, 'due_at', p_due_at,
      'state', 'open', 'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'crm_task.created', 'crm_task', new_task_id, 1,
    pg_catalog.jsonb_build_object(
      'taskId', new_task_id,
      'assigneeMembershipId', p_assignee_membership_id,
      'state', 'open', 'aggregateVersion', 1
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'task_id', new_task_id,
    'task_state', 'open',
    'aggregate_version', 1,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_create_task', normalized_key,
    fingerprint, 'crm_task', new_task_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_task_id, 'open'::text, 1::bigint,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.transition_m3_crm_task(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_task_id uuid,
  p_expected_version bigint,
  p_target_state text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  task_id uuid,
  task_state text,
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
  command_type text;
  normalized_key text;
  normalized_reason text;
  fingerprint text;
  replay_result jsonb;
  locked_task public.crm_tasks%rowtype;
  next_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.update', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_reason := nullif(pg_catalog.btrim(p_reason), '');
  command_type := case p_target_state
    when 'completed' then 'm3_complete_task'
    when 'cancelled' then 'm3_cancel_task'
    else null
  end;
  if command_type is null
    or p_expected_version is null or p_expected_version < 1
    or (p_target_state = 'completed' and normalized_reason is not null)
    or (p_target_state = 'cancelled' and normalized_reason is null)
    or pg_catalog.char_length(normalized_reason) > 2000
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid CRM task lifecycle command';
  end if;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'taskId', p_task_id,
    'expectedVersion', p_expected_version,
    'targetState', p_target_state,
    'reason', normalized_reason
  ));
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, command_type, normalized_key, fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'task_id')::uuid,
      replay_result ->> 'task_state',
      (replay_result ->> 'aggregate_version')::bigint,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select task.* into locked_task
  from public.crm_tasks task
  where task.workspace_id = p_workspace_id and task.id = p_task_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'CRM task does not exist';
  end if;
  if locked_task.state <> 'open' then
    raise exception using errcode = '23514', message = 'only open tasks can transition';
  end if;
  if locked_task.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'task version conflict';
  end if;
  next_version := locked_task.version + 1;
  update public.crm_tasks
  set state = p_target_state,
      completed_at = case when p_target_state = 'completed'
        then pg_catalog.statement_timestamp() else null end,
      completed_by = case when p_target_state = 'completed'
        then actor_user_id else null end,
      cancelled_at = case when p_target_state = 'cancelled'
        then pg_catalog.statement_timestamp() else null end,
      cancelled_by = case when p_target_state = 'cancelled'
        then actor_user_id else null end,
      cancellation_reason = case when p_target_state = 'cancelled'
        then normalized_reason else null end,
      version = next_version
  where workspace_id = p_workspace_id and id = p_task_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'crm_task.' || p_target_state,
    p_entity_type => 'crm_task',
    p_entity_id => p_task_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'state', locked_task.state, 'version', locked_task.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'state', p_target_state, 'version', next_version
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'crm_task.' || p_target_state, 'crm_task',
    p_task_id, next_version,
    pg_catalog.jsonb_build_object(
      'taskId', p_task_id,
      'state', p_target_state,
      'aggregateVersion', next_version
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'task_id', p_task_id,
    'task_state', p_target_state,
    'aggregate_version', next_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, command_type, normalized_key,
    fingerprint, 'crm_task', p_task_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_task_id, p_target_state, next_version,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_complete_task(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_task_id uuid,
  p_expected_version bigint,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  task_id uuid,
  task_state text,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language sql
security definer
set search_path = ''
as $$
  select * from app.transition_m3_crm_task(
    p_workspace_id, p_idempotency_key, p_task_id, p_expected_version,
    'completed', null, p_request_id, p_correlation_id
  );
$$;

create function app.m3_cancel_task(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_task_id uuid,
  p_expected_version bigint,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  task_id uuid,
  task_state text,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
)
language sql
security definer
set search_path = ''
as $$
  select * from app.transition_m3_crm_task(
    p_workspace_id, p_idempotency_key, p_task_id, p_expected_version,
    'cancelled', p_reason, p_request_id, p_correlation_id
  );
$$;

create function app.m3_create_appointment(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_lead_id uuid,
  p_deal_id uuid,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_timezone text,
  p_location_id uuid,
  p_remote_details text,
  p_notes text,
  p_attendee_party_ids uuid[],
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  appointment_id uuid,
  appointment_status text,
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
  normalized_key text;
  normalized_title text;
  normalized_timezone text;
  normalized_remote_details text;
  normalized_notes text;
  fingerprint text;
  replay_result jsonb;
  new_appointment_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.update', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_title := pg_catalog.btrim(coalesce(p_title, ''));
  normalized_timezone := pg_catalog.btrim(coalesce(p_timezone, ''));
  normalized_remote_details := nullif(pg_catalog.btrim(p_remote_details), '');
  normalized_notes := nullif(pg_catalog.btrim(p_notes), '');
  if normalized_title = '' or pg_catalog.char_length(normalized_title) > 200
    or p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at
    or normalized_timezone = '' or pg_catalog.char_length(normalized_timezone) > 100
    or not app.m3_timezone_exists(normalized_timezone)
    or pg_catalog.char_length(normalized_remote_details) > 2000
    or pg_catalog.char_length(normalized_notes) > 4000
    or pg_catalog.num_nonnulls(p_lead_id, p_deal_id) = 0
    or p_attendee_party_ids is null
    or pg_catalog.cardinality(p_attendee_party_ids) > 100
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid CRM appointment command';
  end if;
  if (
    select pg_catalog.count(distinct attendee_id)
    from pg_catalog.unnest(p_attendee_party_ids) attendee(attendee_id)
  ) <> pg_catalog.cardinality(p_attendee_party_ids) then
    raise exception using errcode = '22023', message = 'appointment attendees must be unique';
  end if;
  perform app.assert_m3_crm_links(p_workspace_id, null, p_lead_id, p_deal_id);
  if p_location_id is not null and not exists (
    select 1 from public.locations location
    where location.workspace_id = p_workspace_id
      and location.id = p_location_id and location.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace appointment location is required';
  end if;
  if exists (
    select 1
    from pg_catalog.unnest(p_attendee_party_ids) attendee(attendee_id)
    where not exists (
      select 1 from public.parties party
      where party.workspace_id = p_workspace_id
        and party.id = attendee.attendee_id and party.status = 'active'
    )
  ) then
    raise exception using errcode = '23514', message = 'all appointment attendees must be active workspace parties';
  end if;

  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'leadId', p_lead_id, 'dealId', p_deal_id, 'title', normalized_title,
    'startsAt', p_starts_at, 'endsAt', p_ends_at,
    'timezone', normalized_timezone, 'locationId', p_location_id,
    'remoteDetails', normalized_remote_details, 'notes', normalized_notes,
    'attendeePartyIds', pg_catalog.to_jsonb(p_attendee_party_ids)
  ));
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_create_appointment', normalized_key,
    fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'appointment_id')::uuid,
      replay_result ->> 'appointment_status',
      (replay_result ->> 'aggregate_version')::bigint,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  new_appointment_id := pg_catalog.gen_random_uuid();
  insert into public.crm_appointments (
    id, workspace_id, lead_id, deal_id, title, starts_at, ends_at,
    timezone, location_id, remote_details, notes, created_by
  ) values (
    new_appointment_id, p_workspace_id, p_lead_id, p_deal_id,
    normalized_title, p_starts_at, p_ends_at, normalized_timezone,
    p_location_id, normalized_remote_details, normalized_notes, actor_user_id
  );
  insert into public.crm_appointment_attendees (
    workspace_id, appointment_id, party_id
  )
  select p_workspace_id, new_appointment_id, attendee.attendee_id
  from pg_catalog.unnest(p_attendee_party_ids) attendee(attendee_id);

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'crm_appointment.created',
    p_entity_type => 'crm_appointment',
    p_entity_id => new_appointment_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'lead_id', p_lead_id, 'deal_id', p_deal_id,
      'starts_at', p_starts_at, 'ends_at', p_ends_at,
      'timezone', normalized_timezone, 'location_id', p_location_id,
      'attendee_count', pg_catalog.cardinality(p_attendee_party_ids),
      'status', 'scheduled', 'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'crm_appointment.created', 'crm_appointment',
    new_appointment_id, 1,
    pg_catalog.jsonb_build_object(
      'appointmentId', new_appointment_id,
      'leadId', p_lead_id, 'dealId', p_deal_id,
      'status', 'scheduled', 'aggregateVersion', 1
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'appointment_id', new_appointment_id,
    'appointment_status', 'scheduled',
    'aggregate_version', 1,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_create_appointment', normalized_key,
    fingerprint, 'crm_appointment', new_appointment_id, result_payload,
    new_audit_event_id, new_outbox_event_id
  );
  return query select
    new_appointment_id, 'scheduled'::text, 1::bigint,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

create function app.m3_transition_appointment(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_appointment_id uuid,
  p_expected_version bigint,
  p_target_status text,
  p_outcome text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  appointment_id uuid,
  appointment_status text,
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
  normalized_key text;
  normalized_outcome text;
  normalized_reason text;
  fingerprint text;
  replay_result jsonb;
  locked_appointment public.crm_appointments%rowtype;
  next_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_m3_crm_permission(p_workspace_id, 'crm.update', false);
  normalized_key := app.assert_m3_crm_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_outcome := nullif(pg_catalog.btrim(p_outcome), '');
  normalized_reason := nullif(pg_catalog.btrim(p_reason), '');
  if p_expected_version is null or p_expected_version < 1
    or p_target_status not in ('completed', 'cancelled', 'no_show')
    or (p_target_status = 'completed' and normalized_outcome is null)
    or (p_target_status in ('cancelled', 'no_show') and normalized_reason is null)
    or pg_catalog.char_length(normalized_outcome) > 4000
    or pg_catalog.char_length(normalized_reason) > 2000
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid appointment lifecycle command';
  end if;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'appointmentId', p_appointment_id,
    'expectedVersion', p_expected_version,
    'targetStatus', p_target_status,
    'outcome', normalized_outcome,
    'reason', normalized_reason
  ));
  replay_result := app.replay_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_transition_appointment',
    normalized_key, fingerprint
  );
  if replay_result is not null then
    return query select
      (replay_result ->> 'appointment_id')::uuid,
      replay_result ->> 'appointment_status',
      (replay_result ->> 'aggregate_version')::bigint,
      (replay_result ->> 'audit_event_id')::uuid,
      (replay_result ->> 'outbox_event_id')::uuid,
      true;
    return;
  end if;

  select appointment.* into locked_appointment
  from public.crm_appointments appointment
  where appointment.workspace_id = p_workspace_id
    and appointment.id = p_appointment_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'CRM appointment does not exist';
  end if;
  if locked_appointment.status <> 'scheduled' then
    raise exception using errcode = '23514', message = 'only scheduled appointments can transition';
  end if;
  if locked_appointment.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'appointment version conflict';
  end if;
  next_version := locked_appointment.version + 1;
  update public.crm_appointments
  set status = p_target_status,
      outcome = normalized_outcome,
      status_reason = normalized_reason,
      resolved_at = pg_catalog.statement_timestamp(),
      resolved_by = actor_user_id,
      version = next_version
  where workspace_id = p_workspace_id and id = p_appointment_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'crm_appointment.' || p_target_status,
    p_entity_type => 'crm_appointment',
    p_entity_id => p_appointment_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', locked_appointment.status, 'version', locked_appointment.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', p_target_status,
      'outcome_recorded', normalized_outcome is not null,
      'reason_recorded', normalized_reason is not null,
      'version', next_version
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('idempotency_key', normalized_key)
  );
  new_outbox_event_id := app.append_m3_crm_entity_outbox(
    p_workspace_id, 'crm_appointment.' || p_target_status,
    'crm_appointment', p_appointment_id, next_version,
    pg_catalog.jsonb_build_object(
      'appointmentId', p_appointment_id,
      'status', p_target_status,
      'aggregateVersion', next_version
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'appointment_id', p_appointment_id,
    'appointment_status', p_target_status,
    'aggregate_version', next_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  perform app.record_m3_crm_command(
    p_workspace_id, actor_user_id, 'm3_transition_appointment',
    normalized_key, fingerprint, 'crm_appointment', p_appointment_id,
    result_payload, new_audit_event_id, new_outbox_event_id
  );
  return query select
    p_appointment_id, p_target_status, next_version,
    new_audit_event_id, new_outbox_event_id, false;
end;
$$;

revoke all on function app.assert_m3_crm_command_metadata(text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.replay_m3_crm_command(uuid, uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function app.record_m3_crm_command(
  uuid, uuid, text, text, text, text, uuid, jsonb, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.append_m3_crm_entity_outbox(
  uuid, text, text, uuid, bigint, jsonb, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.assert_m3_crm_links(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.assert_m3_crm_assignee(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_timezone_exists(text)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_lead_state_is_terminal(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.validate_m3_lead_state_semantics()
  from public, anon, authenticated, service_role;
revoke all on function app.prevent_m3_crm_append_only_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.guard_m3_lead_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_m3_lead_workflow_link()
  from public, anon, authenticated, service_role;
revoke all on function app.guard_m3_task_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app.guard_m3_appointment_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app.m3_lead_field_is_present(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_lead_required_fields_satisfied(uuid, uuid, text[])
  from public, anon, authenticated, service_role;
revoke all on function app.transition_m3_crm_task(
  uuid, text, uuid, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;

revoke all on function app.m3_list_leads(uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_get_lead(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_create_lead(
  uuid, text, text, text, uuid, uuid, uuid, timestamptz, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_update_lead(
  uuid, text, uuid, bigint, boolean, text, boolean, uuid,
  boolean, uuid, boolean, timestamptz, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_transition_lead(
  uuid, text, uuid, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_convert_lead(
  uuid, text, uuid, bigint, text, text, uuid, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_create_activity(
  uuid, text, text, text, text, text, text, timestamptz,
  uuid, uuid, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_list_crm_timeline(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_create_task(
  uuid, text, uuid, uuid, uuid, uuid, text, text, text,
  timestamptz, timestamptz, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_complete_task(uuid, text, uuid, bigint, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_cancel_task(
  uuid, text, uuid, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_list_tasks(uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_create_appointment(
  uuid, text, uuid, uuid, text, timestamptz, timestamptz,
  text, uuid, text, text, uuid[], text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_transition_appointment(
  uuid, text, uuid, bigint, text, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_list_appointments(uuid)
  from public, anon, authenticated, service_role;

grant execute on function app.m3_list_leads(uuid) to authenticated;
grant execute on function app.m3_get_lead(uuid, uuid) to authenticated;
grant execute on function app.m3_create_lead(
  uuid, text, text, text, uuid, uuid, uuid, timestamptz, text, uuid
) to authenticated;
grant execute on function app.m3_update_lead(
  uuid, text, uuid, bigint, boolean, text, boolean, uuid,
  boolean, uuid, boolean, timestamptz, text, uuid
) to authenticated;
grant execute on function app.m3_transition_lead(
  uuid, text, uuid, bigint, text, text, text, uuid
) to authenticated;
grant execute on function app.m3_convert_lead(
  uuid, text, uuid, bigint, text, text, uuid, uuid, uuid, text, uuid
) to authenticated;
grant execute on function app.m3_create_activity(
  uuid, text, text, text, text, text, text, timestamptz,
  uuid, uuid, uuid, text, text, uuid
) to authenticated;
grant execute on function app.m3_list_crm_timeline(uuid, uuid, uuid, uuid)
  to authenticated;
grant execute on function app.m3_create_task(
  uuid, text, uuid, uuid, uuid, uuid, text, text, text,
  timestamptz, timestamptz, text, uuid
) to authenticated;
grant execute on function app.m3_complete_task(uuid, text, uuid, bigint, text, uuid)
  to authenticated;
grant execute on function app.m3_cancel_task(
  uuid, text, uuid, bigint, text, text, uuid
) to authenticated;
grant execute on function app.m3_list_tasks(uuid) to authenticated;
grant execute on function app.m3_create_appointment(
  uuid, text, uuid, uuid, text, timestamptz, timestamptz,
  text, uuid, text, text, uuid[], text, uuid
) to authenticated;
grant execute on function app.m3_transition_appointment(
  uuid, text, uuid, bigint, text, text, text, text, uuid
) to authenticated;
grant execute on function app.m3_list_appointments(uuid) to authenticated;

comment on table public.leads is
  'Workspace-scoped CRM lead aggregate pinned to an immutable active workflow version.';
comment on table public.crm_activities is
  'Append-only CRM timeline activity; provider references are references only, never message credentials.';
comment on table public.crm_tasks is
  'Versioned CRM task lifecycle with immutable completed and cancelled records.';
comment on table public.crm_appointments is
  'Timezone-explicit CRM appointment with immutable terminal resolution metadata.';
comment on function app.m3_convert_lead(
  uuid, text, uuid, bigint, text, text, uuid, uuid, uuid, text, uuid
) is
  'Atomically converts one configured conversion-eligible lead into exactly one active-configured deal and primary buyer participant.';
