-- VYN-DEAL-001, VYN-WF-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001,
-- VYN-JOB-001, VYN-API-001, STD-DEAL-001
-- M3-DEAL-AC-001, M3-DEAL-AC-002, M3-DEAL-AC-004
-- T-DEAL-001, T-TEN-001, T-RBAC-001, T-AUD-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(75);

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
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
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
create temporary table pg_temp.participant_results (
  phase text primary key,
  participant_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.inventory_results (
  phase text primary key,
  inventory_link_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.line_item_results (
  phase text primary key,
  line_item_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.line_item_update_results (
  phase text primary key,
  line_item_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  line_item_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.transition_results (
  phase text primary key,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  workflow_event_id uuid,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
grant all on
  pg_temp.deal_results,
  pg_temp.participant_results,
  pg_temp.inventory_results,
  pg_temp.line_item_results,
  pg_temp.line_item_update_results,
  pg_temp.transition_results
to authenticated, service_role;

select extensions.has_table('public', 'deal_type_definitions', 'deal type definitions exist');
select extensions.has_table('public', 'deal_type_versions', 'deal type versions exist');
select extensions.has_table('public', 'deal_line_items', 'exact deal line items exist');
select extensions.has_table('public', 'deal_command_receipts', 'actor-scoped deal receipts exist');

select extensions.has_function(
  'app', 'm3_create_deal',
  array['uuid','text','text','text','uuid','uuid','uuid','uuid','text','text','uuid'],
  'configured deal create command exists'
);
select extensions.has_function(
  'app', 'm3_update_deal',
  array['uuid','text','uuid','bigint','uuid','uuid','uuid','text','boolean','text','uuid'],
  'safe deal update command exists'
);
select extensions.has_function(
  'app', 'm3_transition_deal',
  array['uuid','text','uuid','bigint','text','text','text','uuid'],
  'atomic deal transition command exists'
);
select extensions.has_function(
  'app', 'm3_add_deal_participant',
  array['uuid','text','uuid','bigint','uuid','text','boolean','text','uuid'],
  'participant link command exists'
);
select extensions.has_function(
  'app', 'm3_release_deal_participant',
  array['uuid','text','uuid','bigint','uuid','text','uuid'],
  'participant release command exists'
);
select extensions.has_function(
  'app', 'm3_add_deal_inventory',
  array['uuid','text','uuid','bigint','uuid','text','text','text','jsonb','text','uuid'],
  'inventory link command exists'
);
select extensions.has_function(
  'app', 'm3_release_deal_inventory',
  array['uuid','text','uuid','bigint','uuid','text','uuid'],
  'inventory release command exists'
);
select extensions.has_function(
  'app', 'm3_add_deal_line_item',
  array[
    'uuid','text','uuid','bigint','text','text','text','text','text','text',
    'text','text','integer','text','text','text','uuid'
  ],
  'exact line item create command exists'
);
select extensions.has_function(
  'app', 'm3_update_deal_line_item',
  array[
    'uuid','text','uuid','bigint','uuid','bigint','text','text','text','text',
    'text','text','text','integer','text','text','text','uuid'
  ],
  'versioned line item update command exists'
);
select extensions.has_function(
  'app', 'm3_list_deals',
  array['uuid','integer','timestamp with time zone','uuid','text','uuid'],
  'bounded safe deal list projection exists'
);
select extensions.has_function(
  'app', 'm3_get_deal',
  array['uuid','uuid'],
  'strict deal detail projection exists'
);
select extensions.has_function(
  'app', 'm3_list_deal_participants',
  array['uuid','uuid','integer','timestamp with time zone','uuid'],
  'bounded deal participant projection exists'
);
select extensions.has_function(
  'app', 'm3_list_deal_inventory',
  array['uuid','uuid','integer','timestamp with time zone','uuid'],
  'bounded deal inventory projection exists'
);
select extensions.has_function(
  'app', 'm3_list_deal_line_items',
  array['uuid','uuid','integer','integer','uuid'],
  'bounded exact line-item projection exists'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'deal_type_definitions', 'deal_type_versions',
        'deal_line_items', 'deal_command_receipts'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  4::bigint,
  'T-TEN-001 every new deal table has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.deal_type_versions', 'INSERT')
    and not pg_catalog.has_table_privilege('authenticated', 'public.deal_line_items', 'INSERT')
    and not pg_catalog.has_table_privilege('authenticated', 'public.deal_command_receipts', 'SELECT'),
  'T-RBAC-001 browsers cannot bypass config, command, or receipt boundaries'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'deals'
      and column_info.column_name in (
        'deal_type_definition_id', 'deal_type_version_id',
        'workflow_version_id', 'workflow_instance_id', 'workflow_state_key',
        'location_id', 'legal_entity_id'
      )
      and column_info.is_nullable = 'NO'
  ),
  7::bigint,
  'every deal pins exact configuration, workflow, location, and legal context'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_indexes index_info
    where index_info.schemaname = 'public'
      and index_info.indexname = 'deal_inventory_units_active_sold_uidx'
      and index_info.indexdef like '%WHERE ((role_key = ''sold''%status = ''active''%'
  ),
  'active sold-unit uniqueness remains database-enforced'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_indexes index_info
    where index_info.schemaname = 'public'
      and index_info.indexname = 'deal_type_versions_active_definition_uidx'
      and index_info.indexdef like '%WHERE (status = ''active''%'
  ),
  'one active version per workspace deal type is database-enforced'
);
select extensions.is(
  app.parse_deal_minor_units('9223372036854775807'),
  9223372036854775807::bigint,
  'maximum bigint minor units remain exact'
);
select extensions.is(
  app.parse_deal_minor_units('-9223372036854775808'),
  (-9223372036854775807::bigint - 1),
  'minimum bigint minor units remain exact'
);
select extensions.throws_ok(
  $$select app.parse_deal_minor_units('01')$$,
  '22023',
  'money minor units must be a canonical integer string',
  'non-canonical money strings fail closed'
);
select extensions.throws_ok(
  $$select app.parse_deal_minor_units('9223372036854775808')$$,
  '22003',
  'money minor units exceed bigint range',
  'out-of-range money strings fail before bigint conversion'
);
select extensions.is(
  app.deal_type_configuration_artifact(
    'fixture.cash', '1.0.0', 1,
    '{"en":"Fixture cash","fr":"Vente comptant fictive"}',
    '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{}}',
    '[]', '{"required":[],"optional":[]}',
    array['seller','buyer'], array['trade_in','sold'],
    '{"finance_mode":"none","money_mode":"one_time"}',
    'retail_deal_standard', '1.0.0', repeat('a', 64)
  ) -> 'allowedParticipantRoles',
  '["buyer","seller"]'::jsonb,
  'deal type checksum artifact canonicalizes participant-role ordering'
);
select extensions.is(
  app.deal_type_configuration_artifact(
    'fixture.cash', '1.0.0', 1,
    '{"en":"Fixture cash","fr":"Vente comptant fictive"}',
    '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{}}',
    '[]', '{"required":[],"optional":[]}',
    array['seller','buyer'], array['trade_in','sold'],
    '{"finance_mode":"none","money_mode":"one_time"}',
    'retail_deal_standard', '1.0.0', repeat('a', 64)
  ) -> 'optionLabels' -> 'participant_roles' -> 'buyer',
  '{"en":"Buyer","fr":"Acheteur"}'::jsonb,
  'deal type checksum artifact preserves versioned bilingual option labels'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.require_deal_permission(uuid,text)'::pg_catalog.regprocedure
  ) like '%is_feature_entitled%''deals''%'
  and pg_catalog.pg_get_functiondef(
    'app.require_deal_permission(uuid,text)'::pg_catalog.regprocedure
  ) not like '%custom_workflows%',
  'ordinary deal commands require deals entitlement without custom-workflow coupling'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.m3_transition_deal(uuid,text,uuid,bigint,text,text,text,uuid)'::pg_catalog.regprocedure
  ) like '%behavior_flags @> ''{"cancellation":true}''::jsonb%'
  and pg_catalog.pg_get_functiondef(
    'app.m3_transition_deal(uuid,text,uuid,bigint,text,text,text,uuid)'::pg_catalog.regprocedure
  ) not like '%target_state.key = ''cancelled''%',
  'configured cancellation semantics never depend on a workflow state key'
);

