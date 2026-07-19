-- VYN-CRM-001, VYN-DEAL-001, VYN-FIN-001, VYN-PAY-001,
-- VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-JOB-001, VYN-API-001
-- M3-CRM-AC-004, M3-EXIT-AC-001, M3-DEAL-AC-001..004, M3-FIN-AC-001,
-- M3-PAY-AC-001..003 / T-CRM-002, T-DEAL-001, T-FIN-001,
-- T-PAY-001..003, T-TEN-001, T-AUD-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(32);

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  assurance text default 'aal2',
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
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', case when assurance = 'aal2' then 'totp' else 'password' end,
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint - factor_age_seconds
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

create temporary table pg_temp.party_results (
  phase text primary key,
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.lead_results (
  phase text primary key,
  lead_id uuid,
  aggregate_version bigint,
  state_key text,
  workflow_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.conversion_results (
  phase text primary key,
  lead_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
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
create temporary table pg_temp.payment_results (
  phase text primary key,
  payment_transaction_id uuid,
  status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.correction_results (
  phase text primary key,
  correction_transaction_id uuid,
  original_transaction_id uuid,
  remaining_minor text,
  status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
grant all on
  pg_temp.party_results,
  pg_temp.lead_results,
  pg_temp.conversion_results,
  pg_temp.participant_results,
  pg_temp.inventory_results,
  pg_temp.line_item_results,
  pg_temp.finance_results,
  pg_temp.condition_results,
  pg_temp.payment_results,
  pg_temp.correction_results
to authenticated, service_role;

-- 1. The journey is driven by immutable behavior flags and deal configuration.
select extensions.ok(
  exists (
    select 1
    from public.workflow_definitions definition
    join public.workflow_versions version
      on version.workspace_id = definition.workspace_id
     and version.workflow_definition_id = definition.id
    join public.workflow_states state
      on state.workspace_id = version.workspace_id
     and state.workflow_version_id = version.id
    where definition.workspace_id = '10000000-0000-4000-8000-000000000001'
      and definition.key = 'lead_standard'
      and version.status = 'active'
      and state.behavior_flags @> '{"conversion_eligible":true}'::jsonb
  )
  and exists (
    select 1
    from public.workflow_definitions definition
    join public.workflow_versions version
      on version.workspace_id = definition.workspace_id
     and version.workflow_definition_id = definition.id
    join public.workflow_states state
      on state.workspace_id = version.workspace_id
     and state.workflow_version_id = version.id
    where definition.workspace_id = '10000000-0000-4000-8000-000000000001'
      and definition.key = 'lead_standard'
      and version.status = 'active'
      and state.behavior_flags @> '{"conversion_target":true}'::jsonb
  )
  and exists (
    select 1
    from public.deal_type_definitions definition
    join public.deal_type_versions version
      on version.workspace_id = definition.workspace_id
     and version.deal_type_definition_id = definition.id
    where definition.workspace_id = '10000000-0000-4000-8000-000000000001'
      and definition.key = 'retail.cash'
      and version.status = 'active'
      and version.behavior_flags @> pg_catalog.jsonb_build_object(
        'money_mode', 'one_time',
        'one_time_event_types', '["balance_received"]'::jsonb
      )
  )
  and exists (
    select 1
    from public.deal_type_definitions definition
    join public.deal_type_versions version
      on version.workspace_id = definition.workspace_id
     and version.deal_type_definition_id = definition.id
    where definition.workspace_id = '10000000-0000-4000-8000-000000000001'
      and definition.key = 'retail.third_party_financed'
      and version.status = 'active'
      and version.behavior_flags @> pg_catalog.jsonb_build_object(
        'finance_mode', 'external_lender_tracking',
        'money_mode', 'one_time',
        'one_time_event_types', '["lender_proceeds"]'::jsonb
      )
  ),
  'M3 exit paths are selected by active workflow and deal behavior flags'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.party_results
select 'cash-buyer', result.*
from app.m3_create_party(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-buyer', 'person', 'Exit Cash Buyer', 'en',
  'Cash', 'Buyer', null, null, null, null,
  'm3-exit-cash-buyer', '86000000-0000-4000-8000-000000000001'
) result;
insert into pg_temp.party_results
select 'finance-buyer', result.*
from app.m3_create_party(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-buyer', 'person', 'Exit Finance Buyer', 'fr',
  'Finance', 'Buyer', null, null, null, null,
  'm3-exit-finance-buyer', '86000000-0000-4000-8000-000000000002'
) result;
insert into pg_temp.party_results
select 'finance-lender', result.*
from app.m3_create_party(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-lender', 'organization', 'Exit Synthetic Lender', 'en',
  null, null, null, null, 'Exit Synthetic Lender Inc.', 'EXIT LENDER',
  'm3-exit-finance-lender', '86000000-0000-4000-8000-000000000003'
) result;
reset role;

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.party_results
select 'workspace-b-party', result.*
from app.m3_create_party(
  '20000000-0000-4000-8000-000000000002',
  'm3-exit-workspace-b', 'person', 'Exit Other Workspace Party', 'en',
  'Other', 'Workspace', null, null, null, null,
  'm3-exit-workspace-b', '86000000-0000-4000-8000-000000000004'
) result;
reset role;

-- 2. Parties are created only through the public application boundary.
select extensions.ok(
  (
    select pg_catalog.count(*) = 3
    from public.parties party
    where party.workspace_id = '10000000-0000-4000-8000-000000000001'
      and party.id in (
        select result.party_id
        from pg_temp.party_results result
        where result.phase in ('cash-buyer', 'finance-buyer', 'finance-lender')
      )
      and party.status = 'active'
      and party.version = 1
  )
  and (
    select pg_catalog.bool_and(
      result.aggregate_version = 1 and not result.replayed
    )
    from pg_temp.party_results result
    where result.phase in ('cash-buyer', 'finance-buyer', 'finance-lender')
  ),
  'both buyers and the external lender are active app-created workspace parties'
);

-- Inventory and ready legal-original rows are fixture prerequisites for which
-- Milestone 3 exposes no create/upload command. All business mutations below
-- continue through app RPCs.
set constraints all deferred;
insert into public.stock_number_allocations (
  id, workspace_id, definition_id, inventory_unit_id, sequence_value,
  formatted_value, idempotency_key, command_fingerprint, allocated_by
) values
  (
    '86330000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    '86350000-0000-4000-8000-000000000001',
    863301, 'N-863301', 'm3-exit-stock-cash', repeat('3', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '86330000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    '86350000-0000-4000-8000-000000000002',
    863302, 'N-863302', 'm3-exit-stock-finance', repeat('4', 64),
    '31000000-0000-4000-8000-000000000001'
  );
insert into public.vehicles (
  id, workspace_id, vin, model_year, make, model
) values
  (
    '86340000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '1HGCM82633A863301', 2025, 'Synthetic', 'Cash exit vehicle'
  ),
  (
    '86340000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '1HGCM82633A863302', 2025, 'Synthetic', 'Finance exit vehicle'
  );
insert into public.inventory_units (
  id, workspace_id, vehicle_id, stock_allocation_id, stock_number,
  status, location_id, currency_code, advertised_price_minor, created_by
) values
  (
    '86350000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '86340000-0000-4000-8000-000000000001',
    '86330000-0000-4000-8000-000000000001',
    'N-863301', 'draft', '73000000-0000-4000-8000-000000000001',
    'CAD', 2499999, '31000000-0000-4000-8000-000000000001'
  ),
  (
    '86350000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '86340000-0000-4000-8000-000000000002',
    '86330000-0000-4000-8000-000000000002',
    'N-863302', 'draft', '73000000-0000-4000-8000-000000000001',
    'CAD', 3750000, '31000000-0000-4000-8000-000000000001'
  );
set constraints all immediate;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.lead_results
select 'cash-create', result.*
from app.m3_create_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-lead', 'web.exit_cash', 'Cash exit journey',
  (select party_id from pg_temp.party_results where phase = 'cash-buyer'),
  null, '41000000-0000-4000-8000-000000000001',
  timestamptz '2026-07-20 14:00:00+00',
  'm3-exit-cash-lead', '86100000-0000-4000-8000-000000000001'
) result;
insert into pg_temp.lead_results
select 'cash-contacted', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-contacted',
  (select lead_id from pg_temp.lead_results where phase = 'cash-create'),
  1, 'new__contacted', null,
  'm3-exit-cash-contacted', '86100000-0000-4000-8000-000000000002'
) result;
insert into pg_temp.lead_results
select 'cash-qualified', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-qualified',
  (select lead_id from pg_temp.lead_results where phase = 'cash-create'),
  2, 'contacted__qualified', null,
  'm3-exit-cash-qualified', '86100000-0000-4000-8000-000000000003'
) result;

insert into pg_temp.lead_results
select 'finance-create', result.*
from app.m3_create_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-lead', 'web.exit_finance', 'Finance exit journey',
  (select party_id from pg_temp.party_results where phase = 'finance-buyer'),
  null, '41000000-0000-4000-8000-000000000001',
  timestamptz '2026-07-20 15:00:00+00',
  'm3-exit-finance-lead', '86100000-0000-4000-8000-000000000005'
) result;
insert into pg_temp.lead_results
select 'finance-contacted', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-contacted',
  (select lead_id from pg_temp.lead_results where phase = 'finance-create'),
  1, 'new__contacted', null,
  'm3-exit-finance-contacted', '86100000-0000-4000-8000-000000000006'
) result;
insert into pg_temp.lead_results
select 'finance-qualified', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-qualified',
  (select lead_id from pg_temp.lead_results where phase = 'finance-create'),
  2, 'contacted__qualified', null,
  'm3-exit-finance-qualified', '86100000-0000-4000-8000-000000000007'
) result;

-- 3. Both leads reach the configured conversion-eligible state through RPCs.
select extensions.ok(
  (
    select detail.conversion_eligible
      and detail.version = 3
      and detail.state_key = qualified.state_key
    from pg_temp.lead_results qualified
    cross join app.m3_get_lead(
      '10000000-0000-4000-8000-000000000001',
      (select lead_id from pg_temp.lead_results where phase = 'cash-create')
    ) detail
    where qualified.phase = 'cash-qualified'
  )
  and (
    select detail.conversion_eligible
      and detail.version = 3
      and detail.state_key = qualified.state_key
    from pg_temp.lead_results qualified
    cross join app.m3_get_lead(
      '10000000-0000-4000-8000-000000000001',
      (select lead_id from pg_temp.lead_results where phase = 'finance-create')
    ) detail
    where qualified.phase = 'finance-qualified'
  ),
  'both leads reach a behavior-flagged conversion-eligible state at version 3'
);

insert into pg_temp.conversion_results
select 'cash-first', result.*
from app.m3_convert_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-convert',
  (select lead_id from pg_temp.lead_results where phase = 'cash-create'),
  3, 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001', null,
  '41000000-0000-4000-8000-000000000001',
  'm3-exit-cash-convert', '86100000-0000-4000-8000-000000000004'
) result;
insert into pg_temp.conversion_results
select 'cash-replay', result.*
from app.m3_convert_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-convert',
  (select lead_id from pg_temp.lead_results where phase = 'cash-create'),
  3, 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001', null,
  '41000000-0000-4000-8000-000000000001',
  'm3-exit-cash-convert', '86100000-0000-4000-8000-000000000004'
) result;
insert into pg_temp.conversion_results
select 'finance-first', result.*
from app.m3_convert_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-convert',
  (select lead_id from pg_temp.lead_results where phase = 'finance-create'),
  3, 'retail.third_party_financed', 'CAD',
  '73000000-0000-4000-8000-000000000001', null,
  '41000000-0000-4000-8000-000000000001',
  'm3-exit-finance-convert', '86100000-0000-4000-8000-000000000008'
) result;
insert into pg_temp.conversion_results
select 'finance-replay', result.*
from app.m3_convert_lead(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-convert',
  (select lead_id from pg_temp.lead_results where phase = 'finance-create'),
  3, 'retail.third_party_financed', 'CAD',
  '73000000-0000-4000-8000-000000000001', null,
  '41000000-0000-4000-8000-000000000001',
  'm3-exit-finance-convert', '86100000-0000-4000-8000-000000000008'
) result;

