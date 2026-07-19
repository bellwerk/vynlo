-- VYN-INV-001, VYN-COST-001, VYN-MEDIA-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001, T-TEN-001, T-RBAC-001,
-- M2-INV-AC-005, M2-INV-AC-006, M2-MEDIA-AC-021
--
-- Early M2 command receipts originally serialized a logical idempotency key at
-- workspace/domain scope. That allowed one permitted actor to collide with a
-- different permitted actor's key before the replay branch established actor
-- ownership. Public entrypoints validate the logical key and the reviewed
-- implementations now include workspace, actor, command domain, and key in
-- both the advisory lock and replay lookup. Existing same-actor receipts retain
-- replay compatibility; a different actor always enters a separate physical
-- uniqueness namespace even when both actors deliberately use the same raw
-- key, including values that resemble the retired a1 digest format.
-- Saved-view receipts and opaque managed-download authorizations already use
-- actor predicates in their locks, lookups, and unique keys and are unchanged.

do $$
declare
  target_constraint record;
  dropped_constraint_count integer := 0;
begin
  for target_constraint in
    select constraint_row.conrelid, constraint_row.conname
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.contype = 'u'
      and (
        (
          constraint_row.conrelid =
            'public.inventory_command_receipts'::pg_catalog.regclass
          and pg_catalog.pg_get_constraintdef(constraint_row.oid, false) =
            'UNIQUE (workspace_id, command_type, idempotency_key)'
        )
        or (
          constraint_row.conrelid =
            'public.inventory_cost_entries'::pg_catalog.regclass
          and pg_catalog.pg_get_constraintdef(constraint_row.oid, false) =
            'UNIQUE (workspace_id, idempotency_key)'
        )
        or (
          constraint_row.conrelid =
            'public.media_command_receipts'::pg_catalog.regclass
          and pg_catalog.pg_get_constraintdef(constraint_row.oid, false) =
            'UNIQUE (workspace_id, command_type, idempotency_key)'
        )
      )
  loop
    execute pg_catalog.format(
      'alter table %s drop constraint %I',
      target_constraint.conrelid::pg_catalog.regclass,
      target_constraint.conname
    );
    dropped_constraint_count := dropped_constraint_count + 1;
  end loop;

  if dropped_constraint_count <> 3 then
    raise exception using
      errcode = '55000',
      message = pg_catalog.format(
        'expected to replace 3 legacy idempotency constraints, replaced %s',
        dropped_constraint_count
      );
  end if;
end;
$$;

create unique index inventory_command_receipts_actor_key_uidx
  on public.inventory_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key
  );

create unique index inventory_cost_entries_actor_key_uidx
  on public.inventory_cost_entries (
    workspace_id, created_by, entry_kind, idempotency_key
  );

create unique index media_command_receipts_actor_key_uidx
  on public.media_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key
  )
  where actor_user_id is not null;

create unique index media_command_receipts_actorless_key_uidx
  on public.media_command_receipts (
    workspace_id, command_type, idempotency_key
  )
  where actor_user_id is null;

