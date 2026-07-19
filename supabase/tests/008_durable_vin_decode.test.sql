-- VYN-INV-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-JOB-001,
-- VYN-API-001, T-INV-001, T-INV-002, T-INV-003, T-TEN-001, T-RBAC-001,
-- T-AUD-001, T-JOB-001, T-JOB-003
-- M2-INV-AC-001, M2-INV-AC-002, M2-INV-AC-003, M2-INV-AC-004,
-- M2-INV-AC-010, M2-INV-AC-011
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(58);

-- Test-only compatibility grant used to build the existing duplicate fixture.
-- The transaction rolls it back; 011 proves the production revocation.
grant execute on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) to authenticated;

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  assurance text default 'aal2',
  strong_age_seconds integer default 0
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
        )::bigint - strong_age_seconds
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.vin_request_results (
  vin_decode_request_id uuid,
  job_id uuid,
  outbox_event_id uuid,
  job_status text,
  duplicate_candidate_count integer,
  aggregate_version bigint,
  audit_event_id uuid,
  replayed boolean,
  probe text
);
create temporary table pg_temp.claimed_vin_jobs (
  job_id uuid,
  workspace_id uuid,
  outbox_event_id uuid,
  job_type text,
  entity_type text,
  entity_id uuid,
  payload_schema_version integer,
  payload jsonb,
  idempotency_key text,
  attempt_number integer,
  max_attempts integer,
  lease_token uuid,
  lease_expires_at timestamptz,
  correlation_id uuid,
  causation_id uuid,
  probe text
);
create temporary table pg_temp.vin_completion_results (
  vin_decode_result_id uuid,
  decode_status text,
  duplicate_candidate_count integer,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean,
  probe text
);
create temporary table pg_temp.inventory_create_results (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean
);
create temporary table pg_temp.vin_review_results (
  vin_duplicate_review_id uuid,
  vin_decode_request_id uuid,
  vehicle_id uuid,
  decision text,
  approved_for_intake boolean,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean,
  probe text
);
create temporary table pg_temp.vin_retry_results (
  vin_decode_request_id uuid,
  job_id uuid,
  outbox_event_id uuid,
  job_status text,
  aggregate_version bigint,
  audit_event_id uuid,
  replayed boolean,
  probe text
);
grant all on
  pg_temp.vin_request_results,
  pg_temp.claimed_vin_jobs,
  pg_temp.vin_completion_results,
  pg_temp.inventory_create_results,
  pg_temp.vin_review_results,
  pg_temp.vin_retry_results
to authenticated, service_role;

