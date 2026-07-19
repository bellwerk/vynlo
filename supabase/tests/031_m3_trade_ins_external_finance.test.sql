-- VYN-DEAL-001, VYN-FIN-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001,
-- VYN-JOB-001, VYN-API-001
-- M3-DEAL-AC-003 / M3-FIN-AC-001 / T-DEAL-002 / T-FIN-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(79);

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
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', case when assurance = 'aal2' then 'totp' else 'password' end,
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config(
    'request.jwt.claim.sub', fixture_user_id::text, true
  );
  perform pg_catalog.set_config(
    'request.jwt.claim.role', 'authenticated', true
  );
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create function pg_temp.legal_file_receipt(
  object_key text,
  generation text,
  byte_size bigint,
  checksum text
)
returns jsonb
language sql
immutable
as $$
  select pg_catalog.jsonb_build_object(
    'schemaVersion', 1,
    'verifier', pg_catalog.jsonb_build_object(
      'name', 'fixture-verifier', 'version', '1.0.0'
    ),
    'storage', pg_catalog.jsonb_build_object(
      'bucket', 'media-private',
      'objectKey', object_key,
      'generation', generation,
      'byteSize', byte_size::text,
      'checksumSha256', checksum
    ),
    'malwareScan', pg_catalog.jsonb_build_object(
      'verdict', 'clean',
      'sourceChecksumSha256', checksum,
      'scanner', 'fixture-scanner',
      'signatureVersion', 'fixture-signatures-1'
    )
  );
$$;

create temporary table pg_temp.deal_results (
  phase text primary key,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.trade_results (
  phase text primary key,
  trade_in_id uuid,
  trade_in_version bigint,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.finance_results (
  phase text primary key,
  finance_application_id uuid,
  status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.condition_results (
  phase text primary key,
  condition_id uuid,
  finance_application_id uuid,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
grant all on
  pg_temp.deal_results,
  pg_temp.trade_results,
  pg_temp.finance_results,
  pg_temp.condition_results
to authenticated, service_role;

select extensions.has_table(
  'public', 'trade_ins',
  'M3-DEAL-AC-003 workspace trade-in table exists'
);
select extensions.has_table(
  'public', 'finance_applications',
  'M3-FIN-AC-001 workspace finance application table exists'
);
select extensions.has_table(
  'public', 'finance_application_conditions',
  'M3-FIN-AC-001 append-only finance conditions exist'
);
select extensions.has_function(
  'app', 'm3_list_trade_ins', array['uuid','uuid'],
  'bounded trade-in list RPC exists'
);
select extensions.has_function(
  'app', 'm3_create_trade_in',
  array[
    'uuid','text','uuid','bigint','uuid','uuid','jsonb','text','text',
    'text','text','uuid','bigint','text','text','jsonb','text','uuid'
  ],
  'versioned trade-in create RPC matches the application contract'
);
select extensions.has_function(
  'app', 'm3_update_trade_in',
  array[
    'uuid','text','bigint','uuid','bigint','uuid','uuid','jsonb','text',
    'text','text','text','uuid','bigint','text','text','jsonb','text','uuid'
  ],
  'aggregate and child-version trade-in update RPC exists'
);
select extensions.has_function(
  'app', 'm3_confirm_trade_in_inventory',
  array['uuid','text','uuid','bigint','bigint','uuid','text','uuid'],
  'explicit trade-in inventory confirmation RPC exists'
);
select extensions.has_function(
  'app', 'm3_list_finance_applications', array['uuid','uuid'],
  'bounded finance list RPC exists'
);
select extensions.has_function(
  'app', 'm3_get_finance_application', array['uuid','uuid'],
  'safe finance detail and condition projection exists'
);
select extensions.has_function(
  'app', 'm3_create_finance_application',
  array[
    'uuid','text','uuid','uuid','uuid','text','text','text','text',
    'integer','text','text','uuid'
  ],
  'external finance create RPC matches the application contract'
);
select extensions.has_function(
  'app', 'm3_update_finance_application',
  array[
    'uuid','text','uuid','bigint','text','text','text','integer','text',
    'timestamp with time zone','timestamp with time zone',
    'timestamp with time zone','timestamp with time zone','text','text',
    'boolean','boolean','boolean','boolean','boolean','boolean','boolean',
    'boolean','boolean','boolean','text','uuid'
  ],
  'exact patch-shaped finance update RPC exists'
);
select extensions.has_function(
  'app', 'm3_transition_finance_application',
  array['uuid','text','uuid','bigint','text','text','text','uuid'],
  'versioned finance lifecycle transition RPC exists'
);
select extensions.has_function(
  'app', 'm3_add_finance_condition',
  array[
    'uuid','text','uuid','bigint','text','text','boolean',
    'timestamp with time zone','timestamp with time zone','uuid','text','uuid'
  ],
  'versioned condition append RPC includes due date and supporting file'
);
select extensions.has_function(
  'app', 'm3_update_finance_condition',
  array[
    'uuid','text','uuid','uuid','bigint','bigint','text','boolean',
    'timestamp with time zone','timestamp with time zone','uuid','text','uuid'
  ],
  'immutable condition replacement RPC matches the lifecycle contract'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'trade_ins', 'finance_applications',
        'finance_application_conditions'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  3::bigint,
  'T-TEN-001 every new M3 trade-in/finance table has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.trade_ins', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.finance_applications', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.finance_application_conditions', 'DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.deal_command_receipts', 'SELECT'
  ),
  'T-RBAC-001 browsers cannot bypass command or receipt boundaries'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'app.can_read_finance_workspace(uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'app.can_read_finance_workspace(uuid)', 'EXECUTE'
  ),
  'T-TEN-001 authenticated finance SELECT policies can execute their RLS helper'
);
select extensions.ok(
  not pg_catalog.has_column_privilege(
    'authenticated', 'public.finance_application_conditions',
    'supporting_file_id', 'SELECT'
  ),
  'T-RBAC-001 restricted finance condition file ids require the safe masked RPC'
);
select extensions.ok(
  (
    select pg_catalog.count(*) >= 10
    from pg_catalog.pg_constraint constraint_info
    where constraint_info.contype = 'f'
      and constraint_info.conrelid in (
        'public.trade_ins'::pg_catalog.regclass,
        'public.finance_applications'::pg_catalog.regclass,
        'public.finance_application_conditions'::pg_catalog.regclass
      )
      and pg_catalog.pg_get_constraintdef(constraint_info.oid)
        like '%FOREIGN KEY (workspace_id,%'
  ),
  'T-TEN-001 all owned entity links use composite workspace foreign keys'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_indexes index_info
    where index_info.schemaname = 'public'
      and index_info.indexname = 'deal_inventory_units_active_trade_in_uidx'
      and index_info.indexdef like '%role_key = ''trade_in''%status = ''active''%'
  ),
  'one active trade-in deal link per inventory unit is database-enforced'
);
select extensions.ok(
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'finance_applications'
      and column_info.column_name = 'lender_reported_annual_rate'
      and column_info.is_generated = 'ALWAYS'
  ),
  'lender-reported annual rate has an exact generated decimal projection'
);
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name in (
        'finance_applications', 'finance_application_conditions'
      )
      and column_info.column_name ~ '(schedule|installment|principal|interest|recurring|provider_payload|credential|token)'
  ),
  'M3 finance has no servicing, provider payload, credential, or schedule fields'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.deal_external_finance_approved(uuid,uuid)'::pg_catalog.regprocedure
  ) like '%public.finance_applications%'
  and pg_catalog.pg_get_functiondef(
    'app.deal_external_finance_approved(uuid,uuid)'::pg_catalog.regprocedure
  ) like '%application.status = ''funded''%'
  and pg_catalog.pg_get_functiondef(
    'app.deal_external_finance_approved(uuid,uuid)'::pg_catalog.regprocedure
  ) like '%application.status = ''approved''%',
  'lender approval guard is backed only by same-workspace approved/funded rows'
);
select extensions.ok(
  exists (
    select 1 from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'finance_application_conditions'
      and column_info.column_name = 'due_at'
  ) and exists (
    select 1 from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'finance_application_conditions'
      and column_info.column_name = 'supporting_file_id'
  ),
  'finance conditions expose bounded due-date and attachment fields'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_indexes index_info
    where index_info.schemaname = 'public'
      and index_info.indexname = 'finance_application_conditions_active_key_uidx'
      and index_info.indexdef like '%status = ''active''%'
  ),
  'one active version per logical finance condition key is enforced'
);

