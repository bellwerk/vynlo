-- VYN-INV-001, VYN-INV-002, VYN-NUM-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-API-001, T-INV-001, T-INV-002, T-INV-003,
-- T-NUM-001, T-NUM-002, T-NUM-003, T-TEN-001, T-RBAC-001, T-AUD-001
-- M2-INV-AC-002, M2-INV-AC-003, M2-INV-AC-010, M2-INV-AC-011
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(40);

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
          pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create function pg_temp.prepare_successful_decode(
  fixture_vin text,
  fixture_idempotency_key text,
  fixture_worker_id text,
  fixture_model_year integer,
  fixture_make text,
  fixture_model text
)
returns table (
  vin_decode_request_id uuid,
  vin_decode_result_id uuid,
  aggregate_version bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested record;
  claimed record;
  completed record;
begin
  select result.*
    into requested
  from app.request_vin_decode_job(
    '10000000-0000-4000-8000-000000000001',
    fixture_idempotency_key,
    fixture_vin,
    fixture_model_year,
    'request-' || fixture_idempotency_key,
    pg_catalog.gen_random_uuid()
  ) result;

  select job.*
    into claimed
  from app.claim_jobs(
    fixture_worker_id,
    1,
    300,
    array['inventory.vin_decode']
  ) job;

  if claimed.job_id is null or claimed.entity_id <> requested.vin_decode_request_id then
    raise exception 'unexpected VIN job claim';
  end if;

  select result.*
    into completed
  from app.complete_vin_decode_request(
    '10000000-0000-4000-8000-000000000001',
    requested.vin_decode_request_id,
    claimed.job_id,
    fixture_worker_id,
    claimed.lease_token,
    'nhtsa_vpic',
    'vpic-4.06',
    pg_catalog.statement_timestamp(),
    pg_catalog.jsonb_build_object(
      'Results', pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('Make', fixture_make)
      )
    ),
    '[]'::jsonb,
    fixture_model_year,
    fixture_make,
    fixture_model,
    'Sedan',
    4,
    'FWD',
    '2.4',
    'Gasoline',
    160,
    'Automatic',
    'EX',
    'worker-' || fixture_idempotency_key,
    claimed.correlation_id
  ) result;

  perform app.complete_job(
    claimed.job_id,
    fixture_worker_id,
    claimed.lease_token,
    '{"decode_status":"succeeded"}'::jsonb,
    null
  );

  return query
  select
    requested.vin_decode_request_id,
    completed.vin_decode_result_id,
    completed.aggregate_version;
end;
$$;

create function pg_temp.create_confirmed_intake(
  fixture_request_id uuid,
  fixture_result_id uuid,
  fixture_version bigint,
  fixture_idempotency_key text,
  fixture_model_year integer,
  fixture_make text,
  fixture_model text,
  fixture_confirmed boolean default true,
  fixture_price_minor bigint default 2500000,
  fixture_link_existing boolean default false
)
returns table (
  vin_inventory_intake_id uuid,
  vin_decode_request_id uuid,
  vin_decode_request_version bigint,
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  audit_event_id uuid,
  outbox_event_id uuid,
  linked_existing_open_unit boolean,
  replayed boolean
)
language sql
set search_path = ''
as $$
  select *
  from app.create_inventory_unit_from_vin_decode(
    '10000000-0000-4000-8000-000000000001',
    fixture_request_id,
    fixture_result_id,
    fixture_version,
    '71000000-0000-4000-8000-000000000001',
    '73000000-0000-4000-8000-000000000001',
    'used.ready',
    fixture_idempotency_key,
    fixture_confirmed,
    fixture_model_year,
    fixture_make,
    fixture_model,
    'Sedan',
    4,
    'FWD',
    '2.4',
    'Gasoline',
    160,
    'Automatic',
    'EX',
    case when fixture_link_existing then null else date '2026-07-16' end,
    case when fixture_link_existing then null else 12345 end,
    case when fixture_link_existing then null else 'km' end,
    'CAD',
    case when fixture_link_existing then null else fixture_price_minor end,
    case when fixture_link_existing then null else 'Confirmed VIN intake fixture' end,
    'request-' || fixture_idempotency_key,
    pg_catalog.gen_random_uuid()
  );