select extensions.has_column('public', 'vehicles', 'body_type', 'vehicles store confirmed body type');
select extensions.has_column('public', 'vehicles', 'cylinders', 'vehicles store confirmed cylinder count');
select extensions.has_column('public', 'vehicles', 'drivetrain', 'vehicles store confirmed drivetrain');
select extensions.has_column(
  'public', 'vehicles', 'engine_displacement_liters',
  'vehicles store exact decimal engine displacement'
);
select extensions.has_column('public', 'vehicles', 'fuel_type', 'vehicles store confirmed fuel type');
select extensions.has_column('public', 'vehicles', 'horsepower', 'vehicles store confirmed horsepower');
select extensions.has_column('public', 'vehicles', 'transmission', 'vehicles store confirmed transmission');
select extensions.has_column('public', 'vehicles', 'trim_name', 'vehicles use non-keyword trim_name');
select extensions.has_table('public', 'vin_decode_requests', 'durable VIN request aggregate exists');
select extensions.has_table('public', 'vin_decode_results', 'immutable raw and mapped VIN result exists');
select extensions.has_table('public', 'vin_duplicate_candidates', 'duplicate snapshots exist');
select extensions.has_table('public', 'vin_duplicate_reviews', 'duplicate decisions exist');
select extensions.has_function(
  'app', 'request_vin_decode_job',
  array['uuid', 'text', 'text', 'integer', 'text', 'uuid'],
  'VIN request command exists'
);
select extensions.has_function(
  'app', 'get_vin_decode_request', array['uuid', 'uuid'],
  'safe VIN status projection exists'
);
select extensions.has_function(
  'app', 'retry_vin_decode_job',
  array['uuid', 'uuid', 'text', 'text', 'text', 'uuid'],
  'dead-letter retry command exists'
);
select extensions.has_function(
  'app', 'review_vin_duplicate_request',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'uuid'],
  'duplicate review command exists'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 4
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'vin_decode_requests', 'vin_decode_results',
        'vin_duplicate_candidates', 'vin_duplicate_reviews'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'T-TEN-001 every VIN relation has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.vin_decode_requests', 'SELECT'
  )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.vin_decode_results', 'SELECT'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.vin_duplicate_reviews', 'INSERT'
    ),
  'T-RBAC-001 browser access is limited to narrow RPC projections'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.request_vin_decode_job(uuid,text,text,integer,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.complete_vin_decode_request(uuid,uuid,uuid,text,uuid,text,text,timestamptz,jsonb,jsonb,integer,text,text,text,integer,text,text,text,integer,text,text,text,uuid)',
      'EXECUTE'
    )
    and pg_catalog.has_function_privilege(
      'service_role',
      'app.complete_vin_decode_request(uuid,uuid,uuid,text,uuid,text,text,timestamptz,jsonb,jsonb,integer,text,text,text,integer,text,text,text,integer,text,text,text,uuid)',
      'EXECUTE'
    ),
  'worker completion is service-only while request commands are authenticated'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.request_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      'vin-limited-denied', '1HGCM82633A004352', null,
      'request-vin-limited', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-RBAC-001 inventory.create is required to queue a VIN decode'
);
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from app.request_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      'vin-cross-denied', '1HGCM82633A004352', null,
      'request-vin-cross', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 another workspace cannot queue work in Northstar'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_request_results
    select result.*, 'initial'
    from app.request_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      'vin-request-001', ' 1hgcm82633a004352 ', 2003,
      'request-vin-001', 'a8100000-0000-4000-8000-000000000001'
    ) result
  $$,
  'M2-INV-AC-002 manual or pasted VIN queues one durable request'
);
select extensions.results_eq(
  $$
    select job_status, duplicate_candidate_count, aggregate_version, replayed
    from pg_temp.vin_request_results where probe = 'initial'
  $$,
  $$values ('queued'::text, 0, 1::bigint, false)$$,
  'new VIN request reports queued state without a false duplicate'
);
reset role;
select extensions.ok(
  (
    select request.vin::text = '1HGCM82633A004352'
      and job.job_type = 'inventory.vin_decode'
      and job.entity_type = 'vin_decode_request'
      and job.payload = pg_catalog.jsonb_build_object(
        'request_id', request.id,
        'vin', '1HGCM82633A004352',
        'model_year_hint', 2003
      )
      and event.event_name = 'inventory.vin_decode_requested'
      and event.aggregate_id = request.id
    from pg_temp.vin_request_results result
    join public.vin_decode_requests request on request.id = result.vin_decode_request_id
    join public.jobs job on job.id = result.job_id
    join public.outbox_events event on event.id = result.outbox_event_id
    where result.probe = 'initial'
  ),
  'T-JOB-001 request, exact safe payload, outbox event, and job commit together'
);
select extensions.is(
  (select pg_catalog.count(*) from public.inventory_units),
  0::bigint,
  'T-INV-001 VIN decode does not allocate stock or create inventory'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_request_results
    select result.*, 'replay'
    from app.request_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      'vin-request-001', '1HGCM82633A004352', 2003,
      'request-vin-replay', pg_catalog.gen_random_uuid()
    ) result
  $$,
  'exact VIN request replay succeeds'
);
select extensions.ok(
  (
    select replay.vin_decode_request_id = initial.vin_decode_request_id
      and replay.job_id = initial.job_id
      and replay.outbox_event_id = initial.outbox_event_id
      and replay.audit_event_id = initial.audit_event_id
      and replay.replayed
    from pg_temp.vin_request_results initial
    cross join pg_temp.vin_request_results replay
    where initial.probe = 'initial' and replay.probe = 'replay'
  ),
  'M2-INV-AC-011 VIN request replay returns all original identifiers'
);
select extensions.throws_ok(
  $$
    select * from app.request_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      'vin-request-001', '1HGCM82633A004352', 2004,
      'request-vin-conflict', pg_catalog.gen_random_uuid()
    )
  $$,
  '23505',
  'VIN idempotency key was used for a different request',
  'same VIN idempotency key rejects a changed model-year hint'
);

