-- VYN-AUTH-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-JOB-001
-- Invite-only workspace access. Provider invitation tokens remain exclusively
-- GoTrue-managed: application rows, jobs, audit events, and RPC responses never
-- contain a raw provider token.

alter table public.workspace_invitations
  alter column token_hash drop not null;

comment on column public.workspace_invitations.token_hash is
  'Legacy nullable hash only. New invitations use GoTrue-managed tokens and always store NULL.';

create table public.workspace_invitation_commands (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  command_kind text not null check (command_kind in ('create', 'accept')),
  invitation_id uuid not null,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null
    check (idempotency_key = pg_catalog.btrim(idempotency_key))
    check (pg_catalog.char_length(idempotency_key) between 8 and 200),
  request_fingerprint text not null
    check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  outbox_event_id uuid,
  job_id uuid,
  correlation_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, command_kind, actor_user_id, idempotency_key),
  foreign key (workspace_id, invitation_id)
    references public.workspace_invitations (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  check (
    (command_kind = 'create' and outbox_event_id is not null and job_id is not null)
    or (command_kind = 'accept' and outbox_event_id is null and job_id is null)
  )
);

create unique index workspace_invitation_commands_create_uidx
  on public.workspace_invitation_commands (workspace_id, invitation_id)
  where command_kind = 'create';
create index workspace_invitation_commands_invitation_idx
  on public.workspace_invitation_commands (
    workspace_id,
    invitation_id,
    command_kind,
    created_at
  );

create trigger workspace_invitation_commands_immutable
before update or delete on public.workspace_invitation_commands
for each row execute function app.prevent_job_history_mutation();

create function app.invitation_command_fingerprint(p_request jsonb)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(p_request::text, 'sha256'),
    'hex'
  );
$$;

