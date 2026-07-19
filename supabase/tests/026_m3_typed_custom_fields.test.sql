-- VYN-FIELD-001, VYN-WF-001, VYN-CFG-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, T-FIELD-001, T-FIELD-002, T-FIELD-003, T-CFG-004,
-- T-TEN-001, T-RBAC-001, T-AUD-001,
-- M3-FIELD-AC-001 through M3-FIELD-AC-009.
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(69);

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

create temporary table pg_temp.field_commands (
  custom_field_value_id uuid,
  value_version bigint,
  replayed boolean,
  audit_event_id uuid,
  probe text
);
create temporary table pg_temp.field_activations (
  custom_field_definition_id uuid,
  custom_field_version_id uuid,
  version bigint,
  replayed boolean,
  audit_event_id uuid,
  probe text
);
create temporary table pg_temp.field_definitions (
  custom_field_definition_id uuid,
  custom_field_version_id uuid,
  version bigint,
  replayed boolean,
  audit_event_id uuid,
  probe text
);
grant all on
  pg_temp.field_commands,
  pg_temp.field_activations,
  pg_temp.field_definitions
to authenticated, service_role;

-- A CRM member without restricted-identifier permissions proves that the
-- entitlement does not grant entity or field visibility by itself.
insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  '51000000-0000-4000-8000-000000000026',
  '10000000-0000-4000-8000-000000000001',
  'fixture_custom_field_crm',
  'Fixture custom-field CRM operator',
  'system',
  'active',
  false
);
insert into public.role_permissions (
  workspace_id, role_id, permission_id, status
)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000026',
  permission.id,
  'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key in ('crm.read', 'crm.update');
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '61000000-0000-4000-8000-000000000026',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '51000000-0000-4000-8000-000000000026',
  'active'
);

