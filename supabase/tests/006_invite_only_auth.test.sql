-- T-AUTH-001, T-AUTH-002, T-AUTH-004, T-TEN-001, T-RBAC-001, T-AUD-001, T-JOB-001
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(55);

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  fixture_email text,
  assurance text default 'aal1',
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
    'email', fixture_email,
    'role', 'authenticated',
    'aal', assurance,
    'amr', case
      when assurance = 'aal2' then pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'method', 'totp',
          'timestamp', pg_catalog.floor(
            pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
          )::bigint - factor_age_seconds
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
  perform pg_catalog.set_config('request.jwt.claim.email', fixture_email, true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table invite_test_context (
  expires_at timestamptz not null
) on commit drop;
insert into invite_test_context
values (pg_catalog.statement_timestamp() + interval '1 day');

create temporary table invite_create_result (
  invitation_id uuid,
  invitation_status text,
  outbox_event_id uuid,
  job_id uuid,
  job_status text,
  replayed boolean
) on commit drop;
create temporary table invite_replay_result (
  invitation_id uuid,
  invitation_status text,
  outbox_event_id uuid,
  job_id uuid,
  job_status text,
  replayed boolean
) on commit drop;
create temporary table invite_claim_result (
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
  causation_id uuid
) on commit drop;
create temporary table invite_accept_result (
  invitation_id uuid,
  membership_id uuid,
  invitation_status text,
  replayed boolean
) on commit drop;

grant select on pg_temp.invite_test_context
  to authenticated, service_role;
grant select, insert, delete on
  pg_temp.invite_create_result,
  pg_temp.invite_replay_result,
  pg_temp.invite_claim_result,
  pg_temp.invite_accept_result
to authenticated, service_role;

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
    '33000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'other.user@northstar.invalid',
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
    '33000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'expired.user@northstar.invalid',
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
    '33000000-0000-4000-8000-000000000004',
    'authenticated',
    'authenticated',
    'revoked.user@northstar.invalid',
    extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
    pg_catalog.statement_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"fixture":true}'::jsonb,
    pg_catalog.statement_timestamp(),
    pg_catalog.statement_timestamp(),
    '', '', '', ''
  );

insert into public.workspace_invitations (
  id,
  workspace_id,
  email,
  token_hash,
  status,
  requested_locale,
  invited_by,
  expires_at,
  created_at
)
values
  (
    '83000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    'expired.user@northstar.invalid',
    null,
    'pending',
    'en-CA',
    '31000000-0000-4000-8000-000000000001',
    pg_catalog.statement_timestamp() - interval '1 day',
    pg_catalog.statement_timestamp() - interval '2 days'
  ),
  (
    '83000000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000001',
    'revoked.user@northstar.invalid',
    null,
    'pending',
    'fr-CA',
    '31000000-0000-4000-8000-000000000001',
    pg_catalog.statement_timestamp() + interval '1 day',
    pg_catalog.statement_timestamp()
  ),
  (
    '83000000-0000-4000-8000-000000000005',
    '20000000-0000-4000-8000-000000000002',
    'workspace-b-only@harbour.invalid',
    null,
    'pending',
    'fr-CA',
    '32000000-0000-4000-8000-000000000001',
    pg_catalog.statement_timestamp() + interval '1 day',
    pg_catalog.statement_timestamp()
  );

insert into public.workspace_invitation_roles (
  workspace_id,
  invitation_id,
  role_id
)
values
  (
    '10000000-0000-4000-8000-000000000001',
    '83000000-0000-4000-8000-000000000003',
    '51000000-0000-4000-8000-000000000001'
  ),
  (
    '10000000-0000-4000-8000-000000000001',
    '83000000-0000-4000-8000-000000000004',
    '51000000-0000-4000-8000-000000000001'
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '83000000-0000-4000-8000-000000000005',
    '52000000-0000-4000-8000-000000000001'
  );

update public.workspace_invitations
set status = 'revoked',
    revoked_at = pg_catalog.statement_timestamp()
