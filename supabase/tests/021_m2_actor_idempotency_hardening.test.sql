-- VYN-INV-001, VYN-COST-001, VYN-MEDIA-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001, T-TEN-001, T-RBAC-001,
-- M2-INV-AC-005, M2-INV-AC-006, M2-MEDIA-AC-021
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(45);

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

create temporary table pg_temp.actor_command_results (
  actor_user_id uuid primary key,
  inventory_unit_id uuid,
  cost_entry_id uuid,
  media_id uuid,
  upload_session_id uuid,
  collection_version bigint,
  media_version bigint
);
grant all on pg_temp.actor_command_results to authenticated, service_role;

-- The second active fixture member receives the same permission set so this
-- suite isolates actor identity rather than role capability.
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '61000000-0000-4000-8000-000000000021',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '51000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.locations (
  id, workspace_id, key, name, status, address, contact
) values (
  '73000000-0000-4000-8000-000000000021',
  '10000000-0000-4000-8000-000000000001',
  'synthetic.actor_hardening',
  'Actor hardening synthetic location',
  'active',
  '{}'::jsonb,
  '{}'::jsonb
);

select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_indexes index_row
    where index_row.schemaname = 'public'
      and index_row.indexname = 'inventory_command_receipts_actor_key_uidx'
      and index_row.indexdef like
        '%(workspace_id, actor_user_id, command_type, idempotency_key)%'
  )
  and not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.inventory_command_receipts'::pg_catalog.regclass
      and constraint_row.contype = 'u'
      and pg_catalog.pg_get_constraintdef(constraint_row.oid, false) =
        'UNIQUE (workspace_id, command_type, idempotency_key)'
  ),
  'T-TEN-001 inventory uniqueness includes actor and removes the shared key namespace'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_indexes index_row
    where index_row.schemaname = 'public'
      and index_row.indexname = 'inventory_cost_entries_actor_key_uidx'
      and index_row.indexdef like
        '%(workspace_id, created_by, entry_kind, idempotency_key)%'
  )
  and not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.inventory_cost_entries'::pg_catalog.regclass
      and constraint_row.contype = 'u'
      and pg_catalog.pg_get_constraintdef(constraint_row.oid, false) =
        'UNIQUE (workspace_id, idempotency_key)'
  ),
  'T-TEN-001 cost uniqueness includes actor and kind without a shared key namespace'
);
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_indexes index_row
    where index_row.schemaname = 'public'
      and index_row.indexname = 'media_command_receipts_actor_key_uidx'
      and index_row.indexdef like
        '%(workspace_id, actor_user_id, command_type, idempotency_key)%'
  )
  and exists (
    select 1 from pg_catalog.pg_indexes index_row
    where index_row.schemaname = 'public'
      and index_row.indexname = 'media_command_receipts_actorless_key_uidx'
      and index_row.indexdef like
        '%(workspace_id, command_type, idempotency_key)%'
      and index_row.indexdef like '%WHERE (actor_user_id IS NULL)%'
  )
  and not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.media_command_receipts'::pg_catalog.regclass
      and constraint_row.contype = 'u'
      and pg_catalog.pg_get_constraintdef(constraint_row.oid, false) =
        'UNIQUE (workspace_id, command_type, idempotency_key)'
  ),
  'T-TEN-001 media uniqueness separates attributed actors and actorless workers'
);
select extensions.ok(
  (
    select pg_catalog.bool_and(
      not pg_catalog.has_function_privilege(
        'anon', helper.signature, 'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'authenticated', helper.signature, 'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'service_role', helper.signature, 'EXECUTE'
      )
    )
    from (
      values
        ('app.actor_idempotency_storage_key(uuid,uuid,text,text)'),
        ('app.inventory_actor_idempotency_key(uuid,uuid,text,text)'),
        ('app.cost_actor_idempotency_key(uuid,uuid,text,text)'),
        ('app.media_actor_idempotency_key(uuid,uuid,text,text)')
    ) helper(signature)
  ),
  'T-RBAC-001 actor-key helpers are owner-internal'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from (
      values
        ('app.update_inventory_unit_details_actor_key_impl(uuid,text,uuid,bigint,text,date,timestamp with time zone,timestamp with time zone,bigint,text,bigint,bigint,text,text,boolean,text,text,uuid)'),
        ('app.transfer_inventory_unit_location_actor_key_impl(uuid,text,uuid,bigint,uuid,text,text,uuid)'),
        ('app.transition_inventory_workflow_actor_key_impl(uuid,text,uuid,bigint,text,text,text,uuid)'),
        ('app.post_inventory_cost_entry_actor_key_impl(uuid,text,uuid,bigint,uuid,bigint,text,date,uuid,text,uuid,text,uuid)'),
        ('app.reverse_inventory_cost_entry_actor_key_impl(uuid,text,uuid,bigint,date,text,text,uuid)'),
        ('app.create_vehicle_photo_upload_session_actor_key_impl(uuid,text,uuid,text,text,bigint,text,text,uuid)'),
        ('app.complete_vehicle_photo_upload_actor_key_impl(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)'),
        ('app.reprocess_vehicle_photo_actor_key_impl(uuid,text,uuid,bigint,text,text,uuid)'),
        ('app.reorder_inventory_media_actor_key_impl(uuid,text,uuid,bigint,jsonb,text,uuid)'),
        ('app.set_inventory_media_cover_actor_key_impl(uuid,text,uuid,uuid,bigint,text,uuid)'),
        ('app.record_preserved_legal_original_actor_key_impl(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)'),
        ('app.set_managed_media_retention_hold_actor_key_impl(uuid,text,uuid,bigint,boolean,text,text,text,uuid)'),
        ('app.request_vehicle_photo_upload_verification_actor_key_impl(uuid,text,uuid,uuid,text,uuid)'),
        ('app.create_legal_original_upload_session_actor_key_impl(uuid,text,uuid,text,text,text,bigint,text,text,uuid)'),
        ('app.request_legal_original_upload_verification_actor_key_impl(uuid,text,uuid,uuid,text,uuid)'),
        ('app.update_vehicle_media_caption_actor_key_impl(uuid,text,uuid,bigint,text,text,uuid)'),
        ('app.archive_vehicle_media_actor_key_impl(uuid,text,uuid,bigint,bigint,text,text,uuid)')
    ) implementation(signature)
    join pg_catalog.pg_proc proc
      on proc.oid = pg_catalog.to_regprocedure(implementation.signature)
    where pg_catalog.to_regprocedure(implementation.signature) is not null
      and not pg_catalog.has_function_privilege(
        'anon', implementation.signature, 'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'authenticated', implementation.signature, 'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'service_role', implementation.signature, 'EXECUTE'
      )
      and case
        when implementation.signature like
          'app.post_inventory_cost_entry_actor_key_impl(%'
          or implementation.signature like
            'app.reverse_inventory_cost_entry_actor_key_impl(%'
          then proc.prosrc like '%and entry.created_by = actor_user_id%'
            and proc.prosrc like '%and entry.entry_kind = %'
            and proc.prosrc like
              '%|| actor_user_id::text ||%'
        when implementation.signature like
          'app.complete_vehicle_photo_upload_actor_key_impl(%'
          or implementation.signature like
            'app.record_preserved_legal_original_actor_key_impl(%'
          then proc.prosrc like
              '%and receipt.actor_user_id = p_actor_user_id%'
            and proc.prosrc like
              '%|| p_actor_user_id::text ||%'
        else proc.prosrc like
            '%and receipt.actor_user_id = app.current_user_id()%'
          and proc.prosrc like
            '%|| actor_user_id::text ||%'
      end
  ),
  17,
  'T-RBAC-001 every private implementation scopes replay and advisory locks by actor'
);
select extensions.is(
  (
    select pg_catalog.count(*)::integer
    from (
      values
        ('app.update_inventory_unit_details(uuid,text,uuid,bigint,text,date,timestamp with time zone,timestamp with time zone,bigint,text,bigint,bigint,text,text,boolean,text,text,uuid)', 'inventory_actor_idempotency_key'),
        ('app.transfer_inventory_unit_location(uuid,text,uuid,bigint,uuid,text,text,uuid)', 'inventory_actor_idempotency_key'),
        ('app.transition_inventory_workflow(uuid,text,uuid,bigint,text,text,text,uuid)', 'inventory_actor_idempotency_key'),
        ('app.post_inventory_cost_entry(uuid,text,uuid,bigint,uuid,bigint,text,date,uuid,text,uuid,text,uuid)', 'cost_actor_idempotency_key'),
        ('app.reverse_inventory_cost_entry(uuid,text,uuid,bigint,date,text,text,uuid)', 'cost_actor_idempotency_key'),
        ('app.create_vehicle_photo_upload_session(uuid,text,uuid,text,text,bigint,text,text,uuid)', 'media_actor_idempotency_key'),
        ('app.complete_vehicle_photo_upload(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)', 'media_actor_idempotency_key'),
        ('app.reprocess_vehicle_photo(uuid,text,uuid,bigint,text,text,uuid)', 'media_actor_idempotency_key'),
        ('app.reorder_inventory_media(uuid,text,uuid,bigint,jsonb,text,uuid)', 'media_actor_idempotency_key'),
        ('app.set_inventory_media_cover(uuid,text,uuid,uuid,bigint,text,uuid)', 'media_actor_idempotency_key'),
        ('app.record_preserved_legal_original(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)', 'media_actor_idempotency_key'),
        ('app.set_managed_media_retention_hold(uuid,text,uuid,bigint,boolean,text,text,text,uuid)', 'media_actor_idempotency_key'),
        ('app.request_vehicle_photo_upload_verification(uuid,text,uuid,uuid,text,uuid)', 'media_actor_idempotency_key'),
        ('app.create_legal_original_upload_session(uuid,text,uuid,text,text,text,bigint,text,text,uuid)', 'media_actor_idempotency_key'),
        ('app.request_legal_original_upload_verification(uuid,text,uuid,uuid,text,uuid)', 'media_actor_idempotency_key'),
        ('app.update_vehicle_media_caption(uuid,text,uuid,bigint,text,text,uuid)', 'media_actor_idempotency_key'),
        ('app.archive_vehicle_media(uuid,text,uuid,bigint,bigint,text,text,uuid)', 'media_actor_idempotency_key')
    ) wrapper(signature, helper_name)
    join pg_catalog.pg_proc proc
      on proc.oid = pg_catalog.to_regprocedure(wrapper.signature)
    where proc.prosecdef
      and exists (
        select 1
        from pg_catalog.unnest(
          coalesce(proc.proconfig, array[]::text[])
        ) setting
        where setting in ('search_path=', 'search_path=""')
      )
      and pg_catalog.pg_get_functiondef(proc.oid) like
        '%' || wrapper.helper_name || '%'
  ),
  17,
  'T-RBAC-001 every public command wrapper has strict search path and actor-key routing'
);
select extensions.ok(
  (
    select pg_catalog.bool_and(
      app.actor_idempotency_storage_key(
        '10000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000001',
        domain_name,
        'shared-domain-key-021'
      ) = app.actor_idempotency_storage_key(
        '10000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000002',
        domain_name,
        'shared-domain-key-021'
      )
      and app.actor_idempotency_storage_key(
        '10000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000001',
        domain_name,
        'shared-domain-key-021'
      ) = 'shared-domain-key-021'
    )
    from (
      values
        ('update_inventory_unit_details'),
        ('transfer_inventory_unit_location'),
        ('transition_inventory_workflow'),
        ('inventory_cost.cost'),
        ('inventory_cost.reversal'),
        ('media.create_upload'),
        ('media.complete_upload'),
        ('media.reprocess'),
        ('media.reorder'),
        ('media.set_cover'),
        ('media.record_legal'),
        ('media.retention_hold'),
        ('media.request_upload_verification'),
        ('media.create_legal_upload'),
        ('media.request_legal_verify'),
        ('media.update_caption'),
        ('media.archive')
    ) domain(domain_name)
  ),
  'T-TEN-001 adapters preserve raw keys while actor remains a physical namespace coordinate'
);
select extensions.throws_ok(
  $$
    select app.actor_idempotency_storage_key(
      '10000000-0000-4000-8000-000000000001',
      null,
      'media.create_upload',
      'shared-domain-key-021'
    )
  $$,
  '42501',
  'validated idempotency actor is required',
  'T-RBAC-001 actor-less key translation fails closed'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.actor_command_results (
      actor_user_id, inventory_unit_id
    )
    select
      '31000000-0000-4000-8000-000000000001',
      result.inventory_unit_id
    from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'actor-hardening-create-a-021',
      '1HGCM82633A731001',
      2025,
      'Synthetic',
      'Actor A',
      date '2026-07-01',
      21000,
      'km',
      'CAD',
      2500000,
      'Synthetic actor isolation A',
      'request-actor-hardening-create-a-021',
      'a0210000-0000-4000-8000-000000000001'
    ) result
  $$,
  'actor A inventory fixture is created through the canonical command'
);
reset role;