insert into public.parties (
  id, workspace_id, party_type, display_name, status, version,
  idempotency_key, command_fingerprint, created_by
) values
  (
    '84020000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'person', 'Fixture trade-in owner', 'active', 1,
    'm3-trade-owner-001', repeat('1', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '84020000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'person', 'Fixture finance applicant', 'active', 1,
    'm3-fin-applicant-001', repeat('2', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '84020000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    'organization', 'Fixture external lender', 'active', 1,
    'm3-fin-lender-001', repeat('3', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '84020000-0000-4000-8000-000000000004',
    '20000000-0000-4000-8000-000000000002',
    'person', 'Other workspace owner', 'active', 1,
    'm3-other-owner-001', repeat('4', 64),
    '32000000-0000-4000-8000-000000000001'
  );

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
  and permission.key in ('deals.read', 'finance_applications.read');

set constraints all deferred;
insert into public.stock_number_allocations (
  id, workspace_id, definition_id, inventory_unit_id, sequence_value,
  formatted_value, idempotency_key, command_fingerprint, allocated_by
) values
  (
    '84030000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    '84050000-0000-4000-8000-000000000001',
    840001, 'N-840001', 'm3-trade-stock-001', repeat('5', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '84030000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '72000000-0000-4000-8000-000000000001',
    '84050000-0000-4000-8000-000000000002',
    840002, 'H-840002', 'm3-trade-stock-002', repeat('6', 64),
    '32000000-0000-4000-8000-000000000001'
  );
insert into public.vehicles (
  id, workspace_id, vin, model_year, make, model
) values
  (
    '84040000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '1HGCM82633A840001', 2022, 'Fixture', 'Trade vehicle'
  ),
  (
    '84040000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '1HGCM82633A840002', 2021, 'Fixture', 'Other vehicle'
  );
insert into public.inventory_units (
  id, workspace_id, vehicle_id, stock_allocation_id, stock_number,
  status, location_id, currency_code, advertised_price_minor, created_by
) values
  (
    '84050000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '84040000-0000-4000-8000-000000000001',
    '84030000-0000-4000-8000-000000000001',
    'N-840001', 'draft',
    '73000000-0000-4000-8000-000000000001',
    'CAD', 1600000,
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '84050000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '84040000-0000-4000-8000-000000000002',
    '84030000-0000-4000-8000-000000000002',
    'H-840002', 'draft',
    '73000000-0000-4000-8000-000000000002',
    'CAD', 1500000,
    '32000000-0000-4000-8000-000000000001'
  );
set constraints all immediate;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.deal_results
select 'trade-deal', command.*
from app.m3_create_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-trade-deal-001', 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001',
  (select legal_entity.id from public.legal_entities legal_entity
    where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      and legal_entity.status = 'active'
    order by legal_entity.id limit 1),
  '41000000-0000-4000-8000-000000000001',
  null, null, 'request-trade-deal-001',
  '84060000-0000-4000-8000-000000000001'
) command;

insert into pg_temp.trade_results
select 'trade-create', command.*
from app.m3_create_trade_in(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-trade-create-001',
  p_deal_id => (
    select deal_id from pg_temp.deal_results where phase = 'trade-deal'
  ),
  p_expected_version => 1,
  p_owner_party_id => '84020000-0000-4000-8000-000000000001',
  p_vehicle_id => '84040000-0000-4000-8000-000000000001',
  p_entered_vehicle_facts => null,
  p_allowance_minor => '1500000',
  p_currency_code => 'CAD',
  p_lien_amount_minor => '500000',
  p_payoff_amount_minor => '510000',
  p_lender_party_id => '84020000-0000-4000-8000-000000000003',
  p_odometer_value => 123456,
  p_odometer_unit => 'km',
  p_condition_key => 'good',
  p_tax_eligibility_inputs => '{"jurisdiction":"CA-QC","declaredEligible":true}',
  p_request_id => 'request-trade-create-001',
  p_correlation_id => '84060000-0000-4000-8000-000000000003'
) command;

insert into pg_temp.trade_results
select 'trade-create-replay', command.*
from app.m3_create_trade_in(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-trade-create-001',
  p_deal_id => (
    select deal_id from pg_temp.deal_results where phase = 'trade-deal'
  ),
  p_expected_version => 1,
  p_owner_party_id => '84020000-0000-4000-8000-000000000001',
  p_vehicle_id => '84040000-0000-4000-8000-000000000001',
  p_entered_vehicle_facts => null,
  p_allowance_minor => '1500000',
  p_currency_code => 'CAD',
  p_lien_amount_minor => '500000',
  p_payoff_amount_minor => '510000',
  p_lender_party_id => '84020000-0000-4000-8000-000000000003',
  p_odometer_value => 123456,
  p_odometer_unit => 'km',
  p_condition_key => 'good',
  p_tax_eligibility_inputs => '{"jurisdiction":"CA-QC","declaredEligible":true}',
  p_request_id => 'request-trade-create-001',
  p_correlation_id => '84060000-0000-4000-8000-000000000003'
) command;

select extensions.is(
  (
    select trade_in_version::text || ':' || aggregate_version::text || ':'
      || replayed::text
    from pg_temp.trade_results where phase = 'trade-create'
  ),
  '1:2:false',
  'trade-in create versions both the child and deal aggregate'
);
select extensions.ok(
  (
    select first_result.trade_in_id = replay_result.trade_in_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
      and replay_result.replayed
    from pg_temp.trade_results first_result
    cross join pg_temp.trade_results replay_result
    where first_result.phase = 'trade-create'
      and replay_result.phase = 'trade-create-replay'
  ),
  'actor-scoped trade-in create replay returns original evidence'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.deal_inventory_units inventory_link
    where inventory_link.workspace_id = '10000000-0000-4000-8000-000000000001'
      and inventory_link.deal_id = (
        select deal_id from pg_temp.deal_results where phase = 'trade-deal'
      )
      and inventory_link.role_key = 'trade_in'
  ),
  0::bigint,
  'trade-in capture remains separate from inventory until explicit confirmation'
);
select extensions.is(
  (
    select trade_in.allowance_minor || ':' || trade_in.lien_amount_minor
      || ':' || trade_in.payoff_amount_minor || ':' || trade_in.currency_code
    from app.m3_list_trade_ins(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'trade-deal')
    ) trade_in
  ),
  '1500000:500000:510000:CAD',
  'trade-in read preserves exact same-currency nonnegative minor units'
);
select extensions.throws_ok(
  $$
    select * from app.m3_create_trade_in(
      '10000000-0000-4000-8000-000000000001',
      'm3-trade-create-001',
      (select deal_id from pg_temp.deal_results where phase = 'trade-deal'),
      1, '84020000-0000-4000-8000-000000000001',
      '84040000-0000-4000-8000-000000000001', null,
      '1500001', 'CAD', '500000', '510000',
      '84020000-0000-4000-8000-000000000003', 123456, 'km', 'good',
      '{"jurisdiction":"CA-QC"}', 'request-trade-create-mismatch',
      '84060000-0000-4000-8000-000000000004'
    )
  $$,
  '23505',
  'deal idempotency key was reused with different input',
  'trade-in idempotency mismatch fails before stale aggregate checks'
);
select extensions.throws_ok(
  $$
    select * from app.m3_create_trade_in(
      '10000000-0000-4000-8000-000000000001',
      'm3-trade-missing-vehicle',
      (select deal_id from pg_temp.deal_results where phase = 'trade-deal'),
      2, '84020000-0000-4000-8000-000000000001', null, null,
      '1', 'CAD', '0', '0', null, null, null, null, '{}',
      'request-trade-missing-vehicle',
      '84060000-0000-4000-8000-000000000005'
    )
  $$,
  '23514',
  'trade-in vehicle or entered facts are required',
  'trade-in capture requires a vehicle or bounded entered facts'
);
select extensions.throws_ok(
  $$
    select * from app.m3_create_trade_in(
      '10000000-0000-4000-8000-000000000001',
      'm3-trade-executable-facts',
      (select deal_id from pg_temp.deal_results where phase = 'trade-deal'),
      2, '84020000-0000-4000-8000-000000000001', null,
      '{"script":"never"}', '1', 'CAD', '0', '0', null,
      null, null, null, '{}', 'request-trade-executable-facts',
      '84060000-0000-4000-8000-000000000006'
    )
  $$,
  '23514',
  'entered trade-in facts must be bounded inert data',
  'trade-in entered facts reject executable keys'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_trade_in(
      '10000000-0000-4000-8000-000000000001',
      'm3-trade-update-stale', 1,
      (select trade_in_id from pg_temp.trade_results where phase = 'trade-create'),
      1, '84020000-0000-4000-8000-000000000001',
      '84040000-0000-4000-8000-000000000001', null,
      '1550000', 'CAD', '490000', '505000',
      '84020000-0000-4000-8000-000000000003', 123500, 'km',
      'excellent', '{"jurisdiction":"CA-QC"}',
      'request-trade-update-stale',
      '84060000-0000-4000-8000-000000000007'
    )
  $$,
  '40001',
  'stale deal version',
  'trade-in update rejects stale deal aggregate version'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_trade_in(
      '10000000-0000-4000-8000-000000000001',
      'm3-trade-update-cross-owner', 2,
      (select trade_in_id from pg_temp.trade_results where phase = 'trade-create'),
      1, '84020000-0000-4000-8000-000000000004',
      '84040000-0000-4000-8000-000000000001', null,
      '1550000', 'CAD', '490000', '505000', null, 123500, 'km',
      'excellent', '{}', 'request-trade-update-cross-owner',
      '84060000-0000-4000-8000-000000000008'
    )
  $$,
  '23514',
  'active workspace trade-in owner is required',
  'trade-in update rejects a cross-workspace owner'
);

insert into pg_temp.trade_results
select 'trade-update', command.*
from app.m3_update_trade_in(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-trade-update-001',
  p_expected_version => 2,
  p_trade_in_id => (
    select trade_in_id from pg_temp.trade_results where phase = 'trade-create'
  ),
  p_expected_trade_in_version => 1,
  p_owner_party_id => '84020000-0000-4000-8000-000000000001',
  p_vehicle_id => '84040000-0000-4000-8000-000000000001',
  p_entered_vehicle_facts => null,
  p_allowance_minor => '1550000',
  p_currency_code => 'CAD',
  p_lien_amount_minor => '490000',
  p_payoff_amount_minor => '505000',
  p_lender_party_id => '84020000-0000-4000-8000-000000000003',
  p_odometer_value => 123500,
  p_odometer_unit => 'km',
  p_condition_key => 'excellent',
  p_tax_eligibility_inputs => '{"jurisdiction":"CA-QC","declaredEligible":false}',
  p_request_id => 'request-trade-update-001',
  p_correlation_id => '84060000-0000-4000-8000-000000000009'
) command;

select extensions.is(
  (
    select trade_in_version::text || ':' || aggregate_version::text
    from pg_temp.trade_results where phase = 'trade-update'
  ),
  '2:3',
  'trade-in update increments child and deal aggregate versions atomically'
);
select extensions.throws_ok(
  $$
    select * from app.m3_confirm_trade_in_inventory(
      '10000000-0000-4000-8000-000000000001',
      'm3-trade-confirm-cross-workspace',
      (select trade_in_id from pg_temp.trade_results where phase = 'trade-create'),
      2, 3, '84050000-0000-4000-8000-000000000002',
      'request-trade-confirm-cross-workspace',
      '84060000-0000-4000-8000-000000000010'
    )
  $$,
  '23514',
  'available independently created inventory unit is required',
  'trade-in confirmation rejects cross-workspace inventory'
);

insert into pg_temp.trade_results
select 'trade-confirm', command.*
from app.m3_confirm_trade_in_inventory(
  '10000000-0000-4000-8000-000000000001',
  'm3-trade-confirm-001',
  (select trade_in_id from pg_temp.trade_results where phase = 'trade-create'),
  2, 3, '84050000-0000-4000-8000-000000000001',
  'request-trade-confirm-001',
  '84060000-0000-4000-8000-000000000011'
) command;
insert into pg_temp.trade_results
select 'trade-confirm-replay', command.*
from app.m3_confirm_trade_in_inventory(
  '10000000-0000-4000-8000-000000000001',
  'm3-trade-confirm-001',
  (select trade_in_id from pg_temp.trade_results where phase = 'trade-create'),
  2, 3, '84050000-0000-4000-8000-000000000001',
  'request-trade-confirm-001',
  '84060000-0000-4000-8000-000000000011'
) command;

select extensions.is(
  (
    select trade_in.status || ':' || trade_in.version::text || ':'
      || trade_in.resulting_inventory_unit_id::text
    from public.trade_ins trade_in
    where trade_in.id = (
      select trade_in_id from pg_temp.trade_results where phase = 'trade-create'
    )
  ),
  'confirmed:3:84050000-0000-4000-8000-000000000001',
  'explicit confirmation links the independently created matching inventory unit'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.inventory_units inventory
    where inventory.workspace_id = '10000000-0000-4000-8000-000000000001'
      and inventory.id = '84050000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'trade-in confirmation never creates inventory automatically'
);
select extensions.ok(
  (
    select confirmation.aggregate_version = 4
      and confirmation.trade_in_version = 3
      and replay_result.replayed
      and confirmation.audit_event_id = replay_result.audit_event_id
      and confirmation.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.trade_results confirmation
    cross join pg_temp.trade_results replay_result
    where confirmation.phase = 'trade-confirm'
      and replay_result.phase = 'trade-confirm-replay'
  ),
  'trade-in confirmation versions atomically and replays original evidence'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_trade_in(
      '10000000-0000-4000-8000-000000000001',
      'm3-trade-update-confirmed', 4,
      (select trade_in_id from pg_temp.trade_results where phase = 'trade-create'),
      3, '84020000-0000-4000-8000-000000000001',
      '84040000-0000-4000-8000-000000000001', null,
      '1550000', 'CAD', '490000', '505000', null, 123500, 'km',
      'excellent', '{}', 'request-trade-update-confirmed',
      '84060000-0000-4000-8000-000000000012'
    )
  $$,
  '55000',
  'confirmed or cancelled trade-in cannot be changed',
  'confirmed trade-in facts are immutable through update commands'
);

insert into pg_temp.deal_results
select 'finance-deal', command.*
from app.m3_create_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-deal-001', 'retail.third_party_financed', 'CAD',
  '73000000-0000-4000-8000-000000000001',
  (select legal_entity.id from public.legal_entities legal_entity
    where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      and legal_entity.status = 'active'
    order by legal_entity.id limit 1),
  '41000000-0000-4000-8000-000000000001',
  null, null, 'request-finance-deal-001',
  '84060000-0000-4000-8000-000000000002'
) command;

