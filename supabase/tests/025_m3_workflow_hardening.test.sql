-- VYN-WF-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001,
-- T-WF-001 through T-WF-004, T-RBAC-001, T-TEN-001, T-AUD-001,
-- M3-WF-AC-001 through M3-WF-AC-004.
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(48);

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
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.workflow_fixture (
  states jsonb not null,
  transitions jsonb not null,
  checksum text not null
);
create temporary table pg_temp.workflow_results (
  phase text primary key,
  result jsonb not null
);
grant all on pg_temp.workflow_fixture, pg_temp.workflow_results
  to authenticated, service_role;

insert into pg_temp.workflow_fixture (states, transitions, checksum)
select
  fixture.states,
  fixture.transitions,
  app.workflow_configuration_checksum(
    'custom.deal.review',
    'deal',
    'primary',
    '1.0.0',
    1,
    'new',
    fixture.states,
    fixture.transitions
  )
from (
  select
    '[
      {
        "key":"new",
        "canonicalCategory":"draft",
        "labels":{"en":"New","fr":"Nouveau"},
        "behaviorFlags":{"terminal":false},
        "requiredFields":[],
        "sortOrder":10
      },
      {
        "key":"ready",
        "canonicalCategory":"active",
        "labels":{"en":"Ready","fr":"Pret"},
        "behaviorFlags":{"terminal":false},
        "requiredFields":["customer.party_id"],
        "sortOrder":20
      }
    ]'::jsonb as states,
    '[
      {
        "key":"qualify",
        "fromStateKey":"new",
        "toStateKey":"ready",
        "permissionKey":"deals.transition",
        "guardKey":"lender_approval_recorded",
        "reasonRequired":false,
        "requiredFields":["finance.lender_id"],
        "effectKeys":["deal.document_readiness_review"]
      }
    ]'::jsonb as transitions
) fixture;

select extensions.has_function(
  'app', 'assert_workflow_semantic_flags', array['text','jsonb','jsonb'],
  'configured workflow semantic flag validator exists'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_definition
    where constraint_definition.conrelid
        = 'public.workflow_admin_command_receipts'::pg_catalog.regclass
      and constraint_definition.contype = 'f'
      and pg_catalog.pg_get_constraintdef(constraint_definition.oid)
        like 'FOREIGN KEY (workspace_id, audit_event_id)%'
  ),
  'T-TEN-001 workflow receipt audit evidence preserves workspace context'
);
select extensions.lives_ok(
  $$
    select app.assert_workflow_semantic_flags(
      'lead',
      '[
        {"key":"review_ready","canonicalCategory":"active","behaviorFlags":{"terminal":false,"conversion_eligible":true}},
        {"key":"won","canonicalCategory":"closed","behaviorFlags":{"terminal":true,"conversion_target":true}},
        {"key":"deferred","canonicalCategory":"closed","behaviorFlags":{"terminal":true,"loss_terminal":true}}
      ]'::jsonb,
      '[
        {"fromStateKey":"review_ready","toStateKey":"won","reasonRequired":false},
        {"fromStateKey":"review_ready","toStateKey":"deferred","reasonRequired":true}
      ]'::jsonb
    )
  $$,
  'lead semantic flags work with tenant-neutral alternate state keys'
);
select extensions.throws_ok(
  $$
    select app.assert_workflow_semantic_flags(
      'lead',
      '[
        {"key":"review_ready","canonicalCategory":"active","behaviorFlags":{"terminal":false,"conversion_eligible":true}},
        {"key":"won","canonicalCategory":"active","behaviorFlags":{"terminal":false,"conversion_target":true}}
      ]'::jsonb,
      '[{"fromStateKey":"review_ready","toStateKey":"won","reasonRequired":false}]'::jsonb
    )
  $$,
  '22023',
  'workflow semantic flags have an invalid lifecycle shape',
  'non-terminal conversion targets fail closed'
);
select extensions.throws_ok(
  $$
    select app.assert_workflow_semantic_flags(
      'deal',
      '[
        {"key":"open","canonicalCategory":"active","behaviorFlags":{"terminal":false}},
        {"key":"abandoned","canonicalCategory":"closed","behaviorFlags":{"terminal":true,"cancellation":true}}
      ]'::jsonb,
      '[{"fromStateKey":"open","toStateKey":"abandoned","reasonRequired":false}]'::jsonb
    )
  $$,
  '22023',
  'deal cancellation transitions require reasons',
  'configured cancellation semantics always require a reason'
);