insert into public.inventory_command_receipts (
  workspace_id, command_type, idempotency_key, command_fingerprint,
  inventory_unit_id, result, actor_user_id
) values (
  '10000000-0000-4000-8000-000000000001',
  'update_inventory_unit_details',
  'legacy-same-actor-key-021',
  repeat('1', 64),
  (
    select inventory_unit_id
    from pg_temp.actor_command_results
    where actor_user_id = '31000000-0000-4000-8000-000000000001'
  ),
  '{}'::jsonb,
  '31000000-0000-4000-8000-000000000001'
);
select extensions.is(
  app.inventory_actor_idempotency_key(
    '10000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001',
    'update_inventory_unit_details',
    'legacy-same-actor-key-021'
  ),
  'legacy-same-actor-key-021'::text,
  'same-actor pre-hardening receipts retain replay compatibility'
);
select extensions.is(
  app.inventory_actor_idempotency_key(
    '10000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000002',
    'update_inventory_unit_details',
    'legacy-same-actor-key-021'
  ),
  'legacy-same-actor-key-021'::text,
  'another actor keeps the raw key but uses a separate lock, lookup, and unique tuple'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.actor_command_results (
      actor_user_id, inventory_unit_id
    )
    select
      '31000000-0000-4000-8000-000000000002',
      result.inventory_unit_id
    from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'actor-hardening-create-b-021',
      '1HGCM82633A731002',
      2025,
      'Synthetic',
      'Actor B',
      date '2026-07-02',
      22000,
      'km',
      'CAD',
      2600000,
      'Synthetic actor isolation B',
      'request-actor-hardening-create-b-021',
      'a0210000-0000-4000-8000-000000000002'
    ) result
  $$,
  'actor B can create an independent inventory fixture with equal capability'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'a1:' || pg_catalog.repeat('1', 64),
      (select inventory_unit_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000001'),
      1,
      'used.ready',
      date '2026-07-01',
      timestamptz '2026-07-01 10:00:00+00',
      null,
      21000,
      'km',
      2500000,
      2750000,
      'CAD',
      'Actor A public note',
      true,
      'Actor A restricted note',
      'request-shared-details-a-021',
      'a0210000-0000-4000-8000-000000000003'
    )
  $$,
  'actor A details command succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    select *
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'a1:' || pg_catalog.repeat('1', 64),
      (select inventory_unit_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000002'),
      1,
      'used.ready',
      date '2026-07-02',
      timestamptz '2026-07-02 10:00:00+00',
      null,
      22000,
      'km',
      2600000,
      2850000,
      'CAD',
      'Actor B public note',
      true,
      'Actor B restricted note',
      'request-shared-details-b-021',
      'a0210000-0000-4000-8000-000000000004'
    )
  $$,
  'actor B details command neither replays nor conflicts with actor A'
);
reset role;