insert into pg_temp.finance_results
select 'finance-create', command.*
from app.m3_create_finance_application(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-finance-create-001',
  p_deal_id => (
    select deal_id from pg_temp.deal_results where phase = 'finance-deal'
  ),
  p_applicant_party_id => '84020000-0000-4000-8000-000000000002',
  p_lender_party_id => '84020000-0000-4000-8000-000000000003',
  p_requested_amount_minor => '2500000',
  p_requested_currency_code => 'CAD',
  p_external_reference => 'LENDER-REF-001',
  p_lender_reported_annual_rate => '6.125000',
  p_lender_reported_term_months => 60,
  p_notes => 'External lender record only',
  p_request_id => 'request-finance-create-001',
  p_correlation_id => '84060000-0000-4000-8000-000000000013'
) command;
insert into pg_temp.finance_results
select 'finance-create-replay', command.*
from app.m3_create_finance_application(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-finance-create-001',
  p_deal_id => (
    select deal_id from pg_temp.deal_results where phase = 'finance-deal'
  ),
  p_applicant_party_id => '84020000-0000-4000-8000-000000000002',
  p_lender_party_id => '84020000-0000-4000-8000-000000000003',
  p_requested_amount_minor => '2500000',
  p_requested_currency_code => 'CAD',
  p_external_reference => 'LENDER-REF-001',
  p_lender_reported_annual_rate => '6.125000',
  p_lender_reported_term_months => 60,
  p_notes => 'External lender record only',
  p_request_id => 'request-finance-create-001',
  p_correlation_id => '84060000-0000-4000-8000-000000000013'
) command;