-- An inventory-only reader proves entity-aware RLS independently of the broad
-- synthetic roles installed by the starter pack.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '33000000-0000-4000-8000-000000000025',
  'authenticated', 'authenticated', 'workflow-reader-025@example.invalid',
  extensions.crypt(pg_catalog.gen_random_uuid()::text, extensions.gen_salt('bf')),
  pg_catalog.statement_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"fixture":true}'::jsonb,
  pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp(),
  '', '', '', ''
);
insert into public.workspace_memberships (
  id, workspace_id, user_id, status, invited_at, activated_at
) values (
  '43000000-0000-4000-8000-000000000025',
  '10000000-0000-4000-8000-000000000001',
  '33000000-0000-4000-8000-000000000025',
  'active', pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp()
);
insert into public.user_profiles (
  user_id, display_name, preferred_locale, status, last_workspace_id
) values (
  '33000000-0000-4000-8000-000000000025',
  'Workflow inventory reader', 'en-CA', 'active',
  '10000000-0000-4000-8000-000000000001'
);
insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  '53000000-0000-4000-8000-000000000025',
  '10000000-0000-4000-8000-000000000001',
  'workflow_inventory_reader_025', 'Workflow inventory reader',
  'system', 'active', false
);
insert into public.role_permissions (
  workspace_id, role_id, permission_id, status
)
select
  '10000000-0000-4000-8000-000000000001',
  '53000000-0000-4000-8000-000000000025',
  permission.id,
  'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key = 'inventory.read';
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '63000000-0000-4000-8000-000000000025',
  '10000000-0000-4000-8000-000000000001',
  '43000000-0000-4000-8000-000000000025',
  '53000000-0000-4000-8000-000000000025',
  'active'
);

insert into public.workflow_definitions (
  id, workspace_id, key, entity_type, purpose_key, status
) values (
  '75000000-0000-4000-8000-000000000025',
  '10000000-0000-4000-8000-000000000001',
  'fixture.lead.rls', 'lead', 'primary', 'active'
);
insert into public.workflow_versions (
  id, workspace_id, workflow_definition_id, revision, version,
  schema_version, initial_state_key, status, checksum, source
) values (
  '75100000-0000-4000-8000-000000000025',
  '10000000-0000-4000-8000-000000000001',
  '75000000-0000-4000-8000-000000000025',
  1, '1.0.0', 1, 'new', 'draft', repeat('2', 64), 'configuration'
);
insert into public.workflow_states (
  id, workspace_id, workflow_version_id, key, canonical_category,
  labels, behavior_flags, required_fields, sort_order
) values
  (
    '75200000-0000-4000-8000-000000000025',
    '10000000-0000-4000-8000-000000000001',
    '75100000-0000-4000-8000-000000000025',
    'new', 'draft', '{"en":"New","fr":"Nouveau"}',
    '{"terminal":false}', '{}'::text[], 10
  ),
  (
    '75200000-0000-4000-8000-000000000026',
    '10000000-0000-4000-8000-000000000001',
    '75100000-0000-4000-8000-000000000025',
    'contacted', 'active', '{"en":"Contacted","fr":"Contacte"}',
    '{"terminal":false}', array['lead.owner_id'], 20
  );
