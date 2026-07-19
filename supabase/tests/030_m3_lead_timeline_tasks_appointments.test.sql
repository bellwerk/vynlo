-- VYN-CRM-001, VYN-WF-001, VYN-DEAL-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001 / T-CRM-002, T-WF-001, T-TEN-001,
-- T-RBAC-001, T-AUD-001 / M3-CRM-AC-002 through M3-CRM-AC-004.
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(78);

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

create temporary table pg_temp.party_result (
  probe text primary key,
  party_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.lead_result (
  probe text primary key,
  lead_id uuid,
  aggregate_version bigint,
  state_key text,
  workflow_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.conversion_result (
  probe text primary key,
  lead_id uuid,
  deal_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.activity_result (
  probe text primary key,
  activity_id uuid,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.task_result (
  probe text primary key,
  task_id uuid,
  task_state text,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.appointment_result (
  probe text primary key,
  appointment_id uuid,
  appointment_status text,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.neutral_lead_fixture (
  probe text primary key,
  lead_id uuid not null,
  workflow_instance_id uuid not null
);
grant all on
  pg_temp.party_result, pg_temp.lead_result, pg_temp.conversion_result,
  pg_temp.activity_result, pg_temp.task_result, pg_temp.appointment_result,
  pg_temp.neutral_lead_fixture
to authenticated, service_role;

select extensions.ok(
  to_regclass('public.leads') is not null
    and to_regclass('public.crm_activities') is not null
    and to_regclass('public.crm_tasks') is not null
    and to_regclass('public.crm_appointments') is not null
    and to_regclass('public.crm_appointment_attendees') is not null
    and to_regclass('public.crm_command_receipts') is not null,
  'T-CRM-002 lead, timeline, task, appointment, attendee, and receipt tables exist'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'leads', 'crm_activities', 'crm_tasks', 'crm_appointments',
        'crm_appointment_attendees', 'crm_command_receipts'
      ])
      and relation.relrowsecurity and relation.relforcerowsecurity
  ),
  6,
  'T-TEN-001 all CRM runtime tables force RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.crm_command_receipts', 'SELECT'
  ),
  'T-RBAC-001 authenticated clients cannot read command receipts'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_indexes index_definition
    where index_definition.schemaname = 'public'
      and index_definition.tablename = 'deals'
      and index_definition.indexname = 'deals_originating_lead_uidx'
      and index_definition.indexdef like 'CREATE UNIQUE INDEX%'
  ),
  'T-CRM-002 one originating lead can own at most one deal'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_constraint constraint_definition
    where constraint_definition.conrelid = 'public.deals'::regclass
      and constraint_definition.conname = 'deals_originating_lead_fk'
      and pg_catalog.pg_get_constraintdef(constraint_definition.oid)
        like 'FOREIGN KEY (workspace_id, originating_lead_id)%'
  ),
  'T-TEN-001 converted deal provenance uses a composite workspace FK'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_definition
    where constraint_definition.conrelid = 'public.crm_command_receipts'::regclass
      and constraint_definition.contype = 'u'
      and pg_catalog.pg_get_constraintdef(constraint_definition.oid)
        = 'UNIQUE (workspace_id, actor_user_id, command_type, idempotency_key)'
  ),
  'T-CRM-002 command receipts scope idempotency to workspace and actor'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_definition
    where constraint_definition.conrelid
        = 'public.crm_command_receipts'::pg_catalog.regclass
      and constraint_definition.contype = 'f'
      and pg_catalog.pg_get_constraintdef(constraint_definition.oid)
        like 'FOREIGN KEY (workspace_id, audit_event_id)%'
  ),
  'T-TEN-001 CRM receipt audit evidence preserves workspace context'
);
select extensions.has_function(
  'app', 'm3_list_leads', array['uuid'],
  'exact list-leads RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_get_lead', array['uuid','uuid'],
  'exact get-lead RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_create_lead',
  array['uuid','text','text','text','uuid','uuid','uuid','timestamptz','text','uuid'],
  'exact create-lead RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_update_lead',
  array[
    'uuid','text','uuid','bigint','boolean','text','boolean','uuid',
    'boolean','uuid','boolean','timestamptz','text','uuid'
  ],
  'exact update-lead RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_transition_lead',
  array['uuid','text','uuid','bigint','text','text','text','uuid'],
  'exact transition-lead RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_convert_lead',
  array['uuid','text','uuid','bigint','text','text','uuid','uuid','uuid','text','uuid'],
  'exact convert-lead RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_create_activity',
  array[
    'uuid','text','text','text','text','text','text','timestamptz',
    'uuid','uuid','uuid','text','text','uuid'
  ],
  'exact create-activity RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_create_task',
  array[
    'uuid','text','uuid','uuid','uuid','uuid','text','text','text',
    'timestamptz','timestamptz','text','uuid'
  ],
  'exact create-task RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_complete_task',
  array['uuid','text','uuid','bigint','text','uuid'],
  'exact complete-task RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_cancel_task',
  array['uuid','text','uuid','bigint','text','text','uuid'],
  'required cancel-task lifecycle RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_list_tasks', array['uuid'],
  'exact list-tasks RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_list_crm_timeline', array['uuid','uuid','uuid','uuid'],
  'exact list-timeline RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_create_appointment',
  array[
    'uuid','text','uuid','uuid','text','timestamptz','timestamptz',
    'text','uuid','text','text','uuid[]','text','uuid'
  ],
  'expanded create-appointment RPC signature includes notes'
);
select extensions.has_function(
  'app', 'm3_transition_appointment',
  array['uuid','text','uuid','bigint','text','text','text','text','uuid'],
  'required appointment lifecycle RPC signature exists'
);
select extensions.has_function(
  'app', 'm3_list_appointments', array['uuid'],
  'exact list-appointments RPC signature exists'
);
select extensions.ok(
  (
    select procedure.proargnames[3:17]
    from pg_catalog.pg_proc procedure
    where procedure.oid = to_regprocedure('app.m3_get_lead(uuid,uuid)')
  ) = array[
    'lead_id','prospect_party_id','source_key','assignee_membership_id',
    'summary','next_action_at','state_key','version','created_at',
    'interested_inventory_unit_id','lost_reason','converted_deal_id',
    'workflow_instance_id','conversion_eligible','available_transitions'
  ]::text[],
  'get-lead result includes the exact bounded transition projection field'
);
select extensions.ok(
  (
    select procedure.proargnames[2:18]
    from pg_catalog.pg_proc procedure
    where procedure.oid = to_regprocedure('app.m3_list_tasks(uuid)')
  ) = array[
    'task_id','party_id','lead_id','deal_id','assignee_membership_id','title',
    'description','priority','due_at','reminder_at','state','completed_at',
    'completed_by','cancelled_at','cancellation_reason','version','created_at'
  ]::text[],
  'list-task return names exactly match the application adapter'
);
select extensions.ok(
  (
    select procedure.proargnames[2:18]
    from pg_catalog.pg_proc procedure
    where procedure.oid = to_regprocedure('app.m3_list_appointments(uuid)')
  ) = array[
    'appointment_id','lead_id','deal_id','title','starts_at','ends_at',
    'timezone','location_id','remote_details','notes','attendee_party_ids',
    'status','outcome','status_reason','resolved_at','version','created_at'
  ]::text[],
  'list-appointment return names exactly match the application adapter'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.party_result
select 'workspace-a-party', result.*
from app.m3_create_party(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-party-a', 'person', 'Synthetic CRM Prospect', 'en',
  'Synthetic', 'Prospect', null, null, null, null,
  'crm-030-party-a', '80000000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.lead_result
select 'qualified-path-first', result.*
from app.m3_create_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-lead-qualified', 'web.inquiry',
  'Synthetic qualified-path lead',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  null, '41000000-0000-4000-8000-000000000001',
  timestamptz '2026-08-01 15:00:00+00',
  'crm-030-lead-qualified', '80100000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.lead_result
select 'qualified-path-replay', result.*
from app.m3_create_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-lead-qualified', 'web.inquiry',
  'Synthetic qualified-path lead',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  null, '41000000-0000-4000-8000-000000000001',
  timestamptz '2026-08-01 15:00:00+00',
  'crm-030-lead-qualified', '80100000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.lead_result
select 'lost-path-first', result.*
from app.m3_create_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-lead-lost', 'phone.inbound', 'Synthetic lost-path lead',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  null, '41000000-0000-4000-8000-000000000001', null,
  'crm-030-lead-lost', '80200000-0000-4000-8000-000000000030'
) result;
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.activity_result
select 'activity-first', result.*
from app.m3_create_activity(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-activity', 'note', 'internal', 'Synthetic lead follow-up',
  'Synthetic timeline body', 'crm.manual',
  timestamptz '2026-07-20 14:00:00+00',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  null,
  'synthetic-provider-reference-030', 'crm-030-activity',
  '81100000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.activity_result
select 'activity-replay', result.*
from app.m3_create_activity(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-activity', 'note', 'internal', 'Synthetic lead follow-up',
  'Synthetic timeline body', 'crm.manual',
  timestamptz '2026-07-20 14:00:00+00',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  null,
  'synthetic-provider-reference-030', 'crm-030-activity',
  '81100000-0000-4000-8000-000000000030'
) result;

insert into pg_temp.task_result
select 'task-complete-open', result.*
from app.m3_create_task(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-task-complete',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  null,
  '41000000-0000-4000-8000-000000000001',
  'Complete synthetic follow-up', 'Call the synthetic prospect', 'high',
  timestamptz '2026-08-02 15:00:00+00',
  timestamptz '2026-08-02 14:00:00+00',
  'crm-030-task-complete', '81200000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.task_result
select 'task-completed', result.*
from app.m3_complete_task(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-task-complete-transition',
  (select task_id from pg_temp.task_result where probe = 'task-complete-open'),
  1, 'crm-030-task-complete-transition',
  '81300000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.task_result
select 'task-completed-replay', result.*
from app.m3_complete_task(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-task-complete-transition',
  (select task_id from pg_temp.task_result where probe = 'task-complete-open'),
  1, 'crm-030-task-complete-transition',
  '81300000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.task_result
select 'task-cancel-open', result.*
from app.m3_create_task(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-task-cancel', null,
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  null, '41000000-0000-4000-8000-000000000001',
  'Cancel synthetic follow-up', null, 'normal',
  timestamptz '2026-08-03 15:00:00+00', null,
  'crm-030-task-cancel', '81400000-0000-4000-8000-000000000030'
) result;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_cancel_task(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-task-cancel-no-reason', %L, 1, null,
        'crm-030-task-cancel-no-reason',
        '81500000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select task_id from pg_temp.task_result where probe = 'task-cancel-open')
  ),
  '22023',
  'invalid CRM task lifecycle command',
  'task cancellation requires a nonblank reason'
);
insert into pg_temp.task_result
select 'task-cancelled', result.*
from app.m3_cancel_task(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-task-cancel-transition',
  (select task_id from pg_temp.task_result where probe = 'task-cancel-open'),
  1, 'Synthetic task no longer required',
  'crm-030-task-cancel-transition',
  '81600000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.task_result
select 'task-stale-open', result.*
from app.m3_create_task(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-task-stale', null,
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  null, '41000000-0000-4000-8000-000000000001',
  'Stale synthetic task', null, 'low',
  timestamptz '2026-08-04 15:00:00+00', null,
  'crm-030-task-stale', '81700000-0000-4000-8000-000000000030'
) result;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_complete_task(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-task-stale-transition', %L, 2,
        'crm-030-task-stale-transition',
        '81800000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select task_id from pg_temp.task_result where probe = 'task-stale-open')
  ),
  '40001',
  'task version conflict',
  'stale task lifecycle transition fails optimistic concurrency'
);
reset role;

-- A draft, test-only workflow proves that state keys are tenant configuration,
-- while the allowlisted behavior flags carry platform lifecycle semantics.
insert into public.workflow_definitions (
  id, workspace_id, key, entity_type, purpose_key, status, created_by
) values (
  '03000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'lead_neutral_030', 'lead', 'primary', 'active',
  '31000000-0000-4000-8000-000000000001'
);
insert into public.workflow_versions (
  id, workspace_id, workflow_definition_id, revision, version,
  schema_version, initial_state_key, status, checksum, source, created_by
) values (
  '03010000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '03000000-0000-4000-8000-000000000001',
  1, '1.0.0', 1, 'incoming', 'draft',
  pg_catalog.repeat('0', 64), 'migration_compatibility',
  '31000000-0000-4000-8000-000000000001'
);
select extensions.throws_ok(
  $sql$
    insert into public.workflow_states (
      id, workspace_id, workflow_version_id, key, canonical_category,
      labels, behavior_flags, required_fields, sort_order
    ) values (
      '03020000-0000-4000-8000-000000000099',
      '10000000-0000-4000-8000-000000000001',
      '03010000-0000-4000-8000-000000000001',
      'invalid_target', 'active', '{"en":"Invalid target"}',
      '{"conversion_target":true}', '{}'::text[], 99
    )
  $sql$,
  '23514',
  'lead conversion and loss targets must be terminal workflow states',
  'lead semantic behavior flags reject a nonterminal conversion target'
);
insert into public.workflow_states (
  id, workspace_id, workflow_version_id, key, canonical_category,
  labels, behavior_flags, required_fields, sort_order
) values
  (
    '03020000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '03010000-0000-4000-8000-000000000001',
    'incoming', 'active', '{"en":"Incoming"}', '{"terminal":false}',
    '{}'::text[], 10
  ),
  (
    '03020000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '03010000-0000-4000-8000-000000000001',
    'warmed', 'active', '{"en":"Warmed"}',
    '{"terminal":false,"conversion_eligible":true}', '{}'::text[], 20
  ),
  (
    '03020000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '03010000-0000-4000-8000-000000000001',
    'won', 'closed', '{"en":"Won"}',
    '{"terminal":true,"conversion_target":true}', '{}'::text[], 30
  ),
  (
    '03020000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000001',
    '03010000-0000-4000-8000-000000000001',
    'declined', 'closed', '{"en":"Declined"}',
    '{"terminal":true,"loss_terminal":true}', '{}'::text[], 40
  );
insert into public.workflow_transitions (
  id, workspace_id, workflow_version_id, key, from_state_key, to_state_key,
  permission_key, guard_key, reason_required, required_fields, effect_keys
) values
  (
    '03030000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '03010000-0000-4000-8000-000000000001',
    'incoming__warmed', 'incoming', 'warmed', 'crm.update', null, false,
    array['lead_signal']::text[], '[]'::jsonb
  ),
  (
    '03030000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '03010000-0000-4000-8000-000000000001',
    'warmed__won', 'warmed', 'won', 'deals.create', null, false,
    '{}'::text[], '[]'::jsonb
  ),
  (
    '03030000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '03010000-0000-4000-8000-000000000001',
    'incoming__declined', 'incoming', 'declined', 'crm.update', null, false,
    '{}'::text[], '[]'::jsonb
  );
insert into pg_temp.neutral_lead_fixture values
  (
    'neutral-conversion',
    '03050000-0000-4000-8000-000000000001',
    '03040000-0000-4000-8000-000000000001'
  ),
  (
    'neutral-loss',
    '03050000-0000-4000-8000-000000000002',
    '03040000-0000-4000-8000-000000000002'
  ),
  (
    'neutral-masked',
    '03050000-0000-4000-8000-000000000004',
    '03040000-0000-4000-8000-000000000004'
  );
insert into public.workflow_instances (
  id, workspace_id, workflow_version_id, entity_type, entity_id,
  purpose_key, current_state_key, canonical_status, lifecycle_status, version
)
select
  fixture.workflow_instance_id,
  '10000000-0000-4000-8000-000000000001',
  '03010000-0000-4000-8000-000000000001',
  'lead', fixture.lead_id, 'primary', 'incoming', 'active', 'active', 1
from pg_temp.neutral_lead_fixture fixture;
insert into public.leads (
  id, workspace_id, source_key, summary, prospect_party_id,
  workflow_version_id, workflow_instance_id, state_key, version, created_by
)
select
  fixture.lead_id, '10000000-0000-4000-8000-000000000001',
  'test.neutral', 'Neutral state-key acceptance lead',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  '03010000-0000-4000-8000-000000000001',
  fixture.workflow_instance_id, 'incoming', 1,
  '31000000-0000-4000-8000-000000000001'
from pg_temp.neutral_lead_fixture fixture;

-- M3-FIELD-AC-009: configured lead workflow requirements consume an active
-- value only when the acting member is authorized to see that field.
insert into public.custom_field_definitions (
  id, workspace_id, entity_type, key, status, created_by
) values (
  '03060000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'lead', 'lead_signal', 'active',
  '31000000-0000-4000-8000-000000000001'
);
insert into public.custom_field_versions (
  id, workspace_id, custom_field_definition_id, version, value_type,
  labels, help_text, validation, default_value, options, required,
  visibility_permission_key, edit_permission_key, sensitive, searchable,
  section_key, status, checksum, created_by, activated_at
) values (
  '03061000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '03060000-0000-4000-8000-000000000001',
  1, 'short_text',
  '{"en":"Lead signal","fr":"Signal de prospect"}',
  '{"en":"Qualified signal","fr":"Signal qualifie"}',
  '{"maxLength":100}', null, '[]', false,
  'identifiers.read_restricted', 'crm.update', true, false,
  'lead.qualification', 'active', pg_catalog.repeat('6', 64),
  '31000000-0000-4000-8000-000000000001',
  timestamptz '2026-07-16 21:30:00+00'
);
insert into public.custom_field_values (
  id, workspace_id, custom_field_definition_id, custom_field_version_id,
  entity_type, entity_id, value_type, is_set, text_value, version,
  created_by, updated_by
) values
  (
    '03062000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '03060000-0000-4000-8000-000000000001',
    '03061000-0000-4000-8000-000000000001',
    'lead', '03050000-0000-4000-8000-000000000001',
    'short_text', true, 'qualified', 1,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '03062000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '03060000-0000-4000-8000-000000000001',
    '03061000-0000-4000-8000-000000000001',
    'lead', '03050000-0000-4000-8000-000000000004',
    'short_text', true, 'qualified', 1,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  );

insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  '51000000-0000-4000-8000-000000000030',
  '10000000-0000-4000-8000-000000000001',
  'fixture_lead_field_crm_030', 'Fixture lead field CRM operator',
  'system', 'active', false
);
insert into public.role_permissions (
  workspace_id, role_id, permission_id, status
)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000030',
  permission.id, 'active'
from public.permissions permission
where permission.workspace_id is null and permission.key = 'crm.update';
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '61000000-0000-4000-8000-000000000030',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '51000000-0000-4000-8000-000000000030', 'active'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.throws_ok(
  $sql$
    select * from app.m3_transition_lead(
      '10000000-0000-4000-8000-000000000001',
      'crm-030-neutral-masked',
      '03050000-0000-4000-8000-000000000004', 1,
      'incoming__warmed', null, 'crm-030-neutral-masked',
      '83100000-0000-4000-8000-000000000030'
    )
  $sql$,
  '23514',
  'lead transition required fields are incomplete',
  'a present but unauthorized custom field fails the workflow requirement without disclosure'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_transition_lead(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-neutral-loss-no-reason', %L, 1,
        'incoming__declined', null, 'crm-030-neutral-loss-no-reason',
        '83200000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.neutral_lead_fixture where probe = 'neutral-loss')
  ),
  '23514',
  'lead loss reason is required',
  'loss_terminal behavior requires reason even when transition reasonRequired is false'
);
insert into pg_temp.lead_result
select 'neutral-loss-transition', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-neutral-loss',
  (select lead_id from pg_temp.neutral_lead_fixture where probe = 'neutral-loss'),
  1, 'incoming__declined', 'Synthetic neutral-key loss',
  'crm-030-neutral-loss', '83300000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.lead_result
select 'neutral-conversion-ready', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-neutral-warmed',
  (select lead_id from pg_temp.neutral_lead_fixture where probe = 'neutral-conversion'),
  1, 'incoming__warmed', null, 'crm-030-neutral-warmed',
  '83400000-0000-4000-8000-000000000030'
) result;
select extensions.is(
  (select state_key from pg_temp.lead_result where probe = 'neutral-conversion-ready'),
  'warmed',
  'an authorized active custom-field value satisfies the configured lead workflow requirement'
);
select extensions.is(
  (
    select conversion_eligible
    from app.m3_get_lead(
      '10000000-0000-4000-8000-000000000001',
      (select lead_id from pg_temp.neutral_lead_fixture
        where probe = 'neutral-conversion')
    )
  ),
  true,
  'lead detail derives conversion eligibility from neutral state behavior flags'
);
select extensions.is(
  (
    select available_transitions
    from app.m3_get_lead(
      '10000000-0000-4000-8000-000000000001',
      (select lead_id from pg_temp.neutral_lead_fixture
        where probe = 'neutral-conversion')
    )
  ),
  '[]'::jsonb,
  'available ordinary transitions exclude configured conversion targets'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_transition_lead(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-neutral-direct-conversion', %L, 2,
        'warmed__won', null, 'crm-030-neutral-direct-conversion',
        '83500000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.neutral_lead_fixture
      where probe = 'neutral-conversion')
  ),
  '23514',
  'lead conversion requires the conversion command',
  'ordinary workflow transition cannot enter a conversion_target state'
);
insert into pg_temp.conversion_result
select 'neutral-conversion', result.*
from app.m3_convert_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-neutral-conversion',
  (select lead_id from pg_temp.neutral_lead_fixture where probe = 'neutral-conversion'),
  2, 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001', null,
  '41000000-0000-4000-8000-000000000001',
  'crm-030-neutral-conversion', '83600000-0000-4000-8000-000000000030'
) result;
reset role;