select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(distinct receipt.actor_user_id) = 2
      and pg_catalog.count(distinct receipt.idempotency_key) = 1
      and pg_catalog.bool_and(receipt.idempotency_key ~ '^a1:[a-f0-9]{64}$')
      and pg_catalog.count(audit.id) = 2
      and pg_catalog.bool_and(
        audit.actor_user_id = receipt.actor_user_id
      )
      and pg_catalog.count(event.id) = 2
      and pg_catalog.bool_and(
        event.actor_user_id = receipt.actor_user_id
      )
    from public.inventory_command_receipts receipt
    left join public.audit_events audit
      on audit.workspace_id = receipt.workspace_id
     and audit.id = (receipt.result ->> 'audit_event_id')::uuid
    left join public.outbox_events event
      on event.workspace_id = receipt.workspace_id
     and event.id = (receipt.result ->> 'outbox_event_id')::uuid
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'update_inventory_unit_details'
      and receipt.actor_user_id in (
        '31000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000002'
      )
      and receipt.result ->> 'inventory_unit_id' in (
        select inventory_unit_id::text from pg_temp.actor_command_results
      )
  ),
  'digest-shaped inventory keys produce independent actor-owned receipt, audit, and outbox rows'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select replayed
    from app.update_inventory_unit_details(
      '10000000-0000-4000-8000-000000000001',
      'a1:' || pg_catalog.repeat('1', 64),
      (select inventory_unit_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000001'),
      1,
      'used.ready',
      date '2026-07-01',
      timestamptz '2026-07-01 10:00:00+00',
      null,
      21000,
      'km',
      2500000,
      2750000,
      'CAD',
      'Actor A public note',
      true,
      'Actor A restricted note',
      'request-shared-details-a-021',
      'a0210000-0000-4000-8000-000000000003'
    )
  ),
  true,
  'same-actor details retry replays its own durable result'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    select * from app.transfer_inventory_unit_location(
      '10000000-0000-4000-8000-000000000001',
      'shared-transfer-key-021',
      (select inventory_unit_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000001'),
      2,
      '73000000-0000-4000-8000-000000000021',
      'Actor A transfer',
      'request-shared-transfer-a-021',
      'a0210000-0000-4000-8000-000000000005'
    )
  $$,
  'actor A transfer succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    select * from app.transfer_inventory_unit_location(
      '10000000-0000-4000-8000-000000000001',
      'shared-transfer-key-021',
      (select inventory_unit_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000002'),
      2,
      '73000000-0000-4000-8000-000000000021',
      'Actor B transfer',
      'request-shared-transfer-b-021',
      'a0210000-0000-4000-8000-000000000006'
    )
  $$,
  'actor B transfer is not poisoned by actor A'
);
reset role;