reset role;
select extensions.lives_ok(
  $$
    insert into pg_temp.claimed_vin_jobs
    select claimed.*, 'initial'
    from app.claim_jobs('vin-worker-a', 10, 300, array['inventory.vin_decode']) claimed
  $$,
  'durable runner claims the queued VIN request'
);
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.claimed_vin_jobs where probe = 'initial'),
  1::bigint,
  'one VIN request produces one claimed provider job'
);
select extensions.throws_ok(
  $$
    select * from app.complete_vin_decode_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'initial'),
      (select job_id from pg_temp.claimed_vin_jobs where probe = 'initial'),
      'vin-worker-stale',
      (select lease_token from pg_temp.claimed_vin_jobs where probe = 'initial'),
      'nhtsa_vpic', 'vpic-4.06', timestamptz '2026-07-16 12:00:00+00',
      '{"Results":[]}'::jsonb, '[]'::jsonb,
      2003, 'HONDA', 'Accord', 'Sedan/Saloon', 4, '4x2', '2.4',
      'Gasoline', 160, 'Automatic', 'EX-V6',
      'job-vin-stale-worker',
      (select correlation_id from pg_temp.claimed_vin_jobs where probe = 'initial')
    )
  $$,
  '55000',
  'only the matching active lease owner can record a VIN result',
  'T-JOB-001 stale worker identity cannot persist a provider result'
);
select extensions.throws_ok(
  $$
    select * from app.complete_vin_decode_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'initial'),
      (select job_id from pg_temp.claimed_vin_jobs where probe = 'initial'),
      'vin-worker-a', pg_catalog.gen_random_uuid(),
      'nhtsa_vpic', 'vpic-4.06', timestamptz '2026-07-16 12:00:00+00',
      '{"Results":[]}'::jsonb, '[]'::jsonb,
      2003, 'HONDA', 'Accord', 'Sedan/Saloon', 4, '4x2', '2.4',
      'Gasoline', 160, 'Automatic', 'EX-V6',
      'job-vin-stale-lease',
      (select correlation_id from pg_temp.claimed_vin_jobs where probe = 'initial')
    )
  $$,
  '55000',
  'only the matching active lease owner can record a VIN result',
  'T-JOB-001 stale lease token cannot persist a provider result'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_completion_results
    select result.*, 'initial'
    from app.complete_vin_decode_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'initial'),
      (select job_id from pg_temp.claimed_vin_jobs where probe = 'initial'),
      'vin-worker-a',
      (select lease_token from pg_temp.claimed_vin_jobs where probe = 'initial'),
      'nhtsa_vpic', 'vpic-4.06', timestamptz '2026-07-16 12:00:00+00',
      '{"Results":[{"Make":"HONDA"}]}'::jsonb,
      '["decoded clean"]'::jsonb,
      2003, 'HONDA', 'Accord', 'Sedan/Saloon', 4, '4x2', '2.4',
      'Gasoline', 160, 'Automatic', 'EX-V6',
      'job-vin-complete',
      (select correlation_id from pg_temp.claimed_vin_jobs where probe = 'initial')
    ) result
  $$,
  'M2-INV-AC-002 matching worker lease persists raw and mapped VIN data'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.vin_completion_results completion
    join public.vin_decode_results result
      on result.id = completion.vin_decode_result_id
    where completion.probe = 'initial'
      and completion.decode_status = 'succeeded'
      and completion.aggregate_version = 2
      and not completion.replayed
      and result.provider_key = 'nhtsa_vpic'
      and result.raw_response = '{"Results":[{"Make":"HONDA"}]}'::jsonb
      and result.engine_displacement_liters = 2.400
      and result.trim_name = 'EX-V6'
  ),
  'raw response, exact decimal displacement, and trim_name retain provenance'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.vin_completion_results completion
    join public.audit_events audit on audit.id = completion.audit_event_id
    join public.outbox_events event on event.id = completion.outbox_event_id
    where completion.probe = 'initial'
      and audit.action = 'inventory.vin_decode_succeeded'
      and audit.actor_type = 'worker'
      and event.event_name = 'inventory.vin_decode_succeeded'
      and event.payload::text not like '%Results%'
  ),
  'T-AUD-001 completion is audited and emits metadata without raw provider data'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_completion_results
    select result.*, 'replay'
    from app.complete_vin_decode_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'initial'),
      (select job_id from pg_temp.claimed_vin_jobs where probe = 'initial'),
      'vin-worker-a',
      (select lease_token from pg_temp.claimed_vin_jobs where probe = 'initial'),
      'nhtsa_vpic', 'vpic-4.06', timestamptz '2026-07-16 12:01:00+00',
      '{"Results":[{"Make":"CHANGED"}]}'::jsonb, '[]'::jsonb,
      2004, 'CHANGED', 'Changed', null, null, null, null, null, null, null, null,
      'job-vin-complete-replay',
      (select correlation_id from pg_temp.claimed_vin_jobs where probe = 'initial')
    ) result
  $$,
  'lease-valid completion replay preserves the immutable first result'
);
select extensions.ok(
  (
    select replay.vin_decode_result_id = initial.vin_decode_result_id
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
      and replay.replayed
    from pg_temp.vin_completion_results initial
    cross join pg_temp.vin_completion_results replay
    where initial.probe = 'initial' and replay.probe = 'replay'
  ),
  'M2-INV-AC-011 result replay returns original identifiers without overwrite'
);
select extensions.lives_ok(
  $$
    select app.complete_job(
      (select job_id from pg_temp.claimed_vin_jobs where probe = 'initial'),
      'vin-worker-a',
      (select lease_token from pg_temp.claimed_vin_jobs where probe = 'initial'),
      '{"decode_status":"succeeded"}'::jsonb,
      null
    )
  $$,
  'generic durable job completion follows fenced domain persistence'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  (
    select status = 'succeeded'
      and job_status = 'succeeded'
      and raw_result_reference is not null
      and provider_key = 'nhtsa_vpic'
      and trim_name = 'EX-V6'
      and engine_liters = '2.4'
      and duplicate_candidates = '[]'::jsonb
      and duplicate_review is null
    from app.get_vin_decode_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'initial')
    )
  ),
  'GET projection exposes suggestions and safe terminal job state without raw response'
);
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from app.get_vin_decode_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'initial')
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 status projection does not disclose another workspace request'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$update public.vin_decode_results set trim_name = 'tampered'$$,
  '42501',
  'permission denied for table vin_decode_results',
  'authenticated callers cannot mutate immutable VIN result history'
);

