-- VYN-AUTH-001, VYN-AUTH-002, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- Forward-only Milestone 1 identity, tenancy, RBAC, RLS, and audit foundation.

create extension if not exists citext with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists app;
revoke all on schema app from public;

create table public.organizations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  name text not null check (pg_catalog.btrim(name) <> ''),
  status text not null default 'active'
    check (status in ('active', 'suspended', 'closed')),
  billing_metadata jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(billing_metadata) = 'object'),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp()
);

create index organizations_normalized_name_idx
  on public.organizations (pg_catalog.lower(name));

create table public.workspaces (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  slug extensions.citext not null unique
    check (slug::text ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  name text not null check (pg_catalog.btrim(name) <> ''),
  status text not null default 'provisioning'
    check (status in ('provisioning', 'active', 'suspended', 'closed')),
  default_locale text not null default 'en-CA'
    check (default_locale ~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'),
  timezone text not null default 'UTC' check (pg_catalog.btrim(timezone) <> ''),
  default_currency char(3) not null default 'CAD'
    check (default_currency ~ '^[A-Z]{3}$'),
  odometer_unit text not null default 'km' check (odometer_unit in ('km', 'mi')),
  settings_version bigint not null default 1 check (settings_version > 0),
  mfa_required_for_all boolean not null default false,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (id, organization_id)
);

create index workspaces_organization_idx on public.workspaces (organization_id, status);

create table public.user_profiles (
  user_id uuid primary key references auth.users (id) on delete restrict,
  display_name text,
  preferred_locale text not null default 'en-CA'
    check (preferred_locale ~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'),
  status text not null default 'active'
    check (status in ('active', 'suspended', 'deactivated')),
  last_workspace_id uuid references public.workspaces (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp()
);

create table public.workspace_memberships (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  status text not null default 'invited'
    check (status in ('invited', 'active', 'suspended', 'deactivated')),
  invited_at timestamptz,
  activated_at timestamptz,
  deactivated_at timestamptz,
  invited_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, user_id),
  unique (workspace_id, id),
  constraint workspace_memberships_lifecycle_check check (
    (status = 'invited' and activated_at is null and deactivated_at is null)
    or (status in ('active', 'suspended') and activated_at is not null
      and deactivated_at is null)
    or (status = 'deactivated' and deactivated_at is not null)
  )
);

create index workspace_memberships_user_idx
  on public.workspace_memberships (user_id, status, workspace_id);

create table public.roles (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null
    check (key::text ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  name text not null check (pg_catalog.btrim(name) <> ''),
  description text,
  source text not null default 'workspace'
    check (source in ('system', 'pack', 'workspace')),
  status text not null default 'active' check (status in ('active', 'inactive')),
  requires_mfa boolean not null default false,
  created_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, key),
  unique (workspace_id, id)
);

create table public.permissions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid references public.workspaces (id) on delete restrict,
  key text not null
    check (key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'),
  description text,
  source text not null default 'platform'
    check (source in ('platform', 'workspace')),
  status text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  constraint permissions_source_scope_check check (
    (source = 'platform' and workspace_id is null)
    or (source = 'workspace' and workspace_id is not null)
  )
);

create unique index permissions_platform_key_uidx
  on public.permissions (key)
  where workspace_id is null;
create unique index permissions_workspace_key_uidx
  on public.permissions (workspace_id, key)
  where workspace_id is not null;

create table public.role_permissions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  role_id uuid not null,
  permission_id uuid not null references public.permissions (id) on delete restrict,
  status text not null default 'active' check (status in ('active', 'revoked')),
  granted_by uuid references auth.users (id) on delete restrict,
  granted_at timestamptz not null default pg_catalog.statement_timestamp(),
  revoked_by uuid references auth.users (id) on delete restrict,
  revoked_at timestamptz,
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, role_id, permission_id),
  unique (workspace_id, id),
  foreign key (workspace_id, role_id)
    references public.roles (workspace_id, id) on delete restrict,
  check (
    (status = 'active' and revoked_at is null and revoked_by is null)
    or (status = 'revoked' and revoked_at is not null)
  )
);

create index role_permissions_permission_idx
  on public.role_permissions (permission_id, status);

create table public.membership_roles (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  membership_id uuid not null,
  role_id uuid not null,
  status text not null default 'active' check (status in ('active', 'revoked')),
  assigned_by uuid references auth.users (id) on delete restrict,
  assigned_at timestamptz not null default pg_catalog.statement_timestamp(),
  revoked_by uuid references auth.users (id) on delete restrict,
  revoked_at timestamptz,
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, membership_id, role_id),
  unique (workspace_id, id),
  foreign key (workspace_id, membership_id)
    references public.workspace_memberships (workspace_id, id) on delete restrict,
  foreign key (workspace_id, role_id)
    references public.roles (workspace_id, id) on delete restrict,
  check (
    (status = 'active' and revoked_at is null and revoked_by is null)
    or (status = 'revoked' and revoked_at is not null)
  )
);

create index membership_roles_role_idx on public.membership_roles (workspace_id, role_id, status);

create table public.workspace_invitations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  email extensions.citext not null check (pg_catalog.btrim(email::text) <> ''),
  token_hash text not null unique check (pg_catalog.btrim(token_hash) <> ''),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  requested_locale text not null default 'en-CA'
    check (requested_locale ~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'),
  invited_by uuid not null references auth.users (id) on delete restrict,
  expires_at timestamptz not null,
  accepted_by uuid references auth.users (id) on delete restrict,
  accepted_membership_id uuid,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, accepted_membership_id)
    references public.workspace_memberships (workspace_id, id) on delete restrict,
  check (expires_at > created_at),
  check (
    (status = 'accepted' and accepted_at is not null and accepted_by is not null
      and accepted_membership_id is not null and revoked_at is null)
    or (status = 'revoked' and revoked_at is not null and accepted_at is null
      and accepted_by is null and accepted_membership_id is null)
    or (status in ('pending', 'expired') and accepted_at is null
      and accepted_by is null and accepted_membership_id is null and revoked_at is null)
  )
);