select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(distinct receipt.actor_user_id) = 2
      and pg_catalog.count(distinct receipt.idempotency_key) = 1
    from public.inventory_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'transfer_inventory_unit_location'
      and receipt.result ->> 'inventory_unit_id' in (
        select inventory_unit_id::text from pg_temp.actor_command_results
      )
  ),
  'transfer receipts remain actor-isolated'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    select * from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'shared-transition-key-021',
      (select inventory_unit_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000001'),
      3,
      'in_preparation__ready',
      null,
      'request-shared-transition-a-021',
      'a0210000-0000-4000-8000-000000000007'
    )
  $$,
  'actor A workflow transition succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    select * from app.transition_inventory_workflow(
      '10000000-0000-4000-8000-000000000001',
      'shared-transition-key-021',
      (select inventory_unit_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000002'),
      3,
      'in_preparation__ready',
      null,
      'request-shared-transition-b-021',
      'a0210000-0000-4000-8000-000000000008'
    )
  $$,
  'actor B workflow transition is independent of actor A'
);
reset role;

select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(distinct receipt.actor_user_id) = 2
      and pg_catalog.count(distinct receipt.idempotency_key) = 1
    from public.inventory_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'transition_inventory_workflow'
      and receipt.result ->> 'inventory_unit_id' in (
        select inventory_unit_id::text from pg_temp.actor_command_results
      )
  ),
  'workflow transition receipts remain actor-isolated'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    with posted as (
      select * from app.post_inventory_cost_entry(
        '10000000-0000-4000-8000-000000000001',
        'a1:' || pg_catalog.repeat('2', 64),
        (select inventory_unit_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        4,
        'c2100000-0000-4000-8000-000000000003',
        11000,
        'CAD',
        date '2026-07-16',
        null,
        'Actor A reconditioning',
        null,
        'request-shared-cost-a-021',
        'a0210000-0000-4000-8000-000000000009'
      )
    )
    update pg_temp.actor_command_results fixture
    set cost_entry_id = posted.cost_entry_id
    from posted
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000001'
  $$,
  'actor A cost post succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    with posted as (
      select * from app.post_inventory_cost_entry(
        '10000000-0000-4000-8000-000000000001',
        'a1:' || pg_catalog.repeat('2', 64),
        (select inventory_unit_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        4,
        'c2100000-0000-4000-8000-000000000003',
        12000,
        'CAD',
        date '2026-07-16',
        null,
        'Actor B reconditioning',
        null,
        'request-shared-cost-b-021',
        'a0210000-0000-4000-8000-000000000010'
      )
    )
    update pg_temp.actor_command_results fixture
    set cost_entry_id = posted.cost_entry_id
    from posted
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000002'
  $$,
  'actor B cost post does not receive or conflict with actor A result'
);
reset role;

