-- VYN-JOB-001, VYN-OPS-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- T-JOB-001, T-JOB-002, T-JOB-003
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(71);

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
          'timestamp', pg_catalog.extract(
            epoch from pg_catalog.statement_timestamp()
          )::bigint
        )
      else pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'method', 'password',
          'timestamp', pg_catalog.extract(
            epoch from pg_catalog.statement_timestamp()
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

create function pg_temp.enqueue_fixture(
  fixture_workspace_id uuid,
  fixture_idempotency_key text,
  fixture_job_type text,
  fixture_actor_user_id uuid,
  fixture_max_attempts integer default 8,
  fixture_backoff_base_seconds integer default 1,
  fixture_backoff_max_seconds integer default 4
)
returns uuid
language plpgsql
as $$
declare
  fixture_job_id uuid;
begin
  select queued.job_id
    into fixture_job_id
  from app.enqueue_outbox_job(
    p_workspace_id => fixture_workspace_id,
    p_event_name => 'fixture.work_requested',
    p_aggregate_type => 'workspace',
    p_aggregate_id => fixture_workspace_id,
    p_aggregate_version => 1,
    p_job_type => fixture_job_type,
    p_entity_type => 'workspace',
    p_entity_id => fixture_workspace_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'entity_id', fixture_workspace_id,
      'fixture', true
    ),
    p_idempotency_key => fixture_idempotency_key,
    p_correlation_id => pg_catalog.gen_random_uuid(),
    p_actor_user_id => fixture_actor_user_id,
    p_max_attempts => fixture_max_attempts,
    p_backoff_base_seconds => fixture_backoff_base_seconds,
    p_backoff_max_seconds => fixture_backoff_max_seconds
  ) queued;

  return fixture_job_id;
end;
$$;

select extensions.has_table('public', 'outbox_events', 'outbox_events exists');
select extensions.has_table('public', 'jobs', 'jobs exists');
select extensions.has_table('public', 'job_attempts', 'job_attempts exists');
select extensions.has_table(
  'public',
  'job_admin_reviews',
  'job_admin_reviews exists'
);
select extensions.has_function(
  'app',
  'enqueue_outbox_job',
  array[
    'uuid', 'text', 'text', 'uuid', 'bigint', 'text', 'text', 'uuid',
    'integer', 'jsonb', 'text', 'uuid', 'uuid', 'uuid', 'integer',
    'integer', 'timestamp with time zone', 'integer', 'integer', 'uuid', 'text'
  ],
  'outbox transaction API exists'
);
select extensions.has_function(
  'app',
  'claim_jobs',
  array['text', 'integer', 'integer', 'text[]'],
  'worker claim API exists'
);
select extensions.has_function(
  'app',
  'reclaim_expired_job_leases',
  array['integer'],
  'lease reclaim API exists'
);

select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.enqueue_outbox_job(uuid,text,text,uuid,bigint,text,text,uuid,integer,jsonb,text,uuid,uuid,uuid,integer,integer,timestamptz,integer,integer,uuid,text)',
    'execute'
  ),
  'T-JOB-001 browser role cannot invoke arbitrary enqueue'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.claim_jobs(text,integer,integer,text[])',
    'execute'
  ),
  'T-JOB-002 service role can claim jobs'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.claim_jobs(text,integer,integer,text[])',
    'execute'
  ),
  'T-JOB-002 browser role cannot claim jobs'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'service_role',
    'public.outbox_events',
    'INSERT'
  ),
  'T-JOB-001 service workers cannot bypass the atomic enqueue primitive'
);
select extensions.ok(
  not pg_catalog.has_table_privilege('service_role', 'public.jobs', 'UPDATE'),
  'T-JOB-002 service workers cannot bypass fenced lifecycle functions'
);

select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.claim_jobs(text,integer,integer,text[])'::regprocedure
  ) ~* 'for update of candidate skip locked',
  'T-JOB-002 claim concurrency uses FOR UPDATE SKIP LOCKED'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.reclaim_expired_job_leases(integer)'::regprocedure
  ) ~* 'for update of candidate skip locked',
  'T-JOB-002 lease reclaim concurrency uses FOR UPDATE SKIP LOCKED'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.enqueue_outbox_job(uuid,text,text,uuid,bigint,text,text,uuid,integer,jsonb,text,uuid,uuid,uuid,integer,integer,timestamptz,integer,integer,uuid,text)'::regprocedure
  ) ~* 'pg_advisory_xact_lock',
  'T-JOB-001 idempotent enqueue serializes a logical idempotency scope'
);

