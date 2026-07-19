-- T-AUTH-002, T-AUTH-003, T-AUTH-004, T-TEN-001, T-RBAC-001, T-AUD-001
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(83);

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  assurance text default 'aal1',
  factor_age_seconds integer default 0
)
returns void
language plpgsql
as $$
declare
  claims jsonb;
begin
  claims := pg_catalog.jsonb_build_object(
    'sub', fixture_user_id::text,
    'role', 'authenticated',
    'aal', assurance,
    'amr', case
      when assurance = 'aal2' then pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'method', 'totp',
          'timestamp', pg_catalog.floor(
            pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
          )::bigint - factor_age_seconds
        )
      )
      else pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'method', 'password',
          'timestamp', pg_catalog.extract('epoch', pg_catalog.statement_timestamp())::bigint
        )
      )
    end
  );

  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

select extensions.has_table('public', 'organizations', 'organizations exists');
select extensions.has_table('public', 'workspaces', 'workspaces exists');
select extensions.has_table('public', 'user_profiles', 'user_profiles exists');
select extensions.has_table(
  'public',
  'workspace_memberships',
  'workspace_memberships exists'
);
select extensions.has_table('public', 'roles', 'roles exists');
select extensions.has_table('public', 'permissions', 'permissions exists');
select extensions.has_table('public', 'role_permissions', 'role_permissions exists');
select extensions.has_table('public', 'membership_roles', 'membership_roles exists');
select extensions.has_table(
  'public',
  'workspace_invitations',
  'workspace_invitations exists'
);
select extensions.has_table(
  'public',
  'workspace_invitation_roles',
  'workspace_invitation_roles exists'
);
select extensions.has_table('public', 'audit_events', 'audit_events exists');