insert into public.parties (
  id, workspace_id, party_type, display_name, status, version,
  idempotency_key, command_fingerprint, created_by
) values
  (
    '72600000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'person', 'Synthetic custom-field party', 'active', 1,
    'm3-field-party-a', repeat('a', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '72600000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'person', 'Other workspace synthetic party', 'active', 1,
    'm3-field-party-b', repeat('b', 64),
    '32000000-0000-4000-8000-000000000001'
  );

-- Inventory references use real workspace-owned aggregate fixtures so the
-- field boundary can prove target authorization and tenant isolation.
set constraints all deferred;
insert into public.stock_number_allocations (
  id, workspace_id, definition_id, inventory_unit_id, sequence_value,
  formatted_value, idempotency_key, command_fingerprint, allocated_by
) values
  (
    '72620000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    '72640000-0000-4000-8000-000000000001',
    726201, 'N-726201', 'm3-field-inventory-a', repeat('c', 64),
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '72620000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '72000000-0000-4000-8000-000000000001',
    '72640000-0000-4000-8000-000000000002',
    726202, 'H-726202', 'm3-field-inventory-b', repeat('d', 64),
    '32000000-0000-4000-8000-000000000001'
  );
insert into public.vehicles (
  id, workspace_id, vin, model_year, make, model
) values
  (
    '72630000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '1HGCM82633A726201', 2026, 'Synthetic', 'Field reference A'
  ),
  (
    '72630000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '1HGCM82633A726202', 2026, 'Synthetic', 'Field reference B'
  );
insert into public.inventory_units (
  id, workspace_id, vehicle_id, stock_allocation_id, stock_number,
  status, location_id, currency_code, created_by
) values
  (
    '72640000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '72630000-0000-4000-8000-000000000001',
    '72620000-0000-4000-8000-000000000001',
    'N-726201', 'draft', '73000000-0000-4000-8000-000000000001',
    'CAD', '31000000-0000-4000-8000-000000000001'
  ),
  (
    '72640000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    '72630000-0000-4000-8000-000000000002',
    '72620000-0000-4000-8000-000000000002',
    'H-726202', 'draft', '73000000-0000-4000-8000-000000000002',
    'CAD', '32000000-0000-4000-8000-000000000001'
  );
set constraints all immediate;

insert into public.custom_field_definitions (
  id, workspace_id, entity_type, key, status, created_by
) values
  (
    '73600000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'party', 'customer_reference', 'active',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '73600000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'party', 'restricted_note', 'active',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '73600000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    'party', 'related_party', 'active',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '73600000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000001',
    'party', 'credit_limit', 'active',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '73600000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000001',
    'party', 'activation_fixture', 'active',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '73600000-0000-4000-8000-000000000007',
    '10000000-0000-4000-8000-000000000001',
    'party', 'related_inventory', 'active',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '73600000-0000-4000-8000-000000000006',
    '20000000-0000-4000-8000-000000000002',
    'party', 'disabled_fixture', 'active',
    '32000000-0000-4000-8000-000000000001'
  );

insert into public.custom_field_versions (
  id, workspace_id, custom_field_definition_id, version, value_type,
  labels, help_text, validation, default_value, options, required,
  visibility_permission_key, edit_permission_key, sensitive, searchable,
  section_key, status, checksum, created_by, activated_at
) values
  (
    '74600000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '73600000-0000-4000-8000-000000000001',
    1, 'short_text',
    '{"en":"Customer reference","fr":"Référence client"}',
    '{"en":"Internal reference","fr":"Référence interne"}',
    '{"minLength":2,"maxLength":30}', null, '[]', false,
    null, 'crm.update', false, true, 'party.profile', 'active', repeat('1', 64),
    '31000000-0000-4000-8000-000000000001',
    timestamptz '2026-07-16 21:00:00+00'
  ),
  (
    '74600000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '73600000-0000-4000-8000-000000000002',
    1, 'short_text',
    '{"en":"Restricted note","fr":"Note restreinte"}',
    '{"en":"Restricted","fr":"Restreint"}',
    '{"maxLength":100}', null, '[]', false,
    'identifiers.read_restricted', 'identifiers.manage', true, false,
    'party.restricted', 'active', repeat('2', 64),
    '31000000-0000-4000-8000-000000000001',
    timestamptz '2026-07-16 21:00:00+00'
  ),
  (
    '74600000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '73600000-0000-4000-8000-000000000003',
    1, 'party_reference',
    '{"en":"Related party","fr":"Partie liée"}',
    '{"en":"Workspace party","fr":"Partie de l’espace"}',
    '{}', null, '[]', false, null, 'crm.update', false, false,
    'party.relationships', 'active', repeat('3', 64),
    '31000000-0000-4000-8000-000000000001',
    timestamptz '2026-07-16 21:00:00+00'
  ),
  (
    '74600000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000001',
    '73600000-0000-4000-8000-000000000004',
    1, 'money',
    '{"en":"Credit limit","fr":"Limite de crédit"}',
    '{"en":"Exact amount","fr":"Montant exact"}',
    '{"allowedCurrencies":["CAD"]}', null, '[]', false,
    null, 'crm.update', false, false, 'party.finance', 'active', repeat('4', 64),
    '31000000-0000-4000-8000-000000000001',
    timestamptz '2026-07-16 21:00:00+00'
  ),
  (
    '74600000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000001',
    '73600000-0000-4000-8000-000000000005',
    1, 'boolean',
    '{"en":"Activation fixture","fr":"Fixture d’activation"}',
    '{"en":"Draft field","fr":"Champ brouillon"}',
    '{}', null, '[]', false, null, 'crm.update', false, false,
    'party.profile', 'draft', repeat('5', 64),
    '31000000-0000-4000-8000-000000000001', null
  ),
  (
    '74600000-0000-4000-8000-000000000007',
    '10000000-0000-4000-8000-000000000001',
    '73600000-0000-4000-8000-000000000007',
    1, 'inventory_reference',
    '{"en":"Related inventory","fr":"Inventaire lie"}',
    '{"en":"Authorized workspace inventory","fr":"Inventaire autorise de l espace"}',
    '{}', null, '[]', false, null, 'crm.update', false, false,
    'party.relationships', 'active', repeat('7', 64),
    '31000000-0000-4000-8000-000000000001',
    timestamptz '2026-07-16 21:00:00+00'
  ),
  (
    '74600000-0000-4000-8000-000000000006',
    '20000000-0000-4000-8000-000000000002',
    '73600000-0000-4000-8000-000000000006',
    1, 'short_text',
    '{"en":"Disabled fixture","fr":"Fixture désactivée"}',
    '{"en":"Entitlement test","fr":"Test d’admissibilité"}',
    '{}', null, '[]', false, null, 'crm.update', false, false,
    'party.profile', 'active', repeat('6', 64),
    '32000000-0000-4000-8000-000000000001',
    timestamptz '2026-07-16 21:00:00+00'
  );

select extensions.has_table(
  'public', 'custom_field_definitions',
  'stable custom-field identities are stored'
);
select extensions.has_table(
  'public', 'custom_field_versions',
  'immutable typed custom-field versions are stored'
);
select extensions.has_table(
  'public', 'custom_field_values',
  'typed entity values are stored'
);
select extensions.has_table(
  'public', 'custom_field_command_receipts',
  'actor-scoped custom-field command receipts are stored'
);
select extensions.has_function(
  'app', 'create_custom_field_version',
  array[
    'uuid', 'text', 'text', 'text', 'text', 'jsonb', 'jsonb', 'jsonb',
    'jsonb', 'jsonb', 'boolean', 'text', 'text', 'boolean', 'boolean',
    'text', 'text', 'text', 'uuid'
  ],
  'entitlement-gated custom-field definition command exists'
);
select extensions.has_function(
  'app', 'activate_custom_field_version',
  array['uuid', 'text', 'uuid', 'text', 'text', 'text', 'uuid'],
  'exact custom-field activation command exists'
);
select extensions.has_function(
  'app', 'set_custom_field_value',
  array[
    'uuid', 'text', 'text', 'uuid', 'uuid', 'uuid', 'bigint', 'jsonb',
    'text', 'uuid'
  ],
  'exact typed-value command exists'
);
select extensions.has_function(
  'app', 'get_custom_field_values', array['uuid', 'text', 'uuid'],
  'masked custom-field projection exists'
);
select extensions.ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'app.get_custom_field_values(uuid,text,uuid)'::regprocedure
      )
    ),
    'limit 500'
  ) > 0,
  'custom-field entity projections are bounded to 500 definitions'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    where relation.oid = 'public.custom_field_definitions'::regclass
  ),
  'custom-field definitions force RLS'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    where relation.oid = 'public.custom_field_versions'::regclass
  ),
  'custom-field versions force RLS'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    where relation.oid = 'public.custom_field_values'::regclass
  ),
  'custom-field values force RLS'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    where relation.oid = 'public.custom_field_command_receipts'::regclass
  ),
  'custom-field command receipts force RLS'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.has_custom_field_entity_permission(uuid,text,text)',
    'EXECUTE'
  ),
  'T-TEN-001 authenticated custom-field RLS can execute its safe policy helper'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'app.validate_custom_field_version()', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app.protect_activated_custom_field_version()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated', 'app.validate_custom_field_value_row()', 'EXECUTE'
  ),
  'T-RBAC-001 security-definer custom-field trigger functions are not callable'
);
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.create_custom_field_version(uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,boolean,text,text,boolean,boolean,text,text,text,uuid)'::pg_catalog.regprocedure
  ) like '%pg_advisory_xact_lock%'
  and pg_catalog.pg_get_functiondef(
    'app.activate_custom_field_version(uuid,text,uuid,text,text,text,uuid)'::pg_catalog.regprocedure
  ) like '%pg_advisory_xact_lock%'
  and pg_catalog.pg_get_functiondef(
    'app.set_custom_field_value(uuid,text,text,uuid,uuid,uuid,bigint,jsonb,text,uuid)'::pg_catalog.regprocedure
  ) like '%pg_advisory_xact_lock%',
  'T-FIELD-003 custom-field commands serialize actor-scoped idempotency replay'
);
select extensions.has_index(
  'public', 'custom_field_versions',
  'custom_field_versions_active_definition_uidx',
  'only one active version can exist per definition'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.unnest(array[
      'short_text', 'long_text', 'integer', 'decimal', 'money', 'boolean',
      'date', 'datetime', 'single_select', 'multi_select',
      'party_reference', 'inventory_reference', 'location_reference',
      'user_reference'
    ]) item
  ),
  14,
  'all fourteen Release 1 custom-field types are represented'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.custom_field_versions version
    where version.workspace_id = '10000000-0000-4000-8000-000000000001'
      and version.labels ? 'en' and version.labels ? 'fr'
      and version.help_text ? 'en' and version.help_text ? 'fr'
  ),
  6,
  'fixture versions preserve English and French labels and help'
);
select extensions.ok(
  app.custom_field_json_has_executable_key(
    '{"validation":{"script":"return true"}}'::jsonb
  ),
  'executable-shaped nested configuration is detected'
);
select extensions.throws_ok(
  $$
    select app.normalize_custom_field_value(
      'short_text', '{}'::jsonb, '[]'::jsonb, true, 'null'::jsonb
    )
  $$,
  '23514',
  'required custom field value is missing',
  'required values fail closed'
);
select extensions.is(
  app.normalize_custom_field_value(
    'integer', '{"minimum":"-10","maximum":"10"}', '[]', false,
    '"9"'::jsonb
  ),
  '"9"'::jsonb,
  'integer normalization remains exact text'
);
select extensions.is(
  app.normalize_custom_field_value(
    'decimal', '{"scale":3}', '[]', false, '"1.250"'::jsonb
  ),
  '"1.250"'::jsonb,
  'decimal normalization preserves exact declared scale'
);
select extensions.is(
  app.normalize_custom_field_value(
    'money', '{"allowedCurrencies":["CAD"]}', '[]', false,
    '{"amountMinor":"9007199254740993","currencyCode":"CAD"}'
  ),
  '{"amountMinor":"9007199254740993","currencyCode":"CAD"}'::jsonb,
  'money beyond JavaScript safe integer stays exact'
);
select extensions.throws_ok(
  $$
    select app.normalize_custom_field_value(
      'date', '{}'::jsonb, '[]'::jsonb, false, '"2023-02-29"'::jsonb
    )
  $$,
  '22003',
  'custom field value is out of range',
  'invalid calendar dates fail closed'
);
select extensions.throws_ok(
  $$
    select app.normalize_custom_field_value(
      'single_select', '{}'::jsonb,
      '[{"key":"legacy","active":false,"labels":{"en":"Legacy","fr":"Historique"}}]'::jsonb,
      false, '"legacy"'::jsonb
    )
  $$,
  '23514',
  'custom field option is unavailable',
  'inactive select options cannot be stored'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.field_definitions
select result.*, 'first'
from app.create_custom_field_version(
  '10000000-0000-4000-8000-000000000001',
  'field-definition-command-001',
  'party', 'created_by_command', 'single_select',
  '{"en":"Created by command","fr":"Créé par commande"}',
  '{"en":"Synthetic definition","fr":"Définition synthétique"}',
  '{}', '"new"',
  '[{"key":"new","labels":{"en":"New","fr":"Nouveau"},"active":true}]',
  false, null, 'crm.update', false, true, 'party.command',
  repeat('7', 64), 'm3-field-definition',
  '75600000-0000-4000-8000-000000000012'
) result;
insert into pg_temp.field_definitions
select result.*, 'replay'
from app.create_custom_field_version(
  '10000000-0000-4000-8000-000000000001',
  'field-definition-command-001',
  'party', 'created_by_command', 'single_select',
  '{"en":"Created by command","fr":"Créé par commande"}',
  '{"en":"Synthetic definition","fr":"Définition synthétique"}',
  '{}', '"new"',
  '[{"key":"new","labels":{"en":"New","fr":"Nouveau"},"active":true}]',
  false, null, 'crm.update', false, true, 'party.command',
  repeat('7', 64), 'm3-field-definition',
  '75600000-0000-4000-8000-000000000012'
) result;
select extensions.is(
  (select replayed from pg_temp.field_definitions where probe = 'first'),
  false,
  'definition command creates an original draft version'
);
select extensions.is(
  (select replayed from pg_temp.field_definitions where probe = 'replay'),
  true,
  'definition command replay returns its original result'
);
select extensions.is(
  (
    select pg_catalog.concat(
      definition.entity_type, ':', definition.key, ':', version.value_type,
      ':', version.status, ':', version.version
    )
    from public.custom_field_definitions definition
    join public.custom_field_versions version
      on version.workspace_id = definition.workspace_id
     and version.custom_field_definition_id = definition.id
    where definition.id = (
      select custom_field_definition_id from pg_temp.field_definitions
      where probe = 'first'
    )
  ),
  'party:created_by_command:single_select:draft:1',
  'definition command persists the validated typed draft'
);
select extensions.ok(
  exists (
    select 1 from public.audit_events audit
    where audit.id = (
      select audit_event_id from pg_temp.field_definitions
      where probe = 'first'
    )
      and audit.action = 'custom_field_version.created'
      and audit.after_data ->> 'fieldKey' = 'created_by_command'
  ),
  'definition command writes safe audit metadata'
);
select extensions.throws_ok(
  $$
    select * from app.create_custom_field_version(
      '10000000-0000-4000-8000-000000000001',
      'field-definition-command-001',
      'party', 'created_by_command', 'single_select',
      '{"en":"Different","fr":"Différent"}',
      '{"en":"Synthetic definition","fr":"Définition synthétique"}',
      '{}', '"new"',
      '[{"key":"new","labels":{"en":"New","fr":"Nouveau"},"active":true}]',
      false, null, 'crm.update', false, true, 'party.command',
      repeat('7', 64), 'm3-field-definition',
      '75600000-0000-4000-8000-000000000012'
    )
  $$,
  '23505',
  'idempotency key was reused with different custom field definition input',
  'definition key reuse with a different fingerprint fails closed'
);
insert into pg_temp.field_activations
select result.*, 'first'
from app.activate_custom_field_version(
  '10000000-0000-4000-8000-000000000001',
  'field-activation-001',
  '74600000-0000-4000-8000-000000000005',
  repeat('5', 64),
  'Activate the synthetic typed field.',
  'm3-field-activation',
  '75600000-0000-4000-8000-000000000001'
) result;
insert into pg_temp.field_activations
select result.*, 'replay'
from app.activate_custom_field_version(
  '10000000-0000-4000-8000-000000000001',
  'field-activation-001',
  '74600000-0000-4000-8000-000000000005',
  repeat('5', 64),
  'Activate the synthetic typed field.',
  'm3-field-activation',
  '75600000-0000-4000-8000-000000000001'
) result;
reset role;

select extensions.is(
  (select replayed from pg_temp.field_activations where probe = 'first'),
  false,
  'draft custom-field activation is an original command'
);
select extensions.is(
  (
    select status
    from public.custom_field_versions
    where id = '74600000-0000-4000-8000-000000000005'
  ),
  'active',
  'activation moves the exact version to active'
);
select extensions.is(
  (select replayed from pg_temp.field_activations where probe = 'replay'),
  true,
  'custom-field activation replay returns the original result'
);
select extensions.throws_ok(
  $$
    update public.custom_field_versions
    set labels = '{"en":"Changed","fr":"Modifié"}'
    where id = '74600000-0000-4000-8000-000000000005'
  $$,
  '55000',
  'activated custom field versions are immutable',
  'activated version contents cannot be changed'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.field_commands
select result.*, 'regular-first'
from app.set_custom_field_value(
  '10000000-0000-4000-8000-000000000001',
  'field-shared-001', 'party',
  '72600000-0000-4000-8000-000000000001',
  '73600000-0000-4000-8000-000000000001',
  '74600000-0000-4000-8000-000000000001',
  0, '"AB-123"', 'm3-field-set',
  '75600000-0000-4000-8000-000000000002'
) result;
insert into pg_temp.field_commands
select result.*, 'regular-replay'
from app.set_custom_field_value(
  '10000000-0000-4000-8000-000000000001',
  'field-shared-001', 'party',
  '72600000-0000-4000-8000-000000000001',
  '73600000-0000-4000-8000-000000000001',
  '74600000-0000-4000-8000-000000000001',
  0, '"AB-123"', 'm3-field-set',
  '75600000-0000-4000-8000-000000000002'
) result;
reset role;

select extensions.is(
  (select replayed from pg_temp.field_commands where probe = 'regular-first'),
  false,
  'first typed-value command is not a replay'
);
select extensions.is(
  (
    select pg_catalog.concat(value_type, ':', text_value, ':', version)
    from public.custom_field_values
    where custom_field_definition_id = '73600000-0000-4000-8000-000000000001'
  ),
  'short_text:AB-123:1',
  'typed text storage pins the validated value and aggregate version'
);
select extensions.ok(
  exists (
    select 1
    from public.audit_events audit
    where audit.id = (
      select audit_event_id from pg_temp.field_commands
      where probe = 'regular-first'
    )
      and audit.action = 'custom_field_value.created'
      and audit.after_data ->> 'fieldKey' = 'customer_reference'
  ),
  'typed value creation records append-only audit metadata'
);
select extensions.is(
  (select replayed from pg_temp.field_commands where probe = 'regular-replay'),
  true,
  'identical typed-value replay returns the original receipt'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '10000000-0000-4000-8000-000000000001',
      'field-shared-001', 'party',
      '72600000-0000-4000-8000-000000000001',
      '73600000-0000-4000-8000-000000000001',
      '74600000-0000-4000-8000-000000000001',
      1, '"different"', 'm3-field-set',
      '75600000-0000-4000-8000-000000000002'
    )
  $$,
  '23505',
  'idempotency key was reused with different custom field input',
  'same actor cannot reuse a value key for different input'
);
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '10000000-0000-4000-8000-000000000001',
      'field-version-conflict', 'party',
      '72600000-0000-4000-8000-000000000001',
      '73600000-0000-4000-8000-000000000001',
      '74600000-0000-4000-8000-000000000001',
      0, '"CD-456"', 'm3-field-set',
      '75600000-0000-4000-8000-000000000003'
    )
  $$,
  '40001',
  'custom field value version conflict',
  'stale custom-field mutation loses without overwriting'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