savepoint atomicity_probe;
update public.workspaces
set name = 'Atomicity Probe'
where id = '10000000-0000-4000-8000-000000000001';
do $$
begin
  perform pg_temp.enqueue_fixture(
    '10000000-0000-4000-8000-000000000001',
    'atomicity-rollback',
    'fixture.atomicity',
    '31000000-0000-4000-8000-000000000001'
  );
end;
$$;
rollback to savepoint atomicity_probe;

select extensions.is(
  (
    select name
    from public.workspaces
    where id = '10000000-0000-4000-8000-000000000001'
  ),
  'Northstar Motors Test',
  'T-JOB-001 authoritative row rolls back with its transaction'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.jobs
    where idempotency_key = 'atomicity-rollback'
  ),
  0::bigint,
  'T-JOB-001 outbox and job roll back with the authoritative transaction'
);

do $$
begin
  perform pg_temp.enqueue_fixture(
    '10000000-0000-4000-8000-000000000001',
    'idempotent-a',
    'fixture.idempotent',
    '31000000-0000-4000-8000-000000000001'
  );
end;
$$;

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.jobs
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and job_type = 'fixture.idempotent'
      and idempotency_key = 'idempotent-a'
  ),
  1::bigint,
  'T-JOB-001 one logical request creates one job'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.outbox_events event
    join public.jobs job
      on job.workspace_id = event.workspace_id
     and job.outbox_event_id = event.id
    where job.idempotency_key = 'idempotent-a'
  ),
  1::bigint,
  'T-JOB-001 authoritative enqueue creates one linked outbox event'
);
select extensions.is(
  (
    select replay.created
    from app.enqueue_outbox_job(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_event_name => 'fixture.work_requested',
      p_aggregate_type => 'workspace',
      p_aggregate_id => '10000000-0000-4000-8000-000000000001',
      p_aggregate_version => 1,
      p_job_type => 'fixture.idempotent',
      p_entity_type => 'workspace',
      p_entity_id => '10000000-0000-4000-8000-000000000001',
      p_payload_schema_version => 1,
      p_payload => '{"entity_id":"10000000-0000-4000-8000-000000000001","fixture":true}'::jsonb,
      p_idempotency_key => ' idempotent-a ',
      p_correlation_id => pg_catalog.gen_random_uuid(),
      p_actor_user_id => '31000000-0000-4000-8000-000000000001',
      p_max_attempts => 8,
      p_backoff_base_seconds => 1,
      p_backoff_max_seconds => 4
    ) replay
  ),
  false,
  'T-JOB-001 exact replay normalizes the idempotency key and returns the existing job'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.jobs
    where job_type = 'fixture.idempotent'
      and idempotency_key = 'idempotent-a'
  ),
  1::bigint,
  'T-JOB-001 exact replay cannot duplicate the durable job'
);
select extensions.throws_ok(
  $$
    select *
    from app.enqueue_outbox_job(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_event_name => 'fixture.work_requested',
      p_aggregate_type => 'workspace',
      p_aggregate_id => '10000000-0000-4000-8000-000000000001',
      p_aggregate_version => 1,
      p_job_type => 'fixture.idempotent',
      p_entity_type => 'workspace',
      p_entity_id => '10000000-0000-4000-8000-000000000001',
      p_payload_schema_version => 1,
      p_payload => '{"entity_id":"10000000-0000-4000-8000-000000000099"}'::jsonb,
      p_idempotency_key => 'idempotent-a',
      p_correlation_id => pg_catalog.gen_random_uuid()
    )
  $$,
  '23505',
  'idempotency key was already used for a different job request',
  'T-JOB-001 same idempotency key rejects a different request fingerprint'
);
select extensions.throws_ok(
  $$
    select *
    from app.enqueue_outbox_job(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_event_name => 'fixture.work_requested',
      p_aggregate_type => 'workspace',
      p_aggregate_id => '10000000-0000-4000-8000-000000000001',
      p_aggregate_version => 1,
      p_job_type => 'fixture.secret_payload',
      p_entity_type => 'workspace',
      p_entity_id => '10000000-0000-4000-8000-000000000001',
      p_payload_schema_version => 1,
      p_payload => '{"adapter":{"access_token":"fixture"}}'::jsonb,
      p_idempotency_key => 'secret-payload',
      p_correlation_id => pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'job payload must be an object without credential-bearing keys',
  'T-JOB-001 credential-bearing payload keys fail closed'
);

do $$
begin
  perform pg_temp.enqueue_fixture(
    '20000000-0000-4000-8000-000000000002',
    'idempotent-a',
    'fixture.idempotent',
    '32000000-0000-4000-8000-000000000001'
  );
end;
$$;
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.jobs
    where job_type = 'fixture.idempotent'
      and idempotency_key = 'idempotent-a'
  ),
  2::bigint,
  'T-JOB-001 idempotency scope is isolated by workspace'
);