select extensions.ok(
  exists (
    select 1
    from public.leads lead
    join public.workflow_instances instance
      on instance.workspace_id = lead.workspace_id
     and instance.id = lead.workflow_instance_id
    where lead.id = (
      select lead_id from pg_temp.neutral_lead_fixture where probe = 'neutral-conversion'
    )
      and lead.state_key = 'won'
      and lead.converted_deal_id = (
        select deal_id from pg_temp.conversion_result where probe = 'neutral-conversion'
      )
      and instance.current_state_key = 'won'
      and instance.lifecycle_status = 'completed'
  ) and exists (
    select 1
    from public.leads lead
    join public.workflow_instances instance
      on instance.workspace_id = lead.workspace_id
     and instance.id = lead.workflow_instance_id
    where lead.id = (
      select lead_id from pg_temp.neutral_lead_fixture where probe = 'neutral-loss'
    )
      and lead.state_key = 'declined'
      and lead.lost_reason = 'Synthetic neutral-key loss'
      and instance.current_state_key = 'declined'
      and instance.lifecycle_status = 'completed'
  ),
  'neutral state keys persist conversion and loss provenance from behavior flags'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.deals deal
    where deal.originating_lead_id = (
      select lead_id from pg_temp.neutral_lead_fixture where probe = 'neutral-conversion'
    )
  ),
  1,
  'neutral conversion still creates exactly one configured deal'
);