where id = '83000000-0000-4000-8000-000000000004';

select extensions.has_table(
  'public',
  'workspace_invitation_commands',
  'invite command history table exists'
);
select extensions.has_function(
  'app',
  'create_workspace_invitation_job',
  array['uuid', 'text', 'text', 'uuid[]', 'text', 'timestamp with time zone', 'text', 'uuid'],
  'authenticated invitation creation RPC exists'
);
select extensions.has_function(
  'app',
  'accept_workspace_invitation',
  array['uuid', 'text', 'uuid', 'text', 'uuid'],
  'matching identity acceptance RPC exists'
);
select extensions.has_function(
  'app',
  'read_invitation_delivery_job',
  array['uuid', 'text', 'uuid'],
  'lease-bound service delivery read RPC exists'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'workspace_invitation_commands'
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'T-TEN-001 invitation command history enables and forces RLS'
);
select extensions.ok(
  not (
    select attribute.attnotnull
    from pg_catalog.pg_attribute attribute
    join pg_catalog.pg_class relation on relation.oid = attribute.attrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'workspace_invitations'
      and attribute.attname = 'token_hash'
  ),
  'T-AUTH-001 new GoTrue-managed invitations do not require a local token hash'
);

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'admin@northstar.invalid',
  'aal1',
  0
);
set local role authenticated;

select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-aal1-001',
      'new.user@northstar.invalid',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-aal1',
      'a1000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'active users.manage permission is required',
  'T-AUTH-002 an MFA administrator cannot invite at AAL1'
);

reset role;
select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'admin@northstar.invalid',
  'aal2',
  901
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-stale-001',
      'new.user@northstar.invalid',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-stale',
      'a1000000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  'recent AAL2 authentication is required',
  'T-AUTH-004 invitation creation rejects stale step-up authentication'
);

reset role;
select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000002',
  'limited@northstar.invalid',
  'aal2',
  0
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-rbac-001',
      'new.user@northstar.invalid',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-rbac',
      'a1000000-0000-4000-8000-000000000003'
    )
  $$,
  '42501',
  'active users.manage permission is required',
  'T-RBAC-001 role labels do not substitute for users.manage'
);

reset role;
select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'admin@northstar.invalid',
  'aal2',
  0
);
set local role authenticated;

