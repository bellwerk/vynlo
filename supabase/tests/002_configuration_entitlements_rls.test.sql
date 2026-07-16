-- VYN-AUD-001, VYN-WF-001, VYN-FIELD-001, VYN-E02
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(86);

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
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
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

select extensions.has_table('public', 'approval_records', 'approval history exists');
select extensions.has_table(
  'public',
  'workspace_configuration_versions',
  'workspace configuration history exists'
);
select extensions.has_table(
  'public',
  'workspace_configuration_activations',
  'workspace configuration activation history exists'
);
select extensions.has_table(
  'public',
  'workspace_feature_entitlements',
  'feature entitlement history exists'
);
select extensions.has_function(
  'app',
  'create_workspace_configuration_draft',
  array[
    'uuid', 'text', 'jsonb', 'text', 'jsonb', 'text', 'text', 'uuid',
    'integer', 'integer', 'integer', 'timestamp with time zone',
    'timestamp with time zone'
  ],
  'serialized draft command exists'
);
select extensions.has_function(
  'app',
  'record_workspace_configuration_approval',
  array[
    'uuid', 'uuid', 'text', 'text', 'text', 'text', 'text', 'text',
    'text', 'jsonb', 'text', 'timestamp with time zone',
    'timestamp with time zone', 'uuid'
  ],
  'exact-version approval command exists'
);
select extensions.has_function(
  'app',
  'transition_workspace_configuration_version',
  array['uuid', 'uuid', 'text', 'text', 'text', 'jsonb', 'text'],
  'optimistic lifecycle command exists'
);
select extensions.has_function(
  'app',
  'activate_workspace_configuration_version',
  array[
    'uuid', 'uuid', 'text', 'integer', 'text', 'text',
    'timestamp with time zone'
  ],
  'serialized activation command exists'
);
select extensions.has_function(
  'app',
  'install_workspace_feature_entitlement_version',
  array[
    'uuid', 'text', 'boolean', 'jsonb', 'text', 'jsonb',
    'timestamp with time zone', 'text', 'text', 'timestamp with time zone'
  ],
  'trusted entitlement install command exists'
);
select extensions.has_function(
  'app',
  'activate_workspace_feature_entitlement_version',
  array['uuid', 'uuid', 'text', 'text', 'timestamp with time zone'],
  'trusted entitlement activation command exists'
);
select extensions.has_function(
  'app',
  'retire_workspace_feature_entitlement_version',
  array['uuid', 'uuid', 'text', 'text'],
  'trusted entitlement retirement command exists'
);
select extensions.has_function(
  'app',
  'is_feature_entitled',
  array['uuid', 'text', 'timestamp with time zone'],
  'shared entitlement decision exists'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'approval_records',
        'workspace_configuration_versions',
        'workspace_configuration_activations',
        'workspace_feature_entitlements'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  4::bigint,
  'all exposed configuration tables enable and force RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated',
    'public.workspace_configuration_versions',
    'INSERT'
  )
    and not pg_catalog.has_table_privilege(
      'authenticated',
      'public.workspace_configuration_versions',
      'UPDATE'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated',
      'public.approval_records',
      'INSERT'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated',
      'public.workspace_feature_entitlements',
      'INSERT'
    ),
  'browser roles cannot spoof configuration actors, versions, or lifecycle columns'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;

