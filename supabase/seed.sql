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

-- M3-STARTER-ENTITLEMENTS-BEGIN
-- VYN-CFG-001 / STD-DEAL-001: fail-closed M3 capabilities are enabled as
-- immutable versioned entitlements, never as feature flags. Both fictional
-- workspaces receive the same tenant-neutral payload and canonical checksum.
with workspace_fixture(workspace_id) as (
  values
    ('10000000-0000-4000-8000-000000000001'::uuid),
    ('20000000-0000-4000-8000-000000000002'::uuid)
),
entitlement_fixture(entitlement_key) as (
  values
    ('crm'::text),
    ('deals'::text),
    ('third_party_finance'::text),
    ('one_time_payments'::text),
    ('custom_workflows'::text)
)
insert into public.workspace_feature_entitlements (
  id,
  workspace_id,
  entitlement_key,
  version,
  status,
  enabled,
  limits,
  checksum,
  provenance,
  effective_from,
  effective_until,
  idempotency_key,
  activated_at
)
select
  pg_catalog.md5(
    workspace_fixture.workspace_id::text
      || ':starter-entitlement:'
      || entitlement_fixture.entitlement_key
  )::uuid,
  workspace_fixture.workspace_id,
  entitlement_fixture.entitlement_key,
  1,
  'active',
  true,
  '{}'::jsonb,
  app.entitlement_payload_checksum(true, '{}'::jsonb),
  pg_catalog.jsonb_build_object(
    'source', 'starter_pack',
    'pack_id', 'starter-retail-dealer',
    'pack_version', '1.1.0'
  ),
  timestamptz '2026-07-16 20:00:00+00',
  null,
  'starter-retail-dealer:1.1.0:' || entitlement_fixture.entitlement_key,
  timestamptz '2026-07-16 20:00:00+00'
from workspace_fixture
cross join entitlement_fixture
on conflict (id) do nothing;
-- M3-STARTER-ENTITLEMENTS-END

-- M3-STARTER-LEGAL-ENTITIES-BEGIN
-- VYN-DEAL-001 / STD-DEAL-001: each synthetic workspace has exactly one
-- tenant-neutral active legal entity for deal and document ownership. Runtime
-- onboarding replaces this fixture; it is not a tenant contract or formula.
with workspace_fixture(workspace_id) as (
  values
    ('10000000-0000-4000-8000-000000000001'::uuid),
    ('20000000-0000-4000-8000-000000000002'::uuid)
)
insert into public.legal_entities (
  id,
  workspace_id,
  key,
  legal_names,
  display_names,
  organization_party_id,
  status,
  version,
  created_by,
  created_at
)
select
  pg_catalog.md5(
    workspace_fixture.workspace_id::text || ':starter-legal-entity:primary'
  )::uuid,
  workspace_fixture.workspace_id,
  'primary',
  '{"en":"Synthetic Dealer Legal Entity","fr":"Entité juridique de concession synthétique"}'::jsonb,
  '{"en":"Synthetic Dealer","fr":"Concession synthétique"}'::jsonb,
  null,
  'active',
  1,
  null,
  timestamptz '2026-07-16 20:30:00+00'
from workspace_fixture
on conflict (workspace_id, key) do nothing;
-- M3-STARTER-LEGAL-ENTITIES-END

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

-- M3-STARTER-ROLES-BEGIN
-- STD-DEAL-001 / M3-DEAL-AC-001: install the starter role configuration in
-- both synthetic workspaces without assigning it to fixture memberships. The
-- comma-delimited permission lists are exact immutable platform keys from
-- packs/starter-retail-dealer/roles.yaml; no wildcard grant is persisted.
do $starter_role_seed$
declare
  role_fixture record;
  seeded_workspace_id uuid;
  seeded_role_id uuid;
  seeded_permission_keys text[];
