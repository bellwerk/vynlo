-- VYN-CFG-001, VYN-WF-001, VYN-DEAL-001, VYN-FIN-001, VYN-PAY-001,
-- VYN-TEN-001, VYN-SEC-001, STD-DEAL-001, T-CFG-001, T-CFG-002,
-- T-CFG-004, T-CFG-005, T-CFG-006, T-WF-001, T-DEAL-001, T-FIN-001,
-- T-PAY-001, T-TEN-001, T-RBAC-001
-- M3-WF-AC-001, M3-DEAL-AC-001, M3-FIN-AC-001, M3-PAY-AC-001
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(40);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.roles role
    where role.source = 'pack'
      and role.key::text in (
        'owner_admin', 'manager', 'sales', 'inventory', 'read_only'
      )
  ),
  10::bigint,
  'STD-DEAL-001 installs five starter roles in each synthetic workspace'
);

select extensions.results_eq(
  $$
    select
      role.workspace_id::text,
      role.key::text,
      pg_catalog.count(role_permission.id)::bigint
    from public.roles role
    left join public.role_permissions role_permission
      on role_permission.workspace_id = role.workspace_id
     and role_permission.role_id = role.id
     and role_permission.status = 'active'
    where role.source = 'pack'
      and role.key::text in (
        'owner_admin', 'manager', 'sales', 'inventory', 'read_only'
      )
    group by role.workspace_id, role.key
    order by role.workspace_id, role.key
  $$,
  $$
    values
      ('10000000-0000-4000-8000-000000000001'::text, 'inventory'::text, 23::bigint),
      ('10000000-0000-4000-8000-000000000001'::text, 'manager'::text, 65::bigint),
      ('10000000-0000-4000-8000-000000000001'::text, 'owner_admin'::text, 79::bigint),
      ('10000000-0000-4000-8000-000000000001'::text, 'read_only'::text, 23::bigint),
      ('10000000-0000-4000-8000-000000000001'::text, 'sales'::text, 32::bigint),
      ('20000000-0000-4000-8000-000000000002'::text, 'inventory'::text, 23::bigint),
      ('20000000-0000-4000-8000-000000000002'::text, 'manager'::text, 65::bigint),
      ('20000000-0000-4000-8000-000000000002'::text, 'owner_admin'::text, 79::bigint),
      ('20000000-0000-4000-8000-000000000002'::text, 'read_only'::text, 23::bigint),
      ('20000000-0000-4000-8000-000000000002'::text, 'sales'::text, 32::bigint)
  $$,
  'T-RBAC-001 runtime role grant counts match the exact explicit pack grants'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.role_permissions role_permission
    join public.roles role
      on role.workspace_id = role_permission.workspace_id
     and role.id = role_permission.role_id
    where role.source = 'pack'
      and role_permission.status = 'active'
  ),
  444::bigint,
  'starter roles persist all 222 explicit grants in both workspaces'
);

select extensions.ok(
  not exists (
    select 1
    from public.role_permissions role_permission
    join public.roles role
      on role.workspace_id = role_permission.workspace_id
     and role.id = role_permission.role_id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role.source = 'pack'
      and role_permission.status = 'active'
      and (
        permission.workspace_id is not null
        or permission.source <> 'platform'
        or permission.status <> 'active'
        or permission.key like '%*%'
      )
  ),
  'T-RBAC-001 starter roles grant only active immutable platform permission keys'
);

select extensions.ok(
  not exists (
    select 1
    from public.roles role
    where role.source = 'pack'
      and role.requires_mfa is distinct from (role.key::text = 'owner_admin')
  ),
  'workspace administrators require MFA without broadening other starter roles'
);

select extensions.ok(
  not exists (
    select 1
    from public.membership_roles membership_role
    join public.roles role
      on role.workspace_id = membership_role.workspace_id
     and role.id = membership_role.role_id
    where role.source = 'pack'
  ),
  'starter installation preserves synthetic membership assignments'
);

select extensions.ok(
  not exists (
    (
      select role.key::text, role.status, role.requires_mfa, role.source
      from public.roles role
      where role.workspace_id = '10000000-0000-4000-8000-000000000001'
        and role.source = 'pack'
      except
      select role.key::text, role.status, role.requires_mfa, role.source
      from public.roles role
      where role.workspace_id = '20000000-0000-4000-8000-000000000002'
        and role.source = 'pack'
    )
    union all
    (
      select role.key::text, role.status, role.requires_mfa, role.source
      from public.roles role
      where role.workspace_id = '20000000-0000-4000-8000-000000000002'
        and role.source = 'pack'
      except
      select role.key::text, role.status, role.requires_mfa, role.source
      from public.roles role
      where role.workspace_id = '10000000-0000-4000-8000-000000000001'
        and role.source = 'pack'
    )
  ),
  'T-TEN-001 starter role contracts have cross-workspace parity'
);

select extensions.ok(
  not exists (
    (
      select role.key::text, permission.key
      from public.roles role
      join public.role_permissions role_permission
        on role_permission.workspace_id = role.workspace_id
       and role_permission.role_id = role.id
       and role_permission.status = 'active'
      join public.permissions permission on permission.id = role_permission.permission_id
      where role.workspace_id = '10000000-0000-4000-8000-000000000001'
        and role.source = 'pack'
      except
      select role.key::text, permission.key
      from public.roles role
      join public.role_permissions role_permission
        on role_permission.workspace_id = role.workspace_id
       and role_permission.role_id = role.id
       and role_permission.status = 'active'
      join public.permissions permission on permission.id = role_permission.permission_id
      where role.workspace_id = '20000000-0000-4000-8000-000000000002'
        and role.source = 'pack'
    )
    union all
    (
      select role.key::text, permission.key
      from public.roles role
      join public.role_permissions role_permission
        on role_permission.workspace_id = role.workspace_id
       and role_permission.role_id = role.id
       and role_permission.status = 'active'
      join public.permissions permission on permission.id = role_permission.permission_id
      where role.workspace_id = '20000000-0000-4000-8000-000000000002'
        and role.source = 'pack'
      except
      select role.key::text, permission.key
      from public.roles role
      join public.role_permissions role_permission
        on role_permission.workspace_id = role.workspace_id
       and role_permission.role_id = role.id
       and role_permission.status = 'active'
      join public.permissions permission on permission.id = role_permission.permission_id
      where role.workspace_id = '10000000-0000-4000-8000-000000000001'
        and role.source = 'pack'
    )
  ),
  'starter role permission grants have cross-workspace parity'
);