create function app.actor_idempotency_storage_key(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_domain text,
  p_idempotency_key text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  normalized_domain text := pg_catalog.btrim(
    coalesce(p_domain, '')
  );
  normalized_key text := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
begin
  if p_actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'validated idempotency actor is required';
  end if;
  if p_workspace_id is null
    or normalized_domain !~ '^[a-z][a-z0-9_.]*$'
    or pg_catalog.char_length(normalized_key) not between 8 and 200 then
    raise exception using
      errcode = '22023',
      message = 'invalid actor-scoped idempotency key';
  end if;

  return normalized_key;
end;
$$;

create function app.inventory_actor_idempotency_key(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_command_type text,
  p_idempotency_key text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_key text := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
begin
  return app.actor_idempotency_storage_key(
    p_workspace_id,
    p_actor_user_id,
    p_command_type,
    normalized_key
  );
end;
$$;

create function app.cost_actor_idempotency_key(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_entry_kind text,
  p_idempotency_key text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_key text := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
begin
  return app.actor_idempotency_storage_key(
    p_workspace_id,
    p_actor_user_id,
    'inventory_cost.' || p_entry_kind,
    normalized_key
  );
end;
$$;

create function app.media_actor_idempotency_key(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_command_type text,
  p_idempotency_key text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_key text := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
begin
  return app.actor_idempotency_storage_key(
    p_workspace_id,
    p_actor_user_id,
    p_command_type,
    normalized_key
  );
end;
$$;

revoke all on function app.actor_idempotency_storage_key(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function app.inventory_actor_idempotency_key(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function app.cost_actor_idempotency_key(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function app.media_actor_idempotency_key(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;

-- Keep the reviewed command bodies intact, but make their normalized logical-
-- key contract private. Only the actor-scoping wrappers below are
-- callable by authenticated or service roles.
alter function app.update_inventory_unit_details(
  uuid, text, uuid, bigint, text, date, timestamptz, timestamptz, bigint,
  text, bigint, bigint, text, text, boolean, text, text, uuid
) rename to update_inventory_unit_details_actor_key_impl;
alter function app.transfer_inventory_unit_location(
  uuid, text, uuid, bigint, uuid, text, text, uuid
) rename to transfer_inventory_unit_location_actor_key_impl;
alter function app.transition_inventory_workflow(
  uuid, text, uuid, bigint, text, text, text, uuid
) rename to transition_inventory_workflow_actor_key_impl;

revoke all on function app.update_inventory_unit_details_actor_key_impl(
  uuid, text, uuid, bigint, text, date, timestamptz, timestamptz, bigint,
  text, bigint, bigint, text, text, boolean, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.transfer_inventory_unit_location_actor_key_impl(
  uuid, text, uuid, bigint, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.transition_inventory_workflow_actor_key_impl(
  uuid, text, uuid, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;

create function app.update_inventory_unit_details(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_condition_key text,
  p_acquisition_date date,
  p_acquired_at timestamptz,
  p_available_at timestamptz,
  p_odometer_value bigint,
  p_odometer_unit text,
  p_advertised_price_minor bigint,
  p_expected_sale_price_minor bigint,
  p_expected_sale_price_currency_code text,
  p_public_notes text,
  p_update_internal_notes boolean,
  p_internal_notes text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.update_inventory_unit_details_actor_key_impl(
    p_workspace_id,
    app.inventory_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'update_inventory_unit_details',
      p_idempotency_key
    ),
    p_inventory_unit_id,
    p_expected_version,
    p_condition_key,
    p_acquisition_date,
    p_acquired_at,
    p_available_at,
    p_odometer_value,
    p_odometer_unit,
    p_advertised_price_minor,
    p_expected_sale_price_minor,
    p_expected_sale_price_currency_code,
    p_public_notes,
    p_update_internal_notes,
    p_internal_notes,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.transfer_inventory_unit_location(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_to_location_id uuid,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  location_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.transfer_inventory_unit_location_actor_key_impl(
    p_workspace_id,
    app.inventory_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'transfer_inventory_unit_location',
      p_idempotency_key
    ),
    p_inventory_unit_id,
    p_expected_version,
    p_to_location_id,
    p_reason,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.transition_inventory_workflow(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_transition_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  workflow_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.transition_inventory_workflow_actor_key_impl(
    p_workspace_id,
    app.inventory_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'transition_inventory_workflow',
      p_idempotency_key
    ),
    p_inventory_unit_id,
    p_expected_version,
    p_transition_key,
    p_reason,
    p_request_id,
    p_correlation_id
  ) result;
$$;

alter function app.post_inventory_cost_entry(
  uuid, text, uuid, bigint, uuid, bigint, text, date, uuid, text, uuid,
  text, uuid
) rename to post_inventory_cost_entry_actor_key_impl;
alter function app.reverse_inventory_cost_entry(
  uuid, text, uuid, bigint, date, text, text, uuid
) rename to reverse_inventory_cost_entry_actor_key_impl;

revoke all on function app.post_inventory_cost_entry_actor_key_impl(
  uuid, text, uuid, bigint, uuid, bigint, text, date, uuid, text, uuid,
  text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.reverse_inventory_cost_entry_actor_key_impl(
  uuid, text, uuid, bigint, date, text, text, uuid
) from public, anon, authenticated, service_role;

create function app.post_inventory_cost_entry(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_category_definition_id uuid,
  p_amount_minor bigint,
  p_currency_code text,
  p_incurred_on date,
  p_vendor_party_id uuid,
  p_description text,
  p_supporting_file_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.post_inventory_cost_entry_actor_key_impl(
    p_workspace_id,
    app.cost_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'cost',
      p_idempotency_key
    ),
    p_inventory_unit_id,
    p_expected_version,
    p_category_definition_id,
    p_amount_minor,
    p_currency_code,
    p_incurred_on,
    p_vendor_party_id,
    p_description,
    p_supporting_file_id,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.reverse_inventory_cost_entry(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_cost_entry_id uuid,
  p_expected_version bigint,
  p_reversed_on date,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  reversal_entry_id uuid,
  original_cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.reverse_inventory_cost_entry_actor_key_impl(
    p_workspace_id,
    app.cost_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'reversal',
      p_idempotency_key
    ),
    p_cost_entry_id,
    p_expected_version,
    p_reversed_on,
    p_reason,
    p_request_id,
    p_correlation_id
  ) result;
$$;

alter function app.create_vehicle_photo_upload_session(
  uuid, text, uuid, text, text, bigint, text, text, uuid
) rename to create_vehicle_photo_upload_session_actor_key_impl;
alter function app.complete_vehicle_photo_upload(
  uuid, uuid, text, uuid, uuid, text, bigint, text, boolean, integer,
  integer, integer, jsonb, text, uuid
) rename to complete_vehicle_photo_upload_actor_key_impl;
alter function app.reprocess_vehicle_photo(
  uuid, text, uuid, bigint, text, text, uuid
) rename to reprocess_vehicle_photo_actor_key_impl;
alter function app.reorder_inventory_media(
  uuid, text, uuid, bigint, jsonb, text, uuid
) rename to reorder_inventory_media_actor_key_impl;
alter function app.set_inventory_media_cover(
  uuid, text, uuid, uuid, bigint, text, uuid
) rename to set_inventory_media_cover_actor_key_impl;
alter function app.record_preserved_legal_original(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint,
  text, jsonb, uuid, text, uuid, integer, text, uuid
) rename to record_preserved_legal_original_actor_key_impl;
alter function app.set_managed_media_retention_hold(
  uuid, text, uuid, bigint, boolean, text, text, text, uuid
) rename to set_managed_media_retention_hold_actor_key_impl;
alter function app.request_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) rename to request_vehicle_photo_upload_verification_actor_key_impl;
alter function app.create_legal_original_upload_session(
  uuid, text, uuid, text, text, text, bigint, text, text, uuid
) rename to create_legal_original_upload_session_actor_key_impl;
alter function app.request_legal_original_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) rename to request_legal_original_upload_verification_actor_key_impl;
alter function app.update_vehicle_media_caption(
  uuid, text, uuid, bigint, text, text, uuid
) rename to update_vehicle_media_caption_actor_key_impl;
alter function app.archive_vehicle_media(
  uuid, text, uuid, bigint, bigint, text, text, uuid
) rename to archive_vehicle_media_actor_key_impl;

revoke all on function app.create_vehicle_photo_upload_session_actor_key_impl(
  uuid, text, uuid, text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.complete_vehicle_photo_upload_actor_key_impl(
  uuid, uuid, text, uuid, uuid, text, bigint, text, boolean, integer,
  integer, integer, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.reprocess_vehicle_photo_actor_key_impl(
  uuid, text, uuid, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.reorder_inventory_media_actor_key_impl(
  uuid, text, uuid, bigint, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.set_inventory_media_cover_actor_key_impl(
  uuid, text, uuid, uuid, bigint, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.record_preserved_legal_original_actor_key_impl(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint,
  text, jsonb, uuid, text, uuid, integer, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.set_managed_media_retention_hold_actor_key_impl(
  uuid, text, uuid, bigint, boolean, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.request_vehicle_photo_upload_verification_actor_key_impl(
  uuid, text, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.create_legal_original_upload_session_actor_key_impl(
  uuid, text, uuid, text, text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.request_legal_original_upload_verification_actor_key_impl(
  uuid, text, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.update_vehicle_media_caption_actor_key_impl(
  uuid, text, uuid, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.archive_vehicle_media_actor_key_impl(
  uuid, text, uuid, bigint, bigint, text, text, uuid
) from public, anon, authenticated, service_role;

create function app.create_vehicle_photo_upload_session(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_checksum_sha256 text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  upload_session_id uuid,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  collection_version bigint,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.create_vehicle_photo_upload_session_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.create_upload',
      p_idempotency_key
    ),
    p_inventory_unit_id,
    p_filename,
    p_mime_type,
    p_byte_size,
    p_checksum_sha256,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.complete_vehicle_photo_upload(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_upload_session_id uuid,
  p_observed_mime_type text,
  p_observed_byte_size bigint,
  p_observed_checksum_sha256 text,
  p_signature_verified boolean,
  p_width integer,
  p_height integer,
  p_exif_orientation integer,
  p_malware_scan_receipt jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  processing_run_id uuid,
  job_id uuid,
  media_status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.complete_vehicle_photo_upload_actor_key_impl(
    p_workspace_id,
    p_actor_user_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      p_actor_user_id,
      'media.complete_upload',
      p_idempotency_key
    ),
    p_media_id,
    p_upload_session_id,
    p_observed_mime_type,
    p_observed_byte_size,
    p_observed_checksum_sha256,
    p_signature_verified,
    p_width,
    p_height,
    p_exif_orientation,
    p_malware_scan_receipt,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.reprocess_vehicle_photo(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_expected_version bigint,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  processing_run_id uuid,
  job_id uuid,
  media_status text,
  aggregate_version bigint,
  generation integer,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.reprocess_vehicle_photo_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.reprocess',
      p_idempotency_key
    ),
    p_media_id,
    p_expected_version,
    p_reason,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.reorder_inventory_media(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_collection_version bigint,
  p_ordered_media_ids jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  collection_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.reorder_inventory_media_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.reorder',
      p_idempotency_key
    ),
    p_inventory_unit_id,
    p_expected_collection_version,
    p_ordered_media_ids,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.set_inventory_media_cover(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_media_id uuid,
  p_expected_collection_version bigint,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  cover_media_id uuid,
  collection_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.set_inventory_media_cover_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.set_cover',
      p_idempotency_key
    ),
    p_inventory_unit_id,
    p_media_id,
    p_expected_collection_version,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.record_preserved_legal_original(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_idempotency_key text,
  p_media_kind text,
  p_owner_entity_type text,
  p_owner_entity_id uuid,
  p_storage_bucket text,
  p_storage_object_key text,
  p_storage_generation text,
  p_mime_type text,
  p_byte_size bigint,
  p_checksum_sha256 text,
  p_verification_receipt jsonb,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  media_file_id uuid,
  media_status text,
  retention_policy text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.record_preserved_legal_original_actor_key_impl(
    p_workspace_id,
    p_actor_user_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      p_actor_user_id,
      'media.record_legal',
      p_idempotency_key
    ),
    p_media_kind,
    p_owner_entity_type,
    p_owner_entity_id,
    p_storage_bucket,
    p_storage_object_key,
    p_storage_generation,
    p_mime_type,
    p_byte_size,
    p_checksum_sha256,
    p_verification_receipt,
    p_job_id,
    p_worker_id,
    p_lease_token,
    p_attempt_number,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.set_managed_media_retention_hold(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_file_id uuid,
  p_expected_retention_version bigint,
  p_hold boolean,
  p_hold_kind text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_file_id uuid,
  retention_hold boolean,
  retention_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.set_managed_media_retention_hold_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.retention_hold',
      p_idempotency_key
    ),
    p_media_file_id,
    p_expected_retention_version,
    p_hold,
    p_hold_kind,
    p_reason,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.request_vehicle_photo_upload_verification(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_upload_session_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  upload_session_id uuid,
  job_id uuid,
  job_status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.request_vehicle_photo_upload_verification_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.request_upload_verification',
      p_idempotency_key
    ),
    p_media_id,
    p_upload_session_id,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.create_legal_original_upload_session(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_document_id uuid,
  p_media_kind text,
  p_original_filename text,
  p_expected_mime_type text,
  p_expected_byte_size bigint,
  p_expected_checksum_sha256 text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  upload_session_id uuid,
  document_id uuid,
  media_kind text,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  replayed boolean,
  audit_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.create_legal_original_upload_session_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.create_legal_upload',
      p_idempotency_key
    ),
    p_document_id,
    p_media_kind,
    p_original_filename,
    p_expected_mime_type,
    p_expected_byte_size,
    p_expected_checksum_sha256,
    p_request_id,
    p_correlation_id
  ) result;
$$;

create function app.request_legal_original_upload_verification(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_document_id uuid,
  p_upload_session_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  upload_session_id uuid,
  document_id uuid,
  job_id uuid,
  job_status text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.request_legal_original_upload_verification_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.request_legal_verify',
      p_idempotency_key
    ),
    p_document_id,
    p_upload_session_id,
    p_request_id,
    p_correlation_id
  ) result;
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
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.update_vehicle_media_caption_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.update_caption',
      p_idempotency_key
    ),
    p_media_id,
    p_expected_media_version,
    p_caption,
    p_request_id,
    p_correlation_id
  ) result;
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
language sql
security definer
set search_path = ''
as $$
  select result.*
  from app.archive_vehicle_media_actor_key_impl(
    p_workspace_id,
    app.media_actor_idempotency_key(
      p_workspace_id,
      auth.uid(),
      'media.archive',
      p_idempotency_key
    ),
    p_media_id,
    p_expected_media_version,
    p_expected_collection_version,
    p_reason,
    p_request_id,
    p_correlation_id
  ) result;
$$;

revoke all on function app.update_inventory_unit_details(
  uuid, text, uuid, bigint, text, date, timestamptz, timestamptz, bigint,
  text, bigint, bigint, text, text, boolean, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.transfer_inventory_unit_location(
  uuid, text, uuid, bigint, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.transition_inventory_workflow(
  uuid, text, uuid, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.post_inventory_cost_entry(
  uuid, text, uuid, bigint, uuid, bigint, text, date, uuid, text, uuid,
  text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.reverse_inventory_cost_entry(
  uuid, text, uuid, bigint, date, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.create_vehicle_photo_upload_session(
  uuid, text, uuid, text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.complete_vehicle_photo_upload(
  uuid, uuid, text, uuid, uuid, text, bigint, text, boolean, integer,
  integer, integer, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.reprocess_vehicle_photo(
  uuid, text, uuid, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.reorder_inventory_media(
  uuid, text, uuid, bigint, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.set_inventory_media_cover(
  uuid, text, uuid, uuid, bigint, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.record_preserved_legal_original(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint,
  text, jsonb, uuid, text, uuid, integer, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.set_managed_media_retention_hold(
  uuid, text, uuid, bigint, boolean, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.request_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.create_legal_original_upload_session(
  uuid, text, uuid, text, text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.request_legal_original_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.update_vehicle_media_caption(
  uuid, text, uuid, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.archive_vehicle_media(
  uuid, text, uuid, bigint, bigint, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.update_inventory_unit_details(
  uuid, text, uuid, bigint, text, date, timestamptz, timestamptz, bigint,
  text, bigint, bigint, text, text, boolean, text, text, uuid
) to authenticated;
grant execute on function app.transfer_inventory_unit_location(
  uuid, text, uuid, bigint, uuid, text, text, uuid
) to authenticated;
grant execute on function app.transition_inventory_workflow(
  uuid, text, uuid, bigint, text, text, text, uuid
) to authenticated;
grant execute on function app.post_inventory_cost_entry(
  uuid, text, uuid, bigint, uuid, bigint, text, date, uuid, text, uuid,
  text, uuid
) to authenticated;
grant execute on function app.reverse_inventory_cost_entry(
  uuid, text, uuid, bigint, date, text, text, uuid
) to authenticated;
grant execute on function app.create_vehicle_photo_upload_session(
  uuid, text, uuid, text, text, bigint, text, text, uuid
) to authenticated;
grant execute on function app.reprocess_vehicle_photo(
  uuid, text, uuid, bigint, text, text, uuid
) to authenticated;
grant execute on function app.reorder_inventory_media(
  uuid, text, uuid, bigint, jsonb, text, uuid
) to authenticated;
grant execute on function app.set_inventory_media_cover(
  uuid, text, uuid, uuid, bigint, text, uuid
) to authenticated;
grant execute on function app.set_managed_media_retention_hold(
  uuid, text, uuid, bigint, boolean, text, text, text, uuid
) to authenticated;
grant execute on function app.request_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) to authenticated;
grant execute on function app.create_legal_original_upload_session(
  uuid, text, uuid, text, text, text, bigint, text, text, uuid
) to authenticated;
grant execute on function app.request_legal_original_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) to authenticated;
grant execute on function app.update_vehicle_media_caption(
  uuid, text, uuid, bigint, text, text, uuid
) to authenticated;
grant execute on function app.archive_vehicle_media(
  uuid, text, uuid, bigint, bigint, text, text, uuid
) to authenticated;

comment on function app.actor_idempotency_storage_key(
  uuid, uuid, text, text
) is
  'Internal logical-key validator; actor and domain are enforced by command locks, replay predicates, and composite uniqueness.';
comment on function app.inventory_actor_idempotency_key(
  uuid, uuid, text, text
) is
  'Internal inventory receipt key adapter with same-actor legacy replay compatibility.';
comment on function app.cost_actor_idempotency_key(
  uuid, uuid, text, text
) is
  'Internal cost ledger key adapter with same-actor legacy replay compatibility.';
comment on function app.media_actor_idempotency_key(
  uuid, uuid, text, text
) is
  'Internal media receipt key adapter with same-actor legacy replay compatibility.';

comment on index public.inventory_command_receipts_actor_key_uidx is
  'Explicit actor-scoped uniqueness for inventory command receipts.';
comment on index public.inventory_cost_entries_actor_key_uidx is
  'Explicit actor and cost-command scoped uniqueness for posted cost history.';
comment on index public.media_command_receipts_actor_key_uidx is
  'Explicit actor-scoped uniqueness for user-attributed media command receipts.';
comment on index public.media_command_receipts_actorless_key_uidx is
  'Separate workspace/domain/key uniqueness for trusted actorless worker receipts.';

comment on function app.update_inventory_unit_details(
  uuid, text, uuid, bigint, text, date, timestamptz, timestamptz, bigint,
  text, bigint, bigint, text, text, boolean, text, text, uuid
) is
  'Actor-scoped idempotent inventory detail update; a different actor cannot replay or poison the logical key.';
comment on function app.post_inventory_cost_entry(
  uuid, text, uuid, bigint, uuid, bigint, text, date, uuid, text, uuid,
  text, uuid
) is
  'Actor-scoped idempotent exact minor-unit cost post.';
comment on function app.create_vehicle_photo_upload_session(
  uuid, text, uuid, text, text, bigint, text, text, uuid
) is
  'Actor-scoped idempotent vehicle-photo upload intent with private quarantine coordinates.';
comment on function app.request_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) is
  'Actor-scoped idempotent vehicle-photo verification request.';
comment on function app.complete_vehicle_photo_upload(
  uuid, uuid, text, uuid, uuid, text, bigint, text, boolean, integer,
  integer, integer, jsonb, text, uuid
) is
  'Owner-internal actor-scoped vehicle-photo completion helper; API roles must use the lease-fenced verification wrapper.';
comment on function app.record_preserved_legal_original(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint,
  text, jsonb, uuid, text, uuid, integer, text, uuid
) is
  'Owner-internal actor-scoped preserved-original helper; API roles must use the session- and lease-fenced verification wrapper.';

-- BEGIN GENERATED ACTOR-AWARE IMPLEMENTATIONS

create or replace function app.update_inventory_unit_details_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_condition_key text,
  p_acquisition_date date,
  p_acquired_at timestamptz,
  p_available_at timestamptz,
  p_odometer_value bigint,
  p_odometer_unit text,
  p_advertised_price_minor bigint,
  p_expected_sale_price_minor bigint,
  p_expected_sale_price_currency_code text,
  p_public_notes text,
  p_update_internal_notes boolean,
  p_internal_notes text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
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
  existing_unit public.inventory_units%rowtype;
  linked_instance public.workflow_instances%rowtype;
  existing_receipt public.inventory_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_condition_key text;
  normalized_expected_currency text;
  normalized_public_notes text;
  normalized_internal_notes text;
  request_fingerprint text;
  next_version bigint;
  changed_keys jsonb;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_inventory_command_permission(
    p_workspace_id,
    'inventory.update'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_condition_key := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_condition_key, ''))),
    ''
  );
  normalized_expected_currency := nullif(
    pg_catalog.upper(
      pg_catalog.btrim(coalesce(p_expected_sale_price_currency_code, ''))
    ),
    ''
  );
  normalized_public_notes := nullif(
    pg_catalog.btrim(coalesce(p_public_notes, '')),
    ''
  );
  normalized_internal_notes := case
    when p_update_internal_notes then nullif(
      pg_catalog.btrim(coalesce(p_internal_notes, '')),
      ''
    )
    else null
  end;

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid inventory idempotency key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_update_internal_notes is null then
    raise exception using
      errcode = '23502',
      message = 'internal-note update presence flag is required';
  end if;
  if not p_update_internal_notes
    and nullif(pg_catalog.btrim(coalesce(p_internal_notes, '')), '') is not null then
    raise exception using
      errcode = '22023',
      message = 'internal notes require the explicit update presence flag';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'inventory request ID is too long';
  end if;
  if normalized_condition_key is not null
    and normalized_condition_key !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$' then
    raise exception using errcode = '22023', message = 'invalid inventory condition key';
  end if;
  if (p_odometer_value is null) <> (p_odometer_unit is null)
    or p_odometer_value is not null and p_odometer_value < 0
    or p_odometer_unit is not null and p_odometer_unit not in ('km', 'mi') then
    raise exception using errcode = '22023', message = 'invalid odometer value or unit';
  end if;
  if p_advertised_price_minor is not null and p_advertised_price_minor < 0
    or p_expected_sale_price_minor is not null and p_expected_sale_price_minor < 0 then
    raise exception using errcode = '22023', message = 'inventory money cannot be negative';
  end if;
  if (p_expected_sale_price_minor is null) <> (normalized_expected_currency is null)
    or normalized_expected_currency is not null
      and normalized_expected_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'invalid expected-sale money';
  end if;
  if normalized_public_notes is not null
    and pg_catalog.char_length(normalized_public_notes) > 4000
    or normalized_internal_notes is not null
      and pg_catalog.char_length(normalized_internal_notes) > 8000 then
    raise exception using errcode = '22023', message = 'inventory notes are too long';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_version', p_expected_version,
      'condition_key', normalized_condition_key,
      'acquisition_date', p_acquisition_date,
      'acquired_at', p_acquired_at,
      'available_at', p_available_at,
      'odometer_value', p_odometer_value,
      'odometer_unit', p_odometer_unit,
      'advertised_price_minor', p_advertised_price_minor,
      'expected_sale_price_minor', p_expected_sale_price_minor,
      'expected_sale_price_currency_code', normalized_expected_currency,
      'public_notes', normalized_public_notes,
      'update_internal_notes', p_update_internal_notes,
      'internal_notes', case when p_update_internal_notes
        then normalized_internal_notes else null end
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fupdate_inventory_unit_details\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.inventory_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'update_inventory_unit_details'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'inventory idempotency key was used for a different details command';
    end if;
    return query select
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      existing_receipt.result ->> 'canonical_status',
      existing_receipt.result ->> 'state_key',
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select unit.*
    into existing_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if existing_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if existing_unit.status in ('closed', 'archived') then
    raise exception using
      errcode = '23514',
      message = 'closed inventory details are immutable';
  end if;
  if existing_unit.workflow_instance_id is not null then
    select instance.*
      into linked_instance
    from public.workflow_instances instance
    where instance.workspace_id = p_workspace_id
      and instance.id = existing_unit.workflow_instance_id
      and instance.entity_type = 'inventory_unit'
      and instance.entity_id = p_inventory_unit_id
      and instance.purpose_key = 'primary'
    for update;

    if not found or linked_instance.lifecycle_status <> 'active' then
      raise exception using errcode = '23514', message = 'inventory workflow is not active';
    end if;
    if linked_instance.version <> existing_unit.version
      or linked_instance.current_state_key <> existing_unit.workflow_state_key
      or linked_instance.canonical_status <> existing_unit.status then
      raise exception using
        errcode = '40001',
        message = 'inventory workflow aggregate versions are inconsistent';
    end if;
  end if;
  if normalized_expected_currency is not null
    and normalized_expected_currency <> existing_unit.currency_code then
    raise exception using
      errcode = '23514',
      message = 'expected-sale currency must match inventory currency';
  end if;

  if p_update_internal_notes then
    if not app.has_permission(p_workspace_id, 'inventory.update_internal') then
      raise exception using
        errcode = '42501',
        message = 'internal inventory update permission is required';
    end if;
  end if;

  changed_keys := pg_catalog.to_jsonb(pg_catalog.array_remove(array[
    case when normalized_condition_key is distinct from existing_unit.condition_key
      then 'condition_key' end,
    case when p_acquisition_date is distinct from existing_unit.acquisition_date
      then 'acquisition_date' end,
    case when p_acquired_at is distinct from existing_unit.acquired_at
      then 'acquired_at' end,
    case when p_available_at is distinct from existing_unit.available_at
      then 'available_at' end,
    case when p_odometer_value is distinct from existing_unit.odometer_value
      then 'odometer_value' end,
    case when p_odometer_unit is distinct from existing_unit.odometer_unit
      then 'odometer_unit' end,
    case when p_advertised_price_minor is distinct from existing_unit.advertised_price_minor
      then 'advertised_price_minor' end,
    case when p_expected_sale_price_minor is distinct from existing_unit.expected_sale_price_minor
      then 'expected_sale_price_minor' end,
    case when normalized_expected_currency is distinct from existing_unit.expected_sale_price_currency_code
      then 'expected_sale_price_currency_code' end,
    case when normalized_public_notes is distinct from existing_unit.public_notes
      then 'public_notes' end,
    case when p_update_internal_notes then 'internal_notes' end
  ]::text[], null));

  if pg_catalog.jsonb_array_length(changed_keys) = 0 then
    raise exception using errcode = '23514', message = 'inventory details did not change';
  end if;

  next_version := existing_unit.version + 1;
  if existing_unit.workflow_instance_id is not null then
    update public.workflow_instances
    set version = next_version
    where workspace_id = p_workspace_id
      and id = linked_instance.id;
  end if;

  update public.inventory_units
  set condition_key = normalized_condition_key,
      acquisition_date = p_acquisition_date,
      acquired_at = p_acquired_at,
      available_at = p_available_at,
      odometer_value = p_odometer_value,
      odometer_unit = p_odometer_unit,
      advertised_price_minor = p_advertised_price_minor,
      expected_sale_price_minor = p_expected_sale_price_minor,
      expected_sale_price_currency_code = normalized_expected_currency,
      public_notes = normalized_public_notes,
      version = next_version
  where workspace_id = p_workspace_id
    and id = p_inventory_unit_id;

  if p_update_internal_notes then
    insert into public.inventory_unit_internal_details (
      workspace_id,
      inventory_unit_id,
      internal_notes,
      version,
      created_by,
      updated_by
    ) values (
      p_workspace_id,
      p_inventory_unit_id,
      normalized_internal_notes,
      1,
      actor_user_id,
      actor_user_id
    )
    on conflict on constraint inventory_unit_internal_details_pkey do update
    set internal_notes = excluded.internal_notes,
        version = public.inventory_unit_internal_details.version + 1,
        updated_by = excluded.updated_by;
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_unit.updated',
    p_entity_type => 'inventory_unit',
    p_entity_id => p_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object('version', existing_unit.version),
    p_after_data => pg_catalog.jsonb_build_object(
      'version', next_version,
      'changed_keys', changed_keys
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'internal_values_redacted', p_update_internal_notes
    )
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_unit.updated',
    p_inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', p_inventory_unit_id,
      'aggregateVersion', next_version,
      'changedKeys', changed_keys
    ),
    actor_user_id,
    p_correlation_id
  );

  result_payload := pg_catalog.jsonb_build_object(
    'inventory_unit_id', p_inventory_unit_id,
    'aggregate_version', next_version,
    'canonical_status', existing_unit.status,
    'state_key', coalesce(existing_unit.workflow_state_key, existing_unit.status),
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.inventory_command_receipts (
    workspace_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    inventory_unit_id,
    result,
    actor_user_id
  ) values (
    p_workspace_id,
    'update_inventory_unit_details',
    normalized_idempotency_key,
    request_fingerprint,
    p_inventory_unit_id,
    result_payload,
    actor_user_id
  );

  return query select
    p_inventory_unit_id,
    next_version,
    existing_unit.status,
    coalesce(existing_unit.workflow_state_key, existing_unit.status),
    false,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create or replace function app.transfer_inventory_unit_location_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_to_location_id uuid,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  location_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  existing_unit public.inventory_units%rowtype;
  linked_instance public.workflow_instances%rowtype;
  existing_receipt public.inventory_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_reason text;
  request_fingerprint text;
  next_version bigint;
  new_location_event_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_inventory_command_permission(
    p_workspace_id,
    'inventory.update'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid inventory idempotency key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if normalized_reason is null or pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'location transfer reason is required';
  end if;
  if p_to_location_id is null or p_correlation_id is null then
    raise exception using errcode = '23502', message = 'location and correlation ID are required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'inventory request ID is too long';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_version', p_expected_version,
      'to_location_id', p_to_location_id,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1ftransfer_inventory_unit_location\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.inventory_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'transfer_inventory_unit_location'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'inventory idempotency key was used for a different location command';
    end if;
    return query select
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      existing_receipt.result ->> 'canonical_status',
      existing_receipt.result ->> 'state_key',
      true,
      (existing_receipt.result ->> 'location_event_id')::uuid,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select unit.*
    into existing_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if existing_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if existing_unit.status in ('closed', 'archived') then
    raise exception using
      errcode = '23514',
      message = 'closed inventory cannot transfer location';
  end if;
  if existing_unit.workflow_instance_id is not null then
    select instance.*
      into linked_instance
    from public.workflow_instances instance
    where instance.workspace_id = p_workspace_id
      and instance.id = existing_unit.workflow_instance_id
      and instance.entity_type = 'inventory_unit'
      and instance.entity_id = p_inventory_unit_id
      and instance.purpose_key = 'primary'
    for update;

    if not found or linked_instance.lifecycle_status <> 'active' then
      raise exception using errcode = '23514', message = 'inventory workflow is not active';
    end if;
    if linked_instance.version <> existing_unit.version
      or linked_instance.current_state_key <> existing_unit.workflow_state_key
      or linked_instance.canonical_status <> existing_unit.status then
      raise exception using
        errcode = '40001',
        message = 'inventory workflow aggregate versions are inconsistent';
    end if;
  end if;
  if existing_unit.location_id = p_to_location_id then
    raise exception using errcode = '23514', message = 'inventory is already at that location';
  end if;
  if not exists (
    select 1
    from public.locations location
    where location.workspace_id = p_workspace_id
      and location.id = p_to_location_id
      and location.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'destination location is unavailable';
  end if;

  next_version := existing_unit.version + 1;
  if existing_unit.workflow_instance_id is not null then
    update public.workflow_instances
    set version = next_version
    where workspace_id = p_workspace_id
      and id = linked_instance.id;
  end if;

  update public.inventory_units
  set location_id = p_to_location_id,
      version = next_version
  where workspace_id = p_workspace_id
    and id = p_inventory_unit_id;

  insert into public.inventory_location_events (
    workspace_id,
    inventory_unit_id,
    from_location_id,
    to_location_id,
    aggregate_version,
    reason,
    actor_user_id,
    request_id,
    correlation_id
  ) values (
    p_workspace_id,
    p_inventory_unit_id,
    existing_unit.location_id,
    p_to_location_id,
    next_version,
    normalized_reason,
    actor_user_id,
    p_request_id,
    p_correlation_id
  )
  returning id into new_location_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_unit.location_transferred',
    p_entity_type => 'inventory_unit',
    p_entity_id => p_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'location_id', existing_unit.location_id,
      'version', existing_unit.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'location_id', p_to_location_id,
      'version', next_version
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'location_event_id', new_location_event_id
    )
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_unit.location_transferred',
    p_inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', p_inventory_unit_id,
      'aggregateVersion', next_version,
      'fromLocationId', existing_unit.location_id,
      'toLocationId', p_to_location_id,
      'effectKeys', pg_catalog.jsonb_build_array('listing.refresh')
    ),
    actor_user_id,
    p_correlation_id
  );

  result_payload := pg_catalog.jsonb_build_object(
    'inventory_unit_id', p_inventory_unit_id,
    'aggregate_version', next_version,
    'canonical_status', existing_unit.status,
    'state_key', coalesce(existing_unit.workflow_state_key, existing_unit.status),
    'location_event_id', new_location_event_id,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.inventory_command_receipts (
    workspace_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    inventory_unit_id,
    result,
    actor_user_id
  ) values (
    p_workspace_id,
    'transfer_inventory_unit_location',
    normalized_idempotency_key,
    request_fingerprint,
    p_inventory_unit_id,
    result_payload,
    actor_user_id
  );

  return query select
    p_inventory_unit_id,
    next_version,
    existing_unit.status,
    coalesce(existing_unit.workflow_state_key, existing_unit.status),
    false,
    new_location_event_id,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create or replace function app.transition_inventory_workflow_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_transition_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  workflow_event_id uuid,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  existing_unit public.inventory_units%rowtype;
  existing_instance public.workflow_instances%rowtype;
  configured_transition public.workflow_transitions%rowtype;
  target_state public.workflow_states%rowtype;
  existing_receipt public.inventory_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_transition_key text;
  normalized_reason text;
  request_fingerprint text;
  next_version bigint;
  terminal_state boolean;
  new_workflow_event_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_inventory_command_permission(
    p_workspace_id,
    'inventory.transition'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_transition_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_transition_key, ''))
  );
  normalized_reason := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid inventory idempotency key';
  end if;
  if normalized_transition_key !~ '^[a-z][a-z0-9_]*$' then
    raise exception using errcode = '22023', message = 'invalid workflow transition key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if normalized_reason is not null and pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'workflow transition reason is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'inventory request ID is too long';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_version', p_expected_version,
      'transition_key', normalized_transition_key,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1ftransition_inventory_workflow\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.inventory_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'transition_inventory_workflow'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.command_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'inventory idempotency key was used for a different transition command';
    end if;
    return query select
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      existing_receipt.result ->> 'canonical_status',
      existing_receipt.result ->> 'state_key',
      true,
      (existing_receipt.result ->> 'workflow_event_id')::uuid,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select unit.*
    into existing_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if existing_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if existing_unit.workflow_instance_id is null then
    raise exception using errcode = '23514', message = 'inventory workflow is not configured';
  end if;

  select instance.*
    into existing_instance
  from public.workflow_instances instance
  where instance.workspace_id = p_workspace_id
    and instance.id = existing_unit.workflow_instance_id
    and instance.entity_type = 'inventory_unit'
    and instance.entity_id = p_inventory_unit_id
    and instance.purpose_key = 'primary'
  for update;

  if not found or existing_instance.lifecycle_status <> 'active' then
    raise exception using errcode = '23514', message = 'inventory workflow is not active';
  end if;
  if existing_instance.version <> existing_unit.version
    or existing_instance.current_state_key <> existing_unit.workflow_state_key
    or existing_instance.canonical_status <> existing_unit.status then
    raise exception using
      errcode = '40001',
      message = 'inventory workflow aggregate versions are inconsistent';
  end if;

  select transition.*
    into configured_transition
  from public.workflow_transitions transition
  where transition.workspace_id = p_workspace_id
    and transition.workflow_version_id = existing_instance.workflow_version_id
    and transition.key = normalized_transition_key
    and transition.from_state_key = existing_instance.current_state_key;

  if not found then
    raise exception using errcode = '23514', message = 'workflow transition is not allowed';
  end if;
  if not app.has_permission(p_workspace_id, configured_transition.permission_key) then
    raise exception using
      errcode = '42501',
      message = 'configured workflow transition permission is required';
  end if;
  if configured_transition.reason_required and normalized_reason is null then
    raise exception using errcode = '23514', message = 'workflow transition reason is required';
  end if;

  if configured_transition.guard_key = 'required_fields_complete' and not exists (
    select 1
    from public.vehicles vehicle
    where vehicle.workspace_id = existing_unit.workspace_id
      and vehicle.id = existing_unit.vehicle_id
      and vehicle.model_year is not null
      and vehicle.make is not null
      and vehicle.model is not null
      and existing_unit.location_id is not null
      and existing_unit.acquisition_date is not null
      and existing_unit.odometer_value is not null
      and existing_unit.odometer_unit is not null
  ) then
    raise exception using
      errcode = '23514',
      message = 'required inventory fields are incomplete';
  end if;
  if configured_transition.guard_key = 'sale_completion_requirements_met'
    and not exists (
      select 1
      from public.deal_inventory_units inventory_link
      join public.deals deal
        on deal.workspace_id = inventory_link.workspace_id
       and deal.id = inventory_link.deal_id
      where inventory_link.workspace_id = p_workspace_id
        and inventory_link.inventory_unit_id = p_inventory_unit_id
        and inventory_link.role_key = 'sold'
        and inventory_link.status = 'active'
        and deal.status = 'completed'
    ) then
    raise exception using
      errcode = '23514',
      message = 'sale completion requirements are not met';
  end if;

  select state.*
    into target_state
  from public.workflow_states state
  where state.workspace_id = p_workspace_id
    and state.workflow_version_id = existing_instance.workflow_version_id
    and state.key = configured_transition.to_state_key;

  if not found then
    raise exception using errcode = '23514', message = 'workflow target state is unavailable';
  end if;

  next_version := existing_unit.version + 1;
  terminal_state := target_state.behavior_flags @> '{"terminal":true}'::jsonb
    or target_state.canonical_category in ('closed', 'archived');

  update public.workflow_instances
  set current_state_key = target_state.key,
      canonical_status = target_state.canonical_category,
      lifecycle_status = case when terminal_state then 'completed' else 'active' end,
      completed_at = case when terminal_state
        then pg_catalog.statement_timestamp() else null end,
      version = next_version
  where workspace_id = p_workspace_id
    and id = existing_instance.id;

  update public.inventory_units
  set workflow_state_key = target_state.key,
      status = target_state.canonical_category,
      available_at = case
        when target_state.behavior_flags @> '{"available":true}'::jsonb
          then coalesce(available_at, pg_catalog.statement_timestamp())
        else available_at
      end,
      sold_at = case
        when target_state.key = 'sold'
          then coalesce(sold_at, pg_catalog.statement_timestamp())
        else sold_at
      end,
      closed_at = case
        when target_state.canonical_category in ('closed', 'archived')
          then coalesce(closed_at, pg_catalog.statement_timestamp())
        else closed_at
      end,
      version = next_version
  where workspace_id = p_workspace_id
    and id = p_inventory_unit_id;

  insert into public.workflow_events (
    workspace_id,
    workflow_instance_id,
    transition_id,
    entity_type,
    entity_id,
    from_state_key,
    to_state_key,
    aggregate_version,
    reason,
    actor_user_id,
    request_id,
    correlation_id
  ) values (
    p_workspace_id,
    existing_instance.id,
    configured_transition.id,
    'inventory_unit',
    p_inventory_unit_id,
    existing_instance.current_state_key,
    target_state.key,
    next_version,
    normalized_reason,
    actor_user_id,
    p_request_id,
    p_correlation_id
  )
  returning id into new_workflow_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_unit.transitioned',
    p_entity_type => 'inventory_unit',
    p_entity_id => p_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'state_key', existing_instance.current_state_key,
      'canonical_status', existing_instance.canonical_status,
      'version', existing_unit.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'state_key', target_state.key,
      'canonical_status', target_state.canonical_category,
      'version', next_version
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'workflow_event_id', new_workflow_event_id,
      'transition_key', configured_transition.key
    )
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_unit.transitioned',
    p_inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', p_inventory_unit_id,
      'aggregateVersion', next_version,
      'transitionKey', configured_transition.key,
      'fromStateKey', existing_instance.current_state_key,
      'toStateKey', target_state.key,
      'canonicalStatus', target_state.canonical_category,
      'effectKeys', configured_transition.effect_keys
    ),
    actor_user_id,
    p_correlation_id
  );

  result_payload := pg_catalog.jsonb_build_object(
    'inventory_unit_id', p_inventory_unit_id,
    'aggregate_version', next_version,
    'canonical_status', target_state.canonical_category,
    'state_key', target_state.key,
    'workflow_event_id', new_workflow_event_id,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.inventory_command_receipts (
    workspace_id,
    command_type,
    idempotency_key,
    command_fingerprint,
    inventory_unit_id,
    result,
    actor_user_id
  ) values (
    p_workspace_id,
    'transition_inventory_workflow',
    normalized_idempotency_key,
    request_fingerprint,
    p_inventory_unit_id,
    result_payload,
    actor_user_id
  );

  return query select
    p_inventory_unit_id,
    next_version,
    target_state.canonical_category,
    target_state.key,
    false,
    new_workflow_event_id,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create or replace function app.post_inventory_cost_entry_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_version bigint,
  p_category_definition_id uuid,
  p_amount_minor bigint,
  p_currency_code text,
  p_incurred_on date,
  p_vendor_party_id uuid,
  p_description text,
  p_supporting_file_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
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
  target_unit public.inventory_units%rowtype;
  linked_instance public.workflow_instances%rowtype;
  existing_entry public.inventory_cost_entries%rowtype;
  normalized_idempotency_key text;
  normalized_currency text;
  normalized_description text;
  request_fingerprint text;
  next_version bigint;
  new_entry_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'costs.create'
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_description := nullif(
    pg_catalog.btrim(coalesce(p_description, '')),
    ''
  );

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid cost idempotency key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception using errcode = '22023', message = 'cost amount must be positive minor units';
  end if;
  if normalized_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'invalid cost currency';
  end if;
  if p_incurred_on is null or p_incurred_on > current_date then
    raise exception using errcode = '22023', message = 'invalid cost incurred date';
  end if;
  if normalized_description is not null
    and pg_catalog.char_length(normalized_description) > 2000 then
    raise exception using errcode = '22023', message = 'cost description is too long';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'request ID is too long';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_version', p_expected_version,
      'category_definition_id', p_category_definition_id,
      'amount_minor', p_amount_minor,
      'currency_code', normalized_currency,
      'incurred_on', p_incurred_on,
      'vendor_party_id', p_vendor_party_id,
      'description', normalized_description,
      'supporting_file_id', p_supporting_file_id
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1finventory_cost.cost\x1f' || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select entry.*
    into existing_entry
  from public.inventory_cost_entries entry
  where entry.workspace_id = p_workspace_id
    and entry.created_by = actor_user_id
    and entry.entry_kind = 'cost'
    and entry.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_entry.command_fingerprint <> request_fingerprint
      or existing_entry.entry_kind <> 'cost' then
      raise exception using
        errcode = '23505',
        message = 'cost idempotency key was used for a different command';
    end if;
    select audit.id
      into new_audit_event_id
    from public.audit_events audit
    where audit.workspace_id = p_workspace_id
      and audit.entity_type = 'inventory_cost_entry'
      and audit.entity_id = existing_entry.id
      and audit.action = 'inventory_cost.posted'
    order by audit.occurred_at, audit.id
    limit 1;
    select event.id
      into new_outbox_event_id
    from public.outbox_events event
    where event.workspace_id = p_workspace_id
      and event.aggregate_type = 'inventory_unit'
      and event.aggregate_id = existing_entry.inventory_unit_id
      and event.aggregate_version = existing_entry.aggregate_version
      and event.event_name = 'inventory_cost.posted'
    order by event.occurred_at, event.id
    limit 1;
    if new_audit_event_id is null or new_outbox_event_id is null then
      raise exception using errcode = '55000', message = 'cost command receipt is incomplete';
    end if;
    return query select
      existing_entry.id,
      existing_entry.inventory_unit_id,
      existing_entry.aggregate_version,
      true,
      new_audit_event_id,
      new_outbox_event_id;
    return;
  end if;

  select unit.*
    into target_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_inventory_unit_id
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if target_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if target_unit.workflow_instance_id is not null then
    select instance.*
      into linked_instance
    from public.workflow_instances instance
    where instance.workspace_id = p_workspace_id
      and instance.id = target_unit.workflow_instance_id
      and instance.entity_type = 'inventory_unit'
      and instance.entity_id = p_inventory_unit_id
      and instance.purpose_key = 'primary'
    for update;

    if not found then
      raise exception using errcode = '23514', message = 'inventory workflow is unavailable';
    end if;
    if linked_instance.version <> target_unit.version
      or linked_instance.current_state_key <> target_unit.workflow_state_key
      or linked_instance.canonical_status <> target_unit.status then
      raise exception using
        errcode = '40001',
        message = 'inventory workflow aggregate versions are inconsistent';
    end if;
  end if;
  if target_unit.currency_code <> normalized_currency then
    raise exception using errcode = '23514', message = 'cost currency must match inventory currency';
  end if;
  if not exists (
    select 1
    from public.inventory_cost_category_definitions category
    where category.workspace_id = p_workspace_id
      and category.id = p_category_definition_id
      and category.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'an active cost category is required';
  end if;
  if p_vendor_party_id is not null and not exists (
    select 1
    from public.parties party
    where party.workspace_id = p_workspace_id
      and party.id = p_vendor_party_id
      and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'cost vendor is unavailable';
  end if;
  if p_supporting_file_id is not null and not exists (
    select 1
    from public.media_files file
    join public.media_assets asset
      on asset.workspace_id = file.workspace_id
     and asset.id = file.media_id
    where file.workspace_id = p_workspace_id
      and file.id = p_supporting_file_id
      and file.file_class = 'legal_document_original'
      and file.variant = 'legal_original'
      and file.deleted_at is null
      and asset.status = 'ready'
      and asset.owner_entity_type = 'inventory_unit'
      and asset.owner_entity_id = p_inventory_unit_id
      and asset.media_kind in ('legal_document', 'attachment')
  ) then
    raise exception using
      errcode = '23514',
      message = 'cost supporting file is unavailable';
  end if;

  next_version := target_unit.version + 1;
  new_entry_id := pg_catalog.gen_random_uuid();
  insert into public.inventory_cost_entries (
    id,
    workspace_id,
    inventory_unit_id,
    category_definition_id,
    entry_kind,
    amount_minor,
    currency_code,
    incurred_on,
    vendor_party_id,
    description,
    supporting_file_id,
    idempotency_key,
    command_fingerprint,
    aggregate_version,
    created_by
  ) values (
    new_entry_id,
    p_workspace_id,
    p_inventory_unit_id,
    p_category_definition_id,
    'cost',
    p_amount_minor,
    normalized_currency,
    p_incurred_on,
    p_vendor_party_id,
    normalized_description,
    p_supporting_file_id,
    normalized_idempotency_key,
    request_fingerprint,
    next_version,
    actor_user_id
  );

  if target_unit.workflow_instance_id is not null then
    update public.workflow_instances
    set version = next_version
    where workspace_id = p_workspace_id
      and id = linked_instance.id;
  end if;

  update public.inventory_units
  set version = next_version
  where workspace_id = p_workspace_id
    and id = p_inventory_unit_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_cost.posted',
    p_entity_type => 'inventory_cost_entry',
    p_entity_id => new_entry_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'category_definition_id', p_category_definition_id,
      'amount_minor', p_amount_minor::text,
      'currency_code', normalized_currency,
      'aggregate_version', next_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'vendor_party_id', p_vendor_party_id,
      'supporting_file_id', p_supporting_file_id
    )
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_cost.posted',
    p_inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', p_inventory_unit_id,
      'costEntryId', new_entry_id,
      'amountMinor', p_amount_minor::text,
      'currencyCode', normalized_currency,
      'aggregateVersion', next_version
    ),
    actor_user_id,
    p_correlation_id
  );

  return query select
    new_entry_id,
    p_inventory_unit_id,
    next_version,
    false,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create or replace function app.reverse_inventory_cost_entry_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_cost_entry_id uuid,
  p_expected_version bigint,
  p_reversed_on date,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  reversal_entry_id uuid,
  original_cost_entry_id uuid,
  inventory_unit_id uuid,
  aggregate_version bigint,
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
  original_entry public.inventory_cost_entries%rowtype;
  existing_reversal public.inventory_cost_entries%rowtype;
  target_unit public.inventory_units%rowtype;
  linked_instance public.workflow_instances%rowtype;
  normalized_idempotency_key text;
  normalized_reason text;
  request_fingerprint text;
  next_version bigint;
  new_reversal_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'costs.reverse',
    true
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid reversal idempotency key';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected inventory version is required';
  end if;
  if normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'cost reversal reason is required';
  end if;
  if p_reversed_on is null or p_reversed_on > current_date then
    raise exception using errcode = '22023', message = 'invalid reversal date';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'cost_entry_id', p_cost_entry_id,
      'expected_version', p_expected_version,
      'reversed_on', p_reversed_on,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1finventory_cost.reversal\x1f' || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select entry.*
    into existing_reversal
  from public.inventory_cost_entries entry
  where entry.workspace_id = p_workspace_id
    and entry.created_by = actor_user_id
    and entry.entry_kind = 'reversal'
    and entry.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_reversal.command_fingerprint <> request_fingerprint
      or existing_reversal.entry_kind <> 'reversal' then
      raise exception using
        errcode = '23505',
        message = 'reversal idempotency key was used for a different command';
    end if;
    select audit.id
      into new_audit_event_id
    from public.audit_events audit
    where audit.workspace_id = p_workspace_id
      and audit.entity_type = 'inventory_cost_entry'
      and audit.entity_id = existing_reversal.id
      and audit.action = 'inventory_cost.reversed'
    order by audit.occurred_at, audit.id
    limit 1;
    select event.id
      into new_outbox_event_id
    from public.outbox_events event
    where event.workspace_id = p_workspace_id
      and event.aggregate_type = 'inventory_unit'
      and event.aggregate_id = existing_reversal.inventory_unit_id
      and event.aggregate_version = existing_reversal.aggregate_version
      and event.event_name = 'inventory_cost.reversed'
    order by event.occurred_at, event.id
    limit 1;
    if new_audit_event_id is null or new_outbox_event_id is null then
      raise exception using errcode = '55000', message = 'reversal command receipt is incomplete';
    end if;
    return query select
      existing_reversal.id,
      existing_reversal.reversal_of_id,
      existing_reversal.inventory_unit_id,
      existing_reversal.aggregate_version,
      true,
      new_audit_event_id,
      new_outbox_event_id;
    return;
  end if;

  select entry.*
    into original_entry
  from public.inventory_cost_entries entry
  where entry.workspace_id = p_workspace_id
    and entry.id = p_cost_entry_id
    and entry.entry_kind = 'cost';
  if not found then
    raise exception using errcode = '23514', message = 'posted cost entry is unavailable';
  end if;
  if p_reversed_on < original_entry.incurred_on then
    raise exception using errcode = '22023', message = 'invalid reversal date';
  end if;

  select unit.*
    into target_unit
  from public.inventory_units unit
  where unit.workspace_id = p_workspace_id
    and unit.id = original_entry.inventory_unit_id
  for update;
  if not found then
    raise exception using errcode = '23514', message = 'inventory unit is unavailable';
  end if;
  if target_unit.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'inventory version conflict';
  end if;
  if target_unit.workflow_instance_id is not null then
    select instance.*
      into linked_instance
    from public.workflow_instances instance
    where instance.workspace_id = p_workspace_id
      and instance.id = target_unit.workflow_instance_id
      and instance.entity_type = 'inventory_unit'
      and instance.entity_id = original_entry.inventory_unit_id
      and instance.purpose_key = 'primary'
    for update;

    if not found then
      raise exception using errcode = '23514', message = 'inventory workflow is unavailable';
    end if;
    if linked_instance.version <> target_unit.version
      or linked_instance.current_state_key <> target_unit.workflow_state_key
      or linked_instance.canonical_status <> target_unit.status then
      raise exception using
        errcode = '40001',
        message = 'inventory workflow aggregate versions are inconsistent';
    end if;
  end if;
  if exists (
    select 1
    from public.inventory_cost_entries reversal
    where reversal.workspace_id = p_workspace_id
      and reversal.reversal_of_id = original_entry.id
      and reversal.entry_kind = 'reversal'
  ) then
    raise exception using errcode = '23514', message = 'cost entry is already reversed';
  end if;

  next_version := target_unit.version + 1;
  new_reversal_id := pg_catalog.gen_random_uuid();
  insert into public.inventory_cost_entries (
    id,
    workspace_id,
    inventory_unit_id,
    category_definition_id,
    entry_kind,
    reversal_of_id,
    amount_minor,
    currency_code,
    incurred_on,
    vendor_party_id,
    description,
    supporting_file_id,
    idempotency_key,
    command_fingerprint,
    aggregate_version,
    created_by
  ) values (
    new_reversal_id,
    p_workspace_id,
    original_entry.inventory_unit_id,
    original_entry.category_definition_id,
    'reversal',
    original_entry.id,
    original_entry.amount_minor,
    original_entry.currency_code,
    p_reversed_on,
    original_entry.vendor_party_id,
    normalized_reason,
    original_entry.supporting_file_id,
    normalized_idempotency_key,
    request_fingerprint,
    next_version,
    actor_user_id
  );

  if target_unit.workflow_instance_id is not null then
    update public.workflow_instances
    set version = next_version
    where workspace_id = p_workspace_id
      and id = linked_instance.id;
  end if;

  update public.inventory_units
  set version = next_version
  where workspace_id = p_workspace_id
    and id = original_entry.inventory_unit_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'inventory_cost.reversed',
    p_entity_type => 'inventory_cost_entry',
    p_entity_id => new_reversal_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'original_cost_entry_id', original_entry.id,
      'inventory_unit_id', original_entry.inventory_unit_id,
      'amount_minor', original_entry.amount_minor::text,
      'currency_code', original_entry.currency_code,
      'aggregate_version', next_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2',
    p_metadata => pg_catalog.jsonb_build_object('reason_recorded', true)
  );
  new_outbox_event_id := app.append_inventory_outbox_event(
    p_workspace_id,
    'inventory_cost.reversed',
    original_entry.inventory_unit_id,
    next_version,
    pg_catalog.jsonb_build_object(
      'inventoryUnitId', original_entry.inventory_unit_id,
      'costEntryId', original_entry.id,
      'reversalEntryId', new_reversal_id,
      'amountMinor', original_entry.amount_minor::text,
      'currencyCode', original_entry.currency_code::text,
      'aggregateVersion', next_version
    ),
    actor_user_id,
    p_correlation_id
  );

  return query select
    new_reversal_id,
    original_entry.id,
    original_entry.inventory_unit_id,
    next_version,
    false,
    new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create or replace function app.create_vehicle_photo_upload_session_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_checksum_sha256 text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  upload_session_id uuid,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  collection_version bigint,
  aggregate_version bigint,
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
  profile_id uuid;
  target_collection public.inventory_media_collections%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_filename text;
  normalized_mime_type text;
  normalized_checksum text;
  request_fingerprint text;
  new_media_id uuid := pg_catalog.gen_random_uuid();
  new_upload_session_id uuid := pg_catalog.gen_random_uuid();
  new_upload_bucket text := 'media-private';
  new_upload_object_key text;
  new_expires_at timestamptz := pg_catalog.statement_timestamp()
    + pg_catalog.make_interval(mins => 15);
  new_sort_order integer;
  new_collection_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_media_permission(p_workspace_id, 'media.create');
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_filename := pg_catalog.btrim(coalesce(p_filename, ''));
  normalized_mime_type := pg_catalog.lower(pg_catalog.btrim(coalesce(p_mime_type, '')));
  normalized_checksum := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_checksum_sha256, ''))),
    ''
  );

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid media idempotency key';
  end if;
  if pg_catalog.char_length(normalized_filename) not between 1 and 255
    or normalized_filename ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'invalid media filename';
  end if;
  if normalized_mime_type not in (
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
  ) then
    raise exception using errcode = '22023', message = 'unsupported vehicle photo media type';
  end if;
  if p_byte_size is null or p_byte_size not between 1 and 20000000 then
    raise exception using errcode = '22023', message = 'invalid vehicle photo byte size';
  end if;
  if normalized_checksum is not null and normalized_checksum !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'invalid vehicle photo checksum';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'media request ID is too long';
  end if;

  if not exists (
    select 1
    from public.inventory_units unit
    where unit.workspace_id = p_workspace_id
      and unit.id = p_inventory_unit_id
      and unit.status <> 'archived'
  ) then
    raise exception using errcode = 'P0002', message = 'inventory unit was not found';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'filename', normalized_filename,
      'mime_type', normalized_mime_type,
      'byte_size', p_byte_size,
      'checksum_sha256', normalized_checksum
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.create_upload\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'media.create_upload'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'media idempotency key was used for a different upload request';
    end if;
    return query select
      (existing_receipt.result ->> 'media_id')::uuid,
      (existing_receipt.result ->> 'upload_session_id')::uuid,
      existing_receipt.result ->> 'upload_bucket',
      existing_receipt.result ->> 'upload_object_key',
      (existing_receipt.result ->> 'expires_at')::timestamptz,
      (existing_receipt.result ->> 'collection_version')::bigint,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  profile_id := app.ensure_default_vehicle_photo_profile(
    p_workspace_id,
    actor_user_id
  );

  insert into public.inventory_media_collections (
    workspace_id, inventory_unit_id
  ) values (
    p_workspace_id, p_inventory_unit_id
  ) on conflict (workspace_id, inventory_unit_id) do nothing;

  select collection.* into target_collection
  from public.inventory_media_collections collection
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = p_inventory_unit_id
  for update;

  select pg_catalog.count(*)::integer into new_sort_order
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.inventory_unit_id = p_inventory_unit_id
    and asset.media_kind = 'vehicle_photo'
    and asset.status <> 'archived';

  if new_sort_order >= 50 then
    raise exception using
      errcode = '23514',
      message = 'vehicle photo collection limit was reached';
  end if;

  new_upload_object_key := 'workspaces/' || p_workspace_id::text
    || '/uploads/' || new_upload_session_id::text || '/source';

  insert into public.media_assets (
    id, workspace_id, inventory_unit_id, owner_entity_type, owner_entity_id,
    media_kind, status, sort_order, is_cover, processing_profile_id, created_by
  ) values (
    new_media_id, p_workspace_id, p_inventory_unit_id,
    'inventory_unit', p_inventory_unit_id, 'vehicle_photo', 'awaiting_upload',
    new_sort_order, new_sort_order = 0, profile_id, actor_user_id
  );

  insert into public.media_upload_sessions (
    id, workspace_id, media_id, original_filename, expected_mime_type,
    expected_byte_size, expected_checksum_sha256, quarantine_bucket,
    quarantine_object_key, expires_at, created_by
  ) values (
    new_upload_session_id, p_workspace_id, new_media_id, normalized_filename,
    normalized_mime_type, p_byte_size, normalized_checksum, new_upload_bucket,
    new_upload_object_key, new_expires_at, actor_user_id
  );

  update public.inventory_media_collections collection
  set version = collection.version + 1,
      updated_at = pg_catalog.statement_timestamp()
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = p_inventory_unit_id
  returning collection.version into new_collection_version;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.upload_intent_created',
    p_entity_type => 'media_asset',
    p_entity_id => new_media_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'awaiting_upload',
      'media_kind', 'vehicle_photo',
      'inventory_unit_id', p_inventory_unit_id,
      'sort_order', new_sort_order,
      'is_cover', new_sort_order = 0,
      'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'upload_session_id', new_upload_session_id,
      'profile_id', profile_id,
      'collection_version', new_collection_version
    )
  );

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, actor_user_id,
    correlation_id
  ) values (
    p_workspace_id, 'media.upload_intent_created', 'media_asset', new_media_id,
    1, 1,
    pg_catalog.jsonb_build_object(
      'media_id', new_media_id,
      'inventory_unit_id', p_inventory_unit_id,
      'upload_session_id', new_upload_session_id,
      'profile_id', profile_id
    ),
    actor_user_id, p_correlation_id
  ) returning id into new_outbox_event_id;

  result_payload := pg_catalog.jsonb_build_object(
    'media_id', new_media_id,
    'upload_session_id', new_upload_session_id,
    'upload_bucket', new_upload_bucket,
    'upload_object_key', new_upload_object_key,
    'expires_at', new_expires_at,
    'collection_version', new_collection_version,
    'aggregate_version', 1,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );

  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.create_upload', normalized_idempotency_key,
    request_fingerprint, result_payload, actor_user_id
  );

  return query select
    new_media_id, new_upload_session_id, new_upload_bucket,
    new_upload_object_key, new_expires_at, new_collection_version,
    1::bigint, false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create or replace function app.complete_vehicle_photo_upload_actor_key_impl(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_upload_session_id uuid,
  p_observed_mime_type text,
  p_observed_byte_size bigint,
  p_observed_checksum_sha256 text,
  p_signature_verified boolean,
  p_width integer,
  p_height integer,
  p_exif_orientation integer,
  p_malware_scan_receipt jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  processing_run_id uuid,
  job_id uuid,
  media_status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_media public.media_assets%rowtype;
  target_upload public.media_upload_sessions%rowtype;
  target_profile public.media_processing_profiles%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_mime_type text;
  normalized_checksum text;
  request_fingerprint text;
  next_media_version bigint;
  new_processing_run_id uuid := pg_catalog.gen_random_uuid();
  new_job_id uuid;
  new_outbox_event_id uuid;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  if p_actor_user_id is null
    or not app.job_actor_has_permission(
      p_workspace_id,
      p_actor_user_id,
      'media.create'
    ) then
    raise exception using
      errcode = '42501',
      message = 'validated media.create actor is required';
  end if;

  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_mime_type := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_observed_mime_type, ''))
  );
  normalized_checksum := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_observed_checksum_sha256, ''))
  );

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'invalid media idempotency key';
  end if;
  if normalized_mime_type not in (
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
  ) or normalized_checksum !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'invalid observed upload metadata';
  end if;
  if p_observed_byte_size is null or p_observed_byte_size not between 1 and 20000000
    or p_signature_verified is distinct from true
    or p_width is null or p_width < 1
    or p_height is null or p_height < 1
    or p_width::bigint * p_height::bigint > 60000000
    or (p_exif_orientation is not null and p_exif_orientation not between 1 and 8)
    or p_malware_scan_receipt is null
    or pg_catalog.jsonb_typeof(p_malware_scan_receipt) <> 'object'
    or app.job_payload_contains_forbidden_key(p_malware_scan_receipt)
    or p_malware_scan_receipt ->> 'verdict' <> 'clean'
    or p_malware_scan_receipt ->> 'sourceChecksumSha256' <> normalized_checksum
    or pg_catalog.jsonb_typeof(p_malware_scan_receipt -> 'scanner') <> 'object'
    or pg_catalog.btrim(coalesce(p_malware_scan_receipt #>> '{scanner,name}', '')) = ''
    or pg_catalog.btrim(coalesce(p_malware_scan_receipt #>> '{scanner,version}', '')) = ''
    or pg_catalog.btrim(coalesce(p_malware_scan_receipt ->> 'signatureVersion', '')) = '' then
    raise exception using
      errcode = '23514',
      message = 'upload must pass signature, dimension, checksum, and malware validation';
  end if;
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if p_request_id is not null and pg_catalog.char_length(p_request_id) > 200 then
    raise exception using errcode = '22023', message = 'media request ID is too long';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'upload_session_id', p_upload_session_id,
      'observed_mime_type', normalized_mime_type,
      'observed_byte_size', p_observed_byte_size,
      'observed_checksum_sha256', normalized_checksum,
      'signature_verified', p_signature_verified,
      'width', p_width,
      'height', p_height,
      'exif_orientation', p_exif_orientation,
      'malware_scan_receipt', p_malware_scan_receipt
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.complete_upload\x1f'
        || p_actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = p_actor_user_id
    and receipt.command_type = 'media.complete_upload'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'media idempotency key was used for a different completion request';
    end if;
    return query select
      (existing_receipt.result ->> 'media_id')::uuid,
      (existing_receipt.result ->> 'processing_run_id')::uuid,
      (existing_receipt.result ->> 'job_id')::uuid,
      existing_receipt.result ->> 'media_status',
      (existing_receipt.result ->> 'aggregate_version')::bigint,
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
  for update;

  if not found or target_media.status <> 'awaiting_upload' then
    raise exception using errcode = '55000', message = 'media is not awaiting upload';
  end if;

  select upload.* into target_upload
  from public.media_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id
    and upload.media_id = p_media_id
  for update;

  if not found
    or target_upload.status <> 'awaiting_upload'
    or target_upload.expires_at <= pg_catalog.statement_timestamp() then
    raise exception using errcode = '55000', message = 'media upload session is unavailable';
  end if;
  if target_upload.expected_mime_type <> normalized_mime_type
    or target_upload.expected_byte_size <> p_observed_byte_size
    or (
      target_upload.expected_checksum_sha256 is not null
      and target_upload.expected_checksum_sha256 <> normalized_checksum
    ) then
    raise exception using errcode = '23514', message = 'uploaded object differs from its intent';
  end if;

  select profile.* into target_profile
  from public.media_processing_profiles profile
  where profile.workspace_id = p_workspace_id
    and profile.id = target_media.processing_profile_id;

  if not found or target_profile.status not in ('active', 'retired') then
    raise exception using errcode = '23514', message = 'media processing profile is unavailable';
  end if;

  insert into public.media_processing_runs (
    id, workspace_id, media_id, generation, source_kind, source_id,
    processing_profile_id, profile_snapshot, profile_checksum_sha256
  ) values (
    new_processing_run_id, p_workspace_id, p_media_id, target_media.generation,
    'upload_session', p_upload_session_id, target_profile.id,
    target_profile.profile_snapshot, target_profile.checksum_sha256
  );

  next_media_version := target_media.version + 1;

  select queued.outbox_event_id, queued.job_id
    into new_outbox_event_id, new_job_id
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'media.processing_queued',
    p_aggregate_type => 'media_asset',
    p_aggregate_id => p_media_id,
    p_aggregate_version => next_media_version,
    p_job_type => 'media.process_vehicle_photo',
    p_entity_type => 'vehicle_media',
    p_entity_id => p_media_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'processing_run_id', new_processing_run_id,
      'profile_checksum', target_profile.checksum_sha256,
      'source', pg_catalog.jsonb_build_object(
        'kind', 'upload_session',
        'id', p_upload_session_id
      )
    ),
    p_idempotency_key => 'media:process:' || new_processing_run_id::text,
    p_correlation_id => p_correlation_id,
    p_actor_user_id => p_actor_user_id,
    p_priority => 60,
    p_max_attempts => 8,
    p_backoff_base_seconds => 30,
    p_backoff_max_seconds => 3600,
    p_request_id => p_request_id
  ) queued;

  update public.media_processing_runs run
  set outbox_event_id = new_outbox_event_id,
      job_id = new_job_id
  where run.workspace_id = p_workspace_id
    and run.id = new_processing_run_id;

  update public.media_upload_sessions upload
  set status = 'completed',
      completed_at = pg_catalog.statement_timestamp(),
      observed_mime_type = normalized_mime_type,
      observed_byte_size = p_observed_byte_size,
      observed_checksum_sha256 = normalized_checksum,
      width = p_width,
      height = p_height,
      exif_orientation = p_exif_orientation,
      malware_scan_receipt = p_malware_scan_receipt
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id;

  update public.media_assets asset
  set status = 'quarantined',
      version = next_media_version,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.upload_completed',
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_user_id => p_actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', target_media.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'quarantined',
      'version', next_media_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'server_validated',
    p_metadata => pg_catalog.jsonb_build_object(
      'upload_session_id', p_upload_session_id,
      'processing_run_id', new_processing_run_id,
      'job_id', new_job_id,
      'outbox_event_id', new_outbox_event_id,
      'scanner_name', p_malware_scan_receipt #>> '{scanner,name}',
      'scanner_version', p_malware_scan_receipt #>> '{scanner,version}'
    )
  );

  result_payload := pg_catalog.jsonb_build_object(
    'media_id', p_media_id,
    'processing_run_id', new_processing_run_id,
    'job_id', new_job_id,
    'media_status', 'quarantined',
    'aggregate_version', next_media_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );

  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.complete_upload', normalized_idempotency_key,
    request_fingerprint, result_payload, p_actor_user_id
  );

  return query select
    p_media_id, new_processing_run_id, new_job_id, 'quarantined'::text,
    next_media_version, false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create or replace function app.reprocess_vehicle_photo_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_expected_version bigint,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  processing_run_id uuid,
  job_id uuid,
  media_status text,
  aggregate_version bigint,
  generation integer,
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
  source_file public.media_files%rowtype;
  source_upload public.media_upload_sessions%rowtype;
  target_profile public.media_processing_profiles%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_reason text;
  request_fingerprint text;
  source_kind text;
  source_id uuid;
  next_generation integer;
  next_media_version bigint;
  new_processing_run_id uuid := pg_catalog.gen_random_uuid();
  new_job_id uuid;
  new_outbox_event_id uuid;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_media_permission(p_workspace_id, 'media.update');
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_expected_version is null or p_expected_version < 1
    or pg_catalog.char_length(normalized_reason) not between 1 and 1000
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid media reprocess command';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'expected_version', p_expected_version,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.reprocess\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'media.reprocess'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505', message = 'media reprocess replay conflicts';
    end if;
    return query select
      (existing_receipt.result ->> 'media_id')::uuid,
      (existing_receipt.result ->> 'processing_run_id')::uuid,
      (existing_receipt.result ->> 'job_id')::uuid,
      existing_receipt.result ->> 'media_status',
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      (existing_receipt.result ->> 'generation')::integer,
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
  for update;
  if not found
    or target_media.status not in ('ready', 'failed')
    or target_media.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale or unavailable media version';
  end if;

  select file.* into source_file
  from public.media_files file
  where file.workspace_id = p_workspace_id
    and file.media_id = p_media_id
    and file.file_class = 'vehicle_photo_raw'
    and file.deleted_at is null
  order by file.created_at desc, file.id desc
  limit 1;

  if found then
    source_kind := 'media_file';
    source_id := source_file.id;
  else
    select upload.* into source_upload
    from public.media_upload_sessions upload
    where upload.workspace_id = p_workspace_id
      and upload.media_id = p_media_id
      and upload.status = 'completed'
    order by upload.completed_at desc, upload.id desc
    limit 1;
    if not found then
      raise exception using errcode = '23514', message = 'media has no retained source';
    end if;
    source_kind := 'upload_session';
    source_id := source_upload.id;
  end if;

  perform app.ensure_default_vehicle_photo_profile(p_workspace_id, actor_user_id);
  select profile.* into target_profile
  from public.media_processing_profiles profile
  where profile.workspace_id = p_workspace_id
    and profile.profile_key = 'vehicle_photo.default'
    and profile.status = 'active';

  next_generation := target_media.generation + 1;
  next_media_version := target_media.version + 1;

  insert into public.media_processing_runs (
    id, workspace_id, media_id, generation, source_kind, source_id,
    processing_profile_id, profile_snapshot, profile_checksum_sha256
  ) values (
    new_processing_run_id, p_workspace_id, p_media_id, next_generation,
    source_kind, source_id, target_profile.id, target_profile.profile_snapshot,
    target_profile.checksum_sha256
  );

  select queued.outbox_event_id, queued.job_id
    into new_outbox_event_id, new_job_id
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'media.reprocessing_queued',
    p_aggregate_type => 'media_asset',
    p_aggregate_id => p_media_id,
    p_aggregate_version => next_media_version,
    p_job_type => 'media.process_vehicle_photo',
    p_entity_type => 'vehicle_media',
    p_entity_id => p_media_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'processing_run_id', new_processing_run_id,
      'profile_checksum', target_profile.checksum_sha256,
      'source', pg_catalog.jsonb_build_object('kind', source_kind, 'id', source_id)
    ),
    p_idempotency_key => 'media:process:' || new_processing_run_id::text,
    p_correlation_id => p_correlation_id,
    p_actor_user_id => actor_user_id,
    p_priority => 55,
    p_max_attempts => 8,
    p_backoff_base_seconds => 30,
    p_backoff_max_seconds => 3600,
    p_request_id => p_request_id
  ) queued;

  update public.media_processing_runs run
  set outbox_event_id = new_outbox_event_id,
      job_id = new_job_id
  where run.workspace_id = p_workspace_id
    and run.id = new_processing_run_id;

  update public.media_assets asset
  set status = 'quarantined',
      processing_profile_id = target_profile.id,
      generation = next_generation,
      version = next_media_version,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.reprocessing_queued',
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', target_media.version,
      'generation', target_media.generation
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'quarantined',
      'version', next_media_version,
      'generation', next_generation
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'processing_run_id', new_processing_run_id,
      'job_id', new_job_id,
      'source_kind', source_kind,
      'outbox_event_id', new_outbox_event_id
    )
  );

  result_payload := pg_catalog.jsonb_build_object(
    'media_id', p_media_id,
    'processing_run_id', new_processing_run_id,
    'job_id', new_job_id,
    'media_status', 'quarantined',
    'aggregate_version', next_media_version,
    'generation', next_generation,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.reprocess', normalized_idempotency_key,
    request_fingerprint, result_payload, actor_user_id
  );

  return query select
    p_media_id, new_processing_run_id, new_job_id, 'quarantined'::text,
    next_media_version, next_generation, false, new_audit_event_id,
    new_outbox_event_id;
end;
$$;

create or replace function app.reorder_inventory_media_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_expected_collection_version bigint,
  p_ordered_media_ids jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  collection_version bigint,
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
  target_collection public.inventory_media_collections%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  request_fingerprint text;
  next_collection_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_media_permission(p_workspace_id, 'media.update');
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_expected_collection_version is null or p_expected_collection_version < 1
    or p_ordered_media_ids is null
    or pg_catalog.jsonb_typeof(p_ordered_media_ids) <> 'array'
    or pg_catalog.jsonb_array_length(p_ordered_media_ids) not between 1 and 50
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid media reorder command';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_ordered_media_ids) item
    where pg_catalog.jsonb_typeof(item.value) <> 'string'
      or item.value #>> '{}' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  ) then
    raise exception using errcode = '22023', message = 'media order contains invalid identifiers';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'expected_collection_version', p_expected_collection_version,
      'ordered_media_ids', p_ordered_media_ids
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.reorder\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'media.reorder'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505', message = 'media reorder replay conflicts';
    end if;
    return query select
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      (existing_receipt.result ->> 'collection_version')::bigint,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select collection.* into target_collection
  from public.inventory_media_collections collection
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = p_inventory_unit_id
  for update;
  if not found or target_collection.version <> p_expected_collection_version then
    raise exception using errcode = '40001', message = 'stale media collection version';
  end if;

  if (
    select pg_catalog.count(*)
    from public.media_assets asset
    where asset.workspace_id = p_workspace_id
      and asset.inventory_unit_id = p_inventory_unit_id
      and asset.media_kind = 'vehicle_photo'
      and asset.status <> 'archived'
  ) <> pg_catalog.jsonb_array_length(p_ordered_media_ids)
    or (
      select pg_catalog.count(distinct (item.value #>> '{}')::uuid)
      from pg_catalog.jsonb_array_elements(p_ordered_media_ids) item
    ) <> pg_catalog.jsonb_array_length(p_ordered_media_ids)
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_ordered_media_ids) item
      left join public.media_assets asset
        on asset.workspace_id = p_workspace_id
       and asset.inventory_unit_id = p_inventory_unit_id
       and asset.id = (item.value #>> '{}')::uuid
       and asset.media_kind = 'vehicle_photo'
       and asset.status <> 'archived'
      where asset.id is null
    ) then
    raise exception using errcode = '23514', message = 'media order must contain each active photo once';
  end if;

  update public.media_assets asset
  set sort_order = ordered.ordinality::integer - 1,
      updated_at = pg_catalog.statement_timestamp()
  from pg_catalog.jsonb_array_elements(p_ordered_media_ids)
    with ordinality ordered(value, ordinality)
  where asset.workspace_id = p_workspace_id
    and asset.inventory_unit_id = p_inventory_unit_id
    and asset.id = (ordered.value #>> '{}')::uuid;

  update public.inventory_media_collections collection
  set version = collection.version + 1,
      updated_at = pg_catalog.statement_timestamp()
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = p_inventory_unit_id
  returning collection.version into next_collection_version;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, actor_user_id,
    correlation_id
  ) values (
    p_workspace_id, 'media.collection_reordered', 'inventory_media_collection',
    p_inventory_unit_id, next_collection_version, 1,
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'collection_version', next_collection_version,
      'ordered_media_ids', p_ordered_media_ids
    ),
    actor_user_id, p_correlation_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.collection_reordered',
    p_entity_type => 'inventory_media_collection',
    p_entity_id => p_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'collection_version', target_collection.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'collection_version', next_collection_version,
      'ordered_media_ids', p_ordered_media_ids
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('outbox_event_id', new_outbox_event_id)
  );

  result_payload := pg_catalog.jsonb_build_object(
    'inventory_unit_id', p_inventory_unit_id,
    'collection_version', next_collection_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.reorder', normalized_idempotency_key,
    request_fingerprint, result_payload, actor_user_id
  );

  return query select
    p_inventory_unit_id, next_collection_version, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create or replace function app.set_inventory_media_cover_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_inventory_unit_id uuid,
  p_media_id uuid,
  p_expected_collection_version bigint,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  inventory_unit_id uuid,
  cover_media_id uuid,
  collection_version bigint,
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
  target_collection public.inventory_media_collections%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  request_fingerprint text;
  next_collection_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_media_permission(p_workspace_id, 'media.update');
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_expected_collection_version is null or p_expected_collection_version < 1
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid set-cover command';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'media_id', p_media_id,
      'expected_collection_version', p_expected_collection_version
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.set_cover\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'media.set_cover'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505', message = 'set-cover replay conflicts';
    end if;
    return query select
      (existing_receipt.result ->> 'inventory_unit_id')::uuid,
      (existing_receipt.result ->> 'cover_media_id')::uuid,
      (existing_receipt.result ->> 'collection_version')::bigint,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select collection.* into target_collection
  from public.inventory_media_collections collection
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = p_inventory_unit_id
  for update;
  if not found or target_collection.version <> p_expected_collection_version then
    raise exception using errcode = '40001', message = 'stale media collection version';
  end if;
  if not exists (
    select 1 from public.media_assets asset
    where asset.workspace_id = p_workspace_id
      and asset.inventory_unit_id = p_inventory_unit_id
      and asset.id = p_media_id
      and asset.media_kind = 'vehicle_photo'
      and asset.status <> 'archived'
  ) then
    raise exception using errcode = 'P0002', message = 'cover media was not found';
  end if;

  update public.media_assets asset
  set is_cover = false,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id
    and asset.inventory_unit_id = p_inventory_unit_id
    and asset.media_kind = 'vehicle_photo'
    and asset.status <> 'archived'
    and asset.is_cover;
  update public.media_assets asset
  set is_cover = true,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id
    and asset.inventory_unit_id = p_inventory_unit_id
    and asset.id = p_media_id;

  update public.inventory_media_collections collection
  set version = collection.version + 1,
      updated_at = pg_catalog.statement_timestamp()
  where collection.workspace_id = p_workspace_id
    and collection.inventory_unit_id = p_inventory_unit_id
  returning collection.version into next_collection_version;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, actor_user_id,
    correlation_id
  ) values (
    p_workspace_id, 'media.cover_changed', 'inventory_media_collection',
    p_inventory_unit_id, next_collection_version, 1,
    pg_catalog.jsonb_build_object(
      'inventory_unit_id', p_inventory_unit_id,
      'cover_media_id', p_media_id,
      'collection_version', next_collection_version
    ),
    actor_user_id, p_correlation_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.cover_changed',
    p_entity_type => 'inventory_media_collection',
    p_entity_id => p_inventory_unit_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'collection_version', target_collection.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'collection_version', next_collection_version,
      'cover_media_id', p_media_id
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('outbox_event_id', new_outbox_event_id)
  );

  result_payload := pg_catalog.jsonb_build_object(
    'inventory_unit_id', p_inventory_unit_id,
    'cover_media_id', p_media_id,
    'collection_version', next_collection_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.set_cover', normalized_idempotency_key,
    request_fingerprint, result_payload, actor_user_id
  );

  return query select
    p_inventory_unit_id, p_media_id, next_collection_version, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create or replace function app.record_preserved_legal_original_actor_key_impl(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_idempotency_key text,
  p_media_kind text,
  p_owner_entity_type text,
  p_owner_entity_id uuid,
  p_storage_bucket text,
  p_storage_object_key text,
  p_storage_generation text,
  p_mime_type text,
  p_byte_size bigint,
  p_checksum_sha256 text,
  p_verification_receipt jsonb,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  media_file_id uuid,
  media_status text,
  retention_policy text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_checksum text;
  normalized_generation text;
  request_fingerprint text;
  new_media_id uuid := pg_catalog.gen_random_uuid();
  new_file_id uuid := pg_catalog.gen_random_uuid();
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_checksum := pg_catalog.lower(pg_catalog.btrim(coalesce(p_checksum_sha256, '')));
  normalized_generation := pg_catalog.btrim(coalesce(p_storage_generation, ''));
  if p_actor_user_id is null
    or not app.job_actor_has_permission(
      p_workspace_id,
      p_actor_user_id,
      case
        when p_media_kind = 'signed_document' then 'documents.upload_signed'
        else 'media.create'
      end
    ) then
    raise exception using errcode = '42501', message = 'validated legal-file actor is required';
  end if;
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_media_kind not in ('legal_document', 'signed_document')
    or p_owner_entity_type not in ('document', 'deal', 'inventory_unit')
    or (p_media_kind = 'signed_document' and p_owner_entity_type <> 'document')
    or p_owner_entity_id is null
    or p_storage_bucket <> 'media-private'
    or pg_catalog.char_length(p_storage_object_key) not between 1 and 1000
    or p_storage_object_key not like 'workspaces/' || p_workspace_id::text || '/%'
    or normalized_generation = ''
    or pg_catalog.char_length(normalized_generation) > 200
    or p_mime_type not in (
      'application/pdf', 'image/jpeg', 'image/png', 'image/webp',
      'image/heic', 'image/heif'
    )
    or p_byte_size is null or p_byte_size < 1 or p_byte_size > 50000000
    or normalized_checksum !~ '^[a-f0-9]{64}$'
    or p_job_id is null
    or p_worker_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'
    or p_lease_token is null
    or p_attempt_number is null or p_attempt_number < 1
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid preserved legal original';
  end if;

  if p_owner_entity_type = 'document' then
    perform 1
    from public.documents document
    where document.workspace_id = p_workspace_id
      and document.id = p_owner_entity_id
    for key share;
  elsif p_owner_entity_type = 'deal' then
    perform 1
    from public.deals deal
    where deal.workspace_id = p_workspace_id
      and deal.id = p_owner_entity_id
    for key share;
  else
    perform 1
    from public.inventory_units unit
    where unit.workspace_id = p_workspace_id
      and unit.id = p_owner_entity_id
    for key share;
  end if;
  if not found then
    raise exception using errcode = '23514', message = 'preserved legal owner is unavailable';
  end if;

  if p_storage_object_key not like
    'workspaces/' || p_workspace_id::text || '/'
      || (case p_owner_entity_type
        when 'document' then 'documents'
        when 'deal' then 'deals'
        else 'inventory-units'
      end) || '/' || p_owner_entity_id::text || '/%' then
    raise exception using errcode = '22023', message = 'invalid preserved legal original';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.id = p_job_id
  for update;
  if not found
    or target_job.job_type <> 'media.verify_legal_original'
    or target_job.entity_type <> p_owner_entity_type
    or target_job.entity_id <> p_owner_entity_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number
    or target_job.correlation_id <> p_correlation_id then
    raise exception using
      errcode = '55000',
      message = 'only the active legal verification lease can record an original';
  end if;

  if p_verification_receipt is null
    or pg_catalog.jsonb_typeof(p_verification_receipt) <> 'object'
    or app.job_payload_contains_forbidden_key(p_verification_receipt)
    or p_verification_receipt ->> 'schemaVersion' <> '1'
    or p_verification_receipt ->> 'jobId' <> p_job_id::text
    or p_verification_receipt ->> 'workerId' <> p_worker_id
    or p_verification_receipt ->> 'leaseId' <> p_lease_token::text
    or p_verification_receipt ->> 'attempt' <> p_attempt_number::text
    or pg_catalog.btrim(coalesce(p_verification_receipt -> 'verifier' ->> 'name', '')) = ''
    or pg_catalog.btrim(coalesce(p_verification_receipt -> 'verifier' ->> 'version', '')) = ''
    or p_verification_receipt -> 'storage' ->> 'bucket' <> p_storage_bucket
    or p_verification_receipt -> 'storage' ->> 'objectKey' <> p_storage_object_key
    or p_verification_receipt -> 'storage' ->> 'generation' <> normalized_generation
    or p_verification_receipt -> 'storage' ->> 'byteSize' <> p_byte_size::text
    or p_verification_receipt -> 'storage' ->> 'checksumSha256' <> normalized_checksum
    or p_verification_receipt -> 'malwareScan' ->> 'verdict' <> 'clean'
    or p_verification_receipt -> 'malwareScan' ->> 'sourceChecksumSha256' <> normalized_checksum
    or pg_catalog.btrim(coalesce(p_verification_receipt -> 'malwareScan' ->> 'scanner', '')) = ''
    or pg_catalog.btrim(coalesce(p_verification_receipt -> 'malwareScan' ->> 'signatureVersion', '')) = '' then
    raise exception using
      errcode = '23514',
      message = 'legal original verification receipt does not match stored bytes';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'media_kind', p_media_kind,
      'owner_entity_type', p_owner_entity_type,
      'owner_entity_id', p_owner_entity_id,
      'storage_bucket', p_storage_bucket,
      'storage_object_key', p_storage_object_key,
      'storage_generation', normalized_generation,
      'mime_type', p_mime_type,
      'byte_size', p_byte_size,
      'checksum_sha256', normalized_checksum,
      'verification_receipt', p_verification_receipt,
      'job_id', p_job_id,
      'worker_id', p_worker_id,
      'lease_token', p_lease_token,
      'attempt_number', p_attempt_number
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.record_legal\x1f'
        || p_actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = p_actor_user_id
    and receipt.command_type = 'media.record_legal'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint then
      raise exception using errcode = '23505', message = 'legal original replay conflicts';
    end if;
    return query select
      (existing_receipt.result ->> 'media_id')::uuid,
      (existing_receipt.result ->> 'media_file_id')::uuid,
      'ready'::text,
      'preserve_original'::text,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  insert into public.media_assets (
    id, workspace_id, inventory_unit_id, document_id, deal_id,
    owner_entity_type, owner_entity_id, media_kind, status, created_by
  ) values (
    new_media_id,
    p_workspace_id,
    case when p_owner_entity_type = 'inventory_unit' then p_owner_entity_id end,
    case when p_owner_entity_type = 'document' then p_owner_entity_id end,
    case when p_owner_entity_type = 'deal' then p_owner_entity_id end,
    p_owner_entity_type,
    p_owner_entity_id,
    p_media_kind,
    'ready',
    p_actor_user_id
  );
  insert into public.media_files (
    id, workspace_id, media_id, file_class, variant, storage_bucket,
    storage_object_key, storage_generation, mime_type, byte_size, checksum_sha256,
    metadata_stripped, retention_policy, verification_receipt
  ) values (
    new_file_id, p_workspace_id, new_media_id, 'legal_document_original',
    'legal_original', p_storage_bucket, p_storage_object_key, normalized_generation,
    p_mime_type, p_byte_size, normalized_checksum, false, 'preserve_original',
    p_verification_receipt
  );

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, actor_user_id,
    correlation_id, causation_id
  ) values (
    p_workspace_id, 'media.legal_original_recorded', 'media_asset',
    new_media_id, 1, 1,
    pg_catalog.jsonb_build_object(
      'media_id', new_media_id,
      'media_file_id', new_file_id,
      'media_kind', p_media_kind,
      'owner_entity_type', p_owner_entity_type,
      'owner_entity_id', p_owner_entity_id,
      'retention_policy', 'preserve_original'
    ),
    p_actor_user_id, p_correlation_id, target_job.outbox_event_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.legal_original_recorded',
    p_entity_type => 'media_asset',
    p_entity_id => new_media_id,
    p_actor_user_id => p_actor_user_id,
    p_actor_type => 'worker',
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'ready',
      'media_kind', p_media_kind,
      'retention_policy', 'preserve_original'
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'media_file_id', new_file_id,
      'worker_id', p_worker_id,
      'job_id', p_job_id,
      'storage_generation', normalized_generation,
      'outbox_event_id', new_outbox_event_id
    )
  );

  result_payload := pg_catalog.jsonb_build_object(
    'media_id', new_media_id,
    'media_file_id', new_file_id,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.record_legal', normalized_idempotency_key,
    request_fingerprint, result_payload, p_actor_user_id
  );

  return query select
    new_media_id, new_file_id, 'ready'::text, 'preserve_original'::text,
    false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create or replace function app.set_managed_media_retention_hold_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_file_id uuid,
  p_expected_retention_version bigint,
  p_hold boolean,
  p_hold_kind text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_file_id uuid,
  retention_hold boolean,
  retention_version bigint,
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
  target_file public.media_files%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  normalized_reason text;
  request_fingerprint text;
  current_kind_held boolean := false;
  next_overall_hold boolean;
  next_retention_version bigint;
  new_hold_event_id uuid := pg_catalog.gen_random_uuid();
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    'media.archive',
    true
  );
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_media_file_id is null
    or p_expected_retention_version is null or p_expected_retention_version < 1
    or p_hold is null
    or p_hold_kind not in ('legal', 'incident')
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid media retention hold command';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'actor_user_id', actor_user_id,
      'media_file_id', p_media_file_id,
      'expected_retention_version', p_expected_retention_version,
      'hold', p_hold,
      'hold_kind', p_hold_kind,
      'reason', normalized_reason
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.retention_hold\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'media.retention_hold'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint
      or existing_receipt.actor_user_id <> actor_user_id then
      raise exception using errcode = '23505', message = 'retention hold replay conflicts';
    end if;
    return query select
      (existing_receipt.result ->> 'media_file_id')::uuid,
      (existing_receipt.result ->> 'retention_hold')::boolean,
      (existing_receipt.result ->> 'retention_version')::bigint,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select file.* into target_file
  from public.media_files file
  where file.workspace_id = p_workspace_id
    and file.id = p_media_file_id
  for update;
  if not found or target_file.deleted_at is not null then
    raise exception using errcode = 'P0002', message = 'managed media file was not found';
  end if;
  if target_file.retention_delete_job_id is not null then
    raise exception using
      errcode = '55000',
      message = 'media retention deletion is already in progress';
  end if;
  if p_hold_kind = 'legal' and target_file.file_class <> 'legal_document_original' then
    raise exception using errcode = '23514', message = 'legal hold requires a preserved legal original';
  end if;
  if target_file.retention_version <> p_expected_retention_version then
    raise exception using errcode = '40001', message = 'media retention version conflict';
  end if;

  select coalesce(latest.action = 'held', false)
    into current_kind_held
  from (
    select event.action
    from public.media_retention_hold_events event
    where event.workspace_id = p_workspace_id
      and event.media_file_id = p_media_file_id
      and event.hold_kind = p_hold_kind
    order by event.retention_version desc
    limit 1
  ) latest;
  current_kind_held := coalesce(current_kind_held, false);
  if current_kind_held = p_hold then
    raise exception using errcode = '23514', message = 'media retention hold state is unchanged';
  end if;

  next_retention_version := target_file.retention_version + 1;
  if p_hold then
    next_overall_hold := true;
  else
    select exists (
      select 1
      from (
        select distinct on (event.hold_kind)
          event.hold_kind,
          event.action
        from public.media_retention_hold_events event
        where event.workspace_id = p_workspace_id
          and event.media_file_id = p_media_file_id
          and event.hold_kind <> p_hold_kind
        order by event.hold_kind, event.retention_version desc
      ) latest
      where latest.action = 'held'
    ) into next_overall_hold;
  end if;

  update public.media_files file
  set retention_hold = next_overall_hold,
      retention_version = next_retention_version
  where file.workspace_id = p_workspace_id
    and file.id = p_media_file_id;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, actor_user_id,
    correlation_id
  ) values (
    p_workspace_id,
    case when p_hold then 'media.retention_held' else 'media.retention_released' end,
    'media_file',
    p_media_file_id,
    next_retention_version,
    1,
    pg_catalog.jsonb_build_object(
      'media_file_id', p_media_file_id,
      'hold_kind', p_hold_kind,
      'retention_hold', next_overall_hold,
      'retention_version', next_retention_version
    ),
    actor_user_id,
    p_correlation_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => case
      when p_hold then 'media.retention_held' else 'media.retention_released'
    end,
    p_entity_type => 'media_file',
    p_entity_id => p_media_file_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'retention_hold', target_file.retention_hold,
      'retention_version', target_file.retention_version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'retention_hold', next_overall_hold,
      'retention_version', next_retention_version,
      'hold_kind', p_hold_kind
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'retention_hold_event_id', new_hold_event_id,
      'outbox_event_id', new_outbox_event_id
    )
  );

  insert into public.media_retention_hold_events (
    id, workspace_id, media_file_id, hold_kind, action, retention_version,
    reason, actor_user_id, audit_event_id, outbox_event_id, request_id,
    correlation_id
  ) values (
    new_hold_event_id, p_workspace_id, p_media_file_id, p_hold_kind,
    case when p_hold then 'held' else 'released' end,
    next_retention_version, normalized_reason, actor_user_id,
    new_audit_event_id, new_outbox_event_id, p_request_id, p_correlation_id
  );

  result_payload := pg_catalog.jsonb_build_object(
    'media_file_id', p_media_file_id,
    'retention_hold', next_overall_hold,
    'retention_version', next_retention_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', new_outbox_event_id
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.retention_hold', normalized_idempotency_key,
    request_fingerprint, result_payload, actor_user_id
  );

  return query select
    p_media_file_id, next_overall_hold, next_retention_version, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create or replace function app.request_vehicle_photo_upload_verification_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_upload_session_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  upload_session_id uuid,
  job_id uuid,
  job_status text,
  aggregate_version bigint,
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
  target_upload public.media_upload_sessions%rowtype;
  previous_job public.jobs%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  queued record;
  normalized_idempotency_key text;
  request_fingerprint text;
  next_media_version bigint;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_media_permission(p_workspace_id, 'media.create');
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));

  if pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_media_id is null
    or p_upload_session_id is null
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using
      errcode = '22023',
      message = 'invalid media upload verification request';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'upload_session_id', p_upload_session_id
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.request_upload_verification\x1f'
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'media.request_upload_verification'
    and receipt.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'media verification idempotency replay conflicts';
    end if;
    return query select
      (existing_receipt.result ->> 'media_id')::uuid,
      (existing_receipt.result ->> 'upload_session_id')::uuid,
      (existing_receipt.result ->> 'job_id')::uuid,
      coalesce(
        (
          select job.status
          from public.jobs job
          where job.workspace_id = p_workspace_id
            and job.id = (existing_receipt.result ->> 'job_id')::uuid
        ),
        existing_receipt.result ->> 'job_status'
      ),
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      (existing_receipt.result ->> 'outbox_event_id')::uuid;
    return;
  end if;

  select upload.* into target_upload
  from public.media_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id
    and upload.media_id = p_media_id
  for update;

  if not found or target_upload.created_by <> actor_user_id then
    raise exception using errcode = '42501', message = 'media upload intent is not owned by the actor';
  end if;

  if target_upload.verification_job_id is not null then
    select job.* into previous_job
    from public.jobs job
    where job.workspace_id = p_workspace_id
      and job.id = target_upload.verification_job_id;

    if found and previous_job.status in ('queued', 'running', 'retry_wait', 'succeeded') then
      result_payload := pg_catalog.jsonb_build_object(
        'media_id', p_media_id,
        'upload_session_id', p_upload_session_id,
        'job_id', previous_job.id,
        'job_status', previous_job.status,
        'aggregate_version', (
          select asset.version
          from public.media_assets asset
          where asset.workspace_id = p_workspace_id and asset.id = p_media_id
        ),
        'audit_event_id', target_upload.verification_audit_event_id,
        'outbox_event_id', target_upload.verification_outbox_event_id
      );
      insert into public.media_command_receipts (
        workspace_id, command_type, idempotency_key, request_fingerprint,
        result, actor_user_id
      ) values (
        p_workspace_id, 'media.request_upload_verification',
        normalized_idempotency_key, request_fingerprint, result_payload,
        actor_user_id
      );
      return query select
        p_media_id, p_upload_session_id, previous_job.id, previous_job.status,
        (result_payload ->> 'aggregate_version')::bigint, true,
        target_upload.verification_audit_event_id,
        target_upload.verification_outbox_event_id;
      return;
    end if;
  end if;

  if target_upload.status <> 'awaiting_upload'
    or target_upload.expires_at <= pg_catalog.statement_timestamp() then
    raise exception using errcode = '55000', message = 'media upload session is unavailable';
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo'
  for update;

  if not found or target_media.status <> 'awaiting_upload' then
    raise exception using errcode = '55000', message = 'media is not awaiting upload verification';
  end if;

  next_media_version := target_media.version + 1;
  select result.* into queued
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'media.upload_verification_queued',
    p_aggregate_type => 'media_asset',
    p_aggregate_id => p_media_id,
    p_aggregate_version => next_media_version,
    p_job_type => 'media.verify_vehicle_photo_upload',
    p_entity_type => 'media_upload_session',
    p_entity_id => p_upload_session_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'upload_session_id', p_upload_session_id
    ),
    p_idempotency_key => 'media:verify:' || p_upload_session_id::text || ':'
      || pg_catalog.substr(app.job_request_fingerprint(
        pg_catalog.to_jsonb(normalized_idempotency_key)
      ), 1, 24),
    p_correlation_id => p_correlation_id,
    p_actor_user_id => actor_user_id,
    p_priority => 65,
    p_max_attempts => 6,
    p_backoff_base_seconds => 15,
    p_backoff_max_seconds => 900,
    p_replay_of_job_id => case
      when previous_job.status = 'dead_letter' then previous_job.id
      else null
    end,
    p_request_id => p_request_id
  ) result;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.upload_verification_queued',
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', target_media.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', next_media_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'upload_session_id', p_upload_session_id,
      'job_id', queued.job_id,
      'outbox_event_id', queued.outbox_event_id
    )
  );

  update public.media_assets asset
  set version = next_media_version,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id and asset.id = p_media_id;

  update public.media_upload_sessions upload
  set verification_job_id = queued.job_id,
      verification_outbox_event_id = queued.outbox_event_id,
      verification_audit_event_id = new_audit_event_id,
      verification_requested_at = pg_catalog.statement_timestamp()
  where upload.workspace_id = p_workspace_id and upload.id = p_upload_session_id;

  result_payload := pg_catalog.jsonb_build_object(
    'media_id', p_media_id,
    'upload_session_id', p_upload_session_id,
    'job_id', queued.job_id,
    'job_status', queued.job_status,
    'aggregate_version', next_media_version,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', queued.outbox_event_id
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.request_upload_verification',
    normalized_idempotency_key, request_fingerprint, result_payload,
    actor_user_id
  );

  return query select
    p_media_id, p_upload_session_id, queued.job_id, queued.job_status,
    next_media_version, false, new_audit_event_id, queued.outbox_event_id;