-- 4. Conversion retries return the original deal and exact evidence.
select extensions.ok(
  (
    select not first_result.replayed
      and replay_result.replayed
      and first_result.aggregate_version = 4
      and first_result.lead_id = replay_result.lead_id
      and first_result.deal_id = replay_result.deal_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.conversion_results first_result
    cross join pg_temp.conversion_results replay_result
    where first_result.phase = 'cash-first'
      and replay_result.phase = 'cash-replay'
  )
  and (
    select not first_result.replayed
      and replay_result.replayed
      and first_result.aggregate_version = 4
      and first_result.lead_id = replay_result.lead_id
      and first_result.deal_id = replay_result.deal_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.conversion_results first_result
    cross join pg_temp.conversion_results replay_result
    where first_result.phase = 'finance-first'
      and replay_result.phase = 'finance-replay'
  ),
  'both configured conversions replay the original deal and provenance exactly'
);

-- 5. Each originating lead owns exactly one deal after replay.
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.deals deal
    where deal.originating_lead_id in (
      select lead_id
      from pg_temp.lead_results
      where phase in ('cash-create', 'finance-create')
    )
  ),
  2,
  'conversion replay leaves exactly one deal per originating lead'
);

-- 6. Conversion pins the requested active type and completes the lead workflow.
select extensions.ok(
  not exists (
    select 1
    from (
      values
        ('cash-first'::text, 'retail.cash'::text),
        ('finance-first'::text, 'retail.third_party_financed'::text)
    ) expected(phase, deal_type_key)
    join pg_temp.conversion_results conversion on conversion.phase = expected.phase
    join public.deals deal on deal.id = conversion.deal_id
    join public.deal_type_versions type_version
      on type_version.workspace_id = deal.workspace_id
     and type_version.id = deal.deal_type_version_id
    join public.deal_type_definitions definition
      on definition.workspace_id = type_version.workspace_id
     and definition.id = type_version.deal_type_definition_id
    join public.leads lead
      on lead.workspace_id = deal.workspace_id
     and lead.id = deal.originating_lead_id
    join public.workflow_instances instance
      on instance.workspace_id = lead.workspace_id
     and instance.id = lead.workflow_instance_id
    where definition.key <> expected.deal_type_key
      or type_version.status <> 'active'
      or deal.version <> 2
      or lead.version <> 4
      or lead.converted_deal_id <> deal.id
      or instance.lifecycle_status <> 'completed'
  ),
  'both deals pin active requested types and complete their originating workflow'
);

-- 7. Conversion creates primary buyers; financed retail also links its lender.
insert into pg_temp.participant_results
select 'finance-lender', command.*
from app.m3_add_deal_participant(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-add-lender',
  (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
  2,
  (select party_id from pg_temp.party_results where phase = 'finance-lender'),
  'lender', false,
  'm3-exit-add-lender', '86200000-0000-4000-8000-000000000004'
) command;
select extensions.ok(
  (
    select pg_catalog.string_agg(
      participant.role_key || ':' || participant.is_primary::text || ':'
        || participant.status,
      ',' order by participant.role_key
    ) = 'buyer:true:active'
    from app.m3_list_deal_participants(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.conversion_results where phase = 'cash-first'),
      100, null, null
    ) participant
  )
  and (
    select pg_catalog.string_agg(
      participant.role_key || ':' || participant.is_primary::text || ':'
        || participant.status,
      ',' order by participant.role_key
    ) = 'buyer:true:active,lender:false:active'
    from app.m3_list_deal_participants(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
      100, null, null
    ) participant
  ),
  'app projections show the primary buyers and financed-path lender participants'
);