select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '20000000-0000-4000-8000-000000000002',
      'invite-ws-spoof-001',
      'new.user@northstar.invalid',
      array['52000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-spoof',
      'a1000000-0000-4000-8000-000000000004'
    )
  $$,
  '42501',
  'active users.manage permission is required',
  'T-TEN-001 request workspace spoofing cannot cross the membership boundary'
);
select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-cross-role-001',
      'new.user@northstar.invalid',
      array['52000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-cross-role',
      'a1000000-0000-4000-8000-000000000005'
    )
  $$,
  '23514',
  'all invitation roles must be active in the selected workspace',
  'T-TEN-001 cross-workspace invitation roles fail closed'
);
select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-duplicate-role-001',
      'new.user@northstar.invalid',
      array[
        '51000000-0000-4000-8000-000000000001',
        '51000000-0000-4000-8000-000000000001'
      ]::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-duplicate-role',
      'a1000000-0000-4000-8000-000000000006'
    )
  $$,
  '22023',
  'invitation roles must be unique',
  'T-RBAC-001 duplicate invitation roles are rejected'
);
select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-invalid-email-001',
      'not-an-email',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-invalid-email',
      'a1000000-0000-4000-8000-000000000007'
    )
  $$,
  '22023',
  'invalid invitation email',
  'T-AUTH-001 malformed invitation email is rejected before persistence'
);
select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-expiry-001',
      'new.user@northstar.invalid',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      pg_catalog.statement_timestamp() + interval '31 days',
      'req-invite-expiry',
      'a1000000-0000-4000-8000-000000000008'
    )
  $$,
  '22023',
  'invitation expiry must be in the next 30 days',
  'T-AUTH-001 invitation expiry is bounded'
);
select extensions.throws_ok(
  $$
    insert into public.workspace_invitations (
      workspace_id, email, status, requested_locale, invited_by, expires_at
    ) values (
      '10000000-0000-4000-8000-000000000001',
      'browser-write@northstar.invalid',
      'pending',
      'en-CA',
      '31000000-0000-4000-8000-000000000001',
      pg_catalog.statement_timestamp() + interval '1 day'
    )
  $$,
  '42501',
  'permission denied for table workspace_invitations',
  'T-AUTH-001 browser table writes cannot bypass the trusted command'
);
select extensions.throws_ok(
  $$
    select * from app.read_invitation_delivery_job(
      'a3000000-0000-4000-8000-000000000001',
      'browser-worker-spoof',
      'a3000000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  'permission denied for function read_invitation_delivery_job',
  'T-AUTH-001 authenticated API callers cannot execute the service delivery read'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_invitations
    where workspace_id = '20000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'T-TEN-001 workspace A administrator cannot read workspace B invitations'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.invite_create_result
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-create-001',
      ' New.User@Northstar.Invalid ',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-create',
      'a1000000-0000-4000-8000-000000000009'
    )
  $$,
  'T-AUTH-001 authorized recent-AAL2 invitation command succeeds'
);
select extensions.results_eq(
  $$
    select invitation_status, job_status, replayed
    from pg_temp.invite_create_result
  $$,
  $$values ('pending'::text, 'queued'::text, false)$$,
  'T-JOB-001 invitation and delivery job commit in one command'
);
select extensions.ok(
  (
    select invitation.email::text = 'new.user@northstar.invalid'
      and invitation.token_hash is null
      and invitation.requested_locale = 'en-CA'
      and invitation.invited_by = '31000000-0000-4000-8000-000000000001'
    from public.workspace_invitations invitation
    join pg_temp.invite_create_result result on result.invitation_id = invitation.id
  ),
  'T-AUTH-001 invitation persists normalized metadata and no provider token hash'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_invitation_roles link
    join pg_temp.invite_create_result result on result.invitation_id = link.invitation_id
    where link.workspace_id = '10000000-0000-4000-8000-000000000001'
      and link.role_id = '51000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'T-RBAC-001 explicit invitation role snapshot is preserved once'
);
select extensions.ok(
  (
    select job.job_type = 'auth.invitation.deliver'
      and job.entity_type = 'workspace_invitation'
      and job.payload_schema_version = 1
      and job.payload = pg_catalog.jsonb_build_object(
        'invitation_id', result.invitation_id
      )
      and pg_catalog.jsonb_object_length(job.payload) = 1
    from public.jobs job
    join pg_temp.invite_create_result result on result.job_id = job.id
  ),
  'T-JOB-001 delivery payload contains exactly invitation_id'
);
select extensions.ok(
  (
    select event.event_name = 'auth.invitation.delivery_requested'
      and event.aggregate_type = 'workspace_invitation'
      and event.aggregate_id = result.invitation_id
      and event.payload = pg_catalog.jsonb_build_object(
        'invitation_id', result.invitation_id
      )
    from public.outbox_events event
    join pg_temp.invite_create_result result on result.outbox_event_id = event.id
  ),
  'T-JOB-001 authoritative invitation and outbox record share workspace context'
);
select extensions.ok(
  (
    select job.payload ? 'invitation_id'
      and pg_catalog.strpos(job.payload::text, 'new.user@northstar.invalid') = 0
      and job.payload::text !~* '(password|secret|token|credential|cookie|privatekey)'
    from public.jobs job
    join pg_temp.invite_create_result result on result.job_id = job.id
  ),
  'T-AUTH-001 delivery job omits email, token, and credential-bearing keys'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_invitation_commands command
    join pg_temp.invite_create_result result
      on result.invitation_id = command.invitation_id
    where command.command_kind = 'create'
  ),
  1::bigint,
  'T-JOB-001 append-only command mapping records the atomic queue result'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events audit
    join pg_temp.invite_create_result result on result.invitation_id = audit.entity_id
    where audit.action = 'auth.invitation.created'
      and audit.actor_user_id = '31000000-0000-4000-8000-000000000001'
      and audit.auth_assurance = 'aal2'
      and not (coalesce(audit.after_data, '{}'::jsonb) ? 'email')
  ),
  1::bigint,
  'T-AUD-001 invitation creation emits a scoped non-PII audit event'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.invite_replay_result
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-create-001',
      'new.user@northstar.invalid',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-create-retry',
      'a1000000-0000-4000-8000-000000000010'
    )
  $$,
  'T-AUTH-001 exact invitation retry succeeds idempotently'
);
select extensions.ok(
  (
    select replay.replayed
      and replay.invitation_id = created.invitation_id
      and replay.job_id = created.job_id
      and replay.outbox_event_id = created.outbox_event_id
    from pg_temp.invite_replay_result replay
    cross join pg_temp.invite_create_result created
  ),
  'T-JOB-001 exact retry returns the original invitation and job identities'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.jobs job
    where job.job_type = 'auth.invitation.deliver'
      and job.entity_id = (select invitation_id from pg_temp.invite_create_result)
  ),
  1::bigint,
  'T-JOB-001 exact retry cannot duplicate the delivery job'
);
select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-create-001',
      'changed.user@northstar.invalid',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-create-conflict',
      'a1000000-0000-4000-8000-000000000011'
    )
  $$,
  '23505',
  'invitation idempotency key was used for a different request',
  'T-JOB-001 changed request cannot reuse an invitation idempotency key'
);
select extensions.throws_ok(
  $$
    select * from app.create_workspace_invitation_job(
      '10000000-0000-4000-8000-000000000001',
      'invite-create-002',
      'new.user@northstar.invalid',
      array['51000000-0000-4000-8000-000000000001']::uuid[],
      'en-CA',
      (select expires_at from pg_temp.invite_test_context),
      'req-invite-pending-conflict',
      'a1000000-0000-4000-8000-000000000012'
    )
  $$,
  '23505',
  'duplicate key value violates unique constraint "workspace_invitations_pending_email_uidx"',
  'T-AUTH-001 one email cannot hold duplicate pending invitations in a workspace'
);

