-- VYN-E00-S03, VYN-TEN-001, T-TEN-001, T-RBAC-001
-- Deterministic, fictional two-workspace fixtures. No production or tenant data.
-- Provider identity rows are omitted and password hashes are randomized, so fixtures
-- cannot sign in with a known credential.

-- Retain the Stage 0 compatibility projection while production tests migrate to
-- organizations/workspaces. It contains the same two stable workspace IDs.
-- Keep its disposable DDL and rows in one statement so the seed batch cannot
-- resolve the insert before the compatibility table exists.
do $stage0_seed$
begin
  execute 'create schema if not exists stage0';
  execute $stage0_schema$
    create table if not exists stage0.synthetic_workspaces (
      id uuid primary key,
      slug text not null unique,
      display_name text not null,
      fixture_only boolean not null default true
    )
  $stage0_schema$;
  execute $stage0_rows$
    insert into stage0.synthetic_workspaces (id, slug, display_name)
    values
      ('10000000-0000-4000-8000-000000000001', 'northstar-motors-test', 'Northstar Motors Test'),
      ('20000000-0000-4000-8000-000000000002', 'harbour-auto-lab', 'Harbour Auto Lab')
    on conflict (id) do update
    set slug = excluded.slug,
        display_name = excluded.display_name,
        fixture_only = true
  $stage0_rows$;
end
$stage0_seed$;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '31000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'admin@northstar.invalid',
    extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
    pg_catalog.statement_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"fixture":true}'::jsonb,
    pg_catalog.statement_timestamp(),
    pg_catalog.statement_timestamp(),
    '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '31000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'limited@northstar.invalid',
    extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
    pg_catalog.statement_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"fixture":true}'::jsonb,
    pg_catalog.statement_timestamp(),
    pg_catalog.statement_timestamp(),
    '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '31000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'inactive@northstar.invalid',
    extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
    pg_catalog.statement_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"fixture":true}'::jsonb,
    pg_catalog.statement_timestamp(),
    pg_catalog.statement_timestamp(),
    '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '32000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'admin@harbour.invalid',
    extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
    pg_catalog.statement_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"fixture":true}'::jsonb,
    pg_catalog.statement_timestamp(),
    pg_catalog.statement_timestamp(),
    '', '', '', ''
  )
on conflict (id) do update
set aud = excluded.aud,
    role = excluded.role,
    email = excluded.email,
    raw_app_meta_data = excluded.raw_app_meta_data,
    raw_user_meta_data = excluded.raw_user_meta_data,
    updated_at = excluded.updated_at;

insert into public.organizations (id, name, status, billing_metadata)
values
  ('11000000-0000-4000-8000-000000000001', 'Northstar Group Test', 'active', '{"fixture":true}'),
  ('22000000-0000-4000-8000-000000000002', 'Harbour Group Lab', 'active', '{"fixture":true}')
on conflict (id) do update
set name = excluded.name,
    status = excluded.status,
    billing_metadata = excluded.billing_metadata;

insert into public.workspaces (
  id,
  organization_id,
  slug,
  name,
  status,
  default_locale,
  timezone,
  default_currency,
  odometer_unit,
  mfa_required_for_all
)
values
  (
    '10000000-0000-4000-8000-000000000001',
    '11000000-0000-4000-8000-000000000001',
    'northstar-motors-test',
    'Northstar Motors Test',
    'active',
    'en-CA',
    'America/Toronto',
    'CAD',
    'km',
    false
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '22000000-0000-4000-8000-000000000002',
    'harbour-auto-lab',
    'Harbour Auto Lab',
    'active',
    'fr-CA',
    'America/Halifax',
    'CAD',
    'km',
    false
  )
on conflict (id) do update
set slug = excluded.slug,
    name = excluded.name,
    status = excluded.status,
    default_locale = excluded.default_locale,
    timezone = excluded.timezone,
    default_currency = excluded.default_currency,
    odometer_unit = excluded.odometer_unit,
    mfa_required_for_all = excluded.mfa_required_for_all;