-- Build one open-inventory duplicate through the canonical M1 command. The
-- stock allocation is fixture setup; all counts below prove the VIN workflow
-- itself performs no further allocation.
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_create_results
    select * from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'vin-duplicate-fixture', '1FAFP404X1F192128', 2001, 'FORD', 'Mustang',
      date '2026-07-01', 50000, 'km', 'CAD', 1000000, null,
      'request-vin-duplicate-fixture', pg_catalog.gen_random_uuid()
    )
  $$,
  'synthetic open inventory duplicate fixture is created canonically'
);
reset role;
create temporary table pg_temp.stock_counter_before as
select next_sequence_value
from public.stock_number_counters
where workspace_id = '10000000-0000-4000-8000-000000000001'
  and definition_id = '71000000-0000-4000-8000-000000000001';
grant select on pg_temp.stock_counter_before to authenticated;
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_request_results
    select result.*, 'duplicate'
    from app.request_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      'vin-request-duplicate', '1FAFP404X1F192128', 2001,
      'request-vin-duplicate', 'a8200000-0000-4000-8000-000000000001'
    ) result
  $$,
  'same-workspace open duplicate still queues a provider suggestion request'
);
select extensions.results_eq(
  $$
    select duplicate_candidate_count
    from pg_temp.vin_request_results where probe = 'duplicate'
  $$,
  $$values (1)$$,
  'M2-INV-AC-003 open inventory is captured as an explicit duplicate candidate'
);