insert into public.workflow_states (
  id, workspace_id, workflow_version_id, key, canonical_category,
  labels, behavior_flags, required_fields, sort_order
) values (
  '03020000-0000-4000-8000-000000000005',
  '10000000-0000-4000-8000-000000000001',
  '03010000-0000-4000-8000-000000000001',
  'won_backup', 'closed', '{"en":"Won backup"}',
  '{"terminal":true,"conversion_target":true}', '{}'::text[], 35
);
insert into public.workflow_transitions (
  id, workspace_id, workflow_version_id, key, from_state_key, to_state_key,
  permission_key, guard_key, reason_required, required_fields, effect_keys
) values (
  '03030000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000001',
  '03010000-0000-4000-8000-000000000001',
  'warmed__won_backup', 'warmed', 'won_backup', 'deals.create', null, false,
  '{}'::text[], '[]'::jsonb
);
insert into pg_temp.neutral_lead_fixture values (
  'neutral-ambiguous',
  '03050000-0000-4000-8000-000000000003',
  '03040000-0000-4000-8000-000000000003'
);
insert into public.workflow_instances (
  id, workspace_id, workflow_version_id, entity_type, entity_id,
  purpose_key, current_state_key, canonical_status, lifecycle_status, version
) values (
  '03040000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  '03010000-0000-4000-8000-000000000001',
  'lead', '03050000-0000-4000-8000-000000000003',
  'primary', 'warmed', 'active', 'active', 1
);
insert into public.leads (
  id, workspace_id, source_key, summary, prospect_party_id,
  workflow_version_id, workflow_instance_id, state_key, version, created_by
) values (
  '03050000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  'test.ambiguous', 'Ambiguous conversion-target acceptance lead',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  '03010000-0000-4000-8000-000000000001',
  '03040000-0000-4000-8000-000000000003',
  'warmed', 1, '31000000-0000-4000-8000-000000000001'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $sql$
    select * from app.m3_convert_lead(
      '10000000-0000-4000-8000-000000000001',
      'crm-030-ambiguous-conversion',
      '03050000-0000-4000-8000-000000000003', 1,
      'retail.cash', 'CAD',
      '73000000-0000-4000-8000-000000000001', null,
      '41000000-0000-4000-8000-000000000001',
      'crm-030-ambiguous-conversion',
      '83700000-0000-4000-8000-000000000030'
    )
  $sql$,
  '23514',
  'exactly one configured lead conversion transition is required',
  'conversion fails closed when configuration exposes two conversion targets'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
insert into pg_temp.activity_result
select 'actor-b-same-key', result.*
from app.m3_create_activity(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-activity', 'note', 'internal', 'Second actor follow-up',
  null, null, timestamptz '2026-07-20 15:00:00+00',
  (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
  null, null, null, 'crm-030-activity-actor-b',
  '81900000-0000-4000-8000-000000000030'
) result;
reset role;

select extensions.ok(
  (select replayed from pg_temp.activity_result where probe = 'activity-replay')
    and (
      select activity_id from pg_temp.activity_result where probe = 'activity-first'
    ) = (
      select activity_id from pg_temp.activity_result where probe = 'activity-replay'
    ),
  'append-only activity idempotency replay returns the original row'
);
select extensions.ok(
  not (select replayed from pg_temp.activity_result where probe = 'actor-b-same-key')
    and (
      select activity_id from pg_temp.activity_result where probe = 'activity-first'
    ) <> (
      select activity_id from pg_temp.activity_result where probe = 'actor-b-same-key'
    )
    and (
      select pg_catalog.count(*)
      from public.crm_command_receipts receipt
      where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
        and receipt.command_type = 'm3_create_activity'
        and receipt.idempotency_key = 'crm-030-activity'
    ) = 2,
  'actor-scoped receipts let two authorized actors reuse the same raw key safely'
);
select extensions.ok(
  exists (
    select 1 from public.crm_tasks task
    where task.id = (
      select task_id from pg_temp.task_result where probe = 'task-completed'
    )
      and task.state = 'completed' and task.version = 2
      and task.completed_at is not null
      and task.completed_by = '31000000-0000-4000-8000-000000000001'
  ) and exists (
    select 1 from public.crm_tasks task
    where task.id = (
      select task_id from pg_temp.task_result where probe = 'task-cancelled'
    )
      and task.state = 'cancelled' and task.version = 2
      and task.cancelled_at is not null
      and task.cancelled_by = '31000000-0000-4000-8000-000000000001'
      and task.cancellation_reason = 'Synthetic task no longer required'
  ) and (
    select replayed from pg_temp.task_result where probe = 'task-completed-replay'
  ) and (
    select task_id from pg_temp.task_result where probe = 'task-completed-replay'
  ) = (
    select task_id from pg_temp.task_result where probe = 'task-completed'
  ),
  'task completion and cancellation persist exact terminal metadata'
);
select extensions.throws_ok(
  pg_catalog.format(
    'update public.crm_activities set subject = %L where id = %L',
    'Forbidden activity edit',
    (select activity_id from pg_temp.activity_result where probe = 'activity-first')
  ),
  '55000',
  'CRM history is append-only',
  'timeline activities reject mutation'
);
select extensions.throws_ok(
  pg_catalog.format(
    'update public.crm_tasks set title = %L where id = %L',
    'Forbidden task edit',
    (select task_id from pg_temp.task_result where probe = 'task-completed')
  ),
  '55000',
  'terminal tasks are immutable',
  'terminal task records reject mutation'
);

select extensions.is(
  (select replayed from pg_temp.lead_result where probe = 'qualified-path-first'),
  false,
  'lead create original is not a replay'
);
select extensions.is(
  (select replayed from pg_temp.lead_result where probe = 'qualified-path-replay'),
  true,
  'same actor/idempotency lead create replay is stable'
);
select extensions.ok(
  exists (
    select 1
    from public.leads lead
    join public.workflow_instances instance
      on instance.workspace_id = lead.workspace_id
     and instance.id = lead.workflow_instance_id
    where lead.id = (
      select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'
    )
      and lead.workflow_version_id = instance.workflow_version_id
      and lead.state_key = 'new'
      and instance.current_state_key = 'new'
      and lead.version = 1 and instance.version = 1
  ),
  'lead creation pins and synchronizes the active workflow version'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_create_lead(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-lead-qualified', 'web.inquiry', 'Different summary', %L,
        null, '41000000-0000-4000-8000-000000000001', null,
        'crm-030-lead-qualified',
        '80100000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select party_id from pg_temp.party_result where probe = 'workspace-a-party')
  ),
  '23505',
  'CRM idempotency key was reused with different input',
  'lead idempotency key mismatch fails closed'
);
select extensions.ok(
  (
    select available_transitions @> '[{
      "transitionKey":"new__contacted",
      "toStateKey":"contacted",
      "reasonRequired":false
    }]'::jsonb
      and pg_catalog.jsonb_array_length(available_transitions) <= 100
    from app.m3_get_lead(
      '10000000-0000-4000-8000-000000000001',
      (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first')
    )
  ),
  'get-lead returns bounded permission-filtered configured transitions'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_update_lead(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-lead-stale', %L, 99,
        true, 'Stale update', false, null, false, null, false, null,
        'crm-030-lead-stale',
        '80300000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first')
  ),
  '40001',
  'lead version conflict',
  'stale lead updates fail optimistic concurrency'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_transition_lead(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-lost-no-reason', %L, 1, 'new__lost', null,
        'crm-030-lost-no-reason',
        '80400000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.lead_result where probe = 'lost-path-first')
  ),
  '23514',
  'lead transition reason is required',
  'configured loss transition requires a reason'
);
insert into pg_temp.lead_result
select 'lost-path-transition', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-lost-with-reason',
  (select lead_id from pg_temp.lead_result where probe = 'lost-path-first'),
  1, 'new__lost', 'Synthetic prospect declined',
  'crm-030-lost-with-reason',
  '80500000-0000-4000-8000-000000000030'
) result;
reset role;