select extensions.is(
  (
    select status || ':' || aggregate_version::text || ':' || replayed::text
    from pg_temp.finance_results where phase = 'finance-create'
  ),
  'preparing:2:false',
  'external finance create records preparing state and bumps the deal aggregate'
);
select extensions.ok(
  (
    select first_result.finance_application_id = replay_result.finance_application_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
      and replay_result.replayed
    from pg_temp.finance_results first_result
    cross join pg_temp.finance_results replay_result
    where first_result.phase = 'finance-create'
      and replay_result.phase = 'finance-create-replay'
  ),
  'finance create replay returns the original actor-scoped evidence'
);
select extensions.throws_ok(
  $$
    select * from app.m3_create_finance_application(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-create-001',
      (select deal_id from pg_temp.deal_results where phase = 'finance-deal'),
      '84020000-0000-4000-8000-000000000002',
      '84020000-0000-4000-8000-000000000003',
      '2500001', 'CAD', 'LENDER-REF-001', '6.125000', 60,
      'External lender record only', 'request-finance-create-mismatch',
      '84060000-0000-4000-8000-000000000014'
    )
  $$,
  '23505',
  'deal idempotency key was reused with different input',
  'finance idempotency mismatch fails before row or version checks'
);
select extensions.throws_ok(
  $$
    select * from app.m3_create_finance_application(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-wrong-config',
      (select deal_id from pg_temp.deal_results where phase = 'trade-deal'),
      '84020000-0000-4000-8000-000000000002',
      '84020000-0000-4000-8000-000000000003',
      '1000000', 'CAD', null, null, null, null,
      'request-finance-wrong-config',
      '84060000-0000-4000-8000-000000000015'
    )
  $$,
  '23514',
  'deal type does not allow external finance tracking',
  'finance create fails closed on a deal type without external lender mode'
);
select extensions.throws_ok(
  $$
    select * from app.m3_create_finance_application(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-cross-applicant',
      (select deal_id from pg_temp.deal_results where phase = 'finance-deal'),
      '84020000-0000-4000-8000-000000000004',
      '84020000-0000-4000-8000-000000000003',
      '1000000', 'CAD', null, null, null, null,
      'request-finance-cross-applicant',
      '84060000-0000-4000-8000-000000000016'
    )
  $$,
  '23514',
  'active workspace finance applicant is required',
  'finance create rejects a cross-workspace applicant'
);

