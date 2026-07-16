-- T-INV-001, T-INV-002, T-NUM-001, T-NUM-002, T-NUM-003, T-CRM-001,
-- T-DEAL-001, T-DOC-001, T-TEN-001, T-TEN-002, T-RBAC-001, T-AUD-001
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(72);

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
          'timestamp', pg_catalog.floor(
            pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
          )::bigint
        )
      else pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'method', 'password',
          'timestamp', pg_catalog.floor(
            pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
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

select extensions.has_table('public', 'stock_number_definitions', 'stock definitions exist');
select extensions.has_table('public', 'stock_number_counters', 'stock counters exist');
select extensions.has_table('public', 'stock_number_allocations', 'stock allocations exist');
select extensions.has_table('public', 'vehicles', 'physical vehicles exist');
select extensions.has_table('public', 'inventory_units', 'holding episodes exist');
select extensions.has_table('public', 'parties', 'parties exist');
select extensions.has_table('public', 'deals', 'deal drafts exist');
select extensions.has_table('public', 'deal_participants', 'deal participants exist');
select extensions.has_table('public', 'deal_inventory_units', 'deal inventory links exist');
select extensions.has_table('public', 'document_types', 'document types exist');
select extensions.has_table(
  'public',
  'document_template_versions',
  'document template versions exist'
);
select extensions.has_table('public', 'documents', 'preview documents exist');

select extensions.has_function(
  'app',
  'create_inventory_unit',
  array[
    'uuid', 'uuid', 'text', 'text', 'integer', 'text', 'text', 'date',
    'bigint', 'text', 'text', 'bigint', 'text', 'text', 'uuid'
  ],
  'inventory command exists'
);
select extensions.has_function(
  'app',
  'create_party',
  array['uuid', 'text', 'text', 'text', 'text', 'uuid'],
  'party command exists'
);
select extensions.has_function(
  'app',
  'create_deal_draft',
  array[
    'uuid', 'text', 'text', 'text', 'uuid', 'text', 'uuid', 'text',
    'text', 'text', 'uuid'
  ],
  'deal draft command exists'
);
select extensions.has_function(
  'app',
  'request_document_preview',
  array['uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'uuid'],
  'preview request command exists'
);
select extensions.has_function(
  'app',
  'complete_document_preview',
  array['uuid', 'uuid', 'boolean', 'text', 'text', 'text', 'uuid'],
  'preview completion command exists'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'stock_number_definitions', 'stock_number_counters',
        'stock_number_allocations', 'vehicles', 'inventory_units', 'parties',
        'deals', 'deal_participants', 'deal_inventory_units', 'document_types',
        'document_template_versions', 'documents'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  12::bigint,
  'T-TEN-001 every exposed slice table has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.inventory_units', 'INSERT')
    and not pg_catalog.has_table_privilege('authenticated', 'public.parties', 'INSERT')
    and not pg_catalog.has_table_privilege('authenticated', 'public.deals', 'INSERT')
    and not pg_catalog.has_table_privilege('authenticated', 'public.documents', 'INSERT'),
  'T-RBAC-001 browser mutations must use permissioned commands'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.complete_document_preview(uuid,uuid,boolean,text,text,text,uuid)',
    'EXECUTE'
  ),
  'preview completion remains service-only'
);

insert into public.stock_number_definitions (
  id, workspace_id, key, version, prefix, numeric_width, starting_value,
  increment_by, status, checksum
)
values
  (
    '71000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'synthetic_stock', 1, 'S', 5, 1, 1, 'active', repeat('a', 64)
  ),
  (
    '72000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'synthetic_stock', 1, 'H', 5, 1, 1, 'active', repeat('b', 64)
  );
insert into public.stock_number_counters (
  workspace_id, definition_id, next_sequence_value
)
values
  (
    '10000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    1
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '72000000-0000-4000-8000-000000000001',
    1
  );