create unique index workspace_invitations_pending_email_uidx
  on public.workspace_invitations (workspace_id, email)
  where status = 'pending';
create index workspace_invitations_expiry_idx
  on public.workspace_invitations (status, expires_at);

create table public.workspace_invitation_roles (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  invitation_id uuid not null,
  role_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, invitation_id, role_id),
  foreign key (workspace_id, invitation_id)
    references public.workspace_invitations (workspace_id, id) on delete restrict,
  foreign key (workspace_id, role_id)
    references public.roles (workspace_id, id) on delete restrict
);

create table public.audit_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  actor_user_id uuid references auth.users (id) on delete restrict,
  actor_type text not null
    check (actor_type in ('user', 'service', 'worker', 'support', 'system')),
  action text not null check (pg_catalog.btrim(action) <> ''),
  entity_type text not null check (pg_catalog.btrim(entity_type) <> ''),
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  diff jsonb,
  reason text,
  request_id text,
  correlation_id uuid,
  ip_address inet,
  user_agent text,
  auth_assurance text,
  metadata jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(metadata) = 'object'),
  occurred_at timestamptz not null default pg_catalog.statement_timestamp(),
  check (actor_type <> 'user' or actor_user_id is not null),
  check (before_data is null or pg_catalog.jsonb_typeof(before_data) = 'object'),
  check (after_data is null or pg_catalog.jsonb_typeof(after_data) = 'object'),
  check (diff is null or pg_catalog.jsonb_typeof(diff) = 'object')
);

create index audit_events_workspace_time_idx
  on public.audit_events (workspace_id, occurred_at desc);
create index audit_events_workspace_entity_idx
  on public.audit_events (workspace_id, entity_type, entity_id, occurred_at desc);
create index audit_events_workspace_actor_idx
  on public.audit_events (workspace_id, actor_user_id, occurred_at desc);

-- Stable platform permission contracts from docs/data/PERMISSION_CATALOG.md.
insert into public.permissions (key, source)
values
  ('workspace.read', 'platform'),
  ('workspace.manage', 'platform'),
  ('users.read', 'platform'),
  ('users.manage', 'platform'),
  ('roles.manage', 'platform'),
  ('configuration.read', 'platform'),
  ('configuration.manage', 'platform'),
  ('approvals.read', 'platform'),
  ('approvals.create', 'platform'),
  ('integrations.read', 'platform'),
  ('integrations.manage', 'platform'),
  ('jobs.read', 'platform'),
  ('jobs.manage', 'platform'),
  ('audit.read', 'platform'),
  ('inventory.read', 'platform'),
  ('inventory.create', 'platform'),
  ('inventory.update', 'platform'),
  ('inventory.transition', 'platform'),
  ('inventory.archive', 'platform'),
  ('costs.read', 'platform'),
  ('costs.create', 'platform'),
  ('costs.reverse', 'platform'),
  ('media.read', 'platform'),
  ('media.create', 'platform'),
  ('media.update', 'platform'),
  ('media.archive', 'platform'),
  ('listings.read', 'platform'),
  ('listings.publish', 'platform'),
  ('listings.unpublish', 'platform'),
  ('listings.reconcile', 'platform'),
  ('crm.read', 'platform'),
  ('crm.create', 'platform'),
  ('crm.update', 'platform'),
  ('crm.assign', 'platform'),
  ('deals.read', 'platform'),
  ('deals.create', 'platform'),
  ('deals.update', 'platform'),
  ('deals.transition', 'platform'),
  ('deals.cancel', 'platform'),
  ('deals.close', 'platform'),
  ('finance_applications.read', 'platform'),
  ('finance_applications.create', 'platform'),
  ('finance_applications.update', 'platform'),
  ('payments.read', 'platform'),
  ('payments.record', 'platform'),
  ('payments.settle', 'platform'),
  ('payments.reverse', 'platform'),
  ('payments.refund', 'platform'),
  ('documents.read', 'platform'),
  ('documents.preview', 'platform'),
  ('documents.generate_approved', 'platform'),
  ('documents.print', 'platform'),
  ('documents.upload_signed', 'platform'),
  ('documents.mark_signed', 'platform'),
  ('documents.void', 'platform'),
  ('documents.void_signed', 'platform'),
  ('documents.supersede', 'platform'),
  ('formula.read', 'platform'),
  ('formula.activate', 'platform'),
  ('tax.read', 'platform'),
  ('tax.activate', 'platform'),
  ('template.read', 'platform'),
  ('template.activate', 'platform'),
  ('workflow.read', 'platform'),
  ('workflow.activate', 'platform'),
  ('numbering.read', 'platform'),
  ('numbering.activate', 'platform'),
  ('reports.read', 'platform'),
  ('exports.read', 'platform'),
  ('exports.run', 'platform'),
  ('exports.run_sensitive', 'platform'),
  ('identifiers.read_restricted', 'platform'),
  ('identifiers.manage', 'platform'),
  ('files.read_restricted', 'platform'),
  ('support.access', 'platform');

create function app.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.statement_timestamp();
  return new;
end;
$$;