insert into public.workflow_transitions (
  id, workspace_id, workflow_version_id, key, from_state_key, to_state_key,
  permission_key, guard_key, reason_required, required_fields, effect_keys
) values (
  '75300000-0000-4000-8000-000000000025',
  '10000000-0000-4000-8000-000000000001',
  '75100000-0000-4000-8000-000000000025',
  'contact', 'new', 'contacted', 'crm.update', null, false,
  array['lead.email'], '["lead.follow_up_review"]'
);
insert into public.workflow_instances (
  id, workspace_id, workflow_version_id, entity_type, entity_id, purpose_key,
  current_state_key, canonical_status, lifecycle_status, version
) values (
  '75400000-0000-4000-8000-000000000025',
  '10000000-0000-4000-8000-000000000001',
  '75100000-0000-4000-8000-000000000025',
  'lead', '72400000-0000-4000-8000-000000000025', 'primary',
  'contacted', 'active', 'active', 2
);
insert into public.workflow_events (
  id, workspace_id, workflow_instance_id, transition_id, entity_type,
  entity_id, from_state_key, to_state_key, aggregate_version, reason,
  actor_user_id, request_id, correlation_id
) values (
  '75500000-0000-4000-8000-000000000025',
  '10000000-0000-4000-8000-000000000001',
  '75400000-0000-4000-8000-000000000025',
  '75300000-0000-4000-8000-000000000025',
  'lead', '72400000-0000-4000-8000-000000000025',
  'new', 'contacted', 2, repeat('r', 2000),
  '31000000-0000-4000-8000-000000000001',
  'm3-workflow-event', '75600000-0000-4000-8000-000000000025'
);

select extensions.ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workflow_versions'
      and column_name = 'revision' and is_nullable = 'NO'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workflow_states'
      and column_name = 'required_fields'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workflow_transitions'
      and column_name = 'required_fields'
  ),
  'T-WF-001 workflow revision and state/transition required fields are persisted'
);
select extensions.ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workflow_events'
      and column_name = 'input_snapshot'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workflow_events'
      and column_name = 'effect_snapshot'
  ),
  'T-WF-004 workflow event input and effect snapshots are persisted'
);
select extensions.is(
  app.workflow_entity_read_permission('lead'),
  'crm.read',
  'T-WF-004 lead workflow reads map only to CRM permission'
);
select extensions.is(
  app.workflow_entity_read_permission('deal'),
  'deals.read',
  'T-WF-004 deal workflow reads map only to deals permission'
);
select extensions.ok(
  app.workflow_guard_allowed_for_entity('lead', 'lead_conversion_requirements_met')
  and app.workflow_guard_allowed_for_entity('deal', 'lender_approval_recorded')
  and not app.workflow_guard_allowed_for_entity('lead', 'lender_approval_recorded'),
  'T-WF-002 lead and deal guard catalogs are finite and entity-specific'
);
select extensions.ok(
  app.workflow_effect_allowed_for_entity('lead', 'lead.follow_up_review')
  and app.workflow_effect_allowed_for_entity(
    'deal', 'deal.document_readiness_review'
  )
  and not app.workflow_effect_allowed_for_entity('lead', 'listing.publish'),
  'T-WF-002 inert effect catalogs are finite and entity-specific'
);
select extensions.is(
  (select pg_catalog.char_length(reason) from public.workflow_events
   where id = '75500000-0000-4000-8000-000000000025'),
  2000,
  'T-WF-003 SQL accepts the shared 2,000-character reason boundary'
);
select extensions.is(
  (select input_snapshot from public.workflow_events
   where id = '75500000-0000-4000-8000-000000000025'),
  '{
    "guardKey":null,
    "guardSatisfied":null,
    "reasonProvided":true,
    "requiredFieldKeys":["lead.email","lead.owner_id"]
  }'::jsonb,
  'T-WF-004 workflow event input snapshot excludes entity values'
);
select extensions.is(
  (select effect_snapshot from public.workflow_events
   where id = '75500000-0000-4000-8000-000000000025'),
  '{"effectKeys":["lead.follow_up_review"]}'::jsonb,
  'T-WF-004 workflow event effect snapshot captures inert declarations'
);
select extensions.throws_ok(
  $$
    update public.workflow_events
    set input_snapshot = '{}'::jsonb
    where id = '75500000-0000-4000-8000-000000000025'
  $$,
  '55000',
  'inventory and workflow history is append-only',
  'T-WF-004 workflow event snapshots are append-only'
);
select extensions.throws_ok(
  $$
    insert into public.workflow_events (
      workspace_id, workflow_instance_id, transition_id, entity_type,
      entity_id, from_state_key, to_state_key, aggregate_version, reason,
      actor_user_id, correlation_id
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '75400000-0000-4000-8000-000000000025',
      '75300000-0000-4000-8000-000000000025',
      'lead', '72400000-0000-4000-8000-000000000025',
      'new', 'contacted', 3, repeat('x', 2001),
      '31000000-0000-4000-8000-000000000001',
      '75600000-0000-4000-8000-000000000026'
    )
  $$,
  '23514',
  null,
  'T-WF-003 SQL rejects reasons beyond 2,000 characters'
);

