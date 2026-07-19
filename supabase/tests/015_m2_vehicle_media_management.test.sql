-- VYN-MEDIA-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-API-001
-- M2-MEDIA-MGMT-AC-001 through M2-MEDIA-MGMT-AC-010, T-MED-004,
-- T-MED-005, T-STOR-001, T-TEN-001, T-RBAC-001, T-AUD-001, T-API-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(32);

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
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.media_inventory (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean
);
create temporary table pg_temp.upload_results (
  media_id uuid,
  upload_session_id uuid,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  collection_version bigint,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.caption_results (
  media_id uuid,
  media_version bigint,
  caption text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
create temporary table pg_temp.archive_results (
  media_id uuid,
  inventory_unit_id uuid,
  media_status text,
  media_version bigint,
  collection_version bigint,
  promoted_cover_media_id uuid,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid,
  probe text
);
grant all on
  pg_temp.media_inventory,
  pg_temp.upload_results,
  pg_temp.caption_results,
  pg_temp.archive_results
to authenticated;

select extensions.has_function(
  'app', 'get_vehicle_media_asset', array['uuid', 'uuid'],
  'exact vehicle media read RPC exists'
);
select extensions.has_function(
  'app', 'list_inventory_vehicle_media', array['uuid', 'uuid'],
  'ordered inventory media read RPC exists'
);
select extensions.has_function(
  'app', 'update_vehicle_media_caption',
  array['uuid', 'text', 'uuid', 'bigint', 'text', 'text', 'uuid'],
  'optimistic caption command exists'
);
select extensions.has_function(
  'app', 'archive_vehicle_media',
  array['uuid', 'text', 'uuid', 'bigint', 'bigint', 'text', 'text', 'uuid'],
  'optimistic archive command exists'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'app.get_vehicle_media_asset(uuid,uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated', 'app.list_inventory_vehicle_media(uuid,uuid)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'app.update_vehicle_media_caption(uuid,text,uuid,bigint,text,text,uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'app.archive_vehicle_media(uuid,text,uuid,bigint,bigint,text,text,uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'app.get_vehicle_media_asset(uuid,uuid)', 'EXECUTE'
  ),
  'only authenticated application callers receive the exact media surface'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'app.vehicle_media_files_snapshot(uuid,uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app.vehicle_media_asset_snapshot(uuid,uuid,bigint)',
    'EXECUTE'
  ),
  'internal snapshot helpers cannot bypass permission-scoped RPCs'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$select pg_catalog.count(*) from public.media_files$$,
  '42501',
  'permission denied for table media_files',
  'authenticated callers cannot directly read provider-bearing file rows'
);
select extensions.throws_ok(
  $$select pg_catalog.count(*) from public.media_upload_sessions$$,
  '42501',
  'permission denied for table media_upload_sessions',
  'authenticated callers cannot directly read upload object coordinates'
);

insert into pg_temp.media_inventory
select result.*
from app.create_inventory_unit(
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'm2-media-manager-inventory-001',
  '1HGCM82633A925001',
  2026,
  'Synthetic',
  'Media Manager',
  date '2026-07-16',
  12,
  'km',
  'CAD',
  4200000,
  'Fictional media manager fixture',
  'request-media-manager-inventory-001',
  'b9000000-0000-4000-8000-000000000001'
) result;
select extensions.ok(
  (
    select result.collection_version = 1
      and result.media_items = '[]'::jsonb
    from app.list_inventory_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.media_inventory)
    ) result
  ),
  'an inventory unit without photos returns an exact empty versioned collection'
);

insert into pg_temp.upload_results
select result.*, 'first'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-manager-upload-001',
  (select inventory_unit_id from pg_temp.media_inventory),
  'front.jpg', 'image/jpeg', 1000, repeat('a', 64),
  'request-media-manager-upload-001',
  'b9000000-0000-4000-8000-000000000002'
) result;
insert into pg_temp.upload_results
select result.*, 'second'
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-manager-upload-002',
  (select inventory_unit_id from pg_temp.media_inventory),
  'side.jpg', 'image/jpeg', 1100, repeat('b', 64),
  'request-media-manager-upload-002',
  'b9000000-0000-4000-8000-000000000003'
) result;
select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.min(collection_version) = 2
      and pg_catalog.max(collection_version) = 3
    from pg_temp.upload_results
  ),
  'two upload intents create a versioned two-photo collection'
);
reset role;