select extensions.results_eq(
  $$
    select
      role.key::text,
      pg_catalog.array_agg(permission.key order by permission.key)::text[]
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.workspace_id = role.workspace_id
     and role_permission.role_id = role.id
     and role_permission.status = 'active'
    join public.permissions permission on permission.id = role_permission.permission_id
    where role.workspace_id = '10000000-0000-4000-8000-000000000001'
      and role.source = 'pack'
      and role.key::text in ('owner_admin', 'manager', 'sales')
      and (
        permission.key like 'finance_applications.%'
        or permission.key like 'payments.%'
        or permission.key like 'workflow.%'
      )
    group by role.key
    order by role.key
  $$,
  $$
    values
      (
        'manager'::text,
        array[
          'finance_applications.create', 'finance_applications.read',
          'finance_applications.update', 'payments.read', 'payments.record',
          'payments.refund', 'payments.reverse', 'payments.settle', 'workflow.read'
        ]::text[]
      ),
      (
        'owner_admin'::text,
        array[
          'finance_applications.create', 'finance_applications.read',
          'finance_applications.update', 'payments.read', 'payments.record',
          'payments.refund', 'payments.reverse', 'payments.settle',
          'workflow.activate', 'workflow.read'
        ]::text[]
      ),
      (
        'sales'::text,
        array[
          'finance_applications.create', 'finance_applications.read',
          'finance_applications.update', 'payments.read', 'payments.record',
          'payments.settle', 'workflow.read'
        ]::text[]
      )
  $$,
  'finance, payment, and workflow permission grants are explicit per role'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workspace_feature_entitlements entitlement
    where entitlement.entitlement_key in (
      'crm', 'deals', 'third_party_finance', 'one_time_payments',
      'custom_workflows'
    )
  ),
  10::bigint,
  'T-CFG-005 installs five M3 entitlements in each synthetic workspace'
);

select extensions.results_eq(
  $$
    select entitlement.entitlement_key, pg_catalog.count(*)::bigint
    from public.workspace_feature_entitlements entitlement
    where entitlement.entitlement_key in (
      'crm', 'deals', 'third_party_finance', 'one_time_payments',
      'custom_workflows'
    )
      and entitlement.status = 'active'
      and entitlement.enabled
    group by entitlement.entitlement_key
    order by entitlement.entitlement_key
  $$,
  $$
    values
      ('crm'::text, 2::bigint),
      ('custom_workflows'::text, 2::bigint),
      ('deals'::text, 2::bigint),
      ('one_time_payments'::text, 2::bigint),
      ('third_party_finance'::text, 2::bigint)
  $$,
  'all required M3 entitlements are active in both workspaces'
);

select extensions.ok(
  not exists (
    select 1
    from public.deal_type_versions version
    cross join lateral (
      values
        ('participant_roles'::text, pg_catalog.to_jsonb(version.allowed_participant_roles)),
        ('inventory_roles'::text, pg_catalog.to_jsonb(version.allowed_inventory_roles)),
        (
          'one_time_event_types'::text,
          coalesce(version.behavior_flags -> 'one_time_event_types', '[]'::jsonb)
        )
    ) configured(group_key, configured_keys)
    where version.source = 'starter_pack'
      and version.status = 'active'
      and (
        pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(version.option_labels, '$.keyvalue()')) <> 3
        or pg_catalog.jsonb_typeof(
          version.option_labels -> configured.group_key
        ) <> 'object'
        or pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(version.option_labels -> configured.group_key, '$.keyvalue()')) <> pg_catalog.jsonb_array_length(configured.configured_keys)
        or exists (
          select 1
          from pg_catalog.jsonb_array_elements_text(
            configured.configured_keys
          ) configured_key(value)
          where not (
            version.option_labels -> configured.group_key
              ? configured_key.value
          )
        )
        or exists (
          select 1
          from pg_catalog.jsonb_each(
            version.option_labels -> configured.group_key
          ) localized(key, labels)
          where pg_catalog.jsonb_typeof(localized.labels) <> 'object'
            or pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(localized.labels, '$.keyvalue()')) <> 2
            or not (localized.labels ?& array['en', 'fr'])
            or pg_catalog.btrim(localized.labels ->> 'en') = ''
            or pg_catalog.btrim(localized.labels ->> 'fr') = ''
        )
      )
  ),
  'M3-DEAL-AC-001 starter deal options exactly cover configured keys with bilingual labels'
);

select extensions.ok(
  (
    select pg_catalog.bool_and(
      entitlement.version = 1
      and entitlement.status = 'active'
      and entitlement.enabled
      and entitlement.limits = '{}'::jsonb
      and entitlement.effective_until is null
      and entitlement.provenance @> '{
        "source":"starter_pack",
        "pack_id":"starter-retail-dealer",
        "pack_version":"1.1.0"
      }'::jsonb
    )
    from public.workspace_feature_entitlements entitlement
    where entitlement.entitlement_key in (
      'crm', 'deals', 'third_party_finance', 'one_time_payments',
      'custom_workflows'
    )
  ),
  'T-CFG-004 M3 entitlement versions are immutable active starter records'
);