select pg_temp.authenticate_as('33000000-0000-4000-8000-000000000025');
set local role authenticated;
select extensions.ok(
  exists (
    select 1 from public.workflow_definitions
    where key = 'inventory.standard'
  ),
  'T-WF-004 inventory reader retains inventory workflow visibility'
);
select extensions.is(
  (select pg_catalog.count(*)::integer from public.workflow_definitions
   where id = '75000000-0000-4000-8000-000000000025'),
  0,
  'T-WF-004 inventory reader cannot see lead workflow definitions'
);
select extensions.is(
  (select pg_catalog.count(*)::integer from public.workflow_instances
   where id = '75400000-0000-4000-8000-000000000025'),
  0,
  'T-WF-004 inventory reader cannot see lead workflow instances'
);
select extensions.is(
  (select pg_catalog.count(*)::integer from public.workflow_events
   where id = '75500000-0000-4000-8000-000000000025'),
  0,
  'T-WF-004 inventory reader cannot see lead workflow events'
);
reset role;

select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.read_workflow_definition_admin(uuid,uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'app.create_workflow_version_admin(uuid,text,text,text,text,text,integer,text,jsonb,jsonb,text,uuid,text,text,uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'app.approve_workflow_version_admin(uuid,text,uuid,bigint,text,text,timestamp with time zone,text,uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'app.activate_workflow_version_admin(uuid,text,uuid,bigint,text,text,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'app.read_workflow_definition_admin(uuid,uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'app.activate_workflow_version_admin(uuid,text,uuid,bigint,text,text,text,uuid)',
    'EXECUTE'
  ),
  'T-RBAC-001 only authenticated humans receive workflow administration RPCs'
);
select extensions.ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'app.read_workflow_definition_admin(uuid,uuid)'::regprocedure
      )
    ),
    'limit 100'
  ) > 0,
  'workflow administration reads are bounded to the latest 100 versions'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.workflow_version_artifact(uuid,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'app.workflow_version_has_valid_approval(uuid,uuid,timestamp with time zone)',
    'EXECUTE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.workflow_admin_command_receipts', 'SELECT'
  ),
  'T-RBAC-001 workflow internals and receipts are not browser-readable'
);
select extensions.ok(
  not app.workspace_entitlement_is_enabled(
    '90000000-0000-4000-8000-000000000025',
    'custom_workflows',
    pg_catalog.statement_timestamp()
  ),
  'T-WF-004 missing custom_workflows entitlement fails closed'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'app'
      and procedure.proname in (
        'read_workflow_definition_admin',
        'create_workflow_version_admin',
        'approve_workflow_version_admin',
        'activate_workflow_version_admin'
      )
      and procedure.prosrc like '%workspace_entitlement_is_enabled%'
      and procedure.prosrc like '%custom_workflows%'
  ),
  4,
  'T-WF-004 every workflow administration RPC enforces custom_workflows'
);
select extensions.ok(
  exists (
    select 1
    from public.workflow_versions version
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key = 'inventory.standard'
      and version.source = 'starter_pack'
      and version.status = 'active'
      and version.revision > 0
      and version.approval_record_id is null
  ),
  'T-WF-004 trusted starter installation retains raw-pack activation semantics'
);
select extensions.throws_ok(
  $$
    update public.workflow_states
    set labels = '{"en":"Changed","fr":"Change"}'::jsonb
    where workflow_version_id in (
      select version.id
      from public.workflow_versions version
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where definition.key = 'inventory.standard'
        and version.status = 'active'
      limit 1
    )
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'T-WF-004 activated starter workflow children remain immutable'
);
select extensions.is(
  app.workflow_configuration_checksum(
    'custom.deal.review', 'deal', 'primary', '1.0.0', 1, 'new',
    pg_catalog.jsonb_build_array(
      (select states -> 1 from pg_temp.workflow_fixture),
      (select states -> 0 from pg_temp.workflow_fixture)
    ),
    (select transitions from pg_temp.workflow_fixture)
  ),
  (select checksum from pg_temp.workflow_fixture),
  'T-WF-004 canonical checksum is independent of input state ordering'
);

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'aal1'
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select app.create_workflow_version_admin(
      '10000000-0000-4000-8000-000000000001',
      'workflow-create-aal1-025',
      'custom.deal.review', 'deal', 'primary', '1.0.0', 1, 'new',
      (select states from pg_temp.workflow_fixture),
      (select transitions from pg_temp.workflow_fixture),
      (select checksum from pg_temp.workflow_fixture),
      null::uuid,
      'AAL1 must not create workflow configuration.',
      'm3-workflow-aal1',
      '75600000-0000-4000-8000-000000000027'
    )
  $$,
  '42501',
  'configuration command authorization failed',
  'T-WF-004 workflow draft creation requires recent AAL2'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.workflow_results (phase, result)
