-- VYN-INV-001, VYN-WF-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001,
-- VYN-JOB-001, VYN-API-001, T-INV-004, T-TEN-001, T-RBAC-001, T-AUD-001
-- M2-INV-AC-005, M2-INV-AC-006, M2-INV-AC-010, M2-INV-AC-011
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(97);

-- Test-only compatibility grant for the pre-cutover fixture primitive. The
-- transaction rolls it back; production callers use confirmed VIN intake.
grant execute on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) to authenticated;

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  assurance text default 'aal2'
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
          )::bigint
        )
      )
      else pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'method', 'password',
          'timestamp', pg_catalog.floor(
            pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
          )::bigint
        )
      )
    end
  );

  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.inventory_create_results (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean,
  probe text
);
create temporary table pg_temp.inventory_detail_results (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.inventory_transfer_results (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  location_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.inventory_transition_results (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  workflow_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
grant all on
  pg_temp.inventory_create_results,
  pg_temp.inventory_detail_results,
  pg_temp.inventory_transfer_results,
  pg_temp.inventory_transition_results
to authenticated, service_role;

select extensions.results_eq(
  $$
    select key::text
    from public.permissions
    where workspace_id is null
      and key in (
        'inventory.duplicate_override',
        'inventory.facts_override',
        'inventory.read_internal',
        'inventory.update_internal'
      )
    order by key
  $$,
  $$
    values
      ('inventory.duplicate_override'::text),
      ('inventory.facts_override'::text),
      ('inventory.read_internal'::text),
      ('inventory.update_internal'::text)
  $$,
  'M2-INV-AC-010 sensitive and internal inventory permissions are immutable keys'
);

select extensions.has_table('public', 'locations', 'workspace locations exist');
select extensions.has_table(
  'public',
  'workflow_definitions',
  'generic workflow definitions exist'
);
select extensions.has_table('public', 'workflow_versions', 'workflow versions exist');
select extensions.has_table('public', 'workflow_states', 'workflow states exist');
select extensions.has_table(
  'public',
  'workflow_transitions',
  'workflow transitions exist'
);
select extensions.has_table('public', 'workflow_instances', 'workflow instances exist');
select extensions.has_table('public', 'workflow_events', 'workflow event history exists');
select extensions.has_table(
  'public',
  'inventory_unit_internal_details',
  'permission-separated internal inventory details exist'
);
select extensions.has_table(
  'public',
  'inventory_location_events',
  'inventory location event history exists'
);
select extensions.has_table(
  'public',
  'inventory_command_receipts',
  'inventory idempotency receipts exist'
);

select extensions.has_function(
  'app',
  'update_inventory_unit_details',
  array[
    'uuid', 'text', 'uuid', 'bigint', 'text', 'date',
    'timestamp with time zone', 'timestamp with time zone', 'bigint', 'text',
    'bigint', 'bigint', 'text', 'text', 'boolean', 'text', 'text', 'uuid'
  ],
  'detail update command contract exists'
);
select extensions.has_function(
  'app',
  'transfer_inventory_unit_location',
  array['uuid', 'text', 'uuid', 'bigint', 'uuid', 'text', 'text', 'uuid'],
  'location transfer command contract exists'
);
select extensions.has_function(
  'app',
  'transition_inventory_workflow',
  array['uuid', 'text', 'uuid', 'bigint', 'text', 'text', 'text', 'uuid'],
  'workflow transition command contract exists'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 10
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'locations', 'workflow_definitions', 'workflow_versions',
        'workflow_states', 'workflow_transitions', 'workflow_instances',
        'workflow_events', 'inventory_unit_internal_details',
        'inventory_location_events', 'inventory_command_receipts'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'T-TEN-001 every M2 exposed table has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.locations', 'INSERT')
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.workflow_instances', 'UPDATE'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.workflow_events', 'DELETE'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.inventory_location_events', 'INSERT'
    ),
  'T-RBAC-001 browser writes must use canonical inventory commands'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.inventory_command_receipts', 'SELECT'
  ),
  'idempotency receipts are never browser-readable'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.append_inventory_outbox_event(uuid,text,uuid,bigint,jsonb,uuid,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.prevent_inventory_history_mutation()',
      'EXECUTE'
    ),
  'internal trigger and outbox helpers are not browser-callable'
);
select extensions.is(
  (select pg_catalog.count(*) from public.locations where address @> '{"fixture":true}'),
  2::bigint,
  'M2-INV-AC-005 seed provides two deterministic fictional location fixtures'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workflow_states state
    join public.workflow_versions version
      on version.workspace_id = state.workspace_id
     and version.id = state.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key = 'inventory.standard'
  ),
  18::bigint,
  'M2-INV-AC-006 starter workflow has nine localized states per workspace'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workflow_transitions transition
    join public.workflow_versions version
      on version.workspace_id = transition.workspace_id
     and version.id = transition.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key = 'inventory.standard'
  ),
  32::bigint,
  'M2-INV-AC-006 starter workflow has sixteen transitions per workspace'
);
select extensions.ok(
  not exists (
    select 1
    from public.workflow_versions
    where pg_catalog.char_length(version) not between 5 and 64
      or version !~ '^[0-9]+\.[0-9]+\.[0-9]+$'
  ),
  'workflow versions use the bounded semantic-version contract shared with configuration artifacts'
);
select extensions.ok(
  not exists (
    select 1
    from public.workflow_transitions transition
    cross join lateral pg_catalog.jsonb_array_elements_text(
      transition.effect_keys
    ) effect(effect_key)
    where effect.effect_key not in (
      'listing.publish',
      'listing.unpublish',
      'listing.refresh',
      'media.retention_review'
    )
  ),
  'workflow effects are declarative allowlisted keys, never arbitrary code'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_record
    where constraint_record.conrelid = 'public.inventory_units'::pg_catalog.regclass
      and constraint_record.conname = 'inventory_units_available_location_check'
      and constraint_record.contype = 'c'
  ),
  'available inventory requires a workspace-owned location'
);