do $$
begin
  perform pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
end;
$$;
set local role authenticated;
select extensions.throws_ok(
  $$
    select *
    from app.enqueue_outbox_job(
      '10000000-0000-4000-8000-000000000001',
      'fixture.work_requested',
      'workspace',
      '10000000-0000-4000-8000-000000000001',
      1,
      'fixture.browser_forge',
      'workspace',
      '10000000-0000-4000-8000-000000000001',
      1,
      '{}'::jsonb,
      'browser-forge',
      '91000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'permission denied for function enqueue_outbox_job',
  'T-JOB-001 browser cannot forge an enqueue actor or payload'
);
select extensions.throws_ok(
  $$
    insert into public.jobs (
      workspace_id,
      outbox_event_id,
      job_type,
      entity_type,
      entity_id,
      payload_schema_version,
      payload,
      idempotency_key,
      request_fingerprint,
      correlation_id
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '90000000-0000-4000-8000-000000000099',
      'fixture.browser_forge',
      'workspace',
      '10000000-0000-4000-8000-000000000001',
      1,
      '{}'::jsonb,
      'browser-forge',
      repeat('a', 64),
      '91000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'permission denied for table jobs',
  'T-JOB-001 browser has no direct job insert privilege'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.jobs
    where workspace_id = '20000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'T-JOB-001 jobs.read cannot cross the workspace boundary'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.jobs
    where workspace_id = '10000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'jobs.read exposes same-workspace job metadata'
);
select extensions.throws_ok(
  $$select payload from public.jobs limit 1$$,
  '42501',
  'permission denied for table jobs',
  'browser job views do not expose job payloads'
);
reset role;

do $$
begin
  perform pg_temp.authenticate_as(
    '31000000-0000-4000-8000-000000000002',
    'aal1'
  );
end;
$$;
set local role authenticated;
select extensions.is(
  (select pg_catalog.count(*) from public.jobs),
  0::bigint,
  'T-JOB-001 membership without jobs.read sees no jobs'
);
reset role;

do $$
begin
  perform pg_temp.enqueue_fixture(
    '10000000-0000-4000-8000-000000000001',
    'retry-job',
    'fixture.retry',
    '31000000-0000-4000-8000-000000000001',
    2,
    2,
    8
  );
end;
$$;
select extensions.is(
  (
    select pg_catalog.count(*)
    from app.claim_jobs('worker-retry', 1, 60, array['fixture.retry'])
  ),
  1::bigint,
  'T-JOB-002 worker claims one eligible job'
);
select extensions.is(
  (
    select status
    from public.jobs
    where idempotency_key = 'retry-job'
  ),
  'running',
  'T-JOB-002 claim moves queued job to running'
);
select extensions.throws_ok(
  $$
    select app.complete_job(
      (select id from public.jobs where idempotency_key = 'retry-job'),
      null,
      (select lease_token from public.jobs where idempotency_key = 'retry-job')
    )
  $$,
  '55000',
  'only the active lease owner can complete a job',
  'T-JOB-002 a null worker identity cannot bypass lease ownership'
);
select extensions.throws_ok(
  $$
    select app.complete_job(
      (select id from public.jobs where idempotency_key = 'retry-job'),
      'wrong-worker',
      (select lease_token from public.jobs where idempotency_key = 'retry-job')
    )
  $$,
  '55000',
  'only the active lease owner can complete a job',
  'T-JOB-002 non-owner worker cannot complete the lease'
);
select extensions.is(
  (
    select failure.job_status
    from app.fail_job(
      (select id from public.jobs where idempotency_key = 'retry-job'),
      'worker-retry',
      (select lease_token from public.jobs where idempotency_key = 'retry-job'),
      'transient',
      'fixture_transient',
      'Synthetic transient failure.',
      null,
      null
    ) failure
  ),
  'retry_wait',
  'T-JOB-003 transient failure schedules a retry'
);
select extensions.ok(
  (
    select available_at > pg_catalog.statement_timestamp()
    from public.jobs
    where idempotency_key = 'retry-job'
  ),
  'T-JOB-003 retry uses a future jittered backoff time'
);
select extensions.is(
  (
    select outcome
    from public.job_attempts attempt
    join public.jobs job on job.id = attempt.job_id
    where job.idempotency_key = 'retry-job'
      and attempt.attempt_number = 1
  ),
  'retry_scheduled',
  'T-JOB-003 retry attempt telemetry is append-only'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from app.claim_jobs('worker-retry', 1, 60, array['fixture.retry'])
  ),
  0::bigint,
  'T-JOB-003 retry-wait job is unavailable before its backoff expires'
);

update public.jobs
set available_at = pg_catalog.statement_timestamp() - interval '1 second'
where idempotency_key = 'retry-job';
select extensions.is(
  (
    select attempt_number
    from app.claim_jobs('worker-retry', 1, 60, array['fixture.retry'])
  ),
  2,
  'T-JOB-003 retry consumes the next bounded attempt'
);
select extensions.is(
  (
    select failure.job_status
    from app.fail_job(
      (select id from public.jobs where idempotency_key = 'retry-job'),
      'worker-retry',
      (select lease_token from public.jobs where idempotency_key = 'retry-job'),
      'transient',
      'fixture_transient_again',
      'Synthetic repeated failure.'
    ) failure
  ),
  'dead_letter',
  'T-JOB-003 exhausted attempt budget dead-letters the job'
);
select extensions.ok(
  (
    select review_required
    from public.jobs
    where idempotency_key = 'retry-job'
  ),
  'T-JOB-003 dead letter is visible for admin review'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.job_attempts attempt
    join public.jobs job on job.id = attempt.job_id
    where job.idempotency_key = 'retry-job'
  ),
  2::bigint,
  'T-JOB-003 every started retry has one terminal attempt record'
);