select extensions.lives_ok(
  $$
    select app.create_workspace_configuration_draft(
      '10000000-0000-4000-8000-000000000001',
      'workspace.core',
      '{"locale":"en-CA"}'::jsonb,
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      '{"source":"synthetic_pgtap"}'::jsonb,
      'config-core-v1',
      'VYN-E02 create first synthetic configuration',
      null,
      1,
      1,
      2,
      timestamptz '2026-07-16 00:00:00+00',
      null
    )
  $$,
  'configuration.manage with recent AAL2 can create an immutable draft'
);
select extensions.results_eq(
  $$
    select version, status, created_by
    from public.workspace_configuration_versions
    where idempotency_key = 'config-core-v1'
  $$,
  $$
    values (
      1::bigint,
      'draft'::text,
      '31000000-0000-4000-8000-000000000001'::uuid
    )
  $$,
  'draft version and creator are derived atomically'
);
select extensions.results_eq(
  $$
    select actor_user_id, actor_type, auth_assurance
    from public.audit_events
    where action = 'configuration.workspace_configuration_versions.insert'
      and after_data ->> 'idempotency_key' = 'config-core-v1'
  $$,
  $$
    values (
      '31000000-0000-4000-8000-000000000001'::uuid,
      'user'::text,
      'aal2'::text
    )
  $$,
  'draft creation audit derives the validated browser actor and assurance'
);
select extensions.is(
  app.create_workspace_configuration_draft(
    '10000000-0000-4000-8000-000000000001',
    'workspace.core',
    '{"locale":"en-CA"}'::jsonb,
    app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
    '{"source":"synthetic_pgtap"}'::jsonb,
    'config-core-v1',
    'VYN-E02 retry first synthetic configuration',
    null,
    1,
    1,
    2,
    timestamptz '2026-07-16 00:00:00+00',
    null
  ),
  (
    select id
    from public.workspace_configuration_versions
    where idempotency_key = 'config-core-v1'
  ),
  'same-input draft retry returns the original version id'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'configuration.workspace_configuration_versions.insert'
      and after_data ->> 'idempotency_key' = 'config-core-v1'
  ),
  1::bigint,
  'idempotent draft retry does not duplicate the audit event'
);
select extensions.throws_ok(
  $$
    select app.create_workspace_configuration_draft(
      '10000000-0000-4000-8000-000000000001',
      'workspace.core',
      '{"locale":"fr-CA"}'::jsonb,
      app.configuration_payload_checksum('{"locale":"fr-CA"}'::jsonb),
      '{"source":"synthetic_pgtap"}'::jsonb,
      'config-core-v1',
      'replay with different payload',
      null,
      1,
      1,
      2,
      timestamptz '2026-07-16 00:00:00+00',
      null
    )
  $$,
  '23514',
  'idempotency key was already used with different configuration input',
  'idempotency keys cannot be replayed with changed configuration input'
);
select extensions.throws_ok(
  $$
    select app.create_workspace_configuration_draft(
      '20000000-0000-4000-8000-000000000002',
      'workspace.core',
      '{"locale":"fr-CA"}'::jsonb,
      app.configuration_payload_checksum('{"locale":"fr-CA"}'::jsonb),
      '{"source":"synthetic_pgtap"}'::jsonb,
      'cross-workspace-config',
      'cross-workspace attempt',
      null,
      1,
      1,
      1,
      timestamptz '2026-07-16 00:00:00+00',
      null
    )
  $$,
  '42501',
  'configuration command authorization failed',
  'T-TEN-001 a workspace A administrator cannot create workspace B configuration'
);
select extensions.throws_ok(
  $$
    insert into public.workspace_configuration_versions (
      workspace_id,
      configuration_key,
      version,
      configuration,
      checksum,
      provenance,
      configuration_schema_version,
      minimum_platform_schema_version,
      maximum_platform_schema_version,
      idempotency_key,
      created_by
    ) values (
      '10000000-0000-4000-8000-000000000001',
      'workspace.spoof',
      99,
      '{}'::jsonb,
      app.configuration_payload_checksum('{}'::jsonb),
      '{"source":"spoof"}'::jsonb,
      1,
      1,
      1,
      'browser-spoof',
      '31000000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  'permission denied for table workspace_configuration_versions',
  'browser callers cannot forge configuration versions or creator identity'
);
select extensions.throws_ok(
  $$
    select app.create_workspace_configuration_draft(
      '10000000-0000-4000-8000-000000000001',
      'workspace.bad_checksum',
      '{}'::jsonb,
      repeat('a', 64),
      '{"source":"synthetic_pgtap"}'::jsonb,
      'bad-config-checksum',
      'checksum mismatch',
      null,
      1,
      1,
      1,
      timestamptz '2026-07-16 00:00:00+00',
      null
    )
  $$,
  '23514',
  'configuration checksum does not match the canonical payload',
  'configuration drafts require the canonical payload checksum'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal2', 0);
set local role authenticated;
select extensions.throws_ok(
  $$
    select app.create_workspace_configuration_draft(
      '10000000-0000-4000-8000-000000000001',
      'workspace.denied',
      '{}'::jsonb,
      app.configuration_payload_checksum('{}'::jsonb),
      '{"source":"synthetic_pgtap"}'::jsonb,
      'limited-config-attempt',
      'missing permission',
      null,
      1,
      1,
      1,
      timestamptz '2026-07-16 00:00:00+00',
      null
    )
  $$,
  '42501',
  'configuration command authorization failed',
  'active membership does not imply configuration.manage'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 901);
set local role authenticated;
select extensions.throws_ok(
  $$
    select app.create_workspace_configuration_draft(
      '10000000-0000-4000-8000-000000000001',
      'workspace.stale',
      '{}'::jsonb,
      app.configuration_payload_checksum('{}'::jsonb),
      '{"source":"synthetic_pgtap"}'::jsonb,
      'stale-config-attempt',
      'stale step-up',
      null,
      1,
      1,
      1,
      timestamptz '2026-07-16 00:00:00+00',
      null
    )
  $$,
  '42501',
  'configuration command authorization failed',
  'configuration writes require strong authentication within fifteen minutes'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;

select extensions.lives_ok(
  $$
    select app.transition_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      'draft',
      'validated',
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      '{"passed":true,"schema":true,"dependencies":true,"fixtures":true}'::jsonb,
      'VYN-E02 validation passed'
    )
  $$,
  'draft advances to validated only with passing evidence'
);
select extensions.results_eq(
  $$
    select status, validation_evidence ->> 'passed', validated_by
    from public.workspace_configuration_versions
    where idempotency_key = 'config-core-v1'
  $$,
  $$
    values (
      'validated'::text,
      'true'::text,
      '31000000-0000-4000-8000-000000000001'::uuid
    )
  $$,
  'validation state preserves immutable evidence and derived actor'
);
select extensions.throws_ok(
  $$
    select app.transition_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      'draft',
      'reviewed',
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      '{"review":"passed"}'::jsonb,
      'stale optimistic transition'
    )
  $$,
  '40001',
  'configuration version state changed',
  'stale expected state fails as an optimistic concurrency conflict'
);
select extensions.throws_ok(
  $$
    select app.transition_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      'validated',
      'approved',
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      '{}'::jsonb,
      'skip review attempt'
    )
  $$,
  '23514',
  'invalid workspace configuration lifecycle transition',
  'lifecycle stages cannot be skipped'
);
select extensions.lives_ok(
  $$
    select app.transition_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      'validated',
      'reviewed',
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      '{"review":"synthetic fixture review"}'::jsonb,
      'VYN-E02 review passed'
    )
  $$,
  'validated configuration can advance to reviewed with evidence'
);
select extensions.lives_ok(
  $$
    select app.record_workspace_configuration_approval(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      'tenant',
      'approved',
      'approval-core-v1',
      'VYN-E02 synthetic tenant approval',
      'workspace administrator',
      'Synthetic Northstar',
      '{"scope":"synthetic only"}'::jsonb,
      'urn:synthetic:approval:core-v1',
      null,
      null,
      null
    )
  $$,
  'approvals.create with recent AAL2 records an exact-version approval'
);
select extensions.results_eq(
  $$
    select artifact_key, artifact_version, decision, decided_by
    from public.approval_records
    where idempotency_key = 'approval-core-v1'
  $$,
  $$
    values (
      'workspace.core'::text,
      1::bigint,
      'approved'::text,
      '31000000-0000-4000-8000-000000000001'::uuid
    )
  $$,
  'approval persists exact artifact identity, version, decision, and approver'
);
select extensions.is(
  app.record_workspace_configuration_approval(
    '10000000-0000-4000-8000-000000000001',
    (select id from public.workspace_configuration_versions
      where idempotency_key = 'config-core-v1'),
    app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
    'tenant',
    'approved',
    'approval-core-v1',
    'VYN-E02 synthetic tenant approval',
    'workspace administrator',
    'Synthetic Northstar',
    '{"scope":"synthetic only"}'::jsonb,
    'urn:synthetic:approval:core-v1',
    null,
    null,
    null
  ),
  (select id from public.approval_records where idempotency_key = 'approval-core-v1'),
  'same-input approval retry returns the original decision id'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'configuration.approval_records.insert'
      and after_data ->> 'idempotency_key' = 'approval-core-v1'
  ),
  1::bigint,
  'idempotent approval retry writes one append-only audit event'
);
select extensions.throws_ok(
  $$
    insert into public.approval_records (
      workspace_id,
      artifact_type,
      artifact_key,
      artifact_version,
      artifact_id,
      artifact_checksum,
      approval_type,
      decision,
      decided_by,
      idempotency_key,
      reason
    ) values (
      '10000000-0000-4000-8000-000000000001',
      'workspace_configuration',
      'workspace.core',
      1,
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      'tenant',
      'approved',
      '31000000-0000-4000-8000-000000000002',
      'spoofed-approval',
      'actor spoof'
    )
  $$,
  '42501',
  'permission denied for table approval_records',
  'browser callers cannot forge approver identity or approval lifecycle'
);
select extensions.lives_ok(
  $$
    select app.transition_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      'reviewed',
      'approved',
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      '{}'::jsonb,
      'VYN-E02 exact approval accepted'
    )
  $$,
  'reviewed configuration advances to approved with a current exact approval'
);
select extensions.is(
  (
    select status
    from public.workspace_configuration_versions
    where idempotency_key = 'config-core-v1'
  ),
  'approved',
  'approved state retains exact approval linkage'
);
select extensions.throws_ok(
  $$
    select app.activate_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      repeat('a', 64),
      1,
      'activation-core-v1-bad-checksum',
      'checksum mismatch'
    )
  $$,
  '23514',
  'configuration checksum mismatch',
  'activation requires the exact immutable checksum'
);
select extensions.throws_ok(
  $$
    select app.activate_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      3,
      'activation-core-v1-bad-platform',
      'incompatible platform'
    )
  $$,
  '23514',
  'configuration is incompatible with the current platform schema',
  'activation rejects incompatible platform schema versions'
);
select extensions.lives_ok(
  $$
    select app.activate_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      1,
      'activation-core-v1',
      'VYN-E02 activate exact approved configuration'
    )
  $$,
  'approved effective configuration activates with configuration and workspace authority'
);
select extensions.results_eq(
  $$
    select status, activation_count, activated_by
    from public.workspace_configuration_versions
    where idempotency_key = 'config-core-v1'
  $$,
  $$
    values (
      'active'::text,
      1::bigint,
      '31000000-0000-4000-8000-000000000001'::uuid
    )
  $$,
  'activation derives actor and advances activation count once'
);
select extensions.is(
  app.activate_workspace_configuration_version(
    '10000000-0000-4000-8000-000000000001',
    (select id from public.workspace_configuration_versions
      where idempotency_key = 'config-core-v1'),
    app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
    1,
    'activation-core-v1',
    'VYN-E02 activation retry'
  ),
  (select id from public.workspace_configuration_versions
    where idempotency_key = 'config-core-v1'),
  'activation retry returns the originally activated version id'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_configuration_activations
    where idempotency_key = 'activation-core-v1'
  ),
  1::bigint,
  'activation retry does not duplicate append-only activation history'
);
select extensions.ok(
  not app.is_feature_entitled(
    '10000000-0000-4000-8000-000000000001',
    'inventory'
  ),
  'capability invocation fails closed before an active entitlement exists'
);
select extensions.results_eq(
  $$select distinct workspace_id from public.workspace_configuration_versions$$,
  $$values ('10000000-0000-4000-8000-000000000001'::uuid)$$,
  'T-TEN-001 configuration.read cannot disclose another workspace history'
);