begin
  for role_fixture in
    select fixture.*
    from (values
      (
        'owner_admin'::text,
        'Owner / administrator'::text,
        'Propriétaire / administrateur'::text,
        true,
        'workspace.read,workspace.manage,users.read,users.manage,roles.manage,configuration.read,configuration.manage,approvals.read,approvals.create,integrations.read,integrations.manage,jobs.read,jobs.manage,audit.read,inventory.read,inventory.create,inventory.update,inventory.transition,inventory.archive,inventory.duplicate_override,inventory.facts_override,inventory.read_internal,inventory.update_internal,costs.read,costs.create,costs.reverse,media.read,media.create,media.update,media.archive,listings.read,listings.publish,listings.unpublish,listings.reconcile,crm.read,crm.create,crm.update,crm.assign,deals.read,deals.create,deals.update,deals.transition,deals.cancel,deals.close,finance_applications.read,finance_applications.create,finance_applications.update,payments.read,payments.record,payments.settle,payments.reverse,payments.refund,documents.read,documents.preview,documents.generate_approved,documents.print,documents.upload_signed,documents.mark_signed,documents.void,documents.void_signed,documents.supersede,formula.read,formula.activate,tax.read,tax.activate,tax.override,template.read,template.activate,workflow.read,workflow.activate,numbering.read,numbering.activate,reports.read,exports.read,exports.run,exports.run_sensitive,identifiers.read_restricted,identifiers.manage,files.read_restricted'::text
      ),
      (
        'manager'::text,
        'Manager'::text,
        'Gestionnaire'::text,
        false,
        'workspace.read,users.read,configuration.read,approvals.read,approvals.create,integrations.read,jobs.read,jobs.manage,audit.read,inventory.read,inventory.create,inventory.update,inventory.transition,inventory.archive,inventory.read_internal,inventory.update_internal,costs.read,costs.create,costs.reverse,media.read,media.create,media.update,media.archive,listings.read,listings.publish,listings.unpublish,listings.reconcile,crm.read,crm.create,crm.update,crm.assign,deals.read,deals.create,deals.update,deals.transition,deals.cancel,deals.close,finance_applications.read,finance_applications.create,finance_applications.update,payments.read,payments.record,payments.settle,payments.reverse,payments.refund,documents.read,documents.preview,documents.generate_approved,documents.print,documents.upload_signed,documents.mark_signed,documents.void,documents.void_signed,documents.supersede,formula.read,tax.read,template.read,workflow.read,numbering.read,reports.read,exports.read,exports.run,exports.run_sensitive,identifiers.read_restricted,files.read_restricted'::text
      ),
      (
        'sales'::text,
        'Sales'::text,
        'Ventes'::text,
        false,
        'workspace.read,configuration.read,inventory.read,media.read,listings.read,crm.read,crm.create,crm.update,crm.assign,deals.read,deals.create,deals.update,deals.transition,deals.cancel,deals.close,finance_applications.read,finance_applications.create,finance_applications.update,payments.read,payments.record,payments.settle,documents.read,documents.preview,documents.generate_approved,documents.print,documents.upload_signed,documents.mark_signed,documents.supersede,workflow.read,reports.read,identifiers.read_restricted,files.read_restricted'::text
      ),
      (
        'inventory'::text,
        'Inventory'::text,
        'Inventaire'::text,
        false,
        'workspace.read,configuration.read,inventory.read,inventory.create,inventory.update,inventory.transition,inventory.archive,inventory.read_internal,inventory.update_internal,costs.read,costs.create,media.read,media.create,media.update,media.archive,listings.read,listings.publish,listings.unpublish,listings.reconcile,workflow.read,identifiers.read_restricted,identifiers.manage,files.read_restricted'::text
      ),
      (
        'read_only'::text,
        'Read only'::text,
        'Lecture seule'::text,
        false,
        'workspace.read,configuration.read,jobs.read,audit.read,inventory.read,inventory.read_internal,costs.read,media.read,listings.read,crm.read,deals.read,finance_applications.read,payments.read,documents.read,formula.read,tax.read,template.read,workflow.read,numbering.read,reports.read,exports.read,identifiers.read_restricted,files.read_restricted'::text
      )
    ) as fixture(
      key,
      name_en,
      name_fr,
      requires_mfa,
      permission_list
    )
  loop
    seeded_permission_keys := pg_catalog.string_to_array(
      role_fixture.permission_list,
      ','
    );

    if pg_catalog.cardinality(seeded_permission_keys) <> (
      select pg_catalog.count(*)::integer
      from public.permissions permission
      where permission.workspace_id is null
        and permission.status = 'active'
        and permission.key = any (seeded_permission_keys)
    ) then
      raise exception 'starter role % references a missing platform permission',
        role_fixture.key;
    end if;

    foreach seeded_workspace_id in array array[
      '10000000-0000-4000-8000-000000000001'::uuid,
      '20000000-0000-4000-8000-000000000002'::uuid
    ]
    loop
      insert into public.roles (
        id,
        workspace_id,
        key,
        name,
        description,
        source,
        status,
        requires_mfa
      )
      values (
        pg_catalog.md5(
          seeded_workspace_id::text || ':starter-role:' || role_fixture.key
        )::uuid,
        seeded_workspace_id,
        role_fixture.key,
        case seeded_workspace_id
          when '20000000-0000-4000-8000-000000000002'::uuid
            then role_fixture.name_fr
          else role_fixture.name_en
        end,
        'Starter retail dealer pack 1.1.0',
        'pack',
        'active',
        role_fixture.requires_mfa
      )
      on conflict (workspace_id, key) do update
      set name = excluded.name,
          description = excluded.description,
          source = excluded.source,
          status = excluded.status,
          requires_mfa = excluded.requires_mfa
      returning id into seeded_role_id;

      insert into public.role_permissions (
        workspace_id,
        role_id,
        permission_id,
        status
      )
      select
        seeded_workspace_id,
        seeded_role_id,
        permission.id,
        'active'
      from public.permissions permission
      where permission.workspace_id is null
        and permission.status = 'active'
        and permission.key = any (seeded_permission_keys)
      on conflict (workspace_id, role_id, permission_id) do update
      set status = 'active',
          revoked_by = null,
          revoked_at = null;
    end loop;
  end loop;
end
$starter_role_seed$;
-- M3-STARTER-ROLES-END

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

-- M2-INV-AC-005/M2-INV-AC-006: deterministic, fictional runtime
-- configuration proves that location and workflow behavior are workspace data.
-- These names and UUIDs are synthetic test fixtures, never platform branches.
insert into public.locations (
  id,
  workspace_id,
  key,
  name,
  status,
  locale,
  timezone,
  address,
  contact
)
values
  (
    '73000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'synthetic.primary',
    'Northstar Synthetic Location',
    'active',
    'en-CA',
    'America/Toronto',
    '{"fixture":true}'::jsonb,
    '{}'::jsonb
  ),
  (
    '73000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'synthetic.primary',
    'Harbour Synthetic Location',
    'active',
    'fr-CA',
    'America/Halifax',
    '{"fixture":true}'::jsonb,
    '{}'::jsonb
  )
on conflict (id) do nothing;

insert into public.inventory_condition_definitions (
  id,
  workspace_id,
  key,
  labels,
  status
)
values
  (
    '73100000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'used.ready',
    '{"en":"Used - ready","fr":"Occasion - pret"}'::jsonb,
    'active'
  ),
  (
    '73100000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'used.ready',
    '{"en":"Used - ready","fr":"Occasion - pret"}'::jsonb,
    'active'
  )
on conflict (id) do nothing;

insert into public.workflow_definitions (
  id,
  workspace_id,
  key,
  entity_type,
  purpose_key,
  status
)
values
  (
    '74000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'inventory.standard',
    'inventory_unit',
    'primary',
    'active'
  ),
  (
    '74000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'inventory.standard',
    'inventory_unit',
    'primary',
    'active'
  )
on conflict (id) do nothing;

insert into public.workflow_versions (
  id,
  workspace_id,
  workflow_definition_id,
  version,
  schema_version,
  initial_state_key,
  status,
  checksum,
  source,
  activated_at
)
values
  -- Bound to the exact bytes of
  -- packs/starter-retail-dealer/workflows/inventory.yaml. The specification
  -- validator fails if this digest or the seeded state graph drifts.
  (
    '74100000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '74000000-0000-4000-8000-000000000001',
    '1.0.0',
    1,
    'draft',
    'draft',
    'cd63c3263c6d487f55417f826e919d6309b7b88c6f4da5640cb60da6c7d7b7cf',
    'starter_pack',
    null
  ),
  (
    '74100000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '74000000-0000-4000-8000-000000000002',
    '1.0.0',
    1,
    'draft',
    'draft',
    'cd63c3263c6d487f55417f826e919d6309b7b88c6f4da5640cb60da6c7d7b7cf',
    'starter_pack',
    null
  )