insert into pg_temp.finance_results
select 'finance-update', command.*
from app.m3_update_finance_application(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-finance-update-001',
  p_finance_application_id => (
    select finance_application_id from pg_temp.finance_results
    where phase = 'finance-create'
  ),
  p_expected_version => 1,
  p_approved_amount_minor => '2000000',
  p_approved_currency_code => 'CAD',
  p_lender_reported_annual_rate => '6.125000',
  p_lender_reported_term_months => 60,
  p_external_reference => null,
  p_submitted_at => timestamptz '2020-07-16 20:00:00+00',
  p_approval_expires_at => timestamptz '2099-07-16 20:00:00+00',
  p_customer_accepted_at => timestamptz '2020-07-16 21:00:00+00',
  p_funded_at => null,
  p_funding_reference => null,
  p_notes => null,
  p_update_approval_amount => true,
  p_update_lender_rate => true,
  p_update_lender_term => true,
  p_update_external_reference => false,
  p_update_submitted_at => true,
  p_update_approval_expiry => true,
  p_update_customer_acceptance => true,
  p_update_funded_at => false,
  p_update_funding_reference => false,
  p_update_notes => false,
  p_request_id => 'request-finance-update-001',
  p_correlation_id => '84060000-0000-4000-8000-000000000017'
) command;

select extensions.is(
  (
    select application.approved_amount_minor::text || ':'
      || application.currency_code::text || ':'
      || application.lender_reported_annual_rate_text || ':'
      || application.lender_reported_annual_rate::text || ':'
      || application.lender_reported_term_months::text || ':'
      || application.version::text
    from public.finance_applications application
    where application.id = (
      select finance_application_id from pg_temp.finance_results
      where phase = 'finance-create'
    )
  ),
  '2000000:CAD:6.125000:6.125000:60:2',
  'finance update preserves exact approved money, decimal rate, term, and version'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_finance_application(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_idempotency_key => 'm3-finance-update-stale',
      p_finance_application_id => (
        select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'
      ),
      p_expected_version => 1,
      p_approved_amount_minor => null,
      p_approved_currency_code => null,
      p_lender_reported_annual_rate => null,
      p_lender_reported_term_months => null,
      p_external_reference => null,
      p_submitted_at => null,
      p_approval_expires_at => null,
      p_customer_accepted_at => null,
      p_funded_at => null,
      p_funding_reference => null,
      p_notes => 'stale',
      p_update_approval_amount => false,
      p_update_lender_rate => false,
      p_update_lender_term => false,
      p_update_external_reference => false,
      p_update_submitted_at => false,
      p_update_approval_expiry => false,
      p_update_customer_acceptance => false,
      p_update_funded_at => false,
      p_update_funding_reference => false,
      p_update_notes => true,
      p_request_id => 'request-finance-update-stale',
      p_correlation_id => '84060000-0000-4000-8000-000000000018'
    )
  $$,
  '40001',
  'stale finance application version',
  'finance update rejects stale application version under row lock'
);

insert into pg_temp.finance_results
select 'finance-submitted', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-submit-001',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-create'),
  2, 'submitted', null, 'request-finance-submit-001',
  '84060000-0000-4000-8000-000000000019'
) command;
select extensions.is(
  (
    select status || ':' || aggregate_version::text
    from pg_temp.finance_results where phase = 'finance-submitted'
  ),
  'submitted:4',
  'finance submission is a recorded local lifecycle transition only'
);

reset role;
insert into public.media_assets (
  id, workspace_id, deal_id, owner_entity_type, owner_entity_id,
  media_kind, status, created_by
) values (
  '84070000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  (select deal_id from pg_temp.deal_results where phase = 'finance-deal'),
  'deal',
  (select deal_id from pg_temp.deal_results where phase = 'finance-deal'),
  'legal_document', 'ready',
  '31000000-0000-4000-8000-000000000001'
);
insert into public.media_files (
  id, workspace_id, media_id, file_class, variant, storage_bucket,
  storage_object_key, storage_generation, mime_type, byte_size,
  checksum_sha256, metadata_stripped, retention_policy,
  verification_receipt
) values (
  '84071000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '84070000-0000-4000-8000-000000000001',
  'legal_document_original', 'legal_original', 'media-private',
  'workspaces/10000000-0000-4000-8000-000000000001/deals/'
    || (select deal_id::text from pg_temp.deal_results
        where phase = 'finance-deal')
    || '/finance-conditions/fixture.pdf',
  'm3-finance-condition-generation-001', 'application/pdf', 1024,
  repeat('7', 64), false, 'preserve_original',
  pg_temp.legal_file_receipt(
    'workspaces/10000000-0000-4000-8000-000000000001/deals/'
      || (select deal_id::text from pg_temp.deal_results
          where phase = 'finance-deal')
      || '/finance-conditions/fixture.pdf',
    'm3-finance-condition-generation-001', 1024, repeat('7', 64)
  )
);
set local role authenticated;

insert into pg_temp.condition_results
select 'condition-add', command.*
from app.m3_add_finance_condition(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-condition-001',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-create'),
  3, 'proof_of_income', 'Verified proof of income', true,
  null,
  timestamptz '2099-08-01 20:00:00+00',
  '84071000-0000-4000-8000-000000000001',
  'request-finance-condition-001',
  '84060000-0000-4000-8000-000000000020'
) command;
insert into pg_temp.condition_results
select 'condition-add-replay', command.*
from app.m3_add_finance_condition(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-condition-001',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-create'),
  3, 'proof_of_income', 'Verified proof of income', true,
  null,
  timestamptz '2099-08-01 20:00:00+00',
  '84071000-0000-4000-8000-000000000001',
  'request-finance-condition-001',
  '84060000-0000-4000-8000-000000000020'
) command;