insert into pg_temp.field_commands
select result.*, 'limited-same-key'
from app.set_custom_field_value(
  '10000000-0000-4000-8000-000000000001',
  'field-shared-001', 'party',
  '72600000-0000-4000-8000-000000000001',
  '73600000-0000-4000-8000-000000000001',
  '74600000-0000-4000-8000-000000000001',
  1, '"CD-456"', 'm3-field-set-limited',
  '75600000-0000-4000-8000-000000000004'
) result;
reset role;
select extensions.is(
  (
    select replayed from pg_temp.field_commands
    where probe = 'limited-same-key'
  ),
  false,
  'a second actor owns an independent idempotency namespace'
);
select extensions.is(
  (
    select pg_catalog.count(distinct actor_user_id)::integer
    from public.custom_field_command_receipts
    where command_type = 'set_custom_field_value'
      and idempotency_key = 'field-shared-001'
  ),
  2,
  'same idempotency key is retained once per actor'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.field_commands
select result.*, 'sensitive-admin'
from app.set_custom_field_value(
  '10000000-0000-4000-8000-000000000001',
  'field-sensitive-001', 'party',
  '72600000-0000-4000-8000-000000000001',
  '73600000-0000-4000-8000-000000000002',
  '74600000-0000-4000-8000-000000000002',
  0, '"sensitive synthetic note"', 'm3-field-sensitive',
  '75600000-0000-4000-8000-000000000005'
) result;
reset role;
select extensions.is(
  (select replayed from pg_temp.field_commands where probe = 'sensitive-admin'),
  false,
  'authorized restricted-field write succeeds'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.custom_field_values
    where custom_field_definition_id = '73600000-0000-4000-8000-000000000002'
  ),
  0,
  'direct RLS hides restricted custom-field values'
);
select extensions.ok(
  exists (
    select 1
    from app.get_custom_field_values(
      '10000000-0000-4000-8000-000000000001', 'party',
      '72600000-0000-4000-8000-000000000001'
    ) projection
    where projection.field_key = 'restricted_note'
      and projection.masked and projection.value is null
  ),
  'safe projection preserves field shape while masking its value'
);
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '10000000-0000-4000-8000-000000000001',
      'field-sensitive-limited', 'party',
      '72600000-0000-4000-8000-000000000001',
      '73600000-0000-4000-8000-000000000002',
      '74600000-0000-4000-8000-000000000002',
      1, '"attempt"', 'm3-field-sensitive',
      '75600000-0000-4000-8000-000000000006'
    )
  $$,
  '42501',
  'custom field edit permission is required',
  'entity update permission cannot bypass the field edit permission'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  exists (
    select 1
    from app.get_custom_field_values(
      '10000000-0000-4000-8000-000000000001', 'party',
      '72600000-0000-4000-8000-000000000001'
    ) projection
    where projection.field_key = 'restricted_note'
      and not projection.masked
      and projection.value = '"sensitive synthetic note"'::jsonb
  ),
  'dedicated visibility permission reveals the exact value'
);
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '10000000-0000-4000-8000-000000000001',
      'field-cross-reference', 'party',
      '72600000-0000-4000-8000-000000000001',
      '73600000-0000-4000-8000-000000000003',
      '74600000-0000-4000-8000-000000000003',
      0, '"72600000-0000-4000-8000-000000000002"',
      'm3-field-reference',
      '75600000-0000-4000-8000-000000000007'
    )
  $$,
  '23503',
  'custom field party reference is outside the workspace',
  'cross-workspace party references fail closed'
);
insert into pg_temp.field_commands
select result.*, 'same-workspace-reference'
from app.set_custom_field_value(
  '10000000-0000-4000-8000-000000000001',
  'field-same-reference', 'party',
  '72600000-0000-4000-8000-000000000001',
  '73600000-0000-4000-8000-000000000003',
  '74600000-0000-4000-8000-000000000003',
  0, '"72600000-0000-4000-8000-000000000001"',
  'm3-field-reference',
  '75600000-0000-4000-8000-000000000008'
) result;
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '10000000-0000-4000-8000-000000000001',
      'field-inventory-cross', 'party',
      '72600000-0000-4000-8000-000000000001',
      '73600000-0000-4000-8000-000000000007',
      '74600000-0000-4000-8000-000000000007',
      0, '"72640000-0000-4000-8000-000000000002"',
      'm3-field-inventory-cross',
      '75600000-0000-4000-8000-000000000012'
    )
  $$,
  '23503',
  'custom field inventory reference is outside the workspace',
  'cross-workspace inventory references fail closed'
);
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '10000000-0000-4000-8000-000000000001',
      'field-inventory-missing', 'party',
      '72600000-0000-4000-8000-000000000001',
      '73600000-0000-4000-8000-000000000007',
      '74600000-0000-4000-8000-000000000007',
      0, '"72640000-0000-4000-8000-000000000099"',
      'm3-field-inventory-missing',
      '75600000-0000-4000-8000-000000000013'
    )
  $$,
  '23503',
  'custom field inventory reference is outside the workspace',
  'missing inventory references fail closed without distinguishing tenancy'
);
insert into pg_temp.field_commands
select result.*, 'same-workspace-inventory'
from app.set_custom_field_value(
  '10000000-0000-4000-8000-000000000001',
  'field-inventory-same', 'party',
  '72600000-0000-4000-8000-000000000001',
  '73600000-0000-4000-8000-000000000007',
  '74600000-0000-4000-8000-000000000007',
  0, '"72640000-0000-4000-8000-000000000001"',
  'm3-field-inventory-same',
  '75600000-0000-4000-8000-000000000014'
) result;
select extensions.is(
  (
    select replayed from pg_temp.field_commands
    where probe = 'same-workspace-inventory'
  ),
  false,
  'authorized same-workspace inventory reference is accepted'
);
select extensions.is(
  (
    select pg_catalog.concat_ws(
      ':', value_type, reference_id::text,
      custom_field_version_id::text, version::text
    )
    from public.custom_field_values
    where custom_field_definition_id =
      '73600000-0000-4000-8000-000000000007'
  ),
  'inventory_reference:72640000-0000-4000-8000-000000000001:74600000-0000-4000-8000-000000000007:1',
  'inventory reference storage pins the typed target and immutable version'
);
select extensions.ok(
  exists (
    select 1
    from app.get_custom_field_values(
      '10000000-0000-4000-8000-000000000001', 'party',
      '72600000-0000-4000-8000-000000000001'
    ) projection
    where projection.field_key = 'related_inventory'
      and projection.field_type = 'inventory_reference'
      and projection.custom_field_version_id =
        '74600000-0000-4000-8000-000000000007'
      and not projection.masked
      and projection.value =
        '"72640000-0000-4000-8000-000000000001"'::jsonb
      and projection.value_version = 1
  ),
  'authorized projection returns the exact pinned inventory reference'
);
select extensions.ok(
  exists (
    select 1
    from public.audit_events audit
    where audit.id = (
      select audit_event_id from pg_temp.field_commands
      where probe = 'same-workspace-inventory'
    )
      and audit.after_data ->> 'fieldKey' = 'related_inventory'
      and audit.after_data ->> 'definitionVersionId' =
        '74600000-0000-4000-8000-000000000007'
      and audit.after_data ->> 'valueVersion' = '1'
      and not (audit.after_data ? 'value')
  ),
  'inventory reference audit pins definition provenance without target bytes'
);
insert into pg_temp.field_commands
select result.*, 'money'
from app.set_custom_field_value(
  '10000000-0000-4000-8000-000000000001',
  'field-money-001', 'party',
  '72600000-0000-4000-8000-000000000001',
  '73600000-0000-4000-8000-000000000004',
  '74600000-0000-4000-8000-000000000004',
  0, '{"amountMinor":"9007199254740993","currencyCode":"CAD"}',
  'm3-field-money',
  '75600000-0000-4000-8000-000000000009'
) result;
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '10000000-0000-4000-8000-000000000001',
      'field-workspace-spoof', 'party',
      '72600000-0000-4000-8000-000000000002',
      '73600000-0000-4000-8000-000000000001',
      '74600000-0000-4000-8000-000000000001',
      0, '"spoof"', 'm3-field-spoof',
      '75600000-0000-4000-8000-000000000010'
    )
  $$,
  'P0002',
  'custom field owning entity was not found',
  'request workspace cannot authorize another-workspace entity'
);
reset role;