select extensions.ok(
  (
    select pg_catalog.bool_and(
      entitlement.checksum = app.entitlement_payload_checksum(
        entitlement.enabled,
        entitlement.limits
      )
    )
    from public.workspace_feature_entitlements entitlement
    where entitlement.entitlement_key in (
      'crm', 'deals', 'third_party_finance', 'one_time_payments',
      'custom_workflows'
    )
  ),
  'T-CFG-002 every M3 entitlement stores its exact canonical checksum'
);

select extensions.ok(
  not exists (
    (
      select
        entitlement.entitlement_key,
        entitlement.version,
        entitlement.status,
        entitlement.enabled,
        entitlement.limits,
        entitlement.checksum,
        entitlement.provenance,
        entitlement.effective_from,
        entitlement.effective_until
      from public.workspace_feature_entitlements entitlement
      where entitlement.workspace_id = '10000000-0000-4000-8000-000000000001'
        and entitlement.entitlement_key in (
          'crm', 'deals', 'third_party_finance', 'one_time_payments',
          'custom_workflows'
        )
      except
      select
        entitlement.entitlement_key,
        entitlement.version,
        entitlement.status,
        entitlement.enabled,
        entitlement.limits,
        entitlement.checksum,
        entitlement.provenance,
        entitlement.effective_from,
        entitlement.effective_until
      from public.workspace_feature_entitlements entitlement
      where entitlement.workspace_id = '20000000-0000-4000-8000-000000000002'
        and entitlement.entitlement_key in (
          'crm', 'deals', 'third_party_finance', 'one_time_payments',
          'custom_workflows'
        )
    )
    union all
    (
      select
        entitlement.entitlement_key,
        entitlement.version,
        entitlement.status,
        entitlement.enabled,
        entitlement.limits,
        entitlement.checksum,
        entitlement.provenance,
        entitlement.effective_from,
        entitlement.effective_until
      from public.workspace_feature_entitlements entitlement
      where entitlement.workspace_id = '20000000-0000-4000-8000-000000000002'
        and entitlement.entitlement_key in (
          'crm', 'deals', 'third_party_finance', 'one_time_payments',
          'custom_workflows'
        )
      except
      select
        entitlement.entitlement_key,
        entitlement.version,
        entitlement.status,
        entitlement.enabled,
        entitlement.limits,
        entitlement.checksum,
        entitlement.provenance,
        entitlement.effective_from,
        entitlement.effective_until
      from public.workspace_feature_entitlements entitlement
      where entitlement.workspace_id = '10000000-0000-4000-8000-000000000001'
        and entitlement.entitlement_key in (
          'crm', 'deals', 'third_party_finance', 'one_time_payments',
          'custom_workflows'
        )
    )
  ),
  'T-TEN-001 M3 entitlement payloads have cross-workspace parity'
);

select extensions.ok(
  pg_catalog.to_regclass('public.feature_flags') is null,
  'T-CFG-006 no feature-flag table substitutes for M3 entitlements'
);

select extensions.results_eq(
  $$
    select legal_entity.workspace_id::text, pg_catalog.count(*)::bigint
    from public.legal_entities legal_entity
    where legal_entity.status = 'active'
    group by legal_entity.workspace_id
    order by legal_entity.workspace_id
  $$,
  $$
    values
      ('10000000-0000-4000-8000-000000000001'::text, 1::bigint),
      ('20000000-0000-4000-8000-000000000002'::text, 1::bigint)
  $$,
  'M3-DEAL-AC-001 installs exactly one active legal entity per workspace'
);

select extensions.ok(
  not exists (
    (
      select
        legal_entity.key,
        legal_entity.legal_names,
        legal_entity.display_names,
        legal_entity.organization_party_id,
        legal_entity.status,
        legal_entity.version
      from public.legal_entities legal_entity
      where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      except
      select
        legal_entity.key,
        legal_entity.legal_names,
        legal_entity.display_names,
        legal_entity.organization_party_id,
        legal_entity.status,
        legal_entity.version
      from public.legal_entities legal_entity
      where legal_entity.workspace_id = '20000000-0000-4000-8000-000000000002'
    )
    union all
    (
      select
        legal_entity.key,
        legal_entity.legal_names,
        legal_entity.display_names,
        legal_entity.organization_party_id,
        legal_entity.status,
        legal_entity.version
      from public.legal_entities legal_entity
      where legal_entity.workspace_id = '20000000-0000-4000-8000-000000000002'
      except
      select
        legal_entity.key,
        legal_entity.legal_names,
        legal_entity.display_names,
        legal_entity.organization_party_id,
        legal_entity.status,
        legal_entity.version
      from public.legal_entities legal_entity
      where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
    )
  ),
  'T-TEN-001 starter legal-entity payloads have cross-workspace parity'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workflow_definitions definition
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
  ),
  4::bigint,
  'M3-WF-AC-001 installs lead and deal definitions per workspace'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workflow_versions version
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
  ),
  4::bigint,
  'M3-WF-AC-001 installs one immutable lead/deal version per workspace'
);