reset role;
set local role service_role;
insert into pg_temp.invite_claim_result
select * from app.claim_jobs(
  'invite-worker-test',
  1,
  120,
  array['auth.invitation.deliver']::text[]
);
select extensions.is(
  (select job_type from pg_temp.invite_claim_result),
  'auth.invitation.deliver',
  'T-JOB-001 worker claims only the settled invitation job type'
);
select extensions.is(
  (
    select delivery.provider_identity_exists
    from app.read_invitation_delivery_job(
      (select job_id from pg_temp.invite_claim_result),
      'invite-worker-test',
      (select lease_token from pg_temp.invite_claim_result)
    ) delivery
  ),
  false,
  'T-JOB-001 authoritative delivery reload detects no provider identity before invite'
);
select extensions.throws_ok(
  $$
    select * from app.read_invitation_delivery_job(
      (select job_id from pg_temp.invite_claim_result),
      'other-worker',
      (select lease_token from pg_temp.invite_claim_result)
    )
  $$,
  '22023',
  'invitation delivery job is not eligible for this lease',
  'T-JOB-001 another worker cannot read invitation delivery PII'
);

reset role;
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
values (
  '00000000-0000-0000-0000-000000000000',
  '33000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'new.user@northstar.invalid',
  extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
  pg_catalog.statement_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"fixture":true}'::jsonb,
  pg_catalog.statement_timestamp(),
  pg_catalog.statement_timestamp(),
  '', '', '', ''
);