create function app.enforce_immutable_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  column_name text;
begin
  foreach column_name in array tg_argv loop
    if (pg_catalog.to_jsonb(new) -> column_name)
      is distinct from (pg_catalog.to_jsonb(old) -> column_name) then
      raise exception using
        errcode = '23514',
        message = pg_catalog.format('%I.%I is immutable', tg_table_name, column_name);
    end if;
  end loop;
  return new;
end;
$$;

create function app.prevent_hard_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = pg_catalog.format('hard delete is prohibited for %I', tg_table_name);
end;
$$;

create function app.validate_user_last_workspace()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.last_workspace_id is not null and not exists (
    select 1
    from public.workspace_memberships wm
    where wm.workspace_id = new.last_workspace_id
      and wm.user_id = new.user_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'last_workspace_id must reference a workspace membership for the profile user';
  end if;
  return new;
end;
$$;

create function app.validate_invitation_acceptance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  membership_user_id uuid;
  membership_status text;
  accepted_user_email text;
begin
  if tg_op = 'INSERT' and new.status <> 'pending' then
    raise exception using
      errcode = '23514',
      message = 'invitations must be created in pending status';
  end if;

  if tg_op = 'UPDATE' then
    if old.status <> 'pending' then
      raise exception using
        errcode = '23514',
        message = 'terminal invitation records are immutable';
    end if;

    if new.status = 'accepted' and old.status <> 'pending' then
      raise exception using
        errcode = '23514',
        message = 'only pending invitations can be accepted';
    end if;

    if new.status = 'accepted' and old.expires_at <= pg_catalog.statement_timestamp() then
      raise exception using
        errcode = '23514',
        message = 'expired invitations cannot be accepted';
    end if;

    if new.status = 'expired' and old.expires_at > pg_catalog.statement_timestamp() then
      raise exception using
        errcode = '23514',
        message = 'unexpired invitations cannot be marked expired';
    end if;
  end if;

  if new.status = 'accepted' then
    select wm.user_id, wm.status
      into membership_user_id, membership_status
    from public.workspace_memberships wm
    where wm.workspace_id = new.workspace_id
      and wm.id = new.accepted_membership_id;

    select u.email
      into accepted_user_email
    from auth.users u
    where u.id = new.accepted_by;

    if membership_user_id is null
      or membership_user_id is distinct from new.accepted_by
      or membership_status <> 'active' then
      raise exception using
        errcode = '23514',
        message = 'accepted membership must be active and match the accepted user in the invitation workspace';
    end if;

    if accepted_user_email is null
      or pg_catalog.lower(accepted_user_email) <> pg_catalog.lower(new.email::text) then
      raise exception using
        errcode = '23514',
        message = 'accepted user email must match the invitation email';
    end if;
  end if;
  return new;
end;
$$;

create function app.validate_membership_activation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if old.activated_at is not null
      and new.activated_at is distinct from old.activated_at then
      raise exception using
        errcode = '23514',
        message = 'membership activation time is immutable once recorded';
    end if;

    if old.deactivated_at is not null
      and new.deactivated_at is distinct from old.deactivated_at then
      raise exception using
        errcode = '23514',
        message = 'membership deactivation time is immutable once recorded';
    end if;

    if old.status <> 'invited' and new.status = 'invited' then
      raise exception using
        errcode = '23514',
        message = 'membership status cannot transition back to invited';
    end if;
  end if;

  if current_user in ('anon', 'authenticated') and new.status = 'active' then
    if tg_op = 'INSERT' then
      raise exception using
        errcode = '42501',
        message = 'membership activation requires a trusted application command';
    elsif tg_op = 'UPDATE' and old.status <> 'active' then
      raise exception using
        errcode = '42501',
        message = 'membership activation requires a trusted application command';
    end if;
  end if;
  return new;
end;
$$;

create function app.assert_role_permission_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  permission_workspace_id uuid;
  permission_key text;
  permission_status text;
  role_requires_mfa boolean;
begin
  select p.workspace_id, p.key, p.status
    into permission_workspace_id, permission_key, permission_status
  from public.permissions p
  where p.id = new.permission_id
  for share;

  if not found then
    raise exception using errcode = '23503', message = 'permission does not exist';
  end if;

  if permission_workspace_id is not null
    and permission_workspace_id is distinct from new.workspace_id then
    raise exception using
      errcode = '23514',
      message = 'workspace-scoped permission cannot be granted across workspaces';
  end if;

  select r.requires_mfa
    into role_requires_mfa
  from public.roles r
  where r.workspace_id = new.workspace_id
    and r.id = new.role_id
  for update;

  if new.status = 'active'
    and permission_status = 'active'
    and permission_key in (
    'workspace.manage',
    'users.manage',
    'roles.manage',
    'integrations.manage',
    'support.access'
  ) and role_requires_mfa is not true then
    raise exception using
      errcode = '23514',
      message = 'roles with administrative permissions must require MFA';
  end if;

  return new;
end;
$$;

create function app.derive_browser_identity_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor_user_id uuid;
begin
  if tg_op = 'UPDATE'
    and tg_table_name in ('role_permissions', 'membership_roles') then
    if old.status = 'revoked' and new.status is distinct from old.status then
      raise exception using
        errcode = '23514',
        message = 'revoked role grants cannot be reactivated';
    end if;
  end if;

  if current_user <> 'authenticated' then
    return new;
  end if;

  actor_user_id := auth.uid();
  if actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated identity is required for actor-derived fields';
  end if;

  if tg_table_name = 'workspace_memberships' then
    if tg_op = 'INSERT' then
      new.invited_by := actor_user_id;
      new.invited_at := pg_catalog.statement_timestamp();
    elsif new.status = 'deactivated' and old.status <> 'deactivated' then
      new.deactivated_at := pg_catalog.statement_timestamp();
    end if;
  elsif tg_table_name = 'roles' and tg_op = 'INSERT' then
    new.created_by := actor_user_id;
  elsif tg_table_name = 'role_permissions' then
    if tg_op = 'INSERT' then
      new.granted_by := actor_user_id;
    elsif new.status = 'revoked' and old.status <> 'revoked' then
      new.revoked_by := actor_user_id;
      new.revoked_at := pg_catalog.statement_timestamp();
    end if;
  elsif tg_table_name = 'membership_roles' then
    if tg_op = 'INSERT' then
      new.assigned_by := actor_user_id;
    elsif new.status = 'revoked' and old.status <> 'revoked' then
      new.revoked_by := actor_user_id;
      new.revoked_at := pg_catalog.statement_timestamp();
    end if;
  end if;

  return new;
end;
$$;

create function app.bump_workspace_settings_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if row(
    new.name,
    new.status,
    new.default_locale,
    new.timezone,
    new.default_currency,
    new.odometer_unit,
    new.mfa_required_for_all
  ) is distinct from row(
    old.name,
    old.status,
    old.default_locale,
    old.timezone,
    old.default_currency,
    old.odometer_unit,
    old.mfa_required_for_all
  ) then
    new.settings_version := old.settings_version + 1;
  else
    new.settings_version := old.settings_version;
  end if;

  return new;
end;
$$;

create function app.assert_permission_mfa_requirement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active'
    and old.status is distinct from new.status
    and new.key in (
      'workspace.manage',
      'users.manage',
      'roles.manage',
      'integrations.manage',
      'support.access'
    ) then
    perform 1
    from public.roles r
    join public.role_permissions rp
      on rp.workspace_id = r.workspace_id
     and rp.role_id = r.id
    where rp.permission_id = new.id
      and rp.status = 'active'
    order by r.id
    for update of r;

    if exists (
      select 1
      from public.roles r
      join public.role_permissions rp
        on rp.workspace_id = r.workspace_id
       and rp.role_id = r.id
      where rp.permission_id = new.id
        and rp.status = 'active'
        and not r.requires_mfa
    ) then
      raise exception using
        errcode = '23514',
        message = 'administrative permissions cannot activate for a role without MFA';
    end if;
  end if;

  return new;
end;
$$;

create function app.assert_role_mfa_requirement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.requires_mfa and not new.requires_mfa and exists (
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id = rp.permission_id
    where rp.workspace_id = new.workspace_id
      and rp.role_id = new.id
      and rp.status = 'active'
      and p.status = 'active'
      and p.key in (
        'workspace.manage',
        'users.manage',
        'roles.manage',
        'integrations.manage',
        'support.access'
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'MFA cannot be disabled while a role has administrative permissions';
  end if;
  return new;
end;
$$;

create function app.guard_platform_permission_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.workspace_id is null
    and current_user not in ('postgres', 'supabase_admin') then
    raise exception using
      errcode = '42501',
      message = 'platform permissions are migration-owned';
  end if;
  return new;
end;
$$;

create function app.guard_workspace_permission_key()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.workspace_id is not null and exists (
    select 1
    from public.permissions platform_permission
    where platform_permission.workspace_id is null
      and platform_permission.key = new.key
      and platform_permission.id is distinct from new.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'workspace permission keys cannot shadow platform keys';
  end if;

  return new;
end;
$$;

create trigger organizations_updated_at
before update on public.organizations
for each row execute function app.set_updated_at();
create trigger workspaces_updated_at
before update on public.workspaces
for each row execute function app.set_updated_at();
create trigger workspaces_settings_version
before update on public.workspaces
for each row execute function app.bump_workspace_settings_version();
create trigger user_profiles_updated_at
before update on public.user_profiles
for each row execute function app.set_updated_at();
create trigger workspace_memberships_updated_at
before update on public.workspace_memberships
for each row execute function app.set_updated_at();
create trigger workspace_memberships_activation_guard
before insert or update on public.workspace_memberships
for each row execute function app.validate_membership_activation();
create trigger workspace_memberships_actor_fields
before insert or update on public.workspace_memberships
for each row execute function app.derive_browser_identity_fields();
create trigger roles_updated_at
before update on public.roles
for each row execute function app.set_updated_at();
create trigger roles_actor_fields
before insert on public.roles
for each row execute function app.derive_browser_identity_fields();
create trigger permissions_updated_at
before update on public.permissions
for each row execute function app.set_updated_at();
create trigger role_permissions_updated_at
before update on public.role_permissions
for each row execute function app.set_updated_at();
create trigger role_permissions_actor_fields
before insert or update on public.role_permissions
for each row execute function app.derive_browser_identity_fields();
create trigger membership_roles_updated_at
before update on public.membership_roles
for each row execute function app.set_updated_at();
create trigger membership_roles_actor_fields
before insert or update on public.membership_roles
for each row execute function app.derive_browser_identity_fields();
create trigger workspace_invitations_updated_at
before update on public.workspace_invitations
for each row execute function app.set_updated_at();

create trigger organizations_immutable
before update on public.organizations
for each row execute function app.enforce_immutable_columns('id', 'created_at');
create trigger workspaces_immutable
before update on public.workspaces
for each row execute function app.enforce_immutable_columns('id', 'organization_id', 'slug', 'created_at');
create trigger user_profiles_immutable
before update on public.user_profiles
for each row execute function app.enforce_immutable_columns('user_id', 'created_at');
create trigger workspace_memberships_immutable
before update on public.workspace_memberships
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'user_id', 'invited_at', 'invited_by', 'created_at'
);
create trigger roles_immutable
before update on public.roles
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'key', 'source', 'created_by', 'created_at'
);
create trigger permissions_immutable
before update on public.permissions
for each row execute function app.enforce_immutable_columns('id', 'workspace_id', 'key', 'source', 'created_at');
create trigger role_permissions_immutable
before update on public.role_permissions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'role_id', 'permission_id', 'granted_by', 'granted_at'
);
create trigger membership_roles_immutable
before update on public.membership_roles
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'membership_id', 'role_id', 'assigned_by', 'assigned_at'
);
create trigger workspace_invitations_immutable
before update on public.workspace_invitations
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'email', 'token_hash', 'invited_by', 'expires_at', 'created_at'
);
create trigger workspace_invitation_roles_immutable
before update on public.workspace_invitation_roles
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'invitation_id', 'role_id', 'created_at'
);