select extensions.ok(
  exists (
    select 1 from public.leads lead
    join public.workflow_instances instance
      on instance.workspace_id = lead.workspace_id
     and instance.id = lead.workflow_instance_id
    where lead.id = (
      select lead_id from pg_temp.lead_result where probe = 'lost-path-first'
    )
      and lead.state_key = 'lost'
      and lead.lost_reason = 'Synthetic prospect declined'
      and lead.version = 2
      and instance.lifecycle_status = 'completed'
  ),
  'loss reason and terminal workflow lifecycle are persisted'
);
select extensions.throws_ok(
  pg_catalog.format(
    'update public.leads set summary = %L, version = 3 where id = %L',
    'Forbidden terminal edit',
    (select lead_id from pg_temp.lead_result where probe = 'lost-path-first')
  ),
  '55000',
  'terminal leads are immutable',
  'terminal lead records reject direct mutation'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_convert_lead(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-convert-too-early', %L, 1, 'retail.cash', 'CAD',
        '73000000-0000-4000-8000-000000000001', null,
        '41000000-0000-4000-8000-000000000001',
        'crm-030-convert-too-early',
        '80600000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first')
  ),
  '23514',
  'conversion-eligible lead with an active prospect party is required',
  'workflow guard rejects conversion before qualification'
);
insert into pg_temp.lead_result
select 'qualified-path-contacted', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-lead-contacted',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  1, 'new__contacted', null, 'crm-030-lead-contacted',
  '80700000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.lead_result