select extensions.results_eq(
  $$
    select
      definition.key::text,
      version.workspace_id::text,
      version.version,
      version.revision,
      version.initial_state_key,
      version.status,
      version.checksum,
      version.source
    from public.workflow_versions version
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
    order by definition.key, version.workspace_id
  $$,
  $$
    values
      (
        'lead_standard'::text,
        '10000000-0000-4000-8000-000000000001'::text,
        '1.0.0'::text,
        1::bigint,
        'new'::text,
        'active'::text,
        'db26b119c9d463594ee3ed4569b3aa647c51a6ed956eb2e7c79244a857c0531b'::text,
        'starter_pack'::text
      ),
      (
        'lead_standard'::text,
        '20000000-0000-4000-8000-000000000002'::text,
        '1.0.0'::text,
        1::bigint,
        'new'::text,
        'active'::text,
        'db26b119c9d463594ee3ed4569b3aa647c51a6ed956eb2e7c79244a857c0531b'::text,
        'starter_pack'::text
      ),
      (
        'retail_deal_standard'::text,
        '10000000-0000-4000-8000-000000000001'::text,
        '1.0.0'::text,
        1::bigint,
        'draft'::text,
        'active'::text,
        '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214'::text,
        'starter_pack'::text
      ),
      (
        'retail_deal_standard'::text,
        '20000000-0000-4000-8000-000000000002'::text,
        '1.0.0'::text,
        1::bigint,
        'draft'::text,
        'active'::text,
        '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214'::text,
        'starter_pack'::text
      )
  $$,
  'T-CFG-002 workflow versions bind exact lead/deal YAML byte checksums'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.deal_type_definitions definition
    where definition.key::text in (
      'retail.cash',
      'retail.third_party_financed',
      'wholesale.sale',
      'purchase.vehicle',
      'acquisition.trade_in'
    )
      and definition.status = 'active'
  ),
  10::bigint,
  'STD-DEAL-001 installs five active deal-type definitions per workspace'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.deal_type_versions version
    join public.deal_type_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.deal_type_definition_id
    where definition.key::text in (
      'retail.cash',
      'retail.third_party_financed',
      'wholesale.sale',
      'purchase.vehicle',
      'acquisition.trade_in'
    )
      and version.status = 'active'
      and version.source = 'starter_pack'
  ),
  10::bigint,
  'M3-DEAL-AC-001 installs one active immutable starter version per definition'
);

select extensions.results_eq(
  $$
    select
      definition.key::text,
      version.labels,
      version.field_schema,
      version.allowed_participant_roles,
      version.allowed_inventory_roles,
      version.behavior_flags,
      workflow_definition.key::text,
      workflow_version.version,
      workflow_version.checksum
    from public.deal_type_versions version
    join public.deal_type_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.deal_type_definition_id
    join public.workflow_versions workflow_version
      on workflow_version.workspace_id = version.workspace_id
     and workflow_version.id = version.workflow_version_id
    join public.workflow_definitions workflow_definition
      on workflow_definition.workspace_id = workflow_version.workspace_id
     and workflow_definition.id = workflow_version.workflow_definition_id
    where version.workspace_id = '10000000-0000-4000-8000-000000000001'
      and version.status = 'active'
      and version.source = 'starter_pack'
    order by definition.key
  $$,
  $$
    values
      (
        'acquisition.trade_in'::text,
        '{"en":"Trade-in acquisition","fr":"Acquisition d''un véhicule d''échange"}'::jsonb,
        '{"required":["trade_in_owner_party_id","trade_in_inventory_unit_id","currency_code"],"optional":["lender_party_id","lien_payoff_minor","lien_payoff_currency","authorized_representative_party_id","ownership_details","condition","odometer","tax_eligibility_inputs","notes"]}'::jsonb,
        array['trade_in_owner','dealer_buyer','lender','authorized_representative']::text[],
        array['trade_in']::text[],
        '{"inventory_direction":"inbound","inventory_creation":"explicit_confirmation","finance_mode":"none","money_mode":"one_time","one_time_event_types":["trade_in_credit","balance_received"]}'::jsonb,
        'retail_deal_standard'::text,
        '1.0.0'::text,
        '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214'::text
      ),
      (
        'purchase.vehicle'::text,
        '{"en":"Vehicle purchase","fr":"Achat de véhicule"}'::jsonb,
        '{"required":["seller_party_id","purchased_inventory_unit_id","currency_code"],"optional":["authorized_representative_party_id","ownership_details","condition","odometer","notes"]}'::jsonb,
        array['seller','dealer_buyer','authorized_representative']::text[],
        array['purchased']::text[],
        '{"inventory_direction":"inbound","inventory_creation":"explicit_confirmation","finance_mode":"none","money_mode":"one_time","one_time_event_types":["receipt","balance_received"]}'::jsonb,
        'retail_deal_standard'::text,
        '1.0.0'::text,
        '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214'::text
      ),
      (
        'retail.cash'::text,
        '{"en":"Cash retail","fr":"Vente au détail au comptant"}'::jsonb,
        '{"required":["buyer_party_id","sold_inventory_unit_id","currency_code"],"optional":["trade_in_owner_party_id","trade_in_inventory_unit_id","authorized_representative_party_id","notes"]}'::jsonb,
        array['buyer','seller','trade_in_owner','authorized_representative']::text[],
        array['sold','trade_in']::text[],
        '{"inventory_direction":"outbound","inventory_creation":"none","finance_mode":"none","money_mode":"one_time","one_time_event_types":["deposit","receipt","balance_received","trade_in_credit"]}'::jsonb,
        'retail_deal_standard'::text,
        '1.0.0'::text,
        '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214'::text
      ),
      (
        'retail.third_party_financed'::text,
        '{"en":"Third-party-financed retail","fr":"Vente au détail financée par un tiers"}'::jsonb,
        '{"required":["buyer_party_id","sold_inventory_unit_id","lender_party_id","currency_code"],"optional":["trade_in_owner_party_id","trade_in_inventory_unit_id","authorized_representative_party_id","notes"]}'::jsonb,
        array['buyer','seller','lender','trade_in_owner','authorized_representative']::text[],
        array['sold','trade_in']::text[],
        '{"inventory_direction":"outbound","inventory_creation":"none","finance_mode":"external_lender_tracking","money_mode":"one_time","one_time_event_types":["deposit","receipt","balance_received","trade_in_credit","lender_proceeds"]}'::jsonb,
        'retail_deal_standard'::text,
        '1.0.0'::text,
        '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214'::text
      ),
      (
        'wholesale.sale'::text,
        '{"en":"Wholesale sale","fr":"Vente en gros"}'::jsonb,
        '{"required":["buyer_party_id","wholesale_inventory_unit_id","currency_code"],"optional":["authorized_representative_party_id","notes"]}'::jsonb,
        array['buyer','seller','authorized_representative']::text[],
        array['wholesale']::text[],
        '{"inventory_direction":"outbound","inventory_creation":"none","finance_mode":"none","money_mode":"one_time","one_time_event_types":["deposit","receipt","balance_received"]}'::jsonb,
        'retail_deal_standard'::text,
        '1.0.0'::text,
        '0855356701f9c095a7683a7e9813bc1cb55cd20f58376055e610b96d4b209214'::text
      )
  $$,
  'T-CFG-002 starter deal-type rows exactly mirror all five YAML artifacts'
);