create function app.create_workspace_invitation_job(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_email text,
  p_role_ids uuid[],
  p_requested_locale text,
  p_expires_at timestamptz,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  invitation_id uuid,
  invitation_status text,
  outbox_event_id uuid,
  job_id uuid,
  job_status text,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  normalized_email text;
  normalized_locale text;
  normalized_role_ids uuid[];
  role_count bigint;
  request_fingerprint text;
  existing_fingerprint text;
  existing_invitation_id uuid;
  existing_outbox_event_id uuid;
  existing_job_id uuid;
  existing_job_status text;
  new_invitation_id uuid;
  queued_outbox_event_id uuid;
  queued_job_id uuid;
  queued_job_status text;
begin
  actor_user_id := auth.uid();
  if actor_user_id is null
    or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using
      errcode = '42501',
      message = 'authenticated identity is required';
  end if;
  if not app.has_permission(p_workspace_id, 'users.manage') then
    raise exception using
      errcode = '42501',
      message = 'active users.manage permission is required';
  end if;
  if not app.has_recent_strong_auth() then
    raise exception using
      errcode = '42501',
      message = 'recent AAL2 authentication is required';
  end if;

  normalized_idempotency_key := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
  normalized_email := pg_catalog.lower(pg_catalog.btrim(coalesce(p_email, '')));
  normalized_locale := pg_catalog.btrim(coalesce(p_requested_locale, ''));

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using
      errcode = '22023',
      message = 'invalid invitation idempotency key';
  end if;
  if pg_catalog.char_length(normalized_email) not between 3 and 320
    or normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception using errcode = '22023', message = 'invalid invitation email';
  end if;
  if pg_catalog.char_length(normalized_locale) not between 2 and 64
    or normalized_locale !~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$' then
    raise exception using errcode = '22023', message = 'invalid invitation locale';
  end if;
  if p_expires_at is null
    or p_expires_at <= pg_catalog.statement_timestamp()
    or p_expires_at > pg_catalog.statement_timestamp() + interval '30 days' then
    raise exception using
      errcode = '22023',
      message = 'invitation expiry must be in the next 30 days';
  end if;
  if pg_catalog.btrim(coalesce(p_request_id, '')) = ''
    or pg_catalog.char_length(p_request_id) > 128
    or p_correlation_id is null then
    raise exception using
      errcode = '22023',
      message = 'request and correlation identifiers are required';
  end if;
  if p_role_ids is null
    or coalesce(pg_catalog.array_ndims(p_role_ids), 0) <> 1
    or pg_catalog.cardinality(p_role_ids) not between 1 and 32
    or pg_catalog.array_position(p_role_ids, null::uuid) is not null then
    raise exception using
      errcode = '22023',
      message = 'one to 32 explicit invitation roles are required';
  end if;

  select pg_catalog.array_agg(candidate.role_id order by candidate.role_id)
    into normalized_role_ids
  from (
    select distinct role_id
    from pg_catalog.unnest(p_role_ids) as supplied(role_id)
  ) candidate;

  if pg_catalog.cardinality(normalized_role_ids)
    <> pg_catalog.cardinality(p_role_ids) then
    raise exception using
      errcode = '22023',
      message = 'invitation roles must be unique';
  end if;

  -- Lock the active role set so it cannot become inactive while the command is
  -- validating and copying the immutable invitation-role snapshot.
  perform role.id
  from public.roles role
  where role.workspace_id = p_workspace_id
    and role.id = any(normalized_role_ids)
    and role.status = 'active'
  order by role.id
  for share of role;

  select pg_catalog.count(*)
    into role_count
  from public.roles role
  where role.workspace_id = p_workspace_id
    and role.id = any(normalized_role_ids)
    and role.status = 'active';

  if role_count <> pg_catalog.cardinality(normalized_role_ids) then
    raise exception using
      errcode = '23514',
      message = 'all invitation roles must be active in the selected workspace';
  end if;

  request_fingerprint := app.invitation_command_fingerprint(
    pg_catalog.jsonb_build_object(
      'email', normalized_email,
      'role_ids', pg_catalog.to_jsonb(normalized_role_ids),
      'requested_locale', normalized_locale,
      'expires_at', p_expires_at
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fcreate_invitation\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select
    command.request_fingerprint,
    command.invitation_id,
    command.outbox_event_id,
    command.job_id,
    job.status
    into
      existing_fingerprint,
      existing_invitation_id,
      existing_outbox_event_id,
      existing_job_id,
      existing_job_status
  from public.workspace_invitation_commands command
  join public.jobs job
    on job.workspace_id = command.workspace_id
   and job.id = command.job_id
  where command.workspace_id = p_workspace_id
    and command.command_kind = 'create'
    and command.actor_user_id = app.current_user_id()
    and command.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'invitation idempotency key was used for a different request';
    end if;
    return query
    select
      existing_invitation_id,
      'pending'::text,
      existing_outbox_event_id,
      existing_job_id,
      existing_job_status,
      true;
    return;
  end if;

  if exists (
    select 1
    from auth.users identity
    join public.workspace_memberships membership
      on membership.user_id = identity.id
     and membership.workspace_id = p_workspace_id
    where pg_catalog.lower(pg_catalog.btrim(identity.email)) = normalized_email
  ) then
    raise exception using
      errcode = '23505',
      message = 'the invited identity already has workspace membership history';
  end if;

  new_invitation_id := pg_catalog.gen_random_uuid();
  insert into public.workspace_invitations (
    id,
    workspace_id,
    email,
    token_hash,
    status,
    requested_locale,
    invited_by,
    expires_at
  ) values (
    new_invitation_id,
    p_workspace_id,
    normalized_email,
    null,
    'pending',
    normalized_locale,
    actor_user_id,
    p_expires_at
  );

  insert into public.workspace_invitation_roles (
    workspace_id,
    invitation_id,
    role_id
  )
  select p_workspace_id, new_invitation_id, supplied.role_id
  from pg_catalog.unnest(normalized_role_ids) as supplied(role_id);

  select
    queued.outbox_event_id,
    queued.job_id,
    queued.job_status
    into
      queued_outbox_event_id,
      queued_job_id,
      queued_job_status
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'auth.invitation.delivery_requested',
    p_aggregate_type => 'workspace_invitation',
    p_aggregate_id => new_invitation_id,
    p_aggregate_version => 1,
    p_job_type => 'auth.invitation.deliver',
    p_entity_type => 'workspace_invitation',
    p_entity_id => new_invitation_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'invitation_id', new_invitation_id
    ),
    p_idempotency_key => 'invitation-delivery:' || new_invitation_id::text,
    p_correlation_id => p_correlation_id,
    p_actor_user_id => actor_user_id,
    p_request_id => p_request_id
  ) queued;

  insert into public.workspace_invitation_commands (
    workspace_id,
    command_kind,
    invitation_id,
    actor_user_id,
    idempotency_key,
    request_fingerprint,
    outbox_event_id,
    job_id,
    correlation_id
  ) values (
    p_workspace_id,
    'create',
    new_invitation_id,
    actor_user_id,
    normalized_idempotency_key,
    request_fingerprint,
    queued_outbox_event_id,
    queued_job_id,
    p_correlation_id
  );

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'auth.invitation.created',
    p_entity_type => 'workspace_invitation',
    p_entity_id => new_invitation_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'pending',
      'requested_locale', normalized_locale,
      'expires_at', p_expires_at,
      'role_count', role_count,
      'delivery_job_id', queued_job_id
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2',
    p_metadata => pg_catalog.jsonb_build_object(
      'source', 'create_workspace_invitation_job'
    )
  );

  return query
  select
    new_invitation_id,
    'pending'::text,
    queued_outbox_event_id,
    queued_job_id,
    queued_job_status,
    false;