set local role service_role;
select extensions.is(
  (
    select delivery.provider_identity_exists
    from app.read_invitation_delivery_job(
      (select job_id from pg_temp.invite_claim_result),
      'invite-worker-test',
      (select lease_token from pg_temp.invite_claim_result)
    ) delivery
  ),
  true,
  'T-JOB-001 retry reload selects existing-identity passwordless delivery'
);
select extensions.ok(
  app.complete_job(
    (select job_id from pg_temp.invite_claim_result),
    'invite-worker-test',
    (select lease_token from pg_temp.invite_claim_result),
    pg_catalog.jsonb_build_object(
      'invitation_id', (select invitation_id from pg_temp.invite_create_result),
      'delivery_outcome', 'submitted'
    ),
    'fixture-provider-request-id'
  ),
  'T-JOB-001 provider submission completes through the generic leased job RPC'
);
select extensions.results_eq(
  $$
    select status, result_summary ->> 'delivery_outcome'
    from public.jobs
    where id = (select job_id from pg_temp.invite_create_result)
  $$,
  $$values ('succeeded'::text, 'submitted'::text)$$,
  'T-JOB-001 completed job persists only a safe delivery outcome'
);
select extensions.throws_ok(
  $$
    select * from app.read_invitation_delivery_job(
      (select job_id from pg_temp.invite_claim_result),
      'invite-worker-test',
      (select lease_token from pg_temp.invite_claim_result)
    )
  $$,
  '22023',
  'invitation delivery job is not eligible for this lease',
  'T-JOB-001 completed delivery can no longer disclose authoritative PII'
);

reset role;
select pg_temp.authenticate_as(
  '33000000-0000-4000-8000-000000000002',
  'other.user@northstar.invalid',
  'aal1',
  0
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.accept_workspace_invitation(
      '10000000-0000-4000-8000-000000000001',
      'accept-mismatch-001',
      (select invitation_id from pg_temp.invite_create_result),
      'req-accept-mismatch',
      'a2000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'authenticated email does not match the invitation',
  'T-AUTH-001 a different authenticated email cannot accept the invitation'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_memberships
    where user_id = '33000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'T-AUTH-001 rejected identity mismatch provisions no membership'
);

reset role;
select pg_temp.authenticate_as(
  '33000000-0000-4000-8000-000000000003',
  'expired.user@northstar.invalid',
  'aal1',
  0
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.accept_workspace_invitation(
      '10000000-0000-4000-8000-000000000001',
      'accept-expired-001',
      '83000000-0000-4000-8000-000000000003',
      'req-accept-expired',
      'a2000000-0000-4000-8000-000000000002'
    )
  $$,
  '23514',
  'expired invitations cannot be accepted',
  'T-AUTH-001 expired invitation acceptance fails closed'
);

reset role;
select pg_temp.authenticate_as(
  '33000000-0000-4000-8000-000000000004',
  'revoked.user@northstar.invalid',
  'aal1',
  0
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.accept_workspace_invitation(
      '10000000-0000-4000-8000-000000000001',
      'accept-revoked-001',
      '83000000-0000-4000-8000-000000000004',
      'req-accept-revoked',
      'a2000000-0000-4000-8000-000000000003'
    )
  $$,
  '23514',
  'only a pending invitation can be accepted',
  'T-AUTH-001 revoked invitation acceptance fails closed'
);

reset role;
select pg_temp.authenticate_as(
  '33000000-0000-4000-8000-000000000001',
  'new.user@northstar.invalid',
  'aal1',
  0
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.accept_workspace_invitation(
      '20000000-0000-4000-8000-000000000002',
      'accept-ws-spoof-001',
      (select invitation_id from pg_temp.invite_create_result),
      'req-accept-ws-spoof',
      'a2000000-0000-4000-8000-000000000004'
    )
  $$,
  '23514',
  'pending invitation was not found in the selected workspace',
  'T-TEN-001 acceptance workspace spoofing cannot move an invitation'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.invite_accept_result
    select * from app.accept_workspace_invitation(
      '10000000-0000-4000-8000-000000000001',
      'accept-create-001',
      (select invitation_id from pg_temp.invite_create_result),
      'req-accept-create',
      'a2000000-0000-4000-8000-000000000005'
    )
  $$,
  'T-AUTH-001 matching confirmed identity accepts without prior membership'
);
select extensions.results_eq(
  $$
    select invitation_status, replayed
    from pg_temp.invite_accept_result
  $$,
  $$values ('accepted'::text, false)$$,
  'T-AUTH-001 acceptance returns the stable accepted response'
);

reset role;
select extensions.ok(
  (
    select membership.status = 'active'
      and membership.user_id = '33000000-0000-4000-8000-000000000001'
      and membership.workspace_id = '10000000-0000-4000-8000-000000000001'
      and membership.activated_at is not null
      and profile.status = 'active'
      and profile.preferred_locale = 'en-CA'
    from public.workspace_memberships membership
    join public.user_profiles profile on profile.user_id = membership.user_id
    join pg_temp.invite_accept_result result on result.membership_id = membership.id
  ),
  'T-AUTH-001 trusted acceptance atomically provisions active profile and membership'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.membership_roles assignment
    join pg_temp.invite_accept_result result
      on result.membership_id = assignment.membership_id
    where assignment.workspace_id = '10000000-0000-4000-8000-000000000001'
      and assignment.role_id = '51000000-0000-4000-8000-000000000001'
      and assignment.status = 'active'
  ),
  1::bigint,
  'T-RBAC-001 acceptance copies the explicit active invitation role once'
);
select extensions.ok(
  (
    select invitation.status = 'accepted'
      and invitation.accepted_by = '33000000-0000-4000-8000-000000000001'
      and invitation.accepted_membership_id = result.membership_id
      and invitation.accepted_at is not null
    from public.workspace_invitations invitation
    join pg_temp.invite_accept_result result on result.invitation_id = invitation.id
  ),
  'T-AUTH-001 invitation acceptance links the matching active membership'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events audit
    join pg_temp.invite_accept_result result on result.invitation_id = audit.entity_id
    where audit.action = 'auth.invitation.accepted'
      and audit.actor_user_id = '33000000-0000-4000-8000-000000000001'
      and audit.after_data ->> 'membership_id' = result.membership_id::text
  ),
  1::bigint,
  'T-AUD-001 acceptance emits one workspace-scoped matching-identity audit event'
);
set local role authenticated;
select extensions.ok(
  not app.has_active_membership('10000000-0000-4000-8000-000000000001'),
  'T-AUTH-002 accepted administrator role remains inaccessible at AAL1'
);