select extensions.throws_ok(
  $$
    update public.workflow_states
    set labels = '{"en":"Tampered"}'::jsonb
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and workflow_version_id = '74100000-0000-4000-8000-000000000001'
      and key = 'ready'
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'activated workflow states cannot be rewritten'
);
select extensions.throws_ok(
  $$
    insert into public.workflow_states (
      workspace_id, workflow_version_id, key, canonical_category, labels
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '74100000-0000-4000-8000-000000000001',
      'late_state', 'active', '{"en":"Late"}'::jsonb
    )
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'activated workflow versions cannot gain late child configuration'
);

insert into public.workflow_definitions (
  id, workspace_id, key, entity_type, purpose_key, status
) values (
  '74200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'inventory.validation_fixture',
  'inventory_unit',
  'validation',
  'active'
);
select extensions.throws_ok(
  $$
    insert into public.workflow_versions (
      id, workspace_id, workflow_definition_id, version, initial_state_key,
      status, checksum, activated_at
    ) values (
      '74300000-0000-4000-8000-000000000003',
      '10000000-0000-4000-8000-000000000001',
      '74200000-0000-4000-8000-000000000001',
      '3.0.0',
      'draft',
      'active',
      repeat('c', 64),
      pg_catalog.statement_timestamp()
    )
  $$,
  '23514',
  'workflow version must start as a draft',
  'workflow configuration cannot bypass the draft validation lifecycle'
);
insert into public.workflow_versions (
  id, workspace_id, workflow_definition_id, version, initial_state_key,
  status, checksum, source
) values (
  '74300000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  '74200000-0000-4000-8000-000000000001',
  '2.0.0',
  'missing',
  'draft',
  repeat('b', 64),
  'starter_pack'
);
select extensions.throws_ok(
  $$
    update public.workflow_versions
    set status = 'retired',
        activated_at = pg_catalog.statement_timestamp(),
        retired_at = pg_catalog.statement_timestamp()
    where id = '74300000-0000-4000-8000-000000000002'
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'draft workflow versions cannot skip activation and retire directly'
);
select extensions.throws_ok(
  $$
    update public.workflow_versions
    set status = 'active',
        activated_at = pg_catalog.statement_timestamp()
    where id = '74300000-0000-4000-8000-000000000002'
  $$,
  '23514',
  'workflow initial state must exist before version activation',
  'workflow activation fails closed when its declared initial state is absent'
);
insert into public.workflow_versions (
  id, workspace_id, workflow_definition_id, version, initial_state_key,
  status, checksum, source
) values (
  '74300000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '74200000-0000-4000-8000-000000000001',
  '1.0.0',
  'draft',
  'draft',
  repeat('a', 64),
  'starter_pack'
);
insert into public.workflow_states (
  workspace_id, workflow_version_id, key, canonical_category, labels
) values
  (
    '10000000-0000-4000-8000-000000000001',
    '74300000-0000-4000-8000-000000000001',
    'draft', 'draft', '{"en":"Draft"}'::jsonb
  ),
  (
    '10000000-0000-4000-8000-000000000001',
    '74300000-0000-4000-8000-000000000001',
    'ready', 'active', '{"en":"Ready"}'::jsonb
  );