select extensions.results_eq(
  $$
    select definition.key::text, version.option_labels
    from public.deal_type_versions version
    join public.deal_type_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.deal_type_definition_id
    where version.workspace_id = '10000000-0000-4000-8000-000000000001'
      and version.status = 'active'
      and version.source = 'starter_pack'
    order by definition.key
  $$,
  $$
    values
      (
        'acquisition.trade_in'::text,
        '{"participant_roles":{"trade_in_owner":{"en":"Trade-in owner","fr":"Propriétaire du véhicule d’échange"},"dealer_buyer":{"en":"Dealer buyer","fr":"Acheteur du concessionnaire"},"lender":{"en":"Lender","fr":"Prêteur"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{"trade_in_credit":{"en":"Trade-in credit","fr":"Crédit d’échange"},"balance_received":{"en":"Balance received","fr":"Solde reçu"}}}'::jsonb
      ),
      (
        'purchase.vehicle'::text,
        '{"participant_roles":{"seller":{"en":"Seller","fr":"Vendeur"},"dealer_buyer":{"en":"Dealer buyer","fr":"Acheteur du concessionnaire"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"purchased":{"en":"Purchased vehicle","fr":"Véhicule acheté"}},"one_time_event_types":{"receipt":{"en":"Receipt","fr":"Encaissement"},"balance_received":{"en":"Balance received","fr":"Solde reçu"}}}'::jsonb
      ),
      (
        'retail.cash'::text,
        '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"},"trade_in_owner":{"en":"Trade-in owner","fr":"Propriétaire du véhicule d’échange"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{"deposit":{"en":"Deposit","fr":"Dépôt"},"receipt":{"en":"Receipt","fr":"Encaissement"},"balance_received":{"en":"Balance received","fr":"Solde reçu"},"trade_in_credit":{"en":"Trade-in credit","fr":"Crédit d’échange"}}}'::jsonb
      ),
      (
        'retail.third_party_financed'::text,
        '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"},"lender":{"en":"Lender","fr":"Prêteur"},"trade_in_owner":{"en":"Trade-in owner","fr":"Propriétaire du véhicule d’échange"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"sold":{"en":"Sale vehicle","fr":"Véhicule vendu"},"trade_in":{"en":"Trade-in vehicle","fr":"Véhicule d’échange"}},"one_time_event_types":{"deposit":{"en":"Deposit","fr":"Dépôt"},"receipt":{"en":"Receipt","fr":"Encaissement"},"balance_received":{"en":"Balance received","fr":"Solde reçu"},"trade_in_credit":{"en":"Trade-in credit","fr":"Crédit d’échange"},"lender_proceeds":{"en":"Lender proceeds","fr":"Fonds du prêteur"}}}'::jsonb
      ),
      (
        'wholesale.sale'::text,
        '{"participant_roles":{"buyer":{"en":"Buyer","fr":"Acheteur"},"seller":{"en":"Seller","fr":"Vendeur"},"authorized_representative":{"en":"Authorized representative","fr":"Représentant autorisé"}},"inventory_roles":{"wholesale":{"en":"Wholesale vehicle","fr":"Véhicule de gros"}},"one_time_event_types":{"deposit":{"en":"Deposit","fr":"Dépôt"},"receipt":{"en":"Receipt","fr":"Encaissement"},"balance_received":{"en":"Balance received","fr":"Solde reçu"}}}'::jsonb
      )
  $$,
  'T-CFG-002 starter deal option labels exactly mirror every bilingual YAML choice'
);

select extensions.ok(
  (
    select pg_catalog.bool_and(
      version.checksum = app.deal_type_configuration_checksum(
        definition.key::text,
        version.version,
        version.schema_version,
        version.labels,
        version.option_labels,
        version.sections,
        version.field_schema,
        version.allowed_participant_roles,
        version.allowed_inventory_roles,
        version.behavior_flags,
        workflow_definition.key::text,
        workflow_version.version,
        workflow_version.checksum
      )
    )
    from public.deal_type_versions version
    join public.deal_type_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.deal_type_definition_id
    join public.workflow_versions workflow_version
      on workflow_version.workspace_id = version.workspace_id
     and workflow_version.id = version.workflow_version_id
    join public.workflow_definitions workflow_definition
      on workflow_definition.workspace_id = workflow_version.workspace_id
     and workflow_definition.id = workflow_version.workflow_definition_id
    where version.source = 'starter_pack'
      and version.status = 'active'
  ),
  'T-CFG-002 every starter deal type stores its canonical configuration checksum'
);

