-- VYN-MEDIA-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-API-001
-- M2-MEDIA-MGMT-AC-001 through M2-MEDIA-MGMT-AC-010
-- Exact vehicle-photo reads and optimistic, idempotent management commands.

-- Provider coordinates and upload-session object paths are service-side only.
-- Browser reads use the exact projections below and signed-grant command path.
revoke select on public.media_files, public.media_upload_sessions
  from authenticated;

create function app.vehicle_media_files_snapshot(
  p_workspace_id uuid,
  p_media_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', file.id,
        'processingRunId', file.processing_run_id,
        'fileClass', file.file_class,
        'variant', file.variant,
        'status', case when file.deleted_at is null then 'available' else 'retired' end,
        'mimeType', file.mime_type,
        'byteSize', file.byte_size,
        'checksumSha256', file.checksum_sha256,
        'width', file.width,
        'height', file.height,
        'metadataStripped', file.metadata_stripped,
        'createdAt', file.created_at
      ) order by
        case file.variant
          when 'thumbnail_320' then 1
          when 'thumbnail_640' then 2
          when 'website_1080' then 3
          when 'normalized_master' then 4
          when 'raw_original' then 5
          else 6
        end,
        file.created_at,
        file.id
    ),
    '[]'::jsonb
  )
  from public.media_files file
  where file.workspace_id = p_workspace_id
    and file.media_id = p_media_id
    and file.file_class in ('vehicle_photo_raw', 'vehicle_photo_derivative')
    and file.variant in (
      'raw_original', 'normalized_master', 'website_1080',
      'thumbnail_640', 'thumbnail_320'
    )
    and exists (
      select 1
      from public.media_assets asset
      join public.media_processing_runs run
        on run.workspace_id = asset.workspace_id
       and run.media_id = asset.id
       and run.generation = asset.generation
      where asset.workspace_id = file.workspace_id
        and asset.id = file.media_id
        and run.id = file.processing_run_id
    );
$$;

create function app.vehicle_media_asset_snapshot(
  p_workspace_id uuid,
  p_media_id uuid,
  p_collection_version bigint
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', asset.id,
    'inventoryUnitId', asset.inventory_unit_id,
    'status', asset.status,
    'caption', asset.caption,
    'sortOrder', asset.sort_order,
    'isCover', asset.is_cover,
    'mediaVersion', asset.version,
    'collectionVersion', p_collection_version,
    'processingProfile', pg_catalog.jsonb_build_object(
      'id', profile.id,
      'version', profile.version,
      'checksumSha256', profile.checksum_sha256
    ),
    'files', app.vehicle_media_files_snapshot(asset.workspace_id, asset.id),
    'createdAt', asset.created_at,
    'updatedAt', asset.updated_at,
    'archivedAt', asset.archived_at
  )
  from public.media_assets asset
  join public.media_processing_profiles profile
    on profile.workspace_id = asset.workspace_id
   and profile.id = asset.processing_profile_id
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo';
$$;

create function app.get_vehicle_media_asset(
  p_workspace_id uuid,
  p_media_id uuid
)
returns table (
  media jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target_media public.media_assets%rowtype;
  collection_version bigint;
begin
  perform app.require_media_permission(p_workspace_id, 'media.read');
  if p_workspace_id is null or p_media_id is null then
    raise exception using errcode = '22023', message = 'invalid vehicle media read';
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo';
  if not found then
    raise exception using errcode = 'P0002', message = 'vehicle media was not found';
  end if;

  select collection.version into collection_version
  from public.inventory_media_collections collection
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = target_media.inventory_unit_id;
  if not found then
    raise exception using errcode = '55000', message = 'vehicle media collection is unavailable';
  end if;

  return query
  select app.vehicle_media_asset_snapshot(
    p_workspace_id,
    p_media_id,
    collection_version
  );
end;
$$;

create function app.list_inventory_vehicle_media(
  p_workspace_id uuid,
  p_inventory_unit_id uuid
)
returns table (
  inventory_unit_id uuid,
  collection_version bigint,
  media_items jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_collection_version bigint;
begin
  perform app.require_media_permission(p_workspace_id, 'media.read');
  if p_workspace_id is null or p_inventory_unit_id is null then
    raise exception using errcode = '22023', message = 'invalid inventory media read';
  end if;
  if not exists (
    select 1
    from public.inventory_units unit
    where unit.workspace_id = p_workspace_id
      and unit.id = p_inventory_unit_id
  ) then
    raise exception using errcode = 'P0002', message = 'inventory unit was not found';
  end if;

  select collection.version into current_collection_version
  from public.inventory_media_collections collection
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = p_inventory_unit_id;
  current_collection_version := coalesce(current_collection_version, 1);

  return query
  select
    p_inventory_unit_id,
    current_collection_version,
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          app.vehicle_media_asset_snapshot(
            asset.workspace_id,
            asset.id,
            current_collection_version
          ) order by asset.sort_order, asset.id
        )
        from public.media_assets asset
        where asset.workspace_id = p_workspace_id
          and asset.inventory_unit_id = p_inventory_unit_id
          and asset.media_kind = 'vehicle_photo'
          and asset.status <> 'archived'
      ),
      '[]'::jsonb
    );