-- 8. A party from another workspace cannot cross the deal boundary.
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_add_deal_participant(
        '10000000-0000-4000-8000-000000000001',
        'm3-exit-cross-workspace-party', %L, 2, %L, 'seller', false,
        'm3-exit-cross-workspace-party',
        '86200000-0000-4000-8000-000000000001'
      )
    $sql$,
    (select deal_id from pg_temp.conversion_results where phase = 'cash-first'),
    (select party_id from pg_temp.party_results where phase = 'workspace-b-party')
  ),
  '23514',
  'active workspace party is required',
  'deal commands reject otherwise valid parties owned by another workspace'
);

insert into pg_temp.inventory_results
select 'cash', command.*
from app.m3_add_deal_inventory(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-inventory',
  (select deal_id from pg_temp.conversion_results where phase = 'cash-first'),
  2, '86350000-0000-4000-8000-000000000001', 'sold',
  '2499999', 'CAD', '{"source":"m3-exit-proof"}',
  'm3-exit-cash-inventory', '86200000-0000-4000-8000-000000000002'
) command;
insert into pg_temp.line_item_results
select 'cash', command.*
from app.m3_add_deal_line_item(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-line',
  (select deal_id from pg_temp.conversion_results where phase = 'cash-first'),
  3, 'vehicle.price', 'vehicle', 'Vehicle price', '1.000000',
  '2499999', 'CAD', null, 'delivery', 10, 'operator', null,
  'm3-exit-cash-line', '86200000-0000-4000-8000-000000000003'
) command;

insert into pg_temp.inventory_results
select 'finance', command.*
from app.m3_add_deal_inventory(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-inventory',
  (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
  3, '86350000-0000-4000-8000-000000000002', 'sold',
  '3750000', 'CAD', '{"source":"m3-exit-proof"}',
  'm3-exit-finance-inventory', '86200000-0000-4000-8000-000000000005'
) command;
insert into pg_temp.line_item_results
select 'finance', command.*
from app.m3_add_deal_line_item(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-line',
  (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
  4, 'vehicle.price', 'vehicle', 'Vehicle price', '1.000000',
  '3750000', 'CAD', null, 'delivery', 10, 'operator', null,
  'm3-exit-finance-line', '86200000-0000-4000-8000-000000000006'
) command;

-- 9. Each app projection exposes one exact same-workspace sold inventory link.
select extensions.ok(
  (
    select pg_catalog.string_agg(
      inventory.stock_number || ':' || inventory.role_key || ':'
        || inventory.amount_minor || ':' || inventory.currency_code,
      ',' order by inventory.stock_number
    ) = 'N-863301:sold:2499999:CAD'
    from app.m3_list_deal_inventory(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.conversion_results where phase = 'cash-first'),
      100, null, null
    ) inventory
  )
  and (
    select pg_catalog.string_agg(
      inventory.stock_number || ':' || inventory.role_key || ':'
        || inventory.amount_minor || ':' || inventory.currency_code,
      ',' order by inventory.stock_number
    ) = 'N-863302:sold:3750000:CAD'
    from app.m3_list_deal_inventory(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
      100, null, null
    ) inventory
  ),
  'cash and financed exits each expose the exact configured sold inventory link'
);

-- 10. Each app projection round-trips canonical quantity and integer money.
select extensions.ok(
  (
    select pg_catalog.string_agg(
      line_item.key || ':' || line_item.quantity || ':'
        || line_item.unit_amount_minor || ':' || line_item.currency_code,
      ',' order by line_item.sort_order, line_item.line_item_id
    ) = 'vehicle.price:1.000000:2499999:CAD'
    from app.m3_list_deal_line_items(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.conversion_results where phase = 'cash-first'),
      100, null, null
    ) line_item
  )
  and (
    select pg_catalog.string_agg(
      line_item.key || ':' || line_item.quantity || ':'
        || line_item.unit_amount_minor || ':' || line_item.currency_code,
      ',' order by line_item.sort_order, line_item.line_item_id
    ) = 'vehicle.price:1.000000:3750000:CAD'
    from app.m3_list_deal_line_items(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
      100, null, null
    ) line_item
  ),
  'both exit paths preserve canonical quantity and exact minor-unit line items'
);

-- 11. All linked deal mutations advance their aggregate once in order.
select extensions.ok(
  (select aggregate_version = 3 from pg_temp.inventory_results where phase = 'cash')
  and (select aggregate_version = 4 from pg_temp.line_item_results where phase = 'cash')
  and (select aggregate_version = 3 from pg_temp.participant_results where phase = 'finance-lender')
  and (select aggregate_version = 4 from pg_temp.inventory_results where phase = 'finance')
  and (select aggregate_version = 5 from pg_temp.line_item_results where phase = 'finance')
  and (
    select cash_deal.version = 4 and finance_deal.version = 5
    from public.deals cash_deal
    cross join public.deals finance_deal
    where cash_deal.id = (
        select deal_id from pg_temp.conversion_results where phase = 'cash-first'
      )
      and finance_deal.id = (
        select deal_id from pg_temp.conversion_results where phase = 'finance-first'
      )
  ),
  'linked participants, sold inventory, and lines advance each deal exactly once'
);

reset role;
insert into public.media_assets (
  id, workspace_id, deal_id, owner_entity_type, owner_entity_id,
  media_kind, status, created_by
) values (
  '86700000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
  'deal',
  (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
  'legal_document', 'ready',
  '31000000-0000-4000-8000-000000000001'
);
insert into public.media_files (
  id, workspace_id, media_id, file_class, variant, storage_bucket,
  storage_object_key, storage_generation, mime_type, byte_size,
  checksum_sha256, metadata_stripped, retention_policy,
  verification_receipt
) values (
  '86710000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '86700000-0000-4000-8000-000000000001',
  'legal_document_original', 'legal_original', 'media-private',
  'workspaces/10000000-0000-4000-8000-000000000001/deals/'
    || (select deal_id::text from pg_temp.conversion_results
        where phase = 'finance-first')
    || '/finance-conditions/income-proof.pdf',
  'm3-exit-finance-proof-generation', 'application/pdf', 2048,
  repeat('8', 64), false, 'preserve_original',
  pg_temp.legal_file_receipt(
    'workspaces/10000000-0000-4000-8000-000000000001/deals/'
      || (select deal_id::text from pg_temp.conversion_results
          where phase = 'finance-first')
      || '/finance-conditions/income-proof.pdf',
    'm3-exit-finance-proof-generation', 2048, repeat('8', 64)
  )
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.finance_results
select 'create', command.*
from app.m3_create_finance_application(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-exit-finance-application',
  p_deal_id => (
    select deal_id from pg_temp.conversion_results where phase = 'finance-first'
  ),
  p_applicant_party_id => (
    select party_id from pg_temp.party_results where phase = 'finance-buyer'
  ),
  p_lender_party_id => (
    select party_id from pg_temp.party_results where phase = 'finance-lender'
  ),
  p_requested_amount_minor => '3100000',
  p_requested_currency_code => 'CAD',
  p_external_reference => 'EXIT-LENDER-APPLICATION-001',
  p_lender_reported_annual_rate => '6.125000',
  p_lender_reported_term_months => 60,
  p_notes => 'External lender-reported terms only',
  p_request_id => 'm3-exit-finance-application',
  p_correlation_id => '86400000-0000-4000-8000-000000000001'
) command;

insert into pg_temp.finance_results
select 'update', command.*
from app.m3_update_finance_application(
  p_workspace_id => '10000000-0000-4000-8000-000000000001',
  p_idempotency_key => 'm3-exit-finance-update',
  p_finance_application_id => (
    select finance_application_id from pg_temp.finance_results where phase = 'create'
  ),
  p_expected_version => 1,
  p_approved_amount_minor => '3000000',
  p_approved_currency_code => 'CAD',
  p_lender_reported_annual_rate => '6.125000',
  p_lender_reported_term_months => 60,
  p_external_reference => null,
  p_submitted_at => timestamptz '2026-07-16 14:00:00+00',
  p_approval_expires_at => timestamptz '2099-07-16 14:00:00+00',
  p_customer_accepted_at => timestamptz '2026-07-16 15:00:00+00',
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
  p_request_id => 'm3-exit-finance-update',
  p_correlation_id => '86400000-0000-4000-8000-000000000002'
) command;

insert into pg_temp.finance_results
select 'submitted', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-submit',
  (select finance_application_id from pg_temp.finance_results where phase = 'create'),
  2, 'submitted', null,
  'm3-exit-finance-submit', '86400000-0000-4000-8000-000000000003'
) command;

insert into pg_temp.condition_results
select 'add', command.*
from app.m3_add_finance_condition(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-condition-add',
  (select finance_application_id from pg_temp.finance_results where phase = 'create'),
  3, 'proof_of_income', 'Verified proof of income', true, null,
  timestamptz '2099-07-20 14:00:00+00',
  '86710000-0000-4000-8000-000000000001',
  'm3-exit-finance-condition-add',
  '86400000-0000-4000-8000-000000000004'
) command;

insert into pg_temp.condition_results
select 'satisfied', command.*
from app.m3_update_finance_condition(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-condition-satisfy',
  (select finance_application_id from pg_temp.finance_results where phase = 'create'),
  (select condition_id from pg_temp.condition_results where phase = 'add'),
  4, 1, 'Verified proof of income', true,
  timestamptz '2026-07-16 15:30:00+00',
  timestamptz '2099-07-20 14:00:00+00',
  '86710000-0000-4000-8000-000000000001',
  'm3-exit-finance-condition-satisfy',
  '86400000-0000-4000-8000-000000000005'
) command;

insert into pg_temp.finance_results
select 'approved', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-approve',
  (select finance_application_id from pg_temp.finance_results where phase = 'create'),
  5, 'approved', null,
  'm3-exit-finance-approve', '86400000-0000-4000-8000-000000000006'
) command;