select extensions.ok(
  not exists (
    (
      select
        definition.key::text,
        version.version,
        version.revision,
        version.schema_version,
        version.labels,
        version.option_labels,
        version.sections,
        version.field_schema,
        version.allowed_participant_roles,
        version.allowed_inventory_roles,
        version.behavior_flags,
        version.status,
        version.checksum,
        version.source
      from public.deal_type_versions version
      join public.deal_type_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.deal_type_definition_id
      where version.workspace_id = '10000000-0000-4000-8000-000000000001'
        and version.source = 'starter_pack'
      except
      select
        definition.key::text,
        version.version,
        version.revision,
        version.schema_version,
        version.labels,
        version.option_labels,
        version.sections,
        version.field_schema,
        version.allowed_participant_roles,
        version.allowed_inventory_roles,
        version.behavior_flags,
        version.status,
        version.checksum,
        version.source
      from public.deal_type_versions version
      join public.deal_type_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.deal_type_definition_id
      where version.workspace_id = '20000000-0000-4000-8000-000000000002'
        and version.source = 'starter_pack'
    )
    union all
    (
      select
        definition.key::text,
        version.version,
        version.revision,
        version.schema_version,
        version.labels,
        version.option_labels,
        version.sections,
        version.field_schema,
        version.allowed_participant_roles,
        version.allowed_inventory_roles,
        version.behavior_flags,
        version.status,
        version.checksum,
        version.source
      from public.deal_type_versions version
      join public.deal_type_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.deal_type_definition_id
      where version.workspace_id = '20000000-0000-4000-8000-000000000002'
        and version.source = 'starter_pack'
      except
      select
        definition.key::text,
        version.version,
        version.revision,
        version.schema_version,
        version.labels,
        version.option_labels,
        version.sections,
        version.field_schema,
        version.allowed_participant_roles,
        version.allowed_inventory_roles,
        version.behavior_flags,
        version.status,
        version.checksum,
        version.source
      from public.deal_type_versions version
      join public.deal_type_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.deal_type_definition_id
      where version.workspace_id = '10000000-0000-4000-8000-000000000001'
        and version.source = 'starter_pack'
    )
  ),
  'T-TEN-001 starter deal-type versions have cross-workspace parity'
);

select extensions.ok(
  not exists (
    select 1
    from public.deal_type_versions version
    join public.deal_type_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.deal_type_definition_id
    where version.source = 'starter_pack'
      and pg_catalog.lower(
        definition.key::text || ' ' || version.labels::text || ' '
          || version.option_labels::text || ' '
          || version.field_schema::text || ' ' || version.behavior_flags::text
      ) ~ 'recurring|servicing|collections|repossession'
  ),
  'STD-DEAL-001 starter deal types contain no recurring servicing behavior'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workflow_states state
    join public.workflow_versions version
      on version.workspace_id = state.workspace_id
     and version.id = state.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
  ),
  28::bigint,
  'starter lead/deal workflows install fourteen states per workspace'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.workflow_transitions transition
    join public.workflow_versions version
      on version.workspace_id = transition.workspace_id
     and version.id = transition.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
  ),
  42::bigint,
  'starter lead/deal workflows install twenty-one transitions per workspace'
);

select extensions.results_eq(
  $$
    select
      definition.key::text,
      version.workspace_id::text,
      pg_catalog.count(distinct state.id)::bigint,
      pg_catalog.count(distinct transition.id)::bigint
    from public.workflow_versions version
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    left join public.workflow_states state
      on state.workspace_id = version.workspace_id
     and state.workflow_version_id = version.id
    left join public.workflow_transitions transition
      on transition.workspace_id = version.workspace_id
     and transition.workflow_version_id = version.id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
    group by definition.key, version.workspace_id
    order by definition.key, version.workspace_id
  $$,
  $$
    values
      ('lead_standard'::text, '10000000-0000-4000-8000-000000000001'::text, 6::bigint, 9::bigint),
      ('lead_standard'::text, '20000000-0000-4000-8000-000000000002'::text, 6::bigint, 9::bigint),
      ('retail_deal_standard'::text, '10000000-0000-4000-8000-000000000001'::text, 8::bigint, 12::bigint),
      ('retail_deal_standard'::text, '20000000-0000-4000-8000-000000000002'::text, 8::bigint, 12::bigint)
  $$,
  'state and transition counts are exact for both workflow versions'
);

select extensions.ok(
  (
    select pg_catalog.bool_and(
      pg_catalog.jsonb_typeof(state.labels) = 'object'
      and pg_catalog.jsonb_array_length(pg_catalog.jsonb_path_query_array(state.labels, '$.keyvalue()')) = 2
      and pg_catalog.jsonb_typeof(state.labels -> 'en') = 'string'
      and pg_catalog.jsonb_typeof(state.labels -> 'fr') = 'string'
      and pg_catalog.jsonb_typeof(state.behavior_flags) = 'object'
      and (state.behavior_flags ->> 'terminal')::boolean
        = (state.canonical_category = 'closed')
      and not exists (
        select 1
        from pg_catalog.jsonb_object_keys(state.behavior_flags) flag(key)
        where flag.key not in (
          'terminal', 'conversion_eligible', 'conversion_target',
          'loss_terminal', 'cancellation'
        )
      )
      and (state.behavior_flags @> '{"conversion_eligible":true}'::jsonb)
        = (definition.key::text = 'lead_standard' and state.key = 'qualified')
      and (state.behavior_flags @> '{"conversion_target":true}'::jsonb)
        = (definition.key::text = 'lead_standard' and state.key = 'converted')
      and (state.behavior_flags @> '{"loss_terminal":true}'::jsonb)
        = (definition.key::text = 'lead_standard' and state.key = 'lost')
      and (state.behavior_flags @> '{"cancellation":true}'::jsonb)
        = (definition.key::text = 'retail_deal_standard'
          and state.key = 'cancelled')
    )
    from public.workflow_states state
    join public.workflow_versions version
      on version.workspace_id = state.workspace_id
     and version.id = state.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
  ),
  'M3-WF-AC-001 every state has exact labels and allowlisted semantic flags'
);