end;
$$;

create function app.update_vehicle_media_caption(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_expected_media_version bigint,
  p_caption text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  media_version bigint,
  caption text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_media public.media_assets%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_caption text;
  request_fingerprint text;
  next_media_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_media_permission(p_workspace_id, 'media.update');
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_caption := case
    when p_caption is null then null
    else pg_catalog.btrim(p_caption)
  end;
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_media_id is null
    or p_expected_media_version is null or p_expected_media_version < 1
    or (
      p_caption is not null
      and (
        pg_catalog.char_length(normalized_caption) not between 1 and 500
        or normalized_caption ~ '[[:cntrl:]]'
      )
    )
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid vehicle media caption command';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'actor_user_id', actor_user_id,
      'media_id', p_media_id,
      'expected_media_version', p_expected_media_version,
      'caption', normalized_caption
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.update_caption\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.command_type = 'media.update_caption'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint
      or existing_receipt.actor_user_id <> actor_user_id then
      raise exception using errcode = '23505', message = 'media caption replay conflicts';
    end if;
    return query select
      (existing_receipt.result ->> 'media_id')::uuid,
      (existing_receipt.result ->> 'media_version')::bigint,
      existing_receipt.result ->> 'caption',
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo'
    and asset.status <> 'archived'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'vehicle media was not found';
  end if;
  if target_media.version <> p_expected_media_version then
    raise exception using errcode = '40001', message = 'stale vehicle media version';
  end if;

  next_media_version := target_media.version + 1;
  update public.media_assets asset
  set caption = normalized_caption,
      version = next_media_version,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, actor_user_id,
    correlation_id
  ) values (
    p_workspace_id, 'media.caption_updated', 'media_asset', p_media_id,
    next_media_version, 1,
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'inventory_unit_id', target_media.inventory_unit_id,
      'media_version', next_media_version,
      'caption', normalized_caption
    ),
    actor_user_id, p_correlation_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.caption_updated',
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'caption', target_media.caption,
      'version', target_media.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'caption', normalized_caption,
      'version', next_media_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'inventory_unit_id', target_media.inventory_unit_id,
      'outbox_event_id', new_outbox_event_id
    )
  );

  result_payload := pg_catalog.jsonb_build_object(
    'media_id', p_media_id,
    'media_version', next_media_version,
    'caption', normalized_caption,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.update_caption', normalized_idempotency_key,
    request_fingerprint, result_payload, actor_user_id
  );

  return query select
    p_media_id, next_media_version, normalized_caption, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.archive_vehicle_media(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_expected_media_version bigint,
  p_expected_collection_version bigint,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  inventory_unit_id uuid,
  media_status text,
  media_version bigint,
  collection_version bigint,
  promoted_cover_media_id uuid,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_media public.media_assets%rowtype;
  target_collection public.inventory_media_collections%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_reason text;
  request_fingerprint text;
  next_media_version bigint;
  next_collection_version bigint;
  active_cover_media_id uuid;
  new_promoted_cover_media_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_media_permission(p_workspace_id, 'media.archive');
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_media_id is null
    or p_expected_media_version is null or p_expected_media_version < 1
    or p_expected_collection_version is null or p_expected_collection_version < 1
    or pg_catalog.char_length(normalized_reason) not between 1 and 1000
    or normalized_reason ~ '[[:cntrl:]]'
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid vehicle media archive command';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'actor_user_id', actor_user_id,
      'media_id', p_media_id,
      'expected_media_version', p_expected_media_version,
      'expected_collection_version', p_expected_collection_version,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.archive\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.command_type = 'media.archive'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint
      or existing_receipt.actor_user_id <> actor_user_id then
      raise exception using errcode = '23505', message = 'media archive replay conflicts';
    end if;
    return query select
      (existing_receipt.result ->> 'media_id')::uuid,
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      existing_receipt.result ->> 'media_status',
      (existing_receipt.result ->> 'media_version')::bigint,
      (existing_receipt.result ->> 'collection_version')::bigint,
      (existing_receipt.result ->> 'promoted_cover_media_id')::uuid,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo';
  if not found or target_media.status = 'archived' then
    raise exception using errcode = 'P0002', message = 'vehicle media was not found';
  end if;

  select collection.* into target_collection
  from public.inventory_media_collections collection
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = target_media.inventory_unit_id
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'vehicle media collection is unavailable';
  end if;
  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo'
    and asset.status <> 'archived'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'vehicle media was not found';
  end if;
  if target_media.version <> p_expected_media_version
    or target_collection.version <> p_expected_collection_version then
    raise exception using errcode = '40001', message = 'stale vehicle media archive version';
  end if;

  next_media_version := target_media.version + 1;
  update public.media_assets asset
  set status = 'archived',
      is_cover = false,
      version = next_media_version,
      archived_at = pg_catalog.statement_timestamp(),
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id;

  with compacted as (
    select
      asset.id,
      pg_catalog.row_number() over (
        order by asset.sort_order, asset.id
      )::integer - 1 as next_sort_order
    from public.media_assets asset
    where asset.workspace_id = p_workspace_id
      and asset.inventory_unit_id = target_media.inventory_unit_id
      and asset.media_kind = 'vehicle_photo'
      and asset.status <> 'archived'
  )
  update public.media_assets asset
  set sort_order = compacted.next_sort_order,
      updated_at = pg_catalog.statement_timestamp()
  from compacted
  where asset.workspace_id = p_workspace_id
    and asset.id = compacted.id
    and asset.sort_order <> compacted.next_sort_order;

  select asset.id into active_cover_media_id
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.inventory_unit_id = target_media.inventory_unit_id
    and asset.media_kind = 'vehicle_photo'
    and asset.status <> 'archived'
    and asset.is_cover
  order by asset.sort_order, asset.id
  limit 1;
  if active_cover_media_id is null then
    select asset.id into active_cover_media_id
    from public.media_assets asset
    where asset.workspace_id = p_workspace_id
      and asset.inventory_unit_id = target_media.inventory_unit_id
      and asset.media_kind = 'vehicle_photo'
      and asset.status <> 'archived'
    order by asset.sort_order, asset.id
    limit 1;
    new_promoted_cover_media_id := active_cover_media_id;
    if active_cover_media_id is not null then
      update public.media_assets asset
      set is_cover = asset.id = active_cover_media_id,
          updated_at = pg_catalog.statement_timestamp()
      where asset.workspace_id = p_workspace_id
        and asset.inventory_unit_id = target_media.inventory_unit_id
        and asset.media_kind = 'vehicle_photo'
        and asset.status <> 'archived';
    end if;
  end if;

  update public.inventory_media_collections collection
  set version = collection.version + 1,
      updated_at = pg_catalog.statement_timestamp()
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = target_media.inventory_unit_id
  returning collection.version into next_collection_version;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, actor_user_id,
    correlation_id
  ) values (
    p_workspace_id, 'media.archived', 'media_asset', p_media_id,
    next_media_version, 1,
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'inventory_unit_id', target_media.inventory_unit_id,
      'media_version', next_media_version,
      'collection_version', next_collection_version,
      'active_cover_media_id', active_cover_media_id,
      'promoted_cover_media_id', new_promoted_cover_media_id
    ),
    actor_user_id, p_correlation_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.archived',
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', target_media.version,
      'sort_order', target_media.sort_order,
      'is_cover', target_media.is_cover,
      'collection_version', target_collection.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'archived',
      'version', next_media_version,
      'collection_version', next_collection_version,
      'active_cover_media_id', active_cover_media_id,
      'promoted_cover_media_id', new_promoted_cover_media_id
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'inventory_unit_id', target_media.inventory_unit_id,
      'outbox_event_id', new_outbox_event_id
    )
  );

  result_payload := pg_catalog.jsonb_build_object(
    'media_id', p_media_id,
    'inventory_unit_id', target_media.inventory_unit_id,
    'media_status', 'archived',
    'media_version', next_media_version,
    'collection_version', next_collection_version,
    'promoted_cover_media_id', new_promoted_cover_media_id,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.archive', normalized_idempotency_key,
    request_fingerprint, result_payload, actor_user_id
  );

  return query select
    p_media_id, target_media.inventory_unit_id, 'archived'::text,
    next_media_version, next_collection_version, new_promoted_cover_media_id, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