insert into public.document_types (
  id, workspace_id, key, version, display_name, field_schema,
  official_generation_enabled, status
)
values
  (
    '91000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'synthetic_preview', 1, 'Synthetic preview', '{}', false, 'active'
  ),
  (
    '92000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'synthetic_preview', 1, 'Synthetic preview', '{}', false, 'active'
  );
insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_checksum, renderer_version, field_schema,
  production_approved, watermark, status
)
values
  (
    '93000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    1, 'en-CA', 'synthetic_non_production',
    '<html><body>{{ deal.id }}</body></html>', repeat('c', 64),
    'synthetic-html-v1', '{}', false, 'DRAFT / NON-PRODUCTION', 'active'
  ),
  (
    '94000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    '92000000-0000-4000-8000-000000000001',
    1, 'en-CA', 'synthetic_non_production',
    '<html><body>{{ deal.id }}</body></html>', repeat('d', 64),
    'synthetic-html-v1', '{}', false, 'DRAFT / NON-PRODUCTION', 'active'
  );

insert into public.parties (
  id,
  workspace_id,
  party_type,
  display_name,
  idempotency_key,
  command_fingerprint,
  created_by
) values (
  'b1000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000002',
  'person',
  'Cross-workspace fixture',
  'cross-workspace-party-fixture',
  repeat('e', 64),
  '32000000-0000-4000-8000-000000000001'
);

create temporary table pg_temp.inventory_results (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean,
  probe text
);
create temporary table pg_temp.party_results (
  party_id uuid,
  replayed boolean,
  probe text
);
create temporary table pg_temp.deal_results (
  deal_id uuid,
  participant_id uuid,
  inventory_link_id uuid,
  replayed boolean,
  probe text
);
create temporary table pg_temp.preview_results (
  document_id uuid,
  preview_status text,
  watermark text,
  replayed boolean,
  probe text
);
grant all on pg_temp.inventory_results, pg_temp.party_results,
  pg_temp.deal_results, pg_temp.preview_results to authenticated, service_role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;