insert into public.media_processing_runs (
  id, workspace_id, media_id, generation, source_kind, source_id,
  processing_profile_id, profile_snapshot, profile_checksum_sha256
)
select
  case upload.probe
    when 'first' then 'ca000000-0000-4000-8000-000000000001'::uuid
    else 'ca000000-0000-4000-8000-000000000002'::uuid
  end,
  asset.workspace_id,
  asset.id,
  asset.generation,
  'upload_session',
  upload.upload_session_id,
  profile.id,
  profile.profile_snapshot,
  profile.checksum_sha256
from pg_temp.upload_results upload
join public.media_assets asset on asset.id = upload.media_id
join public.media_processing_profiles profile
  on profile.workspace_id = asset.workspace_id
 and profile.id = asset.processing_profile_id;

update public.media_assets asset
set status = 'ready', updated_at = pg_catalog.statement_timestamp()
where asset.id in (select media_id from pg_temp.upload_results);

insert into public.media_files (
  id, workspace_id, media_id, processing_run_id, file_class, variant,
  storage_bucket, storage_object_key, storage_generation, mime_type,
  byte_size, checksum_sha256, width, height, metadata_stripped,
  retention_policy
)
select
  case upload.probe
    when 'first' then 'cb000000-0000-4000-8000-000000000001'::uuid
    else 'cb000000-0000-4000-8000-000000000002'::uuid
  end,
  '10000000-0000-4000-8000-000000000001'::uuid,
  upload.media_id,
  case upload.probe
    when 'first' then 'ca000000-0000-4000-8000-000000000001'::uuid
    else 'ca000000-0000-4000-8000-000000000002'::uuid
  end,
  'vehicle_photo_derivative',
  'thumbnail_320',
  'media-private',
  'workspaces/10000000-0000-4000-8000-000000000001/media/'
    || upload.media_id::text || '/thumbnail_320/'
    || case upload.probe when 'first' then repeat('c', 64) else repeat('d', 64) end
    || '.webp',
  'provider-fixture-' || upload.probe,
  'image/webp',
  case upload.probe when 'first' then 320 else 330 end,
  case upload.probe when 'first' then repeat('c', 64) else repeat('d', 64) end,
  320,
  213,
  true,
  'retain_until_archive'
from pg_temp.upload_results upload;

insert into public.media_assets (
  id, workspace_id, inventory_unit_id, owner_entity_type, owner_entity_id,
  media_kind, status, created_by
) values (
  'cc000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  (select inventory_unit_id from pg_temp.media_inventory),
  'inventory_unit',
  (select inventory_unit_id from pg_temp.media_inventory),
  'legal_document',
  'ready',
  '31000000-0000-4000-8000-000000000001'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.ok(
  (
    select
      result.collection_version = 3
      and pg_catalog.jsonb_array_length(result.media_items) = 2
      and result.media_items #>> '{0,files,0,id}'
        = 'cb000000-0000-4000-8000-000000000001'
      and result.media_items #>> '{0,files,0,variant}' = 'thumbnail_320'
      and result.media_items #>> '{0,files,0,processingRunId}'
        = 'ca000000-0000-4000-8000-000000000001'
      and result.media_items::text !~* '(storage_bucket|storageBucket|storage_object|storageObject|storage_generation|storageGeneration|provider-fixture)'
      and result.media_items::text !~ 'cc000000-0000-4000-8000-000000000001'
    from app.list_inventory_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.media_inventory)
    ) result
  ),
  'ordered read returns exact current vehicle file provenance without coordinates or legal media'
);
select extensions.ok(
  (
    select
      result.media ->> 'id' = (
        select media_id::text from pg_temp.upload_results where probe = 'first'
      )
      and result.media ->> 'status' = 'ready'
      and result.media #>> '{files,0,id}'
        = 'cb000000-0000-4000-8000-000000000001'
      and result.media::text !~* '(storage|provider-fixture)'
    from app.get_vehicle_media_asset(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.upload_results where probe = 'first')
    ) result
  ),
  'exact asset read returns one vehicle photo and immutable file ID'
);
select extensions.throws_ok(
  $$
    select * from app.get_vehicle_media_asset(
      '10000000-0000-4000-8000-000000000001',
      'cc000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0002',
  'vehicle media was not found',
  'legal originals cannot cross the vehicle-media read boundary'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.list_inventory_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.media_inventory)
    )
  $$,
  '42501',
  'active workspace membership and media permission are required',
  'workspace membership without media.read cannot list photos'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.list_inventory_vehicle_media(
      '20000000-0000-4000-8000-000000000002',
      (select inventory_unit_id from pg_temp.media_inventory)
    )
  $$,
  '42501',
  'active workspace membership and media permission are required',
  'cross-workspace media reads fail before entity lookup'
);