select extensions.throws_ok(
  $$
    insert into public.workflow_transitions (
      workspace_id, workflow_version_id, key, from_state_key, to_state_key,
      permission_key, effect_keys
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '74300000-0000-4000-8000-000000000001',
      'draft__ready', 'draft', 'ready', 'inventory.update',
      '["shell.execute"]'::jsonb
    )
  $$,
  '23514',
  'workflow transition effect is not allowlisted for entity',
  'tenant workflow configuration cannot execute arbitrary effects'
);
select extensions.lives_ok(
  $$
    update public.workflow_versions
    set status = 'active',
        activated_at = pg_catalog.statement_timestamp()
    where id = '74300000-0000-4000-8000-000000000001'
  $$,
  'a valid draft workflow version can activate after its children are installed'
);
select extensions.throws_ok(
  $$
    update public.workflow_versions
    set status = 'draft',
        activated_at = null
    where id = '74300000-0000-4000-8000-000000000001'
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'an active workflow version cannot return to draft'
);
select extensions.lives_ok(
  $$
    update public.workflow_versions
    set status = 'retired',
        retired_at = pg_catalog.statement_timestamp()
    where id = '74300000-0000-4000-8000-000000000001'
  $$,
  'an active workflow version can retire without rewriting its definition'
);
select extensions.throws_ok(
  $$
    update public.workflow_versions
    set status = 'active',
        retired_at = null
    where id = '74300000-0000-4000-8000-000000000001'
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'a retired workflow version cannot be reactivated'
);
select extensions.throws_ok(
  $$
    update public.workflow_versions
    set checksum = repeat('d', 64)
    where id = '74300000-0000-4000-8000-000000000001'
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'retired workflow configuration remains immutable'
);
select extensions.throws_ok(
  $$
    insert into public.role_permissions (
      workspace_id, role_id, permission_id, status
    )
    select
      '10000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000002',
      permission.id,
      'active'
    from public.permissions permission
    where permission.workspace_id is null
      and permission.key = 'inventory.facts_override'
  $$,
  '23514',
  'sensitive inventory override permissions require an MFA role',
  'M2-INV-AC-010 sensitive overrides cannot be granted to a non-MFA role'
);
insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  '53000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture_sensitive_inventory',
  'Fixture sensitive inventory role',
  'system',
  'active',
  true
);
select extensions.lives_ok(
  $$
    insert into public.role_permissions (
      workspace_id, role_id, permission_id, status
    )
    select
      '10000000-0000-4000-8000-000000000001',
      '53000000-0000-4000-8000-000000000001',
      permission.id,
      'active'
    from public.permissions permission
    where permission.workspace_id is null
      and permission.key = 'inventory.facts_override'
  $$,
  'a role requiring MFA can receive a sensitive inventory override permission'
);
select extensions.throws_ok(
  $$
    update public.roles
    set requires_mfa = false
    where id = '53000000-0000-4000-8000-000000000001'
  $$,
  '23514',
  'MFA cannot be disabled while a role has sensitive inventory permissions',
  'MFA cannot be downgraded after a sensitive inventory grant'
);
select extensions.lives_ok(
  $$
    update public.permissions
    set status = 'retired'
    where workspace_id is null
      and key = 'inventory.duplicate_override'
  $$,
  'a sensitive permission may be retired without rewriting its key'
);
select extensions.lives_ok(
  $$
    insert into public.role_permissions (
      workspace_id, role_id, permission_id, status
    )
    select
      '10000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000002',
      permission.id,
      'active'
    from public.permissions permission
    where permission.workspace_id is null
      and permission.key = 'inventory.duplicate_override'
  $$,
  'a retired permission grant remains ineffective until reviewed activation'
);
select extensions.throws_ok(
  $$
    update public.permissions
    set status = 'active'
    where workspace_id is null
      and key = 'inventory.duplicate_override'
  $$,
  '23514',
  'sensitive inventory permissions cannot activate for a role without MFA',
  'permission reactivation rechecks every sensitive inventory role grant'
);