insert into public.deal_type_definitions (
  id, workspace_id, key, status, created_by
) values (
  '83800000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture.cash', 'active',
  '31000000-0000-4000-8000-000000000001'
);

insert into public.deal_type_versions (
  id, workspace_id, deal_type_definition_id, version, revision,
  schema_version, labels, option_labels, sections, field_schema,
  allowed_participant_roles, allowed_inventory_roles, behavior_flags,
  workflow_version_id, status, checksum, source, created_by
)
select
  '83810000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '83800000-0000-4000-8000-000000000001',
  '1.0.0', 1, 1,
  '{"en":"Fixture cash","fr":"Vente comptant fictive"}'::jsonb,
  '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{"deposit":{"en":"Deposit","fr":"Dépôt"},"receipt":{"en":"Receipt","fr":"Encaissement"}}}'::jsonb,
  '[]'::jsonb,
  '{"required":["buyer_party_id","sold_inventory_unit_id","currency_code"],"optional":["notes"]}'::jsonb,
  array['buyer','seller']::text[],
  array['sold','trade_in']::text[],
  '{"inventory_direction":"outbound","inventory_creation":"none","finance_mode":"none","money_mode":"one_time","one_time_event_types":["deposit","receipt"]}'::jsonb,
  workflow_version.id,
  'draft',
  app.deal_type_configuration_checksum(
    'fixture.cash', '1.0.0', 1,
    '{"en":"Fixture cash","fr":"Vente comptant fictive"}'::jsonb,
    '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{"deposit":{"en":"Deposit","fr":"Dépôt"},"receipt":{"en":"Receipt","fr":"Encaissement"}}}'::jsonb,
    '[]'::jsonb,
    '{"required":["buyer_party_id","sold_inventory_unit_id","currency_code"],"optional":["notes"]}'::jsonb,
    array['buyer','seller']::text[],
    array['sold','trade_in']::text[],
    '{"inventory_direction":"outbound","inventory_creation":"none","finance_mode":"none","money_mode":"one_time","one_time_event_types":["deposit","receipt"]}'::jsonb,
    workflow_definition.key::text,
    workflow_version.version,
    workflow_version.checksum
  ),
  'configuration',
  '31000000-0000-4000-8000-000000000001'