insert into pg_temp.caption_results
select result.*, 'initial'
from app.update_vehicle_media_caption(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-caption-001',
  (select media_id from pg_temp.upload_results where probe = 'second'),
  1,
  'Driver-side profile',
  'request-media-caption-001',
  'b9000000-0000-4000-8000-000000000004'
) result;
select extensions.ok(
  (
    select caption = 'Driver-side profile'
      and media_version = 2
      and not replayed
    from pg_temp.caption_results
    where probe = 'initial'
  ),
  'caption update advances only the expected media aggregate version'
);
insert into pg_temp.caption_results
select result.*, 'replay'
from app.update_vehicle_media_caption(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-caption-001',
  (select media_id from pg_temp.upload_results where probe = 'second'),
  1,
  'Driver-side profile',
  'request-media-caption-replay',
  'b9000000-0000-4000-8000-000000000005'
) result;
select extensions.ok(
  (
    select replay.replayed
      and replay.media_version = initial.media_version
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
    from pg_temp.caption_results initial
    join pg_temp.caption_results replay on replay.probe = 'replay'
    where initial.probe = 'initial'
  ),
  'caption replay returns the original audit and outbox evidence'
);
select extensions.throws_ok(
  $$
    select * from app.update_vehicle_media_caption(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-caption-stale',
      (select media_id from pg_temp.upload_results where probe = 'second'),
      1, 'Stale caption', 'request-media-caption-stale',
      'b9000000-0000-4000-8000-000000000006'
    )
  $$,
  '40001',
  'stale vehicle media version',
  'stale caption updates fail optimistically'
);
select extensions.throws_ok(
  $$
    select * from app.update_vehicle_media_caption(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-caption-control',
      (select media_id from pg_temp.upload_results where probe = 'second'),
      2, E'bad\ncaption', 'request-media-caption-control',
      'b9000000-0000-4000-8000-000000000007'
    )
  $$,
  '22023',
  'invalid vehicle media caption command',
  'control characters are rejected from captions'
);
select extensions.throws_ok(
  $$
    select * from app.update_vehicle_media_caption(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-caption-001',
      (select media_id from pg_temp.upload_results where probe = 'second'),
      1, 'Changed replay', 'request-media-caption-conflict',
      'b9000000-0000-4000-8000-000000000008'
    )
  $$,
  '23505',
  'media caption replay conflicts',
  'caption idempotency key cannot be reused for a different request'
);
select extensions.ok(
  (
    select event.event_name = 'media.caption_updated'
      and event.aggregate_version = result.media_version
      and audit.action = 'media.caption_updated'
      and audit.after_data ->> 'caption' = result.caption
    from pg_temp.caption_results result
    join public.outbox_events event on event.id = result.outbox_event_id
    join public.audit_events audit on audit.id = result.audit_event_id
    where result.probe = 'initial'
  ),
  'caption command emits matching append-only audit and outbox records'
);

select extensions.throws_ok(
  $$
    select * from app.archive_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-archive-stale',
      (select media_id from pg_temp.upload_results where probe = 'first'),
      1, 2, 'Duplicate angle', 'request-media-archive-stale',
      'b9000000-0000-4000-8000-000000000009'
    )
  $$,
  '40001',
  'stale vehicle media archive version',
  'archive requires both current media and collection versions'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.archive_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-archive-denied',
      (select media_id from pg_temp.upload_results where probe = 'first'),
      1, 3, 'Denied', 'request-media-archive-denied',
      'b9000000-0000-4000-8000-000000000010'
    )
  $$,
  '42501',
  'active workspace membership and media permission are required',
  'archive requires the immutable media.archive permission'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.archive_results