reset role;
insert into pg_temp.claimed_vin_jobs
select claimed.*, 'duplicate'
from app.claim_jobs('vin-worker-b', 10, 300, array['inventory.vin_decode']) claimed;
insert into pg_temp.vin_completion_results
select result.*, 'duplicate'
from app.complete_vin_decode_request(
  '10000000-0000-4000-8000-000000000001',
  (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'duplicate'),
  (select job_id from pg_temp.claimed_vin_jobs where probe = 'duplicate'),
  'vin-worker-b',
  (select lease_token from pg_temp.claimed_vin_jobs where probe = 'duplicate'),
  'nhtsa_vpic', 'vpic-4.06', pg_catalog.statement_timestamp(),
  '{"Results":[{"Make":"FORD"}]}'::jsonb, '[]'::jsonb,
  2001, 'FORD', 'Mustang', 'Coupe', 6, 'RWD', '3.8',
  'Gasoline', 193, 'Manual', 'Base', 'job-vin-duplicate',
  (select correlation_id from pg_temp.claimed_vin_jobs where probe = 'duplicate')
) result;
select app.complete_job(
  (select job_id from pg_temp.claimed_vin_jobs where probe = 'duplicate'),
  'vin-worker-b',
  (select lease_token from pg_temp.claimed_vin_jobs where probe = 'duplicate'),
  '{"decode_status":"succeeded"}'::jsonb,
  null
);

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001', 'aal2', 3600
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.review_vin_duplicate_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'duplicate'),
      'vin-review-stale-auth', 'override_open_duplicate',
      'Synthetic controlled duplicate exception',
      'request-vin-review-stale', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'recent strong authentication is required for duplicate override',
  'M2-INV-AC-010 open duplicate override fails when AAL2 is older than 15 minutes'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_review_results
    select result.*, 'initial'
    from app.review_vin_duplicate_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'duplicate'),
      'vin-review-override', 'override_open_duplicate',
      'Synthetic controlled duplicate exception',
      'request-vin-review', 'a8300000-0000-4000-8000-000000000001'
    ) result
  $$,
  'recently stepped-up authorized user records a reasoned duplicate override'
);
reset role;
select extensions.ok(
  exists (
    select 1
    from pg_temp.vin_review_results result
    join public.vin_duplicate_reviews review
      on review.id = result.vin_duplicate_review_id
    join public.audit_events audit on audit.id = result.audit_event_id
    join public.outbox_events event on event.id = result.outbox_event_id
    where result.probe = 'initial'
      and result.decision = 'override_open_duplicate'
      and result.approved_for_intake
      and review.strong_auth_used
      and review.reason = 'Synthetic controlled duplicate exception'
      and audit.action = 'inventory.vin_duplicate_reviewed'
      and audit.after_data ->> 'approved_for_intake' = 'true'
      and event.event_name = 'inventory.vin_duplicate_reviewed'
  ),
  'authorized open-duplicate override retains reason, auth, audit, outbox, and intake approval'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_review_results
    select result.*, 'replay'
    from app.review_vin_duplicate_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'duplicate'),
      'vin-review-override', 'override_open_duplicate',
      'Synthetic controlled duplicate exception',
      'request-vin-review-replay', pg_catalog.gen_random_uuid()
    ) result
  $$,
  'exact duplicate review replay succeeds'
);
select extensions.ok(
  (
    select replay.vin_duplicate_review_id = initial.vin_duplicate_review_id
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
      and replay.replayed
    from pg_temp.vin_review_results initial
    cross join pg_temp.vin_review_results replay
    where initial.probe = 'initial' and replay.probe = 'replay'
  ),
  'M2-INV-AC-011 duplicate review replay returns original evidence identifiers'
);
reset role;
select extensions.ok(
  (select next_sequence_value from public.stock_number_counters
   where workspace_id = '10000000-0000-4000-8000-000000000001'
     and definition_id = '71000000-0000-4000-8000-000000000001')
  = (select next_sequence_value from pg_temp.stock_counter_before),
  'T-INV-001 decode and duplicate review never consume a stock number'
);