select extensions.ok(
  (
    select first_result.aggregate_version = 5
      and replay_result.replayed
      and first_result.condition_id = replay_result.condition_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.condition_results first_result
    cross join pg_temp.condition_results replay_result
    where first_result.phase = 'condition-add'
      and replay_result.phase = 'condition-add-replay'
  ),
  'condition append versions the aggregate and replays original evidence'
);
select extensions.throws_ok(
  $$
    select * from app.m3_add_finance_condition(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-condition-001',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'),
      3, 'proof_of_income', 'Different description', true,
      null,
      timestamptz '2099-08-01 20:00:00+00',
      '84071000-0000-4000-8000-000000000001',
      'request-finance-condition-mismatch',
      '84060000-0000-4000-8000-000000000021'
    )
  $$,
  '23505',
  'deal idempotency key was reused with different input',
  'condition idempotency mismatch fails before stale version checks'
);
select extensions.throws_ok(
  $$
    select * from app.m3_add_finance_condition(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-condition-cross-file',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'),
      4, 'cross_file', 'Cross-workspace file', false, null, null,
      '84071000-0000-4000-8000-000000000002',
      'request-finance-condition-cross-file',
      '84060000-0000-4000-8000-000000000022'
    )
  $$,
  '23514',
  'condition attachment must be a ready preserved legal original owned by the same deal',
  'condition attachment rejects unavailable or cross-workspace files'
);
select extensions.ok(
  (
    select detail.requested_amount_minor = '2500000'
      and detail.approved_amount_minor = '2000000'
      and detail.lender_reported_annual_rate = '6.125000'
      and pg_catalog.jsonb_array_length(detail.conditions) = 1
      and detail.conditions -> 0 ->> 'condition_key' = 'proof_of_income'
      and detail.conditions -> 0 ->> 'due_at' is not null
      and detail.conditions -> 0 ->> 'supporting_file_id'
        = '84071000-0000-4000-8000-000000000001'
    from app.m3_get_finance_application(
      '10000000-0000-4000-8000-000000000001',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create')
    ) detail
  ),
  'safe finance detail returns exact fields and bounded condition attachments'
);

select extensions.throws_ok(
  $$
    select * from app.m3_transition_finance_application(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-approve-before-satisfied',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'),
      4, 'approved', null, 'request-finance-approve-before-satisfied',
      '84060000-0000-4000-8000-000000000036'
    )
  $$,
  '23514',
  'all required finance conditions must be satisfied',
  'active unsatisfied condition blocks approval before replacement'
);

insert into pg_temp.condition_results
select 'condition-satisfied', command.*
from app.m3_update_finance_condition(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-condition-satisfy',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-create'),
  (select condition_id from pg_temp.condition_results
    where phase = 'condition-add'),
  4, 1, 'Verified proof of income', true,
  timestamptz '2020-07-17 20:00:00+00',
  timestamptz '2099-08-01 20:00:00+00',
  '84071000-0000-4000-8000-000000000001',
  'request-finance-condition-satisfy',
  '84060000-0000-4000-8000-000000000037'
) command;
insert into pg_temp.condition_results
select 'condition-satisfied-replay', command.*
from app.m3_update_finance_condition(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-condition-satisfy',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-create'),
  (select condition_id from pg_temp.condition_results
    where phase = 'condition-add'),
  4, 1, 'Verified proof of income', true,
  timestamptz '2020-07-17 20:00:00+00',
  timestamptz '2099-08-01 20:00:00+00',
  '84071000-0000-4000-8000-000000000001',
  'request-finance-condition-satisfy',
  '84060000-0000-4000-8000-000000000037'
) command;
select extensions.ok(
  (
    select first_result.aggregate_version = 6
      and first_result.condition_id <> old_result.condition_id
      and replay_result.replayed
      and first_result.condition_id = replay_result.condition_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.condition_results first_result
    cross join pg_temp.condition_results old_result
    cross join pg_temp.condition_results replay_result
    where first_result.phase = 'condition-satisfied'
      and old_result.phase = 'condition-add'
      and replay_result.phase = 'condition-satisfied-replay'
  ),
  'condition satisfaction creates a new immutable version and replays evidence'
);
select extensions.ok(
  (
    select old_condition.status = 'replaced'
      and old_condition.version = 1
      and old_condition.replaced_at is not null
      and new_condition.status = 'active'
      and new_condition.version = 2
      and new_condition.logical_condition_id
        = old_condition.logical_condition_id
      and new_condition.replaces_condition_id = old_condition.id
      and new_condition.satisfied_at is not null
    from public.finance_application_conditions old_condition
    cross join public.finance_application_conditions new_condition
    where old_condition.id = (
        select condition_id from pg_temp.condition_results
        where phase = 'condition-add'
      )
      and new_condition.id = (
        select condition_id from pg_temp.condition_results
        where phase = 'condition-satisfied'
      )
  ),
  'condition replacement preserves lineage and immutable old-version evidence'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_finance_condition(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-condition-satisfy',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'),
      (select condition_id from pg_temp.condition_results
        where phase = 'condition-add'),
      4, 1, 'Changed mismatch description', true,
      timestamptz '2020-07-17 20:00:00+00',
      timestamptz '2099-08-01 20:00:00+00',
      '84071000-0000-4000-8000-000000000001',
      'request-finance-condition-satisfy-mismatch',
      '84060000-0000-4000-8000-000000000038'
    )
  $$,
  '23505',
  'deal idempotency key was reused with different input',
  'condition replacement idempotency mismatch fails before stale checks'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_finance_condition(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-condition-stale-app',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'),
      (select condition_id from pg_temp.condition_results
        where phase = 'condition-satisfied'),
      4, 2, 'Verified proof of income', true,
      timestamptz '2020-07-17 20:00:00+00',
      timestamptz '2099-08-01 20:00:00+00',
      '84071000-0000-4000-8000-000000000001',
      'request-finance-condition-stale-app',
      '84060000-0000-4000-8000-000000000039'
    )
  $$,
  '40001',
  'stale finance application version',
  'condition replacement rejects stale finance aggregate version'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_finance_condition(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-condition-stale-child',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'),
      (select condition_id from pg_temp.condition_results
        where phase = 'condition-satisfied'),
      5, 1, 'Verified proof of income', true,
      timestamptz '2020-07-17 20:00:00+00',
      timestamptz '2099-08-01 20:00:00+00',
      '84071000-0000-4000-8000-000000000001',
      'request-finance-condition-stale-child',
      '84060000-0000-4000-8000-000000000040'
    )
  $$,
  '40001',
  'stale finance condition version',
  'condition replacement rejects stale child version under row lock'
);
select extensions.ok(
  (
    select pg_catalog.jsonb_array_length(detail.conditions) = 1
      and detail.conditions -> 0 ->> 'condition_id' = (
        select condition_id::text from pg_temp.condition_results
        where phase = 'condition-satisfied'
      )
      and detail.conditions -> 0 ->> 'version' = '2'
      and detail.conditions -> 0 ->> 'status' = 'active'
      and detail.conditions -> 0 ->> 'replaces_condition_id' = (
        select condition_id::text from pg_temp.condition_results
        where phase = 'condition-add'
      )
    from app.m3_get_finance_application(
      '10000000-0000-4000-8000-000000000001',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create')
    ) detail
  ),
  'finance detail projects only the current active condition version'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.ok(
  (
    select pg_catalog.jsonb_array_length(detail.conditions) = 1
      and detail.conditions -> 0 ->> 'supporting_file_id' is null
    from app.m3_get_finance_application(
      '10000000-0000-4000-8000-000000000001',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create')
    ) detail
  ),
  'finance detail masks restricted supporting file IDs without file permission'
);
reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.finance_results
select 'finance-approved', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-approve-001',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-create'),
  5, 'approved', null, 'request-finance-approve-001',
  '84060000-0000-4000-8000-000000000023'
) command;
select extensions.is(
  (
    select status || ':' || aggregate_version::text
    from pg_temp.finance_results where phase = 'finance-approved'
  ),
  'approved:7',
  'approval succeeds after immutable condition satisfaction replacement'
);
reset role;
select extensions.ok(
  app.deal_external_finance_approved(
    '10000000-0000-4000-8000-000000000001',
    (select deal_id from pg_temp.deal_results where phase = 'finance-deal')
  ),
  'non-expired same-workspace approved finance satisfies the deal guard'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.finance_results
select 'finance-funded', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-funded-001',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-create'),
  6, 'funded', null, 'request-finance-funded-001',
  '84060000-0000-4000-8000-000000000024'
) command;
select extensions.ok(
  (
    select application.status = 'funded'
      and application.funded_at is not null
      and application.customer_accepted_at is not null
      and application.version = 7
    from public.finance_applications application
    where application.id = (
      select finance_application_id from pg_temp.finance_results
      where phase = 'finance-create'
    )
  ),
  'funding requires customer acceptance and records a local funded timestamp'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_finance_condition(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-condition-terminal',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'),
      (select condition_id from pg_temp.condition_results
        where phase = 'condition-satisfied'),
      7, 2, 'Terminal replacement denied', true,
      timestamptz '2020-07-17 20:00:00+00', null, null,
      'request-finance-condition-terminal',
      '84060000-0000-4000-8000-000000000041'
    )
  $$,
  '55000',
  'finance conditions cannot be replaced after approval or termination',
  'terminal finance application rejects condition replacement'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_finance_application(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_idempotency_key => 'm3-finance-update-terminal',
      p_finance_application_id => (
        select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create'
      ),
      p_expected_version => 7,
      p_approved_amount_minor => null,
      p_approved_currency_code => null,
      p_lender_reported_annual_rate => null,
      p_lender_reported_term_months => null,
      p_external_reference => null,
      p_submitted_at => null,
      p_approval_expires_at => null,
      p_customer_accepted_at => null,
      p_funded_at => null,
      p_funding_reference => null,
      p_notes => 'terminal mutation',
      p_update_approval_amount => false,
      p_update_lender_rate => false,
      p_update_lender_term => false,
      p_update_external_reference => false,
      p_update_submitted_at => false,
      p_update_approval_expiry => false,
      p_update_customer_acceptance => false,
      p_update_funded_at => false,
      p_update_funding_reference => false,
      p_update_notes => true,
      p_request_id => 'request-finance-update-terminal',
      p_correlation_id => '84060000-0000-4000-8000-000000000025'
    )
  $$,
  '55000',
  'terminal finance application cannot be changed',
  'funded finance application is immutable through update commands'
);