delete from pg_temp.invite_accept_result;
insert into pg_temp.invite_accept_result
select * from app.accept_workspace_invitation(
  '10000000-0000-4000-8000-000000000001',
  'accept-create-001',
  (select invitation_id from pg_temp.invite_create_result),
  'req-accept-replay',
  'a2000000-0000-4000-8000-000000000006'
);
select extensions.ok(
  (select replayed from pg_temp.invite_accept_result),
  'T-AUTH-001 exact acceptance retry is idempotent'
);

reset role;
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_memberships
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and user_id = '33000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'T-AUTH-001 acceptance retry cannot duplicate membership'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'auth.invitation.accepted'
      and entity_id = (select invitation_id from pg_temp.invite_create_result)
  ),
  1::bigint,
  'T-AUD-001 acceptance retry cannot duplicate the command audit event'
);

reset role;
select pg_temp.authenticate_as(
  '33000000-0000-4000-8000-000000000001',
  'new.user@northstar.invalid',
  'aal2',
  0
);
set local role authenticated;
select extensions.ok(
  app.has_active_membership('10000000-0000-4000-8000-000000000001'),
  'T-AUTH-002 accepted administrator role becomes effective at AAL2'
);

reset role;
select extensions.throws_ok(
  $$
    update public.workspace_invitation_commands
    set idempotency_key = 'mutated-command-key'
    where invitation_id = (select invitation_id from pg_temp.invite_create_result)
  $$,
  '55000',
  'workspace_invitation_commands is append-only',
  'T-AUD-001 invitation command history is append-only'
);

select * from extensions.finish();
rollback;
