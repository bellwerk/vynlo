-- VYN-INV-001, VYN-COST-001, VYN-SEARCH-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001, T-INV-004, T-COST-001, T-SEARCH-001,
-- T-TEN-001, T-RBAC-001, T-AUD-001, M2-INV-AC-005 through M2-INV-AC-011.
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(64);

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
            pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
          )::bigint
        )
      )
      else pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'method', 'password',
          'timestamp', pg_catalog.floor(
            pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
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

create temporary table pg_temp.operations_inventory_result (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean
);
create temporary table pg_temp.operations_cost_result (
  cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.operations_saved_view_result (
  saved_view_id uuid,
  saved_view_version bigint,
  replayed boolean,
  audit_event_id uuid,
  probe text
);
create temporary table pg_temp.operations_facts_result (
  vehicle_id uuid,
  facts_version bigint,
  history_id uuid,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);

grant all on
  pg_temp.operations_inventory_result,
  pg_temp.operations_cost_result,
  pg_temp.operations_saved_view_result,
  pg_temp.operations_facts_result
to authenticated, service_role;

-- A read-only inventory operator proves masked fields independently from the
-- all-permission administrator and the workspace-only fixture role.
insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  '51000000-0000-4000-8000-000000000016',
  '10000000-0000-4000-8000-000000000001',
  'fixture_inventory_reader',
  'Fixture inventory reader',
  'system',
  'active',
  false
);
insert into public.role_permissions (
  workspace_id, role_id, permission_id, status
)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000016',
  permission.id,
  'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key = 'inventory.read';
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '61000000-0000-4000-8000-000000000016',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '51000000-0000-4000-8000-000000000016',
  'active'
);

insert into public.locations (
  id, workspace_id, key, name, status, address, contact
) values (
  '73000000-0000-4000-8000-000000000016',
  '10000000-0000-4000-8000-000000000001',
  'synthetic.inactive',
  'Inactive synthetic location',
  'inactive',
  '{}'::jsonb,
  '{}'::jsonb
);

select extensions.has_table(
  'public', 'vehicle_facts_override_history',
  'controlled fact changes have immutable history storage'
);
select extensions.has_table(
  'public', 'vehicle_facts_override_command_receipts',
  'controlled fact changes have actor-scoped idempotency receipts'
);
select extensions.has_function(
  'app', 'get_inventory_unit_operations', array['uuid', 'uuid'],
  'exact inventory operator read contract exists'
);
select extensions.has_function(
  'app', 'list_active_inventory_locations', array['uuid'],
  'exact active-location read contract exists'
);
select extensions.has_function(
  'app', 'get_inventory_unit_costs',
  array['uuid', 'uuid', 'timestamp with time zone', 'uuid', 'integer'],
  'bounded exact cost-ledger read contract exists'
);
select extensions.has_function(
  'app', 'list_inventory_saved_views', array['uuid', 'boolean'],
  'permission-scoped reusable saved-view read contract exists'
);
select extensions.has_function(
  'app', 'archive_inventory_saved_view',
  array['uuid', 'text', 'uuid', 'bigint', 'text', 'uuid'],
  'optimistic saved-view archive command exists'
);
select extensions.has_function(
  'app', 'override_vehicle_facts',
  array[
    'uuid', 'text', 'uuid', 'bigint', 'integer', 'text', 'text', 'text',
    'integer', 'text', 'text', 'text', 'integer', 'text', 'text', 'text',
    'text', 'uuid'
  ],
  'full reasoned vehicle-facts replacement command exists'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'vehicle_facts_override_history'
  ),
  'fact correction history has forced RLS'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'vehicle_facts_override_command_receipts'
  ),
  'fact correction receipts have forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'anon', 'public.vehicle_facts_override_history', 'select'
  ),
  'anonymous clients cannot read fact correction history'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'anon', 'public.vehicle_facts_override_command_receipts', 'select'
  ),
  'anonymous clients cannot read fact correction receipts'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