select extensions.results_eq(
  $$
    select
      definition.key::text,
      state.key,
      state.canonical_category,
      state.labels ->> 'en',
      state.labels ->> 'fr',
      (state.behavior_flags ->> 'terminal')::boolean,
      state.sort_order,
      state.required_fields
    from public.workflow_states state
    join public.workflow_versions version
      on version.workspace_id = state.workspace_id
     and version.id = state.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where state.workspace_id = '10000000-0000-4000-8000-000000000001'
      and definition.key::text in ('lead_standard', 'retail_deal_standard')
    order by definition.key, state.sort_order
  $$,
  $$
    values
      ('lead_standard'::text, 'new'::text, 'active'::text, 'New'::text, 'Nouveau'::text, false, 10, '{}'::text[]),
      ('lead_standard'::text, 'contacted'::text, 'active'::text, 'Contacted'::text, 'Contacté'::text, false, 20, '{}'::text[]),
      ('lead_standard'::text, 'appointment'::text, 'pending'::text, 'Appointment'::text, 'Rendez-vous'::text, false, 30, '{}'::text[]),
      ('lead_standard'::text, 'qualified'::text, 'active'::text, 'Qualified'::text, 'Qualifié'::text, false, 40, '{}'::text[]),
      ('lead_standard'::text, 'converted'::text, 'closed'::text, 'Converted'::text, 'Converti'::text, true, 50, '{}'::text[]),
      ('lead_standard'::text, 'lost'::text, 'closed'::text, 'Lost'::text, 'Perdu'::text, true, 60, '{}'::text[]),
      ('retail_deal_standard'::text, 'draft'::text, 'draft'::text, 'Draft'::text, 'Brouillon'::text, false, 10, '{}'::text[]),
      ('retail_deal_standard'::text, 'preparing'::text, 'active'::text, 'Preparing'::text, 'En préparation'::text, false, 20, '{}'::text[]),
      ('retail_deal_standard'::text, 'awaiting_customer'::text, 'pending'::text, 'Awaiting customer'::text, 'En attente du client'::text, false, 30, '{}'::text[]),
      ('retail_deal_standard'::text, 'awaiting_lender'::text, 'pending'::text, 'Awaiting lender'::text, 'En attente du prêteur'::text, false, 40, '{}'::text[]),
      ('retail_deal_standard'::text, 'approved'::text, 'active'::text, 'Approved'::text, 'Approuvé'::text, false, 50, '{}'::text[]),
      ('retail_deal_standard'::text, 'ready_for_delivery'::text, 'active'::text, 'Ready for delivery'::text, 'Prêt pour la livraison'::text, false, 60, '{}'::text[]),
      ('retail_deal_standard'::text, 'completed'::text, 'closed'::text, 'Completed'::text, 'Terminé'::text, true, 70, '{}'::text[]),
      ('retail_deal_standard'::text, 'cancelled'::text, 'closed'::text, 'Cancelled'::text, 'Annulé'::text, true, 80, '{}'::text[])
  $$,
  'starter state graph exactly matches the versioned lead/deal artifacts'
);

select extensions.ok(
  not exists (
    (
      select
        definition.key::text,
        state.key,
        state.canonical_category,
        state.labels,
        state.behavior_flags,
        state.required_fields,
        state.sort_order
      from public.workflow_states state
      join public.workflow_versions version
        on version.workspace_id = state.workspace_id
       and version.id = state.workflow_version_id
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where state.workspace_id = '10000000-0000-4000-8000-000000000001'
        and definition.key::text in ('lead_standard', 'retail_deal_standard')
      except
      select
        definition.key::text,
        state.key,
        state.canonical_category,
        state.labels,
        state.behavior_flags,
        state.required_fields,
        state.sort_order
      from public.workflow_states state
      join public.workflow_versions version
        on version.workspace_id = state.workspace_id
       and version.id = state.workflow_version_id
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where state.workspace_id = '20000000-0000-4000-8000-000000000002'
        and definition.key::text in ('lead_standard', 'retail_deal_standard')
    )
    union all
    (
      select
        definition.key::text,
        state.key,
        state.canonical_category,
        state.labels,
        state.behavior_flags,
        state.required_fields,
        state.sort_order
      from public.workflow_states state
      join public.workflow_versions version
        on version.workspace_id = state.workspace_id
       and version.id = state.workflow_version_id
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where state.workspace_id = '20000000-0000-4000-8000-000000000002'
        and definition.key::text in ('lead_standard', 'retail_deal_standard')
      except
      select
        definition.key::text,
        state.key,
        state.canonical_category,
        state.labels,
        state.behavior_flags,
        state.required_fields,
        state.sort_order
      from public.workflow_states state
      join public.workflow_versions version
        on version.workspace_id = state.workspace_id
       and version.id = state.workflow_version_id
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where state.workspace_id = '10000000-0000-4000-8000-000000000001'
        and definition.key::text in ('lead_standard', 'retail_deal_standard')
    )
  ),
  'T-TEN-001 starter state graphs have cross-workspace parity'
);

select extensions.results_eq(
  $$
    select
      definition.key::text,
      pg_catalog.array_agg(
        transition.key || '|' || transition.from_state_key || '|'
          || transition.to_state_key || '|' || transition.permission_key || '|'
          || coalesce(transition.guard_key, '-') || '|'
          || transition.reason_required::text
        order by transition.key
      )::text[]
    from public.workflow_transitions transition
    join public.workflow_versions version
      on version.workspace_id = transition.workspace_id
     and version.id = transition.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where transition.workspace_id = '10000000-0000-4000-8000-000000000001'
      and definition.key::text in ('lead_standard', 'retail_deal_standard')
    group by definition.key
    order by definition.key
  $$,
  $$
    values
      (
        'lead_standard'::text,
        array[
          'appointment__lost|appointment|lost|crm.update|-|true',
          'appointment__qualified|appointment|qualified|crm.update|-|false',
          'contacted__appointment|contacted|appointment|crm.update|-|false',
          'contacted__lost|contacted|lost|crm.update|-|true',
          'contacted__qualified|contacted|qualified|crm.update|-|false',
          'new__contacted|new|contacted|crm.update|-|false',
          'new__lost|new|lost|crm.update|-|true',
          'qualified__converted|qualified|converted|deals.create|-|false',
          'qualified__lost|qualified|lost|crm.update|-|true'
        ]::text[]
      ),
      (
        'retail_deal_standard'::text,
        array[
          'approved__cancelled|approved|cancelled|deals.cancel|-|true',
          'approved__ready_for_delivery|approved|ready_for_delivery|deals.update|required_documents_generated|false',
          'awaiting_customer__approved|awaiting_customer|approved|deals.update|-|false',
          'awaiting_customer__cancelled|awaiting_customer|cancelled|deals.cancel|-|true',
          'awaiting_lender__approved|awaiting_lender|approved|finance_applications.update|lender_approval_recorded|false',
          'awaiting_lender__cancelled|awaiting_lender|cancelled|deals.cancel|-|true',
          'draft__cancelled|draft|cancelled|deals.cancel|-|true',
          'draft__preparing|draft|preparing|deals.update|-|false',
          'preparing__awaiting_customer|preparing|awaiting_customer|deals.update|-|false',
          'preparing__awaiting_lender|preparing|awaiting_lender|finance_applications.create|-|false',
          'preparing__cancelled|preparing|cancelled|deals.cancel|-|true',
          'ready_for_delivery__completed|ready_for_delivery|completed|deals.close|completion_requirements_met|false'
        ]::text[]
      )
  $$,
  'transition, permission, guard, and reason contracts exactly match the artifacts'
);