on conflict (id) do nothing;

with version_fixture(workspace_id, workflow_version_id) as (
  values
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      '74100000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '20000000-0000-4000-8000-000000000002'::uuid,
      '74100000-0000-4000-8000-000000000002'::uuid
    )
),
state_fixture(
  key,
  category,
  label_en,
  label_fr,
  publishable,
  available,
  terminal,
  sort_order
) as (
  values
    ('draft', 'draft', 'Draft', 'Brouillon', false, false, false, 10),
    ('incomplete', 'draft', 'Incomplete', 'Incomplet', false, false, false, 20),
    ('in_preparation', 'active', 'In preparation', 'En préparation', false, false, false, 30),
    ('ready', 'active', 'Ready', 'Prêt', true, true, false, 40),
    ('listed', 'active', 'Listed', 'Publié', true, true, false, 50),
    ('pending_sale', 'pending', 'Pending sale', 'Vente en attente', false, false, false, 60),
    ('sold', 'closed', 'Sold', 'Vendu', false, false, true, 70),
    ('wholesale', 'closed', 'Wholesale', 'Vente en gros', false, false, true, 80),
    ('archived', 'archived', 'Archived', 'Archivé', false, false, true, 90)
)
insert into public.workflow_states (
  id,
  workspace_id,
  workflow_version_id,
  key,
  canonical_category,
  labels,
  behavior_flags,
  sort_order
)
select
  pg_catalog.md5(
    version_fixture.workspace_id::text || ':inventory.standard:state:' || state_fixture.key
  )::uuid,
  version_fixture.workspace_id,
  version_fixture.workflow_version_id,
  state_fixture.key,
  state_fixture.category,
  pg_catalog.jsonb_build_object(
    'en', state_fixture.label_en,
    'fr', state_fixture.label_fr
  ),
  pg_catalog.jsonb_build_object(
    'publishable', state_fixture.publishable,
    'available', state_fixture.available,
    'terminal', state_fixture.terminal
  ),
  state_fixture.sort_order
from version_fixture
cross join state_fixture
where exists (
  select 1
  from public.workflow_versions version
  where version.workspace_id = version_fixture.workspace_id
    and version.id = version_fixture.workflow_version_id
    and version.status = 'draft'
)
on conflict (workspace_id, workflow_version_id, key) do nothing;

with version_fixture(workspace_id, workflow_version_id) as (
  values
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      '74100000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '20000000-0000-4000-8000-000000000002'::uuid,
      '74100000-0000-4000-8000-000000000002'::uuid
    )
),
transition_fixture(
  key,
  from_state,
  to_state,
  permission_key,
  guard_key,
  reason_required,
  effect_keys
) as (
  values
    ('draft__incomplete', 'draft', 'incomplete', 'inventory.update', null, false, '[]'::jsonb),
    ('draft__in_preparation', 'draft', 'in_preparation', 'inventory.update', 'required_fields_complete', false, '[]'::jsonb),
    ('incomplete__in_preparation', 'incomplete', 'in_preparation', 'inventory.update', 'required_fields_complete', false, '[]'::jsonb),
    ('in_preparation__ready', 'in_preparation', 'ready', 'inventory.update', 'required_fields_complete', false, '["listing.refresh"]'::jsonb),
    ('ready__listed', 'ready', 'listed', 'listings.publish', null, false, '["listing.publish"]'::jsonb),
    ('listed__ready', 'listed', 'ready', 'listings.unpublish', null, false, '["listing.unpublish"]'::jsonb),
    ('ready__pending_sale', 'ready', 'pending_sale', 'deals.update', null, false, '[]'::jsonb),
    ('listed__pending_sale', 'listed', 'pending_sale', 'deals.update', null, false, '["listing.unpublish"]'::jsonb),
    ('pending_sale__ready', 'pending_sale', 'ready', 'deals.update', null, true, '["listing.refresh"]'::jsonb),
    ('pending_sale__sold', 'pending_sale', 'sold', 'deals.close', 'sale_completion_requirements_met', false, '["listing.unpublish","media.retention_review"]'::jsonb),
    ('ready__wholesale', 'ready', 'wholesale', 'deals.close', null, true, '["listing.unpublish","media.retention_review"]'::jsonb),
    ('listed__wholesale', 'listed', 'wholesale', 'deals.close', null, true, '["listing.unpublish","media.retention_review"]'::jsonb),
    ('draft__archived', 'draft', 'archived', 'inventory.archive', null, true, '["media.retention_review"]'::jsonb),
    ('incomplete__archived', 'incomplete', 'archived', 'inventory.archive', null, true, '["media.retention_review"]'::jsonb),
    ('in_preparation__archived', 'in_preparation', 'archived', 'inventory.archive', null, true, '["listing.unpublish","media.retention_review"]'::jsonb),
    ('ready__archived', 'ready', 'archived', 'inventory.archive', null, true, '["listing.unpublish","media.retention_review"]'::jsonb)
)
insert into public.workflow_transitions (
  id,
  workspace_id,
  workflow_version_id,
  key,
  from_state_key,
  to_state_key,
  permission_key,
  guard_key,
  reason_required,
  effect_keys
)
select
  pg_catalog.md5(
    version_fixture.workspace_id::text || ':inventory.standard:transition:'
      || transition_fixture.key
  )::uuid,
  version_fixture.workspace_id,
  version_fixture.workflow_version_id,
  transition_fixture.key,
  transition_fixture.from_state,
  transition_fixture.to_state,
  transition_fixture.permission_key,
  transition_fixture.guard_key,
  transition_fixture.reason_required,
  transition_fixture.effect_keys
from version_fixture
cross join transition_fixture
where exists (
  select 1
  from public.workflow_versions version
  where version.workspace_id = version_fixture.workspace_id
    and version.id = version_fixture.workflow_version_id
    and version.status = 'draft'
)
on conflict (workspace_id, workflow_version_id, key) do nothing;

update public.workflow_versions
set status = 'active',
    activated_at = timestamptz '2026-07-16 16:00:00+00'
where id in (
    '74100000-0000-4000-8000-000000000001',
    '74100000-0000-4000-8000-000000000002'
  )
  and status = 'draft';