select 'qualified-path-qualified', result.*
from app.m3_transition_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-lead-qualified-transition',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  2, 'contacted__qualified', null, 'crm-030-lead-qualified-transition',
  '80800000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.conversion_result
select 'conversion-first', result.*
from app.m3_convert_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-conversion-first',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  3, 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001', null,
  '41000000-0000-4000-8000-000000000001',
  'crm-030-conversion-first',
  '80900000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.conversion_result
select 'conversion-replay', result.*
from app.m3_convert_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-conversion-first',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  3, 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001', null,
  '41000000-0000-4000-8000-000000000001',
  'crm-030-conversion-first',
  '80900000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.conversion_result
select 'conversion-alternate-key', result.*
from app.m3_convert_lead(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-conversion-alternate',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  3, 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001', null,
  '41000000-0000-4000-8000-000000000001',
  'crm-030-conversion-alternate',
  '81000000-0000-4000-8000-000000000030'
) result;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_convert_lead(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-conversion-first', %L, 3, 'retail.cash', 'USD',
        '73000000-0000-4000-8000-000000000001', null,
        '41000000-0000-4000-8000-000000000001',
        'crm-030-conversion-first',
        '80900000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first')
  ),
  '23505',
  'CRM idempotency key was reused with different input',
  'conversion idempotency mismatch fails closed'
);
reset role;