select 'create-first', app.create_workflow_version_admin(
  '10000000-0000-4000-8000-000000000001',
  'workflow-create-025',
  'custom.deal.review', 'deal', 'primary', '1.0.0', 1, 'new',
  (select states from pg_temp.workflow_fixture),
  (select transitions from pg_temp.workflow_fixture),
  (select checksum from pg_temp.workflow_fixture),
  null::uuid,
  'Create the synthetic workflow draft.',
  'm3-workflow-create',
  '75600000-0000-4000-8000-000000000028'
);
insert into pg_temp.workflow_results (phase, result)
select 'create-replay', app.create_workflow_version_admin(
  '10000000-0000-4000-8000-000000000001',
  'workflow-create-025',
  'custom.deal.review', 'deal', 'primary', '1.0.0', 1, 'new',
  (select states from pg_temp.workflow_fixture),
  (select transitions from pg_temp.workflow_fixture),
  (select checksum from pg_temp.workflow_fixture),
  null::uuid,
  'Create the synthetic workflow draft.',
  'm3-workflow-create',
  '75600000-0000-4000-8000-000000000028'
);
select extensions.is(
  (select (result ->> 'replayed')::boolean from pg_temp.workflow_results
   where phase = 'create-first'),
  false,
  'T-WF-004 create-version returns an original result'
);
select extensions.is(
  (select (result ->> 'replayed')::boolean from pg_temp.workflow_results
   where phase = 'create-replay'),
  true,
  'T-WF-004 identical create-version replay is deterministic'
);
select extensions.throws_ok(
  $$
    select app.create_workflow_version_admin(
      '10000000-0000-4000-8000-000000000001',
      'workflow-create-025',
      'custom.deal.review', 'deal', 'primary', '1.0.0', 1, 'new',
      (select states from pg_temp.workflow_fixture),
      (select transitions from pg_temp.workflow_fixture),
      (select checksum from pg_temp.workflow_fixture),
      null::uuid,
      'Changed input under the same idempotency key.',
      'm3-workflow-create',
      '75600000-0000-4000-8000-000000000028'
    )
  $$,
  '23505',
  'workflow idempotency key was used for different create input',
  'T-WF-004 create-version idempotency key reuse fails closed'
);
reset role;