from public.workflow_definitions workflow_definition
join public.workflow_versions workflow_version
  on workflow_version.workspace_id = workflow_definition.workspace_id
 and workflow_version.workflow_definition_id = workflow_definition.id
where workflow_definition.workspace_id = '10000000-0000-4000-8000-000000000001'
  and workflow_definition.key = 'retail_deal_standard'
  and workflow_version.version = '1.0.0'
  and workflow_version.status = 'active';

select extensions.throws_ok(
  $$
    update public.deal_type_versions
    set option_labels = option_labels #- '{participant_roles,seller}'
    where id = '83810000-0000-4000-8000-000000000001'
  $$,
  '23514',
  'deal option labels must exactly match configured keys',
  'deal type option labels fail closed when a configured key is missing'
);

update public.deal_type_versions
set status = 'active', activated_at = pg_catalog.statement_timestamp()
where id = '83810000-0000-4000-8000-000000000001';

select extensions.is(
  (
    select status from public.deal_type_versions
    where id = '83810000-0000-4000-8000-000000000001'
  ),
  'active',
  'exact configured deal type activates against its pinned active workflow'
);
select extensions.throws_ok(
  $$
    update public.deal_type_versions
    set labels = '{"en":"Changed","fr":"Change"}'
    where id = '83810000-0000-4000-8000-000000000001'
  $$,
  '23514',
  'deal type lifecycle transition is not allowed',
  'activated deal type values are immutable'
);

insert into public.legal_entities (
  id, workspace_id, key, legal_names, display_names, status, version,
  created_by
) values (
  '83815000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture.primary',
  '{"en":"Fixture Legal Entity Inc.","fr":"Entite juridique fictive inc."}',
  '{"en":"Fixture Legal Entity","fr":"Entite juridique fictive"}',
  'active', 1,
  '31000000-0000-4000-8000-000000000001'
);