select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(distinct entry.created_by) = 2
      and pg_catalog.count(distinct entry.idempotency_key) = 1
      and pg_catalog.bool_and(entry.idempotency_key ~ '^a1:[a-f0-9]{64}$')
      and pg_catalog.count(audit.id) = 2
      and pg_catalog.bool_and(audit.actor_user_id = entry.created_by)
      and pg_catalog.count(event.id) = 2
      and pg_catalog.bool_and(event.actor_user_id = entry.created_by)
    from public.inventory_cost_entries entry
    left join public.audit_events audit
      on audit.workspace_id = entry.workspace_id
     and audit.entity_type = 'inventory_cost_entry'
     and audit.entity_id = entry.id
     and audit.action = 'inventory_cost.posted'
    left join public.outbox_events event
      on event.workspace_id = entry.workspace_id
     and event.aggregate_type = 'inventory_unit'
     and event.aggregate_id = entry.inventory_unit_id
     and event.aggregate_version = entry.aggregate_version
     and event.event_name = 'inventory_cost.posted'
    where entry.workspace_id = '10000000-0000-4000-8000-000000000001'
      and entry.entry_kind = 'cost'
      and entry.id in (
        select cost_entry_id from pg_temp.actor_command_results
      )
  ),
  'digest-shaped cost keys produce independent actor-owned receipt, audit, and outbox rows'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    select * from app.reverse_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'shared-cost-reversal-key-021',
      (select cost_entry_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000001'),
      5,
      date '2026-07-16',
      'Actor A correction',
      'request-shared-reversal-a-021',
      'a0210000-0000-4000-8000-000000000011'
    )
  $$,
  'actor A cost reversal succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    select * from app.reverse_inventory_cost_entry(
      '10000000-0000-4000-8000-000000000001',
      'shared-cost-reversal-key-021',
      (select cost_entry_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000002'),
      5,
      date '2026-07-16',
      'Actor B correction',
      'request-shared-reversal-b-021',
      'a0210000-0000-4000-8000-000000000012'
    )
  $$,
  'actor B cost reversal is independent of actor A'
);
reset role;