select extensions.lives_ok(
  $$
    insert into pg_temp.operations_inventory_result
    select result.*
    from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'm2-operations-create-001',
      '1HGCM82633A700016',
      2025,
      'Synthetic',
      'Operator',
      date '2026-07-01',
      42000,
      'km',
      'CAD',
      2750000,
      'Synthetic operator fixture',
      'request-m2-operations-create',
      'a7160000-0000-4000-8000-000000000001'
    ) result
  $$,
  'operator fixture inventory is created through the canonical command'
);
select extensions.lives_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'm2-operations-details-001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      1,
      'used.ready',
      date '2026-07-01',
      timestamptz '2026-07-01 10:00:00+00',
      null,
      42000,
      'km',
      2750000,
      2900000,
      'CAD',
      'Synthetic operator fixture',
      true,
      'Restricted synthetic operating note',
      'request-m2-operations-details',
      'a7160000-0000-4000-8000-000000000002'
    )
  $$,
  'restricted internal detail is written through its permission boundary'
);
select extensions.lives_ok(
  $$
    select *
    from app.transfer_inventory_unit_location(
      '10000000-0000-4000-8000-000000000001',
      'm2-operations-location-001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      2,
      '73000000-0000-4000-8000-000000000001',
      'Moved into the synthetic showroom',
      'request-m2-operations-location',
      'a7160000-0000-4000-8000-000000000003'
    )
  $$,
  'location is changed through the versioned transfer command'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.operations_cost_result
    select result.*
    from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-operations-cost-001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      3,
      'c2100000-0000-4000-8000-000000000003',
      10000,
      'CAD',
      date '2026-07-16',
      null,
      'Synthetic reconditioning',
      null,
      'request-m2-operations-cost',
      'a7160000-0000-4000-8000-000000000004'
    ) result
  $$,
  'exact minor-unit fixture cost is posted through the ledger command'
);