insert into public.parties (
  id, workspace_id, party_type, display_name, status, version,
  idempotency_key, command_fingerprint, created_by
) values
  (
    '83820000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'person', 'Fixture buyer', 'active', 1,
    'm3-deal-party-001', repeat('1', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '83820000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'person', 'Other workspace buyer', 'active', 1,
    'm3-deal-party-002', repeat('2', 64),
    '32000000-0000-4000-8000-000000000001'
  );

set constraints all deferred;
insert into public.stock_number_allocations (
  id, workspace_id, definition_id, inventory_unit_id, sequence_value,
  formatted_value, idempotency_key, command_fingerprint, allocated_by
) values (
  '83830000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  '83850000-0000-4000-8000-000000000001',
  838001, 'N-838001', 'm3-deal-stock-001', repeat('3', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.vehicles (
  id, workspace_id, vin, model_year, make, model
) values (
  '83840000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '1HGCM82633A838001', 2024, 'Fixture', 'Deal vehicle'
);
insert into public.inventory_units (
  id, workspace_id, vehicle_id, stock_allocation_id, stock_number,
  status, location_id, currency_code, advertised_price_minor, created_by
) values (
  '83850000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '83840000-0000-4000-8000-000000000001',
  '83830000-0000-4000-8000-000000000001',
  'N-838001', 'draft', '73000000-0000-4000-8000-000000000001',
  'CAD', 2499999,
  '31000000-0000-4000-8000-000000000001'
);
set constraints all immediate;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.deal_results
select 'create', command.*
from app.m3_create_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-create-deal-001', 'fixture.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001',
  (select legal_entity.id from public.legal_entities legal_entity
    where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      and legal_entity.status = 'active'
    order by legal_entity.id limit 1),
  '41000000-0000-4000-8000-000000000001',
  null, 'Synthetic deal', 'request-deal-001',
  '83860000-0000-4000-8000-000000000001'
) command;

insert into pg_temp.deal_results
select 'create-replay', command.*
from app.m3_create_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-create-deal-001', 'fixture.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001',
  (select legal_entity.id from public.legal_entities legal_entity
    where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      and legal_entity.status = 'active'
    order by legal_entity.id limit 1),
  '41000000-0000-4000-8000-000000000001',
  null, 'Synthetic deal', 'request-deal-001-replay',
  '83860000-0000-4000-8000-000000000001'
) command;

select extensions.ok(
  (select replayed from pg_temp.deal_results where phase = 'create-replay')
    and (select deal_id from pg_temp.deal_results where phase = 'create')
      = (select deal_id from pg_temp.deal_results where phase = 'create-replay'),
  'actor-idempotent create returns the original deal'
);
-- Receipts and inert outbox rows are intentionally service-only. Assert their
-- cardinality as the database owner, then restore the authenticated command
-- boundary for the remaining authorization checks.
reset role;
select extensions.is(
  (
    select pg_catalog.count(*) from public.deal_command_receipts receipt
    where receipt.deal_id = (
      select deal_id from pg_temp.deal_results where phase = 'create'
    ) and receipt.command_type = 'm3_create_deal'
  ),
  1::bigint,
  'create replay appends exactly one receipt'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.audit_events audit
    where audit.entity_id = (
      select deal_id from pg_temp.deal_results where phase = 'create'
    ) and audit.action = 'deal.created'
  ),
  1::bigint,
  'create replay appends exactly one audit event'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.outbox_events outbox
    where outbox.aggregate_id = (
      select deal_id from pg_temp.deal_results where phase = 'create'
    ) and outbox.event_name = 'deal.created'
  ),
  1::bigint,
  'create replay appends exactly one outbox event'
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.m3_create_deal(
      '10000000-0000-4000-8000-000000000001',
      'm3-create-deal-001', 'fixture.cash', 'USD',
      '73000000-0000-4000-8000-000000000001',
      (select legal_entity.id from public.legal_entities legal_entity
        where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
          and legal_entity.status = 'active' order by legal_entity.id limit 1),
      '41000000-0000-4000-8000-000000000001', null, 'Changed',
      'request-deal-mismatch', '83860000-0000-4000-8000-000000000001'
    )
  $$,
  '23505',
  'deal idempotency key was reused with different input',
  'same actor cannot reuse a create key with changed input'
);