insert into pg_temp.finance_results
select 'funded', command.*
from app.m3_transition_finance_application(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-fund',
  (select finance_application_id from pg_temp.finance_results where phase = 'create'),
  6, 'funded', null,
  'm3-exit-finance-fund', '86400000-0000-4000-8000-000000000007'
) command;

-- 12. The external-finance lifecycle advances one deal and application version.
select extensions.ok(
  (select status = 'preparing' and aggregate_version = 6 and not replayed
    from pg_temp.finance_results where phase = 'create')
  and (select status = 'preparing' and aggregate_version = 7 and not replayed
    from pg_temp.finance_results where phase = 'update')
  and (select status = 'submitted' and aggregate_version = 8 and not replayed
    from pg_temp.finance_results where phase = 'submitted')
  and (select aggregate_version = 9 and not replayed
    from pg_temp.condition_results where phase = 'add')
  and (select aggregate_version = 10 and not replayed
    from pg_temp.condition_results where phase = 'satisfied')
  and (select status = 'approved' and aggregate_version = 11 and not replayed
    from pg_temp.finance_results where phase = 'approved')
  and (select status = 'funded' and aggregate_version = 12 and not replayed
    from pg_temp.finance_results where phase = 'funded')
  and (
    select application.status = 'funded'
      and application.version = 7
      and application.funded_at is not null
      and application.customer_accepted_at is not null
    from public.finance_applications application
    where application.id = (
      select finance_application_id from pg_temp.finance_results where phase = 'create'
    )
  ),
  'external finance records exact local lifecycle through funded at deal version 12'
);

-- 13. Safe detail returns exact lender-reported terms and current condition evidence.
select extensions.ok(
  (
    select detail.deal_id = (
        select deal_id from pg_temp.conversion_results where phase = 'finance-first'
      )
      and detail.applicant_party_id = (
        select party_id from pg_temp.party_results where phase = 'finance-buyer'
      )
      and detail.lender_party_id = (
        select party_id from pg_temp.party_results where phase = 'finance-lender'
      )
      and detail.requested_amount_minor = '3100000'
      and detail.approved_amount_minor = '3000000'
      and detail.currency_code = 'CAD'
      and detail.external_reference = 'EXIT-LENDER-APPLICATION-001'
      and detail.lender_reported_annual_rate = '6.125000'
      and detail.lender_reported_term_months = 60
      and detail.status = 'funded'
      and detail.version = 7
      and pg_catalog.jsonb_array_length(detail.conditions) = 1
      and detail.conditions -> 0 ->> 'condition_key' = 'proof_of_income'
      and detail.conditions -> 0 ->> 'version' = '2'
      and detail.conditions -> 0 ->> 'status' = 'active'
      and detail.conditions -> 0 ->> 'satisfied_at' is not null
      and detail.conditions -> 0 ->> 'supporting_file_id'
        = '86710000-0000-4000-8000-000000000001'
    from app.m3_get_finance_application(
      '10000000-0000-4000-8000-000000000001',
      (select finance_application_id from pg_temp.finance_results where phase = 'create')
    ) detail
  ),
  'finance detail exposes exact lender terms, funded lifecycle, and legal evidence'
);

-- 14. Satisfying a condition appends a version and preserves the original.
-- Condition history is intentionally projected through the bounded finance
-- detail RPC for operators; inspect its immutable rows here as database owner.
reset role;
select extensions.ok(
  (
    select old_condition.status = 'replaced'
      and old_condition.version = 1
      and old_condition.satisfied_at is null
      and old_condition.replaced_at is not null
      and new_condition.status = 'active'
      and new_condition.version = 2
      and new_condition.logical_condition_id = old_condition.logical_condition_id
      and new_condition.replaces_condition_id = old_condition.id
      and new_condition.satisfied_at is not null
      and new_condition.supporting_file_id
        = '86710000-0000-4000-8000-000000000001'
    from public.finance_application_conditions old_condition
    cross join public.finance_application_conditions new_condition
    where old_condition.id = (
        select condition_id from pg_temp.condition_results where phase = 'add'
      )
      and new_condition.id = (
        select condition_id from pg_temp.condition_results where phase = 'satisfied'
      )
  ),
  'condition satisfaction preserves immutable lineage and its legal-original file'
);
set local role authenticated;

insert into pg_temp.payment_results
select 'cash-record', command.*
from app.m3_record_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-payment-record',
  (select deal_id from pg_temp.conversion_results where phase = 'cash-first'),
  'balance_received', '2499999', 'CAD', 'bank_transfer', 'EXIT-CASH-001',
  timestamptz '2026-07-16 16:00:00+00', null,
  'Cash balance received', 'm3-exit-cash-payment-record',
  '86500000-0000-4000-8000-000000000001'
) command;
insert into pg_temp.payment_results
select 'cash-record-replay', command.*
from app.m3_record_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-payment-record',
  (select deal_id from pg_temp.conversion_results where phase = 'cash-first'),
  'balance_received', '2499999', 'CAD', 'bank_transfer', 'EXIT-CASH-001',
  timestamptz '2026-07-16 16:00:00+00', null,
  'Cash balance received', 'm3-exit-cash-payment-record',
  '86500000-0000-4000-8000-000000000001'
) command;
insert into pg_temp.payment_results
select 'cash-settle', command.*
from app.m3_settle_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-payment-settle',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'cash-record'),
  1, timestamptz '2026-07-16 17:00:00+00',
  'm3-exit-cash-payment-settle',
  '86500000-0000-4000-8000-000000000002'
) command;
insert into pg_temp.payment_results
select 'cash-settle-replay', command.*
from app.m3_settle_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-payment-settle',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'cash-record'),
  1, timestamptz '2026-07-16 17:00:00+00',
  'm3-exit-cash-payment-settle',
  '86500000-0000-4000-8000-000000000002'
) command;
insert into pg_temp.correction_results
select 'cash-correction', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-payment-correct',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'cash-record'),
  2, 'refund', '25000', 'CAD',
  'Customer-requested post-settlement adjustment',
  'm3-exit-cash-payment-correct',
  '86500000-0000-4000-8000-000000000003'
) command;
insert into pg_temp.correction_results
select 'cash-correction-replay', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-cash-payment-correct',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'cash-record'),
  2, 'refund', '25000', 'CAD',
  'Customer-requested post-settlement adjustment',
  'm3-exit-cash-payment-correct',
  '86500000-0000-4000-8000-000000000003'
) command;

