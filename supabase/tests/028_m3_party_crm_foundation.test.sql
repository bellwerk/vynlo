-- VYN-CRM-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-JOB-001
-- T-CRM-001, T-TEN-001, T-RBAC-001, T-AUTH-002, T-AUD-001
-- M3-CRM-AC-001: party/CRM profile, contact, address, restricted identifier,
-- relationship, communication preference, idempotency, and event evidence.
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(67);

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

create temporary table pg_temp.party_results (
  probe text primary key,
  party_id uuid not null,
  aggregate_version bigint not null,
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  replayed boolean not null
);
create temporary table pg_temp.entity_results (
  probe text primary key,
  entity_id uuid not null,
  party_id uuid not null,
  aggregate_version bigint not null,
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  replayed boolean not null
);
create temporary table pg_temp.legacy_results (
  probe text primary key,
  party_id uuid not null,
  replayed boolean not null
);
create temporary table pg_temp.party_projection (
  party_id uuid,
  party_type text,
  display_name text,
  preferred_locale text,
  status text,
  version bigint,
  contacts jsonb,
  addresses jsonb,
  identifiers jsonb,
  relationships jsonb,
  preferences jsonb,
  profile jsonb
);
create temporary table pg_temp.identifier_reveal (
  identifier_id uuid,
  party_id uuid,
  plaintext_value text,
  audit_event_id uuid
);
grant all on
  pg_temp.party_results,
  pg_temp.entity_results,
  pg_temp.legacy_results,
  pg_temp.party_projection,
  pg_temp.identifier_reveal
to authenticated, service_role;

-- The second Northstar fixture user receives CRM only, deliberately excluding
-- both restricted-identifier permissions.
insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  '52800000-0000-4000-8000-000000000028',
  '10000000-0000-4000-8000-000000000001',
  'crm_only_028', 'CRM-only fixture', 'system', 'active', false
);
insert into public.role_permissions (
  workspace_id, role_id, permission_id, status
)
select
  '10000000-0000-4000-8000-000000000001',
  '52800000-0000-4000-8000-000000000028',
  permission.id,
  'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key in ('crm.read', 'crm.create', 'crm.update');
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '62800000-0000-4000-8000-000000000028',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '52800000-0000-4000-8000-000000000028',
  'active'
);

select extensions.has_table(
  'public', 'legal_entities',
  'T-CRM-001 legal-entity prerequisite exists'
);
select extensions.ok(
  to_regclass('public.party_person_profiles') is not null
    and to_regclass('public.party_organization_profiles') is not null,
  'T-CRM-001 person and organization profiles exist'
);
select extensions.ok(
  to_regclass('public.party_contacts') is not null
    and to_regclass('public.party_addresses') is not null,
  'T-CRM-001 normalized contacts and structured addresses exist'
);
select extensions.has_table(
  'public', 'party_identifiers',
  'T-AUTH-002 restricted identifier storage exists'
);
select extensions.ok(
  to_regclass('public.party_relationships') is not null
    and to_regclass('public.party_communication_preferences') is not null,
  'T-CRM-001 relationships and communication preferences exist'
);
select extensions.has_table(
  'public', 'party_command_receipts',
  'T-CRM-001 actor-scoped command receipts exist'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any (array[
        'legal_entities', 'party_person_profiles',
        'party_organization_profiles', 'party_contacts', 'party_addresses',
        'party_identifiers', 'party_relationships',
        'party_communication_preferences', 'party_command_receipts'
      ])
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  9,
  'T-TEN-001 every new exposed or restricted table forces RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.party_identifiers', 'SELECT'
  ) and not pg_catalog.has_table_privilege(
    'authenticated', 'public.party_command_receipts', 'SELECT'
  ),
  'T-RBAC-001 ordinary authenticated SQL cannot read identifiers or receipts'
);
select extensions.ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public' and table_name = 'party_identifiers'
      and column_name = 'encrypted_value' and data_type = 'bytea'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public' and table_name = 'party_identifiers'
      and column_name in ('value', 'plaintext_value')
  ),
  'T-AUTH-002 identifiers persist ciphertext and no plaintext column'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_indexes index_definition
    where index_definition.schemaname = 'public'
      and index_definition.tablename = 'parties'
      and index_definition.indexdef like
        '%(workspace_id, idempotency_actor_user_id, idempotency_key)%'
      and index_definition.indexdef like 'CREATE UNIQUE INDEX%'
  ),
  'T-CRM-001 legacy party idempotency uniqueness is actor scoped'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_indexes index_definition
    where index_definition.schemaname = 'public'
      and index_definition.tablename = 'party_command_receipts'
      and index_definition.indexdef like
        '%(workspace_id, actor_user_id, command_type, idempotency_key)%'
      and index_definition.indexdef like 'CREATE UNIQUE INDEX%'
  ),
  'T-CRM-001 M3 command receipts are actor and command scoped'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_definition
    where constraint_definition.conrelid
        = 'public.party_command_receipts'::pg_catalog.regclass
      and constraint_definition.contype = 'f'
      and pg_catalog.pg_get_constraintdef(constraint_definition.oid)
        like 'FOREIGN KEY (workspace_id, audit_event_id)%'
  ),
  'T-TEN-001 party receipt audit evidence preserves workspace context'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_definition
    where constraint_definition.conrelid = 'public.legal_entities'::regclass
      and constraint_definition.contype = 'f'
      and pg_catalog.pg_get_constraintdef(constraint_definition.oid)
        like 'FOREIGN KEY (workspace_id, organization_party_id)%'
  ),
  'T-TEN-001 legal entity organization links preserve workspace context'
);