insert into pg_temp.finance_results
select 'finance-blocked-create', command.*
from app.m3_create_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-blocked-create',
  (select deal_id from pg_temp.deal_results where phase = 'finance-deal'),
  '84020000-0000-4000-8000-000000000002',
  '84020000-0000-4000-8000-000000000003',
  '1800000', 'CAD', 'LENDER-REF-002', '7.500000', 48, null,
  'request-finance-blocked-create',
  '84060000-0000-4000-8000-000000000026'
) command;
insert into pg_temp.finance_results
select 'finance-blocked-update', command.*
from app.m3_update_finance_application(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-finance-blocked-update',
  p_finance_application_id => (
    select finance_application_id from pg_temp.finance_results
    where phase = 'finance-blocked-create'
  ),
  p_expected_version => 1,
  p_approved_amount_minor => '1700000',
  p_approved_currency_code => 'CAD',
  p_lender_reported_annual_rate => null,
  p_lender_reported_term_months => null,
  p_external_reference => null,
  p_submitted_at => timestamptz '2020-07-16 20:00:00+00',
  p_approval_expires_at => null,
  p_customer_accepted_at => null,
  p_funded_at => null,
  p_funding_reference => null,
  p_notes => null,
  p_update_approval_amount => true,
  p_update_lender_rate => false,
  p_update_lender_term => false,
  p_update_external_reference => false,
  p_update_submitted_at => true,
  p_update_approval_expiry => false,
  p_update_customer_acceptance => false,
  p_update_funded_at => false,
  p_update_funding_reference => false,
  p_update_notes => false,
  p_request_id => 'request-finance-blocked-update',
  p_correlation_id => '84060000-0000-4000-8000-000000000027'
) command;
insert into pg_temp.finance_results
select 'finance-blocked-submitted', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-blocked-submit',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-blocked-create'),
  2, 'submitted', null, 'request-finance-blocked-submit',
  '84060000-0000-4000-8000-000000000028'
) command;
insert into pg_temp.condition_results
select 'condition-unsatisfied', command.*
from app.m3_add_finance_condition(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-condition-unsatisfied',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-blocked-create'),
  3, 'bank_statement', 'Current bank statement', true,
  null, timestamptz '2099-08-01 20:00:00+00', null,
  'request-finance-condition-unsatisfied',
  '84060000-0000-4000-8000-000000000029'
) command;
select extensions.throws_ok(
  $$
    select * from app.m3_transition_finance_application(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-approve-unsatisfied',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-blocked-create'),
      4, 'approved', null, 'request-finance-approve-unsatisfied',
      '84060000-0000-4000-8000-000000000030'
    )
  $$,
  '23514',
  'all required finance conditions must be satisfied',
  'unsatisfied required condition blocks lender approval'
);
select extensions.throws_ok(
  $$
    select * from app.m3_add_finance_condition(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-condition-stale',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-blocked-create'),
      3, 'stale_condition', 'Stale condition', false, null, null, null,
      'request-finance-condition-stale',
      '84060000-0000-4000-8000-000000000031'
    )
  $$,
  '40001',
  'stale finance application version',
  'condition append rejects stale finance application version'
);
insert into pg_temp.finance_results
select 'finance-declined', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-decline-001',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-blocked-create'),
  4, 'declined', 'Lender declined the external application',
  'request-finance-decline-001',
  '84060000-0000-4000-8000-000000000032'
) command;
select extensions.is(
  (
    select application.status || ':' || application.status_reason
    from public.finance_applications application
    where application.id = (
      select finance_application_id from pg_temp.finance_results
      where phase = 'finance-blocked-create'
    )
  ),
  'declined:Lender declined the external application',
  'adverse finance outcome preserves its required reason'
);