$$;

create temporary table pg_temp.decode_results (
  vin_decode_request_id uuid,
  vin_decode_result_id uuid,
  aggregate_version bigint,
  probe text
);
create temporary table pg_temp.intake_results (
  vin_inventory_intake_id uuid,
  vin_decode_request_id uuid,
  vin_decode_request_version bigint,
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  audit_event_id uuid,
  outbox_event_id uuid,
  linked_existing_open_unit boolean,
  replayed boolean,
  probe text
);
create temporary table pg_temp.legacy_inventory_results (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean,
  probe text
);
grant all on
  pg_temp.decode_results,
  pg_temp.intake_results,
  pg_temp.legacy_inventory_results
to authenticated, service_role;
grant execute on function pg_temp.prepare_successful_decode(
  text, text, text, integer, text, text
) to authenticated;
grant execute on function pg_temp.create_confirmed_intake(
  uuid, uuid, bigint, text, integer, text, text, boolean, bigint, boolean
) to authenticated;

select extensions.has_table(
  'public',
  'vin_inventory_intakes',
  'immutable VIN intake receipts exist'
);
select extensions.has_column(
  'public',
  'vin_decode_requests',
  'consumed_by_inventory_intake_id',
  'VIN requests expose an irreversible consumption link'
);
select extensions.has_function(
  'app',
  'create_inventory_unit_from_vin_decode',
  array[
    'uuid', 'uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text', 'text',
    'boolean', 'integer', 'text', 'text', 'text', 'integer', 'text', 'text',
    'text', 'integer', 'text', 'text', 'date', 'bigint', 'text', 'text',
    'bigint', 'text', 'text', 'uuid'
  ],
  'canonical confirmed VIN intake command exists'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'vin_inventory_intakes'
  ),
  'T-TEN-001 VIN intake receipts use forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.vin_inventory_intakes', 'SELECT'
  ),
  'T-RBAC-001 browser callers cannot read intake internals directly'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.create_inventory_unit_from_vin_decode(uuid,uuid,uuid,bigint,uuid,uuid,text,text,boolean,integer,text,text,text,integer,text,text,text,integer,text,text,date,bigint,text,text,bigint,text,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.create_inventory_unit_from_vin_decode(uuid,uuid,uuid,bigint,uuid,text,boolean,integer,text,text,text,integer,text,text,text,integer,text,text,date,bigint,text,text,bigint,text,text,uuid)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.create_inventory_unit(uuid,uuid,text,text,integer,text,text,date,bigint,text,text,bigint,text,text,uuid)',
      'EXECUTE'
    ),
  'T-RBAC-001 canonical intake replaces direct browser access to the legacy primitive'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'legacy-bypass-denied', '1HGCM82633A900011', 2003, 'HONDA', 'Accord',
      null, null, null, 'CAD', null, null,
      'request-legacy-bypass', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'permission denied for function create_inventory_unit',
  'T-RBAC-001 authenticated callers cannot bypass VIN confirmation'
);
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from app.create_inventory_unit_from_vin_decode(
      '10000000-0000-4000-8000-000000000001',
      pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 1,
      '71000000-0000-4000-8000-000000000001',
      '73000000-0000-4000-8000-000000000001', 'used.ready',
      'cross-workspace-intake',
      true, 2003, 'HONDA', 'Accord', null, null, null, null, null, null,
      null, null, null, null, null, 'CAD', null, null,
      'request-cross-workspace', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 another workspace cannot consume a Northstar VIN request'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
insert into pg_temp.decode_results
select prepared.*, 'new'
from pg_temp.prepare_successful_decode(
  '1HGCM82633A900012',
  'intake-decode-new-001',
  'intake-worker-new',
  2003,
  'HONDA',
  'Accord'
) prepared;

select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'new'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'new'),
      (select aggregate_version from pg_temp.decode_results where probe = 'new'),
      'intake-unconfirmed-001', 2003, 'HONDA', 'Accord', false
    )
  $$,
  '22023',
  'normalized VIN facts require explicit confirmation',
  'T-INV-002 provider suggestions cannot allocate stock without explicit confirmation'
);
select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'new'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'new'),
      1,
      'intake-stale-version-001', 2003, 'HONDA', 'Accord'
    )
  $$,
  '40001',
  'VIN request version conflict',
  'T-INV-003 stale confirmation cannot consume a changed VIN request'
);
select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'new'),
      pg_catalog.gen_random_uuid(),
      (select aggregate_version from pg_temp.decode_results where probe = 'new'),
      'intake-wrong-result-001', 2003, 'HONDA', 'Accord'
    )
  $$,
  '23514',
  'confirmed VIN result does not belong to the request',
  'T-INV-002 confirmation is bound to the immutable provider result shown to the user'
);