insert into public.locations (
  id, workspace_id, key, name, status, locale, timezone, address, contact
) values (
  '73000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  'synthetic.secondary',
  'Northstar Secondary Synthetic Location',
  'active',
  'en-CA',
  'America/Toronto',
  '{"fixture":true}'::jsonb,
  '{}'::jsonb
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;

select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_create_results
    select result.*, 'initial'
    from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'm2-inventory-create-001',
      '1HGCM82633A700001',
      2024,
      'Synthetic',
      'Roadster',
      date '2026-07-01',
      12000,
      'km',
      'CAD',
      2500000,
      'Initial synthetic note',
      'request-m2-create-001',
      'a7000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'M1 create command remains compatible after the M2 migration'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    where unit.id = (
      select inventory_unit_id
      from pg_temp.inventory_create_results
      where probe = 'initial'
    )
      and unit.status = 'active'
      and unit.workflow_state_key = 'in_preparation'
      and unit.workflow_instance_id is not null
      and unit.version = 1
  ),
  'M2-INV-AC-006 legacy creation auto-attaches the active configured workflow'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.workflow_instances instance
      on instance.workspace_id = unit.workspace_id
     and instance.id = unit.workflow_instance_id
    where unit.id = (
      select inventory_unit_id
      from pg_temp.inventory_create_results
      where probe = 'initial'
    )
      and instance.entity_type = 'inventory_unit'
      and instance.current_state_key = unit.workflow_state_key
      and instance.canonical_status = unit.status
      and instance.version = unit.version
  ),
  'workflow instance and inventory aggregate start in synchronized state'
);
reset role;
select extensions.throws_ok(
  $$
    update public.inventory_units
    set version = version + 1
    where id = (
      select inventory_unit_id
      from pg_temp.inventory_create_results
      where probe = 'initial'
    )
  $$,
  '23514',
  'inventory workflow link must match the workspace-owned aggregate state',
  'the immediate projection trigger rejects an unsynchronized aggregate version'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
select extensions.throws_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-aal1-denied',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      1, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      null, 12345, 'km', 2550000,
      2400000, 'CAD', 'Updated public note', true, 'Restricted synthetic note',
      'request-m2-details-aal1', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and inventory permission are required',
  'MFA-required administrator role fails closed at AAL1'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal2');
select extensions.throws_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-limited-denied',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      1, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      timestamptz '2026-07-02 10:00:00+00', 12345, 'km', 2550000,
      2400000, 'CAD', 'Updated public note', false, null,
      'request-m2-details-limited', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and inventory permission are required',
  'T-RBAC-001 missing inventory.update permission denies details command'
);
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001', 'aal2');
select extensions.throws_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-cross-denied',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      1, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      timestamptz '2026-07-02 10:00:00+00', 12345, 'km', 2550000,
      2400000, 'CAD', 'Updated public note', false, null,
      'request-m2-details-cross', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and inventory permission are required',
  'T-TEN-001 another workspace administrator cannot mutate Northstar inventory'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_detail_results
    select result.*, 'initial'
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-command-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      1,
      'used',
      date '2026-07-01',
      timestamptz '2026-07-01 10:00:00+00',
      null,
      12345,
      'km',
      2550000,
      2400000,
      'CAD',
      'Updated public note',
      true,
      'Restricted synthetic note',
      'request-m2-details-001',
      'a7100000-0000-4000-8000-000000000001'
    ) result
  $$,
  'M2-INV-AC-005 updates normalized inventory detail through one command'
);
select extensions.results_eq(
  $$
    select aggregate_version, canonical_status, state_key, replayed
    from pg_temp.inventory_detail_results
    where probe = 'initial'
  $$,
  $$values (2::bigint, 'active'::text, 'in_preparation'::text, false)$$,
  'detail command returns the synchronized aggregate version and workflow projection'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.workflow_instances instance
      on instance.workspace_id = unit.workspace_id
     and instance.id = unit.workflow_instance_id
    where unit.id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
      and instance.lifecycle_status = 'active'
      and instance.current_state_key = unit.workflow_state_key
      and instance.canonical_status = unit.status
      and instance.version = unit.version
      and unit.version = 2
  ),
  'detail command advances the locked active workflow instance before inventory validation'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    where unit.id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
      and unit.condition_key = 'used'
      and unit.acquisition_date = date '2026-07-01'
      and unit.acquired_at = timestamptz '2026-07-01 10:00:00+00'
      and unit.available_at is null
      and unit.odometer_value = 12345
      and unit.odometer_unit = 'km'
      and unit.advertised_price_minor = 2550000
      and unit.expected_sale_price_minor = 2400000
      and unit.expected_sale_price_currency_code = 'CAD'
      and unit.public_notes = 'Updated public note'
      and unit.version = 2
  ),
  'detail command persists exact money, condition, odometer, and lifecycle values'
);
select extensions.is(
  (
    select internal_notes
    from public.inventory_unit_internal_details
    where inventory_unit_id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
  ),
  'Restricted synthetic note'::text,
  'internal notes remain in the separately permissioned relation'
);
select extensions.ok(
  (
    select audit.after_data::text not like '%Restricted synthetic note%'
      and audit.before_data::text not like '%Restricted synthetic note%'
      and audit.metadata ->> 'internal_values_redacted' = 'true'
    from public.audit_events audit
    where audit.id = (
      select audit_event_id from pg_temp.inventory_detail_results where probe = 'initial'
    )
  ),
  'T-AUD-001 audit records changed keys but redact internal values'
);
reset role;
select extensions.ok(
  (
    select event.payload::text not like '%Restricted synthetic note%'
      and event.event_name = 'inventory_unit.updated'
      and event.aggregate_version = 2
    from public.outbox_events event
    where event.id = (
      select outbox_event_id from pg_temp.inventory_detail_results where probe = 'initial'
    )
  ),
  'T-JOB-001 transactional outbox carries redacted versioned update metadata'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_command_receipts receipt
    where receipt.command_type = 'update_inventory_unit_details'
      and receipt.idempotency_key = 'm2-details-command-001'
      and receipt.result::text not like '%Restricted synthetic note%'
  ),
  'idempotency receipt stores only canonical result identifiers and state'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_detail_results
    select result.*, 'replay'
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-command-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      1, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      null, 12345, 'km', 2550000,
      2400000, 'CAD', 'Updated public note', true, 'Restricted synthetic note',
      'request-m2-details-replay', pg_catalog.gen_random_uuid()
    ) result
  $$,
  'exact detail-command replay succeeds'
);
select extensions.ok(
  (
    select replay.inventory_unit_id = initial.inventory_unit_id
      and replay.aggregate_version = initial.aggregate_version
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
      and replay.replayed
    from pg_temp.inventory_detail_results initial
    cross join pg_temp.inventory_detail_results replay
    where initial.probe = 'initial' and replay.probe = 'replay'
  ),
  'M2-INV-AC-011 detail replay returns the original entity, version, audit, and outbox IDs'
);
select extensions.throws_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-command-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      1, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      null, 12345, 'km', 2550000,
      2400000, 'CAD', 'Different public note', true, 'Restricted synthetic note',
      'request-m2-details-conflict', pg_catalog.gen_random_uuid()
    )
  $$,
  '23505',
  'inventory idempotency key was used for a different details command',
  'M2-INV-AC-011 reused detail idempotency key rejects a different fingerprint'
);
select extensions.throws_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-stale-version',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      1, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      null, 12345, 'km', 2550000,
      2400000, 'CAD', 'Stale change', false, null,
      'request-m2-details-stale', pg_catalog.gen_random_uuid()
    )
  $$,
  '40001',
  'inventory version conflict',
  'M2-INV-AC-011 stale aggregate version fails closed'
);
select extensions.throws_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-hidden-flag',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      2, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      null, 12345, 'km', 2550000,
      2400000, 'CAD', 'Updated public note', false, 'Implicit hidden change',
      'request-m2-details-hidden-flag', pg_catalog.gen_random_uuid()
    )
  $$,
  '22023',
  'internal notes require the explicit update presence flag',
  'internal-note writes require an explicit presence flag'
);