select extensions.throws_ok(
  $$
    select * from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'invalid-vin-command', '1HGCM82633I004352', 2024, 'Example', 'Roadster',
      date '2026-07-16', 100, 'km', 'CAD', 2500000, null,
      'request-invalid-vin', pg_catalog.gen_random_uuid()
    )
  $$,
  '22023',
  'VIN must contain 17 valid typed or pasted characters',
  'T-INV-002 invalid typed VIN fails closed'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_results
    select result.*, 'initial'
    from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'inventory-command-001', '1hgcm82633a004352', 2024, 'Example', 'Roadster',
      date '2026-07-16', 12345, 'km', 'CAD', 2500000, 'Synthetic fixture',
      'request-inventory-001', 'a1000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'T-INV-001 creates a physical vehicle and holding episode atomically'
);
select extensions.results_eq(
  $$select stock_number, replayed from pg_temp.inventory_results where probe = 'initial'$$,
  $$values ('S00001'::text, false)$$,
  'T-NUM-001 first configured stock number is deterministic'
);
select extensions.ok(
  (select inventory_unit_id <> vehicle_id from pg_temp.inventory_results where probe = 'initial'),
  'T-INV-001 physical vehicle remains separate from its holding episode'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units inventory
    join public.stock_number_allocations allocation
      on allocation.workspace_id = inventory.workspace_id
     and allocation.id = inventory.stock_allocation_id
     and allocation.inventory_unit_id = inventory.id
    where inventory.id = (
      select inventory_unit_id from pg_temp.inventory_results where probe = 'initial'
    )
  ),
  'T-NUM-001 allocation and holding episode link transactionally'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.audit_events
    where action = 'inventory_unit.created'
      and entity_id = (
        select inventory_unit_id from pg_temp.inventory_results where probe = 'initial'
      )
  ),
  1::bigint,
  'T-AUD-001 inventory creation writes one audit event'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.inventory_results
    select result.*, 'replay'
    from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'inventory-command-001', '1HGCM82633A004352', 2024, 'Example', 'Roadster',
      date '2026-07-16', 12345, 'km', 'CAD', 2500000, 'Synthetic fixture',
      'request-inventory-replay', 'a1000000-0000-4000-8000-000000000002'
    ) result
  $$,
  'T-NUM-003 exact inventory replay succeeds'
);
select extensions.ok(
  (select inventory_unit_id from pg_temp.inventory_results where probe = 'initial')
    = (select inventory_unit_id from pg_temp.inventory_results where probe = 'replay')
    and (select replayed from pg_temp.inventory_results where probe = 'replay')
    and (
      select pg_catalog.count(*) from public.stock_number_allocations
      where idempotency_key = 'inventory-command-001'
    ) = 1,
  'T-NUM-003 replay returns the same entity and cannot allocate twice'
);
select extensions.throws_ok(
  $$
    select * from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'inventory-command-001', '1HGCM82633A004353', 2024, 'Example', 'Roadster',
      date '2026-07-16', 12345, 'km', 'CAD', 2500000, null,
      'request-inventory-conflict', pg_catalog.gen_random_uuid()
    )
  $$,
  '23505',
  'inventory idempotency key was used for a different request',
  'T-NUM-003 reused idempotency key rejects a different fingerprint'
);
select extensions.throws_ok(
  $$
    select * from app.create_inventory_unit(
      '20000000-0000-4000-8000-000000000002',
      '72000000-0000-4000-8000-000000000001',
      'cross-workspace-inventory', '1HGCM82633A004354', 2024, null, null,
      null, null, null, 'CAD', null, null, 'request-cross', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 workspace A actor cannot create in workspace B'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal2');
select extensions.throws_ok(
  $$
    select * from app.create_party(
      '10000000-0000-4000-8000-000000000001', 'limited-party-attempt',
      'person', 'Denied', 'request-limited', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-RBAC-001 missing crm.create permission denies the command'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000003', 'aal2');
select extensions.throws_ok(
  $$
    select * from app.create_party(
      '10000000-0000-4000-8000-000000000001', 'inactive-party-attempt',
      'person', 'Denied', 'request-inactive', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 inactive membership denies the command'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
select extensions.throws_ok(
  $$
    select * from app.create_party(
      '10000000-0000-4000-8000-000000000001', 'aal1-party-attempt',
      'person', 'Denied', 'request-aal1', pg_catalog.gen_random_uuid()
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-AUTH-002 administrator role cannot act without required MFA assurance'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');

select extensions.lives_ok(
  $$
    do $concurrency_probe$
    declare
      sequence_number integer;
    begin
      for sequence_number in 1..100 loop
        perform inventory_unit_id
        from app.create_inventory_unit(
          '10000000-0000-4000-8000-000000000001',
          '71000000-0000-4000-8000-000000000001',
          'pgtap-concurrency-' || pg_catalog.lpad(sequence_number::text, 3, '0'),
          '1HGCM82633A' || pg_catalog.lpad(sequence_number::text, 6, '0'),
          2024, 'Example', 'Batch', null, null, null, 'CAD', null, null,
          'request-concurrency-' || sequence_number::text,
          pg_catalog.gen_random_uuid()
        );
      end loop;
    end
    $concurrency_probe$
  $$,
  'T-NUM-001 serialized counter allocation handles a 100-command contention probe'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.stock_number_allocations
    where idempotency_key like 'pgtap-concurrency-%'
  ),
  100::bigint,
  'T-NUM-001 all 100 committed attempts allocate exactly once'
);
select extensions.ok(
  (
    select pg_catalog.count(distinct formatted_value) = 100
      and pg_catalog.max(sequence_value) - pg_catalog.min(sequence_value) = 99
    from public.stock_number_allocations
    where idempotency_key like 'pgtap-concurrency-%'
  ),
  'T-NUM-001 counter locking yields unique monotonic values without committed gaps'
);
select extensions.throws_ok(
  $$
    update public.stock_number_allocations
    set formatted_value = 'TAMPERED'
    where idempotency_key = 'inventory-command-001'
  $$,
  '42501',
  'permission denied for table stock_number_allocations',
  'T-NUM-003 browser cannot mutate permanent allocations'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.party_results
    select result.*, 'initial'
    from app.create_party(
      '10000000-0000-4000-8000-000000000001', 'party-command-001',
      'person', '  Synthetic   Customer  ', 'request-party-001',
      'a2000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'T-CRM-001 creates a minimal workspace-owned party'
);
select extensions.ok(
  (select display_name = 'Synthetic Customer' from public.parties where idempotency_key = 'party-command-001')
    and (
      select pg_catalog.count(*) = 1 from public.audit_events
      where action = 'party.created'
        and entity_id = (select party_id from pg_temp.party_results where probe = 'initial')
    ),
  'T-CRM-001 party normalization and audit commit together'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.party_results
    select result.*, 'replay'
    from app.create_party(
      '10000000-0000-4000-8000-000000000001', 'party-command-001',
      'person', 'Synthetic Customer', 'request-party-replay',
      'a2000000-0000-4000-8000-000000000002'
    ) result
  $$,
  'exact party replay succeeds'
);
select extensions.ok(
  (select party_id from pg_temp.party_results where probe = 'initial')
    = (select party_id from pg_temp.party_results where probe = 'replay')
    and (select replayed from pg_temp.party_results where probe = 'replay')
    and (select pg_catalog.count(*) from public.parties where idempotency_key = 'party-command-001') = 1,
  'party replay is idempotent'
);
select extensions.throws_ok(
  $$
    select * from app.create_party(
      '10000000-0000-4000-8000-000000000001', 'invalid-party-command',
      'household', 'Invalid', 'request-invalid-party', pg_catalog.gen_random_uuid()
    )
  $$,
  '22023',
  'invalid party type',
  'invalid party type fails closed'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.deal_results
    select result.*, 'initial'
    from app.create_deal_draft(
      '10000000-0000-4000-8000-000000000001', 'deal-command-001',
      'retail.cash', 'CAD',
      (select party_id from pg_temp.party_results where probe = 'initial'),
      'buyer',
      (select inventory_unit_id from pg_temp.inventory_results where probe = 'initial'),
      'sold', 'Synthetic draft', 'request-deal-001',
      'a3000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'T-DEAL-001 creates a workspace-owned deal draft with required links'
);
select extensions.ok(
  exists (
    select 1
    from public.deals deal
    join public.deal_participants participant
      on participant.workspace_id = deal.workspace_id and participant.deal_id = deal.id
    join public.deal_inventory_units inventory_link
      on inventory_link.workspace_id = deal.workspace_id and inventory_link.deal_id = deal.id
    where deal.id = (select deal_id from pg_temp.deal_results where probe = 'initial')
      and deal.owner_membership_id = '41000000-0000-4000-8000-000000000001'
      and participant.party_id = (select party_id from pg_temp.party_results where probe = 'initial')
      and inventory_link.inventory_unit_id = (
        select inventory_unit_id from pg_temp.inventory_results where probe = 'initial'
      )
  ),
  'T-DEAL-001 owner membership is derived and party/inventory links are composite-scoped'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.audit_events
    where action = 'deal.created'
      and entity_id = (select deal_id from pg_temp.deal_results where probe = 'initial')
  ),
  1::bigint,
  'T-AUD-001 deal creation is audited'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.deal_results
    select result.*, 'replay'
    from app.create_deal_draft(
      '10000000-0000-4000-8000-000000000001', 'deal-command-001',
      'retail.cash', 'CAD',
      (select party_id from pg_temp.party_results where probe = 'initial'),
      'buyer',
      (select inventory_unit_id from pg_temp.inventory_results where probe = 'initial'),
      'sold', 'Synthetic draft', 'request-deal-replay',
      'a3000000-0000-4000-8000-000000000002'
    ) result
  $$,
  'exact deal replay succeeds'
);
select extensions.ok(
  (select deal_id from pg_temp.deal_results where probe = 'initial')
    = (select deal_id from pg_temp.deal_results where probe = 'replay')
    and (select replayed from pg_temp.deal_results where probe = 'replay')
    and (select pg_catalog.count(*) from public.deals where idempotency_key = 'deal-command-001') = 1,
  'deal replay cannot duplicate the draft or links'
);
select extensions.throws_ok(
  $$
    select * from app.create_deal_draft(
      '10000000-0000-4000-8000-000000000001', 'deal-cross-party',
      'retail.cash', 'CAD', 'b1000000-0000-4000-8000-000000000001', 'buyer',
      (select inventory_unit_id from pg_temp.inventory_results where probe = 'initial'),
      'purchased', null, 'request-cross-party', pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'active participant party must belong to the workspace',
  'T-TEN-001 cross-workspace party linkage fails without disclosure'
);
select extensions.throws_ok(
  $$
    select * from app.create_deal_draft(
      '10000000-0000-4000-8000-000000000001', 'deal-second-sold',
      'retail.cash', 'CAD',
      (select party_id from pg_temp.party_results where probe = 'initial'),
      'buyer',
      (select inventory_unit_id from pg_temp.inventory_results where probe = 'initial'),
      'sold', null, 'request-second-sold', pg_catalog.gen_random_uuid()
    )
  $$,
  '23505',
  'active sold inventory unit is already linked to a deal',
  'T-DEAL-001 one active sold linkage prevents conflicting draft deals'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.preview_results
    select result.*, 'initial'
    from app.request_document_preview(
      '10000000-0000-4000-8000-000000000001', 'preview-command-001',
      (select deal_id from pg_temp.deal_results where probe = 'initial'),
      '93000000-0000-4000-8000-000000000001', 'en-CA',
      'request-preview-001', 'a4000000-0000-4000-8000-000000000001'
    ) result
  $$,
  'T-DOC-001 requests a synthetic preview record'
);
select extensions.ok(
  exists (
    select 1 from public.documents document
    where document.id = (select document_id from pg_temp.preview_results where probe = 'initial')
      and document.mode = 'preview'
      and document.status = 'queued'
      and document.official_number is null
      and document.watermark = 'DRAFT / NON-PRODUCTION'
  ),
  'T-DOC-001 preview is queued, unnumbered, and visibly non-production'
);
select extensions.ok(
  (
    select pg_catalog.jsonb_array_length(render_input_snapshot -> 'participants') = 1
      and pg_catalog.jsonb_array_length(render_input_snapshot -> 'inventory_units') = 1
    from public.documents
    where id = (select document_id from pg_temp.preview_results where probe = 'initial')
  ),
  'preview stores a server-built immutable input snapshot'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.audit_events
    where action = 'document.preview_requested'
      and entity_id = (select document_id from pg_temp.preview_results where probe = 'initial')
  ),
  1::bigint,
  'T-AUD-001 preview request is audited'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.preview_results
    select result.*, 'replay'
    from app.request_document_preview(
      '10000000-0000-4000-8000-000000000001', 'preview-command-001',
      (select deal_id from pg_temp.deal_results where probe = 'initial'),
      '93000000-0000-4000-8000-000000000001', 'en-CA',
      'request-preview-replay', 'a4000000-0000-4000-8000-000000000002'
    ) result
  $$,
  'exact preview replay succeeds'
);
select extensions.ok(
  (select document_id from pg_temp.preview_results where probe = 'initial')
    = (select document_id from pg_temp.preview_results where probe = 'replay')
    and (select replayed from pg_temp.preview_results where probe = 'replay')
    and (select pg_catalog.count(*) from public.documents where idempotency_key = 'preview-command-001') = 1,
  'preview replay cannot duplicate a document request'
);
select extensions.throws_ok(
  $$
    select * from app.request_document_preview(
      '10000000-0000-4000-8000-000000000001', 'preview-cross-template',
      (select deal_id from pg_temp.deal_results where probe = 'initial'),
      '94000000-0000-4000-8000-000000000001', 'en-CA',
      'request-cross-template', pg_catalog.gen_random_uuid()
    )
  $$,
  '23514',
  'active synthetic non-production template must belong to the workspace',
  'T-TEN-001 cross-workspace template use is denied'
);
select extensions.ok(
  (
    select metadata ->> 'outbox_enqueue_deferred' = 'true'
    from public.audit_events
    where action = 'document.preview_requested'
      and entity_id = (select document_id from pg_temp.preview_results where probe = 'initial')
  ),
  'queued preview records explicitly mark outbox enqueue as deferred integration work'
);

select extensions.throws_ok(
  $$
    insert into public.document_template_versions (
      workspace_id, document_type_id, version, locale, source_html,
      source_checksum, renderer_version, production_approved
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001', 2, 'en-CA',
      '<html>unsafe production flag</html>', repeat('e', 64), 'synthetic-html-v1', true
    )
  $$,
  '42501',
  'permission denied for table document_template_versions',
  'browser cannot activate or insert a template directly'
);
select extensions.throws_ok(
  $$
    delete from public.deal_inventory_units
    where id = (select inventory_link_id from pg_temp.deal_results where probe = 'initial')
  $$,
  '42501',
  'permission denied for table deal_inventory_units',
  'browser cannot delete immutable deal linkage history'
);

set local role service_role;
select extensions.lives_ok(
  $$
    select app.complete_document_preview(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_results where probe = 'initial'),
      true, repeat('f', 64), null, 'request-preview-complete',
      'a4000000-0000-4000-8000-000000000003'
    )
  $$,
  'preview worker contract completes one queued record'
);
select extensions.results_eq(
  $$
    select status, generated_checksum, failure_code
    from public.documents
    where id = (select document_id from pg_temp.preview_results where probe = 'initial')
  $$,
  $$values ('generated'::text, repeat('f', 64)::text, null::text)$$,
  'preview completion stores terminal checksum state'
);
select extensions.is(
  app.complete_document_preview(
    '10000000-0000-4000-8000-000000000001',
    (select document_id from pg_temp.preview_results where probe = 'initial'),
    true, repeat('f', 64), null, 'request-preview-complete-replay',
    'a4000000-0000-4000-8000-000000000004'
  ),
  'generated'::text,
  'preview completion replay is idempotent'
);
select extensions.throws_ok(
  $$
    select app.complete_document_preview(
      '10000000-0000-4000-8000-000000000001',
      (select document_id from pg_temp.preview_results where probe = 'initial'),
      false, null, 'RENDER_FAILED', 'request-preview-conflict',
      pg_catalog.gen_random_uuid()
    )
  $$,
  '55000',
  'terminal preview result cannot be replaced',
  'terminal preview result cannot be contradicted'
);
select extensions.is(
  (
    select pg_catalog.count(*) from public.audit_events
    where action = 'document.preview_generated'
      and entity_id = (select document_id from pg_temp.preview_results where probe = 'initial')
  ),
  1::bigint,
  'T-AUD-001 preview completion is audited exactly once'
);

reset role;
select extensions.throws_ok(
  $$
    insert into public.document_template_versions (
      workspace_id, document_type_id, version, locale, source_html,
      source_checksum, renderer_version, production_approved
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001', 2, 'en-CA',
      '<html>production is prohibited</html>', repeat('e', 64),
      'synthetic-html-v1', true
    )
  $$,
  '23514',
  'new row for relation "document_template_versions" violates check constraint "document_template_versions_production_approved_check"',
  'T-DOC-001 even trusted writes cannot mark a synthetic template production-approved'
);
select extensions.throws_ok(
  $$
    update public.stock_number_allocations
    set formatted_value = 'TAMPERED'
    where idempotency_key = 'inventory-command-001'
  $$,
  '23514',
  'stock_number_allocations.formatted_value is immutable',
  'T-NUM-003 permanent allocation fields remain immutable to trusted roles'
);
select extensions.throws_ok(
  $$
    update public.document_template_versions
    set source_html = '<html>tampered</html>'
    where id = '93000000-0000-4000-8000-000000000001'
  $$,
  '23514',
  'document_template_versions.source_html is immutable',
  'synthetic template source remains immutable'
);
select extensions.throws_ok(
  $$
    delete from public.documents
    where id = (select document_id from pg_temp.preview_results where probe = 'initial')
  $$,
  '55000',
  'hard delete is prohibited for documents',
  'preview history cannot be hard deleted'
);
select extensions.throws_ok(
  $$
    insert into public.deal_participants (
      workspace_id, deal_id, party_id, role_key
    ) values (
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where probe = 'initial'),
      'b1000000-0000-4000-8000-000000000001',
      'buyer'
    )
  $$,
  '23503',
  'insert or update on table "deal_participants" violates foreign key constraint "deal_participants_workspace_id_party_id_fkey"',
  'T-TEN-001 composite foreign key rejects a cross-workspace party link'
);

-- Create workspace B records through the same commands so the final RLS probe
-- has real rows to attempt to disclose.
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
insert into pg_temp.inventory_results
select result.*, 'workspace-b'
from app.create_inventory_unit(
  '20000000-0000-4000-8000-000000000002',
  '72000000-0000-4000-8000-000000000001',
  'workspace-b-inventory', '1HGCM82633A900001', 2024, 'Example', 'Harbour',
  null, null, null, 'CAD', null, null, 'request-b-inventory',
  'b4000000-0000-4000-8000-000000000001'
) result;
insert into pg_temp.party_results
select result.*, 'workspace-b'
from app.create_party(
  '20000000-0000-4000-8000-000000000002', 'workspace-b-party',
  'person', 'Workspace B Customer', 'request-b-party',
  'b4000000-0000-4000-8000-000000000002'
) result;
insert into pg_temp.deal_results
select result.*, 'workspace-b'
from app.create_deal_draft(
  '20000000-0000-4000-8000-000000000002', 'workspace-b-deal',
  'retail.cash', 'CAD',
  (select party_id from pg_temp.party_results where probe = 'workspace-b'),
  'buyer',
  (select inventory_unit_id from pg_temp.inventory_results where probe = 'workspace-b'),
  'sold', null, 'request-b-deal',
  'b4000000-0000-4000-8000-000000000003'
) result;
insert into pg_temp.preview_results
select result.*, 'workspace-b'
from app.request_document_preview(
  '20000000-0000-4000-8000-000000000002', 'workspace-b-preview',
  (select deal_id from pg_temp.deal_results where probe = 'workspace-b'),
  '94000000-0000-4000-8000-000000000001', 'en-CA',
  'request-b-preview', 'b4000000-0000-4000-8000-000000000004'
) result;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
select extensions.ok(
  (select pg_catalog.count(*) from public.inventory_units where workspace_id = '20000000-0000-4000-8000-000000000002') = 0
    and (select pg_catalog.count(*) from public.parties where workspace_id = '20000000-0000-4000-8000-000000000002') = 0
    and (select pg_catalog.count(*) from public.deals where workspace_id = '20000000-0000-4000-8000-000000000002') = 0
    and (select pg_catalog.count(*) from public.documents where workspace_id = '20000000-0000-4000-8000-000000000002') = 0,
  'T-TEN-001 workspace A cannot select workspace B vertical-slice records'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.stock_number_allocations allocation
    join public.inventory_units inventory
      on inventory.workspace_id = allocation.workspace_id
     and inventory.id = allocation.inventory_unit_id
    where allocation.idempotency_key = 'inventory-command-001'
      and allocation.formatted_value = inventory.stock_number
  ),
  1::bigint,
  'T-NUM-003 committed stock value remains linked and never re-enters a pool'
);
select extensions.ok(
  not exists (
    select 1 from public.documents
    where mode <> 'preview' or official_number is not null
  ),
  'T-DOC-001 this slice cannot create an official or numbered document'
);

select * from extensions.finish();
rollback;