create trigger user_profiles_last_workspace_guard
before insert or update of last_workspace_id on public.user_profiles
for each row execute function app.validate_user_last_workspace();
create trigger workspace_invitations_acceptance_guard
before insert or update on public.workspace_invitations
for each row execute function app.validate_invitation_acceptance();
create trigger role_permissions_scope_guard
before insert or update on public.role_permissions
for each row execute function app.assert_role_permission_scope();
create trigger roles_mfa_guard
before update of requires_mfa on public.roles
for each row execute function app.assert_role_mfa_requirement();
create trigger permissions_mfa_guard
before update of status on public.permissions
for each row execute function app.assert_permission_mfa_requirement();
create trigger permissions_platform_guard
before insert or update on public.permissions
for each row execute function app.guard_platform_permission_write();
create trigger permissions_workspace_key_guard
before insert or update on public.permissions
for each row execute function app.guard_workspace_permission_key();

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'organizations',
    'workspaces',
    'user_profiles',
    'workspace_memberships',
    'roles',
    'permissions',
    'role_permissions',
    'membership_roles',
    'workspace_invitations',
    'workspace_invitation_roles',
    'audit_events'
  ] loop
    execute pg_catalog.format(
      'create trigger %I before delete on public.%I for each row execute function app.prevent_hard_delete()',
      table_name || '_prevent_hard_delete',
      table_name
    );
  end loop;