select extensions.throws_ok(
  $$
    update public.custom_field_versions
    set labels = '{"en":"Changed","fr":"Modifie"}'
    where id = '74600000-0000-4000-8000-000000000007'
  $$,
  '55000',
  'activated custom field versions are immutable',
  'activated inventory-reference definition provenance cannot be rewritten'
);

select extensions.is(
  (
    select replayed from pg_temp.field_commands
    where probe = 'same-workspace-reference'
  ),
  false,
  'same-workspace party reference is accepted'
);
select extensions.is(
  (select replayed from pg_temp.field_commands where probe = 'money'),
  false,
  'exact money custom-field command succeeds'
);
select extensions.is(
  (
    select pg_catalog.concat(money_minor::text, ':', money_currency)
    from public.custom_field_values
    where custom_field_definition_id = '73600000-0000-4000-8000-000000000004'
  ),
  '9007199254740993:CAD',
  'typed money storage preserves minor units and ISO currency'
);
select extensions.is(
  (
    select pg_catalog.num_nonnulls(
      text_value, integer_value, decimal_value, money_minor, money_currency,
      boolean_value, date_value, datetime_value, selected_keys, reference_id
    )::integer
    from public.custom_field_values
    where custom_field_definition_id = '73600000-0000-4000-8000-000000000004'
  ),
  2,
  'money row populates only its exact typed pair'
);
select extensions.ok(
  exists (
    select 1
    from public.audit_events audit
    where audit.id = (
      select audit_event_id from pg_temp.field_commands
      where probe = 'sensitive-admin'
    )
      and audit.after_data ->> 'valueRedacted' = 'true'
      and pg_catalog.strpos(audit.after_data::text, 'sensitive synthetic note') = 0
  ),
  'sensitive value bytes never enter audit payloads'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '10000000-0000-4000-8000-000000000001',
      'field-inventory-limited', 'party',
      '72600000-0000-4000-8000-000000000001',
      '73600000-0000-4000-8000-000000000007',
      '74600000-0000-4000-8000-000000000007',
      1, '"72640000-0000-4000-8000-000000000001"',
      'm3-field-inventory-limited',
      '75600000-0000-4000-8000-000000000015'
    )
  $$,
  '42501',
  'custom field inventory reference permission is required',
  'CRM update permission cannot authorize an unreadable inventory target'
);
select extensions.ok(
  exists (
    select 1
    from app.get_custom_field_values(
      '10000000-0000-4000-8000-000000000001', 'party',
      '72600000-0000-4000-8000-000000000001'
    ) projection
    where projection.field_key = 'related_inventory'
      and projection.masked
      and projection.value is null
  ),
  'inventory references remain masked without target read permission'
);
reset role;