select extensions.ok(
  (select not replayed from pg_temp.conversion_result where probe = 'conversion-first')
    and (select replayed from pg_temp.conversion_result where probe = 'conversion-replay')
    and (select replayed from pg_temp.conversion_result
      where probe = 'conversion-alternate-key'),
  'conversion is original once and semantically replayed for retry keys'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.deals deal
    where deal.workspace_id = '10000000-0000-4000-8000-000000000001'
      and deal.originating_lead_id = (
        select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'
      )
  ),
  1,
  'row lock plus unique provenance produces exactly one configured deal'
);
select extensions.ok(
  exists (
    select 1
    from public.deals deal
    join public.deal_type_versions type_version
      on type_version.workspace_id = deal.workspace_id
     and type_version.id = deal.deal_type_version_id
    join public.deal_participants participant
      on participant.workspace_id = deal.workspace_id
     and participant.deal_id = deal.id
    where deal.id = (
      select deal_id from pg_temp.conversion_result where probe = 'conversion-first'
    )
      and type_version.status = 'active'
      and participant.party_id = (
        select party_id from pg_temp.party_result where probe = 'workspace-a-party'
      )
      and participant.role_key = 'buyer'
      and participant.is_primary
  ),
  'conversion pins active deal configuration and preserves the lead party as buyer'
);
select extensions.ok(
  exists (
    select 1
    from public.leads lead
    join public.workflow_instances instance
      on instance.workspace_id = lead.workspace_id
     and instance.id = lead.workflow_instance_id
    where lead.id = (
      select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'
    )
      and lead.state_key = 'converted'
      and lead.converted_deal_id = (
        select deal_id from pg_temp.conversion_result where probe = 'conversion-first'
      )
      and lead.version = 4
      and instance.current_state_key = 'converted'
      and instance.lifecycle_status = 'completed'
  ),
  'lead and pinned workflow transition atomically to converted'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select available_transitions
    from app.m3_get_lead(
      '10000000-0000-4000-8000-000000000001',
      (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first')
    )
  ),
  '[]'::jsonb,
  'terminal converted lead exposes no available transitions'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from app.m3_list_crm_timeline(
      '10000000-0000-4000-8000-000000000001',
      (select party_id from pg_temp.party_result where probe = 'workspace-a-party'),
      (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
      null
    )
  ),
  1,
  'lead conversion preserves the append-only party and lead timeline'
);
select extensions.ok(
  exists (
    select 1 from app.m3_list_tasks('10000000-0000-4000-8000-000000000001') task
    where task.task_id = (
      select task_id from pg_temp.task_result where probe = 'task-completed'
    ) and task.state = 'completed' and task.version = 2
  ),
  'list-tasks projects completed lifecycle evidence through the application contract'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_create_appointment(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-appointment-bad-zone', %L, %L,
        'Invalid timezone appointment',
        timestamptz '2026-08-10 14:00:00+00',
        timestamptz '2026-08-10 15:00:00+00',
        'Mars/Olympus', null, 'Synthetic remote details', null,
        array[%L]::uuid[], 'crm-030-appointment-bad-zone',
        '82000000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
    (select deal_id from pg_temp.conversion_result where probe = 'conversion-first'),
    (select party_id from pg_temp.party_result where probe = 'workspace-a-party')
  ),
  '22023',
  'invalid CRM appointment command',
  'appointment creation rejects an unknown IANA timezone'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_create_appointment(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-appointment-bad-range', %L, %L,
        'Invalid interval appointment',
        timestamptz '2026-08-10 15:00:00+00',
        timestamptz '2026-08-10 14:00:00+00',
        'America/Toronto', null, null, null, '{}'::uuid[],
        'crm-030-appointment-bad-range',
        '82100000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
    (select deal_id from pg_temp.conversion_result where probe = 'conversion-first')
  ),
  '22023',
  'invalid CRM appointment command',
  'appointment creation rejects a nonpositive time interval'
);
insert into pg_temp.appointment_result
select 'appointment-complete-open', result.*
from app.m3_create_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-complete',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  (select deal_id from pg_temp.conversion_result where probe = 'conversion-first'),
  'Synthetic delivery appointment',
  timestamptz '2026-08-10 14:00:00+00',
  timestamptz '2026-08-10 15:30:00+00',
  'America/Toronto', '73000000-0000-4000-8000-000000000001',
  'Synthetic video fallback', 'Bring synthetic acceptance paperwork',
  array[(select party_id from pg_temp.party_result
    where probe = 'workspace-a-party')]::uuid[],
  'crm-030-appointment-complete',
  '82200000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.appointment_result
select 'appointment-complete-replay', result.*
from app.m3_create_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-complete',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  (select deal_id from pg_temp.conversion_result where probe = 'conversion-first'),
  'Synthetic delivery appointment',
  timestamptz '2026-08-10 14:00:00+00',
  timestamptz '2026-08-10 15:30:00+00',
  'America/Toronto', '73000000-0000-4000-8000-000000000001',
  'Synthetic video fallback', 'Bring synthetic acceptance paperwork',
  array[(select party_id from pg_temp.party_result
    where probe = 'workspace-a-party')]::uuid[],
  'crm-030-appointment-complete',
  '82200000-0000-4000-8000-000000000030'
) result;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_create_appointment(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-appointment-complete', %L, %L,
        'Changed appointment title',
        timestamptz '2026-08-10 14:00:00+00',
        timestamptz '2026-08-10 15:30:00+00',
        'America/Toronto',
        '73000000-0000-4000-8000-000000000001',
        'Synthetic video fallback', 'Bring synthetic acceptance paperwork',
        array[%L]::uuid[], 'crm-030-appointment-complete',
        '82200000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
    (select deal_id from pg_temp.conversion_result where probe = 'conversion-first'),
    (select party_id from pg_temp.party_result where probe = 'workspace-a-party')
  ),
  '23505',
  'CRM idempotency key was reused with different input',
  'appointment create idempotency mismatch fails closed'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_transition_appointment(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-appointment-complete-no-outcome', %L, 1,
        'completed', null, null,
        'crm-030-appointment-complete-no-outcome',
        '82300000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select appointment_id from pg_temp.appointment_result
      where probe = 'appointment-complete-open')
  ),
  '22023',
  'invalid appointment lifecycle command',
  'completed appointment requires an outcome'
);
insert into pg_temp.appointment_result
select 'appointment-completed', result.*
from app.m3_transition_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-complete-transition',
  (select appointment_id from pg_temp.appointment_result
    where probe = 'appointment-complete-open'),
  1, 'completed', 'Synthetic delivery confirmed', null,
  'crm-030-appointment-complete-transition',
  '82400000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.appointment_result