end;
$$;

create function app.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid();
$$;

create function app.auth_assurance_at_least(level text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case level
    when 'aal1' then coalesce(auth.jwt() ->> 'aal', '') in ('aal1', 'aal2')
    when 'aal2' then coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
    else false
  end;
$$;

create function app.has_recent_strong_auth(max_age_seconds integer default 900)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select max_age_seconds between 1 and 3600
    and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
    and exists (
      select 1
      from pg_catalog.jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) factor
      where factor ->> 'method' in ('totp', 'webauthn', 'phone')
        and (factor ->> 'timestamp') ~ '^[0-9]+$'
        and (factor ->> 'timestamp')::numeric between
          pg_catalog.floor(pg_catalog.extract(epoch from pg_catalog.statement_timestamp()))
            - max_age_seconds
          and pg_catalog.floor(
            pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
          )
    );
$$;

create function app.has_active_membership(target_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspace_memberships wm
    join public.user_profiles up on up.user_id = wm.user_id
    join public.workspaces w on w.id = wm.workspace_id
    join public.organizations o on o.id = w.organization_id
    where wm.workspace_id = target_workspace_id
      and wm.user_id = auth.uid()
      and wm.status = 'active'
      and up.status = 'active'
      and w.status = 'active'
      and o.status = 'active'
      and (
        (
          not w.mfa_required_for_all
          and not exists (
            select 1
            from public.membership_roles mr
            join public.roles r
              on r.workspace_id = mr.workspace_id
             and r.id = mr.role_id
            where mr.workspace_id = wm.workspace_id
              and mr.membership_id = wm.id
              and mr.status = 'active'
              and r.status = 'active'
              and r.requires_mfa
          )
        )
        or app.auth_assurance_at_least('aal2')
      )
  );
$$;