select result.*, 'initial'
from app.archive_vehicle_media(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-archive-001',
  (select media_id from pg_temp.upload_results where probe = 'first'),
  1,
  3,
  'Duplicate angle',
  'request-media-archive-001',
  'b9000000-0000-4000-8000-000000000011'
) result;
select extensions.ok(
  (
    select media_status = 'archived'
      and media_version = 2
      and collection_version = 4
      and promoted_cover_media_id = (
        select media_id from pg_temp.upload_results where probe = 'second'
      )
      and not replayed
    from pg_temp.archive_results
    where probe = 'initial'
  ),
  'archive advances both versions and promotes the next ordered cover'
);
insert into pg_temp.archive_results
select result.*, 'replay'
from app.archive_vehicle_media(
  '10000000-0000-4000-8000-000000000001',
  'm2-media-archive-001',
  (select media_id from pg_temp.upload_results where probe = 'first'),
  1,
  3,
  'Duplicate angle',
  'request-media-archive-replay',
  'b9000000-0000-4000-8000-000000000012'
) result;
select extensions.ok(
  (
    select replay.replayed
      and replay.media_version = initial.media_version
      and replay.collection_version = initial.collection_version
      and replay.audit_event_id = initial.audit_event_id
      and replay.outbox_event_id = initial.outbox_event_id
    from pg_temp.archive_results initial
    join pg_temp.archive_results replay on replay.probe = 'replay'
    where initial.probe = 'initial'
  ),
  'archive replay returns the original dual-version result'
);
select extensions.throws_ok(
  $$
    select * from app.archive_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      'm2-media-archive-001',
      (select media_id from pg_temp.upload_results where probe = 'first'),
      1, 3, 'Changed replay', 'request-media-archive-conflict',
      'b9000000-0000-4000-8000-000000000013'
    )
  $$,
  '23505',
  'media archive replay conflicts',
  'archive idempotency key cannot be reused with changed intent'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 1
      and pg_catalog.bool_and(asset.sort_order = 0)
      and pg_catalog.bool_and(asset.is_cover)
    from public.media_assets asset
    where asset.workspace_id = '10000000-0000-4000-8000-000000000001'
      and asset.inventory_unit_id = (select inventory_unit_id from pg_temp.media_inventory)
      and asset.media_kind = 'vehicle_photo'
      and asset.status <> 'archived'
  ),
  'archive atomically compacts active order and leaves exactly one cover'
);
select extensions.ok(
  (
    select result.collection_version = 4
      and pg_catalog.jsonb_array_length(result.media_items) = 1
      and result.media_items #>> '{0,id}' = (
        select media_id::text from pg_temp.upload_results where probe = 'second'
      )
      and result.media_items #>> '{0,sortOrder}' = '0'
      and result.media_items #>> '{0,isCover}' = 'true'
    from app.list_inventory_vehicle_media(
      '10000000-0000-4000-8000-000000000001',
      (select inventory_unit_id from pg_temp.media_inventory)
    ) result
  ),
  'ordered read excludes archived photos and returns the promoted cover'
);
select extensions.ok(
  (
    select result.media ->> 'status' = 'archived'
      and result.media ->> 'archivedAt' is not null
      and result.media ->> 'isCover' = 'false'
    from app.get_vehicle_media_asset(
      '10000000-0000-4000-8000-000000000001',
      (select media_id from pg_temp.upload_results where probe = 'first')
    ) result
  ),
  'exact asset read preserves archived aggregate history'
);
reset role;
select extensions.ok(
  (
    select event.event_name = 'media.archived'
      and event.aggregate_version = result.media_version
      and event.payload ->> 'collection_version' = result.collection_version::text
      and audit.action = 'media.archived'
      and audit.reason = 'Duplicate angle'
    from pg_temp.archive_results result
    join public.outbox_events event on event.id = result.outbox_event_id
    join public.audit_events audit on audit.id = result.audit_event_id
    where result.probe = 'initial'
  ),
  'archive emits correlated audit and outbox evidence for both versions'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.bool_and(file.deleted_at is null)
      and pg_catalog.bool_and(file.retention_policy = 'retain_until_archive')
    from public.media_files file
    where file.id in (
      'cb000000-0000-4000-8000-000000000001',
      'cb000000-0000-4000-8000-000000000002'
    )
  ),
  'logical archive preserves immutable files and retention provenance'
);
select extensions.ok(
  not exists (
    select 1
    from public.outbox_events event
    where event.event_name in ('media.caption_updated', 'media.archived')
      and event.payload::text ~* '(storage|bucket|object_key|generation|service_role)'
  )
  and not exists (
    select 1
    from public.audit_events audit
    where audit.action in ('media.caption_updated', 'media.archived')
      and (
        coalesce(audit.before_data, '{}'::jsonb)::text
          ~* '(storage|bucket|object_key|generation|service_role)'
        or coalesce(audit.after_data, '{}'::jsonb)::text
          ~* '(storage|bucket|object_key|generation|service_role)'
        or audit.metadata::text
          ~* '(storage|bucket|object_key|generation|service_role)'
      )
  ),
  'media management telemetry contains no storage coordinates or credentials'
);
reset role;

select * from extensions.finish();
rollback;