create temporary table pg_temp.stock_before_new as
select next_sequence_value
from public.stock_number_counters
where workspace_id = '10000000-0000-4000-8000-000000000001'
  and definition_id = '71000000-0000-4000-8000-000000000001';
grant select on pg_temp.stock_before_new to authenticated;

select extensions.lives_ok(
  $$
    insert into pg_temp.intake_results
    select result.*, 'new'
    from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'new'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'new'),
      (select aggregate_version from pg_temp.decode_results where probe = 'new'),
      'intake-create-new-001', 2003, 'HONDA', 'Accord'
    ) result
  $$,
  'T-INV-001 confirmed new VIN creates one vehicle and holding episode atomically'
);
select extensions.results_eq(
  $$
    select vin_decode_request_version, linked_existing_open_unit, replayed
    from pg_temp.intake_results where probe = 'new'
  $$,
  $$values (3::bigint, false, false)$$,
  'M2-INV-AC-011 new intake advances once and reports that it allocated a holding'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.intake_results result
    join public.vin_inventory_intakes intake
      on intake.id = result.vin_inventory_intake_id
    join public.vin_decode_requests request
      on request.id = intake.vin_decode_request_id
    where result.probe = 'new'
      and request.consumed_at is not null
      and request.consumed_by_inventory_intake_id = intake.id
      and intake.inventory_unit_id = result.inventory_unit_id
      and intake.vehicle_id = result.vehicle_id
  ),
  'T-INV-003 decode request, result, intake receipt, vehicle, and unit remain linked'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.intake_results created
    join public.vin_inventory_intakes intake
      on intake.id = created.vin_inventory_intake_id
    where created.probe = 'new'
      and intake.confirmed_facts ->> 'engine_liters' = '2.4'
      and intake.confirmed_facts ->> 'trim_name' = 'EX'
      and intake.confirmed_facts::text not like '%Results%'
  ),
  'confirmed fact snapshot is exact, bounded, and excludes the raw provider payload'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.intake_results created
    join public.vehicles vehicle on vehicle.id = created.vehicle_id
    where created.probe = 'new'
      and vehicle.vin = '1HGCM82633A900012'
      and vehicle.engine_displacement_liters = 2.400
      and vehicle.trim_name = 'EX'
  ),
  'explicitly confirmed normalized facts populate the physical vehicle'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.intake_results created
    join public.audit_events audit on audit.id = created.audit_event_id
    join public.outbox_events event on event.id = created.outbox_event_id
    where created.probe = 'new'
      and audit.action = 'inventory_unit.intake_confirmed'
      and audit.actor_user_id = '31000000-0000-4000-8000-000000000001'
      and event.event_name = 'inventory_unit.intake_confirmed'
      and event.payload ->> 'vinDecodeRequestId' = created.vin_decode_request_id::text
  ),
  'T-AUD-001 intake audit and outbox evidence commit with the authoritative record'
);
select extensions.is(
  (
    select next_sequence_value
    from public.stock_number_counters
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and definition_id = '71000000-0000-4000-8000-000000000001'
  ),
  (select next_sequence_value + 1 from pg_temp.stock_before_new),
  'T-NUM-001 confirmed intake advances the transactional stock counter once'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.intake_results
    select result.*, 'new-replay'
    from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'new'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'new'),
      (select aggregate_version from pg_temp.decode_results where probe = 'new'),
      'intake-create-new-001', 2003, 'HONDA', 'Accord'
    ) result
  $$,
  'T-NUM-003 exact intake replay succeeds after consumption'
);
select extensions.ok(
  (
    select replay.vin_inventory_intake_id = initial.vin_inventory_intake_id
      and replay.inventory_unit_id = initial.inventory_unit_id
      and replay.stock_number = initial.stock_number
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
      and replay.replayed
    from pg_temp.intake_results initial
    cross join pg_temp.intake_results replay
    where initial.probe = 'new' and replay.probe = 'new-replay'
  )
    and (
      select pg_catalog.count(*) = 1
      from public.stock_number_allocations allocation
      where allocation.inventory_unit_id = (
        select inventory_unit_id from pg_temp.intake_results where probe = 'new'
      )
    ),
  'T-NUM-003 replay returns original evidence and cannot allocate twice'
);
select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'new'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'new'),
      (select aggregate_version from pg_temp.decode_results where probe = 'new'),
      'intake-create-new-001', 2003, 'HONDA', 'Accord', true, 2600000
    )
  $$,
  '23505',
  'inventory intake idempotency key was used for a different request',
  'changed command data cannot reuse an intake idempotency key'
);
select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'new'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'new'),
      (select aggregate_version from pg_temp.decode_results where probe = 'new'),
      'intake-second-key-001', 2003, 'HONDA', 'Accord'
    )
  $$,
  '23505',
  'VIN request was already consumed',
  'one decode request cannot create a second holding episode under another key'
);
select extensions.throws_ok(
  $$update public.vin_inventory_intakes set idempotency_key = 'tampered-intake-key'$$,
  '42501',
  'permission denied for table vin_inventory_intakes',
  'authenticated callers cannot mutate immutable intake receipts'
);