insert into pg_temp.payment_results
select 'finance-record', command.*
from app.m3_record_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-payment-record',
  (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
  'lender_proceeds', '3000000', 'CAD', 'bank_transfer', 'EXIT-LENDER-001',
  timestamptz '2026-07-16 18:00:00+00', null,
  'External lender proceeds', 'm3-exit-finance-payment-record',
  '86500000-0000-4000-8000-000000000004'
) command;
insert into pg_temp.payment_results
select 'finance-record-replay', command.*
from app.m3_record_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-payment-record',
  (select deal_id from pg_temp.conversion_results where phase = 'finance-first'),
  'lender_proceeds', '3000000', 'CAD', 'bank_transfer', 'EXIT-LENDER-001',
  timestamptz '2026-07-16 18:00:00+00', null,
  'External lender proceeds', 'm3-exit-finance-payment-record',
  '86500000-0000-4000-8000-000000000004'
) command;
insert into pg_temp.payment_results
select 'finance-settle', command.*
from app.m3_settle_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-payment-settle',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'finance-record'),
  1, timestamptz '2026-07-16 19:00:00+00',
  'm3-exit-finance-payment-settle',
  '86500000-0000-4000-8000-000000000005'
) command;
insert into pg_temp.payment_results
select 'finance-settle-replay', command.*
from app.m3_settle_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-payment-settle',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'finance-record'),
  1, timestamptz '2026-07-16 19:00:00+00',
  'm3-exit-finance-payment-settle',
  '86500000-0000-4000-8000-000000000005'
) command;
insert into pg_temp.correction_results
select 'finance-correction', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-payment-correct',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'finance-record'),
  2, 'refund', '100000', 'CAD',
  'Lender funding reconciliation correction',
  'm3-exit-finance-payment-correct',
  '86500000-0000-4000-8000-000000000006'
) command;
insert into pg_temp.correction_results
select 'finance-correction-replay', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-exit-finance-payment-correct',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'finance-record'),
  2, 'refund', '100000', 'CAD',
  'Lender funding reconciliation correction',
  'm3-exit-finance-payment-correct',
  '86500000-0000-4000-8000-000000000006'
) command;

-- 15. Cash payment record replay preserves exact money and provenance.
select extensions.ok(
  (
    select first_result.status = 'recorded'
      and first_result.aggregate_version = 5
      and not first_result.replayed
      and replay_result.replayed
      and first_result.payment_transaction_id = replay_result.payment_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.payment_results first_result
    cross join pg_temp.payment_results replay_result
    where first_result.phase = 'cash-record'
      and replay_result.phase = 'cash-record-replay'
  ),
  'cash balance receipt records once and replays exact evidence at deal version 5'
);

-- 16. Lender-proceeds record replay preserves exact money and provenance.
select extensions.ok(
  (
    select first_result.status = 'recorded'
      and first_result.aggregate_version = 13
      and not first_result.replayed
      and replay_result.replayed
      and first_result.payment_transaction_id = replay_result.payment_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.payment_results first_result
    cross join pg_temp.payment_results replay_result
    where first_result.phase = 'finance-record'
      and replay_result.phase = 'finance-record-replay'
  ),
  'configured lender proceeds record once and replay at financed deal version 13'
);

-- 17. Cash settlement replay cannot advance the transaction or deal twice.
select extensions.ok(
  (
    select first_result.status = 'settled'
      and first_result.aggregate_version = 6
      and not first_result.replayed
      and replay_result.replayed
      and first_result.payment_transaction_id = replay_result.payment_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.payment_results first_result
    cross join pg_temp.payment_results replay_result
    where first_result.phase = 'cash-settle'
      and replay_result.phase = 'cash-settle-replay'
  ),
  'cash settlement commits once and retry returns the original version-6 evidence'
);

-- 18. Lender-proceeds settlement replay cannot advance transaction or deal twice.
select extensions.ok(
  (
    select first_result.status = 'settled'
      and first_result.aggregate_version = 14
      and not first_result.replayed
      and replay_result.replayed
      and first_result.payment_transaction_id = replay_result.payment_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.payment_results first_result
    cross join pg_temp.payment_results replay_result
    where first_result.phase = 'finance-settle'
      and replay_result.phase = 'finance-settle-replay'
  ),
  'lender-proceeds settlement commits once and retry returns version-14 evidence'
);

-- 19. Cash correction is linked, reasoned, exact, and idempotent.
select extensions.ok(
  (
    select first_result.status = 'settled'
      and first_result.aggregate_version = 7
      and first_result.remaining_minor = '2474999'
      and not first_result.replayed
      and replay_result.replayed
      and first_result.correction_transaction_id
        = replay_result.correction_transaction_id
      and first_result.original_transaction_id = replay_result.original_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.correction_results first_result
    cross join pg_temp.correction_results replay_result
    where first_result.phase = 'cash-correction'
      and replay_result.phase = 'cash-correction-replay'
  ),
  'cash refund appends one linked correction and preserves an exact 2474999 remainder'
);

-- 20. Lender-proceeds correction is linked, reasoned, exact, and idempotent.
select extensions.ok(
  (
    select first_result.status = 'settled'
      and first_result.aggregate_version = 15
      and first_result.remaining_minor = '2900000'
      and not first_result.replayed
      and replay_result.replayed
      and first_result.correction_transaction_id
        = replay_result.correction_transaction_id
      and first_result.original_transaction_id = replay_result.original_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.correction_results first_result
    cross join pg_temp.correction_results replay_result
    where first_result.phase = 'finance-correction'
      and replay_result.phase = 'finance-correction-replay'
  ),
  'lender refund appends one linked correction and preserves an exact 2900000 remainder'
);

-- 21. Cash ledger read preserves the settled original and negative correction.
-- The bounded RPC still derives the actor from JWT claims; inspect its private
-- append-only backing rows as database owner without granting browser access.
reset role;
select extensions.ok(
  (
    select pg_catalog.string_agg(
      transaction.transaction_type || ':' || transaction.amount_minor || ':'
        || transaction.status || ':' || transaction.version::text || ':'
        || (transaction.corrects_transaction_id is not null)::text,
      ',' order by transaction.amount_minor::bigint desc
    ) = 'balance_received:2499999:settled:2:false,refund:-25000:settled:1:true'
    from app.m3_list_payment_transactions(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.conversion_results where phase = 'cash-first')
    ) transaction
  )
  and (
    select original.amount_minor = 2499999
      and original.status = 'settled'
      and original.version = 2
      and correction.amount_minor = -25000
      and correction.correction_reason
        = 'Customer-requested post-settlement adjustment'
      and correction.corrects_transaction_id = original.id
    from public.payment_transactions original
    cross join public.payment_transactions correction
    where original.id = (
        select payment_transaction_id from pg_temp.payment_results
        where phase = 'cash-record'
      )
      and correction.id = (
        select correction_transaction_id from pg_temp.correction_results
        where phase = 'cash-correction'
      )
  ),
  'cash correction preserves the exact settled original and reasoned negative event'
);

-- 22. Financed ledger read preserves lender proceeds and negative correction.
select extensions.ok(
  (
    select pg_catalog.string_agg(
      transaction.transaction_type || ':' || transaction.amount_minor || ':'
        || transaction.status || ':' || transaction.version::text || ':'
        || (transaction.corrects_transaction_id is not null)::text,
      ',' order by transaction.amount_minor::bigint desc
    ) = 'lender_proceeds:3000000:settled:2:false,refund:-100000:settled:1:true'
    from app.m3_list_payment_transactions(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.conversion_results where phase = 'finance-first')
    ) transaction
  )
  and (
    select original.amount_minor = 3000000
      and original.status = 'settled'
      and original.version = 2
      and correction.amount_minor = -100000
      and correction.correction_reason
        = 'Lender funding reconciliation correction'
      and correction.corrects_transaction_id = original.id
    from public.payment_transactions original
    cross join public.payment_transactions correction
    where original.id = (
        select payment_transaction_id from pg_temp.payment_results
        where phase = 'finance-record'
      )
      and correction.id = (
        select correction_transaction_id from pg_temp.correction_results
        where phase = 'finance-correction'
      )
  ),
  'financed correction preserves exact lender proceeds and reasoned negative event'
);

