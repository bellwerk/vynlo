-- VYN-INV-001, VYN-INV-002, VYN-NUM-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001, VYN-API-001, T-INV-001, T-INV-002,
-- T-INV-003, T-NUM-001, T-RBAC-001, T-AUD-001
-- M2-INV-AC-002, M2-INV-AC-003, M2-INV-AC-004, M2-INV-AC-010,
-- M2-INV-AC-011
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(44);

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

create function pg_temp.prepare_dead_letter_decode(
  fixture_vin text,
  fixture_key text,
  fixture_worker text
)
returns table (
  vin_decode_request_id uuid,
  aggregate_version bigint,
  terminal_job_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested record;
  claimed record;
begin
  select result.* into requested
  from app.request_vin_decode_job(
    '10000000-0000-4000-8000-000000000001',
    fixture_key,
    fixture_vin,
    2008,
    'request-' || fixture_key,
    pg_catalog.gen_random_uuid()
  ) result;

  select job.* into claimed
  from app.claim_jobs(
    fixture_worker,
    1,
    300,
    array['inventory.vin_decode']
  ) job;
  if claimed.job_id is null
    or claimed.entity_id is distinct from requested.vin_decode_request_id then
    raise exception 'unexpected VIN job claim';
  end if;

  perform app.fail_job(
    claimed.job_id,
    fixture_worker,
    claimed.lease_token,
    'permanent',
    'provider_terminal_fixture',
    'Synthetic terminal provider failure retained for manual intake evidence.',
    'provider-request-fixture',
    null
  );

  return query select requested.vin_decode_request_id,
    requested.aggregate_version, claimed.job_id;
end;
$$;

create function pg_temp.prepare_retried_dead_letter_decode(
  fixture_vin text,
  fixture_request_key text,
  fixture_retry_key text,
  fixture_worker text
)
returns table (
  vin_decode_request_id uuid,
  aggregate_version bigint,
  terminal_job_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  prepared record;
  retried record;
  claimed record;
begin
  select result.* into prepared
  from pg_temp.prepare_dead_letter_decode(
    fixture_vin,
    fixture_request_key,
    fixture_worker || '-initial'
  ) result;

  select result.* into retried
  from app.retry_vin_decode_job(
    '10000000-0000-4000-8000-000000000001',
    prepared.vin_decode_request_id,
    fixture_retry_key,
    'Retry the terminal provider failure before manual intake.',
    'request-' || fixture_retry_key,
    pg_catalog.gen_random_uuid()
  ) result;

  select job.* into claimed
  from app.claim_jobs(
    fixture_worker || '-retry',
    1,
    300,
    array['inventory.vin_decode']
  ) job;
  if claimed.job_id is null
    or claimed.job_id is distinct from retried.job_id
    or claimed.entity_id is distinct from prepared.vin_decode_request_id then
    raise exception 'unexpected retried VIN job claim';
  end if;

  perform app.fail_job(
    claimed.job_id,
    fixture_worker || '-retry',
    claimed.lease_token,
    'permanent',
    'provider_terminal_fixture',
    'Synthetic retried provider failure retained for manual intake evidence.',
    'provider-request-retry-fixture',
    null
  );

  return query select prepared.vin_decode_request_id,
    retried.aggregate_version, claimed.job_id;
end;
$$;

create function pg_temp.create_manual_intake(
  fixture_request_id uuid,
  fixture_version bigint,
  fixture_key text,
  fixture_price bigint default 9223372036854775807,
  fixture_duplicate_decision text default null,
  fixture_duplicate_reason text default null,
  fixture_model_year integer default 2008,
  fixture_make text default 'HONDA',
  fixture_model text default 'Pilot',
  fixture_link_existing boolean default false
)
returns table (
  vin_manual_inventory_intake_id uuid,
  vin_decode_request_id uuid,
  vin_decode_request_version bigint,
  terminal_job_id uuid,
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
  from app.create_inventory_unit_from_failed_vin_decode(
    '10000000-0000-4000-8000-000000000001',
    fixture_request_id,
    fixture_version,
    '71000000-0000-4000-8000-000000000001',
    '73000000-0000-4000-8000-000000000001',
    'used.ready',
    fixture_key,
    true,
    'Provider exhausted its durable attempts; operator confirmed manual facts.',
    fixture_duplicate_decision,
    fixture_duplicate_reason,
    fixture_model_year,
    fixture_make,
    fixture_model,
    'SUV',
    6,
    'AWD',
    '3.5',
    'Gasoline',
    250,
    'Automatic',
    'EX-L',
    case when fixture_link_existing then null else date '2026-07-16' end,
    case when fixture_link_existing then null else 140000 end,
    case when fixture_link_existing then null else 'km' end,
    'CAD',
    case when fixture_link_existing then null else fixture_price end,
    case when fixture_link_existing then null else 'Manual dead-letter intake fixture' end,
    'request-' || fixture_key,
    pg_catalog.gen_random_uuid()
  );
$$;

create temporary table pg_temp.failed_requests (
  vin_decode_request_id uuid,
  aggregate_version bigint,
  terminal_job_id uuid,
  probe text
);
create temporary table pg_temp.manual_results (
  vin_manual_inventory_intake_id uuid,
  vin_decode_request_id uuid,
  vin_decode_request_version bigint,
  terminal_job_id uuid,
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  audit_event_id uuid,
  outbox_event_id uuid,
  linked_existing_open_unit boolean,
  replayed boolean,
  probe text
);
grant all on pg_temp.failed_requests, pg_temp.manual_results
  to authenticated, service_role;
grant execute on function pg_temp.prepare_dead_letter_decode(text, text, text)
  to authenticated;
grant execute on function pg_temp.prepare_retried_dead_letter_decode(
  text, text, text, text
) to authenticated;
grant execute on function pg_temp.create_manual_intake(
  uuid, bigint, text, bigint, text, text, integer, text, text, boolean
)
  to authenticated;

select extensions.has_table(
  'public', 'inventory_condition_definitions',
  'workspace inventory condition configuration exists'
);
select extensions.has_table(
  'public', 'vin_inventory_intake_links',
  'one-request/one-unit VIN link receipts exist'
);
select extensions.has_table(
  'public', 'vin_manual_inventory_intakes',
  'manual dead-letter intake provenance exists'
);
select extensions.has_column(
  'public', 'vin_decode_requests',
  'consumed_by_manual_inventory_intake_id',
  'VIN requests expose an exclusive manual consumption reference'
);
select extensions.has_function(
  'app', 'create_inventory_unit_from_vin_decode',
  array[
    'uuid', 'uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text', 'text',
    'boolean', 'integer', 'text', 'text', 'text', 'integer', 'text', 'text',
    'text', 'integer', 'text', 'text', 'date', 'bigint', 'text', 'text',
    'bigint', 'text', 'text', 'uuid'
  ],
  'completed confirmed-decode intake signature exists'
);
select extensions.has_function(
  'app', 'create_inventory_unit_from_failed_vin_decode',
  array[
    'uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text', 'text', 'boolean',
    'text', 'text', 'text', 'integer', 'text', 'text', 'text', 'integer',
    'text', 'text', 'text', 'integer', 'text', 'text', 'date', 'bigint',
    'text', 'text', 'bigint', 'text', 'text', 'uuid'
  ],
  'manual dead-letter intake command exists'
);
select extensions.ok(
  (
    select
      pg_catalog.strpos(
        pg_catalog.lower(definition.function_definition),
        'for update'
      ) > 0
      and pg_catalog.strpos(
        pg_catalog.lower(definition.function_definition),
        'if target_request.consumed_at is not null'
      ) > pg_catalog.strpos(
        pg_catalog.lower(definition.function_definition),
        'for update'
      )
      and pg_catalog.strpos(
        pg_catalog.lower(definition.function_definition),
        'if target_request.consumed_at is not null'
      ) < pg_catalog.strpos(
        pg_catalog.lower(definition.function_definition),
        'into existing_retry_job'
      )
      and pg_catalog.strpos(
        pg_catalog.lower(definition.function_definition),
        'if target_request.consumed_at is not null'
      ) < pg_catalog.strpos(
        pg_catalog.lower(definition.function_definition),
        'from app.enqueue_outbox_job('
      )
    from information_schema.routines definition
    where definition.routine_schema = 'app'
      and definition.routine_name = 'retry_vin_decode_job'
  ),
  'M2-INV-AC-004 retry locks the VIN request and rejects consumption before replay or enqueue'
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
  ),
  'authenticated callers can execute only the complete confirmed signature'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.create_inventory_unit_from_failed_vin_decode(uuid,uuid,bigint,uuid,uuid,text,text,boolean,text,text,text,integer,text,text,text,integer,text,text,text,integer,text,text,date,bigint,text,text,bigint,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated callers can execute the guarded manual command'
);

select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'inventory_condition_definitions'
  ),
  'condition configuration uses forced RLS'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'vin_inventory_intake_links'
  ),
  'VIN link receipts use forced RLS'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'vin_manual_inventory_intakes'
  ),
  'manual intake provenance uses forced RLS'
);
select extensions.ok(
  pg_catalog.has_table_privilege(
    'authenticated', 'public.inventory_condition_definitions', 'SELECT'
  ),
  'authorized browser reads can resolve configured condition labels'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.vin_inventory_intake_links', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.vin_manual_inventory_intakes', 'SELECT'
  ),
  'browser roles cannot disclose manual or linkage provenance'
);
select extensions.ok(
  pg_catalog.has_table_privilege(
    'service_role', 'public.vin_inventory_intake_links', 'SELECT'
  )
  and pg_catalog.has_table_privilege(
    'service_role', 'public.vin_manual_inventory_intakes', 'SELECT'
  ),
  'service role has narrow read-only provenance access'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.failed_requests
select prepared.*, 'manual'
from pg_temp.prepare_dead_letter_decode(
  '1HGCM82633A900018',
  'manual-decode-018-001',
  'manual-worker-018-001'
) prepared;

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from pg_temp.create_manual_intake(
      (select vin_decode_request_id from pg_temp.failed_requests where probe = 'manual'),
      (select aggregate_version from pg_temp.failed_requests where probe = 'manual'),
      'manual-cross-workspace-018'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'M2-INV-AC-010 another workspace cannot consume a terminal VIN request'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.throws_ok(
  $$
    select * from pg_temp.create_manual_intake(
      (select vin_decode_request_id from pg_temp.failed_requests where probe = 'manual'),
      (select aggregate_version from pg_temp.failed_requests where probe = 'manual'),
      'manual-without-permission-018'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'M2-INV-AC-010 a member without inventory.create cannot consume manual facts'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');

select extensions.lives_ok(
  $$
    insert into pg_temp.manual_results
    select result.*, 'first'
    from pg_temp.create_manual_intake(
      (select vin_decode_request_id from pg_temp.failed_requests where probe = 'manual'),
      (select aggregate_version from pg_temp.failed_requests where probe = 'manual'),
      'manual-intake-018-001',
      9223372036854775807
    ) result
  $$,
  'manual facts create inventory after the authoritative job dead-letters'
);
select extensions.ok(
  (
    select unit.location_id = '73000000-0000-4000-8000-000000000001'
      and unit.condition_key = 'used.ready'
    from public.inventory_units unit
    join pg_temp.manual_results result on result.inventory_unit_id = unit.id
    where result.probe = 'first'
  ),
  'manual intake atomically persists active location and configured condition'
);
select extensions.is(
  (
    select unit.advertised_price_minor
    from public.inventory_units unit
    join pg_temp.manual_results result on result.inventory_unit_id = unit.id
    where result.probe = 'first'
  ),
  9223372036854775807::bigint,
  'manual intake preserves exact PostgreSQL bigint minor units'
);
select extensions.ok(
  (
    select request.consumed_at is not null
      and request.consumed_by_inventory_intake_id is null
      and request.consumed_by_manual_inventory_intake_id = result.vin_manual_inventory_intake_id
    from public.vin_decode_requests request
    join pg_temp.manual_results result
      on result.vin_decode_request_id = request.id
    where result.probe = 'first'
  ),
  'manual consumption is exclusive and irreversible'
);
select extensions.ok(
  (
    select status = 'consumed'
      and job_status = 'dead_letter'
      and not retryable
      and not review_required
    from app.get_vin_decode_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.failed_requests where probe = 'manual')
    )
  ),
  'M2-INV-AC-004 consumed manual request is terminal while dead-letter history remains visible'
);
select extensions.ok(
  (
    select intake.terminal_job_id = failed.terminal_job_id
      and intake.terminal_failure_snapshot ->> 'last_error_code'
        = 'provider_terminal_fixture'
    from public.vin_manual_inventory_intakes intake
    join pg_temp.failed_requests failed
      on failed.vin_decode_request_id = intake.vin_decode_request_id
    where failed.probe = 'manual'
  ),
  'manual provenance references and snapshots the terminal failure safely'
);
select extensions.ok(
  (
    select event.payload ?& array[
      'inventoryUnitId', 'vehicleId', 'vinDecodeRequestId',
      'vinManualInventoryIntakeId', 'vinInventoryIntakeLinkId', 'terminalJobId'
    ]
      and not event.payload ?| array[
        'manualReason', 'manualFacts', 'providerError',
        'advertisedPriceMinor', 'make', 'model'
      ]
    from public.outbox_events event
    join pg_temp.manual_results result on result.outbox_event_id = event.id
    where result.probe = 'first'
  ),
  'manual outbox evidence contains references only'
);
select extensions.ok(
  (
    select audit.action = 'inventory_unit.manual_intake_confirmed'
      and audit.after_data ->> 'approved_for_intake' = 'true'
      and audit.metadata ->> 'terminal_job_id' = result.terminal_job_id::text
    from public.audit_events audit
    join pg_temp.manual_results result on result.audit_event_id = audit.id
    where result.probe = 'first'
  ),
  'manual intake audit truthfully records approval and terminal lineage'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.manual_results
    select result.*, 'replay'
    from pg_temp.create_manual_intake(
      (select vin_decode_request_id from pg_temp.failed_requests where probe = 'manual'),
      (select aggregate_version from pg_temp.failed_requests where probe = 'manual'),
      'manual-intake-018-001',
      9223372036854775807
    ) result
  $$,
  'exact manual intake replay succeeds after consumption'
);
select extensions.ok(
  (
    select replay.replayed
      and replay.vin_manual_inventory_intake_id = original.vin_manual_inventory_intake_id
      and replay.inventory_unit_id = original.inventory_unit_id
      and replay.terminal_job_id = original.terminal_job_id
    from pg_temp.manual_results replay
    cross join pg_temp.manual_results original
    where replay.probe = 'replay' and original.probe = 'first'
  ),
  'manual replay returns the same receipt, unit, and terminal job'
);
select extensions.throws_ok(
  $$
    select * from pg_temp.create_manual_intake(
      (select vin_decode_request_id from pg_temp.failed_requests where probe = 'manual'),
      (select aggregate_version from pg_temp.failed_requests where probe = 'manual'),
      'manual-intake-018-001',
      9223372036854775806
    )
  $$,
  '23505',
  'manual VIN intake idempotency key was used for a different request',
  'changed manual replay fails before touching consumed state'
);

insert into pg_temp.failed_requests
select prepared.*, 'already-linked-open'
from pg_temp.prepare_dead_letter_decode(
  '1HGCM82633A900018',
  'manual-decode-018-002',
  'manual-worker-018-002'
) prepared;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
select extensions.throws_ok(
  $$
    select * from pg_temp.create_manual_intake(
      (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'already-linked-open'
      ),
      (
        select aggregate_version
        from pg_temp.failed_requests
        where probe = 'already-linked-open'
      ),
      'manual-intake-open-aal1-018',
      9223372036854775807,
      'override_open_duplicate',
      'Manager verified that this request refers to the existing open holding.'
    )
  $$,
  '42501',
  'recent strong authentication is required for duplicate override',
  'M2-INV-AC-010 AAL1 cannot authorize manual linkage to an open holding'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from pg_temp.create_manual_intake(
      (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'already-linked-open'
      ),
      (
        select aggregate_version
        from pg_temp.failed_requests
        where probe = 'already-linked-open'
      ),
      'manual-intake-open-conflict-018',
      9223372036854775807,
      'override_open_duplicate',
      'Manager verified that this request refers to the existing open holding.',
      2009,
      'HONDA',
      'Pilot'
    )
  $$,
  '23514',
  'confirmed VIN facts conflict with authoritative vehicle facts',
  'M2-INV-AC-003 manual open-unit linkage rejects conflicting authoritative facts'
);
select extensions.throws_ok(
  $$
    select * from pg_temp.create_manual_intake(
      (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'already-linked-open'
      ),
      (
        select aggregate_version
        from pg_temp.failed_requests
        where probe = 'already-linked-open'
      ),
      'manual-intake-open-discarded-details-018',
      9223372036854775807,
      'override_open_duplicate',
      'Manager verified that this request refers to the existing open holding.'
    )
  $$,
  '22023',
  'open VIN linkage cannot change inventory-unit details',
  'M2-INV-AC-003 manual open linkage rejects inventory details instead of discarding them'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.manual_results
    select result.*, 'already-linked-open'
    from pg_temp.create_manual_intake(
      (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'already-linked-open'
      ),
      (
        select aggregate_version
        from pg_temp.failed_requests
        where probe = 'already-linked-open'
      ),
      'manual-intake-018-002',
      9223372036854775807,
      'override_open_duplicate',
      'Manager verified that this request refers to the existing open holding.',
      2008,
      'HONDA',
      'Pilot',
      true
    ) result
  $$,
  'a later reviewed request can link an already-linked open holding'
);
select extensions.ok(
  (
    select later.inventory_unit_id = original.inventory_unit_id
      and later.stock_number = original.stock_number
      and later.vin_decode_request_id <> original.vin_decode_request_id
      and later.linked_existing_open_unit
      and not later.replayed
    from pg_temp.manual_results later
    cross join pg_temp.manual_results original
    where later.probe = 'already-linked-open'
      and original.probe = 'first'
  ),
  'independent open-duplicate request returns the existing unit and stock'
);
select extensions.ok(
  (
    select pg_catalog.count(distinct link.vin_decode_request_id) = 2
      and pg_catalog.count(distinct allocation.id) = 1
    from pg_temp.manual_results original
    join public.vin_inventory_intake_links link
      on link.workspace_id = '10000000-0000-4000-8000-000000000001'
     and link.inventory_unit_id = original.inventory_unit_id
    join public.stock_number_allocations allocation
      on allocation.workspace_id = link.workspace_id
     and allocation.inventory_unit_id = link.inventory_unit_id
    where original.probe = 'first'
  ),
  'two request receipts reference one open unit and one permanent allocation'
);

insert into pg_temp.failed_requests
select prepared.*, 'consumed-after-retry'
from pg_temp.prepare_retried_dead_letter_decode(
  '1HGCM82633A900020',
  'manual-decode-018-003',
  'manual-retry-018-003',
  'manual-worker-018-003'
) prepared;
select extensions.lives_ok(
  $$
    insert into pg_temp.manual_results
    select result.*, 'consumed-after-retry'
    from pg_temp.create_manual_intake(
      (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'consumed-after-retry'
      ),
      (
        select aggregate_version
        from pg_temp.failed_requests
        where probe = 'consumed-after-retry'
      ),
      'manual-intake-018-003',
      3500000
    ) result
  $$,
  'a dead-letter retry can be consumed exactly once by manual intake'
);
select extensions.throws_ok(
  $$
    select *
    from app.retry_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'consumed-after-retry'
      ),
      'manual-retry-018-003',
      'Retry the terminal provider failure before manual intake.',
      'request-consumed-retry-replay-018',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '55000',
  'consumed VIN requests cannot be retried',
  'M2-INV-AC-004 a consumed request rejects an otherwise exact retry replay'
);
select extensions.throws_ok(
  $$
    select *
    from app.retry_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'consumed-after-retry'
      ),
      'manual-retry-consumed-fresh-018',
      'A fresh retry must not bypass terminal consumption.',
      'request-consumed-retry-fresh-018',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '55000',
  'consumed VIN requests cannot be retried',
  'M2-INV-AC-004 a consumed request rejects a fresh retry command'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 2
    from public.jobs job
    where job.workspace_id = '10000000-0000-4000-8000-000000000001'
      and job.job_type = 'inventory.vin_decode'
      and job.entity_type = 'vin_decode_request'
      and job.entity_id = (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'consumed-after-retry'
      )
  )
  and (
    select pg_catalog.count(*) = 1
    from public.audit_events audit
    where audit.workspace_id = '10000000-0000-4000-8000-000000000001'
      and audit.entity_type = 'vin_decode_request'
      and audit.entity_id = (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'consumed-after-retry'
      )
      and audit.action = 'inventory.vin_decode_retry_requested'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.outbox_events event
    where event.workspace_id = '10000000-0000-4000-8000-000000000001'
      and event.aggregate_type = 'vin_decode_request'
      and event.aggregate_id = (
        select vin_decode_request_id
        from pg_temp.failed_requests
        where probe = 'consumed-after-retry'
      )
      and event.event_name = 'inventory.vin_decode_retry_requested'
  ),
  'consumed retry rejection creates no job, audit, or outbox side effects'
);