select extensions.lives_ok(
  $$
    select app.create_workspace_configuration_draft(
      '10000000-0000-4000-8000-000000000001',
      'workspace.core',
      '{"locale":"fr-CA"}'::jsonb,
      app.configuration_payload_checksum('{"locale":"fr-CA"}'::jsonb),
      '{"source":"synthetic_pgtap","previous":"config-core-v1"}'::jsonb,
      'config-core-v2',
      'VYN-E02 create successor configuration',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      1,
      1,
      2,
      timestamptz '2026-07-16 00:00:00+00',
      null
    )
  $$,
  'new configuration creates version two from the latest immutable predecessor'
);
select extensions.throws_ok(
  $$
    select app.create_workspace_configuration_draft(
      '10000000-0000-4000-8000-000000000001',
      'workspace.core',
      '{"locale":"es-CA"}'::jsonb,
      app.configuration_payload_checksum('{"locale":"es-CA"}'::jsonb),
      '{"source":"synthetic_pgtap"}'::jsonb,
      'config-core-v3-stale-base',
      'stale predecessor attempt',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      1,
      1,
      2,
      timestamptz '2026-07-16 00:00:00+00',
      null
    )
  $$,
  '40001',
  'configuration history advanced; base a new draft on the latest version',
  'serialized allocation rejects a stale predecessor instead of forking history'
);
select extensions.results_eq(
  $$
    select version
    from public.workspace_configuration_versions
    where configuration_key = 'workspace.core'
    order by version
  $$,
  $$values (1::bigint), (2::bigint)$$,
  'serialized version allocation is gap-free for committed drafts'
);
select extensions.lives_ok(
  $$
    select app.transition_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v2'),
      'draft',
      'validated',
      app.configuration_payload_checksum('{"locale":"fr-CA"}'::jsonb),
      '{"passed":true,"schema":true,"dependencies":true,"fixtures":true}'::jsonb,
      'validate successor'
    )
  $$,
  'successor draft validates'
);
select extensions.lives_ok(
  $$
    select app.transition_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v2'),
      'validated',
      'reviewed',
      app.configuration_payload_checksum('{"locale":"fr-CA"}'::jsonb),
      '{"review":"successor reviewed"}'::jsonb,
      'review successor'
    )
  $$,
  'successor validation advances to review'
);
select extensions.lives_ok(
  $$
    select app.record_workspace_configuration_approval(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v2'),
      app.configuration_payload_checksum('{"locale":"fr-CA"}'::jsonb),
      'tenant',
      'approved',
      'approval-core-v2',
      'approve successor'
    )
  $$,
  'successor receives its own exact approval record'
);
select extensions.lives_ok(
  $$
    select app.transition_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v2'),
      'reviewed',
      'approved',
      app.configuration_payload_checksum('{"locale":"fr-CA"}'::jsonb),
      '{}'::jsonb,
      'accept successor approval'
    )
  $$,
  'successor advances to approved'
);
select extensions.lives_ok(
  $$
    select app.activate_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v2'),
      app.configuration_payload_checksum('{"locale":"fr-CA"}'::jsonb),
      1,
      'activation-core-v2',
      'activate successor'
    )
  $$,
  'successor activation atomically supersedes the prior active version'
);
select extensions.results_eq(
  $$
    select version, status
    from public.workspace_configuration_versions
    where configuration_key = 'workspace.core'
    order by version
  $$,
  $$values (1::bigint, 'superseded'::text), (2::bigint, 'active'::text)$$,
  'exactly one version is active after supersession'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_configuration_activations
    where configuration_key = 'workspace.core'
  ),
  2::bigint,
  'each successful activation appends one history record'
);
select extensions.lives_ok(
  $$
    select app.activate_workspace_configuration_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_configuration_versions
        where idempotency_key = 'config-core-v1'),
      app.configuration_payload_checksum('{"locale":"en-CA"}'::jsonb),
      1,
      'rollback-core-v1',
      'rollback to earlier compatible approved version'
    )
  $$,
  'rollback reactivates an earlier approved compatible exact version'
);
select extensions.results_eq(
  $$
    select cv.version, cv.status, cv.activation_count,
      (
        select activation.activation_kind
        from public.workspace_configuration_activations activation
        where activation.configuration_version_id = cv.id
        order by activation.created_at desc, activation.id desc
        limit 1
      )
    from public.workspace_configuration_versions cv
    where cv.configuration_key = 'workspace.core'
    order by cv.version
  $$,
  $$
    values
      (1::bigint, 'active'::text, 2::bigint, 'rollback'::text),
      (2::bigint, 'superseded'::text, 1::bigint, 'activate'::text)
  $$,
  'rollback preserves immutable version lineage and append-only activation history'
);