-- 23. Retries do not duplicate conversion, settlement, or correction artifacts.
-- Command receipts and inert outbox evidence are service-only. The remaining
-- exit assertions are read-only, so cross this boundary once as database owner.
select extensions.ok(
  (
    select pg_catalog.count(*) = 2
    from public.crm_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'm3_convert_lead'
      and receipt.idempotency_key in (
        'm3-exit-cash-convert', 'm3-exit-finance-convert'
      )
  )
  and (
    select pg_catalog.count(*) = 2
    from public.deal_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'm3_settle_payment_transaction'
      and receipt.idempotency_key in (
        'm3-exit-cash-payment-settle', 'm3-exit-finance-payment-settle'
      )
  )
  and (
    select pg_catalog.count(*) = 2
    from public.deal_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'm3_correct_payment_transaction'
      and receipt.idempotency_key in (
        'm3-exit-cash-payment-correct', 'm3-exit-finance-payment-correct'
      )
  )
  and not exists (
    select 1
    from (
      values
        ('cash-first'::text, 'cash-record'::text, 'cash-correction'::text),
        ('finance-first'::text, 'finance-record'::text, 'finance-correction'::text)
    ) expected(conversion_phase, payment_phase, correction_phase)
    join pg_temp.conversion_results conversion
      on conversion.phase = expected.conversion_phase
    where (
      select pg_catalog.count(*)
      from public.deals deal
      where deal.originating_lead_id = conversion.lead_id
    ) <> 1
    or (
      select pg_catalog.count(*)
      from public.payment_transactions transaction
      where transaction.deal_id = conversion.deal_id
    ) <> 2
  ),
  'conversion and settlement retries leave one deal, original, and correction per path'
);

-- 24. Final aggregate versions prove every successful mutation advanced once.
select extensions.ok(
  (
    select deal.version = 7
    from public.deals deal
    where deal.id = (
      select deal_id from pg_temp.conversion_results where phase = 'cash-first'
    )
  )
  and (
    select deal.version = 15
    from public.deals deal
    where deal.id = (
      select deal_id from pg_temp.conversion_results where phase = 'finance-first'
    )
  ),
  'cash and financed exits finish at exact aggregate versions 7 and 15'
);

reset role;

-- 25. Every cash-path command has exact receipt, audit, and outbox parity.
with party_evidence as (
  select
    'm3_create_party'::text as command_type,
    'm3-exit-cash-buyer'::text as idempotency_key,
    result.party_id as entity_id,
    result.audit_event_id,
    result.outbox_event_id
  from pg_temp.party_results result
  where result.phase = 'cash-buyer'
),
crm_evidence as (
  select
    expected.command_type,
    expected.idempotency_key,
    result.lead_id as entity_id,
    result.audit_event_id,
    result.outbox_event_id
  from (
    values
      ('cash-create'::text, 'm3_create_lead'::text, 'm3-exit-cash-lead'::text),
      ('cash-contacted'::text, 'm3_transition_lead'::text,
        'm3-exit-cash-contacted'::text),
      ('cash-qualified'::text, 'm3_transition_lead'::text,
        'm3-exit-cash-qualified'::text)
  ) expected(phase, command_type, idempotency_key)
  join pg_temp.lead_results result on result.phase = expected.phase
  union all
  select
    'm3_convert_lead', 'm3-exit-cash-convert', result.lead_id,
    result.audit_event_id, result.outbox_event_id
  from pg_temp.conversion_results result
  where result.phase = 'cash-first'
),
deal_evidence as (
  select
    'm3_add_deal_inventory'::text as command_type,
    'm3-exit-cash-inventory'::text as idempotency_key,
    result.deal_id,
    result.audit_event_id,
    result.outbox_event_id
  from pg_temp.inventory_results result where result.phase = 'cash'
  union all
  select
    'm3_add_deal_line_item', 'm3-exit-cash-line', result.deal_id,
    result.audit_event_id, result.outbox_event_id
  from pg_temp.line_item_results result where result.phase = 'cash'
  union all
  select
    'm3_record_payment_transaction', 'm3-exit-cash-payment-record',
    conversion.deal_id, result.audit_event_id, result.outbox_event_id
  from pg_temp.payment_results result
  cross join pg_temp.conversion_results conversion
  where result.phase = 'cash-record' and conversion.phase = 'cash-first'
  union all
  select
    'm3_settle_payment_transaction', 'm3-exit-cash-payment-settle',
    conversion.deal_id, result.audit_event_id, result.outbox_event_id
  from pg_temp.payment_results result
  cross join pg_temp.conversion_results conversion
  where result.phase = 'cash-settle' and conversion.phase = 'cash-first'
  union all
  select
    'm3_correct_payment_transaction', 'm3-exit-cash-payment-correct',
    conversion.deal_id, result.audit_event_id, result.outbox_event_id
  from pg_temp.correction_results result
  cross join pg_temp.conversion_results conversion
  where result.phase = 'cash-correction' and conversion.phase = 'cash-first'
),
all_evidence as (
  select audit_event_id, outbox_event_id from party_evidence
  union all
  select audit_event_id, outbox_event_id from crm_evidence
  union all
  select audit_event_id, outbox_event_id from deal_evidence
)
select extensions.ok(
  (
    select pg_catalog.count(*) = 10
      and pg_catalog.count(distinct audit_event_id) = 10
      and pg_catalog.count(distinct outbox_event_id) = 10
    from all_evidence
  )
  and not exists (
    select 1 from party_evidence evidence
    where not exists (
      select 1 from public.party_command_receipts receipt
      where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
        and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
        and receipt.command_type = evidence.command_type
        and receipt.idempotency_key = evidence.idempotency_key
        and receipt.party_id = evidence.entity_id
        and receipt.audit_event_id = evidence.audit_event_id
        and receipt.outbox_event_id = evidence.outbox_event_id
    )
  )
  and not exists (
    select 1 from crm_evidence evidence
    where not exists (
      select 1 from public.crm_command_receipts receipt
      where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
        and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
        and receipt.command_type = evidence.command_type
        and receipt.idempotency_key = evidence.idempotency_key
        and receipt.entity_id = evidence.entity_id
        and receipt.audit_event_id = evidence.audit_event_id
        and receipt.outbox_event_id = evidence.outbox_event_id
    )
  )
  and not exists (
    select 1 from deal_evidence evidence
    where not exists (
      select 1 from public.deal_command_receipts receipt
      where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
        and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
        and receipt.command_type = evidence.command_type
        and receipt.idempotency_key = evidence.idempotency_key
        and receipt.deal_id = evidence.deal_id
        and receipt.audit_event_id = evidence.audit_event_id
        and receipt.outbox_event_id = evidence.outbox_event_id
    )
  )
  and not exists (
    select 1 from all_evidence evidence
    where not exists (
      select 1 from public.audit_events audit
      where audit.workspace_id = '10000000-0000-4000-8000-000000000001'
        and audit.id = evidence.audit_event_id
    )
    or not exists (
      select 1 from public.outbox_events event
      where event.workspace_id = '10000000-0000-4000-8000-000000000001'
        and event.id = evidence.outbox_event_id
    )
  ),
  'cash exit has ten distinct app-command receipt, audit, and outbox triples'
);