select 'appointment-completed-replay', result.*
from app.m3_transition_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-complete-transition',
  (select appointment_id from pg_temp.appointment_result
    where probe = 'appointment-complete-open'),
  1, 'completed', 'Synthetic delivery confirmed', null,
  'crm-030-appointment-complete-transition',
  '82400000-0000-4000-8000-000000000030'
) result;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_transition_appointment(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-appointment-complete-transition', %L, 1,
        'completed', 'Changed synthetic outcome', null,
        'crm-030-appointment-complete-transition',
        '82400000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select appointment_id from pg_temp.appointment_result
      where probe = 'appointment-complete-open')
  ),
  '23505',
  'CRM idempotency key was reused with different input',
  'appointment lifecycle idempotency mismatch fails before terminal lookup'
);
insert into pg_temp.appointment_result
select 'appointment-cancel-open', result.*
from app.m3_create_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-cancel',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  null, 'Synthetic remote follow-up',
  timestamptz '2026-08-11 16:00:00+00',
  timestamptz '2026-08-11 16:30:00+00',
  'America/Toronto', null, 'Synthetic remote room',
  'Synthetic cancellation candidate', '{}'::uuid[],
  'crm-030-appointment-cancel',
  '82500000-0000-4000-8000-000000000030'
) result;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_transition_appointment(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-appointment-cancel-no-reason', %L, 1,
        'cancelled', null, null,
        'crm-030-appointment-cancel-no-reason',
        '82600000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select appointment_id from pg_temp.appointment_result
      where probe = 'appointment-cancel-open')
  ),
  '22023',
  'invalid appointment lifecycle command',
  'cancelled appointment requires a reason'
);
insert into pg_temp.appointment_result
select 'appointment-cancelled', result.*
from app.m3_transition_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-cancel-transition',
  (select appointment_id from pg_temp.appointment_result
    where probe = 'appointment-cancel-open'),
  1, 'cancelled', null, 'Synthetic schedule conflict',
  'crm-030-appointment-cancel-transition',
  '82700000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.appointment_result
select 'appointment-no-show-open', result.*
from app.m3_create_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-no-show', null,
  (select deal_id from pg_temp.conversion_result where probe = 'conversion-first'),
  'Synthetic no-show candidate',
  timestamptz '2026-08-12 16:00:00+00',
  timestamptz '2026-08-12 17:00:00+00',
  'America/Toronto', '73000000-0000-4000-8000-000000000001',
  null, 'Synthetic no-show notes',
  array[(select party_id from pg_temp.party_result
    where probe = 'workspace-a-party')]::uuid[],
  'crm-030-appointment-no-show',
  '82800000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.appointment_result
select 'appointment-no-show', result.*
from app.m3_transition_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-no-show-transition',
  (select appointment_id from pg_temp.appointment_result
    where probe = 'appointment-no-show-open'),
  1, 'no_show', null, 'Synthetic attendee absent',
  'crm-030-appointment-no-show-transition',
  '82900000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.appointment_result
select 'appointment-stale-open', result.*
from app.m3_create_appointment(
  '10000000-0000-4000-8000-000000000001',
  'crm-030-appointment-stale',
  (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
  null, 'Synthetic stale candidate',
  timestamptz '2026-08-13 16:00:00+00',
  timestamptz '2026-08-13 17:00:00+00',
  'America/Toronto', null, null, null, '{}'::uuid[],
  'crm-030-appointment-stale',
  '83000000-0000-4000-8000-000000000030'
) result;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_transition_appointment(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-appointment-stale-transition', %L, 2,
        'completed', 'Synthetic stale outcome', null,
        'crm-030-appointment-stale-transition',
        '83100000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select appointment_id from pg_temp.appointment_result
      where probe = 'appointment-stale-open')
  ),
  '40001',
  'appointment version conflict',
  'stale appointment lifecycle transition fails optimistic concurrency'
);
select extensions.ok(
  (
    select replayed from pg_temp.appointment_result
    where probe = 'appointment-complete-replay'
  ) and (
    select replayed from pg_temp.appointment_result
    where probe = 'appointment-completed-replay'
  ) and (
    select appointment_id from pg_temp.appointment_result
    where probe = 'appointment-completed-replay'
  ) = (
    select appointment_id from pg_temp.appointment_result
    where probe = 'appointment-completed'
  ),
  'appointment creation and terminal lifecycle retries replay stable evidence'
);
select extensions.ok(
  exists (
    select 1
    from app.m3_list_appointments('10000000-0000-4000-8000-000000000001') appointment
    where appointment.appointment_id = (
      select appointment_id from pg_temp.appointment_result
      where probe = 'appointment-completed'
    )
      and appointment.lead_id = (
        select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'
      )
      and appointment.deal_id = (
        select deal_id from pg_temp.conversion_result where probe = 'conversion-first'
      )
      and appointment.starts_at = timestamptz '2026-08-10 14:00:00+00'
      and appointment.ends_at = timestamptz '2026-08-10 15:30:00+00'
      and appointment.timezone = 'America/Toronto'
      and appointment.location_id = '73000000-0000-4000-8000-000000000001'
      and appointment.remote_details = 'Synthetic video fallback'
      and appointment.notes = 'Bring synthetic acceptance paperwork'
      and appointment.attendee_party_ids = array[
        (select party_id from pg_temp.party_result where probe = 'workspace-a-party')
      ]::uuid[]
      and appointment.status = 'completed'
      and appointment.outcome = 'Synthetic delivery confirmed'
      and appointment.status_reason is null
      and appointment.resolved_at is not null
      and appointment.version = 2
  ),
  'list-appointments preserves interval, timezone, location, remote, notes, attendees, and outcome'
);
reset role;