select extensions.has_function(
  'app', 'm3_list_parties', array['uuid'],
  'application list-party RPC contract exists'
);
select extensions.has_function(
  'app', 'm3_get_party', array['uuid', 'uuid'],
  'application get-party RPC contract exists'
);
select extensions.is(
  pg_catalog.regexp_count(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef('app.m3_get_party(uuid,uuid)'::regprocedure)
    ),
    'limit 100'
  ),
  5,
  'party detail bounds every nested CRM collection to 100 rows'
);
select extensions.has_function(
  'app', 'm3_create_party',
  array[
    'uuid', 'text', 'text', 'text', 'text', 'text', 'text', 'text',
    'date', 'text', 'text', 'text', 'uuid'
  ],
  'application create-party RPC contract exists'
);
select extensions.has_function(
  'app', 'm3_add_party_contact',
  array[
    'uuid', 'text', 'uuid', 'text', 'text', 'boolean', 'boolean',
    'text', 'text', 'boolean', 'text', 'uuid'
  ],
  'application add-contact RPC contract exists'
);
select extensions.has_function(
  'app', 'm3_add_party_address',
  array[
    'uuid', 'text', 'uuid', 'text', 'text', 'text', 'text', 'text',
    'text', 'text', 'boolean', 'text', 'uuid'
  ],
  'application add-address RPC contract exists'
);
select extensions.has_function(
  'app', 'm3_replace_party_identifier',
  array[
    'uuid', 'text', 'uuid', 'text', 'text', 'text', 'date', 'date',
    'text', 'text', 'uuid'
  ],
  'application replace-identifier RPC contract exists'
);
select extensions.has_function(
  'app', 'm3_add_party_relationship',
  array['uuid', 'text', 'uuid', 'uuid', 'text', 'date', 'date', 'text', 'uuid'],
  'application add-relationship RPC contract exists'
);
select extensions.ok(
  to_regprocedure(
    'app.m3_update_party(uuid,text,uuid,bigint,text,text,text,text,text,date,text,text,text,uuid)'
  ) is not null
    and to_regprocedure(
      'app.m3_archive_party(uuid,text,uuid,bigint,text,text,uuid)'
    ) is not null
    and to_regprocedure(
      'app.m3_set_party_communication_preference(uuid,text,uuid,bigint,text,boolean,boolean,text,text,text,uuid)'
    ) is not null,
  'expected-version update, archive, and preference RPCs exist'
);
select extensions.ok(
  (
    select procedure.proargnames[1:13]
    from pg_catalog.pg_proc procedure
    where procedure.oid = to_regprocedure(
      'app.m3_create_party(uuid,text,text,text,text,text,text,text,date,text,text,text,uuid)'
    )
  ) = array[
    'p_workspace_id', 'p_idempotency_key', 'p_party_type', 'p_display_name',
    'p_preferred_locale', 'p_given_name', 'p_family_name', 'p_preferred_name',
    'p_birth_date', 'p_legal_name', 'p_registration_name', 'p_request_id',
    'p_correlation_id'
  ]::text[],
  'create-party named parameters exactly match the application adapter'
);
select extensions.ok(
  (
    select procedure.proargnames[3:14]
    from pg_catalog.pg_proc procedure
    where procedure.oid = to_regprocedure('app.m3_get_party(uuid,uuid)')
  ) = array[
    'party_id', 'party_type', 'display_name', 'preferred_locale', 'status',
    'version', 'contacts', 'addresses', 'identifiers', 'relationships',
    'preferences', 'profile'
  ]::text[],
  'get-party result names exactly match the application adapter'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.party_results
select 'person-first', result.*
from app.m3_create_party(
  '10000000-0000-4000-8000-000000000001',
  'crm-person-028', 'person', '  Synthetic   Person  ', 'en',
  'Synthetic', 'Person', 'Syn', date '1990-01-02', null, null,
  'crm-create-person-028', '70000000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.party_results
select 'person-replay', result.*
from app.m3_create_party(
  '10000000-0000-4000-8000-000000000001',
  'crm-person-028', 'person', '  Synthetic   Person  ', 'en',
  'Synthetic', 'Person', 'Syn', date '1990-01-02', null, null,
  'crm-create-person-028', '70000000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.party_results
select 'organization-first', result.*
from app.m3_create_party(
  '10000000-0000-4000-8000-000000000001',
  'crm-organization-028', 'organization', 'Synthetic Organization', 'fr',
  null, null, null, null, 'Synthetic Organization Legal', 'SYNTH ORG',
  'crm-create-organization-028', '70100000-0000-4000-8000-000000000028'
) result;
reset role;

select extensions.is(
  (select replayed from pg_temp.party_results where probe = 'person-first'),
  false,
  'T-CRM-001 create-party original command is not a replay'
);
select extensions.is(
  (select replayed from pg_temp.party_results where probe = 'person-replay'),
  true,
  'T-CRM-001 same-actor create-party replay is stable'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.parties party
    where party.id = (
      select party_id from pg_temp.party_results where probe = 'person-first'
    )
      and party.display_name = 'Synthetic Person'
      and party.party_type = 'person'
      and party.version = 1
  ),
  1,
  'T-CRM-001 party identity is normalized and versioned'
);
select extensions.ok(
  exists (
    select 1
    from public.party_person_profiles profile
    where profile.party_id = (
      select party_id from pg_temp.party_results where probe = 'person-first'
    )
      and profile.given_name = 'Synthetic'
      and profile.family_name = 'Person'
      and profile.preferred_locale = 'en'
  ) and exists (
    select 1
    from public.party_organization_profiles profile
    where profile.party_id = (
      select party_id from pg_temp.party_results
      where probe = 'organization-first'
    )
      and profile.legal_name = 'Synthetic Organization Legal'
      and profile.preferred_locale = 'fr'
  ),
  'T-CRM-001 create-party persists the matching typed profile'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000003');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.m3_create_party(
      '10000000-0000-4000-8000-000000000001',
      'crm-person-028', 'person', 'Different Person', 'en',
      'Different', 'Person', null, null, null, null,
      'crm-create-person-028', '70000000-0000-4000-8000-000000000028'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'inactive membership fails closed before idempotency lookup'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.m3_create_party(
      '10000000-0000-4000-8000-000000000001',
      'crm-person-028', 'person', 'Different Person', 'en',
      'Different', 'Person', null, null, null, null,
      'crm-create-person-028', '70000000-0000-4000-8000-000000000028'
    )
  $$,
  '23505',
  'party idempotency key was used for different create input',
  'same-actor idempotency mismatch fails closed'
);

insert into pg_temp.entity_results
select 'contact-first', result.*
from app.m3_add_party_contact(
  '10000000-0000-4000-8000-000000000001',
  'crm-contact-028',
  (select party_id from pg_temp.party_results where probe = 'person-first'),
  'email', '  SYNTHETIC.PERSON@EXAMPLE.INVALID  ', true, true,
  'granted', 'synthetic written consent', false,
  'crm-contact-028', '70200000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.entity_results
select 'address-first', result.*
from app.m3_add_party_address(
  '10000000-0000-4000-8000-000000000001',
  'crm-address-028',
  (select party_id from pg_temp.party_results where probe = 'person-first'),
  'mailing', '100 Synthetic Way', null, 'Synthetic City', 'QC', 'H0H 0H0',
  'ca', true, 'crm-address-028',
  '70300000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.entity_results
select 'relationship-first', result.*
from app.m3_add_party_relationship(
  '10000000-0000-4000-8000-000000000001',
  'crm-relationship-028',
  (select party_id from pg_temp.party_results where probe = 'person-first'),
  (select party_id from pg_temp.party_results where probe = 'organization-first'),
  'employment.employer', date '2026-01-01', null,
  'crm-relationship-028', '70400000-0000-4000-8000-000000000028'
) result;
reset role;

select extensions.ok(
  exists (
    select 1 from public.party_contacts contact
    where contact.id = (
      select entity_id from pg_temp.entity_results where probe = 'contact-first'
    )
      and contact.value = 'SYNTHETIC.PERSON@EXAMPLE.INVALID'
      and contact.normalized_value = 'synthetic.person@example.invalid'
      and contact.is_primary and contact.is_preferred
      and contact.consent_status = 'granted'
      and contact.consent_source = 'synthetic written consent'
      and not contact.do_not_contact
  ),
  'T-CRM-001 contact normalization and consent provenance are persisted'
);
select extensions.ok(
  exists (
    select 1 from public.party_addresses address
    where address.id = (
      select entity_id from pg_temp.entity_results where probe = 'address-first'
    )
      and address.line_1 = '100 Synthetic Way'
      and address.locality = 'Synthetic City'
      and address.region = 'QC'
      and address.postal_code = 'H0H 0H0'
      and address.country_code = 'CA'
      and address.is_primary
  ),
  'T-CRM-001 address command persists structured normalized data'
);
select extensions.ok(
  exists (
    select 1 from public.party_relationships relationship
    where relationship.id = (
      select entity_id from pg_temp.entity_results
      where probe = 'relationship-first'
    )
      and relationship.workspace_id = '10000000-0000-4000-8000-000000000001'
      and relationship.relationship_type = 'employment.employer'
      and relationship.status = 'active'
  ),
  'T-TEN-001 same-workspace relationship is stored with lifecycle state'
);

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'aal1'
);
set local role authenticated;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_replace_party_identifier(
        '10000000-0000-4000-8000-000000000001',
        'crm-identifier-aal1-028', %L, 'government.synthetic', 'CA-QC',
        'SYNTHETIC-ID-9001', date '2026-01-01', null,
        'Synthetic fixture initial value', 'crm-identifier-aal1-028',
        '70500000-0000-4000-8000-000000000028'
      )
    $sql$,
    (select party_id from pg_temp.party_results where probe = 'person-first')
  ),
  '42501',
  'active workspace membership and permission are required',
  'T-AUTH-002 an AAL1 administrator session cannot manage identifiers'
);
reset role;

select pg_catalog.set_config('app.crm_identifier_encryption_key', '', true);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_replace_party_identifier(
        '10000000-0000-4000-8000-000000000001',
        'crm-identifier-key-028', %L, 'government.synthetic', 'CA-QC',
        'SYNTHETIC-ID-9001', date '2026-01-01', null,
        'Synthetic fixture initial value', 'crm-identifier-key-028',
        '70600000-0000-4000-8000-000000000028'
      )
    $sql$,
    (select party_id from pg_temp.party_results where probe = 'person-first')
  ),
  '55000',
  'CRM identifier encryption key is unavailable',
  'T-AUTH-002 identifier encryption fails closed without a runtime key'
);
reset role;