-- 26. Every financed-path command has exact receipt, audit, and outbox parity.
with party_evidence as (
  select
    'm3_create_party'::text as command_type,
    expected.idempotency_key,
    result.party_id as entity_id,
    result.audit_event_id,
    result.outbox_event_id
  from (
    values
      ('finance-buyer'::text, 'm3-exit-finance-buyer'::text),
      ('finance-lender'::text, 'm3-exit-finance-lender'::text)
  ) expected(phase, idempotency_key)
  join pg_temp.party_results result on result.phase = expected.phase
),
crm_evidence as (
  select
    expected.command_type,
    expected.idempotency_key,
    result.lead_id as entity_id,
    result.audit_event_id,
    result.outbox_event_id
  from (
    values
      ('finance-create'::text, 'm3_create_lead'::text,
        'm3-exit-finance-lead'::text),
      ('finance-contacted'::text, 'm3_transition_lead'::text,
        'm3-exit-finance-contacted'::text),
      ('finance-qualified'::text, 'm3_transition_lead'::text,
        'm3-exit-finance-qualified'::text)
  ) expected(phase, command_type, idempotency_key)
  join pg_temp.lead_results result on result.phase = expected.phase
  union all
  select
    'm3_convert_lead', 'm3-exit-finance-convert', result.lead_id,
    result.audit_event_id, result.outbox_event_id
  from pg_temp.conversion_results result
  where result.phase = 'finance-first'
),
deal_evidence as (
  select
    'm3_add_deal_participant'::text as command_type,
    'm3-exit-add-lender'::text as idempotency_key,
    result.deal_id,
    result.audit_event_id,
    result.outbox_event_id
  from pg_temp.participant_results result where result.phase = 'finance-lender'
  union all
  select
    'm3_add_deal_inventory', 'm3-exit-finance-inventory', result.deal_id,
    result.audit_event_id, result.outbox_event_id
  from pg_temp.inventory_results result where result.phase = 'finance'
  union all
  select
    'm3_add_deal_line_item', 'm3-exit-finance-line', result.deal_id,
    result.audit_event_id, result.outbox_event_id
  from pg_temp.line_item_results result where result.phase = 'finance'
  union all
  select
    expected.command_type, expected.idempotency_key, conversion.deal_id,
    result.audit_event_id, result.outbox_event_id
  from (
    values
      ('create'::text, 'm3_create_finance_application'::text,
        'm3-exit-finance-application'::text),
      ('update'::text, 'm3_update_finance_application'::text,
        'm3-exit-finance-update'::text),
      ('submitted'::text, 'm3_transition_finance_application'::text,
        'm3-exit-finance-submit'::text),
      ('approved'::text, 'm3_transition_finance_application'::text,
        'm3-exit-finance-approve'::text),
      ('funded'::text, 'm3_transition_finance_application'::text,
        'm3-exit-finance-fund'::text)
  ) expected(phase, command_type, idempotency_key)
  join pg_temp.finance_results result on result.phase = expected.phase
  cross join pg_temp.conversion_results conversion
  where conversion.phase = 'finance-first'
  union all
  select
    expected.command_type, expected.idempotency_key, conversion.deal_id,
    result.audit_event_id, result.outbox_event_id
  from (
    values
      ('add'::text, 'm3_add_finance_condition'::text,
        'm3-exit-finance-condition-add'::text),
      ('satisfied'::text, 'm3_update_finance_condition'::text,
        'm3-exit-finance-condition-satisfy'::text)
  ) expected(phase, command_type, idempotency_key)
  join pg_temp.condition_results result on result.phase = expected.phase
  cross join pg_temp.conversion_results conversion
  where conversion.phase = 'finance-first'
  union all
  select
    expected.command_type, expected.idempotency_key, conversion.deal_id,
    result.audit_event_id, result.outbox_event_id
  from (
    values
      ('finance-record'::text, 'm3_record_payment_transaction'::text,
        'm3-exit-finance-payment-record'::text),
      ('finance-settle'::text, 'm3_settle_payment_transaction'::text,
        'm3-exit-finance-payment-settle'::text)
  ) expected(phase, command_type, idempotency_key)
  join pg_temp.payment_results result on result.phase = expected.phase
  cross join pg_temp.conversion_results conversion
  where conversion.phase = 'finance-first'
  union all
  select
    'm3_correct_payment_transaction', 'm3-exit-finance-payment-correct',
    conversion.deal_id, result.audit_event_id, result.outbox_event_id
  from pg_temp.correction_results result
  cross join pg_temp.conversion_results conversion
  where result.phase = 'finance-correction'
    and conversion.phase = 'finance-first'
),
all_evidence as (
  select audit_event_id, outbox_event_id from party_evidence
  union all
  select audit_event_id, outbox_event_id from crm_evidence
  union all
  select audit_event_id, outbox_event_id from deal_evidence
)
select extensions.ok(
  (
    select pg_catalog.count(*) = 19
      and pg_catalog.count(distinct audit_event_id) = 19
      and pg_catalog.count(distinct outbox_event_id) = 19
    from all_evidence
  )
  and not exists (
    select 1 from party_evidence evidence
    where not exists (
      select 1 from public.party_command_receipts receipt
      where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
        and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
        and receipt.command_type = evidence.command_type
        and receipt.idempotency_key = evidence.idempotency_key
        and receipt.party_id = evidence.entity_id
        and receipt.audit_event_id = evidence.audit_event_id
        and receipt.outbox_event_id = evidence.outbox_event_id
    )
  )
  and not exists (
    select 1 from crm_evidence evidence
    where not exists (
      select 1 from public.crm_command_receipts receipt
      where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
        and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
        and receipt.command_type = evidence.command_type
        and receipt.idempotency_key = evidence.idempotency_key
        and receipt.entity_id = evidence.entity_id
        and receipt.audit_event_id = evidence.audit_event_id
        and receipt.outbox_event_id = evidence.outbox_event_id
    )
  )
  and not exists (
    select 1 from deal_evidence evidence
    where not exists (
      select 1 from public.deal_command_receipts receipt
      where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
        and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
        and receipt.command_type = evidence.command_type
        and receipt.idempotency_key = evidence.idempotency_key
        and receipt.deal_id = evidence.deal_id
        and receipt.audit_event_id = evidence.audit_event_id
        and receipt.outbox_event_id = evidence.outbox_event_id
    )
  )
  and not exists (
    select 1 from all_evidence evidence
    where not exists (
      select 1 from public.audit_events audit
      where audit.workspace_id = '10000000-0000-4000-8000-000000000001'
        and audit.id = evidence.audit_event_id
    )
    or not exists (
      select 1 from public.outbox_events event
      where event.workspace_id = '10000000-0000-4000-8000-000000000001'
        and event.id = evidence.outbox_event_id
    )
  ),
  'financed exit has nineteen distinct app-command receipt, audit, and outbox triples'
);