create function app.has_permission(target_workspace_id uuid, permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.has_active_membership(target_workspace_id)
    and exists (
      select 1
      from public.workspace_memberships wm
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
        and wm.user_id = auth.uid()
        and wm.status = 'active'
        and p.key = permission_key
        and (p.workspace_id is null or p.workspace_id = target_workspace_id)
    );
$$;

create function app.has_organization_membership(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspaces w
    where w.organization_id = target_organization_id
      and app.has_active_membership(w.id)
  );
$$;

create function app.has_organization_permission(
  target_organization_id uuid,
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
    from public.workspaces w
    where w.organization_id = target_organization_id
      and app.has_permission(w.id, permission_key)
  );
$$;

create function app.can_read_user_profile(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles caller_profile
    where caller_profile.user_id = auth.uid()
      and caller_profile.status = 'active'
  ) and (
    target_user_id = auth.uid()
    or exists (
      select 1
      from public.workspace_memberships target_membership
      where target_membership.user_id = target_user_id
        and app.has_permission(target_membership.workspace_id, 'users.read')
    )
  );
$$;

create function app.can_read_permission(permission_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when permission_workspace_id is not null
      then app.has_active_membership(permission_workspace_id)
    else exists (
      select 1
      from public.workspace_memberships wm
      where wm.user_id = auth.uid()
        and app.has_active_membership(wm.workspace_id)
    )
  end;
$$;

create function app.write_audit_event(
  p_workspace_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_actor_user_id uuid default null,
  p_actor_type text default 'service',
  p_before_data jsonb default null,
  p_after_data jsonb default null,
  p_diff jsonb default null,
  p_reason text default null,
  p_request_id text default null,
  p_correlation_id uuid default null,
  p_ip_address inet default null,
  p_user_agent text default null,
  p_auth_assurance text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_id uuid;
begin
  if not exists (select 1 from public.workspaces w where w.id = p_workspace_id) then
    raise exception using errcode = '23503', message = 'audit workspace does not exist';
  end if;

  if pg_catalog.btrim(coalesce(p_action, '')) = ''
    or pg_catalog.btrim(coalesce(p_entity_type, '')) = '' then
    raise exception using errcode = '23514', message = 'audit action and entity type are required';
  end if;

  if p_actor_type = 'user' and (
    p_actor_user_id is null
    or not exists (
      select 1
      from public.workspace_memberships wm
      where wm.workspace_id = p_workspace_id
        and wm.user_id = p_actor_user_id
    )
  ) then
    raise exception using
      errcode = '23514',
      message = 'user audit actors must have membership history in the audit workspace';
  end if;

  insert into public.audit_events (
    workspace_id,
    actor_user_id,
    actor_type,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data,
    diff,
    reason,
    request_id,
    correlation_id,
    ip_address,
    user_agent,
    auth_assurance,
    metadata
  ) values (
    p_workspace_id,
    p_actor_user_id,
    p_actor_type,
    p_action,
    p_entity_type,
    p_entity_id,
    p_before_data,
    p_after_data,
    p_diff,
    p_reason,
    p_request_id,
    p_correlation_id,
    p_ip_address,
    p_user_agent,
    p_auth_assurance,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into event_id;

  return event_id;
end;
$$;

create function app.record_identity_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_before jsonb;
  row_after jsonb;
  audit_workspace_id uuid;
  audit_entity_id uuid;
  audit_actor_id uuid;
  invoker_role text;
begin
  row_before := case when tg_op = 'UPDATE' then pg_catalog.to_jsonb(old) else null end;
  row_after := pg_catalog.to_jsonb(new);

  if tg_table_name = 'workspace_invitations' then
    row_before := row_before - 'token_hash';
    row_after := row_after - 'token_hash';
  end if;

  audit_workspace_id := ((row_after ->> tg_argv[0])::uuid);
  audit_entity_id := ((row_after ->> 'id')::uuid);
  audit_actor_id := auth.uid();
  invoker_role := pg_catalog.current_setting('role', true);

  if invoker_role is null or invoker_role in ('', 'none') then
    invoker_role := session_user;
  end if;

  -- A privileged pooled connection may retain stale request GUCs. Attribute a
  -- browser mutation only when the active database role and signed JWT role are
  -- both authenticated and the subject has active user/workspace state.
  if invoker_role <> 'authenticated'
    or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated'
    or audit_actor_id is null
    or not (
      exists (
        select 1
        from public.workspace_memberships wm
        join public.user_profiles up on up.user_id = wm.user_id
        where wm.workspace_id = audit_workspace_id
          and wm.user_id = audit_actor_id
          and wm.status = 'active'
          and up.status = 'active'
      )
      or (
        tg_op = 'UPDATE'
        and tg_table_name = 'workspace_memberships'
        and row_before ->> 'user_id' = audit_actor_id::text
        and row_before ->> 'status' = 'active'
        and exists (
          select 1
          from public.user_profiles up
          where up.user_id = audit_actor_id
            and up.status = 'active'
        )
      )
    ) then
    audit_actor_id := null;
  end if;

  insert into public.audit_events (
    workspace_id,
    actor_user_id,
    actor_type,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data,
    auth_assurance,
    metadata
  ) values (
    audit_workspace_id,
    audit_actor_id,
    case when audit_actor_id is null then 'service' else 'user' end,
    'identity.' || tg_table_name || '.' || pg_catalog.lower(tg_op),
    tg_table_name,
    audit_entity_id,
    row_before,
    row_after,
    case
      when audit_actor_id is null then 'system'
      else coalesce(auth.jwt() ->> 'aal', 'unknown')
    end,
    '{"source":"database_trigger"}'::jsonb
  );

  return new;
end;
$$;

create function app.prevent_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'audit events are append-only';
end;
$$;

create function app.record_boundary_status_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  audit_workspace_id uuid;
  audit_workspace_ids uuid[];
  audit_entity_id uuid;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if tg_table_name = 'organizations' then
    audit_entity_id := new.id;
    select coalesce(pg_catalog.array_agg(w.id order by w.id), '{}'::uuid[])
      into audit_workspace_ids
    from public.workspaces w
    where w.organization_id = new.id;
  elsif tg_table_name = 'user_profiles' then
    audit_entity_id := new.user_id;
    select coalesce(
        pg_catalog.array_agg(distinct wm.workspace_id order by wm.workspace_id),
        '{}'::uuid[]
      )
      into audit_workspace_ids
    from public.workspace_memberships wm
    where wm.user_id = new.user_id;
  else
    raise exception using
      errcode = '55000',
      message = 'unsupported boundary status audit source';
  end if;

  foreach audit_workspace_id in array audit_workspace_ids loop
    insert into public.audit_events (
      workspace_id,
      actor_type,
      action,
      entity_type,
      entity_id,
      before_data,
      after_data,
      auth_assurance,
      metadata
    ) values (
      audit_workspace_id,
      'service',
      'identity.' || tg_table_name || '.status_update',
      tg_table_name,
      audit_entity_id,
      pg_catalog.jsonb_build_object('status', old.status),
      pg_catalog.jsonb_build_object('status', new.status),
      'system',
      '{"source":"database_trigger"}'::jsonb
    );
  end loop;

  return new;
end;
$$;

drop trigger audit_events_prevent_hard_delete on public.audit_events;
create trigger audit_events_immutable
before update or delete on public.audit_events
for each row execute function app.prevent_audit_mutation();

create trigger workspaces_audit
after insert or update on public.workspaces
for each row execute function app.record_identity_audit('id');
create trigger organizations_status_audit
after update of status on public.organizations
for each row execute function app.record_boundary_status_audit();
create trigger user_profiles_status_audit
after update of status on public.user_profiles
for each row execute function app.record_boundary_status_audit();
create trigger workspace_memberships_audit
after insert or update on public.workspace_memberships
for each row execute function app.record_identity_audit('workspace_id');
create trigger roles_audit
after insert or update on public.roles
for each row execute function app.record_identity_audit('workspace_id');
create trigger permissions_audit
after insert or update on public.permissions
for each row
when (new.workspace_id is not null)
execute function app.record_identity_audit('workspace_id');
create trigger role_permissions_audit
after insert or update on public.role_permissions
for each row execute function app.record_identity_audit('workspace_id');
create trigger membership_roles_audit
after insert or update on public.membership_roles
for each row execute function app.record_identity_audit('workspace_id');
create trigger workspace_invitations_audit
after insert or update on public.workspace_invitations
for each row execute function app.record_identity_audit('workspace_id');
create trigger workspace_invitation_roles_audit
after insert or update on public.workspace_invitation_roles
for each row execute function app.record_identity_audit('workspace_id');

alter table public.organizations enable row level security;
alter table public.organizations force row level security;
alter table public.workspaces enable row level security;
alter table public.workspaces force row level security;
alter table public.user_profiles enable row level security;
alter table public.user_profiles force row level security;
alter table public.workspace_memberships enable row level security;
alter table public.workspace_memberships force row level security;
alter table public.roles enable row level security;
alter table public.roles force row level security;
alter table public.permissions enable row level security;
alter table public.permissions force row level security;
alter table public.role_permissions enable row level security;
alter table public.role_permissions force row level security;
alter table public.membership_roles enable row level security;
alter table public.membership_roles force row level security;
alter table public.workspace_invitations enable row level security;
alter table public.workspace_invitations force row level security;
alter table public.workspace_invitation_roles enable row level security;
alter table public.workspace_invitation_roles force row level security;
alter table public.audit_events enable row level security;
alter table public.audit_events force row level security;

create policy organizations_select on public.organizations
for select to authenticated
using (app.has_organization_membership(id));

create policy workspaces_select on public.workspaces
for select to authenticated
using (app.has_permission(id, 'workspace.read'));
create policy workspaces_update on public.workspaces
for update to authenticated
using (app.has_permission(id, 'workspace.manage') and app.has_recent_strong_auth())
with check (app.has_permission(id, 'workspace.manage') and app.has_recent_strong_auth());

create policy user_profiles_select on public.user_profiles
for select to authenticated
using (app.can_read_user_profile(user_id));
create policy user_profiles_update on public.user_profiles
for update to authenticated
using (user_id = app.current_user_id() and status = 'active')
with check (user_id = app.current_user_id() and status = 'active');

create policy memberships_select on public.workspace_memberships
for select to authenticated
using (
  app.has_active_membership(workspace_id)
  and (user_id = app.current_user_id() or app.has_permission(workspace_id, 'users.read'))
);
create policy memberships_insert on public.workspace_memberships
for insert to authenticated
with check (
  status = 'invited'
  and activated_at is null
  and deactivated_at is null
  and app.has_permission(workspace_id, 'users.manage')
  and app.has_recent_strong_auth()
);
create policy memberships_update on public.workspace_memberships
for update to authenticated
using (app.has_permission(workspace_id, 'users.manage') and app.has_recent_strong_auth())
with check (app.has_permission(workspace_id, 'users.manage') and app.has_recent_strong_auth());

create policy roles_select on public.roles
for select to authenticated
using (app.has_active_membership(workspace_id));
create policy roles_insert on public.roles
for insert to authenticated
with check (
  source = 'workspace'
  and app.has_permission(workspace_id, 'roles.manage')
  and app.has_recent_strong_auth()
);
create policy roles_update on public.roles
for update to authenticated
using (app.has_permission(workspace_id, 'roles.manage') and app.has_recent_strong_auth())
with check (app.has_permission(workspace_id, 'roles.manage') and app.has_recent_strong_auth());

create policy permissions_select on public.permissions
for select to authenticated
using (app.can_read_permission(workspace_id));
create policy permissions_insert on public.permissions
for insert to authenticated
with check (
  workspace_id is not null
  and source = 'workspace'
  and status = 'active'
  and app.has_permission(workspace_id, 'roles.manage')
  and app.has_recent_strong_auth()
);
create policy permissions_update on public.permissions
for update to authenticated
using (
  workspace_id is not null
  and source = 'workspace'
  and app.has_permission(workspace_id, 'roles.manage')
  and app.has_recent_strong_auth()
)
with check (
  workspace_id is not null
  and source = 'workspace'
  and app.has_permission(workspace_id, 'roles.manage')
  and app.has_recent_strong_auth()
);

create policy role_permissions_select on public.role_permissions
for select to authenticated
using (app.has_active_membership(workspace_id));
create policy role_permissions_insert on public.role_permissions
for insert to authenticated
with check (
  status = 'active'
  and app.has_permission(workspace_id, 'roles.manage')
  and app.has_recent_strong_auth()
);
create policy role_permissions_update on public.role_permissions
for update to authenticated
using (app.has_permission(workspace_id, 'roles.manage') and app.has_recent_strong_auth())
with check (app.has_permission(workspace_id, 'roles.manage') and app.has_recent_strong_auth());

create policy membership_roles_select on public.membership_roles
for select to authenticated
using (
  app.has_active_membership(workspace_id)
  and (
    app.has_permission(workspace_id, 'users.read')
    or exists (
      select 1
      from public.workspace_memberships wm
      where wm.workspace_id = membership_roles.workspace_id
        and wm.id = membership_roles.membership_id
        and wm.user_id = app.current_user_id()
    )
  )
);
create policy membership_roles_insert on public.membership_roles
for insert to authenticated
with check (
  status = 'active'
  and app.has_permission(workspace_id, 'users.manage')
  and app.has_recent_strong_auth()
);
create policy membership_roles_update on public.membership_roles
for update to authenticated
using (app.has_permission(workspace_id, 'users.manage') and app.has_recent_strong_auth())
with check (app.has_permission(workspace_id, 'users.manage') and app.has_recent_strong_auth());

create policy invitations_select on public.workspace_invitations
for select to authenticated
using (app.has_permission(workspace_id, 'users.manage') and app.has_recent_strong_auth());

create policy invitation_roles_select on public.workspace_invitation_roles
for select to authenticated
using (app.has_permission(workspace_id, 'users.manage') and app.has_recent_strong_auth());

create policy audit_events_select on public.audit_events
for select to authenticated
using (app.has_permission(workspace_id, 'audit.read'));

revoke all on table
  public.organizations,
  public.workspaces,
  public.user_profiles,
  public.workspace_memberships,
  public.roles,
  public.permissions,
  public.role_permissions,
  public.membership_roles,
  public.workspace_invitations,
  public.workspace_invitation_roles,
  public.audit_events
from public, anon, authenticated, service_role;

grant select (id, name, status, created_at, updated_at)
  on public.organizations to authenticated;
grant select on public.workspaces to authenticated;
grant update (
  name,
  status,
  default_locale,
  timezone,
  default_currency,
  odometer_unit,
  mfa_required_for_all
) on public.workspaces to authenticated;
grant select on public.user_profiles to authenticated;
grant update (display_name, preferred_locale) on public.user_profiles to authenticated;
grant select on
  public.workspace_memberships,
  public.roles,
  public.permissions,
  public.role_permissions,
  public.membership_roles
to authenticated;
grant insert (workspace_id, user_id, status)
  on public.workspace_memberships to authenticated;
grant update (status)
  on public.workspace_memberships to authenticated;
grant insert (
  workspace_id,
  key,
  name,
  description,
  source,
  status,
  requires_mfa
) on public.roles to authenticated;
grant update (name, description, status, requires_mfa)
  on public.roles to authenticated;
grant insert (workspace_id, key, description, source, status)
  on public.permissions to authenticated;
grant update (description, status)
  on public.permissions to authenticated;
grant insert (workspace_id, role_id, permission_id, status)
  on public.role_permissions to authenticated;
grant update (status)
  on public.role_permissions to authenticated;
grant insert (workspace_id, membership_id, role_id, status)
  on public.membership_roles to authenticated;
grant update (status)
  on public.membership_roles to authenticated;
grant select (
  id,
  workspace_id,
  email,
  status,
  requested_locale,
  invited_by,
  expires_at,
  accepted_by,
  accepted_membership_id,
  accepted_at,
  revoked_at,
  created_at,
  updated_at
) on public.workspace_invitations to authenticated;
grant select on public.workspace_invitation_roles to authenticated;
grant select on public.audit_events to authenticated;

grant select, insert, update on
  public.organizations,
  public.workspaces,
  public.user_profiles,
  public.workspace_memberships,
  public.roles,
  public.permissions,
  public.role_permissions,
  public.membership_roles,
  public.workspace_invitations,
  public.workspace_invitation_roles
to service_role;
grant select on public.audit_events to service_role;

revoke all on all functions in schema app from public, anon, authenticated, service_role;
grant usage on schema app to authenticated, service_role;
grant execute on function app.current_user_id() to authenticated, service_role;
grant execute on function app.auth_assurance_at_least(text) to authenticated, service_role;
grant execute on function app.has_recent_strong_auth(integer) to authenticated, service_role;
grant execute on function app.has_active_membership(uuid) to authenticated, service_role;
grant execute on function app.has_permission(uuid, text) to authenticated, service_role;
grant execute on function app.has_organization_membership(uuid) to authenticated, service_role;
grant execute on function app.has_organization_permission(uuid, text) to authenticated, service_role;
grant execute on function app.can_read_user_profile(uuid) to authenticated, service_role;
grant execute on function app.can_read_permission(uuid) to authenticated, service_role;
grant execute on function app.write_audit_event(
  uuid,
  text,
  text,
  uuid,
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb,
  text,
  text,
  uuid,
  inet,
  text,
  text,
  jsonb
) to service_role;

comment on schema app is 'Private fixed-search-path helpers for authorization and trusted writes.';
comment on table public.organizations is 'Commercial account boundary; lifecycle-only, never hard deleted.';
comment on table public.workspaces is 'Operational tenant and Row-Level Security boundary.';
comment on table public.permissions is 'Immutable permission-key contracts; labels are localized outside this table.';
comment on table public.audit_events is 'Append-only workspace audit history written by trusted routines.';
comment on function app.write_audit_event(
  uuid,
  text,
  text,
  uuid,
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb,
  text,
  text,
  uuid,
  inet,
  text,
  text,
  jsonb
) is 'Service-role-only append primitive; browser roles have no execute or insert privilege.';