select extensions.throws_ok(
  $$
    select app.install_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      'inventory',
      true,
      '{}'::jsonb,
      app.entitlement_payload_checksum(true, '{}'::jsonb),
      '{"source":"synthetic_contract"}'::jsonb,
      timestamptz '2026-07-16 00:00:00+00',
      'inventory-entitlement-v1-browser',
      'browser self-entitlement attempt',
      null
    )
  $$,
  '42501',
  'permission denied for function install_workspace_feature_entitlement_version',
  'workspace administrators cannot self-grant commercial entitlements'
);

reset role;
set local role service_role;

select extensions.lives_ok(
  $$
    select app.install_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      'inventory',
      true,
      '{"max_active_units":100}'::jsonb,
      app.entitlement_payload_checksum(true, '{"max_active_units":100}'::jsonb),
      '{"source":"synthetic_contract","reference":"plan-fixture"}'::jsonb,
      timestamptz '2026-07-16 00:00:00+00',
      'inventory-entitlement-v1',
      'install synthetic inventory entitlement',
      null
    )
  $$,
  'trusted service can install an immutable entitlement draft'
);
select extensions.is(
  app.install_workspace_feature_entitlement_version(
    '10000000-0000-4000-8000-000000000001',
    'inventory',
    true,
    '{"max_active_units":100}'::jsonb,
    app.entitlement_payload_checksum(true, '{"max_active_units":100}'::jsonb),
    '{"source":"synthetic_contract","reference":"plan-fixture"}'::jsonb,
    timestamptz '2026-07-16 00:00:00+00',
    'inventory-entitlement-v1',
    'retry synthetic inventory entitlement',
    null
  ),
  (
    select id from public.workspace_feature_entitlements
    where idempotency_key = 'inventory-entitlement-v1'
  ),
  'same-input entitlement install retry returns the original version id'
);
select extensions.throws_ok(
  $$
    select app.install_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      'inventory',
      false,
      '{"max_active_units":100}'::jsonb,
      app.entitlement_payload_checksum(false, '{"max_active_units":100}'::jsonb),
      '{"source":"synthetic_contract","reference":"plan-fixture"}'::jsonb,
      timestamptz '2026-07-16 00:00:00+00',
      'inventory-entitlement-v1',
      'changed replay',
      null
    )
  $$,
  '23514',
  'idempotency key was already used with different entitlement input',
  'entitlement idempotency keys cannot be replayed with changed capability state'
);
select extensions.lives_ok(
  $$
    select app.activate_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_feature_entitlements
        where idempotency_key = 'inventory-entitlement-v1'),
      app.entitlement_payload_checksum(true, '{"max_active_units":100}'::jsonb),
      'activate synthetic inventory entitlement'
    )
  $$,
  'trusted service can activate an effective entitlement version'
);
select extensions.lives_ok(
  $$
    select app.activate_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_feature_entitlements
        where idempotency_key = 'inventory-entitlement-v1'),
      app.entitlement_payload_checksum(true, '{"max_active_units":100}'::jsonb),
      'retry synthetic inventory entitlement activation'
    )
  $$,
  'entitlement activation is state-idempotent'
);
select extensions.results_eq(
  $$
    select version, status, enabled
    from public.workspace_feature_entitlements
    where entitlement_key = 'inventory'
      and workspace_id = '10000000-0000-4000-8000-000000000001'
  $$,
  $$values (1::bigint, 'active'::text, true)$$,
  'active entitlement preserves version, lifecycle, and capability decision'
);
select extensions.ok(
  app.is_feature_entitled(
    '10000000-0000-4000-8000-000000000001',
    'inventory'
  ),
  'shared entitlement service allows active enabled effective capability'
);
select extensions.results_eq(
  $$
    select actor_user_id, actor_type, auth_assurance
    from public.audit_events
    where action = 'configuration.workspace_feature_entitlements.insert'
      and after_data ->> 'idempotency_key' = 'inventory-entitlement-v1'
  $$,
  $$values (null::uuid, 'service'::text, 'system'::text)$$,
  'service entitlement writes ignore stale browser claims in audit attribution'
);
select extensions.lives_ok(
  $$
    select app.install_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      'inventory',
      false,
      '{}'::jsonb,
      app.entitlement_payload_checksum(false, '{}'::jsonb),
      '{"source":"synthetic_contract","reference":"plan-change"}'::jsonb,
      timestamptz '2026-07-16 00:00:00+00',
      'inventory-entitlement-v2',
      'install disabled successor entitlement',
      null
    )
  $$,
  'trusted service creates a successor entitlement history version'
);
select extensions.lives_ok(
  $$
    select app.activate_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_feature_entitlements
        where idempotency_key = 'inventory-entitlement-v2'),
      app.entitlement_payload_checksum(false, '{}'::jsonb),
      'activate disabled successor entitlement'
    )
  $$,
  'successor entitlement activation supersedes the prior version atomically'
);
select extensions.results_eq(
  $$
    select version, status, enabled
    from public.workspace_feature_entitlements
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and entitlement_key = 'inventory'
    order by version
  $$,
  $$
    values
      (1::bigint, 'superseded'::text, true),
      (2::bigint, 'active'::text, false)
  $$,
  'entitlement history retains superseded capability decisions'
);
select extensions.ok(
  not app.is_feature_entitled(
    '10000000-0000-4000-8000-000000000001',
    'inventory'
  ),
  'active disabled version denies capability invocation'
);
select extensions.lives_ok(
  $$
    select app.retire_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_feature_entitlements
        where idempotency_key = 'inventory-entitlement-v2'),
      app.entitlement_payload_checksum(false, '{}'::jsonb),
      'retire disabled entitlement version'
    )
  $$,
  'trusted service retires an entitlement without rewriting history'
);
select extensions.lives_ok(
  $$
    select app.retire_workspace_feature_entitlement_version(
      '10000000-0000-4000-8000-000000000001',
      (select id from public.workspace_feature_entitlements
        where idempotency_key = 'inventory-entitlement-v2'),
      app.entitlement_payload_checksum(false, '{}'::jsonb),
      'retry entitlement retirement'
    )
  $$,
  'entitlement retirement is state-idempotent'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_feature_entitlements
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and entitlement_key = 'inventory'
      and status = 'active'
  ),
  0::bigint,
  'retirement leaves no active capability version'
);
select extensions.lives_ok(
  $$
    select app.install_workspace_feature_entitlement_version(
      '20000000-0000-4000-8000-000000000002',
      'inventory',
      true,
      '{}'::jsonb,
      app.entitlement_payload_checksum(true, '{}'::jsonb),
      '{"source":"synthetic_contract"}'::jsonb,
      timestamptz '2026-07-16 00:00:00+00',
      'harbour-inventory-entitlement-v1',
      'install workspace B entitlement',
      null
    )
  $$,
  'trusted service can install an independently scoped workspace B entitlement'
);
select extensions.lives_ok(
  $$
    select app.activate_workspace_feature_entitlement_version(
      '20000000-0000-4000-8000-000000000002',
      (select id from public.workspace_feature_entitlements
        where idempotency_key = 'harbour-inventory-entitlement-v1'),
      app.entitlement_payload_checksum(true, '{}'::jsonb),
      'activate workspace B entitlement'
    )
  $$,
  'workspace B entitlement activates independently'
);