select pg_catalog.set_config(
  'app.crm_identifier_encryption_key',
  pg_catalog.repeat('synthetic-key-028-', 4),
  true
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.entity_results
select 'identifier-v1', result.*
from app.m3_replace_party_identifier(
  '10000000-0000-4000-8000-000000000001',
  'crm-identifier-v1-028',
  (select party_id from pg_temp.party_results where probe = 'person-first'),
  'government.synthetic', 'CA-QC', 'SYNTHETIC-ID-9001',
  date '2026-01-01', null, 'Synthetic fixture initial value',
  'crm-identifier-v1-028', '70700000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.entity_results
select 'identifier-v2', result.*
from app.m3_replace_party_identifier(
  '10000000-0000-4000-8000-000000000001',
  'crm-identifier-v2-028',
  (select party_id from pg_temp.party_results where probe = 'person-first'),
  'government.synthetic', 'CA-QC', 'SYNTHETIC-ID-9002',
  date '2026-02-01', null, 'Synthetic fixture correction',
  'crm-identifier-v2-028', '70800000-0000-4000-8000-000000000028'
) result;
reset role;

select extensions.is(
  (
    select pg_catalog.string_agg(
      identifier.version::text || ':' || identifier.status,
      ',' order by identifier.version
    )
    from public.party_identifiers identifier
    where identifier.party_id = (
      select party_id from pg_temp.party_results where probe = 'person-first'
    )
      and identifier.identifier_type = 'government.synthetic'
      and identifier.jurisdiction = 'CA-QC'
  ),
  '1:replaced,2:active',
  'T-CRM-001 identifier correction creates an immutable replacement version'
);
select extensions.ok(
  (
    select pg_catalog.bool_and(
      pg_catalog.strpos(
        pg_catalog.encode(identifier.encrypted_value, 'escape'),
        'SYNTHETIC-ID-'
      ) = 0
      and identifier.value_fingerprint ~ '^[0-9a-f]{64}$'
    )
    from public.party_identifiers identifier
    where identifier.party_id = (
      select party_id from pg_temp.party_results where probe = 'person-first'
    )
  ) and (
    select masked_suffix = '9002'
    from public.party_identifiers identifier
    where identifier.id = (
      select entity_id from pg_temp.entity_results where probe = 'identifier-v2'
    )
  ),
  'T-AUTH-002 identifier ciphertext and keyed fingerprint replace plaintext at rest'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
insert into pg_temp.party_projection
select * from app.m3_get_party(
  '10000000-0000-4000-8000-000000000001',
  (select party_id from pg_temp.party_results where probe = 'person-first')
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_reveal_party_identifier(
        '10000000-0000-4000-8000-000000000001', %L,
        'CRM-only user must not reveal restricted values',
        'crm-reveal-denied-028',
        '70900000-0000-4000-8000-000000000028'
      )
    $sql$,
    (select entity_id from pg_temp.entity_results where probe = 'identifier-v2')
  ),
  '42501',
  'active workspace membership and permission are required',
  'T-RBAC-001 CRM read does not grant restricted identifier reveal'
);
reset role;

select extensions.ok(
  (
    select projection.identifiers @> pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'identifierId',
        (select entity_id from pg_temp.entity_results where probe = 'identifier-v2'),
        'identifierType', 'government.synthetic',
        'jurisdiction', 'CA-QC',
        'maskedValue', '********9002'
      )
    )
      and projection.identifiers::text not like '%SYNTHETIC-ID-%'
      and projection.identifiers::text not like '%encrypted_value%'
    from pg_temp.party_projection projection
  ),
  'T-AUTH-002 ordinary CRM projection exposes only the active masked identifier'
);
select extensions.ok(
  (
    select contacts @> '[{"contactType":"email","consentStatus":"granted"}]'::jsonb
      and addresses @> '[{"addressType":"mailing","countryCode":"CA"}]'::jsonb
      and profile ->> 'givenName' = 'Synthetic'
      and profile ->> 'familyName' = 'Person'
    from pg_temp.party_projection
  ),
  'application get-party projection has exact profile/contact/address JSON shapes'
);

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'aal1'
);
set local role authenticated;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_reveal_party_identifier(
        '10000000-0000-4000-8000-000000000001', %L,
        'AAL1 reveal must fail', 'crm-reveal-aal1-028',
        '71000000-0000-4000-8000-000000000028'
      )
    $sql$,
    (select entity_id from pg_temp.entity_results where probe = 'identifier-v2')
  ),
  '42501',
  'active workspace membership and permission are required',
  'T-AUTH-002 an AAL1 administrator session cannot reveal restricted identifiers'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.identifier_reveal