select extensions.is(
  (
    select pg_catalog.concat(
      definition.key::text, ':', definition.entity_type, ':', version.status,
      ':', version.revision, ':', version.source
    )
    from public.workflow_definitions definition
    join public.workflow_versions version
      on version.workspace_id = definition.workspace_id
     and version.workflow_definition_id = definition.id
    where version.id = (
      select (result ->> 'workflowVersionId')::uuid
      from pg_temp.workflow_results where phase = 'create-first'
    )
  ),
  'custom.deal.review:deal:draft:1:configuration',
  'T-WF-004 create-version persists dotted identity and configuration provenance'
);
select extensions.is(
  (
    select pg_catalog.concat_ws(
      ':',
      pg_catalog.array_to_string(state.required_fields, ','),
      pg_catalog.array_to_string(transition.required_fields, ','),
      transition.guard_key,
      transition.effect_keys ->> 0
    )
    from public.workflow_states state
    join public.workflow_transitions transition
      on transition.workspace_id = state.workspace_id
     and transition.workflow_version_id = state.workflow_version_id
    where state.workflow_version_id = (
      select (result ->> 'workflowVersionId')::uuid
      from pg_temp.workflow_results where phase = 'create-first'
    )
      and state.key = 'ready'
      and transition.key = 'qualify'
  ),
  'customer.party_id:finance.lender_id:lender_approval_recorded:deal.document_readiness_review',
  'T-WF-003 create-version persists required fields, guard, and inert effect'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.workflow_admin_command_receipts receipt
    where receipt.command_type = 'create_workflow_version'
      and receipt.idempotency_key = 'workflow-create-025'
      and receipt.actor_user_id = '31000000-0000-4000-8000-000000000001'
  ),
  1,
  'T-WF-004 create-version stores one actor-scoped receipt'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select app.approve_workflow_version_admin(
      '10000000-0000-4000-8000-000000000001',
      'workflow-approve-stale-025',
      (select (result ->> 'workflowVersionId')::uuid
       from pg_temp.workflow_results where phase = 'create-first'),
      99,
      (select checksum from pg_temp.workflow_fixture),
      'Stale workflow approval must fail.',
      null::timestamptz,
      'm3-workflow-approve-stale',
      '75600000-0000-4000-8000-000000000029'
    )
  $$,
  '40001',
  'workflow revision conflict',
  'T-WF-004 stale workflow approval loses optimistically'
);
insert into pg_temp.workflow_results (phase, result)
select 'approve-first', app.approve_workflow_version_admin(
  '10000000-0000-4000-8000-000000000001',
  'workflow-approve-025',
  (select (result ->> 'workflowVersionId')::uuid
   from pg_temp.workflow_results where phase = 'create-first'),
  1,
  (select checksum from pg_temp.workflow_fixture),
  'Approve the exact synthetic workflow draft.',
  null::timestamptz,
  'm3-workflow-approve',
  '75600000-0000-4000-8000-000000000030'
);
insert into pg_temp.workflow_results (phase, result)
select 'approve-replay', app.approve_workflow_version_admin(
  '10000000-0000-4000-8000-000000000001',
  'workflow-approve-025',
  (select (result ->> 'workflowVersionId')::uuid
   from pg_temp.workflow_results where phase = 'create-first'),
  1,
  (select checksum from pg_temp.workflow_fixture),
  'Approve the exact synthetic workflow draft.',
  null::timestamptz,
  'm3-workflow-approve',
  '75600000-0000-4000-8000-000000000030'
);
select extensions.is(
  (select (result ->> 'replayed')::boolean from pg_temp.workflow_results
   where phase = 'approve-first'),
  false,
  'T-WF-004 workflow approval returns an original result'
);
select extensions.is(
  (select (result ->> 'replayed')::boolean from pg_temp.workflow_results
   where phase = 'approve-replay'),
  true,
  'T-WF-004 identical workflow approval replay is deterministic'
);
reset role;