reset role;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;
select extensions.results_eq(
  $$select distinct workspace_id from public.workspace_feature_entitlements$$,
  $$values ('10000000-0000-4000-8000-000000000001'::uuid)$$,
  'T-TEN-001 workspace A cannot read workspace B entitlement history'
);
select extensions.ok(
  not app.is_feature_entitled(
    '20000000-0000-4000-8000-000000000002',
    'inventory'
  ),
  'T-TEN-001 entitlement helper fails closed for a foreign workspace'
);
select extensions.results_eq(
  $$
    select distinct workspace_id
    from public.audit_events
    where action like 'configuration.%'
  $$,
  $$values ('10000000-0000-4000-8000-000000000001'::uuid)$$,
  'T-TEN-001 audit.read never discloses foreign configuration events'
);

reset role;
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001', 'aal2', 0);
set local role authenticated;
select extensions.results_eq(
  $$select distinct workspace_id from public.workspace_feature_entitlements$$,
  $$values ('20000000-0000-4000-8000-000000000002'::uuid)$$,
  'workspace B reads only its own entitlement history'
);
select extensions.ok(
  app.is_feature_entitled(
    '20000000-0000-4000-8000-000000000002',
    'inventory'
  ),
  'workspace B independently resolves its active entitlement'
);
select extensions.is(
  (select pg_catalog.count(*) from public.workspace_configuration_versions),
  0::bigint,
  'workspace B cannot read workspace A configuration history'
);