reset role;
select extensions.throws_ok(
  $$
    update public.vin_inventory_intakes
    set idempotency_key = 'owner-tampered-intake-key'
  $$,
  '55000',
  'VIN decode result and review history is append-only',
  'even the table owner cannot rewrite a VIN intake receipt'
);
select extensions.throws_ok(
  $$
    update public.vin_decode_requests
    set version = version + 1
    where id = (
      select vin_decode_request_id from pg_temp.decode_results where probe = 'new'
    )
  $$,
  '55000',
  'consumed VIN decode requests are immutable',
  'consumed request state cannot be reopened or advanced'
);

set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.review_vin_duplicate_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'new'),
      'review-after-consume-001', 'override_open_duplicate',
      'Late review must not alter consumed history',
      'request-review-after-consume', pg_catalog.gen_random_uuid()
    )
  $$,
  '55000',
  'consumed VIN decode requests cannot be reviewed',
  'duplicate decisions cannot be appended after inventory consumption'
);

-- Historical VINs may create a new holding episode only after a matching
-- reacquisition review. The legacy primitive is invoked by the owner solely to
-- build a pre-migration fixture; API roles remain unable to call it.
reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
insert into pg_temp.legacy_inventory_results
select result.*, 'historical'
from app.create_inventory_unit(
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'historical-fixture-001', '1HGCM82633A900013', 2004, 'HONDA', 'Civic',
  date '2026-01-01', 50000, 'km', 'CAD', 1000000, null,
  'request-historical-fixture', pg_catalog.gen_random_uuid()
);
update public.workflow_instances instance
set current_state_key = 'closed',
    canonical_status = 'closed',
    lifecycle_status = 'completed',
    version = 2,
    completed_at = pg_catalog.statement_timestamp()