select extensions.ok(
  exists (
    select 1
    from public.workflow_versions version
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    join public.approval_records approval
      on approval.workspace_id = version.workspace_id
     and approval.id = version.approval_record_id
    where version.id = (
      select (result ->> 'workflowVersionId')::uuid
      from pg_temp.workflow_results where phase = 'create-first'
    )
      and approval.artifact_type = 'workflow_version'
      and approval.artifact_key = 'workflow.custom.deal.review'
      and approval.artifact_version = version.revision
      and approval.artifact_id = version.id
      and approval.artifact_checksum = version.checksum
      and approval.decision = 'approved'
      and approval.decided_by = version.approved_by
      and approval.decided_at = version.approved_at
  ),
  'T-WF-004 approval freezes the exact revision, artifact, checksum, and actor'
);
select extensions.throws_ok(
  $$
    update public.workflow_transitions
    set reason_required = true
    where workflow_version_id = (
      select (result ->> 'workflowVersionId')::uuid
      from pg_temp.workflow_results where phase = 'create-first'
    )
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'T-WF-004 approved workflow child configuration is immutable'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select app.activate_workflow_version_admin(
      '10000000-0000-4000-8000-000000000001',
      'workflow-activate-stale-025',
      (select (result ->> 'workflowVersionId')::uuid
       from pg_temp.workflow_results where phase = 'create-first'),
      1,
      repeat('f', 64),
      'Wrong checksum activation must fail.',
      'm3-workflow-activate-stale',
      '75600000-0000-4000-8000-000000000031'
    )
  $$,
  '23514',
  'workflow checksum mismatch',
  'T-WF-004 activation fails closed on checksum drift'
);
insert into pg_temp.workflow_results (phase, result)
select 'activate-first', app.activate_workflow_version_admin(
  '10000000-0000-4000-8000-000000000001',
  'workflow-activate-025',
  (select (result ->> 'workflowVersionId')::uuid
   from pg_temp.workflow_results where phase = 'create-first'),
  1,
  (select checksum from pg_temp.workflow_fixture),
  'Activate the approved synthetic workflow.',
  'm3-workflow-activate',
  '75600000-0000-4000-8000-000000000032'
);
insert into pg_temp.workflow_results (phase, result)
select 'activate-replay', app.activate_workflow_version_admin(
  '10000000-0000-4000-8000-000000000001',
  'workflow-activate-025',
  (select (result ->> 'workflowVersionId')::uuid
   from pg_temp.workflow_results where phase = 'create-first'),
  1,
  (select checksum from pg_temp.workflow_fixture),
  'Activate the approved synthetic workflow.',
  'm3-workflow-activate',
  '75600000-0000-4000-8000-000000000032'
);
insert into pg_temp.workflow_results (phase, result)
select 'read-admin', app.read_workflow_definition_admin(
  '10000000-0000-4000-8000-000000000001',
  (select (result ->> 'workflowDefinitionId')::uuid
   from pg_temp.workflow_results where phase = 'create-first')
);
select extensions.is(
  (select (result ->> 'replayed')::boolean from pg_temp.workflow_results
   where phase = 'activate-first'),
  false,
  'T-WF-004 activation returns an original result'
);
select extensions.is(
  (select (result ->> 'replayed')::boolean from pg_temp.workflow_results
   where phase = 'activate-replay'),
  true,
  'T-WF-004 identical activation replay is deterministic'
);
select extensions.is(
  (select result #>> '{definition,key}' from pg_temp.workflow_results
   where phase = 'read-admin'),
  'custom.deal.review',
  'T-WF-004 admin read returns the authorized dotted definition'
);
reset role;

select extensions.is(
  (
    select pg_catalog.concat_ws(
      ':', version.status, version.revision::text,
      (version.approval_record_id is not null)::text,
      (version.activated_at is not null)::text
    )
    from public.workflow_versions version
    where version.id = (
      select (result ->> 'workflowVersionId')::uuid
      from pg_temp.workflow_results where phase = 'create-first'
    )
  ),
  'active:1:true:true',
  'T-WF-004 activation persists one approved immutable active version'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.workflow_admin_command_receipts receipt
    where receipt.workflow_version_id = (
      select (result ->> 'workflowVersionId')::uuid
      from pg_temp.workflow_results where phase = 'create-first'
    )
  ),
  3,
  'T-WF-004 create, approve, and activate each store one receipt'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.audit_events audit
    where audit.entity_id = (
      select (result ->> 'workflowVersionId')::uuid
      from pg_temp.workflow_results where phase = 'create-first'
    )
      and audit.action in (
        'workflow.version_created',
        'workflow.version_approved',
        'workflow.version_activated'
      )
  ),
  3,
  'T-AUD-001 workflow administration records create, approve, and activate audits'
);
select extensions.throws_ok(
  $$
    update public.workflow_versions
    set checksum = repeat('9', 64)
    where id = (
      select (result ->> 'workflowVersionId')::uuid
      from pg_temp.workflow_results where phase = 'create-first'
    )
  $$,
  '55000',
  'approved or activated workflow configuration is immutable',
  'T-WF-004 activated workflow version metadata is immutable'
);

select * from extensions.finish();
rollback;