select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(distinct entry.created_by) = 2
      and pg_catalog.count(distinct entry.idempotency_key) = 1
      and pg_catalog.count(audit.id) = 2
      and pg_catalog.bool_and(audit.actor_user_id = entry.created_by)
      and pg_catalog.count(event.id) = 2
      and pg_catalog.bool_and(event.actor_user_id = entry.created_by)
    from public.inventory_cost_entries entry
    left join public.audit_events audit
      on audit.workspace_id = entry.workspace_id
     and audit.entity_type = 'inventory_cost_entry'
     and audit.entity_id = entry.id
     and audit.action = 'inventory_cost.reversed'
    left join public.outbox_events event
      on event.workspace_id = entry.workspace_id
     and event.aggregate_type = 'inventory_unit'
     and event.aggregate_id = entry.inventory_unit_id
     and event.aggregate_version = entry.aggregate_version
     and event.event_name = 'inventory_cost.reversed'
    where entry.workspace_id = '10000000-0000-4000-8000-000000000001'
      and entry.entry_kind = 'reversal'
      and entry.reversal_of_id in (
        select cost_entry_id from pg_temp.actor_command_results
      )
  ),
  'cost reversal history remains actor-isolated'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    with uploaded as (
      select * from app.create_vehicle_photo_upload_session(
        '10000000-0000-4000-8000-000000000001',
        'a1:' || pg_catalog.repeat('3', 64),
        (select inventory_unit_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        'actor-a.jpg',
        'image/jpeg',
        1024,
        repeat('a', 64),
        'request-shared-upload-a-021',
        'a0210000-0000-4000-8000-000000000013'
      )
    )
    update pg_temp.actor_command_results fixture
    set media_id = uploaded.media_id,
        upload_session_id = uploaded.upload_session_id,
        collection_version = uploaded.collection_version,
        media_version = uploaded.aggregate_version
    from uploaded
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000001'
  $$,
  'actor A upload intent succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    with uploaded as (
      select * from app.create_vehicle_photo_upload_session(
        '10000000-0000-4000-8000-000000000001',
        'a1:' || pg_catalog.repeat('3', 64),
        (select inventory_unit_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        'actor-b.jpg',
        'image/jpeg',
        2048,
        repeat('b', 64),
        'request-shared-upload-b-021',
        'a0210000-0000-4000-8000-000000000014'
      )
    )
    update pg_temp.actor_command_results fixture
    set media_id = uploaded.media_id,
        upload_session_id = uploaded.upload_session_id,
        collection_version = uploaded.collection_version,
        media_version = uploaded.aggregate_version
    from uploaded
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000002'
  $$,
  'actor B upload intent neither receives nor conflicts with actor A result'
);
reset role;