from pg_temp.legacy_inventory_results fixture
where fixture.probe = 'historical'
  and instance.entity_type = 'inventory_unit'
  and instance.entity_id = fixture.inventory_unit_id;
update public.inventory_units unit
set status = 'closed',
    workflow_state_key = case
      when unit.workflow_instance_id is null then null else 'closed'
    end,
    version = 2,
    closed_at = pg_catalog.statement_timestamp()
from pg_temp.legacy_inventory_results fixture
where fixture.probe = 'historical'
  and unit.id = fixture.inventory_unit_id;

set local role authenticated;
insert into pg_temp.decode_results
select prepared.*, 'historical'
from pg_temp.prepare_successful_decode(
  '1HGCM82633A900013',
  'intake-decode-history-001',
  'intake-worker-history',
  2004,
  'HONDA',
  'Civic'
) prepared;
select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'historical'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'historical'),
      (select aggregate_version from pg_temp.decode_results where probe = 'historical'),
      'intake-history-before-review', 2004, 'HONDA', 'Civic'
    )
  $$,
  '55000',
  'current VIN duplicate state requires a completed review',
  'historical inventory cannot bypass a reacquisition review'
);
select extensions.lives_ok(
  $$
    select * from app.review_vin_duplicate_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'historical'),
      'review-history-001', 'reacquire_existing_vehicle',
      'Closed holding episode verified before reacquisition',
      'request-review-history', pg_catalog.gen_random_uuid()
    )
  $$,
  'controlled historical reacquisition records its required review'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.intake_results
    select result.*, 'historical'
    from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'historical'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'historical'),
      3,
      'intake-history-after-review', 2004, 'HONDA', 'Civic'
    ) result
  $$,
  'reviewed historical VIN creates a new holding episode'
);
select extensions.ok(
  (
    select created.vehicle_id = historical.vehicle_id
      and created.inventory_unit_id <> historical.inventory_unit_id
      and created.stock_number <> historical.stock_number
    from pg_temp.intake_results created
    cross join pg_temp.legacy_inventory_results historical
    where created.probe = 'historical' and historical.probe = 'historical'
  ),
  'historical reacquisition reuses physical identity but allocates a new permanent stock number'
);
select extensions.throws_ok(
  $$
    select *
    from app.override_vehicle_facts(
      '10000000-0000-4000-8000-000000000001',
      'intake-history-stale-facts',
      (
        select vehicle_id
        from pg_temp.intake_results
        where probe = 'historical'
      ),
      1,
      2004, 'HONDA', 'Civic', 'Sedan', 4, 'FWD', '2.4', 'Gasoline',
      160, 'Automatic', 'EX', 'Stale correction after confirmed intake',
      'request-intake-history-stale-facts',
      'a7110000-0000-4000-8000-000000000001'
    )
  $$,
  '40001',
  'vehicle facts version conflict',
  'M2-INV-AC-002 historical null-fact fill advances optimistic concurrency'
);

-- An open holding episode is never duplicated. A reasoned, stepped-up manager
-- review authorizes a one-time linkage to the existing open unit without
-- allocating another stock number.
reset role;
insert into pg_temp.legacy_inventory_results
select result.*, 'open'
from app.create_inventory_unit(
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'open-fixture-001', '1HGCM82633A900014', 2005, 'HONDA', 'CR-V',
  date '2026-02-01', 60000, 'km', 'CAD', 1200000, null,
  'request-open-fixture', pg_catalog.gen_random_uuid()
);
update public.inventory_units unit
set location_id = '73000000-0000-4000-8000-000000000001',
    condition_key = 'used.ready'
from pg_temp.legacy_inventory_results fixture
where fixture.probe = 'open'
  and unit.id = fixture.inventory_unit_id;