select extensions.lives_ok(
  $$
    select app.acknowledge_dead_letter_job(
      (select id from public.jobs where idempotency_key = 'retry-job'),
      '31000000-0000-4000-8000-000000000001',
      'Reviewed synthetic exhaustion.',
      pg_catalog.gen_random_uuid()
    )
  $$,
  'T-JOB-003 authorized admin can acknowledge a dead letter'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.job_admin_reviews review
    join public.jobs job on job.id = review.job_id
    where job.idempotency_key = 'retry-job'
      and review.decision = 'acknowledged'
  ),
  1::bigint,
  'T-JOB-003 dead-letter admin review is durable and observable'
);

do $$
begin
  perform pg_temp.enqueue_fixture(
    '10000000-0000-4000-8000-000000000001',
    'permanent-job',
    'fixture.permanent',
    '31000000-0000-4000-8000-000000000001'
  );
  perform *
  from app.claim_jobs('worker-permanent', 1, 60, array['fixture.permanent']);
end;
$$;
select extensions.is(
  (
    select failure.job_status
    from app.fail_job(
      (select id from public.jobs where idempotency_key = 'permanent-job'),
      'worker-permanent',
      (select lease_token from public.jobs where idempotency_key = 'permanent-job'),
      'validation',
      'fixture_invalid',
      'Synthetic permanent validation failure.'
    ) failure
  ),
  'dead_letter',
  'T-JOB-003 validation errors do not retry without correction'
);
select extensions.throws_ok(
  $$
    select app.replay_dead_letter_job(
      (select id from public.jobs where idempotency_key = 'permanent-job'),
      'permanent-replay-denied',
      '31000000-0000-4000-8000-000000000002',
      'Limited user must not replay.',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active jobs.manage permission is required',
  'T-JOB-003 missing jobs.manage cannot review or replay dead letters'
);
select extensions.lives_ok(
  $$
    select app.replay_dead_letter_job(
      (select id from public.jobs where idempotency_key = 'permanent-job'),
      'permanent-replay',
      '31000000-0000-4000-8000-000000000001',
      'Corrected synthetic input and requested replay.',
      pg_catalog.gen_random_uuid()
    )
  $$,
  'T-JOB-003 jobs.manage creates a linked bounded replay job'
);
select extensions.is(
  (
    select replay_of_job_id
    from public.jobs
    where idempotency_key = 'permanent-replay'
  ),
  (
    select id
    from public.jobs
    where idempotency_key = 'permanent-job'
  ),
  'T-JOB-003 replay links to the reviewed dead-letter job'
);
select extensions.is(
  (
    select event.causation_id
    from public.outbox_events event
    join public.jobs replay on replay.outbox_event_id = event.id
    where replay.idempotency_key = 'permanent-replay'
  ),
  (
    select outbox_event_id
    from public.jobs
    where idempotency_key = 'permanent-job'
  ),
  'T-JOB-003 replay preserves causation telemetry'
);
select extensions.lives_ok(
  $$
    select app.cancel_job(
      (select id from public.jobs where idempotency_key = 'permanent-replay'),
      '31000000-0000-4000-8000-000000000001',
      'Synthetic replay no longer needed.',
      pg_catalog.gen_random_uuid()
    )
  $$,
  'T-JOB-003 jobs.manage can cancel a safely queued job'
);
select extensions.is(
  (
    select status
    from public.jobs
    where idempotency_key = 'permanent-replay'
  ),
  'cancelled',
  'T-JOB-003 cancellation is durable and observable'
);

do $$
begin
  perform pg_temp.enqueue_fixture(
    '10000000-0000-4000-8000-000000000001',
    'lease-job',
    'fixture.lease',
    '31000000-0000-4000-8000-000000000001',
    2,
    1,
    2
  );
  perform *
  from app.claim_jobs('worker-lease-a', 1, 60, array['fixture.lease']);
end;
$$;
create temporary table lease_probe as
select id as job_id, lease_token as first_lease_token
from public.jobs
where idempotency_key = 'lease-job';

update public.jobs
set current_attempt_started_at = pg_catalog.statement_timestamp() - interval '2 minutes',
    heartbeat_at = pg_catalog.statement_timestamp() - interval '90 seconds',
    lease_expires_at = pg_catalog.statement_timestamp() - interval '1 second'
where idempotency_key = 'lease-job';
select extensions.is(
  (
    select resulting_status
    from app.reclaim_expired_job_leases(10)
    where job_id = (select job_id from lease_probe)
  ),
  'retry_wait',
  'T-JOB-002 expired lease is safely reclaimed into retry wait'
);
select extensions.is(
  (
    select outcome
    from public.job_attempts
    where job_id = (select job_id from lease_probe)
      and attempt_number = 1
  ),
  'lease_expired',
  'T-JOB-002 reclaimed lease writes terminal attempt telemetry'
);
select extensions.throws_ok(
  $$
    select app.complete_job(
      (select job_id from lease_probe),
      'worker-lease-a',
      (select first_lease_token from lease_probe)
    )
  $$,
  '55000',
  'only the active lease owner can complete a job',
  'T-JOB-002 stale worker cannot complete after lease reclaim'
);

update public.jobs
set available_at = pg_catalog.statement_timestamp() - interval '1 second'
where idempotency_key = 'lease-job';
select extensions.is(
  (
    select attempt_number
    from app.claim_jobs('worker-lease-b', 1, 60, array['fixture.lease'])
  ),
  2,
  'T-JOB-002 reclaimed job can be leased by another worker'
);
select extensions.ok(
  (
    select job.lease_token <> probe.first_lease_token
    from public.jobs job
    cross join lease_probe probe
    where job.id = probe.job_id
  ),
  'T-JOB-002 reclaim issues a new fencing lease token'
);
select extensions.ok(
  app.heartbeat_job(
    (select job_id from lease_probe),
    'worker-lease-b',
    (select lease_token from public.jobs where id = (select job_id from lease_probe)),
    120
  ) > pg_catalog.statement_timestamp(),
  'T-JOB-002 active worker can heartbeat and extend its lease'
);
select extensions.lives_ok(
  $$
    select app.complete_job(
      (select job_id from lease_probe),
      'worker-lease-b',
      (select lease_token from public.jobs where id = (select job_id from lease_probe)),
      '{"fixture_status":"ok"}'::jsonb,
      'provider-request-fixture'
    )
  $$,
  'T-JOB-002 new lease owner can complete the reclaimed job'
);
select extensions.is(
  (
    select status
    from public.jobs
    where id = (select job_id from lease_probe)
  ),
  'succeeded',
  'T-JOB-002 reclaimed job reaches one terminal success state'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.jobs
    where idempotency_key = 'lease-job'
  ),
  1::bigint,
  'T-JOB-002 lease reclaim does not duplicate the logical job'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.job_attempts
    where job_id = (select job_id from lease_probe)
  ),
  2::bigint,
  'T-JOB-002 expired and successful attempts remain independently observable'
);