select * from app.m3_reveal_party_identifier(
  '10000000-0000-4000-8000-000000000001',
  (select entity_id from pg_temp.entity_results where probe = 'identifier-v2'),
  'Synthetic acceptance verification', 'crm-reveal-ok-028',
  '71100000-0000-4000-8000-000000000028'
);
reset role;

select extensions.is(
  (select plaintext_value from pg_temp.identifier_reveal),
  'SYNTHETIC-ID-9002',
  'T-AUTH-002 explicit authorized reveal decrypts the selected identifier'
);
select extensions.ok(
  exists (
    select 1
    from public.audit_events audit
    where audit.id = (select audit_event_id from pg_temp.identifier_reveal)
      and audit.action = 'party.identifier_revealed'
      and audit.after_data ->> 'masked_value' = '********9002'
      and audit.after_data::text not like '%SYNTHETIC-ID-%'
  ),
  'T-AUD-001 identifier reveal is audited without plaintext'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.entity_results
select 'preference-first', result.*
from app.m3_set_party_communication_preference(
  '10000000-0000-4000-8000-000000000001',
  'crm-preference-028',
  (select party_id from pg_temp.party_results where probe = 'person-first'),
  (
    select version from public.parties
    where id = (
      select party_id from pg_temp.party_results where probe = 'person-first'
    )
  ),
  'marketing.email', false, true, 'withdrawn',
  'Synthetic opt-out request', 'crm-preference-028',
  '71200000-0000-4000-8000-000000000028'
) result;
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_update_party(
        '10000000-0000-4000-8000-000000000001',
        'crm-update-stale-028', %L, 1,
        'Stale Synthetic Person', 'en', 'Synthetic', 'Person', 'Syn',
        date '1990-01-02', null, null, 'crm-update-stale-028',
        '71300000-0000-4000-8000-000000000028'
      )
    $sql$,
    (select party_id from pg_temp.party_results where probe = 'person-first')
  ),
  '40001',
  'party version conflict',
  'T-CRM-001 stale expected aggregate version fails optimistically'
);
insert into pg_temp.party_results
select 'person-update', result.*
from app.m3_update_party(
  '10000000-0000-4000-8000-000000000001',
  'crm-update-valid-028',
  (select party_id from pg_temp.party_results where probe = 'person-first'),
  (
    select version from public.parties
    where id = (
      select party_id from pg_temp.party_results where probe = 'person-first'
    )
  ),
  'Synthetic Person Updated', 'fr', 'Synthetic', 'Updated', 'Syn',
  date '1990-01-02', null, null, 'crm-update-valid-028',
  '71310000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.party_results
select 'person-update-replay', result.*
from app.m3_update_party(
  '10000000-0000-4000-8000-000000000001',
  'crm-update-valid-028',
  (select party_id from pg_temp.party_results where probe = 'person-first'),
  (
    select aggregate_version from pg_temp.party_results
    where probe = 'person-update'
  ) - 1,
  'Synthetic Person Updated', 'fr', 'Synthetic', 'Updated', 'Syn',
  date '1990-01-02', null, null, 'crm-update-valid-028',
  '71310000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.party_results
select 'organization-archive', result.*
from app.m3_archive_party(
  '10000000-0000-4000-8000-000000000001',
  'crm-archive-valid-028',
  (select party_id from pg_temp.party_results where probe = 'organization-first'),
  1, 'Synthetic duplicate organization', 'crm-archive-valid-028',
  '71320000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.party_results
select 'organization-archive-replay', result.*
from app.m3_archive_party(
  '10000000-0000-4000-8000-000000000001',
  'crm-archive-valid-028',
  (select party_id from pg_temp.party_results where probe = 'organization-first'),
  1, 'Synthetic duplicate organization', 'crm-archive-valid-028',
  '71320000-0000-4000-8000-000000000028'
) result;
reset role;

select extensions.ok(
  exists (
    select 1
    from public.party_communication_preferences preference
    where preference.id = (
      select entity_id from pg_temp.entity_results where probe = 'preference-first'
    )
      and preference.channel_key = 'marketing.email'
      and not preference.allowed
      and preference.do_not_contact
      and preference.consent_status = 'withdrawn'
      and preference.consent_source = 'Synthetic opt-out request'
  ),
  'T-CRM-001 versioned communication preference persists do-not-contact state'
);
select extensions.ok(
  exists (
    select 1
    from public.parties party
    join public.party_person_profiles profile
      on profile.workspace_id = party.workspace_id
     and profile.party_id = party.id
    where party.id = (
      select party_id from pg_temp.party_results where probe = 'person-first'
    )
      and party.display_name = 'Synthetic Person Updated'
      and profile.family_name = 'Updated'
      and profile.preferred_locale = 'fr'
  ),
  'T-CRM-001 optimistic party update persists the matching typed profile'
);
select extensions.ok(
  (select replayed from pg_temp.party_results where probe = 'person-update-replay')
    and (
      select aggregate_version from pg_temp.party_results
      where probe = 'person-update'
    ) = (
      select aggregate_version from pg_temp.party_results
      where probe = 'person-update-replay'
    ),
  'T-CRM-001 party update replay returns stable actor-scoped evidence'
);
select extensions.ok(
  exists (
    select 1 from public.parties party
    where party.id = (
      select party_id from pg_temp.party_results
      where probe = 'organization-first'
    )
      and party.status = 'archived'
      and party.version = 2
  ),
  'T-CRM-001 archive is a versioned lifecycle command instead of hard delete'
);
select extensions.ok(
  (select replayed from pg_temp.party_results
    where probe = 'organization-archive-replay')
    and (
      select aggregate_version from pg_temp.party_results
      where probe = 'organization-archive'
    ) = (
      select aggregate_version from pg_temp.party_results
      where probe = 'organization-archive-replay'
    ),
  'T-CRM-001 party archive replay returns stable actor-scoped evidence'
);
set local role authenticated;
select extensions.ok(
  exists (
    select 1
    from app.m3_get_party(
      '10000000-0000-4000-8000-000000000001',
      (select party_id from pg_temp.party_results where probe = 'person-first')
    ) projection
    where pg_catalog.jsonb_array_length(projection.relationships) = 1
      and projection.relationships -> 0 ->> 'relationshipType'
        = 'employment.employer'
      and pg_catalog.jsonb_array_length(projection.preferences) = 1
      and projection.preferences -> 0 ->> 'channelKey' = 'marketing.email'
      and (projection.preferences -> 0 ->> 'doNotContact')::boolean
  ),
  'T-CRM-001 party detail returns active relationships and preferences'
);
reset role;

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.party_results
select 'workspace-b-person', result.*
from app.m3_create_party(
  '20000000-0000-4000-8000-000000000002',
  'crm-workspace-b-028', 'person', 'Other Workspace Person', 'fr',
  'Other', 'Person', null, null, null, null,
  'crm-workspace-b-028', '71400000-0000-4000-8000-000000000028'
) result;
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.parties party
    where party.workspace_id = '20000000-0000-4000-8000-000000000002'
  ),
  0,
  'T-TEN-001 forced RLS hides other-workspace parties'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.legal_entities entity
    where entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      and entity.status = 'active'
  ),
  1,
  'T-TEN-001 legal-entity RLS exposes only the caller workspace fixture'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_get_party(
        '20000000-0000-4000-8000-000000000002', %L
      )
    $sql$,
    (select party_id from pg_temp.party_results where probe = 'workspace-b-person')
  ),
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 cross-workspace get-party fails before data lookup'
);
select extensions.throws_ok(
  pg_catalog.format(
    $sql$
      select * from app.m3_add_party_relationship(
        '10000000-0000-4000-8000-000000000001',
        'crm-cross-workspace-028', %L, %L, 'household.member', null, null,
        'crm-cross-workspace-028',
        '71500000-0000-4000-8000-000000000028'
      )
    $sql$,
    (select party_id from pg_temp.party_results where probe = 'person-first'),
    (select party_id from pg_temp.party_results where probe = 'workspace-b-person')
  ),
  '23514',
  'related party must be active in the same workspace',
  'T-TEN-001 relationship RPC rejects an other-workspace party ID'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legacy_results
select 'actor-a-first', result.*
from app.create_party(
  '10000000-0000-4000-8000-000000000001',
  'legacy-shared-key-028', 'organization', 'Actor A Legacy Party',
  'legacy-actor-a-028', '71600000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.legacy_results
select 'actor-a-replay', result.*
from app.create_party(
  '10000000-0000-4000-8000-000000000001',
  'legacy-shared-key-028', 'organization', 'Actor A Legacy Party',
  'legacy-actor-a-028', '71600000-0000-4000-8000-000000000028'
) result;
insert into pg_temp.legacy_results
select 'actor-a-person', result.*
from app.create_party(
  '10000000-0000-4000-8000-000000000001',
  'legacy-person-key-028', 'person', 'Alex Legacy Example',
  'legacy-person-028', '71800000-0000-4000-8000-000000000028'
) result;
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
insert into pg_temp.legacy_results
select 'actor-c-first', result.*
from app.create_party(
  '10000000-0000-4000-8000-000000000001',
  'legacy-shared-key-028', 'organization', 'Actor C Legacy Party',
  'legacy-actor-c-028', '71700000-0000-4000-8000-000000000028'
) result;
reset role;

select extensions.ok(
  (select replayed from pg_temp.legacy_results where probe = 'actor-a-replay')
    and (
      select party_id from pg_temp.legacy_results where probe = 'actor-a-first'
    ) = (
      select party_id from pg_temp.legacy_results where probe = 'actor-a-replay'
    ),
  'T-CRM-001 legacy same-actor replay returns the original party'
);
select extensions.ok(
  not (select replayed from pg_temp.legacy_results where probe = 'actor-c-first')
    and (
      select party_id from pg_temp.legacy_results where probe = 'actor-a-first'
    ) <> (
      select party_id from pg_temp.legacy_results where probe = 'actor-c-first'
    ),
  'T-TEN-001 a second actor may reuse the raw key without another actor replay'
);
select extensions.is(
  (
    select pg_catalog.count(distinct party.idempotency_actor_user_id)::integer
    from public.parties party
    where party.workspace_id = '10000000-0000-4000-8000-000000000001'
      and party.idempotency_key = 'legacy-shared-key-028'
  ),
  2,
  'T-CRM-001 legacy raw key ownership is persisted for both actors'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from public.party_organization_profiles profile
    join pg_temp.legacy_results result on result.party_id = profile.party_id
    where result.probe in ('actor-a-first', 'actor-c-first')
      and profile.legal_name in ('Actor A Legacy Party', 'Actor C Legacy Party')
      and profile.preferred_locale in ('en', 'fr')
  ),
  2,
  'T-CRM-001 legacy organization creates materialize typed profiles atomically'
);
select extensions.ok(
  exists (
    select 1
    from public.party_person_profiles profile
    join pg_temp.legacy_results result on result.party_id = profile.party_id
    where result.probe = 'actor-a-person'
      and profile.given_name = 'Alex'
      and profile.family_name = 'Legacy Example'
      and profile.preferred_locale in ('en', 'fr')
  ),
  'T-CRM-001 legacy person creates deterministically split a typed profile'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  (
    select profile ->> 'legalName' = 'Actor A Legacy Party'
    from app.m3_get_party(
      '10000000-0000-4000-8000-000000000001',
      (select party_id from pg_temp.legacy_results where probe = 'actor-a-first')
    )
  ) and (
    select profile ->> 'givenName' = 'Alex'
      and profile ->> 'familyName' = 'Legacy Example'
    from app.m3_get_party(
      '10000000-0000-4000-8000-000000000001',
      (select party_id from pg_temp.legacy_results where probe = 'actor-a-person')
    )
  ),
  'T-CRM-001 legacy create results remain readable through typed M3 detail'
);
reset role;

select extensions.throws_ok(
  pg_catalog.format(
    'delete from public.parties where id = %L',
    (select party_id from pg_temp.party_results where probe = 'person-first')
  ),
  '55000',
  'hard delete is prohibited for parties',
  'T-CRM-001 parties cannot be hard deleted'
);
select extensions.throws_ok(
  pg_catalog.format(
    'delete from public.party_contacts where id = %L',
    (select entity_id from pg_temp.entity_results where probe = 'contact-first')
  ),
  '55000',
  'party history is append-only',
  'T-CRM-001 versioned contact history cannot be hard deleted'
);
select extensions.throws_ok(
  $$
    delete from public.legal_entities
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and key = 'primary'
  $$,
  '55000',
  'legal entities cannot be hard deleted',
  'T-CRM-001 legal entities cannot be hard deleted'
);
select extensions.throws_ok(
  $$
    update public.legal_entities
    set legal_names = '{"en":"Changed","fr":"Change"}'::jsonb
    where workspace_id = '10000000-0000-4000-8000-000000000001'
      and key = 'primary'
  $$,
  '55000',
  'legal entity versions are immutable except for retirement',
  'T-CRM-001 active legal-entity configuration is immutable'
);

select extensions.ok(
  not exists (
    select 1
    from public.audit_events audit
    where audit.action in (
      'party.identifier_replaced', 'party.identifier_revealed'
    )
      and (
        coalesce(audit.before_data, '{}'::jsonb)::text like '%SYNTHETIC-ID-%'
        or coalesce(audit.after_data, '{}'::jsonb)::text like '%SYNTHETIC-ID-%'
        or coalesce(audit.metadata, '{}'::jsonb)::text like '%SYNTHETIC-ID-%'
      )
  ) and not exists (
    select 1
    from public.outbox_events event
    where event.event_name = 'party.identifier_replaced'
      and event.payload::text like '%SYNTHETIC-ID-%'
  ),
  'T-AUD-001 identifier audit/outbox payloads never contain plaintext'
);
select extensions.ok(
  not exists (
    select 1
    from pg_temp.party_results result
    where result.probe not like '%replay'
      and (
        not exists (
          select 1 from public.audit_events audit
          where audit.id = result.audit_event_id
            and audit.workspace_id in (
              '10000000-0000-4000-8000-000000000001',
              '20000000-0000-4000-8000-000000000002'
            )
        )
        or not exists (
          select 1 from public.outbox_events event
          where event.id = result.outbox_event_id
            and event.aggregate_id = result.party_id
            and event.aggregate_version = result.aggregate_version
        )
      )
  ) and not exists (
    select 1
    from pg_temp.entity_results result
    where not exists (
      select 1 from public.audit_events audit
      where audit.id = result.audit_event_id
    ) or not exists (
      select 1 from public.outbox_events event
      where event.id = result.outbox_event_id
        and event.aggregate_id = result.party_id
        and event.aggregate_version = result.aggregate_version
    )
  ),
  'T-AUD-001 every tested write returns matching audit and outbox evidence'
);
select extensions.ok(
  exists (
    select 1
    from public.outbox_events event
    join pg_temp.legacy_results result on result.probe = 'actor-a-first'
      and event.aggregate_id = result.party_id
    where event.event_name = 'party.created'
      and event.payload ->> 'api' = 'legacy'
  ),
  'T-AUD-001 legacy create compatibility now writes transactional outbox evidence'
);

select * from extensions.finish();
rollback;