revoke all on function app.vehicle_media_files_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.vehicle_media_asset_snapshot(uuid, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function app.get_vehicle_media_asset(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.list_inventory_vehicle_media(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.update_vehicle_media_caption(
  uuid, text, uuid, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.archive_vehicle_media(
  uuid, text, uuid, bigint, bigint, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.get_vehicle_media_asset(uuid, uuid)
  to authenticated;
grant execute on function app.list_inventory_vehicle_media(uuid, uuid)
  to authenticated;
grant execute on function app.update_vehicle_media_caption(
  uuid, text, uuid, bigint, text, text, uuid
) to authenticated;
grant execute on function app.archive_vehicle_media(
  uuid, text, uuid, bigint, bigint, text, text, uuid
) to authenticated;

comment on function app.get_vehicle_media_asset(uuid, uuid) is
  'Exact permission-scoped vehicle-photo read with immutable file provenance and no storage coordinates.';
comment on function app.list_inventory_vehicle_media(uuid, uuid) is
  'Ordered active vehicle-photo collection read; legal media and storage coordinates are excluded.';
comment on function app.update_vehicle_media_caption(
  uuid, text, uuid, bigint, text, text, uuid
) is 'Idempotent optimistic vehicle-photo caption command with audit and outbox evidence.';
comment on function app.archive_vehicle_media(
  uuid, text, uuid, bigint, bigint, text, text, uuid
) is 'Idempotent optimistic vehicle-photo archive with atomic cover promotion and order compaction.';