-- M3-STARTER-WORKFLOWS-BEGIN
-- VYN-WF-001 / STD-DEAL-001 / M3-WF-AC-001: deterministic starter lead and
-- deal workflows are installed as workspace configuration in both fictional
-- boundaries. Version checksums bind the exact shipped YAML bytes; every
-- state, transition, permission, guard, required-field list, and inert effect
-- is duplicated without a tenant branch.
insert into public.workflow_definitions (
  id,
  workspace_id,
  key,
  entity_type,
  purpose_key,
  status
)
values
  (
    '35010000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'lead_standard',
    'lead',
    'primary',
    'active'
  ),
  (
    '35010000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'lead_standard',
    'lead',
    'primary',
    'active'
  ),
  (
    '35020000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'retail_deal_standard',
    'deal',
    'primary',
    'active'
  ),
  (
    '35020000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'retail_deal_standard',
    'deal',
    'primary',
    'active'
  )
on conflict (id) do nothing;

insert into public.workflow_versions (
  id,
  workspace_id,
  workflow_definition_id,
  version,
  schema_version,
  initial_state_key,
  status,
  checksum,
  source,
  activated_at
)
values
  -- Exact SHA-256 bytes: packs/starter-retail-dealer/workflows/lead.yaml.
  (
    '35110000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '35010000-0000-4000-8000-000000000001',
    '1.0.0',
    1,
    'new',
    'draft',
    'db26b119c9d463594ee3ed4569b3aa647c51a6ed956eb2e7c79244a857c0531b',
    'starter_pack',
    null
  ),
  (
    '35110000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '35010000-0000-4000-8000-000000000002',
    '1.0.0',
    1,
    'new',
    'draft',
    'db26b119c9d463594ee3ed4569b3aa647c51a6ed956eb2e7c79244a857c0531b',
    'starter_pack',
    null
  ),
  -- Exact SHA-256 bytes: packs/starter-retail-dealer/workflows/deal.yaml.
  (
    '35120000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '35020000-0000-4000-8000-000000000001',
    '1.0.0',
    1,
    'draft',
    'draft',
    '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214',
    'starter_pack',
    null
  ),
  (
    '35120000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '35020000-0000-4000-8000-000000000002',
    '1.0.0',
    1,
    'draft',
    'draft',
    '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214',
    'starter_pack',
    null
  )
on conflict (id) do nothing;

with version_fixture(workspace_id, workflow_key, workflow_version_id) as (
  values
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      'lead_standard'::text,
      '35110000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '20000000-0000-4000-8000-000000000002'::uuid,
      'lead_standard'::text,
      '35110000-0000-4000-8000-000000000002'::uuid
    ),
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      'retail_deal_standard'::text,
      '35120000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '20000000-0000-4000-8000-000000000002'::uuid,
      'retail_deal_standard'::text,
      '35120000-0000-4000-8000-000000000002'::uuid
    )
),
state_fixture(
  workflow_key,
  key,
  category,
  label_en,
  label_fr,
  behavior_flags,
  sort_order,
  required_fields
) as (
  values
    ('lead_standard', 'new', 'active', 'New', 'Nouveau', '{"terminal":false}'::jsonb, 10, '{}'::text[]),
    ('lead_standard', 'contacted', 'active', 'Contacted', 'Contacté', '{"terminal":false}'::jsonb, 20, '{}'::text[]),
    ('lead_standard', 'appointment', 'pending', 'Appointment', 'Rendez-vous', '{"terminal":false}'::jsonb, 30, '{}'::text[]),
    ('lead_standard', 'qualified', 'active', 'Qualified', 'Qualifié', '{"terminal":false,"conversion_eligible":true}'::jsonb, 40, '{}'::text[]),
    ('lead_standard', 'converted', 'closed', 'Converted', 'Converti', '{"terminal":true,"conversion_target":true}'::jsonb, 50, '{}'::text[]),
    ('lead_standard', 'lost', 'closed', 'Lost', 'Perdu', '{"terminal":true,"loss_terminal":true}'::jsonb, 60, '{}'::text[]),
    ('retail_deal_standard', 'draft', 'draft', 'Draft', 'Brouillon', '{"terminal":false}'::jsonb, 10, '{}'::text[]),
    ('retail_deal_standard', 'preparing', 'active', 'Preparing', 'En préparation', '{"terminal":false}'::jsonb, 20, '{}'::text[]),
    ('retail_deal_standard', 'awaiting_customer', 'pending', 'Awaiting customer', 'En attente du client', '{"terminal":false}'::jsonb, 30, '{}'::text[]),
    ('retail_deal_standard', 'awaiting_lender', 'pending', 'Awaiting lender', 'En attente du prêteur', '{"terminal":false}'::jsonb, 40, '{}'::text[]),
    ('retail_deal_standard', 'approved', 'active', 'Approved', 'Approuvé', '{"terminal":false}'::jsonb, 50, '{}'::text[]),
    ('retail_deal_standard', 'ready_for_delivery', 'active', 'Ready for delivery', 'Prêt pour la livraison', '{"terminal":false}'::jsonb, 60, '{}'::text[]),
    ('retail_deal_standard', 'completed', 'closed', 'Completed', 'Terminé', '{"terminal":true}'::jsonb, 70, '{}'::text[]),
    ('retail_deal_standard', 'cancelled', 'closed', 'Cancelled', 'Annulé', '{"terminal":true,"cancellation":true}'::jsonb, 80, '{}'::text[])
)
insert into public.workflow_states (
  id,
  workspace_id,
  workflow_version_id,
  key,
  canonical_category,
  labels,
  behavior_flags,
  required_fields,
  sort_order
)
select
  pg_catalog.md5(
    version_fixture.workspace_id::text || ':' || version_fixture.workflow_key
      || ':state:' || state_fixture.key
  )::uuid,
  version_fixture.workspace_id,
  version_fixture.workflow_version_id,
  state_fixture.key,
  state_fixture.category,
  pg_catalog.jsonb_build_object(
    'en', state_fixture.label_en,
    'fr', state_fixture.label_fr
  ),
  state_fixture.behavior_flags,
  state_fixture.required_fields,
  state_fixture.sort_order
from version_fixture
join state_fixture
  on state_fixture.workflow_key = version_fixture.workflow_key
where exists (
  select 1
  from public.workflow_versions version
  where version.workspace_id = version_fixture.workspace_id
    and version.id = version_fixture.workflow_version_id
    and version.status = 'draft'
)
on conflict (workspace_id, workflow_version_id, key) do nothing;