reset role;
select extensions.lives_ok(
  $$
    insert into public.role_permissions (
      workspace_id, role_id, permission_id, status
    )
    select
      '10000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000002',
      permission.id,
      'active'
    from public.permissions permission
    where permission.workspace_id is null
      and permission.key = 'inventory.update'
  $$,
  'non-MFA limited role may receive the non-sensitive inventory.update permission'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal2');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_detail_results
    select result.*, 'limited-public'
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-limited-public',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      2, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      null, 12345, 'km', 2550000,
      2400000, 'CAD', 'Limited public-only update', false, null,
      'request-m2-details-limited-public',
      'a7100000-0000-4000-8000-000000000002'
    ) result
  $$,
  'public-only update does not require reading or authorizing hidden notes'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.inventory_unit_internal_details
    where inventory_unit_id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
  ),
  0::bigint,
  'T-RBAC-001 user without inventory.read_internal cannot disclose hidden details'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
select extensions.is(
  (
    select internal_notes
    from public.inventory_unit_internal_details
    where inventory_unit_id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
  ),
  'Restricted synthetic note'::text,
  'public-only update preserves the hidden note without coupling'
);
select extensions.throws_ok(
  $$
    select *
    from app.transfer_inventory_unit_location(
      '10000000-0000-4000-8000-000000000001',
      'm2-transfer-cross-workspace',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      3,
      '73000000-0000-4000-8000-000000000002',
      'Cross-workspace destination probe',
      'request-m2-transfer-cross',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'destination location is unavailable',
  'T-TEN-001 cross-workspace destination fails without disclosure'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_transfer_results
    select result.*, 'initial'
    from app.transfer_inventory_unit_location(
      '10000000-0000-4000-8000-000000000001',
      'm2-transfer-command-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      3,
      '73000000-0000-4000-8000-000000000003',
      'Synthetic location transfer',
      'request-m2-transfer-001',
      'a7200000-0000-4000-8000-000000000001'
    ) result
  $$,
  'M2-INV-AC-005 transfers an inventory unit through the canonical command'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.inventory_location_events event
      on event.workspace_id = unit.workspace_id
     and event.inventory_unit_id = unit.id
    where unit.id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
      and unit.location_id = '73000000-0000-4000-8000-000000000003'
      and unit.version = 4
      and event.id = (
        select location_event_id from pg_temp.inventory_transfer_results where probe = 'initial'
      )
      and event.from_location_id is null
      and event.to_location_id = unit.location_id
      and event.aggregate_version = unit.version
  ),
  'location projection and append-only transfer event commit at one aggregate version'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.workflow_instances instance
      on instance.workspace_id = unit.workspace_id
     and instance.id = unit.workflow_instance_id
    where unit.id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
      and instance.lifecycle_status = 'active'
      and instance.current_state_key = unit.workflow_state_key
      and instance.canonical_status = unit.status
      and instance.version = unit.version
      and unit.version = 4
  ),
  'location transfer advances the locked active workflow instance before inventory validation'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.inventory_transfer_results result
    join public.audit_events audit on audit.id = result.audit_event_id
    join public.outbox_events event on event.id = result.outbox_event_id
    where result.probe = 'initial'
      and audit.action = 'inventory_unit.location_transferred'
      and event.event_name = 'inventory_unit.location_transferred'
      and event.aggregate_version = result.aggregate_version
  ),
  'T-AUD-001 transfer commits its event, audit, and outbox records transactionally'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_transfer_results
    select result.*, 'replay'
    from app.transfer_inventory_unit_location(
      '10000000-0000-4000-8000-000000000001',
      'm2-transfer-command-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      3,
      '73000000-0000-4000-8000-000000000003',
      'Synthetic location transfer',
      'request-m2-transfer-replay',
      pg_catalog.gen_random_uuid()
    ) result
  $$,
  'exact location-transfer replay succeeds'
);
select extensions.ok(
  (
    select replay.aggregate_version = initial.aggregate_version
      and replay.location_event_id = initial.location_event_id
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
      and replay.replayed
    from pg_temp.inventory_transfer_results initial
    cross join pg_temp.inventory_transfer_results replay
    where initial.probe = 'initial' and replay.probe = 'replay'
  ),
  'M2-INV-AC-011 transfer replay returns original event identifiers'
);
select extensions.throws_ok(
  $$
    select *
    from app.transfer_inventory_unit_location(
      '10000000-0000-4000-8000-000000000001',
      'm2-transfer-same-location',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      4,
      '73000000-0000-4000-8000-000000000003',
      'No-op transfer probe',
      'request-m2-transfer-same',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'inventory is already at that location',
  'no-op transfer fails without writing history'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal2');
select extensions.throws_ok(
  $$
    select *
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-limited-denied',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      4, 'in_preparation__ready', null, 'request-m2-transition-limited',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and inventory permission are required',
  'T-RBAC-001 inventory.update alone cannot authorize workflow transition'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_transition_results
    select result.*, 'ready-initial'
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-ready-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      4, 'in_preparation__ready', null, 'request-m2-transition-ready',
      'a7300000-0000-4000-8000-000000000001'
    ) result
  $$,
  'M2-INV-AC-006 executes an allowlisted configured workflow transition'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.workflow_instances instance
      on instance.workspace_id = unit.workspace_id
     and instance.id = unit.workflow_instance_id
    where unit.id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
      and unit.status = 'active'
      and unit.workflow_state_key = 'ready'
      and unit.version = 5
      and instance.current_state_key = unit.workflow_state_key
      and instance.canonical_status = unit.status
      and instance.version = unit.version
  ),
  'transition synchronizes instance state, canonical status, and aggregate version'
);
reset role;
select extensions.ok(
  exists (
    select 1
    from pg_temp.inventory_transition_results result
    join public.workflow_events workflow_event
      on workflow_event.id = result.workflow_event_id
     and workflow_event.workspace_id = '10000000-0000-4000-8000-000000000001'
    join public.audit_events audit
      on audit.id = result.audit_event_id
     and audit.workspace_id = workflow_event.workspace_id
    join public.outbox_events outbox
      on outbox.id = result.outbox_event_id
     and outbox.workspace_id = workflow_event.workspace_id
    where result.probe = 'ready-initial'
      and workflow_event.aggregate_version = result.aggregate_version
      and audit.action = 'inventory_unit.transitioned'
      and audit.metadata ->> 'workflow_event_id' = result.workflow_event_id::text
      and outbox.event_name = 'inventory_unit.transitioned'
      and outbox.aggregate_version = result.aggregate_version
      and outbox.payload ->> 'toStateKey' = result.state_key
  ),
  'T-AUD-001 transition commits workflow, audit, and outbox evidence at one version'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_transition_results
    select result.*, 'ready-replay'
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-ready-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      4, 'in_preparation__ready', null, 'request-m2-transition-ready-replay',
      pg_catalog.gen_random_uuid()
    ) result
  $$,
  'exact workflow-transition replay succeeds'
);
select extensions.ok(
  (
    select replay.aggregate_version = initial.aggregate_version
      and replay.workflow_event_id = initial.workflow_event_id
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
      and replay.replayed
    from pg_temp.inventory_transition_results initial
    cross join pg_temp.inventory_transition_results replay
    where initial.probe = 'ready-initial' and replay.probe = 'ready-replay'
  ),
  'M2-INV-AC-011 transition replay returns original event identifiers'
);
select extensions.throws_ok(
  $$
    select *
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-stale-version',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      4, 'ready__listed', null, 'request-m2-transition-stale',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '40001',
  'inventory version conflict',
  'workflow transition rejects a stale aggregate version'
);
select extensions.throws_ok(
  $$
    select *
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-invalid-from',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      5, 'in_preparation__ready', null, 'request-m2-transition-invalid-from',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'workflow transition is not allowed',
  'transition key must be valid from the current immutable state'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_transition_results
    select result.*, 'listed'
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-listed-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      5, 'ready__listed', null, 'request-m2-transition-listed',
      'a7300000-0000-4000-8000-000000000002'
    ) result
  $$,
  'configured listing transition succeeds with its immutable permission key'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_transition_results
    select result.*, 'pending'
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-pending-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      6, 'listed__pending_sale', null, 'request-m2-transition-pending',
      'a7300000-0000-4000-8000-000000000003'
    ) result
  $$,
  'pending-sale transition changes the canonical status to pending'
);
select extensions.throws_ok(
  $$
    select *
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-return-no-reason',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      7, 'pending_sale__ready', null, 'request-m2-transition-return-no-reason',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'workflow transition reason is required',
  'configured reason-required transition fails closed without a reason'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_transition_results
    select result.*, 'returned-ready'
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-return-ready',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      7, 'pending_sale__ready', 'Synthetic deal cancelled',
      'request-m2-transition-return-ready',
      'a7300000-0000-4000-8000-000000000004'
    ) result
  $$,
  'reason-required transition persists its operational explanation'
);
select extensions.throws_ok(
  $$
    select *
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-archive-no-reason',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      8, 'ready__archived', null, 'request-m2-transition-archive-no-reason',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'workflow transition reason is required',
  'archive transition requires a reason'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_transition_results
    select result.*, 'archived'
    from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'm2-transition-archive-001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      8, 'ready__archived', 'Synthetic archive decision',
      'request-m2-transition-archive',
      'a7300000-0000-4000-8000-000000000005'
    ) result
  $$,
  'terminal workflow transition succeeds through configured archive permission'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.workflow_instances instance
      on instance.workspace_id = unit.workspace_id
     and instance.id = unit.workflow_instance_id
    where unit.id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
      and unit.status = 'archived'
      and unit.workflow_state_key = 'archived'
      and unit.version = 9
      and unit.closed_at is not null
      and instance.lifecycle_status = 'completed'
      and instance.completed_at is not null
      and instance.version = unit.version
  ),
  'terminal state closes both inventory and workflow lifecycle projections'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workflow_events
    where entity_id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
  ),
  5::bigint,
  'each committed transition appends exactly one workflow event and replays append none'
);
select extensions.throws_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-details-terminal-denied',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      9, 'used', date '2026-07-01', timestamptz '2026-07-01 10:00:00+00',
      timestamptz '2026-07-02 10:00:00+00', 12345, 'km', 2550000,
      2400000, 'CAD', 'Terminal mutation', false, null,
      'request-m2-details-terminal', pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'closed inventory details are immutable',
  'terminal inventory detail mutation fails closed'
);
select extensions.throws_ok(
  $$
    select *
    from app.transfer_inventory_unit_location(
      '10000000-0000-4000-8000-000000000001',
      'm2-transfer-terminal-denied',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      9,
      '73000000-0000-4000-8000-000000000001',
      'Terminal transfer probe',
      'request-m2-transfer-terminal',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'closed inventory cannot transfer location',
  'terminal inventory location transfer fails closed'
);
select extensions.throws_ok(
  $$
    update public.inventory_location_events
    set reason = 'Browser tamper'
    where inventory_unit_id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
  $$,
  '42501',
  'permission denied for table inventory_location_events',
  'browser cannot directly mutate append-only inventory history'
);

reset role;
select extensions.throws_ok(
  $$
    update public.inventory_location_events
    set reason = 'Trusted tamper'
    where inventory_unit_id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
  $$,
  '55000',
  'inventory and workflow history is append-only',
  'even trusted roles cannot rewrite location history'
);
select extensions.throws_ok(
  $$
    delete from public.workflow_events
    where entity_id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
  $$,
  '55000',
  'inventory and workflow history is append-only',
  'even trusted roles cannot delete workflow history'
);
select extensions.throws_ok(
  $$
    update public.inventory_command_receipts
    set result = '{}'::jsonb
    where inventory_unit_id = (
      select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'
    )
  $$,
  '55000',
  'inventory and workflow history is append-only',
  'idempotency receipts are append-only for trusted roles too'
);
select extensions.throws_ok(
  $$
    insert into public.inventory_location_events (
      workspace_id, inventory_unit_id, to_location_id, aggregate_version,
      reason, actor_user_id, correlation_id
    ) values (
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.inventory_create_results where probe = 'initial'),
      '73000000-0000-4000-8000-000000000002',
      10,
      'Cross-workspace composite-key probe',
      '31000000-0000-4000-8000-000000000001',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '23503',
  'insert or update on table "inventory_location_events" violates foreign key constraint "inventory_location_events_workspace_id_to_location_id_fkey"',
  'T-TEN-001 composite key prevents cross-workspace history linkage'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select extensions.ok(
  (
    select pg_catalog.count(*)
    from public.workflow_events
    where workspace_id = '10000000-0000-4000-8000-000000000001'
  ) = 0
    and (
      select pg_catalog.count(*)
      from public.inventory_location_events
      where workspace_id = '10000000-0000-4000-8000-000000000001'
    ) = 0,
  'T-TEN-001 Harbour actor cannot select Northstar inventory history'
);

select * from extensions.finish();
rollback;