insert into public.user_profiles (user_id, display_name, preferred_locale, status)
values
  ('31000000-0000-4000-8000-000000000001', 'Northstar Admin', 'en-CA', 'active'),
  ('31000000-0000-4000-8000-000000000002', 'Northstar Limited', 'en-CA', 'active'),
  ('31000000-0000-4000-8000-000000000003', 'Northstar Inactive', 'en-CA', 'deactivated'),
  ('32000000-0000-4000-8000-000000000001', 'Harbour Admin', 'fr-CA', 'active')
on conflict (user_id) do update
set display_name = excluded.display_name,
    preferred_locale = excluded.preferred_locale,
    status = excluded.status;

insert into public.workspace_memberships (
  id,
  workspace_id,
  user_id,
  status,
  invited_at,
  activated_at,
  deactivated_at,
  invited_by
)
values
  (
    '41000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001',
    'active',
    timestamptz '2026-07-15 12:00:00+00',
    timestamptz '2026-07-15 12:05:00+00',
    null,
    null
  ),
  (
    '41000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000002',
    'active',
    timestamptz '2026-07-15 12:00:00+00',
    timestamptz '2026-07-15 12:05:00+00',
    null,
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '41000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000003',
    'deactivated',
    timestamptz '2026-07-15 12:00:00+00',
    timestamptz '2026-07-15 12:05:00+00',
    timestamptz '2026-07-15 13:00:00+00',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '42000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    '32000000-0000-4000-8000-000000000001',
    'active',
    timestamptz '2026-07-15 12:00:00+00',
    timestamptz '2026-07-15 12:05:00+00',
    null,
    null
  )
on conflict (workspace_id, user_id) do update
set status = excluded.status,
    activated_at = excluded.activated_at,
    deactivated_at = excluded.deactivated_at,
    invited_by = excluded.invited_by;

update public.user_profiles
set last_workspace_id = case user_id
  when '32000000-0000-4000-8000-000000000001' then '20000000-0000-4000-8000-000000000002'::uuid
  else '10000000-0000-4000-8000-000000000001'::uuid
end
where user_id in (
  '31000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000002',
  '31000000-0000-4000-8000-000000000003',
  '32000000-0000-4000-8000-000000000001'
);

insert into public.roles (id, workspace_id, key, name, source, status, requires_mfa)
values
  (
    '51000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'fixture_admin',
    'Fixture administrator',
    'system',
    'active',
    true
  ),
  (
    '51000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'fixture_limited',
    'Fixture limited member',
    'system',
    'active',
    false
  ),
  (
    '52000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'fixture_admin',
    'Fixture administrator',
    'system',
    'active',
    true
  )
on conflict (workspace_id, key) do update
set name = excluded.name,
    status = excluded.status,
    requires_mfa = excluded.requires_mfa;

insert into public.role_permissions (workspace_id, role_id, permission_id, status)
select
  role.workspace_id,
  role.id,
  permission.id,
  'active'
from public.roles role
cross join public.permissions permission
where role.id in (
    '51000000-0000-4000-8000-000000000001',
    '52000000-0000-4000-8000-000000000001'
  )
  and permission.workspace_id is null
on conflict (workspace_id, role_id, permission_id) do update
set status = 'active',
    revoked_by = null,
    revoked_at = null;

insert into public.role_permissions (workspace_id, role_id, permission_id, status)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000002',
  permission.id,
  'active'
from public.permissions permission
where permission.key = 'workspace.read'
  and permission.workspace_id is null
on conflict (workspace_id, role_id, permission_id) do update
set status = 'active',
    revoked_by = null,
    revoked_at = null;

insert into public.membership_roles (
  id,
  workspace_id,
  membership_id,
  role_id,
  status
)
values
  (
    '61000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '41000000-0000-4000-8000-000000000001',
    '51000000-0000-4000-8000-000000000001',
    'active'
  ),
  (
    '61000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '41000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000002',
    'active'
  ),
  (
    '61000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '41000000-0000-4000-8000-000000000003',
    '51000000-0000-4000-8000-000000000001',
    'active'
  ),
  (
    '62000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    '42000000-0000-4000-8000-000000000001',
    '52000000-0000-4000-8000-000000000001',
    'active'
  )
on conflict (workspace_id, membership_id, role_id) do update
set status = 'active',
    revoked_by = null,
    revoked_at = null;