with version_fixture(workspace_id, workflow_key, workflow_version_id) as (
  values
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      'lead_standard'::text,
      '35110000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '20000000-0000-4000-8000-000000000002'::uuid,
      'lead_standard'::text,
      '35110000-0000-4000-8000-000000000002'::uuid
    ),
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      'retail_deal_standard'::text,
      '35120000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '20000000-0000-4000-8000-000000000002'::uuid,
      'retail_deal_standard'::text,
      '35120000-0000-4000-8000-000000000002'::uuid
    )
),
transition_fixture(
  workflow_key,
  key,
  from_state,
  to_state,
  permission_key,
  guard_key,
  reason_required,
  required_fields,
  effect_keys
) as (
  values
    ('lead_standard', 'new__contacted', 'new', 'contacted', 'crm.update', null, false, '{}'::text[], '[]'::jsonb),
    ('lead_standard', 'contacted__appointment', 'contacted', 'appointment', 'crm.update', null, false, '{}'::text[], '[]'::jsonb),
    ('lead_standard', 'contacted__qualified', 'contacted', 'qualified', 'crm.update', null, false, '{}'::text[], '[]'::jsonb),
    ('lead_standard', 'appointment__qualified', 'appointment', 'qualified', 'crm.update', null, false, '{}'::text[], '[]'::jsonb),
    ('lead_standard', 'qualified__converted', 'qualified', 'converted', 'deals.create', null, false, '{}'::text[], '[]'::jsonb),
    ('lead_standard', 'new__lost', 'new', 'lost', 'crm.update', null, true, '{}'::text[], '[]'::jsonb),
    ('lead_standard', 'contacted__lost', 'contacted', 'lost', 'crm.update', null, true, '{}'::text[], '[]'::jsonb),
    ('lead_standard', 'appointment__lost', 'appointment', 'lost', 'crm.update', null, true, '{}'::text[], '[]'::jsonb),
    ('lead_standard', 'qualified__lost', 'qualified', 'lost', 'crm.update', null, true, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'draft__preparing', 'draft', 'preparing', 'deals.update', null, false, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'preparing__awaiting_customer', 'preparing', 'awaiting_customer', 'deals.update', null, false, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'preparing__awaiting_lender', 'preparing', 'awaiting_lender', 'finance_applications.create', null, false, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'awaiting_customer__approved', 'awaiting_customer', 'approved', 'deals.update', null, false, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'awaiting_lender__approved', 'awaiting_lender', 'approved', 'finance_applications.update', 'lender_approval_recorded', false, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'approved__ready_for_delivery', 'approved', 'ready_for_delivery', 'deals.update', 'required_documents_generated', false, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'ready_for_delivery__completed', 'ready_for_delivery', 'completed', 'deals.close', 'completion_requirements_met', false, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'draft__cancelled', 'draft', 'cancelled', 'deals.cancel', null, true, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'preparing__cancelled', 'preparing', 'cancelled', 'deals.cancel', null, true, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'awaiting_customer__cancelled', 'awaiting_customer', 'cancelled', 'deals.cancel', null, true, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'awaiting_lender__cancelled', 'awaiting_lender', 'cancelled', 'deals.cancel', null, true, '{}'::text[], '[]'::jsonb),
    ('retail_deal_standard', 'approved__cancelled', 'approved', 'cancelled', 'deals.cancel', null, true, '{}'::text[], '[]'::jsonb)
)
insert into public.workflow_transitions (
  id,
  workspace_id,
  workflow_version_id,
  key,
  from_state_key,
  to_state_key,
  permission_key,
  guard_key,
  reason_required,
  required_fields,
  effect_keys
)
select
  pg_catalog.md5(
    version_fixture.workspace_id::text || ':' || version_fixture.workflow_key
      || ':transition:' || transition_fixture.key
  )::uuid,
  version_fixture.workspace_id,
  version_fixture.workflow_version_id,
  transition_fixture.key,
  transition_fixture.from_state,
  transition_fixture.to_state,
  transition_fixture.permission_key,
  transition_fixture.guard_key,
  transition_fixture.reason_required,
  transition_fixture.required_fields,
  transition_fixture.effect_keys
from version_fixture
join transition_fixture
  on transition_fixture.workflow_key = version_fixture.workflow_key
where exists (
  select 1
  from public.workflow_versions version
  where version.workspace_id = version_fixture.workspace_id
    and version.id = version_fixture.workflow_version_id
    and version.status = 'draft'
)
on conflict (workspace_id, workflow_version_id, key) do nothing;

update public.workflow_versions
set status = 'active',
    activated_at = timestamptz '2026-07-16 21:00:00+00'
where id in (
    '35110000-0000-4000-8000-000000000001',
    '35110000-0000-4000-8000-000000000002',
    '35120000-0000-4000-8000-000000000001',
    '35120000-0000-4000-8000-000000000002'
  )
  and status = 'draft';
-- M3-STARTER-WORKFLOWS-END