select extensions.throws_ok(
  $$
    update public.outbox_events
    set event_name = 'fixture.tampered'
    where id = (
      select outbox_event_id from public.jobs where idempotency_key = 'lease-job'
    )
  $$,
  '55000',
  'outbox_events is append-only',
  'T-JOB-001 outbox events are immutable'
);
select extensions.throws_ok(
  $$
    delete from public.outbox_events
    where id = (
      select outbox_event_id from public.jobs where idempotency_key = 'lease-job'
    )
  $$,
  '55000',
  'outbox_events is append-only',
  'T-JOB-001 outbox events cannot be deleted'
);
select extensions.throws_ok(
  $$
    update public.job_attempts
    set outcome = 'dead_lettered'
    where job_id = (select job_id from lease_probe)
      and attempt_number = 1
  $$,
  '55000',
  'job_attempts is append-only',
  'T-JOB-003 attempt history is immutable'
);
select extensions.throws_ok(
  $$
    update public.job_admin_reviews
    set reason = 'tampered'
    where job_id = (
      select id from public.jobs where idempotency_key = 'retry-job'
    )
  $$,
  '55000',
  'job_admin_reviews is append-only',
  'T-JOB-003 admin review history is immutable'
);
select extensions.throws_ok(
  $$
    update public.jobs
    set workspace_id = '20000000-0000-4000-8000-000000000002'
    where id = (select job_id from lease_probe)
  $$,
  '23514',
  'jobs.workspace_id is immutable',
  'T-JOB-001 job workspace ownership is immutable'
);
select extensions.throws_ok(
  $$
    delete from public.jobs
    where id = (select job_id from lease_probe)
  $$,
  '55000',
  'hard delete is prohibited for jobs',
  'T-JOB-001 durable jobs cannot be hard-deleted'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'outbox_events',
        'jobs',
        'job_attempts',
        'job_admin_reviews'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  4::bigint,
  'all outbox/job tables enable and force RLS'
);
select extensions.ok(
  (
    select pg_catalog.count(*) >= 1
    from public.audit_events
    where action = 'job.queued'
      and entity_id = (select job_id from lease_probe)
      and correlation_id is not null
  ),
  'T-JOB-001 enqueue writes correlated append-only audit evidence'
);
select extensions.ok(
  (
    select pg_catalog.count(*) >= 1
    from public.audit_events
    where action = 'job.succeeded'
      and entity_id = (select job_id from lease_probe)
      and metadata ->> 'worker_id' = 'worker-lease-b'
  ),
  'T-JOB-003 terminal state writes worker and attempt audit telemetry'
);
select extensions.ok(
  not exists (
    select 1
    from public.audit_events
    where entity_id = (select job_id from lease_probe)
      and pg_catalog.to_jsonb(audit_events)::text ~* '(access_token|password|private_key)'
  ),
  'job audit evidence omits credential-bearing payload data'
);

select * from extensions.finish();
rollback;