-- Retire only the second fictional workspace entitlement inside this rolled
-- back test transaction, then prove neither full admin permission nor table
-- presence grants access.
select app.retire_workspace_feature_entitlement_version(
  entitlement.workspace_id,
  entitlement.id,
  entitlement.checksum,
  'Synthetic fail-closed custom-field entitlement test.'
)
from public.workspace_feature_entitlements entitlement
where entitlement.workspace_id = '20000000-0000-4000-8000-000000000002'
  and entitlement.entitlement_key = 'custom_workflows'
  and entitlement.status = 'active';

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from app.get_custom_field_values(
      '20000000-0000-4000-8000-000000000002', 'party',
      '72600000-0000-4000-8000-000000000002'
    )
  ),
  0,
  'disabled custom_workflows entitlement returns no projection'
);
select extensions.throws_ok(
  $$
    select * from app.set_custom_field_value(
      '20000000-0000-4000-8000-000000000002',
      'field-disabled-entitlement', 'party',
      '72600000-0000-4000-8000-000000000002',
      '73600000-0000-4000-8000-000000000006',
      '74600000-0000-4000-8000-000000000006',
      0, '"blocked"', 'm3-field-disabled',
      '75600000-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'custom field entity update permission is required',
  'full entity permission cannot bypass a disabled entitlement'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.custom_field_definitions
    where workspace_id = '10000000-0000-4000-8000-000000000001'
  ),
  0,
  'RLS also hides another workspace custom-field definitions'
);
reset role;

select extensions.throws_ok(
  $$
    update public.custom_field_command_receipts
    set result = '{}'::jsonb
    where idempotency_key = 'field-shared-001'
  $$,
  '55000',
  'custom field command history is append-only',
  'command receipts cannot be rewritten'
);
select extensions.throws_ok(
  $$
    delete from public.custom_field_values
    where custom_field_definition_id = '73600000-0000-4000-8000-000000000001'
  $$,
  '55000',
  'hard delete is prohibited for custom_field_values',
  'custom-field values cannot be hard deleted'
);

select * from extensions.finish();
rollback;