insert into pg_temp.failed_requests (
  vin_decode_request_id, aggregate_version, terminal_job_id, probe
)
select requested.vin_decode_request_id, requested.aggregate_version,
  requested.job_id, 'pending'
from app.request_vin_decode_job(
  '10000000-0000-4000-8000-000000000001',
  'manual-pending-018-001',
  '1HGCM82633A900019',
  2008,
  'request-manual-pending-018-001',
  pg_catalog.gen_random_uuid()
) requested;
select extensions.throws_ok(
  $$
    select * from pg_temp.create_manual_intake(
      (select vin_decode_request_id from pg_temp.failed_requests where probe = 'pending'),
      (select aggregate_version from pg_temp.failed_requests where probe = 'pending'),
      'manual-intake-pending-018',
      2500000
    )
  $$,
  '55000',
  'manual intake requires the authoritative latest VIN job to be dead letter',
  'queued or retryable VIN work cannot be bypassed by manual intake'
);

reset role;
select extensions.throws_ok(
  $$
    update public.vin_manual_inventory_intakes
    set manual_reason = 'rewritten'
    where id = (
      select vin_manual_inventory_intake_id
      from pg_temp.manual_results where probe = 'first'
    )
  $$,
  '55000',
  'VIN decode result and review history is append-only',
  'manual intake provenance is append-only even for the owner'
);
select extensions.throws_ok(
  $$
    delete from public.vin_inventory_intake_links
    where id = (
      select intake.link_receipt_id
      from public.vin_manual_inventory_intakes intake
      join pg_temp.manual_results result
        on result.vin_manual_inventory_intake_id = intake.id
      where result.probe = 'first'
    )
  $$,
  '55000',
  'VIN decode result and review history is append-only',
  'one-unit linkage receipts are append-only'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.stock_number_allocations allocation
    join pg_temp.manual_results result
      on result.inventory_unit_id = allocation.inventory_unit_id
    where result.probe = 'first'
  ),
  1::bigint,
  'manual intake commits exactly one permanent stock allocation'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.vin_decode_results result
    join pg_temp.failed_requests failed
      on failed.vin_decode_request_id = result.vin_decode_request_id
    where failed.probe = 'manual'
  ),
  0::bigint,
  'manual intake does not fabricate a provider decode result'
);
select extensions.ok(
  (
    select job.status = 'dead_letter'
      and job.last_error_code = 'provider_terminal_fixture'
      and job.last_error_detail_safe is not null
    from public.jobs job
    join pg_temp.failed_requests failed on failed.terminal_job_id = job.id
    where failed.probe = 'manual'
  ),
  'manual intake preserves the authoritative job failure history unchanged'
);

select * from extensions.finish();
rollback;