-- 27. Returned provenance describes the exact conversion, funding, and money events.
select extensions.ok(
  not exists (
    select 1
    from (
      values ('cash-first'::text), ('finance-first'::text)
    ) expected(phase)
    join pg_temp.conversion_results conversion on conversion.phase = expected.phase
    where not exists (
      select 1 from public.audit_events audit
      where audit.id = conversion.audit_event_id
        and audit.action = 'lead.converted'
        and audit.entity_type = 'lead'
        and audit.entity_id = conversion.lead_id
        and audit.after_data ->> 'converted_deal_id' = conversion.deal_id::text
    )
    or not exists (
      select 1 from public.outbox_events event
      where event.id = conversion.outbox_event_id
        and event.event_name = 'lead.converted'
        and event.aggregate_type = 'lead'
        and event.aggregate_id = conversion.lead_id
        and event.aggregate_version = 4
        and event.payload ->> 'dealId' = conversion.deal_id::text
    )
  )
  and (
    select exists (
      select 1 from public.audit_events audit
      where audit.id = funded.audit_event_id
        and audit.action = 'deal.finance_application_transitioned'
        and audit.entity_type = 'finance_application'
        and audit.entity_id = funded.finance_application_id
        and audit.after_data ->> 'status' = 'funded'
        and audit.after_data ->> 'version' = '7'
    )
    and exists (
      select 1 from public.outbox_events event
      where event.id = funded.outbox_event_id
        and event.event_name = 'deal.finance_application_transitioned'
        and event.aggregate_id = conversion.deal_id
        and event.aggregate_version = 12
        and event.payload ->> 'toStatus' = 'funded'
        and event.payload ->> 'financeApplicationVersion' = '7'
    )
    from pg_temp.finance_results funded
    cross join pg_temp.conversion_results conversion
    where funded.phase = 'funded' and conversion.phase = 'finance-first'
  )
  and not exists (
    select 1
    from (
      values
        ('cash-settle'::text, 'cash-first'::text, 'balance_received'::text,
          '2499999'::text, 6::bigint),
        ('finance-settle'::text, 'finance-first'::text, 'lender_proceeds'::text,
          '3000000'::text, 14::bigint)
    ) expected(payment_phase, conversion_phase, transaction_type, amount_minor,
      aggregate_version)
    join pg_temp.payment_results payment on payment.phase = expected.payment_phase
    join pg_temp.conversion_results conversion
      on conversion.phase = expected.conversion_phase
    where not exists (
      select 1 from public.audit_events audit
      where audit.id = payment.audit_event_id
        and audit.action = 'deal.payment_transaction_settled'
        and audit.entity_id = payment.payment_transaction_id
        and audit.after_data ->> 'status' = 'settled'
        and audit.after_data ->> 'version' = '2'
    )
    or not exists (
      select 1 from public.outbox_events event
      where event.id = payment.outbox_event_id
        and event.event_name = 'deal.payment_transaction_settled'
        and event.aggregate_id = conversion.deal_id
        and event.aggregate_version = expected.aggregate_version
        and event.payload ->> 'transactionType' = expected.transaction_type
        and event.payload ->> 'amountMinor' = expected.amount_minor
        and event.payload ->> 'status' = 'settled'
    )
  )
  and not exists (
    select 1
    from (
      values
        ('cash-correction'::text, 'cash-first'::text,
          'Customer-requested post-settlement adjustment'::text,
          '-25000'::text, '2474999'::text, 7::bigint),
        ('finance-correction'::text, 'finance-first'::text,
          'Lender funding reconciliation correction'::text,
          '-100000'::text, '2900000'::text, 15::bigint)
    ) expected(correction_phase, conversion_phase, reason, amount_minor,
      remaining_minor, aggregate_version)
    join pg_temp.correction_results correction
      on correction.phase = expected.correction_phase
    join pg_temp.conversion_results conversion
      on conversion.phase = expected.conversion_phase
    where not exists (
      select 1 from public.audit_events audit
      where audit.id = correction.audit_event_id
        and audit.action = 'deal.payment_transaction_corrected'
        and audit.entity_id = correction.correction_transaction_id
        and audit.reason = expected.reason
        and audit.after_data ->> 'amount_minor' = expected.amount_minor
        and audit.after_data ->> 'remaining_minor' = expected.remaining_minor
    )
    or not exists (
      select 1 from public.outbox_events event
      where event.id = correction.outbox_event_id
        and event.event_name = 'deal.payment_transaction_corrected'
        and event.aggregate_id = conversion.deal_id
        and event.aggregate_version = expected.aggregate_version
        and event.payload ->> 'amountMinor' = expected.amount_minor
        and event.payload ->> 'remainingMinor' = expected.remaining_minor
    )
  ),
  'audit and outbox payloads exactly identify conversion, funding, settlement, and correction'
);

-- 28. Every child row remains inside its deal workspace with exact cardinality.
select extensions.ok(
  (
    select pg_catalog.count(*) = 3
      and pg_catalog.bool_and(
        participant.workspace_id = deal.workspace_id
        and participant.workspace_id = '10000000-0000-4000-8000-000000000001'
      )
    from public.deal_participants participant
    join public.deals deal on deal.id = participant.deal_id
    where deal.id in (
      select deal_id from pg_temp.conversion_results
      where phase in ('cash-first', 'finance-first')
    )
  )
  and (
    select pg_catalog.count(*) = 2
      and pg_catalog.bool_and(inventory.workspace_id = deal.workspace_id)
    from public.deal_inventory_units inventory
    join public.deals deal on deal.id = inventory.deal_id
    where deal.id in (
      select deal_id from pg_temp.conversion_results
      where phase in ('cash-first', 'finance-first')
    )
  )
  and (
    select pg_catalog.count(*) = 2
      and pg_catalog.bool_and(line_item.workspace_id = deal.workspace_id)
    from public.deal_line_items line_item
    join public.deals deal on deal.id = line_item.deal_id
    where deal.id in (
      select deal_id from pg_temp.conversion_results
      where phase in ('cash-first', 'finance-first')
    )
  )
  and (
    select pg_catalog.count(*) = 1
      and pg_catalog.bool_and(application.workspace_id = deal.workspace_id)
    from public.finance_applications application
    join public.deals deal on deal.id = application.deal_id
    where deal.id = (
      select deal_id from pg_temp.conversion_results where phase = 'finance-first'
    )
  )
  and (
    select pg_catalog.count(*) = 4
      and pg_catalog.bool_and(transaction.workspace_id = deal.workspace_id)
    from public.payment_transactions transaction
    join public.deals deal on deal.id = transaction.deal_id
    where deal.id in (
      select deal_id from pg_temp.conversion_results
      where phase in ('cash-first', 'finance-first')
    )
  ),
  'participants, inventory, lines, finance, and payments keep exact workspace scope'
);

-- 29. A workspace-B actor cannot observe any workspace-A exit artifact via RLS.
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  (
    select pg_catalog.count(*) = 0
    from public.deals deal
    where deal.id in (
      select deal_id from pg_temp.conversion_results
      where phase in ('cash-first', 'finance-first')
    )
  )
  and (
    select pg_catalog.count(*) = 0
    from public.finance_applications application
    where application.id = (
      select finance_application_id from pg_temp.finance_results where phase = 'create'
    )
  )
  and (
    select pg_catalog.count(*) = 0
    from public.payment_transactions transaction
    where transaction.deal_id in (
      select deal_id from pg_temp.conversion_results
      where phase in ('cash-first', 'finance-first')
    )
  ),
  'forced RLS hides both complete exit journeys from the other workspace actor'
);
reset role;

-- 30. External-finance and one-time ledgers store no provider/servicing fields.
select extensions.ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute attribute
    join pg_catalog.pg_class relation on relation.oid = attribute.attrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in ('finance_applications', 'payment_transactions')
      and attribute.attnum > 0
      and not attribute.attisdropped
      and attribute.attname ~* '(provider|credential|secret|token|credit.?pull|recurr|schedule|servic|principal|interest)'
  ),
  'finance and payment records contain no provider credentials or servicing fields'
);

-- 31. Milestone 3 creates no recurring-payment or loan-servicing schema.
select extensions.ok(
  to_regclass('public.payment_schedules') is null
    and to_regclass('public.payment_schedule_items') is null
    and to_regclass('public.recurring_payments') is null
    and to_regclass('public.loan_accounts') is null
    and to_regclass('public.loan_installments') is null
    and to_regclass('public.servicing_accounts') is null,
  'exit journeys create no recurring, amortization, or servicing tables'
);

-- 32. Exit outbox records are inert and exclude private/provider material.
select extensions.ok(
  not exists (
    select 1
    from public.outbox_events event
    where event.aggregate_id in (
      select deal_id from pg_temp.conversion_results
      where phase in ('cash-first', 'finance-first')
    )
      and (
        event.event_name ~* '(provider|credit.?pull|recurr|schedule|servic|principal|interest)'
        or event.payload::text
          ~* '(provider|credential|secret|token|credit.?pull|recurr|schedule|servic|principal|interest)'
        or event.payload::text like '%EXIT-LENDER-APPLICATION-001%'
        or event.payload::text like '%EXIT-LENDER-001%'
        or event.payload::text like '%EXIT-CASH-001%'
        or event.payload::text like '%External lender-reported terms only%'
        or event.payload::text like '%Customer-requested post-settlement adjustment%'
        or event.payload::text like '%Lender funding reconciliation correction%'
      )
  ),
  'outbox events contain no provider effect, recurring artifact, note, or reference'
);

select * from extensions.finish();
rollback;