select extensions.ok(
  not exists (
    (
      select
        definition.key::text,
        transition.key,
        transition.from_state_key,
        transition.to_state_key,
        transition.permission_key,
        transition.guard_key,
        transition.reason_required,
        transition.required_fields,
        transition.effect_keys
      from public.workflow_transitions transition
      join public.workflow_versions version
        on version.workspace_id = transition.workspace_id
       and version.id = transition.workflow_version_id
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where transition.workspace_id = '10000000-0000-4000-8000-000000000001'
        and definition.key::text in ('lead_standard', 'retail_deal_standard')
      except
      select
        definition.key::text,
        transition.key,
        transition.from_state_key,
        transition.to_state_key,
        transition.permission_key,
        transition.guard_key,
        transition.reason_required,
        transition.required_fields,
        transition.effect_keys
      from public.workflow_transitions transition
      join public.workflow_versions version
        on version.workspace_id = transition.workspace_id
       and version.id = transition.workflow_version_id
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where transition.workspace_id = '20000000-0000-4000-8000-000000000002'
        and definition.key::text in ('lead_standard', 'retail_deal_standard')
    )
    union all
    (
      select
        definition.key::text,
        transition.key,
        transition.from_state_key,
        transition.to_state_key,
        transition.permission_key,
        transition.guard_key,
        transition.reason_required,
        transition.required_fields,
        transition.effect_keys
      from public.workflow_transitions transition
      join public.workflow_versions version
        on version.workspace_id = transition.workspace_id
       and version.id = transition.workflow_version_id
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where transition.workspace_id = '20000000-0000-4000-8000-000000000002'
        and definition.key::text in ('lead_standard', 'retail_deal_standard')
      except
      select
        definition.key::text,
        transition.key,
        transition.from_state_key,
        transition.to_state_key,
        transition.permission_key,
        transition.guard_key,
        transition.reason_required,
        transition.required_fields,
        transition.effect_keys
      from public.workflow_transitions transition
      join public.workflow_versions version
        on version.workspace_id = transition.workspace_id
       and version.id = transition.workflow_version_id
      join public.workflow_definitions definition
        on definition.workspace_id = version.workspace_id
       and definition.id = version.workflow_definition_id
      where transition.workspace_id = '10000000-0000-4000-8000-000000000001'
        and definition.key::text in ('lead_standard', 'retail_deal_standard')
    )
  ),
  'T-TEN-001 starter transition graphs have cross-workspace parity'
);

select extensions.ok(
  (
    select pg_catalog.bool_and(
      pg_catalog.cardinality(transition.required_fields) = 0
      and transition.effect_keys = '[]'::jsonb
    )
    from public.workflow_transitions transition
    join public.workflow_versions version
      on version.workspace_id = transition.workspace_id
     and version.id = transition.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
  ),
  'starter transitions install no undeclared required fields or side effects'
);

select extensions.ok(
  not exists (
    select 1
    from public.workflow_transitions transition
    join public.workflow_versions version
      on version.workspace_id = transition.workspace_id
     and version.id = transition.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    left join public.permissions permission
      on permission.workspace_id is null
     and permission.key = transition.permission_key
     and permission.source = 'platform'
     and permission.status = 'active'
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
      and permission.id is null
  ),
  'every starter transition references an active immutable platform permission'
);

select extensions.ok(
  not exists (
    select 1
    from public.workflow_states state
    join public.workflow_transitions transition
      on transition.workspace_id = state.workspace_id
     and transition.workflow_version_id = state.workflow_version_id
     and transition.from_state_key = state.key
    join public.workflow_versions version
      on version.workspace_id = state.workspace_id
     and version.id = state.workflow_version_id
    join public.workflow_definitions definition
      on definition.workspace_id = version.workspace_id
     and definition.id = version.workflow_definition_id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
      and state.behavior_flags @> '{"terminal":true}'::jsonb
  ),
  'T-WF-001 terminal starter states have no outgoing transition'
);

select extensions.ok(
  not exists (
    select 1
    from public.workflow_definitions definition
    left join public.workflow_versions version
      on version.workspace_id = definition.workspace_id
     and version.workflow_definition_id = definition.id
    left join public.workflow_states state
      on state.workspace_id = version.workspace_id
     and state.workflow_version_id = version.id
    left join public.workflow_transitions transition
      on transition.workspace_id = version.workspace_id
     and transition.workflow_version_id = version.id
    where definition.key::text in ('lead_standard', 'retail_deal_standard')
      and pg_catalog.lower(
        definition.key::text || ' ' || coalesce(state.key, '') || ' '
          || coalesce(transition.key, '') || ' '
          || coalesce(transition.guard_key, '') || ' '
          || coalesce(transition.effect_keys::text, '')
      ) ~ 'recurring|servicing|collections|repossession'
  ),
  'STD-DEAL-001 core starter configuration contains no tenant-specific or servicing behavior'
);

select * from extensions.finish();
rollback;