select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(distinct receipt.actor_user_id) = 2
      and pg_catalog.count(distinct receipt.idempotency_key) = 1
      and pg_catalog.bool_and(receipt.idempotency_key ~ '^a1:[a-f0-9]{64}$')
      and pg_catalog.count(audit.id) = 2
      and pg_catalog.bool_and(
        audit.actor_user_id = receipt.actor_user_id
      )
      and pg_catalog.count(event.id) = 2
      and pg_catalog.bool_and(
        event.actor_user_id = receipt.actor_user_id
      )
    from public.media_command_receipts receipt
    left join public.audit_events audit
      on audit.workspace_id = receipt.workspace_id
     and audit.id = (receipt.result ->> 'audit_event_id')::uuid
    left join public.outbox_events event
      on event.workspace_id = receipt.workspace_id
     and event.id = (receipt.result ->> 'outbox_event_id')::uuid
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'media.create_upload'
      and receipt.result ->> 'media_id' in (
        select media_id::text from pg_temp.actor_command_results
      )
  ),
  'digest-shaped media keys produce independent actor-owned receipt, audit, and outbox rows'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    with requested as (
      select * from app.request_vehicle_photo_upload_verification(
        '10000000-0000-4000-8000-000000000001',
        'shared-upload-verify-key-021',
        (select media_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        (select upload_session_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        'request-shared-verify-a-021',
        'a0210000-0000-4000-8000-000000000015'
      )
    )
    update pg_temp.actor_command_results fixture
    set media_version = requested.aggregate_version
    from requested
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000001'
  $$,
  'actor A upload verification request succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    with requested as (
      select * from app.request_vehicle_photo_upload_verification(
        '10000000-0000-4000-8000-000000000001',
        'shared-upload-verify-key-021',
        (select media_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        (select upload_session_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        'request-shared-verify-b-021',
        'a0210000-0000-4000-8000-000000000016'
      )
    )
    update pg_temp.actor_command_results fixture
    set media_version = requested.aggregate_version
    from requested
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000002'
  $$,
  'actor B verification request is not poisoned by actor A'
);
reset role;

select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(distinct receipt.actor_user_id) = 2
      and pg_catalog.count(distinct receipt.idempotency_key) = 1
    from public.media_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.command_type = 'media.request_upload_verification'
      and receipt.result ->> 'media_id' in (
        select media_id::text from pg_temp.actor_command_results
      )
  ),
  'upload verification receipts remain actor-isolated'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    with reordered as (
      select * from app.reorder_inventory_media(
        '10000000-0000-4000-8000-000000000001',
        'shared-media-reorder-key-021',
        (select inventory_unit_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        (select collection_version from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        pg_catalog.jsonb_build_array(
          (select media_id from pg_temp.actor_command_results
           where actor_user_id = '31000000-0000-4000-8000-000000000001')
        ),
        'request-shared-reorder-a-021',
        'a0210000-0000-4000-8000-000000000017'
      )
    )
    update pg_temp.actor_command_results fixture
    set collection_version = reordered.collection_version
    from reordered
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000001'
  $$,
  'actor A media reorder succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    with reordered as (
      select * from app.reorder_inventory_media(
        '10000000-0000-4000-8000-000000000001',
        'shared-media-reorder-key-021',
        (select inventory_unit_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        (select collection_version from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        pg_catalog.jsonb_build_array(
          (select media_id from pg_temp.actor_command_results
           where actor_user_id = '31000000-0000-4000-8000-000000000002')
        ),
        'request-shared-reorder-b-021',
        'a0210000-0000-4000-8000-000000000018'
      )
    )
    update pg_temp.actor_command_results fixture
    set collection_version = reordered.collection_version
    from reordered
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000002'
  $$,
  'actor B media reorder is independent of actor A'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    with covered as (
      select * from app.set_inventory_media_cover(
        '10000000-0000-4000-8000-000000000001',
        'shared-media-cover-key-021',
        (select inventory_unit_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        (select media_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        (select collection_version from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        'request-shared-cover-a-021',
        'a0210000-0000-4000-8000-000000000019'
      )
    )
    update pg_temp.actor_command_results fixture
    set collection_version = covered.collection_version
    from covered
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000001'
  $$,
  'actor A cover command succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    with covered as (
      select * from app.set_inventory_media_cover(
        '10000000-0000-4000-8000-000000000001',
        'shared-media-cover-key-021',
        (select inventory_unit_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        (select media_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        (select collection_version from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        'request-shared-cover-b-021',
        'a0210000-0000-4000-8000-000000000020'
      )
    )
    update pg_temp.actor_command_results fixture
    set collection_version = covered.collection_version
    from covered
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000002'
  $$,
  'actor B cover command is independent of actor A'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    with captioned as (
      select * from app.update_vehicle_media_caption(
        '10000000-0000-4000-8000-000000000001',
        'shared-media-caption-key-021',
        (select media_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        (select media_version from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000001'),
        'Actor A caption',
        'request-shared-caption-a-021',
        'a0210000-0000-4000-8000-000000000021'
      )
    )
    update pg_temp.actor_command_results fixture
    set media_version = captioned.media_version
    from captioned
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000001'
  $$,
  'actor A caption succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    with captioned as (
      select * from app.update_vehicle_media_caption(
        '10000000-0000-4000-8000-000000000001',
        'shared-media-caption-key-021',
        (select media_id from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        (select media_version from pg_temp.actor_command_results
         where actor_user_id = '31000000-0000-4000-8000-000000000002'),
        'Actor B caption',
        'request-shared-caption-b-021',
        'a0210000-0000-4000-8000-000000000022'
      )
    )
    update pg_temp.actor_command_results fixture
    set media_version = captioned.media_version
    from captioned
    where fixture.actor_user_id = '31000000-0000-4000-8000-000000000002'
  $$,
  'actor B caption is independent of actor A'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    select * from app.archive_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      'shared-media-archive-key-021',
      (select media_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000001'),
      (select media_version from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000001'),
      (select collection_version from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000001'),
      'Actor A archive',
      'request-shared-archive-a-021',
      'a0210000-0000-4000-8000-000000000023'
    )
  $$,
  'actor A archive succeeds with the shared logical key'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.lives_ok(
  $$
    select * from app.archive_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      'shared-media-archive-key-021',
      (select media_id from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000002'),
      (select media_version from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000002'),
      (select collection_version from pg_temp.actor_command_results
       where actor_user_id = '31000000-0000-4000-8000-000000000002'),
      'Actor B archive',
      'request-shared-archive-b-021',
      'a0210000-0000-4000-8000-000000000024'
    )
  $$,
  'actor B archive is independent of actor A'
);
reset role;

select extensions.ok(
  (
    select pg_catalog.count(*) = 12
      and pg_catalog.count(distinct receipt.actor_user_id) = 2
      and pg_catalog.count(
        distinct (receipt.command_type, receipt.idempotency_key)
      ) = 6
    from public.media_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.actor_user_id in (
        '31000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000002'
      )
      and receipt.command_type in (
        'media.create_upload',
        'media.request_upload_verification',
        'media.reorder',
        'media.set_cover',
        'media.update_caption',
        'media.archive'
      )
      and (
        receipt.result ->> 'media_id' in (
          select media_id::text from pg_temp.actor_command_results
        )
        or receipt.result ->> 'inventory_unit_id' in (
          select inventory_unit_id::text from pg_temp.actor_command_results
        )
      )
  ),
  'all exercised media receipt domains retain two independent actor results'
);

select extensions.ok(
  (
    select pg_catalog.count(*) = 18
      and pg_catalog.count(audit.id) = 18
      and pg_catalog.bool_and(
        audit.actor_user_id = receipt.actor_user_id
      )
    from (
      select receipt.actor_user_id, receipt.result
      from public.inventory_command_receipts receipt
      where receipt.command_type in (
        'update_inventory_unit_details',
        'transfer_inventory_unit_location',
        'transition_inventory_workflow'
      )
        and receipt.result ->> 'inventory_unit_id' in (
          select inventory_unit_id::text from pg_temp.actor_command_results
        )
      union all
      select receipt.actor_user_id, receipt.result
      from public.media_command_receipts receipt
      where receipt.command_type in (
        'media.create_upload',
        'media.request_upload_verification',
        'media.reorder',
        'media.set_cover',
        'media.update_caption',
        'media.archive'
      )
        and (
          receipt.result ->> 'media_id' in (
            select media_id::text from pg_temp.actor_command_results
          )
          or receipt.result ->> 'inventory_unit_id' in (
            select inventory_unit_id::text from pg_temp.actor_command_results
          )
        )
    ) receipt
    left join public.audit_events audit
      on audit.workspace_id = '10000000-0000-4000-8000-000000000001'
     and audit.id = (receipt.result ->> 'audit_event_id')::uuid
  ),
  'T-AUD-001 every exercised actor-scoped receipt has its same-actor audit'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 18
      and pg_catalog.count(event.id) = 18
      and pg_catalog.bool_and(
        event.actor_user_id = receipt.actor_user_id
      )
    from (
      select receipt.actor_user_id, receipt.result
      from public.inventory_command_receipts receipt
      where receipt.command_type in (
        'update_inventory_unit_details',
        'transfer_inventory_unit_location',
        'transition_inventory_workflow'
      )
        and receipt.result ->> 'inventory_unit_id' in (
          select inventory_unit_id::text from pg_temp.actor_command_results
        )
      union all
      select receipt.actor_user_id, receipt.result
      from public.media_command_receipts receipt
      where receipt.command_type in (
        'media.create_upload',
        'media.request_upload_verification',
        'media.reorder',
        'media.set_cover',
        'media.update_caption',
        'media.archive'
      )
        and (
          receipt.result ->> 'media_id' in (
            select media_id::text from pg_temp.actor_command_results
          )
          or receipt.result ->> 'inventory_unit_id' in (
            select inventory_unit_id::text from pg_temp.actor_command_results
          )
        )
    ) receipt
    left join public.outbox_events event
      on event.workspace_id = '10000000-0000-4000-8000-000000000001'
     and event.id = (receipt.result ->> 'outbox_event_id')::uuid
  ),
  'T-AUD-001 every exercised actor-scoped receipt has its same-actor outbox event'
);

select * from extensions.finish();
rollback;