select extensions.has_function('app', 'current_user_id', array[]::name[], 'current user helper exists');
select extensions.has_function(
  'app',
  'has_active_membership',
  array['uuid'],
  'active membership helper exists'
);
select extensions.has_function(
  'app',
  'has_permission',
  array['uuid', 'text'],
  'permission helper exists'
);
select extensions.has_function(
  'app',
  'has_recent_strong_auth',
  array['integer'],
  'recent assurance helper exists'
);
select extensions.has_function(
  'app',
  'write_audit_event',
  array[
    'uuid', 'text', 'text', 'uuid', 'uuid', 'text', 'jsonb', 'jsonb',
    'jsonb', 'text', 'text', 'uuid', 'inet', 'text', 'text', 'jsonb'
  ],
  'trusted audit append helper exists'
);
select extensions.has_function(
  'app',
  'validate_membership_activation',
  array[]::name[],
  'membership lifecycle guard exists'
);
select extensions.has_function(
  'app',
  'assert_permission_mfa_requirement',
  array[]::name[],
  'permission reactivation MFA guard exists'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;

select extensions.ok(
  app.has_active_membership('10000000-0000-4000-8000-000000000001'),
  'T-TEN-001 active member resolves its workspace'
);
select extensions.ok(
  app.has_permission('10000000-0000-4000-8000-000000000001', 'roles.manage'),
  'T-RBAC-001 explicit active role grant resolves permission'
);
select extensions.results_eq(
  $$select id from public.workspaces order by id$$,
  $$values ('10000000-0000-4000-8000-000000000001'::uuid)$$,
  'T-TEN-001 workspace A administrator cannot select workspace B'
);
select extensions.results_eq(
  $$select id from public.organizations order by id$$,
  $$values ('11000000-0000-4000-8000-000000000001'::uuid)$$,
  'T-TEN-001 workspace A administrator cannot select organization B'
);
select extensions.is(
  (select pg_catalog.count(*) from public.user_profiles),
  3::bigint,
  'T-TEN-001 roster access does not disclose workspace B profile'
);
select extensions.lives_ok(
  $$
    insert into public.roles (workspace_id, key, name)
    values (
      '10000000-0000-4000-8000-000000000001',
      'fixture_allowed',
      'Allowed fixture role'
    )
  $$,
  'same-workspace role write succeeds with roles.manage and recent AAL2'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'identity.roles.insert'
      and after_data ->> 'key' = 'fixture_allowed'
  ),
  1::bigint,
  'T-AUD-001 privileged same-workspace role write is audited atomically'
);
select extensions.results_eq(
  $$
    select actor_user_id, actor_type, auth_assurance
    from public.audit_events
    where action = 'identity.roles.insert'
      and after_data ->> 'key' = 'fixture_allowed'
  $$,
  $$
    values (
      '31000000-0000-4000-8000-000000000001'::uuid,
      'user'::text,
      'aal2'::text
    )
  $$,
  'T-AUD-001 browser mutation audit captures the validated actor and assurance'
);
select extensions.is(
  (select created_by from public.roles where key = 'fixture_allowed'),
  '31000000-0000-4000-8000-000000000001'::uuid,
  'browser role creation derives created_by from the authenticated subject'
);
select extensions.ok(
  not pg_catalog.has_column_privilege('authenticated', 'public.organizations', 'billing_metadata', 'SELECT')
    and not pg_catalog.has_column_privilege('authenticated', 'public.workspace_memberships', 'invited_by', 'INSERT')
    and not pg_catalog.has_column_privilege('authenticated', 'public.workspace_memberships', 'activated_at', 'INSERT')
    and not pg_catalog.has_column_privilege('authenticated', 'public.roles', 'created_by', 'INSERT')
    and not pg_catalog.has_column_privilege('authenticated', 'public.role_permissions', 'granted_by', 'INSERT')
    and not pg_catalog.has_column_privilege('authenticated', 'public.membership_roles', 'assigned_by', 'INSERT'),
  'internal billing, ownership, and lifecycle columns are not browser-exposed'
);
select extensions.lives_ok(
  $$
    update public.workspaces
    set name = 'Northstar Motors Test Updated'
    where id = '10000000-0000-4000-8000-000000000001'
  $$,
  'workspace.manage with recent AAL2 can update an allowed workspace setting'
);
select extensions.is(
  (
    select settings_version
    from public.workspaces
    where id = '10000000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'workspace settings version advances automatically on configuration change'
);
select extensions.throws_ok(
  $$
    update public.workspaces
    set settings_version = 99
    where id = '10000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  'permission denied for table workspaces',
  'browser callers cannot forge workspace settings versions'
);
select extensions.throws_ok(
  $$
    insert into public.roles (workspace_id, key, name)
    values (
      '20000000-0000-4000-8000-000000000002',
      'cross_workspace_attempt',
      'Cross workspace attempt'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "roles"',
  'T-TEN-001 WITH CHECK rejects workspace B insert'
);
select extensions.throws_ok(
  $$
    update public.organizations
    set name = 'Unaudited browser change'
    where id = '11000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  'permission denied for table organizations',
  'organization lifecycle changes are service-command-only in this slice'
);
select extensions.throws_ok(
  $$
    insert into public.permissions (workspace_id, key, source)
    values (
      '10000000-0000-4000-8000-000000000001',
      'roles.manage',
      'workspace'
    )
  $$,
  '23514',
  'workspace permission keys cannot shadow platform keys',
  'T-RBAC-001 workspace-private permissions cannot shadow platform keys'
);
select extensions.throws_ok(
  $$
    insert into public.workspace_memberships (
      workspace_id,
      user_id,
      status
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '32000000-0000-4000-8000-000000000001',
      'active'
    )
  $$,
  '42501',
  'membership activation requires a trusted application command',
  'invite-only membership activation cannot be forged through the browser role'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal1', 0);
set local role authenticated;

select extensions.ok(
  app.has_active_membership('10000000-0000-4000-8000-000000000001'),
  'active limited membership remains active'
);
select extensions.ok(
  app.has_permission('10000000-0000-4000-8000-000000000001', 'workspace.read'),
  'limited fixture has its explicit read permission'
);
select extensions.ok(
  not app.has_permission('10000000-0000-4000-8000-000000000001', 'roles.manage'),
  'T-RBAC-001 missing permission is not inferred from membership or role label'
);
select extensions.throws_ok(
  $$
    insert into public.roles (workspace_id, key, name)
    values (
      '10000000-0000-4000-8000-000000000001',
      'missing_permission_attempt',
      'Missing permission attempt'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "roles"',
  'T-RBAC-001 missing roles.manage rejects a same-workspace write'
);
select extensions.is(
  (select pg_catalog.count(*) from public.audit_events),
  0::bigint,
  'audit rows are not disclosed without audit.read'
);

reset role;
update public.user_profiles
set status = 'deactivated'
where user_id = '31000000-0000-4000-8000-000000000002';
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'identity.user_profiles.status_update'
      and entity_id = '31000000-0000-4000-8000-000000000002'
      and workspace_id = '10000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'T-AUD-001 user deactivation emits a workspace-scoped audit event'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal1', 0);
set local role authenticated;
select extensions.ok(
  not app.has_active_membership('10000000-0000-4000-8000-000000000001'),
  'T-AUTH-003 a deactivated user profile cannot authorize through an active membership'
);
select extensions.is(
  (select pg_catalog.count(*) from public.user_profiles),
  0::bigint,
  'T-AUTH-003 a deactivated profile cannot use a stale session to read profile data'
);

reset role;
update public.user_profiles
set status = 'active'
where user_id = '31000000-0000-4000-8000-000000000002';
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000003', 'aal2', 0);
set local role authenticated;

select extensions.ok(
  not app.has_active_membership('10000000-0000-4000-8000-000000000001'),
  'inactive membership fails the authoritative membership helper'
);
select extensions.is(
  (select pg_catalog.count(*) from public.workspaces),
  0::bigint,
  'T-TEN-001 inactive membership cannot select its former workspace'
);
select extensions.throws_ok(
  $$
    insert into public.roles (workspace_id, key, name)
    values (
      '10000000-0000-4000-8000-000000000001',
      'inactive_attempt',
      'Inactive attempt'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "roles"',
  'inactive membership cannot write despite a retained role assignment'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1', 0);
set local role authenticated;

select extensions.ok(
  not app.has_active_membership('10000000-0000-4000-8000-000000000001'),
  'T-AUTH-002 administrator role requires AAL2 for workspace access'
);
select extensions.is(
  (select pg_catalog.count(*) from public.workspaces),
  0::bigint,
  'T-AUTH-002 administrator without MFA cannot select the workspace'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 1000);
set local role authenticated;

select extensions.ok(
  app.auth_assurance_at_least('aal2'),
  'an AAL2 session retains its assurance level'
);
select extensions.ok(
  not app.has_recent_strong_auth(),
  'T-AUTH-004 strong authentication older than fifteen minutes is stale'
);
select extensions.throws_ok(
  $$
    insert into public.roles (workspace_id, key, name)
    values (
      '10000000-0000-4000-8000-000000000001',
      'stale_step_up_attempt',
      'Stale step-up attempt'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "roles"',
  'T-AUTH-004 stale AAL2 cannot perform role-management write'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 900);
set local role authenticated;

select extensions.ok(
  app.has_recent_strong_auth(),
  'T-AUTH-004 strong authentication is valid at the fifteen-minute boundary'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', -1);
set local role authenticated;

select extensions.ok(
  not app.has_recent_strong_auth(),
  'T-AUTH-004 a future authentication-method timestamp fails closed'
);

reset role;

insert into public.workspace_invitations (
  id,
  workspace_id,
  email,
  token_hash,
  status,
  invited_by,
  expires_at,
  created_at
) values (
  '81000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  'limited@northstar.invalid',
  'expired-fixture-hash-not-a-credential',
  'pending',
  '31000000-0000-4000-8000-000000000001',
  pg_catalog.statement_timestamp() - interval '1 day',
  pg_catalog.statement_timestamp() - interval '2 days'
);
select extensions.throws_ok(
  $$
    update public.workspace_invitations
    set status = 'accepted',
        accepted_by = '31000000-0000-4000-8000-000000000002',
        accepted_membership_id = '41000000-0000-4000-8000-000000000002',
        accepted_at = pg_catalog.statement_timestamp()
    where id = '81000000-0000-4000-8000-000000000002'
  $$,
  '23514',
  'expired invitations cannot be accepted',
  'expired invitations fail closed even for a privileged command'
);
select extensions.throws_ok(
  $$
    insert into public.membership_roles (
      workspace_id,
      membership_id,
      role_id,
      status
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '41000000-0000-4000-8000-000000000001',
      '52000000-0000-4000-8000-000000000001',
      'active'
    )
  $$,
  '23503',
  'insert or update on table "membership_roles" violates foreign key constraint "membership_roles_workspace_id_role_id_fkey"',
  'T-TEN-001 composite role ownership blocks a cross-workspace assignment'
);

insert into public.permissions (
  id,
  workspace_id,
  key,
  source,
  status
) values (
  '71000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000002',
  'fixture.private_read',
  'workspace',
  'active'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where workspace_id = '20000000-0000-4000-8000-000000000002'
      and action = 'identity.permissions.insert'
      and entity_id = '71000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'T-AUD-001 workspace-scoped permission creation is audited atomically'
);

select extensions.throws_ok(
  $$
    insert into public.role_permissions (
      workspace_id,
      role_id,
      permission_id,
      status
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'active'
    )
  $$,
  '23514',
  'workspace-scoped permission cannot be granted across workspaces',
  'T-TEN-001 workspace-private permission cannot cross the boundary'
);

select extensions.throws_ok(
  $$
    insert into public.role_permissions (
      workspace_id,
      role_id,
      permission_id,
      status
    )
    select
      '10000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000002',
      p.id,
      'active'
    from public.permissions p
    where p.key = 'roles.manage' and p.workspace_id is null
  $$,
  '23514',
  'roles with administrative permissions must require MFA',
  'T-AUTH-002 administrative permission cannot be granted to a non-MFA role'
);

update public.roles
set requires_mfa = true
where id = '51000000-0000-4000-8000-000000000002';
insert into public.role_permissions (workspace_id, role_id, permission_id, status)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000002',
  p.id,
  'active'
from public.permissions p
where p.key = 'roles.manage' and p.workspace_id is null;
update public.permissions
set status = 'retired'
where key = 'roles.manage' and workspace_id is null;
update public.roles
set requires_mfa = false
where id = '51000000-0000-4000-8000-000000000002';

select extensions.throws_ok(
  $$
    update public.permissions
    set status = 'active'
    where key = 'roles.manage' and workspace_id is null
  $$,
  '23514',
  'administrative permissions cannot activate for a role without MFA',
  'T-AUTH-002 permission reactivation cannot bypass the role MFA invariant'
);

update public.role_permissions
set status = 'revoked',
    revoked_at = pg_catalog.statement_timestamp()
where workspace_id = '10000000-0000-4000-8000-000000000001'
  and role_id = '51000000-0000-4000-8000-000000000002'
  and permission_id = (
    select id from public.permissions
    where key = 'roles.manage' and workspace_id is null
  );
update public.permissions
set status = 'active'
where key = 'roles.manage' and workspace_id is null;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;
select extensions.throws_ok(
  $$
    insert into public.workspace_invitations (
      id,
      workspace_id,
      email,
      token_hash,
      status,
      invited_by,
      expires_at
    ) values (
      '81000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      'invitee@northstar.invalid',
      'fixture-hash-not-a-credential',
      'pending',
      '31000000-0000-4000-8000-000000000001',
      pg_catalog.statement_timestamp() + interval '1 day'
    )
  $$,
  '42501',
  'permission denied for table workspace_invitations',
  'invitation creation is restricted to a trusted application command'
);

reset role;
set local role service_role;
select extensions.lives_ok(
  $$
    insert into public.workspace_invitations (
      id,
      workspace_id,
      email,
      token_hash,
      status,
      invited_by,
      expires_at
    ) values (
      '81000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      'invitee@northstar.invalid',
      'fixture-hash-not-a-credential',
      'pending',
      '31000000-0000-4000-8000-000000000001',
      pg_catalog.statement_timestamp() + interval '1 day'
    )
  $$,
  'trusted service role can create a pending invitation'
);
select extensions.is(
  (
    select actor_type
    from public.audit_events
    where action = 'identity.workspace_invitations.insert'
      and entity_id = '81000000-0000-4000-8000-000000000001'
  ),
  'service',
  'T-AUD-001 a privileged pooled write with stale JWT claims is attributed to service'
);
select extensions.is(
  (
    select actor_user_id
    from public.audit_events
    where action = 'identity.workspace_invitations.insert'
      and entity_id = '81000000-0000-4000-8000-000000000001'
  ),
  null::uuid,
  'T-AUD-001 stale JWT subject is not retained on a service audit event'
);
select extensions.is(
  (
    select auth_assurance
    from public.audit_events
    where action = 'identity.workspace_invitations.insert'
      and entity_id = '81000000-0000-4000-8000-000000000001'
  ),
  'system',
  'T-AUD-001 stale JWT assurance is not retained on a service audit event'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_invitations
    where id = '81000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'authorized administrators can list invitation metadata'
);
select extensions.throws_ok(
  $$
    select token_hash
    from public.workspace_invitations
    where id = '81000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  'permission denied for table workspace_invitations',
  'invitation token hashes are never browser-readable'
);
select extensions.is(
  (
    select after_data ? 'token_hash'
    from public.audit_events
    where action = 'identity.workspace_invitations.insert'
      and entity_id = '81000000-0000-4000-8000-000000000001'
  ),
  false,
  'invitation audit snapshots never retain the token hash'
);

reset role;
select extensions.throws_ok(
  $$
    update public.workspace_invitations
    set status = 'accepted',
        accepted_by = '31000000-0000-4000-8000-000000000002',
        accepted_membership_id = '41000000-0000-4000-8000-000000000002',
        accepted_at = pg_catalog.statement_timestamp()
    where id = '81000000-0000-4000-8000-000000000001'
  $$,
  '23514',
  'accepted user email must match the invitation email',
  'invitation acceptance cannot activate a different identity'
);

select extensions.throws_ok(
  $$
    insert into public.workspace_invitation_roles (
      workspace_id,
      invitation_id,
      role_id
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '81000000-0000-4000-8000-000000000001',
      '52000000-0000-4000-8000-000000000001'
    )
  $$,
  '23503',
  'insert or update on table "workspace_invitation_roles" violates foreign key constraint "workspace_invitation_roles_workspace_id_role_id_fkey"',
  'invitation role links require same-workspace role ownership'
);
select extensions.throws_ok(
  $$
    update public.workspace_invitations
    set token_hash = 'changed-fixture-hash'
    where id = '81000000-0000-4000-8000-000000000001'
  $$,
  '23514',
  'workspace_invitations.token_hash is immutable',
  'invitation token hashes are immutable after creation'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;
select extensions.throws_ok(
  $$select app.write_audit_event(
    '10000000-0000-4000-8000-000000000001',
    'fixture.browser_forge',
    'workspace'
  )$$,
  '42501',
  'permission denied for function write_audit_event',
  'browser caller cannot forge an audit event'
);

reset role;
set local role service_role;
select extensions.throws_ok(
  $$
    insert into public.permissions (key, source)
    values ('fixture.service_global', 'platform')
  $$,
  '42501',
  'platform permissions are migration-owned',
  'global platform permission contracts can only change through migrations'
);
select extensions.lives_ok(
  $$select app.write_audit_event(
    '10000000-0000-4000-8000-000000000001',
    'fixture.trusted_append',
    'workspace',
    '10000000-0000-4000-8000-000000000001',
    null,
    'service',
    null,
    '{"status":"checked"}'::jsonb,
    null,
    'T-AUD-001 fixture',
    'fixture-request'
  )$$,
  'T-AUD-001 service role can append through the trusted function'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'fixture.trusted_append'
  ),
  1::bigint,
  'trusted audit append persists exactly once'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'fixture.trusted_append'
  ),
  1::bigint,
  'audit.read exposes same-workspace audit event'
);
select extensions.results_eq(
  $$select distinct workspace_id from public.audit_events order by workspace_id$$,
  $$values ('10000000-0000-4000-8000-000000000001'::uuid)$$,
  'T-TEN-001 audit.read never crosses the workspace boundary'
);

reset role;
select extensions.throws_ok(
  $$
    update public.audit_events
    set reason = 'tampered'
    where action = 'fixture.trusted_append'
  $$,
  '55000',
  'audit events are append-only',
  'T-AUD-001 audit update is prohibited even to the database owner'
);
select extensions.throws_ok(
  $$delete from public.audit_events where action = 'fixture.trusted_append'$$,
  '55000',
  'audit events are append-only',
  'T-AUD-001 audit delete is prohibited even to the database owner'
);
select extensions.throws_ok(
  $$delete from public.roles where id = '51000000-0000-4000-8000-000000000002'$$,
  '55000',
  'hard delete is prohibited for roles',
  'identity records use lifecycle state instead of hard delete'
);
select extensions.throws_ok(
  $$
    update public.permissions
    set key = 'fixture.renamed_permission'
    where key = 'workspace.read' and workspace_id is null
  $$,
  '23514',
  'permissions.key is immutable',
  'T-RBAC-001 permission keys are immutable machine contracts'
);
select extensions.throws_ok(
  $$
    update public.workspace_memberships
    set workspace_id = '20000000-0000-4000-8000-000000000002'
    where id = '41000000-0000-4000-8000-000000000002'
  $$,
  '23514',
  'workspace_memberships.workspace_id is immutable',
  'T-TEN-001 workspace reassignment spoof is rejected'
);
update public.organizations
set status = 'suspended'
where id = '11000000-0000-4000-8000-000000000001';
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'identity.organizations.status_update'
      and entity_id = '11000000-0000-4000-8000-000000000001'
      and workspace_id = '10000000-0000-4000-8000-000000000001'
      and after_data ->> 'status' = 'suspended'
  ),
  1::bigint,
  'T-AUD-001 organization suspension emits one event per workspace boundary'
);
update public.organizations
set status = 'active'
where id = '11000000-0000-4000-8000-000000000001';
select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
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
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  11::bigint,
  'all exposed tenancy tables enable and force RLS'
);

select * from extensions.finish();
rollback;