insert into pg_temp.finance_results
select 'finance-cancel-create', command.*
from app.m3_create_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-cancel-create',
  (select deal_id from pg_temp.deal_results where phase = 'finance-deal'),
  '84020000-0000-4000-8000-000000000002',
  '84020000-0000-4000-8000-000000000003',
  '900000', 'CAD', null, null, null, null,
  'request-finance-cancel-create',
  '84060000-0000-4000-8000-000000000033'
) command;
select extensions.throws_ok(
  $$
    select * from app.m3_transition_finance_application(
      '10000000-0000-4000-8000-000000000001',
      'm3-finance-cancel-no-reason',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-cancel-create'),
      1, 'cancelled', null, 'request-finance-cancel-no-reason',
      '84060000-0000-4000-8000-000000000034'
    )
  $$,
  '23514',
  'finance transition reason is required',
  'finance cancellation requires a bounded reason'
);
insert into pg_temp.finance_results
select 'finance-cancelled', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-finance-cancel-001',
  (select finance_application_id from pg_temp.finance_results
    where phase = 'finance-cancel-create'),
  1, 'cancelled', 'Customer withdrew the external application',
  'request-finance-cancel-001',
  '84060000-0000-4000-8000-000000000035'
) command;
select extensions.is(
  (
    select pg_catalog.string_agg(
      application.status, ',' order by application.status
    )
    from app.m3_list_finance_applications(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'finance-deal')
    ) application
  ),
  'cancelled,declined,funded',
  'bounded finance list exposes only safe lifecycle summary fields'
);

reset role;
select extensions.ok(
  not exists (
    select 1
    from pg_temp.trade_results result
    where result.phase not like '%replay'
      and (
        not exists (
          select 1 from public.audit_events audit
          where audit.id = result.audit_event_id
            and audit.workspace_id = '10000000-0000-4000-8000-000000000001'
        )
        or not exists (
          select 1 from public.outbox_events event
          where event.id = result.outbox_event_id
            and event.aggregate_id = result.deal_id
            and event.aggregate_version = result.aggregate_version
        )
      )
  ) and not exists (
    select 1
    from pg_temp.finance_results result
    join public.finance_applications application
      on application.id = result.finance_application_id
    where result.phase not like '%replay'
      and (
        not exists (
          select 1 from public.audit_events audit
          where audit.id = result.audit_event_id
            and audit.workspace_id = application.workspace_id
        )
        or not exists (
          select 1 from public.outbox_events event
          where event.id = result.outbox_event_id
            and event.aggregate_id = application.deal_id
            and event.aggregate_version = result.aggregate_version
        )
      )
  ) and not exists (
    select 1
    from pg_temp.condition_results result
    join public.finance_applications application
      on application.id = result.finance_application_id
    where result.phase not like '%replay'
      and (
        not exists (
          select 1 from public.audit_events audit
          where audit.id = result.audit_event_id
        )
        or not exists (
          select 1 from public.outbox_events event
          where event.id = result.outbox_event_id
            and event.aggregate_id = application.deal_id
            and event.aggregate_version = result.aggregate_version
        )
      )
  ),
  'T-AUD-001 every tested write returns matching audit and outbox evidence'
);
select extensions.ok(
  not exists (
    select 1 from public.outbox_events event
    where event.aggregate_id in (
      select deal_id from pg_temp.deal_results
      where phase in ('trade-deal', 'finance-deal')
    )
      and event.payload::text like '%External lender record only%'
  )
  and not exists (
    select 1 from public.outbox_events event
    where event.aggregate_id = (
      select deal_id from pg_temp.deal_results where phase = 'finance-deal'
    )
      and event.event_name ~ '(provider|credit_pull|schedule|servicing)'
  ),
  'outbox events contain no notes, provider calls, credit pulls, or servicing effects'
);

reset role;
select extensions.throws_ok(
  $$
    delete from public.trade_ins
    where id = (
      select trade_in_id from pg_temp.trade_results where phase = 'trade-create'
    )
  $$,
  '55000',
  'hard delete is prohibited for trade_ins',
  'trade-in history cannot be hard deleted'
);
select extensions.throws_ok(
  $$
    delete from public.finance_applications
    where id = (
      select finance_application_id from pg_temp.finance_results
      where phase = 'finance-create'
    )
  $$,
  '55000',
  'hard delete is prohibited for finance_applications',
  'finance application history cannot be hard deleted'
);
select extensions.throws_ok(
  $$
    update public.finance_application_conditions
    set satisfied_at = pg_catalog.statement_timestamp()
    where id = (
      select condition_id from pg_temp.condition_results
      where phase = 'condition-unsatisfied'
    )
  $$,
  '55000',
  'finance condition versions are immutable except controlled replacement',
  'finance condition evidence rejects direct mutation outside replacement'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.trade_ins trade_in
    where trade_in.workspace_id = '10000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'T-TEN-001 forced RLS hides another workspace trade-ins'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.finance_applications application
    where application.workspace_id = '10000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'T-TEN-001 forced RLS hides another workspace finance applications'
);
select extensions.throws_ok(
  $$
    select * from app.m3_list_trade_ins(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'trade-deal')
    )
  $$,
  '42501',
  'active deals entitlement, membership, and permission are required',
  'cross-workspace trade-in read RPC fails closed'
);
select extensions.throws_ok(
  $$
    select * from app.m3_get_finance_application(
      '10000000-0000-4000-8000-000000000001',
      (select finance_application_id from pg_temp.finance_results
        where phase = 'finance-create')
    )
  $$,
  '42501',
  'active deals entitlement, membership, and permission are required',
  'cross-workspace finance detail RPC fails closed'
);

reset role;
select * from extensions.finish();
rollback;