-- M3-FIELD-AC-009: inventory-reference custom fields are present to workflow
-- guards only when the acting member can read inventory.
reset role;
insert into public.custom_field_definitions (
  id, workspace_id, entity_type, key, status, created_by
) values (
  '83870000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'deal', 'inventory_evidence', 'active',
  '31000000-0000-4000-8000-000000000001'
);
insert into public.custom_field_versions (
  id, workspace_id, custom_field_definition_id, version, value_type,
  labels, help_text, validation, default_value, options, required,
  visibility_permission_key, edit_permission_key, sensitive, searchable,
  section_key, status, checksum, created_by, activated_at
) values (
  '83871000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '83870000-0000-4000-8000-000000000001',
  1, 'inventory_reference',
  '{"en":"Inventory evidence","fr":"Preuve inventaire"}',
  '{"en":"Authorized inventory reference","fr":"Reference inventaire autorisee"}',
  '{}', null, '[]', false, null, 'deals.update', false, false,
  'deal.inventory', 'active', pg_catalog.repeat('7', 64),
  '31000000-0000-4000-8000-000000000001',
  timestamptz '2026-07-16 21:45:00+00'
);
insert into public.custom_field_values (
  id, workspace_id, custom_field_definition_id, custom_field_version_id,
  entity_type, entity_id, value_type, is_set, reference_id, version,
  created_by, updated_by
) values (
  '83872000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '83870000-0000-4000-8000-000000000001',
  '83871000-0000-4000-8000-000000000001',
  'deal', (select deal_id from pg_temp.deal_results where phase = 'create'),
  'inventory_reference', true, '83850000-0000-4000-8000-000000000001', 1,
  '31000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.is(
  app.deal_field_is_present(
    '10000000-0000-4000-8000-000000000001',
    (select deal_id from pg_temp.deal_results where phase = 'create'),
    'inventory_evidence'
  ),
  true,
  'an inventory-authorized actor can satisfy a deal requirement with an active inventory-reference field'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.is(
  app.deal_field_is_present(
    '10000000-0000-4000-8000-000000000001',
    (select deal_id from pg_temp.deal_results where phase = 'create'),
    'inventory_evidence'
  ),
  false,
  'a masked inventory-reference value fails a deal workflow requirement without disclosure'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.participant_results
select 'participant', command.*
from app.m3_add_deal_participant(
  '10000000-0000-4000-8000-000000000001',
  'm3-add-participant-001',
  (select deal_id from pg_temp.deal_results where phase = 'create'),
  1, '83820000-0000-4000-8000-000000000001', 'buyer', true,
  'request-participant-001', '83860000-0000-4000-8000-000000000002'
) command;
select extensions.is(
  (select aggregate_version from pg_temp.participant_results where phase = 'participant'),
  2::bigint,
  'participant link atomically advances the aggregate version'
);
select extensions.throws_ok(
  $$
    select * from app.m3_add_deal_participant(
      '10000000-0000-4000-8000-000000000001',
      'm3-add-participant-cross',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      2, '83820000-0000-4000-8000-000000000002', 'buyer', false,
      'request-participant-cross', '83860000-0000-4000-8000-000000000003'
    )
  $$,
  '23514',
  'active workspace party is required',
  'cross-workspace participant links fail closed'
);

select extensions.throws_ok(
  $$
    select * from app.m3_add_deal_inventory(
      '10000000-0000-4000-8000-000000000001',
      'm3-add-inventory-role',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      2, '83850000-0000-4000-8000-000000000001', 'leased',
      null, null, '{}', 'request-inventory-role',
      '83860000-0000-4000-8000-000000000004'
    )
  $$,
  '23514',
  'inventory role is not allowed by the pinned deal type',
  'deal type inventory-role allowlist fails closed'
);
insert into pg_temp.inventory_results
select 'inventory', command.*
from app.m3_add_deal_inventory(
  '10000000-0000-4000-8000-000000000001',
  'm3-add-inventory-001',
  (select deal_id from pg_temp.deal_results where phase = 'create'),
  2, '83850000-0000-4000-8000-000000000001', 'sold',
  '2499999', 'CAD', '{"source":"fixture"}',
  'request-inventory-001', '83860000-0000-4000-8000-000000000005'
) command;
select extensions.is(
  (select aggregate_version from pg_temp.inventory_results where phase = 'inventory'),
  3::bigint,
  'inventory link atomically advances the aggregate version'
);
select extensions.is(
  (
    select amount_minor::text || ':' || currency_code::text
    from public.deal_inventory_units
    where id = (select inventory_link_id from pg_temp.inventory_results where phase = 'inventory')
  ),
  '2499999:CAD',
  'inventory link preserves exact amount and matching currency'
);

select extensions.throws_ok(
  $$
    select * from app.m3_add_deal_line_item(
      '10000000-0000-4000-8000-000000000001',
      'm3-add-line-currency',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      3, 'vehicle.price', 'vehicle', 'Vehicle price', '1.000000',
      '2499999', 'USD', null, 'delivery', 10, 'operator', null,
      'request-line-currency', '83860000-0000-4000-8000-000000000006'
    )
  $$,
  '23514',
  'line item currency must match deal currency',
  'cross-currency line items fail closed'
);
insert into pg_temp.line_item_results
select 'line-item', command.*
from app.m3_add_deal_line_item(
  '10000000-0000-4000-8000-000000000001',
  'm3-add-line-001',
  (select deal_id from pg_temp.deal_results where phase = 'create'),
  3, 'vehicle.price', 'vehicle', 'Vehicle price', '1.000000',
  '2499999', 'CAD', null, 'delivery', 10, 'operator', null,
  'request-line-001', '83860000-0000-4000-8000-000000000007'
) command;
select extensions.is(
  (
    select quantity_text || ':' || unit_amount_minor::text || ':' || currency_code::text
    from public.deal_line_items
    where id = (select line_item_id from pg_temp.line_item_results where phase = 'line-item')
  ),
  '1.000000:2499999:CAD',
  'canonical quantity string and bigint amount round-trip exactly'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_deal_line_item(
      '10000000-0000-4000-8000-000000000001',
      'm3-update-line-stale',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      3,
      (select line_item_id from pg_temp.line_item_results where phase = 'line-item'),
      1, 'vehicle', 'Vehicle price', '1', '2500000', 'CAD',
      null, 'delivery', 10, 'operator', null,
      'request-line-stale', '83860000-0000-4000-8000-000000000008'
    )
  $$,
  '40001',
  'stale deal version',
  'stale aggregate line-item updates fail before mutation'
);
insert into pg_temp.line_item_update_results
select 'line-item-update', command.*
from app.m3_update_deal_line_item(
  '10000000-0000-4000-8000-000000000001',
  'm3-update-line-001',
  (select deal_id from pg_temp.deal_results where phase = 'create'),
  4,
  (select line_item_id from pg_temp.line_item_results where phase = 'line-item'),
  1, 'vehicle', 'Vehicle price', '1', '2500000', 'CAD',
  null, 'delivery', 10, 'operator', null,
  'request-line-001', '83860000-0000-4000-8000-000000000009'
) command;
select extensions.is(
  (select line_item_version from pg_temp.line_item_update_results where phase = 'line-item-update'),
  2::bigint,
  'line-item and aggregate optimistic versions advance together'
);
select extensions.is(
  (
    select
      (detail.available_transitions -> 0 ->> 'transitionKey') || ':'
        || (detail.available_transitions -> 0 ->> 'toStateKey')
    from app.m3_get_deal(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create')
    ) detail
  ),
  'draft__preparing:preparing',
  'deal detail exposes the permitted configured transition key and target state'
);

insert into pg_temp.transition_results
select 'prepare', command.*
from app.m3_transition_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-transition-prepare',
  (select deal_id from pg_temp.deal_results where phase = 'create'),
  5, 'draft__preparing', null,
  'request-transition-prepare', '83860000-0000-4000-8000-000000000010'
) command;
insert into pg_temp.transition_results
select 'prepare-replay', command.*
from app.m3_transition_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-transition-prepare',
  (select deal_id from pg_temp.deal_results where phase = 'create'),
  5, 'draft__preparing', null,
  'request-transition-prepare-replay', '83860000-0000-4000-8000-000000000010'
) command;
select extensions.ok(
  (select replayed from pg_temp.transition_results where phase = 'prepare-replay')
    and (select workflow_event_id from pg_temp.transition_results where phase = 'prepare')
      = (select workflow_event_id from pg_temp.transition_results where phase = 'prepare-replay'),
  'transition replay returns one immutable workflow event'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.workflow_events workflow_event
    where workflow_event.entity_id = (
      select deal_id from pg_temp.deal_results where phase = 'create'
    ) and workflow_event.to_state_key = 'preparing'
  ),
  1::bigint,
  'transition replay appends exactly one workflow event'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.audit_events audit
    where audit.entity_id = (
      select deal_id from pg_temp.deal_results where phase = 'create'
    ) and audit.action = 'deal.transitioned'
  ),
  1::bigint,
  'transition replay appends exactly one audit event'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.outbox_events outbox
    where outbox.aggregate_id = (
      select deal_id from pg_temp.deal_results where phase = 'create'
    ) and outbox.event_name = 'deal.transitioned'
  ),
  1::bigint,
  'transition replay appends exactly one inert outbox event'
);
select extensions.throws_ok(
  $$
    select * from app.m3_release_deal_participant(
      '10000000-0000-4000-8000-000000000001',
      'm3-release-participant-nondraft',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      6,
      (select participant_id from pg_temp.participant_results where phase = 'participant'),
      'request-release-participant-nondraft',
      '83860000-0000-4000-8000-000000000016'
    )
  $$,
  '55000',
  'deal participant can only be released while draft',
  'participant links cannot be released after the deal leaves draft'
);
select extensions.throws_ok(
  $$
    select * from app.m3_release_deal_inventory(
      '10000000-0000-4000-8000-000000000001',
      'm3-release-inventory-nondraft',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      6,
      (select inventory_link_id from pg_temp.inventory_results where phase = 'inventory'),
      'request-release-inventory-nondraft',
      '83860000-0000-4000-8000-000000000017'
    )
  $$,
  '55000',
  'deal inventory link can only be released while draft',
  'inventory links cannot be released after the deal leaves draft'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_deal_line_item(
      '10000000-0000-4000-8000-000000000001',
      'm3-update-line-nondraft',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      6,
      (select line_item_id from pg_temp.line_item_results where phase = 'line-item'),
      2, 'vehicle', 'Vehicle price', '1', '2500000', 'CAD',
      null, 'delivery', 10, 'operator', null,
      'request-update-line-nondraft',
      '83860000-0000-4000-8000-000000000018'
    )
  $$,
  '55000',
  'deal line item can only be updated while draft',
  'line items cannot be overwritten after the deal leaves draft'
);
select extensions.throws_ok(
  $$
    select * from app.m3_transition_deal(
      '10000000-0000-4000-8000-000000000001',
      'm3-transition-cancel-missing-reason',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      6, 'preparing__cancelled', null,
      'request-transition-cancel-no-reason',
      '83860000-0000-4000-8000-000000000011'
    )
  $$,
  '23514',
  'deal transition reason is required',
  'reason-required deal transitions fail closed'
);
insert into pg_temp.transition_results
select 'cancel', command.*
from app.m3_transition_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-transition-cancel',
  (select deal_id from pg_temp.deal_results where phase = 'create'),
  6, 'preparing__cancelled', 'Customer withdrew',
  'request-transition-cancel', '83860000-0000-4000-8000-000000000012'
) command;
select extensions.is(
  (
    select lifecycle_status || ':' || status || ':' || workflow_state_key
    from public.deals
    where id = (select deal_id from pg_temp.deal_results where phase = 'create')
  ),
  'completed:closed:cancelled',
  'terminal transition synchronizes deal and pinned workflow lifecycle'
);
select extensions.throws_ok(
  $$
    select * from app.m3_update_deal(
      '10000000-0000-4000-8000-000000000001',
      'm3-update-completed',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      7, null, null, null, 'No change', false,
      'request-update-completed', '83860000-0000-4000-8000-000000000013'
    )
  $$,
  '55000',
  'completed deal cannot be updated',
  'completed deals reject ordinary updates'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from app.m3_list_deals(
      '10000000-0000-4000-8000-000000000001', 50, null, null,
      'closed', null
    ) listed
    where listed.deal_id = (
      select deal_id from pg_temp.deal_results where phase = 'create'
    )
      and listed.active_participant_count = 1
      and listed.active_inventory_count = 1
      and listed.active_line_item_count = 1
  ),
  1::bigint,
  'safe list projection returns bounded aggregate counts and pinned labels'
);
select extensions.is(
  (
    select
      detail.deal_type_key || ':' || detail.deal_type_version || ':'
        || detail.deal_type_revision::text || ':' || detail.currency_code
        || ':' || detail.lifecycle_status || ':' || detail.state_key
    from app.m3_get_deal(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create')
    ) detail
  ),
  'fixture.cash:1.0.0:1:CAD:completed:cancelled',
  'deal detail returns exact pinned configuration and lifecycle context'
);
select extensions.ok(
  (
    select
      detail.deal_type_checksum ~ '^[a-f0-9]{64}$'
      and detail.deal_type_field_schema ? 'required'
      and detail.deal_type_behavior_flags ->> 'finance_mode' = 'none'
    from app.m3_get_deal(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create')
    ) detail
  ),
  'deal detail exposes exact declarative config without calculated or tax output'
);
select extensions.ok(
  (
    select
      detail.participant_role_options = '[{"key":"buyer","labels":{"en":"Buyer","fr":"Acheteur"}},{"key":"seller","labels":{"en":"Seller","fr":"Vendeur"}}]'::jsonb
      and detail.inventory_role_options = '[{"key":"sold","labels":{"en":"Sale vehicle","fr":"Véhicule vendu"}},{"key":"trade_in","labels":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}}]'::jsonb
      and detail.one_time_event_type_options = '[{"key":"deposit","labels":{"en":"Deposit","fr":"Dépôt"}},{"key":"receipt","labels":{"en":"Receipt","fr":"Encaissement"}}]'::jsonb
    from app.m3_get_deal(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create')
    ) detail
  ),
  'deal detail exposes ordered bilingual options from its pinned configuration version'
);
select extensions.is(
  (
    select pg_catalog.jsonb_array_length(detail.available_transitions)
    from app.m3_get_deal(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create')
    ) detail
  ),
  0,
  'terminal deal detail exposes no available transitions'
);
select extensions.is(
  (
    select
      participant.party_display_name || ':' || participant.role_key || ':'
        || participant.status
    from app.m3_list_deal_participants(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      100, null, null
    ) participant
  ),
  'Fixture buyer:buyer:active',
  'bounded participant read returns the workspace CRM projection'
);
select extensions.is(
  (
    select
      inventory.stock_number || ':' || inventory.role_key || ':'
        || inventory.amount_minor || ':' || inventory.currency_code
    from app.m3_list_deal_inventory(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      100, null, null
    ) inventory
  ),
  'N-838001:sold:2499999:CAD',
  'bounded inventory read preserves exact linked minor units as text'
);
select extensions.is(
  (
    select
      line_item.key || ':' || line_item.quantity || ':'
        || line_item.unit_amount_minor || ':' || line_item.currency_code || ':'
        || line_item.version::text
    from app.m3_list_deal_line_items(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      100, null, null
    ) line_item
  ),
  'vehicle.price:1:2500000:CAD:2',
  'bounded line-item read returns canonical quantity and minor-unit text'
);
select extensions.throws_ok(
  $$
    select * from app.m3_list_deal_participants(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      100, pg_catalog.statement_timestamp(), null
    )
  $$,
  '22023',
  'deal participant cursor is incomplete',
  'participant cursor pairs fail closed when incomplete'
);
select extensions.throws_ok(
  $$
    select * from app.m3_list_deal_inventory(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      100, null, '83850000-0000-4000-8000-000000000001'
    )
  $$,
  '22023',
  'deal inventory cursor is incomplete',
  'inventory cursor pairs fail closed when incomplete'
);
select extensions.throws_ok(
  $$
    select * from app.m3_list_deal_line_items(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'create'),
      100, -1, '83850000-0000-4000-8000-000000000001'
    )
  $$,
  '22023',
  'deal line-item cursor is invalid',
  'line-item cursors reject invalid sort positions'
);

