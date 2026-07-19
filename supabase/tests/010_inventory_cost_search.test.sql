-- VYN-COST-001, VYN-SEARCH-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- T-COST-001, T-COST-002, T-SEARCH-001, T-TEN-001, T-RBAC-001
-- M2-INV-AC-007, M2-INV-AC-008, M2-INV-AC-009, M2-INV-AC-011
begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(65);

-- Test-only compatibility grant for cost/search fixture setup. It is rolled
-- back and does not reopen the production legacy RPC.
grant execute on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) to authenticated;

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
            pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
          )::bigint
        )
      )
      else pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'method', 'password',
          'timestamp', pg_catalog.floor(
            pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
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

create function pg_temp.legal_file_receipt(
  object_key text,
  generation text,
  byte_size bigint,
  checksum_sha256 text
)
returns jsonb
language sql
immutable
as $$
  select pg_catalog.jsonb_build_object(
    'schemaVersion', 1,
    'verifier', pg_catalog.jsonb_build_object(
      'name', 'fixture-verifier', 'version', '1.0.0'
    ),
    'storage', pg_catalog.jsonb_build_object(
      'bucket', 'media-private',
      'objectKey', object_key,
      'generation', generation,
      'byteSize', byte_size::text,
      'checksumSha256', checksum_sha256
    ),
    'malwareScan', pg_catalog.jsonb_build_object(
      'verdict', 'clean',
      'sourceChecksumSha256', checksum_sha256,
      'scanner', 'fixture-clamd',
      'signatureVersion', 'fixture-1'
    )
  );
$$;

create temporary table pg_temp.cost_inventory_result (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean
);
create temporary table pg_temp.cost_command_results (
  cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.reversal_command_results (
  reversal_entry_id uuid,
  original_cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.saved_view_results (
  saved_view_id uuid,
  saved_view_version bigint,
  replayed boolean,
  audit_event_id uuid,
  probe text
);

grant all on
  pg_temp.cost_inventory_result,
  pg_temp.cost_command_results,
  pg_temp.reversal_command_results,
  pg_temp.saved_view_results
to authenticated, service_role;

select extensions.has_table(
  'public', 'inventory_cost_category_definitions',
  'versioned inventory cost categories exist'
);
select extensions.has_table(
  'public', 'inventory_cost_entries',
  'append-only inventory cost entries exist'
);
select extensions.has_table(
  'public', 'inventory_cost_metrics',
  'inventory cost metrics projection exists'
);
select extensions.has_table(
  'public', 'inventory_search_documents',
  'workspace inventory search documents exist'
);
select extensions.has_table(
  'public', 'inventory_saved_views',
  'versioned inventory saved views exist'
);
select extensions.has_table(
  'public', 'inventory_saved_view_command_receipts',
  'saved-view idempotency receipts exist'
);

select extensions.has_function(
  'app', 'post_inventory_cost_entry',
  array[
    'uuid', 'text', 'uuid', 'bigint', 'uuid', 'bigint', 'text', 'date',
    'uuid', 'text', 'uuid', 'text', 'uuid'
  ],
  'cost posting command contract exists'
);
select extensions.has_function(
  'app', 'reverse_inventory_cost_entry',
  array['uuid', 'text', 'uuid', 'bigint', 'date', 'text', 'text', 'uuid'],
  'cost reversal command contract exists'
);
select extensions.has_function(
  'app', 'save_inventory_view',
  array[
    'uuid', 'text', 'uuid', 'bigint', 'text', 'jsonb', 'jsonb', 'jsonb',
    'text', 'text', 'text', 'text', 'uuid'
  ],
  'saved-view command contract exists'
);
select extensions.has_function(
  'app', 'search_inventory_units',
  array[
    'uuid', 'text', 'text[]', 'uuid[]', 'bigint', 'bigint', 'integer',
    'integer', 'real', 'timestamp with time zone', 'uuid', 'integer'
  ],
  'bounded inventory search contract exists'
);

select extensions.ok(
  (
    select pg_catalog.count(*) = 6
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'inventory_cost_category_definitions', 'inventory_cost_entries',
        'inventory_cost_metrics', 'inventory_search_documents',
        'inventory_saved_views', 'inventory_saved_view_command_receipts'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'T-TEN-001 every cost, search, and saved-view table has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.inventory_cost_entries', 'INSERT,UPDATE,DELETE'
  )
    and not pg_catalog.has_table_privilege(
      'authenticated', 'public.inventory_saved_views', 'INSERT,UPDATE,DELETE'
    ),
  'T-RBAC-001 browser mutations must use canonical cost and saved-view commands'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.inventory_saved_view_command_receipts', 'SELECT'
  ),
  'saved-view idempotency receipts are never browser-readable'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'app.refresh_inventory_cost_metric(uuid,uuid)', 'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated', 'app.refresh_inventory_search_document(uuid,uuid)', 'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.inventory_saved_view_payload_valid(jsonb,jsonb,jsonb)',
      'EXECUTE'
    ),
  'projection and configuration helpers are not browser-callable'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.inventory_cost_category_definitions category
    where category.id in (
      'c2100000-0000-4000-8000-000000000001',
      'c2100000-0000-4000-8000-000000000002',
      'c2100000-0000-4000-8000-000000000003',
      'c2200000-0000-4000-8000-000000000001',
      'c2200000-0000-4000-8000-000000000002',
      'c2200000-0000-4000-8000-000000000003'
    )
      and category.status = 'active'
  ),
  6::bigint,
  'tenant-neutral seed includes localized versioned cost categories per workspace'
);