end;
$$;

create or replace function app.create_legal_original_upload_session_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_document_id uuid,
  p_media_kind text,
  p_original_filename text,
  p_expected_mime_type text,
  p_expected_byte_size bigint,
  p_expected_checksum_sha256 text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  upload_session_id uuid,
  document_id uuid,
  media_kind text,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  replayed boolean,
  audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_filename text := pg_catalog.btrim(coalesce(p_original_filename, ''));
  normalized_mime text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_expected_mime_type, '')));
  normalized_checksum text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_expected_checksum_sha256, '')));
  fingerprint text;
  existing public.media_command_receipts%rowtype;
  new_id uuid := pg_catalog.gen_random_uuid();
  new_key text;
  new_expiry timestamptz := pg_catalog.statement_timestamp() + interval '15 minutes';
  new_audit uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    case when p_media_kind = 'signed_document'
      then 'documents.upload_signed' else 'media.create' end,
    p_media_kind = 'signed_document'
  );
  if pg_catalog.char_length(normalized_key) not between 8 and 200
    or p_document_id is null
    or p_media_kind not in ('legal_document', 'signed_document')
    or pg_catalog.char_length(normalized_filename) not between 1 and 255
    or normalized_filename ~ '[[:cntrl:]]'
    or normalized_mime not in (
      'application/pdf', 'image/jpeg', 'image/png', 'image/webp',
      'image/heic', 'image/heif'
    )
    or p_expected_byte_size is null or p_expected_byte_size not between 1 and 50000000
    or normalized_checksum !~ '^[a-f0-9]{64}$'
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid legal original upload intent';
  end if;
  perform 1 from public.documents document
  where document.workspace_id = p_workspace_id and document.id = p_document_id
  for key share;
  if not found then
    raise exception using errcode = 'P0002', message = 'document was not found';
  end if;
  fingerprint := app.job_request_fingerprint(pg_catalog.jsonb_build_object(
    'document_id', p_document_id, 'media_kind', p_media_kind,
    'original_filename', normalized_filename, 'expected_mime_type', normalized_mime,
    'expected_byte_size', p_expected_byte_size,
    'expected_checksum_sha256', normalized_checksum
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fmedia.create_legal_original_upload\x1f'
      || actor_user_id::text || E'\x1f' || normalized_key, 0));
  select receipt.* into existing from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'media.create_legal_upload'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing.actor_user_id is distinct from actor_user_id
      or existing.request_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'legal upload intent replay conflicts';
    end if;
    return query select
      (existing.result ->> 'upload_session_id')::uuid,
      (existing.result ->> 'document_id')::uuid,
      existing.result ->> 'media_kind', existing.result ->> 'upload_bucket',
      existing.result ->> 'upload_object_key',
      (existing.result ->> 'expires_at')::timestamptz, true,
      (existing.result ->> 'audit_event_id')::uuid;
    return;
  end if;
  new_key := 'workspaces/' || p_workspace_id::text || '/documents/'
    || p_document_id::text || '/upload-intents/' || new_id::text || '/source';
  insert into public.legal_original_upload_sessions (
    id, workspace_id, document_id, media_kind, original_filename,
    expected_mime_type, expected_byte_size, expected_checksum_sha256,
    upload_object_key, expires_at, created_by
  ) values (
    new_id, p_workspace_id, p_document_id, p_media_kind, normalized_filename,
    normalized_mime, p_expected_byte_size, normalized_checksum,
    new_key, new_expiry, actor_user_id
  );
  new_audit := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.legal_upload_intent_created',
    p_entity_type => 'legal_original_upload_session',
    p_entity_id => new_id,
    p_actor_type => 'user', p_actor_user_id => actor_user_id,
    p_after_data => pg_catalog.jsonb_build_object(
      'document_id', p_document_id, 'media_kind', p_media_kind,
      'status', 'awaiting_upload', 'expected_byte_size', p_expected_byte_size,
      'expected_mime_type', normalized_mime, 'expires_at', new_expiry),
    p_request_id => p_request_id, p_correlation_id => p_correlation_id,
    p_auth_assurance => case when p_media_kind = 'signed_document' then 'step_up' else 'session' end
  );
  result_payload := pg_catalog.jsonb_build_object(
    'upload_session_id', new_id, 'document_id', p_document_id,
    'media_kind', p_media_kind, 'upload_bucket', 'media-private',
    'upload_object_key', new_key, 'expires_at', new_expiry,
    'audit_event_id', new_audit);
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint, result, actor_user_id
  ) values (
    p_workspace_id, 'media.create_legal_upload', normalized_key,
    fingerprint, result_payload, actor_user_id);
  return query select new_id, p_document_id, p_media_kind, 'media-private'::text,
    new_key, new_expiry, false, new_audit;