reset role;
select extensions.throws_ok(
  $$
    update public.workspace_configuration_versions
    set configuration = '{"locale":"tampered"}'::jsonb,
        checksum = app.configuration_payload_checksum('{"locale":"tampered"}'::jsonb)
    where idempotency_key = 'config-core-v1'
  $$,
  '23514',
  'workspace_configuration_versions.configuration is immutable',
  'active configuration payloads cannot be changed in place'
);
select extensions.throws_ok(
  $$
    update public.approval_records
    set reason = 'tampered'
    where idempotency_key = 'approval-core-v1'
  $$,
  '55000',
  'approval_records records are append-only',
  'approval history cannot be rewritten'
);
select extensions.throws_ok(
  $$
    delete from public.workspace_configuration_activations
    where idempotency_key = 'activation-core-v1'
  $$,
  '55000',
  'workspace_configuration_activations records are append-only',
  'activation and rollback history cannot be deleted'
);
select extensions.throws_ok(
  $$
    delete from public.workspace_configuration_versions
    where idempotency_key = 'config-core-v1'
  $$,
  '55000',
  'hard delete is prohibited for workspace_configuration_versions',
  'configuration versions use retirement rather than hard delete'
);
select extensions.throws_ok(
  $$
    delete from public.workspace_feature_entitlements
    where idempotency_key = 'inventory-entitlement-v1'
  $$,
  '55000',
  'hard delete is prohibited for workspace_feature_entitlements',
  'entitlement history cannot be hard deleted'
);

select * from extensions.finish();
rollback;