insert into public.inventory_cost_category_definitions (
  id, workspace_id, key, version, labels, status, checksum, activated_at
) values
  (
    'ca100000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'synthetic.validation',
    1,
    '{"en":"Synthetic validation","fr":"Validation synthetique"}'::jsonb,
    'active',
    repeat('a', 64),
    pg_catalog.statement_timestamp()
  ),
  (
    'ca200000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    'synthetic.validation',
    1,
    '{"en":"Synthetic validation","fr":"Validation synthetique"}'::jsonb,
    'active',
    repeat('b', 64),
    pg_catalog.statement_timestamp()
  );

select extensions.throws_ok(
  $$
    update public.inventory_cost_category_definitions
    set labels = '{"en":"Rewritten"}'::jsonb
    where id = 'ca100000-0000-4000-8000-000000000001'
  $$,
  '55000',
  'activated inventory cost category configuration is immutable',
  'active cost category definitions cannot be rewritten'
);

-- Grant only inventory.read to the limited fixture so the search projection can
-- prove that cost fields remain hidden independently of inventory visibility.
insert into public.role_permissions (workspace_id, role_id, permission_id, status)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000002',
  permission.id,
  'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key = 'inventory.read'
on conflict (workspace_id, role_id, permission_id) do update
set status = 'active', revoked_by = null, revoked_at = null;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;

select extensions.lives_ok(
  $$
    insert into pg_temp.cost_inventory_result
    select result.*
    from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'm2-cost-create-001',
      '1HGCM82633A700010',
      2024,
      'Synthetic',
      'Costmobile',
      date '2026-07-01',
      12000,
      'km',
      'CAD',
      2500000,
      'Synthetic cost test inventory',
      'request-m2-cost-create-001',
      'ca700000-0000-4000-8000-000000000001'
    ) result
  $$,
  'cost/search fixture inventory is created through the canonical command'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_search_documents document
    where document.inventory_unit_id = (
      select inventory_unit_id from pg_temp.cost_inventory_result
    )
      and document.search_text like '%synthetic%'
  ),
  'T-SEARCH-001 inventory creation refreshes the workspace search document'
);

reset role;
insert into public.media_assets (
  id, workspace_id, inventory_unit_id, owner_entity_type, owner_entity_id,
  media_kind, status, created_by
) values
  (
    'c3100000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    (select inventory_unit_id from pg_temp.cost_inventory_result),
    'inventory_unit', (select inventory_unit_id from pg_temp.cost_inventory_result),
    'legal_document', 'ready', '31000000-0000-4000-8000-000000000001'
  ),
  (
    'c3100000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    null, 'inventory_unit', 'ca300000-0000-4000-8000-000000000099',
    'attachment', 'ready', '31000000-0000-4000-8000-000000000001'
  ),
  (
    'c3100000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    (select inventory_unit_id from pg_temp.cost_inventory_result),
    'inventory_unit', (select inventory_unit_id from pg_temp.cost_inventory_result),
    'legal_document', 'ready', '31000000-0000-4000-8000-000000000001'
  ),
  (
    'c3100000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000001',
    null, 'inventory_unit', (select inventory_unit_id from pg_temp.cost_inventory_result),
    'attachment', 'ready', '31000000-0000-4000-8000-000000000001'
  ),
  (
    'c3100000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000001',
    (select inventory_unit_id from pg_temp.cost_inventory_result),
    'inventory_unit', (select inventory_unit_id from pg_temp.cost_inventory_result),
    'legal_document', 'processing', '31000000-0000-4000-8000-000000000001'
  ),
  (
    'c3200000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    null, 'inventory_unit', (select inventory_unit_id from pg_temp.cost_inventory_result),
    'attachment', 'ready', '32000000-0000-4000-8000-000000000001'
  );