-- M3-STARTER-DEAL-TYPES-BEGIN
-- STD-DEAL-001 / M3-DEAL-AC-001 / T-CFG-002: the five installable starter
-- deal types mirror packs/starter-retail-dealer/deal-types/*.yaml. Definitions
-- and versions are workspace records, not platform branches. Checksums are
-- calculated from the canonical persisted artifact and pinned workflow bytes.
with workspace_fixture(workspace_id) as (
  values
    ('10000000-0000-4000-8000-000000000001'::uuid),
    ('20000000-0000-4000-8000-000000000002'::uuid)
),
deal_type_fixture(key) as (
  values
    ('retail.cash'::text),
    ('retail.third_party_financed'::text),
    ('wholesale.sale'::text),
    ('purchase.vehicle'::text),
    ('acquisition.trade_in'::text)
)
insert into public.deal_type_definitions (
  id,
  workspace_id,
  key,
  status,
  created_by,
  created_at
)
select
  pg_catalog.md5(
    workspace_fixture.workspace_id::text || ':starter-deal-type:'
      || deal_type_fixture.key
  )::uuid,
  workspace_fixture.workspace_id,
  deal_type_fixture.key,
  'active',
  null,
  timestamptz '2026-07-16 21:15:00+00'
from workspace_fixture
cross join deal_type_fixture
on conflict (workspace_id, key) do nothing;

with deal_type_fixture(
  key,
  label_en,
  label_fr,
  field_schema,
  participant_roles,
  inventory_roles,
  option_labels,
  behavior_flags
) as (
  values
    (
      'retail.cash'::text,
      'Cash retail'::text,
      'Vente au détail au comptant'::text,
      '{"required":["buyer_party_id","sold_inventory_unit_id","currency_code"],"optional":["trade_in_owner_party_id","trade_in_inventory_unit_id","authorized_representative_party_id","notes"]}'::jsonb,
      array['buyer','seller','trade_in_owner','authorized_representative']::text[],
      array['sold','trade_in']::text[],
      '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"},"trade_in_owner":{"en":"Trade-in owner","fr":"Propriétaire du véhicule d’échange"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{"deposit":{"en":"Deposit","fr":"Dépôt"},"receipt":{"en":"Receipt","fr":"Encaissement"},"balance_received":{"en":"Balance received","fr":"Solde reçu"},"trade_in_credit":{"en":"Trade-in credit","fr":"Crédit d’échange"}}}'::jsonb,
      '{"inventory_direction":"outbound","inventory_creation":"none","finance_mode":"none","money_mode":"one_time","one_time_event_types":["deposit","receipt","balance_received","trade_in_credit"]}'::jsonb
    ),
    (
      'retail.third_party_financed'::text,
      'Third-party-financed retail'::text,
      'Vente au détail financée par un tiers'::text,
      '{"required":["buyer_party_id","sold_inventory_unit_id","lender_party_id","currency_code"],"optional":["trade_in_owner_party_id","trade_in_inventory_unit_id","authorized_representative_party_id","notes"]}'::jsonb,
      array['buyer','seller','lender','trade_in_owner','authorized_representative']::text[],
      array['sold','trade_in']::text[],
      '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"},"lender":{"en":"Lender","fr":"Prêteur"},"trade_in_owner":{"en":"Trade-in owner","fr":"Propriétaire du véhicule d’échange"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{"deposit":{"en":"Deposit","fr":"Dépôt"},"receipt":{"en":"Receipt","fr":"Encaissement"},"balance_received":{"en":"Balance received","fr":"Solde reçu"},"trade_in_credit":{"en":"Trade-in credit","fr":"Crédit d’échange"},"lender_proceeds":{"en":"Lender proceeds","fr":"Fonds du prêteur"}}}'::jsonb,
      '{"inventory_direction":"outbound","inventory_creation":"none","finance_mode":"external_lender_tracking","money_mode":"one_time","one_time_event_types":["deposit","receipt","balance_received","trade_in_credit","lender_proceeds"]}'::jsonb
    ),
    (
      'wholesale.sale'::text,
      'Wholesale sale'::text,
      'Vente en gros'::text,
      '{"required":["buyer_party_id","wholesale_inventory_unit_id","currency_code"],"optional":["authorized_representative_party_id","notes"]}'::jsonb,
      array['buyer','seller','authorized_representative']::text[],
      array['wholesale']::text[],
      '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"wholesale":{"en":"Wholesale vehicle","fr":"Véhicule de gros"}},"one_time_event_types":{"deposit":{"en":"Deposit","fr":"Dépôt"},"receipt":{"en":"Receipt","fr":"Encaissement"},"balance_received":{"en":"Balance received","fr":"Solde reçu"}}}'::jsonb,
      '{"inventory_direction":"outbound","inventory_creation":"none","finance_mode":"none","money_mode":"one_time","one_time_event_types":["deposit","receipt","balance_received"]}'::jsonb
    ),
    (
      'purchase.vehicle'::text,
      'Vehicle purchase'::text,
      'Achat de véhicule'::text,
      '{"required":["seller_party_id","purchased_inventory_unit_id","currency_code"],"optional":["authorized_representative_party_id","ownership_details","condition","odometer","notes"]}'::jsonb,
      array['seller','dealer_buyer','authorized_representative']::text[],
      array['purchased']::text[],
      '{"participant_roles":{"seller":{"en":"Seller","fr":"Vendeur"},"dealer_buyer":{"en":"Dealer buyer","fr":"Acheteur du concessionnaire"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"purchased":{"en":"Purchased vehicle","fr":"Véhicule acheté"}},"one_time_event_types":{"receipt":{"en":"Receipt","fr":"Encaissement"},"balance_received":{"en":"Balance received","fr":"Solde reçu"}}}'::jsonb,
      '{"inventory_direction":"inbound","inventory_creation":"explicit_confirmation","finance_mode":"none","money_mode":"one_time","one_time_event_types":["receipt","balance_received"]}'::jsonb
    ),
    (
      'acquisition.trade_in'::text,
      'Trade-in acquisition'::text,
      'Acquisition d''un véhicule d''échange'::text,
      '{"required":["trade_in_owner_party_id","trade_in_inventory_unit_id","currency_code"],"optional":["lender_party_id","lien_payoff_minor","lien_payoff_currency","authorized_representative_party_id","ownership_details","condition","odometer","tax_eligibility_inputs","notes"]}'::jsonb,
      array['trade_in_owner','dealer_buyer','lender','authorized_representative']::text[],
      array['trade_in']::text[],
      '{"participant_roles":{"trade_in_owner":{"en":"Trade-in owner","fr":"Propriétaire du véhicule d’échange"},"dealer_buyer":{"en":"Dealer buyer","fr":"Acheteur du concessionnaire"},"lender":{"en":"Lender","fr":"Prêteur"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{"trade_in_credit":{"en":"Trade-in credit","fr":"Crédit d’échange"},"balance_received":{"en":"Balance received","fr":"Solde reçu"}}}'::jsonb,
      '{"inventory_direction":"inbound","inventory_creation":"explicit_confirmation","finance_mode":"none","money_mode":"one_time","one_time_event_types":["trade_in_credit","balance_received"]}'::jsonb
    )
)
insert into public.deal_type_versions (
  id,
  workspace_id,
  deal_type_definition_id,
  version,
  revision,
  schema_version,
  labels,
  option_labels,
  sections,
  field_schema,
  allowed_participant_roles,
  allowed_inventory_roles,
  behavior_flags,
  workflow_version_id,
  status,
  checksum,
  source,
  created_by,
  activated_at,
  retired_at,
  created_at
)
select
  pg_catalog.md5(
    definition.workspace_id::text || ':starter-deal-type:'
      || deal_type_fixture.key || ':1.0.0'
  )::uuid,
  definition.workspace_id,
  definition.id,
  '1.0.0',
  1,
  1,
  pg_catalog.jsonb_build_object(
    'en', deal_type_fixture.label_en,
    'fr', deal_type_fixture.label_fr
  ),
  deal_type_fixture.option_labels,
  '[]'::jsonb,
  deal_type_fixture.field_schema,
  deal_type_fixture.participant_roles,
  deal_type_fixture.inventory_roles,
  deal_type_fixture.behavior_flags,
  workflow_version.id,
  'draft',
  app.deal_type_configuration_checksum(
    deal_type_fixture.key,
    '1.0.0',
    1,
    pg_catalog.jsonb_build_object(
      'en', deal_type_fixture.label_en,
      'fr', deal_type_fixture.label_fr
    ),
    deal_type_fixture.option_labels,
    '[]'::jsonb,
    deal_type_fixture.field_schema,
    deal_type_fixture.participant_roles,
    deal_type_fixture.inventory_roles,
    deal_type_fixture.behavior_flags,
    workflow_definition.key::text,
    workflow_version.version,
    workflow_version.checksum
  ),
  'starter_pack',
  null,
  null,
  null,
  timestamptz '2026-07-16 21:15:00+00'
from public.deal_type_definitions definition
join deal_type_fixture
  on deal_type_fixture.key = definition.key::text
join public.workflow_definitions workflow_definition
  on workflow_definition.workspace_id = definition.workspace_id
 and workflow_definition.key = 'retail_deal_standard'
 and workflow_definition.entity_type = 'deal'
 and workflow_definition.status = 'active'
join public.workflow_versions workflow_version
  on workflow_version.workspace_id = workflow_definition.workspace_id
 and workflow_version.workflow_definition_id = workflow_definition.id
 and workflow_version.version = '1.0.0'
 and workflow_version.status = 'active'
where definition.workspace_id in (
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002'
  )
  and not exists (
    select 1
    from public.deal_type_versions existing_version
    where existing_version.workspace_id = definition.workspace_id
      and existing_version.deal_type_definition_id = definition.id
      and existing_version.version = '1.0.0'
  )
on conflict (workspace_id, deal_type_definition_id, version) do nothing;

update public.deal_type_versions version
set status = 'active',
    activated_at = timestamptz '2026-07-16 21:20:00+00'
from public.deal_type_definitions definition
where definition.workspace_id = version.workspace_id
  and definition.id = version.deal_type_definition_id
  and definition.key::text in (
    'retail.cash',
    'retail.third_party_financed',
    'wholesale.sale',
    'purchase.vehicle',
    'acquisition.trade_in'
  )
  and version.source = 'starter_pack'
  and version.version = '1.0.0'
  and version.status = 'draft';
-- M3-STARTER-DEAL-TYPES-END

-- M2-COST-AC-001: active cost categories are fictional workspace runtime
-- configuration. The same generic keys and localized labels are installed in
-- both synthetic boundaries without creating tenant-specific platform code.
with category_fixture(
  id,
  workspace_id,
  key,
  label_en,
  label_fr
) as (
  values
    (
      'c2100000-0000-4000-8000-000000000001'::uuid,
      '10000000-0000-4000-8000-000000000001'::uuid,
      'acquisition'::text,
      'Acquisition'::text,
      'Acquisition'::text
    ),
    (
      'c2100000-0000-4000-8000-000000000002'::uuid,
      '10000000-0000-4000-8000-000000000001'::uuid,
      'transport'::text,
      'Transport'::text,
      'Transport'::text
    ),
    (
      'c2100000-0000-4000-8000-000000000003'::uuid,
      '10000000-0000-4000-8000-000000000001'::uuid,
      'reconditioning'::text,
      'Reconditioning'::text,
      'Remise en état'::text
    ),
    (
      'c2200000-0000-4000-8000-000000000001'::uuid,
      '20000000-0000-4000-8000-000000000002'::uuid,
      'acquisition'::text,
      'Acquisition'::text,
      'Acquisition'::text
    ),
    (
      'c2200000-0000-4000-8000-000000000002'::uuid,
      '20000000-0000-4000-8000-000000000002'::uuid,
      'transport'::text,
      'Transport'::text,
      'Transport'::text
    ),
    (
      'c2200000-0000-4000-8000-000000000003'::uuid,
      '20000000-0000-4000-8000-000000000002'::uuid,
      'reconditioning'::text,
      'Reconditioning'::text,
      'Remise en état'::text
    )
)
insert into public.inventory_cost_category_definitions (
  id,
  workspace_id,
  key,
  version,
  labels,
  status,
  checksum,
  activated_at
)
select
  category_fixture.id,
  category_fixture.workspace_id,
  category_fixture.key,
  1,
  pg_catalog.jsonb_build_object(
    'en', category_fixture.label_en,
    'fr', category_fixture.label_fr
  ),
  'active',
  pg_catalog.encode(
    extensions.digest(
      'synthetic|inventory_cost_category|'
        || category_fixture.key || '|1|'
        || category_fixture.label_en || '|'
        || category_fixture.label_fr,
      'sha256'
    ),
    'hex'
  ),
  timestamptz '2026-07-16 18:00:00+00'
from category_fixture
on conflict (id) do nothing;

-- M1-VSL-AC-001: tenant-neutral, fictional stock definitions prove that each
-- workspace owns its own immutable numbering state. These are synthetic local
-- fixtures, not a contract formula or a tenant production convention.
insert into public.stock_number_definitions (
  id,
  workspace_id,
  key,
  version,
  prefix,
  numeric_width,
  starting_value,
  increment_by,
  status,
  checksum
)
values
  (
    '71000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'synthetic.default',
    1,
    'N-',
    5,
    1,
    1,
    'active',
    pg_catalog.encode(
      extensions.digest('synthetic.default|1|N-|5|1|1', 'sha256'),
      'hex'
    )
  ),
  (
    '72000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'synthetic.default',
    1,
    'H-',
    5,
    1,
    1,
    'active',
    pg_catalog.encode(
      extensions.digest('synthetic.default|1|H-|5|1|1', 'sha256'),
      'hex'
    )
  )
on conflict (id) do nothing;

-- Local synthetic artifact bucket. Production buckets are provisioned and
-- verified per environment; this bucket is private and browser writes remain
-- prohibited.
insert into storage.buckets (id, name, public, file_size_limit)
values ('document-previews', 'document-previews', false, 10000000)
on conflict (id) do nothing;

insert into public.stock_number_counters (
  workspace_id,
  definition_id,
  next_sequence_value
)
values
  (
    '10000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    1
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '72000000-0000-4000-8000-000000000001',
    1
  )
on conflict (workspace_id, definition_id) do nothing;

-- M1-DOC-AC-001: the only seeded renderer input is explicitly synthetic,
-- watermarked, unnumbered, and incapable of official generation.
insert into public.document_types (
  id,
  workspace_id,
  key,
  version,
  labels,
  field_schema_checksum,
  checksum,
  fixture_evidence,
  display_name,
  field_schema,
  official_generation_enabled,
  status
)
values
  (
    '81000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'synthetic.preview',
    1,
    '{"en":"Synthetic transaction preview","fr":"Aper\u00e7u synth\u00e9tique de transaction"}'::jsonb,
    pg_catalog.encode(
      extensions.digest(
        '{"type":"object","additionalProperties":false,"properties":{},"description":"Synthetic preview fields"}'::jsonb::text,
        'sha256'
      ),
      'hex'
    ),
    pg_catalog.encode(
      extensions.digest(
        pg_catalog.jsonb_build_object(
          'key', 'synthetic.preview',
          'version', 1,
          'fieldSchema',
            '{"type":"object","additionalProperties":false,"properties":{},"description":"Synthetic preview fields"}'::jsonb,
          'productionEnabled', false
        )::text,
        'sha256'
      ),
      'hex'
    ),
    '{"source":"milestone_1_preview_compatibility","productionApproved":false}'::jsonb,
    'Synthetic transaction preview',
    '{"type":"object","additionalProperties":false,"properties":{},"description":"Synthetic preview fields"}'::jsonb,
    false,
    'active'
  ),
  (
    '82000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'synthetic.preview',
    1,
    '{"en":"Synthetic transaction preview","fr":"Aper\u00e7u synth\u00e9tique de transaction"}'::jsonb,
    pg_catalog.encode(
      extensions.digest(
        '{"type":"object","additionalProperties":false,"properties":{},"description":"Synthetic preview fields"}'::jsonb::text,
        'sha256'
      ),
      'hex'
    ),
    pg_catalog.encode(
      extensions.digest(
        pg_catalog.jsonb_build_object(
          'key', 'synthetic.preview',
          'version', 1,
          'fieldSchema',
            '{"type":"object","additionalProperties":false,"properties":{},"description":"Synthetic preview fields"}'::jsonb,
          'productionEnabled', false
        )::text,
        'sha256'
      ),
      'hex'
    ),
    '{"source":"milestone_1_preview_compatibility","productionApproved":false}'::jsonb,
    'Aperçu synthétique de transaction',
    '{"type":"object","additionalProperties":false,"properties":{},"description":"Synthetic preview fields"}'::jsonb,
    false,
    'active'
  )
on conflict (id) do nothing;

with synthetic_template(source_html) as (
  values ($template$
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Vynlo synthetic preview</title>
    <style>
      body { color: #17251f; font: 16px/1.5 system-ui, sans-serif; margin: 48px; }
      .watermark { border: 3px solid #9a432c; color: #9a432c; font-weight: 800; padding: 12px; }
      dl { display: grid; grid-template-columns: 12rem 1fr; gap: 8px; }
    </style>
  </head>
  <body>
    <div class="watermark">{{ watermark }}</div>
    <h1>Synthetic transaction preview</h1>
    <dl>
      <dt>Deal</dt><dd>{{ deal.id }}</dd>
      <dt>Deal type</dt><dd>{{ deal.deal_type_key }}</dd>
      <dt>Currency</dt><dd>{{ deal.currency_code }}</dd>
      <dt>Party</dt><dd>{{ participants[0].display_name }}</dd>
      <dt>Stock</dt><dd>{{ inventory_units[0].stock_number }}</dd>
      <dt>VIN</dt><dd>{{ inventory_units[0].vin }}</dd>
    </dl>
  </body>
</html>
$template$))
insert into public.document_template_versions (
  id,
  workspace_id,
  document_type_id,
  version,
  locale,
  template_class,
  source_html,
  source_checksum,
  source_bundle_checksum,
  renderer_version,
  field_schema,
  field_schema_checksum,
  fixture_evidence,
  production_approved,
  watermark,
  status
)
select
  fixture.id,
  fixture.workspace_id,
  fixture.document_type_id,
  1,
  fixture.locale,
  'synthetic_non_production',
  synthetic_template.source_html,
  pg_catalog.encode(
    extensions.digest(synthetic_template.source_html, 'sha256'),
    'hex'
  ),
  pg_catalog.encode(
    extensions.digest(
      pg_catalog.jsonb_build_object(
        'htmlChecksum', pg_catalog.encode(
          extensions.digest(synthetic_template.source_html, 'sha256'),
          'hex'
        ),
        'css', '',
        'assets', '{}'::jsonb,
        'fonts', '{}'::jsonb
      )::text,
      'sha256'
    ),
    'hex'
  ),
  'synthetic-html-v1',
  '{"type":"object","additionalProperties":false,"properties":{},"description":"Synthetic preview fields"}'::jsonb,
  pg_catalog.encode(
    extensions.digest(
      '{"type":"object","additionalProperties":false,"properties":{},"description":"Synthetic preview fields"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  '{"source":"milestone_1_preview_compatibility","productionApproved":false}'::jsonb,
  false,
  'DRAFT / NON-PRODUCTION',
  'active'
from synthetic_template
cross join (values
  (
    '91000000-0000-4000-8000-000000000001'::uuid,
    '10000000-0000-4000-8000-000000000001'::uuid,
    '81000000-0000-4000-8000-000000000001'::uuid,
    'en-CA'::text
  ),
  (
    '92000000-0000-4000-8000-000000000001'::uuid,
    '20000000-0000-4000-8000-000000000002'::uuid,
    '82000000-0000-4000-8000-000000000001'::uuid,
    'fr-CA'::text
  )
) as fixture(id, workspace_id, document_type_id, locale)
on conflict (id) do nothing;
