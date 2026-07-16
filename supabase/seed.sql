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
    'Synthetic transaction preview',
    '{"type":"object","additionalProperties":false,"synthetic":true}'::jsonb,
    false,
    'active'
  ),
  (
    '82000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'synthetic.preview',
    1,
    'Aperçu synthétique de transaction',
    '{"type":"object","additionalProperties":false,"synthetic":true}'::jsonb,
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
  renderer_version,
  field_schema,
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
  'synthetic-html-v1',
  '{"type":"object","additionalProperties":false,"synthetic":true}'::jsonb,
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