insert into pg_temp.deal_results
select 'conflict-deal', command.*
from app.m3_create_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-create-deal-conflict', 'fixture.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001',
  (select legal_entity.id from public.legal_entities legal_entity
    where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      and legal_entity.status = 'active' order by legal_entity.id limit 1),
  '41000000-0000-4000-8000-000000000001', null, null,
  'request-deal-conflict', '83860000-0000-4000-8000-000000000014'
) command;
select extensions.throws_ok(
  $$
    select * from app.m3_add_deal_inventory(
      '10000000-0000-4000-8000-000000000001',
      'm3-add-inventory-conflict',
      (select deal_id from pg_temp.deal_results where phase = 'conflict-deal'),
      1, '83850000-0000-4000-8000-000000000001', 'sold',
      null, null, '{}', 'request-inventory-conflict',
      '83860000-0000-4000-8000-000000000015'
    )
  $$,
  '23505',
  'inventory unit already has an active sold deal link',
  'active sold-unit conflicts fail under the inventory row lock and unique index'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.is(
  (
    select pg_catalog.count(*) from public.deals deal
    where deal.workspace_id = '10000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'T-TEN-001 direct RLS reads hide another workspace deals'
);
select extensions.throws_ok(
  $$
    select * from app.m3_list_deals(
      '10000000-0000-4000-8000-000000000001', 50, null, null, null, null
    )
  $$,
  '42501',
  'active deals entitlement, membership, and permission are required',
  'cross-workspace read RPC fails closed'
);

reset role;
select * from extensions.finish();
rollback;