set local role authenticated;
insert into pg_temp.decode_results
select prepared.*, 'open'
from pg_temp.prepare_successful_decode(
  '1HGCM82633A900014',
  'intake-decode-open-001',
  'intake-worker-open',
  2005,
  'HONDA',
  'CR-V'
) prepared;
select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'open'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'open'),
      (select aggregate_version from pg_temp.decode_results where probe = 'open'),
      'intake-open-before-review', 2005, 'HONDA', 'CR-V'
    )
  $$,
  '55000',
  'current VIN duplicate state requires a completed review',
  'open inventory cannot bypass a duplicate review'
);
select extensions.ok(
  (
    select approved_for_intake
    from app.review_vin_duplicate_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'open'),
      'review-open-001', 'override_open_duplicate',
      'Open holding episode conflict acknowledged',
      'request-review-open', pg_catalog.gen_random_uuid()
    )
  ),
  'authorized stepped-up review truthfully approves safe existing-unit linkage'
);
select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'open'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'open'),
      3,
      'intake-open-conflicting-facts', 2006, 'HONDA', 'CR-V'
    )
  $$,
  '23514',
  'confirmed VIN facts conflict with authoritative vehicle facts',
  'M2-INV-AC-003 confirmed open-unit linkage rejects conflicting authoritative facts'
);
select extensions.throws_ok(
  $$
    select * from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'open'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'open'),
      3,
      'intake-open-discarded-details', 2005, 'HONDA', 'CR-V'
    )
  $$,
  '22023',
  'open VIN linkage cannot change inventory-unit details',
  'M2-INV-AC-003 open linkage rejects inventory details instead of discarding them'
);
create temporary table pg_temp.stock_before_open as
select next_sequence_value
from public.stock_number_counters
where workspace_id = '10000000-0000-4000-8000-000000000001'
  and definition_id = '71000000-0000-4000-8000-000000000001';
grant select on pg_temp.stock_before_open to authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.intake_results
    select result.*, 'open'
    from pg_temp.create_confirmed_intake(
      (select vin_decode_request_id from pg_temp.decode_results where probe = 'open'),
      (select vin_decode_result_id from pg_temp.decode_results where probe = 'open'),
      3,
      'intake-open-after-review', 2005, 'HONDA', 'CR-V', true, 2500000, true
    ) result
  $$,
  'open duplicate review safely links the existing holding episode'
);
select extensions.is(
  (
    select next_sequence_value
    from public.stock_number_counters
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and definition_id = '71000000-0000-4000-8000-000000000001'
  ),
  (select next_sequence_value from pg_temp.stock_before_open),
  'T-NUM-002 linked open duplicate never burns a stock number'
);
select extensions.ok(
  (
    select linked.inventory_unit_id = existing.inventory_unit_id
      and linked.stock_number = existing.stock_number
      and linked.linked_existing_open_unit
    from pg_temp.intake_results linked
    cross join pg_temp.legacy_inventory_results existing
    where linked.probe = 'open' and existing.probe = 'open'
  ),
  'open override returns the existing unit and stock allocation'
);
select extensions.ok(
  (
    select vehicle.model_year = 2005
      and vehicle.make = 'HONDA'
      and vehicle.model = 'CR-V'
      and vehicle.body_type = 'Sedan'
      and vehicle.cylinders = 4
      and vehicle.drivetrain = 'FWD'
      and vehicle.engine_displacement_liters = 2.400
      and vehicle.fuel_type = 'Gasoline'
      and vehicle.horsepower = 160
      and vehicle.transmission = 'Automatic'
      and vehicle.trim_name = 'EX'
      and vehicle.facts_version = 2
    from public.vehicles vehicle
    join pg_temp.intake_results linked on linked.vehicle_id = vehicle.id
    where linked.probe = 'open'
  ),
  'M2-INV-AC-002 compatible open-unit linkage persists previously-null confirmed facts before returning'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.create_inventory_unit(uuid,uuid,text,text,integer,text,text,date,bigint,text,text,bigint,text,text,uuid)',
    'EXECUTE'
  ),
  'legacy create remains unavailable after every canonical duplicate path'
);

select * from extensions.finish();
rollback;