-- A provider terminal failure is visible in the inventory status projection
-- and can be replayed with a new durable job without allocating inventory.
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_request_results
    select result.*, 'failure'
    from app.request_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      'vin-request-failure', '2HGES16575H123456', 2005,
      'request-vin-failure', 'a8400000-0000-4000-8000-000000000001'
    ) result
  $$,
  'provider-failure probe queues independently'
);
reset role;
insert into pg_temp.claimed_vin_jobs
select claimed.*, 'failure'
from app.claim_jobs('vin-worker-c', 10, 300, array['inventory.vin_decode']) claimed;
select * from app.fail_job(
  (select job_id from pg_temp.claimed_vin_jobs where probe = 'failure'),
  'vin-worker-c',
  (select lease_token from pg_temp.claimed_vin_jobs where probe = 'failure'),
  'permanent', 'vin.provider_rejected',
  'The VIN provider rejected the validated request.', null, null
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  (
    select status = 'dead_letter'
      and job_status = 'dead_letter'
      and retryable
      and review_required
      and last_error_classification = 'permanent'
      and last_error_code = 'vin.provider_rejected'
      and raw_result_reference is null
    from app.get_vin_decode_request(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'failure')
    )
  ),
  'M2-INV-AC-004 provider failure is visible with safe retry and review state'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_retry_results
    select result.*, 'initial'
    from app.retry_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'failure'),
      'vin-retry-failure-001', 'Retry after synthetic provider rejection',
      'request-vin-retry', 'a8500000-0000-4000-8000-000000000001'
    ) result
  $$,
  'M2-INV-AC-004 dead-letter VIN request is explicitly retryable'
);
reset role;
select extensions.ok(
  exists (
    select 1
    from pg_temp.vin_retry_results retry
    join public.jobs job on job.id = retry.job_id
    where retry.probe = 'initial'
      and retry.job_status = 'queued'
      and not retry.replayed
      and job.replay_of_job_id = (
        select job_id from pg_temp.claimed_vin_jobs where probe = 'failure'
      )
      and job.payload = (
        select payload from pg_temp.claimed_vin_jobs where probe = 'failure'
      )
  ),
  'retry preserves the safe decode contract and links the dead-letter source'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.vin_retry_results
    select result.*, 'replay'
    from app.retry_vin_decode_job(
      '10000000-0000-4000-8000-000000000001',
      (select vin_decode_request_id from pg_temp.vin_request_results where probe = 'failure'),
      'vin-retry-failure-001', 'Retry after synthetic provider rejection',
      'request-vin-retry-replay', pg_catalog.gen_random_uuid()
    ) result
  $$,
  'exact manual retry replay succeeds after the new job is queued'
);
select extensions.ok(
  (
    select replay.job_id = initial.job_id
      and replay.outbox_event_id = initial.outbox_event_id
      and replay.audit_event_id = initial.audit_event_id
      and replay.aggregate_version = initial.aggregate_version
      and replay.replayed
    from pg_temp.vin_retry_results initial
    cross join pg_temp.vin_retry_results replay
    where initial.probe = 'initial' and replay.probe = 'replay'
  ),
  'M2-INV-AC-011 retry replay returns original durable job evidence'
);
select extensions.is(
  (select pg_catalog.count(*) from public.inventory_units),
  1::bigint,
  'failure and retry paths still create no inventory or stock allocation'
);

reset role;
select extensions.throws_ok(
  $$delete from public.vin_duplicate_reviews$$,
  '55000',
  'VIN decode result and review history is append-only',
  'duplicate decision history cannot be deleted even by an application owner'
);

select * from extensions.finish();
rollback;