select extensions.ok(
  exists (
    select 1 from public.crm_appointments appointment
    where appointment.id = (
      select appointment_id from pg_temp.appointment_result
      where probe = 'appointment-cancelled'
    )
      and appointment.status = 'cancelled'
      and appointment.status_reason = 'Synthetic schedule conflict'
      and appointment.outcome is null
      and appointment.resolved_at is not null
      and appointment.resolved_by = '31000000-0000-4000-8000-000000000001'
      and appointment.version = 2
  ) and exists (
    select 1 from public.crm_appointments appointment
    where appointment.id = (
      select appointment_id from pg_temp.appointment_result
      where probe = 'appointment-no-show'
    )
      and appointment.status = 'no_show'
      and appointment.status_reason = 'Synthetic attendee absent'
      and appointment.outcome is null
      and appointment.resolved_at is not null
      and appointment.resolved_by = '31000000-0000-4000-8000-000000000001'
      and appointment.version = 2
  ),
  'cancelled and no-show appointments preserve exact terminal reason metadata'
);
select extensions.throws_ok(
  pg_catalog.format(
    'update public.crm_appointments set notes = %L where id = %L',
    'Forbidden terminal appointment edit',
    (select appointment_id from pg_temp.appointment_result
      where probe = 'appointment-completed')
  ),
  '55000',
  'resolved appointments are immutable',
  'terminal appointment records reject direct mutation'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.party_result
select 'workspace-b-party', result.*
from app.m3_create_party(
  '20000000-0000-4000-8000-000000000002',
  'crm-030-party-b', 'person', 'Synthetic Harbour Prospect', 'fr',
  'Harbour', 'Prospect', null, null, null, null,
  'crm-030-party-b', '83800000-0000-4000-8000-000000000030'
) result;
insert into pg_temp.lead_result
select 'workspace-b-lead', result.*
from app.m3_create_lead(
  '20000000-0000-4000-8000-000000000002',
  'crm-030-lead-b', 'web.inquiry', 'Synthetic workspace B lead',
  (select party_id from pg_temp.party_result where probe = 'workspace-b-party'),
  null, '42000000-0000-4000-8000-000000000001', null,
  'crm-030-lead-b', '83900000-0000-4000-8000-000000000030'
) result;
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.leads lead
    where lead.workspace_id = '10000000-0000-4000-8000-000000000001'
  ),
  0,
  'workspace B actor cannot read workspace A leads through forced RLS'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.leads lead
    where lead.workspace_id = '20000000-0000-4000-8000-000000000002'
  ),
  0,
  'workspace A actor cannot read workspace B leads through forced RLS'
);
select extensions.throws_ok(
  pg_catalog.format(
    'select * from app.m3_get_lead(%L, %L)',
    '20000000-0000-4000-8000-000000000002',
    (select lead_id from pg_temp.lead_result where probe = 'workspace-b-lead')
  ),
  '42501',
  'active workspace membership and permission are required',
  'cross-workspace get-lead fails before data lookup'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_create_activity(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-cross-activity', 'note', 'internal',
        'Forbidden cross-workspace activity', null, null,
        timestamptz '2026-08-14 14:00:00+00', %L, %L, null, null,
        'crm-030-cross-activity',
        '84000000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select party_id from pg_temp.party_result where probe = 'workspace-b-party'),
    (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first')
  ),
  '23514',
  'active workspace party is required',
  'activity command rejects a party from another workspace'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_create_appointment(
        '10000000-0000-4000-8000-000000000001',
        'crm-030-cross-attendee', %L, null,
        'Forbidden cross-workspace attendee',
        timestamptz '2026-08-14 14:00:00+00',
        timestamptz '2026-08-14 15:00:00+00',
        'America/Toronto', null, null, null, array[%L]::uuid[],
        'crm-030-cross-attendee',
        '84100000-0000-4000-8000-000000000030'
      )
    $sql$,
    (select lead_id from pg_temp.lead_result where probe = 'qualified-path-first'),
    (select party_id from pg_temp.party_result where probe = 'workspace-b-party')
  ),
  '23514',
  'all appointment attendees must be active workspace parties',
  'appointment command rejects an attendee from another workspace'
);
reset role;

with write_evidence(
  entity_type, entity_id, aggregate_version,
  audit_event_id, outbox_event_id, replayed
) as (
  select 'lead', lead_id, aggregate_version,
    audit_event_id, outbox_event_id, replayed
  from pg_temp.lead_result
  union all
  select 'lead', lead_id, aggregate_version,
    audit_event_id, outbox_event_id, replayed
  from pg_temp.conversion_result
  union all
  select 'crm_activity', activity_id, aggregate_version,
    audit_event_id, outbox_event_id, replayed
  from pg_temp.activity_result
  union all
  select 'crm_task', task_id, aggregate_version,
    audit_event_id, outbox_event_id, replayed
  from pg_temp.task_result
  union all
  select 'crm_appointment', appointment_id, aggregate_version,
    audit_event_id, outbox_event_id, replayed
  from pg_temp.appointment_result
)
select extensions.ok(
  not exists (
    select 1
    from write_evidence evidence
    where not evidence.replayed
      and (
        not exists (
          select 1 from public.audit_events audit
          where audit.id = evidence.audit_event_id
            and audit.entity_type = evidence.entity_type
            and audit.entity_id = evidence.entity_id
        )
        or not exists (
          select 1 from public.outbox_events event
          where event.id = evidence.outbox_event_id
            and event.aggregate_type = evidence.entity_type
            and event.aggregate_id = evidence.entity_id
            and event.aggregate_version = evidence.aggregate_version
        )
        or not exists (
          select 1 from public.crm_command_receipts receipt
          where receipt.audit_event_id = evidence.audit_event_id
            and receipt.outbox_event_id = evidence.outbox_event_id
            and receipt.entity_type = evidence.entity_type
            and receipt.entity_id = evidence.entity_id
        )
      )
  ),
  'every successful CRM command returns linked receipt, audit, and outbox evidence'
);
select extensions.ok(
  exists (
    select 1
    from public.audit_events audit
    join pg_temp.task_result result
      on result.probe = 'task-cancelled'
     and audit.id = result.audit_event_id
    where audit.action = 'crm_task.cancelled'
      and audit.reason = 'Synthetic task no longer required'
  ) and exists (
    select 1
    from public.outbox_events event
    join pg_temp.appointment_result result
      on result.probe = 'appointment-no-show'
     and event.id = result.outbox_event_id
    where event.event_name = 'crm_appointment.no_show'
      and event.aggregate_version = 2
      and event.payload ->> 'status' = 'no_show'
  ) and exists (
    select 1
    from public.audit_events audit
    join pg_temp.conversion_result result
      on result.probe = 'conversion-first'
     and audit.id = result.audit_event_id
    where audit.action = 'lead.converted'
      and audit.after_data ->> 'converted_deal_id' = result.deal_id::text
  ),
  'task cancellation, appointment no-show, and conversion carry exact audit/outbox provenance'
);

select * from extensions.finish();
rollback;