end;
$$;

create or replace function app.request_legal_original_upload_verification_actor_key_impl(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_document_id uuid,
  p_upload_session_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  upload_session_id uuid,
  document_id uuid,
  job_id uuid,
  job_status text,
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
  target public.legal_original_upload_sessions%rowtype;
  normalized_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  fingerprint text;
  existing public.media_command_receipts%rowtype;
  queued record;
  new_audit uuid;
  result_payload jsonb;
begin
  select upload.* into target from public.legal_original_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id
    and upload.document_id = p_document_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'legal upload intent was not found'; end if;
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    case when target.media_kind = 'signed_document'
      then 'documents.upload_signed' else 'media.create' end,
    target.media_kind = 'signed_document'
  );
  if target.created_by <> actor_user_id then
    raise exception using errcode = '42501', message = 'legal upload intent is not owned by the actor';
  end if;
  if pg_catalog.char_length(normalized_key) not between 8 and 200
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid legal verification request';
  end if;
  fingerprint := app.job_request_fingerprint(pg_catalog.jsonb_build_object(
    'document_id', p_document_id, 'upload_session_id', p_upload_session_id));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fmedia.request_legal_verification\x1f'
      || actor_user_id::text || E'\x1f' || normalized_key, 0));
  select receipt.* into existing from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'media.request_legal_verify'
    and receipt.idempotency_key = normalized_key;
  if found then
    if existing.actor_user_id is distinct from actor_user_id
      or existing.request_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'legal verification replay conflicts';
    end if;
    return query select
      (existing.result ->> 'upload_session_id')::uuid,
      (existing.result ->> 'document_id')::uuid,
      (existing.result ->> 'job_id')::uuid,
      coalesce((select job.status from public.jobs job
        where job.workspace_id = p_workspace_id
          and job.id = (existing.result ->> 'job_id')::uuid),
        existing.result ->> 'job_status'),
      true, (existing.result ->> 'audit_event_id')::uuid,
      (existing.result ->> 'outbox_event_id')::uuid;
    return;
  end if;
  if target.status <> 'awaiting_upload'
    or target.expires_at <= pg_catalog.statement_timestamp() then
    raise exception using errcode = '55000', message = 'legal upload intent is unavailable';
  end if;
  select result.* into queued from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'media.legal_original_verification_queued',
    p_aggregate_type => 'legal_original_upload_session',
    p_aggregate_id => p_upload_session_id,
    p_aggregate_version => 1,
    p_job_type => 'media.verify_legal_original',
    p_entity_type => 'document', p_entity_id => p_document_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object('upload_session_id', p_upload_session_id),
    p_idempotency_key => 'media:verify-legal:' || p_upload_session_id::text,
    p_correlation_id => p_correlation_id, p_actor_user_id => actor_user_id,
    p_priority => 35, p_max_attempts => 6,
    p_backoff_base_seconds => 30, p_backoff_max_seconds => 1800,
    p_request_id => p_request_id
  ) result;
  new_audit := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.legal_original_verification_queued',
    p_entity_type => 'legal_original_upload_session', p_entity_id => p_upload_session_id,
    p_actor_type => 'user', p_actor_user_id => actor_user_id,
    p_before_data => pg_catalog.jsonb_build_object('status', target.status),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'verification_requested', 'job_id', queued.job_id,
      'outbox_event_id', queued.outbox_event_id),
    p_request_id => p_request_id, p_correlation_id => p_correlation_id,
    p_auth_assurance => case when target.media_kind = 'signed_document' then 'step_up' else 'session' end
  );
  update public.legal_original_upload_sessions upload set
    status = 'verification_requested', verification_job_id = queued.job_id,
    verification_outbox_event_id = queued.outbox_event_id,
    verification_audit_event_id = new_audit,
    verification_requested_at = pg_catalog.statement_timestamp()
  where upload.workspace_id = p_workspace_id and upload.id = p_upload_session_id;
  result_payload := pg_catalog.jsonb_build_object(
    'upload_session_id', p_upload_session_id, 'document_id', p_document_id,
    'job_id', queued.job_id, 'job_status', queued.job_status,
    'audit_event_id', new_audit, 'outbox_event_id', queued.outbox_event_id);
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint, result, actor_user_id
  ) values (
    p_workspace_id, 'media.request_legal_verify', normalized_key,
    fingerprint, result_payload, actor_user_id);
  return query select p_upload_session_id, p_document_id, queued.job_id,
    queued.job_status, false, new_audit, queued.outbox_event_id;
end;
$$;

create or replace function app.update_vehicle_media_caption_actor_key_impl(
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
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
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

create or replace function app.archive_vehicle_media_actor_key_impl(
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
        || actor_user_id::text || E'\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
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

-- END GENERATED ACTOR-AWARE IMPLEMENTATIONS