end;
$$;

create function app.accept_workspace_invitation(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_invitation_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  invitation_id uuid,
  membership_id uuid,
  invitation_status text,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  identity_email text;
  jwt_email text;
  identity_email_confirmed_at timestamptz;
  normalized_idempotency_key text;
  request_fingerprint text;
  existing_fingerprint text;
  existing_command_invitation_id uuid;
  target_invitation public.workspace_invitations%rowtype;
  existing_profile_status text;
  accepted_role_ids uuid[];
  invitation_role_count bigint;
  active_role_count bigint;
  new_membership_id uuid;
begin
  actor_user_id := auth.uid();
  if actor_user_id is null
    or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using
      errcode = '42501',
      message = 'authenticated identity is required';
  end if;

  select
    pg_catalog.lower(pg_catalog.btrim(identity.email)),
    identity.email_confirmed_at
    into identity_email, identity_email_confirmed_at
  from auth.users identity
  where identity.id = actor_user_id;

  jwt_email := pg_catalog.lower(
    pg_catalog.btrim(coalesce(auth.jwt() ->> 'email', ''))
  );
  if identity_email is null
    or identity_email_confirmed_at is null
    or jwt_email = ''
    or jwt_email <> identity_email then
    raise exception using
      errcode = '42501',
      message = 'a confirmed matching authenticated email is required';
  end if;

  normalized_idempotency_key := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using
      errcode = '22023',
      message = 'invalid invitation acceptance idempotency key';
  end if;
  if p_workspace_id is null or p_invitation_id is null then
    raise exception using
      errcode = '23502',
      message = 'workspace and invitation identifiers are required';
  end if;
  if pg_catalog.btrim(coalesce(p_request_id, '')) = ''
    or pg_catalog.char_length(p_request_id) > 128
    or p_correlation_id is null then
    raise exception using
      errcode = '22023',
      message = 'request and correlation identifiers are required';
  end if;
  if not exists (
    select 1
    from public.workspaces workspace
    join public.organizations organization
      on organization.id = workspace.organization_id
    where workspace.id = p_workspace_id
      and workspace.status = 'active'
      and organization.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'invitation workspace must be active';
  end if;

  request_fingerprint := app.invitation_command_fingerprint(
    pg_catalog.jsonb_build_object('invitation_id', p_invitation_id)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1faccept_invitation\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select command.request_fingerprint, command.invitation_id
    into existing_fingerprint, existing_command_invitation_id
  from public.workspace_invitation_commands command
  where command.workspace_id = p_workspace_id
    and command.command_kind = 'accept'
    and command.actor_user_id = app.current_user_id()
    and command.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_fingerprint <> request_fingerprint
      or existing_command_invitation_id <> p_invitation_id then
      raise exception using
        errcode = '23505',
        message = 'acceptance idempotency key was used for a different request';
    end if;

    select invitation.*
      into target_invitation
    from public.workspace_invitations invitation
    where invitation.workspace_id = p_workspace_id
      and invitation.id = p_invitation_id;

    if not found
      or target_invitation.status <> 'accepted'
      or target_invitation.accepted_by <> actor_user_id
      or target_invitation.accepted_membership_id is null then
      raise exception using
        errcode = '55000',
        message = 'accepted invitation command state is inconsistent';
    end if;

    return query
    select
      target_invitation.id,
      target_invitation.accepted_membership_id,
      'accepted'::text,
      true;
    return;
  end if;

  select invitation.*
    into target_invitation
  from public.workspace_invitations invitation
  where invitation.workspace_id = p_workspace_id
    and invitation.id = p_invitation_id
  for update;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'pending invitation was not found in the selected workspace';
  end if;

  if target_invitation.status = 'accepted'
    and target_invitation.accepted_by = actor_user_id
    and target_invitation.accepted_membership_id is not null then
    insert into public.workspace_invitation_commands (
      workspace_id,
      command_kind,
      invitation_id,
      actor_user_id,
      idempotency_key,
      request_fingerprint,
      correlation_id
    ) values (
      p_workspace_id,
      'accept',
      p_invitation_id,
      actor_user_id,
      normalized_idempotency_key,
      request_fingerprint,
      p_correlation_id
    );

    return query
    select
      target_invitation.id,
      target_invitation.accepted_membership_id,
      'accepted'::text,
      true;
    return;
  end if;

  if target_invitation.status <> 'pending' then
    raise exception using
      errcode = '23514',
      message = 'only a pending invitation can be accepted';
  end if;
  if target_invitation.expires_at <= pg_catalog.statement_timestamp() then
    raise exception using
      errcode = '23514',
      message = 'expired invitations cannot be accepted';
  end if;
  if pg_catalog.lower(target_invitation.email::text) <> identity_email then
    raise exception using
      errcode = '42501',
      message = 'authenticated email does not match the invitation';
  end if;

  select pg_catalog.array_agg(link.role_id order by link.role_id), pg_catalog.count(*)
    into accepted_role_ids, invitation_role_count
  from public.workspace_invitation_roles link
  where link.workspace_id = p_workspace_id
    and link.invitation_id = p_invitation_id;

  if invitation_role_count = 0 then
    raise exception using
      errcode = '23514',
      message = 'invitation must preserve at least one role';
  end if;

  perform role.id
  from public.roles role
  where role.workspace_id = p_workspace_id
    and role.id = any(accepted_role_ids)
    and role.status = 'active'
  order by role.id
  for share of role;

  select pg_catalog.count(*)
    into active_role_count
  from public.roles role
  where role.workspace_id = p_workspace_id
    and role.id = any(accepted_role_ids)
    and role.status = 'active';

  if active_role_count <> invitation_role_count then
    raise exception using
      errcode = '23514',
      message = 'all invitation roles must remain active at acceptance';
  end if;

  select profile.status
    into existing_profile_status
  from public.user_profiles profile
  where profile.user_id = actor_user_id
  for update;

  if not found then
    insert into public.user_profiles (
      user_id,
      preferred_locale,
      status
    ) values (
      actor_user_id,
      target_invitation.requested_locale,
      'active'
    ) on conflict (user_id) do nothing;

    select profile.status
      into existing_profile_status
    from public.user_profiles profile
    where profile.user_id = actor_user_id
    for update;
  end if;

  if existing_profile_status is distinct from 'active' then
    raise exception using
      errcode = '42501',
      message = 'inactive user profiles cannot accept invitations';
  end if;

  if exists (
    select 1
    from public.workspace_memberships membership
    where membership.workspace_id = p_workspace_id
      and membership.user_id = actor_user_id
  ) then
    raise exception using
      errcode = '23505',
      message = 'authenticated identity already has workspace membership history';
  end if;

  new_membership_id := pg_catalog.gen_random_uuid();
  insert into public.workspace_memberships (
    id,
    workspace_id,
    user_id,
    status,
    invited_at,
    activated_at,
    invited_by
  ) values (
    new_membership_id,
    p_workspace_id,
    actor_user_id,
    'active',
    target_invitation.created_at,
    pg_catalog.statement_timestamp(),
    target_invitation.invited_by
  );

  insert into public.membership_roles (
    workspace_id,
    membership_id,
    role_id,
    status,
    assigned_by
  )
  select
    p_workspace_id,
    new_membership_id,
    supplied.role_id,
    'active',
    target_invitation.invited_by
  from pg_catalog.unnest(accepted_role_ids) as supplied(role_id);

  update public.workspace_invitations invitation
  set status = 'accepted',
      accepted_by = actor_user_id,
      accepted_membership_id = new_membership_id,
      accepted_at = pg_catalog.statement_timestamp()
  where invitation.workspace_id = p_workspace_id
    and invitation.id = p_invitation_id;

  insert into public.workspace_invitation_commands (
    workspace_id,
    command_kind,
    invitation_id,
    actor_user_id,
    idempotency_key,
    request_fingerprint,
    correlation_id
  ) values (
    p_workspace_id,
    'accept',
    p_invitation_id,
    actor_user_id,
    normalized_idempotency_key,
    request_fingerprint,
    p_correlation_id
  );

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'auth.invitation.accepted',
    p_entity_type => 'workspace_invitation',
    p_entity_id => p_invitation_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('status', 'pending'),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'accepted',
      'membership_id', new_membership_id,
      'role_count', invitation_role_count
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'source', 'accept_workspace_invitation'
    )
  );

  return query
  select p_invitation_id, new_membership_id, 'accepted'::text, false;
end;
$$;

create function app.read_invitation_delivery_job(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid
)
returns table (
  invitation_id uuid,
  workspace_id uuid,
  email text,
  requested_locale text,
  expires_at timestamptz,
  provider_identity_exists boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_job_id is null
    or p_lease_token is null then
    raise exception using
      errcode = '22023',
      message = 'valid delivery lease identifiers are required';
  end if;

  return query
  select
    invitation.id,
    invitation.workspace_id,
    invitation.email::text,
    invitation.requested_locale,
    invitation.expires_at,
    exists (
      select 1
      from auth.users identity
      where pg_catalog.lower(pg_catalog.btrim(identity.email))
        = pg_catalog.lower(invitation.email::text)
    )
  from public.jobs job
  join public.workspace_invitations invitation
    on invitation.workspace_id = job.workspace_id
   and invitation.id = job.entity_id
  where job.id = p_job_id
    and job.status = 'running'
    and job.lease_owner = p_worker_id
    and job.lease_token = p_lease_token
    and job.lease_expires_at > pg_catalog.statement_timestamp()
    and job.job_type = 'auth.invitation.deliver'
    and job.entity_type = 'workspace_invitation'
    and job.payload_schema_version = 1
    and job.payload = pg_catalog.jsonb_build_object(
      'invitation_id', invitation.id
    )
    and invitation.status = 'pending'
    and invitation.expires_at > pg_catalog.statement_timestamp();

  if not found then
    raise exception using
      errcode = '22023',
      message = 'invitation delivery job is not eligible for this lease';
  end if;
end;
$$;

alter table public.workspace_invitation_commands enable row level security;
alter table public.workspace_invitation_commands force row level security;

revoke all on table public.workspace_invitation_commands
  from public, anon, authenticated, service_role;
grant select on public.workspace_invitation_commands to service_role;

revoke all on function app.invitation_command_fingerprint(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.create_workspace_invitation_job(
  uuid, text, text, uuid[], text, timestamptz, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.accept_workspace_invitation(
  uuid, text, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.read_invitation_delivery_job(uuid, text, uuid)
  from public, anon, authenticated, service_role;

grant execute on function app.create_workspace_invitation_job(
  uuid, text, text, uuid[], text, timestamptz, text, uuid
) to authenticated;
grant execute on function app.accept_workspace_invitation(
  uuid, text, uuid, text, uuid
) to authenticated;
grant execute on function app.read_invitation_delivery_job(uuid, text, uuid)
  to service_role;

comment on table public.workspace_invitation_commands is
  'Append-only idempotency and correlation history for invitation create/accept commands.';
comment on function app.create_workspace_invitation_job(
  uuid, text, text, uuid[], text, timestamptz, text, uuid
) is
  'Recent-AAL2 users.manage command atomically creates a pending invitation and delivery job.';
comment on function app.accept_workspace_invitation(
  uuid, text, uuid, text, uuid
) is
  'Matching confirmed identity command atomically provisions active membership and roles.';
comment on function app.read_invitation_delivery_job(uuid, text, uuid) is
  'Service-only lease-bound authoritative invitation delivery input; provider tokens are excluded.';