insert into public.media_files (
  id, workspace_id, media_id, file_class, variant, storage_bucket,
  storage_object_key, storage_generation, mime_type, byte_size,
  checksum_sha256, metadata_stripped, retention_policy, verification_receipt
)
select
  fixture.id,
  fixture.workspace_id,
  fixture.media_id,
  'legal_document_original',
  'legal_original',
  'media-private',
  fixture.object_key,
  fixture.generation,
  'application/pdf',
  fixture.byte_size,
  fixture.checksum_sha256,
  false,
  'preserve_original',
  pg_temp.legal_file_receipt(
    fixture.object_key, fixture.generation, fixture.byte_size, fixture.checksum_sha256
  )
from (values
  (
    'c3300000-0000-4000-8000-000000000001'::uuid,
    '10000000-0000-4000-8000-000000000001'::uuid,
    'c3100000-0000-4000-8000-000000000001'::uuid,
    'workspaces/10000000-0000-4000-8000-000000000001/inventory-units/cost-fixture/valid.pdf'::text,
    'cost-generation-valid'::text, 101::bigint, repeat('1', 64)::text
  ),
  (
    'c3300000-0000-4000-8000-000000000002'::uuid,
    '10000000-0000-4000-8000-000000000001'::uuid,
    'c3100000-0000-4000-8000-000000000002'::uuid,
    'workspaces/10000000-0000-4000-8000-000000000001/inventory-units/cost-fixture/wrong-owner.pdf'::text,
    'cost-generation-owner'::text, 102::bigint, repeat('2', 64)::text
  ),
  (
    'c3300000-0000-4000-8000-000000000005'::uuid,
    '10000000-0000-4000-8000-000000000001'::uuid,
    'c3100000-0000-4000-8000-000000000005'::uuid,
    'workspaces/10000000-0000-4000-8000-000000000001/inventory-units/cost-fixture/not-ready.pdf'::text,
    'cost-generation-ready'::text, 105::bigint, repeat('5', 64)::text
  ),
  (
    'c3300000-0000-4000-8000-000000000006'::uuid,
    '20000000-0000-4000-8000-000000000002'::uuid,
    'c3200000-0000-4000-8000-000000000001'::uuid,
    'workspaces/20000000-0000-4000-8000-000000000002/inventory-units/cost-fixture/cross-workspace.pdf'::text,
    'cost-generation-cross'::text, 106::bigint, repeat('6', 64)::text
  )
) as fixture(
  id, workspace_id, media_id, object_key, generation, byte_size, checksum_sha256
);
insert into public.media_files (
  id, workspace_id, media_id, file_class, variant, storage_bucket,
  storage_object_key, mime_type, byte_size, checksum_sha256,
  metadata_stripped, retention_policy
) values (
  'c3300000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  'c3100000-0000-4000-8000-000000000003',
  'document_preview', 'preview', 'media-private',
  'workspaces/10000000-0000-4000-8000-000000000001/inventory-units/cost-fixture/preview.pdf',
  'application/pdf', 103, repeat('3', 64), false, 'retain_until_archive'
);
insert into public.media_files (
  id, workspace_id, media_id, file_class, variant, storage_bucket,
  storage_object_key, mime_type, byte_size, checksum_sha256,
  metadata_stripped, retention_policy, delete_after, deleted_at
) values (
  'c3300000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000001',
  'c3100000-0000-4000-8000-000000000004',
  'vehicle_photo_raw', 'raw_original', 'media-private',
  'workspaces/10000000-0000-4000-8000-000000000001/inventory-units/cost-fixture/deleted.bin',
  'application/pdf', 104, repeat('4', 64), false,
  'delete_after_verified_master',
  pg_catalog.statement_timestamp() - interval '2 days',
  pg_catalog.statement_timestamp() - interval '1 day'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;

select extensions.lives_ok(
  $$
    insert into pg_temp.cost_command_results
    select result.*, 'posted'
    from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-post-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      1,
      'ca100000-0000-4000-8000-000000000001',
      9007199254740993,
      'cad',
      date '2026-07-10',
      null,
      'Synthetic reconditioning cost',
      'c3300000-0000-4000-8000-000000000001',
      'request-m2-cost-post-001',
      'ca700000-0000-4000-8000-000000000002'
    ) result
  $$,
  'M2-INV-AC-007 exact minor-unit cost posting succeeds'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.cost_command_results result
    join public.inventory_cost_entries entry on entry.id = result.cost_entry_id
    join public.audit_events audit on audit.id = result.audit_event_id
    join public.outbox_events event on event.id = result.outbox_event_id
    where result.probe = 'posted'
      and not result.replayed
      and result.aggregate_version = 2
      and entry.supporting_file_id = 'c3300000-0000-4000-8000-000000000001'
      and audit.action = 'inventory_cost.posted'
      and event.event_name = 'inventory_cost.posted'
  ),
  'cost posting returns matching aggregate, audit, and outbox evidence'
);
reset role;
select extensions.ok(
  exists (
    select 1
    from pg_temp.cost_command_results result
    join public.audit_events audit on audit.id = result.audit_event_id
    join public.outbox_events event on event.id = result.outbox_event_id
    where result.probe = 'posted'
      and pg_catalog.jsonb_typeof(audit.after_data -> 'amount_minor') = 'string'
      and audit.after_data ->> 'amount_minor' = '9007199254740993'
      and pg_catalog.jsonb_typeof(event.payload -> 'amountMinor') = 'string'
      and event.payload ->> 'amountMinor' = '9007199254740993'
  ),
  'minor-unit audit and outbox boundaries preserve values above JS safe integer as text'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select metric.posted_cost_minor
    from public.inventory_cost_metrics metric
    where metric.inventory_unit_id = (
      select inventory_unit_id from pg_temp.cost_inventory_result
    )
  ),
  9007199254740993::bigint,
  'T-COST-001 cost metric preserves the exact integer-minor-unit total'
);
select extensions.is(
  (
    select metric.estimated_gross_minor
    from public.inventory_cost_metrics metric
    where metric.inventory_unit_id = (
      select inventory_unit_id from pg_temp.cost_inventory_result
    )
  ),
  (-9007199252240993)::bigint,
  'T-COST-001 estimated gross uses exact integer arithmetic'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.workflow_instances instance
      on instance.workspace_id = unit.workspace_id
     and instance.id = unit.workflow_instance_id
    where unit.id = (select inventory_unit_id from pg_temp.cost_inventory_result)
      and unit.version = 2
      and instance.version = unit.version
  ),
  'cost posting advances inventory and workflow aggregate versions together'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.workflow_instances instance
      on instance.workspace_id = unit.workspace_id
     and instance.id = unit.workflow_instance_id
    where unit.id = (select inventory_unit_id from pg_temp.cost_inventory_result)
      and instance.lifecycle_status = 'active'
      and instance.current_state_key = unit.workflow_state_key
      and instance.canonical_status = unit.status
      and instance.version = unit.version
      and unit.version = 2
  ),
  'cost posting advances the locked active workflow instance before inventory validation'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.cost_command_results
    select result.*, 'replay'
    from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-post-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      1,
      'ca100000-0000-4000-8000-000000000001',
      9007199254740993,
      'CAD',
      date '2026-07-10',
      null,
      'Synthetic reconditioning cost',
      'c3300000-0000-4000-8000-000000000001',
      'request-m2-cost-post-001-replay',
      'ca700000-0000-4000-8000-000000000003'
    ) result
  $$,
  'matching cost idempotency replay succeeds'
);
select extensions.ok(
  (
    select replay.replayed
      and replay.cost_entry_id = posted.cost_entry_id
      and replay.audit_event_id = posted.audit_event_id
      and replay.outbox_event_id = posted.outbox_event_id
    from pg_temp.cost_command_results replay
    cross join pg_temp.cost_command_results posted
    where replay.probe = 'replay' and posted.probe = 'posted'
  ),
  'cost replay returns the original durable evidence without another mutation'
);
select extensions.throws_ok(
  $$
    select * from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-post-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      2,
      'ca100000-0000-4000-8000-000000000001',
      125001,
      'CAD',
      date '2026-07-10', null, null, null, null,
      'ca700000-0000-4000-8000-000000000004'
    )
  $$,
  '23505',
  'cost idempotency key was used for a different command',
  'T-COST-002 cost idempotency keys reject a different command fingerprint'
);
select extensions.throws_ok(
  $$
    select * from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-stale-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      1,
      'ca100000-0000-4000-8000-000000000001',
      1000,
      'CAD',
      date '2026-07-10', null, null, null, null,
      'ca700000-0000-4000-8000-000000000005'
    )
  $$,
  '40001',
  'inventory version conflict',
  'concurrent stale cost commands fail closed'
);
select extensions.throws_ok(
  $$
    select * from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-scope-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      2,
      'ca200000-0000-4000-8000-000000000001',
      1000,
      'CAD',
      date '2026-07-10', null, null, null, null,
      'ca700000-0000-4000-8000-000000000006'
    )
  $$,
  '23514',
  'an active cost category is required',
  'T-TEN-001 another workspace cost category cannot cross the aggregate boundary'
);
select extensions.throws_ok(
  $$
    select * from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-file-owner-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      2, 'ca100000-0000-4000-8000-000000000001', 1000, 'CAD',
      date '2026-07-10', null, null,
      'c3300000-0000-4000-8000-000000000002',
      'request-m2-cost-file-owner-001',
      'ca700000-0000-4000-8000-000000000012'
    )
  $$,
  '23514',
  'cost supporting file is unavailable',
  'cost evidence owned by another aggregate is rejected'
);
select extensions.throws_ok(
  $$
    select * from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-file-class-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      2, 'ca100000-0000-4000-8000-000000000001', 1000, 'CAD',
      date '2026-07-10', null, null,
      'c3300000-0000-4000-8000-000000000003',
      'request-m2-cost-file-class-001',
      'ca700000-0000-4000-8000-000000000013'
    )
  $$,
  '23514',
  'cost supporting file is unavailable',
  'document previews cannot be attached as preserved cost evidence'
);
select extensions.throws_ok(
  $$
    select * from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-file-deleted-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      2, 'ca100000-0000-4000-8000-000000000001', 1000, 'CAD',
      date '2026-07-10', null, null,
      'c3300000-0000-4000-8000-000000000004',
      'request-m2-cost-file-deleted-001',
      'ca700000-0000-4000-8000-000000000014'
    )
  $$,
  '23514',
  'cost supporting file is unavailable',
  'deleted managed files cannot be attached as cost evidence'
);
select extensions.throws_ok(
  $$
    select * from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-file-not-ready',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      2, 'ca100000-0000-4000-8000-000000000001', 1000, 'CAD',
      date '2026-07-10', null, null,
      'c3300000-0000-4000-8000-000000000005',
      'request-m2-cost-file-not-ready',
      'ca700000-0000-4000-8000-000000000015'
    )
  $$,
  '23514',
  'cost supporting file is unavailable',
  'unverified managed files cannot be attached as cost evidence'
);
select extensions.throws_ok(
  $$
    select * from app.post_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-file-cross-001',
      (select inventory_unit_id from pg_temp.cost_inventory_result),
      2, 'ca100000-0000-4000-8000-000000000001', 1000, 'CAD',
      date '2026-07-10', null, null,
      'c3300000-0000-4000-8000-000000000006',
      'request-m2-cost-file-cross-001',
      'ca700000-0000-4000-8000-000000000016'
    )
  $$,
  '23514',
  'cost supporting file is unavailable',
  'another workspace managed file cannot cross the cost aggregate boundary'
);
reset role;
select extensions.throws_ok(
  $$
    update public.inventory_cost_entries
    set amount_minor = amount_minor + 1
    where id = (
      select cost_entry_id from pg_temp.cost_command_results where probe = 'posted'
    )
  $$,
  '55000',
  'posted inventory cost history is append-only',
  'T-COST-002 posted cost history cannot be rewritten'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;

select extensions.ok(
  exists (
    select 1
    from app.search_inventory_units(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_query => 'synthetic',
      p_page_size => 10
    ) result
    where result.inventory_unit_id = (
      select inventory_unit_id from pg_temp.cost_inventory_result
    )
      and result.advertised_price_minor = '2500000'
      and result.posted_cost_minor = '9007199254740993'
      and result.estimated_gross_minor = '-9007199252240993'
  ),
  'M2-INV-AC-009 search returns bounded precision-preserving cost-aware results'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal2');
select extensions.ok(
  exists (
    select 1
    from app.search_inventory_units(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_query => 'synthetic',
      p_page_size => 10
    ) result
    where result.inventory_unit_id = (
      select inventory_unit_id from pg_temp.cost_inventory_result
    )
      and result.posted_cost_minor is null
      and result.estimated_gross_minor is null
  ),
  'M2-INV-AC-009 inventory readers without costs.read receive masked cost fields'
);
select extensions.throws_ok(
  $$
    select * from app.save_inventory_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-share-denied-001',
      null,
      null,
      'Shared without authority',
      '{}'::jsonb,
      '{"key":"updated_at","direction":"desc"}'::jsonb,
      '["stock"]'::jsonb,
      'responsive',
      'comfortable',
      'workspace',
      null,
      'ca700000-0000-4000-8000-000000000012'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'workspace-shared views require inventory update authority'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001', 'aal2');
select extensions.throws_ok(
  $$
    select * from app.search_inventory_units(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_page_size => 10
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'T-TEN-001 another workspace administrator cannot search Northstar inventory'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
select extensions.throws_ok(
  $$
    select * from app.search_inventory_units(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_statuses => array['draft', 'active', 'pending', 'closed', 'archived', 'active'],
      p_page_size => 10
    )
  $$,
  '22023',
  'invalid inventory status filter',
  'T-SEARCH-001 status filters enforce the application cardinality bound'
);
select extensions.throws_ok(
  $$
    select * from app.search_inventory_units(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_location_ids => array[null::uuid],
      p_page_size => 10
    )
  $$,
  '22023',
  'invalid inventory location filter',
  'T-SEARCH-001 location UUID arrays reject null elements'
);
select extensions.throws_ok(
  $$
    select * from app.search_inventory_units(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_maximum_days_in_stock => 100001,
      p_page_size => 10
    )
  $$,
  '22023',
  'invalid inventory age filter',
  'T-SEARCH-001 inventory age filters enforce the application upper bound'
);
select extensions.throws_ok(
  $$
    select * from app.search_inventory_units(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_page_size => null
    )
  $$,
  '22023',
  'inventory page size must be from 1 to 100',
  'T-SEARCH-001 explicit null cannot disable the inventory result bound'
);
select extensions.throws_ok(
  $$
    select * from app.search_inventory_units(
      p_workspace_id => '10000000-0000-4000-8000-000000000001',
      p_page_size => 101
    )
  $$,
  '22023',
  'inventory page size must be from 1 to 100',
  'T-SEARCH-001 unbounded page sizes fail closed'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
select extensions.throws_ok(
  $$
    select * from app.reverse_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-reverse-001',
      (select cost_entry_id from pg_temp.cost_command_results where probe = 'posted'),
      2,
      date '2026-07-11',
      'Synthetic correction',
      'request-m2-cost-reverse-001',
      'ca700000-0000-4000-8000-000000000007'
    )
  $$,
  '42501',
  'active workspace membership and permission are required',
  'M2-INV-AC-007 AAL1 administrator is denied before cost reversal'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
select extensions.throws_ok(
  $$
    select * from app.reverse_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-reverse-before-incurred',
      (select cost_entry_id from pg_temp.cost_command_results where probe = 'posted'),
      2,
      date '2026-07-09',
      'Impossible correction date',
      'request-m2-cost-reverse-before-incurred',
      'ca700000-0000-4000-8000-000000000016'
    )
  $$,
  '22023',
  'invalid reversal date',
  'T-COST-002 reversal date cannot precede the original incurred date'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.reversal_command_results
    select * from app.reverse_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-reverse-001',
      (select cost_entry_id from pg_temp.cost_command_results where probe = 'posted'),
      2,
      date '2026-07-11',
      'Synthetic correction',
      'request-m2-cost-reverse-001',
      'ca700000-0000-4000-8000-000000000007'
    )
  $$,
  'M2-INV-AC-007 an authorized reversal appends a correction entry'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.reversal_command_results result
    join public.audit_events audit on audit.id = result.audit_event_id
    join public.outbox_events event on event.id = result.outbox_event_id
    where not result.replayed
      and result.aggregate_version = 3
      and audit.action = 'inventory_cost.reversed'
      and audit.auth_assurance = 'aal2'
      and event.event_name = 'inventory_cost.reversed'
  ),
  'reversal returns strong-auth audit and matching outbox evidence'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_units unit
    join public.workflow_instances instance
      on instance.workspace_id = unit.workspace_id
     and instance.id = unit.workflow_instance_id
    where unit.id = (select inventory_unit_id from pg_temp.cost_inventory_result)
      and instance.lifecycle_status = 'active'
      and instance.current_state_key = unit.workflow_state_key
      and instance.canonical_status = unit.status
      and instance.version = unit.version
      and unit.version = 3
  ),
  'cost reversal advances the locked active workflow instance before inventory validation'
);
select extensions.is(
  (
    select metric.posted_cost_minor
    from public.inventory_cost_metrics metric
    where metric.inventory_unit_id = (
      select inventory_unit_id from pg_temp.cost_inventory_result
    )
  ),
  0::bigint,
  'reversal projection subtracts the original exact cost amount'
);
select extensions.ok(
  exists (
    select 1
    from public.inventory_cost_entries reversal
    join public.inventory_cost_entries original
      on original.workspace_id = reversal.workspace_id
     and original.id = reversal.reversal_of_id
    where reversal.id = (
      select reversal_entry_id from pg_temp.reversal_command_results
    )
      and reversal.entry_kind = 'reversal'
      and original.entry_kind = 'cost'
      and reversal.amount_minor = original.amount_minor
  ),
  'T-COST-002 correction history preserves linked original and reversal entries'
);
select extensions.is(
  (
    select history.effective_status
    from public.inventory_cost_entry_history history
    where history.id = (
      select cost_entry_id from pg_temp.cost_command_results where probe = 'posted'
    )
  ),
  'reversed'::text,
  'append-only cost history derives reversed status without mutating the original row'
);
select extensions.throws_ok(
  $$
    select * from app.reverse_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'm2-cost-reverse-002',
      (select cost_entry_id from pg_temp.cost_command_results where probe = 'posted'),
      3,
      date '2026-07-11',
      'Duplicate correction',
      null,
      'ca700000-0000-4000-8000-000000000008'
    )
  $$,
  '23514',
  'cost entry is already reversed',
  'a cost entry can be reversed at most once'
);

select extensions.lives_ok(
  $$
    insert into pg_temp.saved_view_results
    select result.*, 'created'
    from app.save_inventory_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-save-001',
      null,
      null,
      'Synthetic ready inventory',
      '{"status":["active"]}'::jsonb,
      '{"key":"updated_at","direction":"desc"}'::jsonb,
      '["stock","vehicle","state","price"]'::jsonb,
      'responsive',
      'comfortable',
      'private',
      'request-m2-view-save-001',
      'ca700000-0000-4000-8000-000000000009'
    ) result
  $$,
  'M2-INV-AC-009 a validated versioned inventory view can be saved'
);
select extensions.ok(
  exists (
    select 1
    from pg_temp.saved_view_results result
    join public.inventory_saved_views saved_view on saved_view.id = result.saved_view_id
    join public.audit_events audit on audit.id = result.audit_event_id
    where result.probe = 'created'
      and not result.replayed
      and result.saved_view_version = 1
      and saved_view.owner_user_id = auth.uid()
      and audit.action = 'inventory_saved_view.created'
  ),
  'saved view ownership, version, and audit evidence are authoritative'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.saved_view_results
    select result.*, 'replay'
    from app.save_inventory_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-save-001',
      null,
      null,
      'Synthetic ready inventory',
      '{"status":["active"]}'::jsonb,
      '{"key":"updated_at","direction":"desc"}'::jsonb,
      '["stock","vehicle","state","price"]'::jsonb,
      'responsive',
      'comfortable',
      'private',
      'request-m2-view-save-replay',
      'ca700000-0000-4000-8000-000000000010'
    ) result
  $$,
  'matching saved-view idempotency replay succeeds'
);
select extensions.ok(
  (
    select replay.replayed
      and replay.saved_view_id = created.saved_view_id
      and replay.saved_view_version = created.saved_view_version
      and replay.audit_event_id = created.audit_event_id
    from pg_temp.saved_view_results replay
    cross join pg_temp.saved_view_results created
    where replay.probe = 'replay' and created.probe = 'created'
  ),
  'saved-view replay returns the original durable receipt'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002', 'aal2');
select extensions.lives_ok(
  $$
    insert into pg_temp.saved_view_results
    select result.*, 'second-created'
    from app.save_inventory_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-save-001',
      null,
      null,
      'Second user private inventory',
      '{"status":["active"]}'::jsonb,
      '{"key":"updated_at","direction":"desc"}'::jsonb,
      '["stock","vehicle","state","price"]'::jsonb,
      'responsive',
      'comfortable',
      'private',
      'request-m2-view-save-second',
      'ca700000-0000-4000-8000-000000000013'
    ) result
  $$,
  'a second workspace user can reuse a private saved-view idempotency key'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.saved_view_results
    select result.*, 'second-replay'
    from app.save_inventory_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-save-001',
      null,
      null,
      'Second user private inventory',
      '{"status":["active"]}'::jsonb,
      '{"key":"updated_at","direction":"desc"}'::jsonb,
      '["stock","vehicle","state","price"]'::jsonb,
      'responsive',
      'comfortable',
      'private',
      'request-m2-view-save-second-replay',
      'ca700000-0000-4000-8000-000000000014'
    ) result
  $$,
  'the second workspace user replays only their own private command'
);
reset role;
select extensions.ok(
  (
    select
      not second_created.replayed
      and second_replay.replayed
      and second_replay.saved_view_id = second_created.saved_view_id
      and second_replay.audit_event_id = second_created.audit_event_id
      and second_created.saved_view_id <> first_created.saved_view_id
      and saved_view.owner_user_id = '31000000-0000-4000-8000-000000000002'
      and (
        select pg_catalog.count(*) = 2
          and pg_catalog.count(distinct receipt.actor_user_id) = 2
        from public.inventory_saved_view_command_receipts receipt
        where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
          and receipt.idempotency_key = 'm2-view-save-001'
      )
    from pg_temp.saved_view_results second_created
    join pg_temp.saved_view_results second_replay
      on second_replay.probe = 'second-replay'
    join pg_temp.saved_view_results first_created
      on first_created.probe = 'created'
    join public.inventory_saved_views saved_view
      on saved_view.id = second_created.saved_view_id
    where second_created.probe = 'second-created'
  ),
  'private saved-view receipts, replays, and results remain isolated by actor'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
reset role;
select extensions.ok(
  not app.inventory_saved_view_payload_valid(
    '{"status":"active"}'::jsonb,
    '{"key":"updated_at","direction":"desc"}'::jsonb,
    '["stock"]'::jsonb
  )
  and not app.inventory_saved_view_payload_valid(
    '{"locationIds":["not-a-uuid"]}'::jsonb,
    '{"key":"updated_at","direction":"desc"}'::jsonb,
    '["stock"]'::jsonb
  )
  and not app.inventory_saved_view_payload_valid(
    '{"minimumPriceMinor":"11","maximumPriceMinor":"10"}'::jsonb,
    '{"key":"updated_at","direction":"desc"}'::jsonb,
    '["stock"]'::jsonb
  )
  and not app.inventory_saved_view_payload_valid(
    '{"minimumDaysInStock":1.5,"missingFields":["unsafe"]}'::jsonb,
    '{"key":"updated_at","direction":"desc"}'::jsonb,
    '["stock"]'::jsonb
  ),
  'saved-view SQL validates filter types, enums, UUID arrays, ranges, and integer bounds'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.save_inventory_view(
      '10000000-0000-4000-8000-000000000001',
      'm2-view-invalid-001',
      null,
      null,
      'Unsafe view',
      '{"rawSql":"delete from inventory_units"}'::jsonb,
      '{"key":"updated_at","direction":"desc"}'::jsonb,
      '["stock"]'::jsonb,
      'responsive',
      'comfortable',
      'private',
      null,
      'ca700000-0000-4000-8000-000000000011'
    )
  $$,
  '22023',
  'invalid saved-view configuration',
  'saved views reject arbitrary query or SQL configuration'
);

reset role;
select extensions.throws_ok(
  $$
    update public.inventory_saved_view_command_receipts
    set saved_view_version = saved_view_version + 1
    where saved_view_id = (
      select saved_view_id from pg_temp.saved_view_results where probe = 'created'
    )
  $$,
  '55000',
  'posted inventory cost history is append-only',
  'saved-view command receipts are append-only'
);
select extensions.ok(
  exists (
    select 1
    from public.audit_events audit
    where audit.correlation_id in (
      'ca700000-0000-4000-8000-000000000002',
      'ca700000-0000-4000-8000-000000000007',
      'ca700000-0000-4000-8000-000000000009'
    )
      and audit.action in (
        'inventory_cost.posted',
        'inventory_cost.reversed',
        'inventory_saved_view.created'
      )
    group by audit.workspace_id
    having pg_catalog.count(*) = 3
  ),
  'T-AUD-001 M2 cost and saved-view commands preserve correlation traceability'
);

select * from extensions.finish();
rollback;