select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  ),
  1,
  'operator detail returns exactly one workspace-owned aggregate'
);
select extensions.ok(
  (
    select can_transfer_location
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  ),
  'inventory.update grants the same location-transfer capability enforced by the command'
);
select extensions.is(
  (
    select internal_notes
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  ),
  'Restricted synthetic operating note'::text,
  'authorized internal readers receive the restricted note'
);
select extensions.results_eq(
  $$
    select posted_cost_minor, estimated_gross_minor
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  $$,
  $$values ('10000'::text, '2890000'::text)$$,
  'authorized cost readers receive exact string minor-unit metrics'
);
select extensions.ok(
  (
    select pg_catalog.jsonb_array_length(allowed_transitions) > 0
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  ),
  'operator detail exposes only currently executable configured transitions'
);
select extensions.ok(
  (
    select aggregate_version = workflow_instance_version
      and workflow_configuration_version = '1.0.0'
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  ),
  'inventory and workflow versions remain synchronized in the read model'
);
select extensions.results_eq(
  $$
    select location_id, location_key, name
    from app.list_active_inventory_locations(
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  $$
    values (
      '73000000-0000-4000-8000-000000000001'::uuid,
      'synthetic.primary'::text,
      'Northstar Synthetic Location'::text
    )
  $$,
  'active-location choices exclude inactive and foreign-workspace records'
);
select extensions.throws_ok(
  $$
    select *
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000016'
    )
  $$,
  'P0002',
  'inventory unit was not found',
  'missing inventory detail maps to an exact not-found contract'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.lives_ok(
  $$
    select *
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  $$,
  'read-only inventory operator can load the public dossier'
);
select extensions.is(
  (
    select internal_notes
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  ),
  null::text,
  'internal notes are masked without inventory.read_internal'
);
select extensions.ok(
  (
    select posted_cost_minor is null and estimated_gross_minor is null
      and not can_read_costs
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  ),
  'cost metrics are masked without costs.read'
);
select extensions.is(
  (
    select pg_catalog.jsonb_array_length(allowed_transitions)
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  ),
  0,
  'transitions without the configured permission are not disclosed as allowed'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select *
    from app.get_inventory_unit_operations(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result)
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 foreign workspace administrator cannot read inventory detail'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.results_eq(
  $$
    select
      inventory_unit_id,
      aggregate_version,
      currency_code,
      posted_cost_minor,
      estimated_gross_minor,
      posted_entry_count
    from app.get_inventory_unit_costs(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      null,
      null,
      100
    )
  $$,
  $$
    values (
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      4::bigint,
      'CAD'::text,
      '10000'::text,
      '2890000'::text,
      1::integer
    )
  $$,
  'cost read returns exact aggregate version, currency, metrics, and count'
);
select extensions.ok(
  (
    select pg_catalog.jsonb_array_length(categories) = 3
      and categories @> '[{"key":"reconditioning","labels":{"en":"Reconditioning"}}]'::jsonb
    from app.get_inventory_unit_costs(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      null,
      null,
      100
    )
  ),
  'cost read includes active localized workspace category choices'
);
select extensions.ok(
  (
    select pg_catalog.jsonb_array_length(entries) = 1
      and entries @> '[{"amountMinor":"10000","effectiveStatus":"posted"}]'::jsonb
      and next_cursor is null
    from app.get_inventory_unit_costs(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      null,
      null,
      100
    )
  ),
  'bounded ledger preserves exact amounts, effective status, and cursor state'
);
select extensions.throws_ok(
  $$
    select *
    from app.get_inventory_unit_costs(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      null,
      null,
      0
    )
  $$,
  '22023',
  'invalid cost-ledger query',
  'unbounded or empty cost pages fail closed'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.throws_ok(
  $$
    select *
    from app.get_inventory_unit_costs(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      null,
      null,
      100
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'cost ledger fails closed without costs.read'
);
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select *
    from app.get_inventory_unit_costs(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.operations_inventory_result),
      null,
      null,
      100
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'foreign workspace administrator cannot read the ledger'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.lives_ok(
  $$
    insert into pg_temp.operations_saved_view_result
    select result.*, 'private'
    from app.save_inventory_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-operations-view-private',
      null,
      null,
      'Private synthetic view',
      '{"locationIds":["73000000-0000-4000-8000-000000000001"],"status":["active"]}'::jsonb,
      '{"key":"updated_at","direction":"desc"}'::jsonb,
      '["stock","vehicle","location","state"]'::jsonb,
      'responsive',
      'comfortable',
      'private',
      'request-m2-view-private',
      'a7160000-0000-4000-8000-000000000005'
    ) result
  $$,
  'owner creates a reusable private view'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.operations_saved_view_result
    select result.*, 'shared'
    from app.save_inventory_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-operations-view-shared',
      null,
      null,
      'Shared synthetic view',
      '{"locationIds":["73000000-0000-4000-8000-000000000001"]}'::jsonb,
      '{"key":"updated_at","direction":"desc"}'::jsonb,
      '["stock","vehicle","location","state"]'::jsonb,
      'responsive',
      'compact',
      'workspace',
      'request-m2-view-shared',
      'a7160000-0000-4000-8000-000000000006'
    ) result
  $$,
  'authorized owner creates a reusable workspace view'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from app.list_inventory_saved_views(
      '10000000-0000-4000-8000-000000000001',
      false
    )
    where saved_view_id in (
      select saved_view_id from pg_temp.operations_saved_view_result
    )
  ),
  2,
  'owner lists both full private and shared active configurations'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.results_eq(
  $$
    select name, share_scope, is_owner, filters -> 'locationIds'
    from app.list_inventory_saved_views(
      '10000000-0000-4000-8000-000000000001',
      false
    )
    where saved_view_id in (
      select saved_view_id from pg_temp.operations_saved_view_result
    )
  $$,
  $$
    values (
      'Shared synthetic view'::text,
      'workspace'::text,
      false,
      '["73000000-0000-4000-8000-000000000001"]'::jsonb
    )
  $$,
  'non-owner can load only the shared view with its location filter intact'
);
select extensions.throws_ok(
  $$
    select *
    from app.archive_inventory_saved_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-archive-nonowner',
      (select saved_view_id from pg_temp.operations_saved_view_result where probe = 'shared'),
      1,
      'request-m2-view-archive-nonowner',
      'a7160000-0000-4000-8000-000000000007'
    )
  $$,
  '42501',
  'saved view is unavailable',
  'workspace sharing never grants mutation ownership'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.lives_ok(
  $$
    insert into pg_temp.operations_saved_view_result
    select result.*, 'archived'
    from app.archive_inventory_saved_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-archive-owner',
      (select saved_view_id from pg_temp.operations_saved_view_result where probe = 'private'),
      1,
      'request-m2-view-archive-owner',
      'a7160000-0000-4000-8000-000000000008'
    ) result
  $$,
  'owner archives a view with optimistic concurrency'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.operations_saved_view_result
    select result.*, 'archive-replay'
    from app.archive_inventory_saved_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-archive-owner',
      (select saved_view_id from pg_temp.operations_saved_view_result where probe = 'private'),
      1,
      'request-m2-view-archive-replay',
      'a7160000-0000-4000-8000-000000000009'
    ) result
  $$,
  'matching archive retry replays the durable receipt'
);
select extensions.ok(
  (
    select replay.replayed
      and replay.saved_view_id = archived.saved_view_id
      and replay.saved_view_version = archived.saved_view_version
      and replay.audit_event_id = archived.audit_event_id
    from pg_temp.operations_saved_view_result replay
    cross join pg_temp.operations_saved_view_result archived
    where replay.probe = 'archive-replay'
      and archived.probe = 'archived'
  ),
  'archive replay returns the exact original identifiers'
);
select extensions.throws_ok(
  $$
    select *
    from app.archive_inventory_saved_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-archive-owner',
      (select saved_view_id from pg_temp.operations_saved_view_result where probe = 'private'),
      2,
      'request-m2-view-archive-reuse',
      'a7160000-0000-4000-8000-000000000010'
    )
  $$,
  '23505',
  'saved-view idempotency key was used for another command',
  'changed archive payload cannot reuse an idempotency key'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from app.list_inventory_saved_views(
      '10000000-0000-4000-8000-000000000001', false
    )
    where saved_view_id = (
      select saved_view_id from pg_temp.operations_saved_view_result where probe = 'private'
    )
  ),
  0,
  'active saved-view list excludes archived views'
);
select extensions.ok(
  exists (
    select 1
    from app.list_inventory_saved_views(
      '10000000-0000-4000-8000-000000000001', true
    )
    where saved_view_id = (
      select saved_view_id from pg_temp.operations_saved_view_result where probe = 'private'
    )
      and status = 'archived'
      and version = 2
      and is_owner
  ),
  'owner can deliberately include archived view history'
);
select extensions.ok(
  exists (
    select 1
    from public.audit_events audit
    where audit.id = (
      select audit_event_id
      from pg_temp.operations_saved_view_result
      where probe = 'archived'
    )
      and audit.action = 'inventory_saved_view.archived'
      and audit.before_data ->> 'status' = 'active'
      and audit.after_data ->> 'status' = 'archived'
  ),
  'saved-view archive records append-only before/after audit evidence'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
select extensions.throws_ok(
  $$
    select *
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'm2-facts-aal1-denied',
      (select vehicle_id from pg_temp.operations_inventory_result),
      1,
      2025, 'Synthetic', 'Corrected', 'SUV', 4, 'AWD', '2.5', 'Gasoline',
      200, 'Automatic', 'Lab', 'Registration correction',
      'request-m2-facts-aal1', 'a7160000-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'facts override fails closed without current AAL2 administration context'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal2');
select extensions.throws_ok(
  $$
    select *
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'm2-facts-reader-denied',
      (select vehicle_id from pg_temp.operations_inventory_result),
      1,
      2025, 'Synthetic', 'Corrected', 'SUV', 4, 'AWD', '2.5', 'Gasoline',
      200, 'Automatic', 'Lab', 'Registration correction',
      'request-m2-facts-reader', 'a7160000-0000-4000-8000-000000000012'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'inventory reader cannot override physical facts'
);
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001', 'aal2');
select extensions.throws_ok(
  $$
    select *
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'm2-facts-cross-denied',
      (select vehicle_id from pg_temp.operations_inventory_result),
      1,
      2025, 'Synthetic', 'Corrected', 'SUV', 4, 'AWD', '2.5', 'Gasoline',
      200, 'Automatic', 'Lab', 'Registration correction',
      'request-m2-facts-cross', 'a7160000-0000-4000-8000-000000000013'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 foreign workspace administrator cannot override facts'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
select extensions.lives_ok(
  $$
    insert into pg_temp.operations_facts_result
    select result.*, 'created'
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'm2-facts-override-001',
      (select vehicle_id from pg_temp.operations_inventory_result),
      1,
      2025, 'Synthetic', 'Corrected', 'SUV', 4, 'AWD', '2.5', 'Gasoline',
      200, 'Automatic', 'Lab', 'Registration document correction',
      'request-m2-facts-created', 'a7160000-0000-4000-8000-000000000014'
    ) result
  $$,
  'M2-INV-AC-010 full reasoned facts override succeeds after recent step-up'
);
select extensions.ok(
  exists (
    select 1
    from public.vehicles vehicle
    where vehicle.id = (select vehicle_id from pg_temp.operations_inventory_result)
      and vehicle.facts_version = 2
      and vehicle.model = 'Corrected'
      and vehicle.body_type = 'SUV'
      and pg_catalog.trim_scale(vehicle.engine_displacement_liters)::text = '2.5'
  ),
  'vehicle stores the corrected full snapshot at the next facts version'
);
select extensions.ok(
  exists (
    select 1
    from public.vehicle_facts_override_history history
    where history.id = (
      select history_id from pg_temp.operations_facts_result where probe = 'created'
    )
      and history.facts_version_before = 1
      and history.facts_version_after = 2
      and history.before_facts ->> 'model' = 'Operator'
      and history.after_facts ->> 'model' = 'Corrected'
      and history.reason = 'Registration document correction'
  ),
  'immutable history preserves exact before/after facts and reason'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.operations_facts_result result
    join public.audit_events audit on audit.id = result.audit_event_id
    join public.outbox_events event on event.id = result.outbox_event_id
    where result.probe = 'created'
      and audit.action = 'vehicle.facts_overridden'
      and audit.auth_assurance = 'aal2'
      and event.event_name = 'vehicle.facts_overridden'
      and event.aggregate_type = 'vehicle'
      and event.aggregate_version = 2
      and event.payload = pg_catalog.jsonb_build_object(
        'vehicle_id', result.vehicle_id,
        'facts_version', result.facts_version,
        'history_id', result.history_id
      )
  ),
  'audit and reference-only outbox evidence commit with the correction'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.operations_facts_result
    select result.*, 'replay'
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'm2-facts-override-001',
      (select vehicle_id from pg_temp.operations_inventory_result),
      1,
      2025, 'Synthetic', 'Corrected', 'SUV', 4, 'AWD', '2.5', 'Gasoline',
      200, 'Automatic', 'Lab', 'Registration document correction',
      'request-m2-facts-replay', 'a7160000-0000-4000-8000-000000000015'
    ) result
  $$,
  'matching fact override retry replays the durable receipt'
);
select extensions.ok(
  (
    select replay.replayed
      and replay.vehicle_id = created.vehicle_id
      and replay.facts_version = created.facts_version
      and replay.history_id = created.history_id
      and replay.audit_event_id = created.audit_event_id
      and replay.outbox_event_id = created.outbox_event_id
    from pg_temp.operations_facts_result replay
    cross join pg_temp.operations_facts_result created
    where replay.probe = 'replay' and created.probe = 'created'
  ),
  'facts replay returns every original identifier'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.vehicle_facts_override_history
    where vehicle_id = (select vehicle_id from pg_temp.operations_inventory_result)
  ),
  1,
  'idempotent replay never appends duplicate history'
);
select extensions.throws_ok(
  $$
    select *
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'm2-facts-override-001',
      (select vehicle_id from pg_temp.operations_inventory_result),
      1,
      2025, 'Synthetic', 'Changed again', 'SUV', 4, 'AWD', '2.5', 'Gasoline',
      200, 'Automatic', 'Lab', 'Different request',
      'request-m2-facts-reuse', 'a7160000-0000-4000-8000-000000000016'
    )
  $$,
  '23505',
  'vehicle fact override idempotency key was reused',
  'changed fact payload cannot reuse an idempotency key'
);
select extensions.throws_ok(
  $$
    select *
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'm2-facts-stale-version',
      (select vehicle_id from pg_temp.operations_inventory_result),
      1,
      2025, 'Synthetic', 'Stale', 'SUV', 4, 'AWD', '2.5', 'Gasoline',
      200, 'Automatic', 'Lab', 'Stale concurrent attempt',
      'request-m2-facts-stale', 'a7160000-0000-4000-8000-000000000017'
    )
  $$,
  '40001',
  'vehicle facts version conflict',
  'concurrent stale fact correction fails closed'
);
select extensions.throws_ok(
  $$
    select *
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'm2-facts-no-change',
      (select vehicle_id from pg_temp.operations_inventory_result),
      2,
      2025, 'Synthetic', 'Corrected', 'SUV', 4, 'AWD', '2.5', 'Gasoline',
      200, 'Automatic', 'Lab', 'No actual correction',
      'request-m2-facts-no-change', 'a7160000-0000-4000-8000-000000000018'
    )
  $$,
  '23514',
  'vehicle facts did not change',
  'no-op fact correction is rejected'
);
reset role;
select extensions.throws_ok(
  $$
    update public.vehicle_facts_override_history
    set reason = 'tampered'
    where id = (
      select history_id from pg_temp.operations_facts_result where probe = 'created'
    )
  $$,
  '55000',
  'vehicle fact correction history is append-only',
  'fact correction history cannot be rewritten'
);
select extensions.throws_ok(
  $$
    delete from public.vehicle_facts_override_command_receipts
    where history_id = (
      select history_id from pg_temp.operations_facts_result where probe = 'created'
    )
  $$,
  '55000',
  'vehicle fact correction history is append-only',
  'fact correction command receipts cannot be deleted'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.vehicle_facts_override_history
  ),
  0,
  'T-TEN-001 forced RLS hides fact history from another workspace'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.vehicle_facts_override_command_receipts
  ),
  0,
  'T-TEN-001 forced RLS hides fact receipts from another workspace'
);

reset role;
select * from extensions.finish();
rollback;
