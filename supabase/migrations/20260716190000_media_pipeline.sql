-- VYN-MEDIA-001, VYN-STOR-001, VYN-JOB-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-API-001, T-MED-001 through T-MED-005, T-STOR-001
-- M2-MEDIA-AC-001 through M2-MEDIA-AC-013
-- Forward-only private media pipeline, managed-storage provenance, and retention.

create unique index audit_events_workspace_id_uidx
  on public.audit_events (workspace_id, id);

create table public.media_processing_profiles (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  profile_key extensions.citext not null check (
    profile_key::text ~ '^[a-z][a-z0-9_.-]{2,119}$'
  ),
  version integer not null check (version > 0),
  profile_snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(profile_snapshot) = 'object'
    and not app.job_payload_contains_forbidden_key(profile_snapshot)
  ),
  checksum_sha256 text not null check (checksum_sha256 ~ '^[a-f0-9]{64}$'),
  status text not null default 'draft' check (status in ('draft', 'active', 'retired')),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  activated_at timestamptz,
  retired_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, profile_key, version),
  check (
    (status = 'draft' and activated_at is null and retired_at is null)
    or (status = 'active' and activated_at is not null and retired_at is null)
    or (status = 'retired' and activated_at is not null and retired_at is not null)
  )
);

create unique index media_processing_profiles_active_key_uidx
  on public.media_processing_profiles (workspace_id, profile_key)
  where status = 'active';

create table public.inventory_media_collections (
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  inventory_unit_id uuid not null,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  primary key (workspace_id, inventory_unit_id),
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id) on delete restrict
);

create table public.media_assets (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  inventory_unit_id uuid,
  document_id uuid,
  deal_id uuid,
  owner_entity_type text not null check (
    owner_entity_type ~ '^[a-z][a-z0-9_]*$'
  ),
  owner_entity_id uuid not null,
  media_kind text not null check (
    media_kind in ('vehicle_photo', 'legal_document', 'signed_document', 'attachment')
  ),
  status text not null default 'awaiting_upload' check (
    status in ('awaiting_upload', 'quarantined', 'processing', 'ready', 'failed', 'archived')
  ),
  caption text check (
    caption is null or pg_catalog.char_length(caption) between 1 and 500
  ),
  sort_order integer check (sort_order is null or sort_order >= 0),
  is_cover boolean not null default false,
  processing_profile_id uuid,
  generation integer not null default 1 check (generation > 0),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  archived_at timestamptz,
  unique (workspace_id, id),
  foreign key (workspace_id, inventory_unit_id)
    references public.inventory_units (workspace_id, id) on delete restrict,
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, processing_profile_id)
    references public.media_processing_profiles (workspace_id, id) on delete restrict,
  constraint media_assets_owner_shape_check check (pg_catalog.coalesce((
    (
      media_kind = 'vehicle_photo'
      and inventory_unit_id is not null
      and owner_entity_type = 'inventory_unit'
      and owner_entity_id = inventory_unit_id
      and document_id is null
      and deal_id is null
      and sort_order is not null
      and processing_profile_id is not null
    )
    or (
      media_kind = 'legal_document'
      and (
        (
          owner_entity_type = 'document'
          and owner_entity_id = document_id
          and inventory_unit_id is null
          and deal_id is null
        )
        or (
          owner_entity_type = 'deal'
          and owner_entity_id = deal_id
          and inventory_unit_id is null
          and document_id is null
        )
        or (
          owner_entity_type = 'inventory_unit'
          and owner_entity_id = inventory_unit_id
          and document_id is null
          and deal_id is null
        )
      )
      and sort_order is null
      and is_cover is false
      and processing_profile_id is null
    )
    or (
      media_kind = 'signed_document'
      and owner_entity_type = 'document'
      and owner_entity_id = document_id
      and inventory_unit_id is null
      and deal_id is null
      and sort_order is null
      and is_cover is false
      and processing_profile_id is null
    )
    or (
      media_kind = 'attachment'
      and inventory_unit_id is null
      and document_id is null
      and deal_id is null
      and sort_order is null
      and is_cover is false
      and processing_profile_id is null
    )
  ), false)),
  constraint media_assets_archive_shape_check check (
    (status = 'archived' and archived_at is not null and is_cover is false)
    or (status <> 'archived' and archived_at is null)
  )
);

create index media_assets_inventory_order_idx
  on public.media_assets (workspace_id, inventory_unit_id, sort_order, id)
  where media_kind = 'vehicle_photo' and status <> 'archived';
create unique index media_assets_inventory_cover_uidx
  on public.media_assets (workspace_id, inventory_unit_id)
  where media_kind = 'vehicle_photo' and status <> 'archived' and is_cover;
create index media_assets_owner_idx
  on public.media_assets (workspace_id, owner_entity_type, owner_entity_id, created_at desc);

create table public.media_upload_sessions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  media_id uuid not null,
  original_filename text not null check (
    pg_catalog.char_length(original_filename) between 1 and 255
    and original_filename !~ '[[:cntrl:]]'
  ),
  expected_mime_type text not null check (
    expected_mime_type in ('image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif')
  ),
  expected_byte_size bigint not null check (expected_byte_size between 1 and 20000000),
  expected_checksum_sha256 text not null
    check (expected_checksum_sha256 ~ '^[a-f0-9]{64}$'),
  quarantine_bucket text not null check (
    quarantine_bucket ~ '^[a-z0-9][a-z0-9_-]{2,62}$'
  ),
  quarantine_object_key text not null check (
    pg_catalog.char_length(quarantine_object_key) between 1 and 1000
  ),
  status text not null default 'awaiting_upload' check (
    status in ('awaiting_upload', 'completed', 'expired')
  ),
  expires_at timestamptz not null,
  completed_at timestamptz,
  observed_mime_type text,
  observed_byte_size bigint,
  observed_checksum_sha256 text,
  width integer,
  height integer,
  exif_orientation smallint,
  malware_scan_receipt jsonb,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, media_id),
  unique (quarantine_bucket, quarantine_object_key),
  foreign key (workspace_id, media_id)
    references public.media_assets (workspace_id, id) on delete restrict,
  constraint media_upload_sessions_path_check check (
    quarantine_object_key = 'workspaces/' || workspace_id::text
      || '/uploads/' || id::text || '/source'
  ),
  constraint media_upload_sessions_completion_shape_check check (
    (
      status = 'awaiting_upload'
      and completed_at is null
      and observed_mime_type is null
      and observed_byte_size is null
      and observed_checksum_sha256 is null
      and width is null and height is null and exif_orientation is null
      and malware_scan_receipt is null
    )
    or (
      status = 'completed'
      and completed_at is not null
      and observed_mime_type = expected_mime_type
      and observed_byte_size = expected_byte_size
      and observed_checksum_sha256 ~ '^[a-f0-9]{64}$'
      and width > 0 and height > 0
      and width::bigint * height::bigint <= 60000000
      and (exif_orientation is null or exif_orientation between 1 and 8)
      and pg_catalog.jsonb_typeof(malware_scan_receipt) = 'object'
      and malware_scan_receipt ->> 'verdict' = 'clean'
    )
    or (
      status = 'expired'
      and completed_at is null
      and observed_mime_type is null
      and observed_byte_size is null
      and observed_checksum_sha256 is null
      and width is null and height is null and exif_orientation is null
      and malware_scan_receipt is null
    )
  )
);

create index media_upload_sessions_expiry_idx
  on public.media_upload_sessions (expires_at, id)
  where status = 'awaiting_upload';

create table public.media_processing_runs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  media_id uuid not null,
  generation integer not null check (generation > 0),
  source_kind text not null check (source_kind in ('upload_session', 'media_file')),
  source_id uuid not null,
  processing_profile_id uuid not null,
  profile_snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(profile_snapshot) = 'object'
    and not app.job_payload_contains_forbidden_key(profile_snapshot)
  ),
  profile_checksum_sha256 text not null check (profile_checksum_sha256 ~ '^[a-f0-9]{64}$'),
  outbox_event_id uuid,
  job_id uuid,
  status text not null default 'queued' check (
    status in ('queued', 'processing', 'succeeded', 'failed')
  ),
  terminal_receipt_checksum_sha256 text check (
    terminal_receipt_checksum_sha256 is null
    or terminal_receipt_checksum_sha256 ~ '^[a-f0-9]{64}$'
  ),
  started_at timestamptz,
  completed_at timestamptz,
  last_error_classification text,
  last_error_code text check (
    last_error_code is null or pg_catalog.char_length(last_error_code) <= 120
  ),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, media_id, generation),
  unique (workspace_id, outbox_event_id),
  unique (workspace_id, job_id),
  foreign key (workspace_id, media_id)
    references public.media_assets (workspace_id, id) on delete restrict,
  foreign key (workspace_id, processing_profile_id)
    references public.media_processing_profiles (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  constraint media_processing_runs_job_shape_check check (
    (outbox_event_id is null and job_id is null)
    or (outbox_event_id is not null and job_id is not null)
  ),
  constraint media_processing_runs_terminal_shape_check check (
    (
      status = 'queued'
      and started_at is null and completed_at is null
      and terminal_receipt_checksum_sha256 is null
      and last_error_classification is null and last_error_code is null
    )
    or (
      status = 'processing'
      and started_at is not null and completed_at is null
      and terminal_receipt_checksum_sha256 is null
    )
    or (
      status = 'succeeded'
      and started_at is not null and completed_at is not null
      and terminal_receipt_checksum_sha256 is not null
      and last_error_classification is null and last_error_code is null
    )
    or (
      status = 'failed'
      and started_at is not null and completed_at is not null
      and terminal_receipt_checksum_sha256 is null
      and last_error_classification is not null and last_error_code is not null
    )
  )
);

create index media_processing_runs_state_idx
  on public.media_processing_runs (workspace_id, status, created_at, id);

create table public.media_processing_completions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  media_id uuid not null,
  processing_run_id uuid not null,
  job_id uuid not null,
  worker_id text not null check (
    pg_catalog.char_length(worker_id) between 1 and 200
    and worker_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
  ),
  lease_token uuid not null,
  attempt_number integer not null check (attempt_number > 0),
  receipt_schema_version integer not null check (receipt_schema_version > 0),
  receipt jsonb not null check (
    pg_catalog.jsonb_typeof(receipt) = 'object'
    and not app.job_payload_contains_forbidden_key(receipt)
  ),
  receipt_checksum_sha256 text not null check (
    receipt_checksum_sha256 ~ '^[a-f0-9]{64}$'
  ),
  completed_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, processing_run_id),
  foreign key (workspace_id, media_id)
    references public.media_assets (workspace_id, id) on delete restrict,
  foreign key (workspace_id, processing_run_id)
    references public.media_processing_runs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict
);

create table public.media_files (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  media_id uuid not null,
  processing_run_id uuid,
  file_class text not null check (
    file_class in ('vehicle_photo_raw', 'vehicle_photo_derivative', 'legal_document_original', 'document_preview')
  ),
  variant text not null check (
    variant in ('raw_original', 'normalized_master', 'website_1080', 'thumbnail_640', 'thumbnail_320', 'legal_original', 'preview')
  ),
  storage_bucket text not null check (
    storage_bucket ~ '^[a-z0-9][a-z0-9_-]{2,62}$'
  ),
  storage_object_key text not null check (
    pg_catalog.char_length(storage_object_key) between 1 and 1000
  ),
  storage_generation text check (
    storage_generation is null or (
      pg_catalog.btrim(storage_generation) <> ''
      and pg_catalog.char_length(storage_generation) <= 200
    )
  ),
  mime_type text not null check (pg_catalog.char_length(mime_type) between 3 and 120),
  byte_size bigint not null check (byte_size > 0),
  checksum_sha256 text not null check (checksum_sha256 ~ '^[a-f0-9]{64}$'),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  metadata_stripped boolean not null default false,
  retention_policy text not null check (
    retention_policy in ('delete_after_verified_master', 'preserve_original', 'retain_until_archive')
  ),
  delete_after timestamptz,
  retention_hold boolean not null default false,
  retention_version bigint not null default 1 check (retention_version > 0),
  verification_receipt jsonb check (
    verification_receipt is null
    or (
      pg_catalog.jsonb_typeof(verification_receipt) = 'object'
      and not app.job_payload_contains_forbidden_key(verification_receipt)
    )
  ),
  retention_delete_job_id uuid,
  retention_delete_lease_token uuid,
  retention_delete_attempt_number integer check (
    retention_delete_attempt_number is null or retention_delete_attempt_number > 0
  ),
  retention_delete_started_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (storage_bucket, storage_object_key),
  unique (workspace_id, media_id, processing_run_id, variant),
  foreign key (workspace_id, media_id)
    references public.media_assets (workspace_id, id) on delete restrict,
  foreign key (workspace_id, processing_run_id)
    references public.media_processing_runs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, retention_delete_job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  constraint media_files_dimension_pair_check check ((width is null) = (height is null)),
  constraint media_files_retention_shape_check check (pg_catalog.coalesce((
    (
      file_class = 'vehicle_photo_raw'
      and variant = 'raw_original'
      and retention_policy = 'delete_after_verified_master'
      and delete_after is not null
      and metadata_stripped is false
    )
    or (
      file_class = 'vehicle_photo_derivative'
      and variant in ('normalized_master', 'website_1080', 'thumbnail_640', 'thumbnail_320')
      and retention_policy = 'retain_until_archive'
      and delete_after is null
      and metadata_stripped
      and mime_type = 'image/webp'
      and width is not null and height is not null
    )
    or (
      file_class = 'legal_document_original'
      and variant = 'legal_original'
      and retention_policy = 'preserve_original'
      and delete_after is null
      and deleted_at is null
      and metadata_stripped is false
      and storage_bucket = 'media-private'
      and storage_generation is not null
      and verification_receipt ->> 'schemaVersion' = '1'
      and pg_catalog.btrim(verification_receipt -> 'verifier' ->> 'name') <> ''
      and pg_catalog.btrim(verification_receipt -> 'verifier' ->> 'version') <> ''
      and verification_receipt -> 'storage' ->> 'bucket' = storage_bucket
      and verification_receipt -> 'storage' ->> 'objectKey' = storage_object_key
      and verification_receipt -> 'storage' ->> 'generation' = storage_generation
      and verification_receipt -> 'storage' ->> 'byteSize' = byte_size::text
      and verification_receipt -> 'storage' ->> 'checksumSha256' = checksum_sha256
      and verification_receipt -> 'malwareScan' ->> 'verdict' = 'clean'
      and verification_receipt -> 'malwareScan' ->> 'sourceChecksumSha256' = checksum_sha256
      and pg_catalog.btrim(verification_receipt -> 'malwareScan' ->> 'scanner') <> ''
      and pg_catalog.btrim(verification_receipt -> 'malwareScan' ->> 'signatureVersion') <> ''
    )
    or (
      file_class = 'document_preview'
      and variant = 'preview'
      and retention_policy = 'retain_until_archive'
      and delete_after is null
    )
  ), false)),
  constraint media_files_deleted_shape_check check (
    deleted_at is null
    or (
      file_class = 'vehicle_photo_raw'
      and retention_policy = 'delete_after_verified_master'
      and not retention_hold
      and deleted_at >= delete_after
    )
  ),
  constraint media_files_retention_delete_fence_check check (
    (
      retention_delete_job_id is null
      and retention_delete_lease_token is null
      and retention_delete_attempt_number is null
      and retention_delete_started_at is null
    )
    or (
      file_class = 'vehicle_photo_raw'
      and retention_policy = 'delete_after_verified_master'
      and not retention_hold
      and retention_delete_job_id is not null
      and retention_delete_lease_token is not null
      and retention_delete_attempt_number is not null
      and retention_delete_started_at is not null
    )
  )
);

create table public.media_retention_hold_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  media_file_id uuid not null,
  hold_kind text not null check (hold_kind in ('legal', 'incident')),
  action text not null check (action in ('held', 'released')),
  retention_version bigint not null check (retention_version > 1),
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  audit_event_id uuid not null,
  outbox_event_id uuid not null,
  request_id text check (request_id is null or pg_catalog.char_length(request_id) <= 200),
  correlation_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, media_file_id, retention_version),
  foreign key (workspace_id, media_file_id)
    references public.media_files (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict
);

create index media_retention_hold_events_file_idx
  on public.media_retention_hold_events (
    workspace_id, media_file_id, hold_kind, retention_version desc
  );

create index media_files_asset_idx
  on public.media_files (workspace_id, media_id, variant, created_at);
create index media_files_retention_due_idx
  on public.media_files (delete_after, id)
  where file_class = 'vehicle_photo_raw' and deleted_at is null and not retention_hold;

alter table public.inventory_cost_entries
  add constraint inventory_cost_entries_supporting_file_fk
  foreign key (workspace_id, supporting_file_id)
  references public.media_files (workspace_id, id)
  on delete restrict;

create table public.media_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  command_type text not null check (
    command_type ~ '^media\.[a-z][a-z0-9_]*$'
  ),
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  result jsonb not null check (
    pg_catalog.jsonb_typeof(result) = 'object'
    and not app.job_payload_contains_forbidden_key(result)
  ),
  actor_user_id uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, command_type, idempotency_key)
);

create function app.prevent_media_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'media history is append-only';
end;
$$;

create function app.protect_media_processing_profile()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft'
      or new.activated_at is not null
      or new.retired_at is not null then
      raise exception using
        errcode = '23514',
        message = 'media processing profile must start as a draft';
    end if;
    return new;
  end if;

  if old.workspace_id is distinct from new.workspace_id
    or old.profile_key is distinct from new.profile_key
    or old.version is distinct from new.version
    or old.profile_snapshot is distinct from new.profile_snapshot
    or old.checksum_sha256 is distinct from new.checksum_sha256
    or old.created_by is distinct from new.created_by
    or old.created_at is distinct from new.created_at then
    raise exception using
      errcode = '55000',
      message = 'media processing profiles are immutable after activation';
  end if;

  if old.status = 'draft' and new.status = 'draft'
    and new.activated_at is null and new.retired_at is null then
    return new;
  end if;
  if old.status = 'draft' and new.status = 'active'
    and new.activated_at is not null and new.retired_at is null then
    return new;
  end if;
  if old.status = 'active' and new.status = 'retired'
    and new.activated_at is not distinct from old.activated_at
    and new.retired_at is not null
    and new.retired_at >= new.activated_at then
    return new;
  end if;

  raise exception using
    errcode = '55000',
    message = 'media processing profile lifecycle transition is not allowed';
end;
$$;

create trigger media_processing_profiles_guard
before insert or update on public.media_processing_profiles
for each row execute function app.protect_media_processing_profile();
create trigger media_processing_profiles_no_delete
before delete on public.media_processing_profiles
for each row execute function app.prevent_media_history_mutation();
create trigger media_upload_sessions_no_delete
before delete on public.media_upload_sessions
for each row execute function app.prevent_media_history_mutation();
create trigger media_processing_runs_no_delete
before delete on public.media_processing_runs
for each row execute function app.prevent_media_history_mutation();
create trigger media_processing_completions_append_only
before update or delete on public.media_processing_completions
for each row execute function app.prevent_media_history_mutation();
create trigger media_command_receipts_append_only
before update or delete on public.media_command_receipts
for each row execute function app.prevent_media_history_mutation();

create function app.guard_media_file_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.id is distinct from new.id
    or old.workspace_id is distinct from new.workspace_id
    or old.media_id is distinct from new.media_id
    or old.processing_run_id is distinct from new.processing_run_id
    or old.file_class is distinct from new.file_class
    or old.variant is distinct from new.variant
    or old.storage_bucket is distinct from new.storage_bucket
    or old.storage_object_key is distinct from new.storage_object_key
    or old.storage_generation is distinct from new.storage_generation
    or old.mime_type is distinct from new.mime_type
    or old.byte_size is distinct from new.byte_size
    or old.checksum_sha256 is distinct from new.checksum_sha256
    or old.width is distinct from new.width
    or old.height is distinct from new.height
    or old.metadata_stripped is distinct from new.metadata_stripped
    or old.retention_policy is distinct from new.retention_policy
    or old.delete_after is distinct from new.delete_after
    or old.verification_receipt is distinct from new.verification_receipt
    or old.created_at is distinct from new.created_at
  then
    raise exception using
      errcode = '55000',
      message = 'media file provenance is immutable';
  end if;

  if old.deleted_at is not distinct from new.deleted_at
    and new.retention_version = old.retention_version + 1
    and old.retention_delete_job_id is not distinct from new.retention_delete_job_id
    and old.retention_delete_lease_token is not distinct from new.retention_delete_lease_token
    and old.retention_delete_attempt_number is not distinct from new.retention_delete_attempt_number
    and old.retention_delete_started_at is not distinct from new.retention_delete_started_at then
    return new;
  end if;

  if old.deleted_at is null
    and new.deleted_at is null
    and old.retention_hold is not distinct from new.retention_hold
    and old.retention_version = new.retention_version
    and not new.retention_hold
    and new.retention_delete_job_id is not null
    and new.retention_delete_lease_token is not null
    and new.retention_delete_attempt_number is not null
    and new.retention_delete_started_at is not null then
    return new;
  end if;

  if old.retention_hold is not distinct from new.retention_hold
    and old.retention_version = new.retention_version
    and old.retention_delete_job_id is not distinct from new.retention_delete_job_id
    and old.retention_delete_lease_token is not distinct from new.retention_delete_lease_token
    and old.retention_delete_attempt_number is not distinct from new.retention_delete_attempt_number
    and old.retention_delete_started_at is not distinct from new.retention_delete_started_at
    and new.retention_delete_job_id is not null
    and old.deleted_at is null
    and new.deleted_at is not null
    and old.file_class = 'vehicle_photo_raw'
    and old.retention_policy = 'delete_after_verified_master'
    and not old.retention_hold
    and old.delete_after <= pg_catalog.statement_timestamp()
    and new.deleted_at >= old.delete_after then
    return new;
  end if;

  raise exception using
    errcode = '55000',
    message = 'media file provenance is immutable';
end;
$$;

create trigger media_files_guard
before update on public.media_files
for each row execute function app.guard_media_file_update();
create trigger media_files_no_delete
before delete on public.media_files
for each row execute function app.prevent_media_history_mutation();
create trigger media_retention_hold_events_append_only
before update or delete on public.media_retention_hold_events
for each row execute function app.prevent_media_history_mutation();

create function app.require_media_permission(
  target_workspace_id uuid,
  permission_key text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
begin
  actor_user_id := auth.uid();
  if actor_user_id is null
    or not app.has_permission(target_workspace_id, permission_key) then
    raise exception using
      errcode = '42501',
      message = 'active workspace membership and media permission are required';
  end if;
  return actor_user_id;
end;
$$;

create function app.ensure_default_vehicle_photo_profile(
  p_workspace_id uuid,
  p_actor_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id uuid;
  next_profile_version integer;
  profile_body text;
  profile_checksum text;
  profile_document jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fvehicle_photo.default',
      0
    )
  );

  select profile.id into profile_id
  from public.media_processing_profiles profile
  where profile.workspace_id = p_workspace_id
    and profile.profile_key = 'vehicle_photo.default'
    and profile.status = 'active';

  if found then
    return profile_id;
  end if;

  select coalesce(pg_catalog.max(profile.version), 0) + 1
    into next_profile_version
  from public.media_processing_profiles profile
  where profile.workspace_id = p_workspace_id
    and profile.profile_key = 'vehicle_photo.default';
  if next_profile_version < 1 then
    raise exception using errcode = '22003', message = 'media profile version is exhausted';
  end if;

  profile_body := pg_catalog.format(
    '{"schemaVersion":1,"profileKey":"vehicle_photo.default","version":%s,"sourcePolicy":{"maximumBytes":20000000,"maximumPixels":60000000,"acceptedMimeTypes":["image/jpeg","image/png","image/webp","image/heic","image/heif"]},"transformationPolicy":{"orientation":"exif_auto","outputColorSpace":"srgb","metadata":{"exif":"strip","gps":"strip","iptc":"strip","xmp":"strip"}},"derivatives":[{"variant":"normalized_master","role":"normalized_master","mimeType":"image/webp","resize":{"mode":"max_edge","maximumEdgePixels":2560,"withoutEnlargement":true}},{"variant":"website_1080","role":"website","mimeType":"image/webp","resize":{"mode":"max_width","maximumWidthPixels":1080,"withoutEnlargement":true}},{"variant":"thumbnail_640","role":"thumbnail","mimeType":"image/webp","resize":{"mode":"max_width","maximumWidthPixels":640,"withoutEnlargement":true}},{"variant":"thumbnail_320","role":"thumbnail","mimeType":"image/webp","resize":{"mode":"max_width","maximumWidthPixels":320,"withoutEnlargement":true}}]}',
    next_profile_version
  );
  profile_checksum := pg_catalog.encode(
    extensions.digest(profile_body, 'sha256'),
    'hex'
  );
  profile_document := profile_body::jsonb
    || pg_catalog.jsonb_build_object('checksumSha256', profile_checksum);

  insert into public.media_processing_profiles (
    workspace_id, profile_key, version, profile_snapshot,
    checksum_sha256, status, created_by
  ) values (
    p_workspace_id, 'vehicle_photo.default', next_profile_version, profile_document,
    profile_checksum, 'draft', p_actor_user_id
  )
  returning id into profile_id;

  update public.media_processing_profiles
  set status = 'active',
      activated_at = pg_catalog.statement_timestamp()
  where workspace_id = p_workspace_id
    and id = profile_id;

  return profile_id;
end;
$$;

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
  normalized_checksum := pg_catalog.nullif(
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
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
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
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
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

create function app.start_vehicle_photo_processing(
  p_workspace_id uuid,
  p_media_id uuid,
  p_processing_run_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_request_id text
)
returns table (
  media_id uuid,
  processing_run_id uuid,
  job_id uuid,
  generation integer,
  source_kind text,
  source_id uuid,
  source_bucket text,
  source_object_key text,
  source_mime_type text,
  source_byte_size bigint,
  source_checksum_sha256 text,
  source_width integer,
  source_height integer,
  source_exif_orientation integer,
  profile_snapshot jsonb,
  profile_checksum_sha256 text,
  media_status text,
  already_succeeded boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  target_run public.media_processing_runs%rowtype;
  target_media public.media_assets%rowtype;
  source_upload public.media_upload_sessions%rowtype;
  source_file public.media_files%rowtype;
  starting boolean;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_worker_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    or p_lease_token is null
    or p_attempt_number is null or p_attempt_number < 1
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid media worker identity';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.id = p_job_id
  for update;

  if not found
    or target_job.job_type <> 'media.process_vehicle_photo'
    or target_job.entity_type <> 'vehicle_media'
    or target_job.entity_id <> p_media_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using
      errcode = '55000',
      message = 'only the active media job lease can start processing';
  end if;

  select run.* into target_run
  from public.media_processing_runs run
  where run.workspace_id = p_workspace_id
    and run.id = p_processing_run_id
    and run.media_id = p_media_id
    and run.job_id = p_job_id
    and run.outbox_event_id = target_job.outbox_event_id
  for update;

  if not found or target_run.status = 'failed' then
    raise exception using errcode = '55000', message = 'media processing run is unavailable';
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo'
  for update;

  if not found or target_media.status in ('awaiting_upload', 'failed', 'archived') then
    raise exception using errcode = '55000', message = 'media state does not permit processing';
  end if;

  if target_run.source_kind = 'upload_session' then
    select upload.* into source_upload
    from public.media_upload_sessions upload
    where upload.workspace_id = p_workspace_id
      and upload.id = target_run.source_id
      and upload.media_id = p_media_id
      and upload.status = 'completed';
    if not found then
      raise exception using errcode = '23514', message = 'validated upload source is unavailable';
    end if;
  else
    select file.* into source_file
    from public.media_files file
    where file.workspace_id = p_workspace_id
      and file.id = target_run.source_id
      and file.media_id = p_media_id
      and file.file_class = 'vehicle_photo_raw'
      and file.deleted_at is null;
    if not found then
      raise exception using errcode = '23514', message = 'retained media source is unavailable';
    end if;
  end if;

  starting := target_run.status = 'queued';
  if starting then
    update public.media_processing_runs run
    set status = 'processing',
        started_at = pg_catalog.statement_timestamp()
    where run.workspace_id = p_workspace_id
      and run.id = p_processing_run_id;

    update public.media_assets asset
    set status = 'processing',
        updated_at = pg_catalog.statement_timestamp()
    where asset.workspace_id = p_workspace_id
      and asset.id = p_media_id;

    perform app.write_audit_event(
      p_workspace_id => p_workspace_id,
      p_action => 'media.processing_started',
      p_entity_type => 'media_asset',
      p_entity_id => p_media_id,
      p_actor_type => 'worker',
      p_before_data => pg_catalog.jsonb_build_object('status', target_media.status),
      p_after_data => pg_catalog.jsonb_build_object(
        'status', 'processing',
        'generation', target_run.generation
      ),
      p_request_id => p_request_id,
      p_correlation_id => target_job.correlation_id,
      p_auth_assurance => 'service',
      p_metadata => pg_catalog.jsonb_build_object(
        'worker_id', p_worker_id,
        'job_id', p_job_id,
        'processing_run_id', p_processing_run_id,
        'attempt_number', p_attempt_number
      )
    );
  end if;

  return query select
    p_media_id,
    p_processing_run_id,
    p_job_id,
    target_run.generation,
    target_run.source_kind,
    target_run.source_id,
    case
      when target_run.source_kind = 'upload_session' then source_upload.quarantine_bucket
      else source_file.storage_bucket
    end,
    case
      when target_run.source_kind = 'upload_session' then source_upload.quarantine_object_key
      else source_file.storage_object_key
    end,
    case
      when target_run.source_kind = 'upload_session' then source_upload.observed_mime_type
      else source_file.mime_type
    end,
    case
      when target_run.source_kind = 'upload_session' then source_upload.observed_byte_size
      else source_file.byte_size
    end,
    case
      when target_run.source_kind = 'upload_session' then source_upload.observed_checksum_sha256
      else source_file.checksum_sha256
    end,
    case
      when target_run.source_kind = 'upload_session' then source_upload.width
      else source_file.width
    end,
    case
      when target_run.source_kind = 'upload_session' then source_upload.height
      else source_file.height
    end,
    case
      when target_run.source_kind = 'upload_session' then source_upload.exif_orientation::integer
      else null::integer
    end,
    target_run.profile_snapshot,
    target_run.profile_checksum_sha256,
    case when target_run.status = 'succeeded' then 'ready' else 'processing' end,
    target_run.status = 'succeeded';
end;
$$;

create function app.complete_vehicle_photo_processing(
  p_workspace_id uuid,
  p_media_id uuid,
  p_processing_run_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_receipt jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  processing_run_id uuid,
  media_status text,
  aggregate_version bigint,
  raw_file_id uuid,
  normalized_master_file_id uuid,
  raw_delete_after timestamptz,
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
  target_run public.media_processing_runs%rowtype;
  target_media public.media_assets%rowtype;
  target_upload public.media_upload_sessions%rowtype;
  target_source_file public.media_files%rowtype;
  existing_completion public.media_processing_completions%rowtype;
  source_mime_type text;
  source_byte_size bigint;
  source_checksum text;
  source_width integer;
  source_height integer;
  raw_object jsonb;
  processor_receipt jsonb;
  derivative_objects jsonb;
  processor_outputs jsonb;
  expected_variant text;
  expected_role text;
  expected_object_key text;
  raw_extension text;
  output_receipt jsonb;
  stored_object jsonb;
  receipt_checksum text;
  next_media_version bigint;
  new_raw_file_id uuid := pg_catalog.gen_random_uuid();
  new_master_file_id uuid;
  new_file_id uuid;
  new_raw_delete_after timestamptz := pg_catalog.statement_timestamp()
    + pg_catalog.make_interval(days => 7);
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_worker_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    or p_lease_token is null
    or p_attempt_number is null or p_attempt_number < 1
    or p_receipt is null or pg_catalog.jsonb_typeof(p_receipt) <> 'object'
    or app.job_payload_contains_forbidden_key(p_receipt)
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid media completion contract';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.id = p_job_id
  for update;

  if not found
    or target_job.job_type <> 'media.process_vehicle_photo'
    or target_job.entity_type <> 'vehicle_media'
    or target_job.entity_id <> p_media_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number
    or target_job.correlation_id <> p_correlation_id then
    raise exception using
      errcode = '55000',
      message = 'only the active media job lease can complete processing';
  end if;

  select run.* into target_run
  from public.media_processing_runs run
  where run.workspace_id = p_workspace_id
    and run.id = p_processing_run_id
    and run.media_id = p_media_id
    and run.job_id = p_job_id
    and run.outbox_event_id = target_job.outbox_event_id
  for update;

  if not found or target_run.status not in ('processing', 'succeeded') then
    raise exception using errcode = '55000', message = 'media processing run cannot complete';
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo'
  for update;

  if not found or target_media.status not in ('processing', 'ready') then
    raise exception using errcode = '55000', message = 'media state cannot complete';
  end if;

  if target_run.source_kind = 'upload_session' then
    select upload.* into target_upload
    from public.media_upload_sessions upload
    where upload.workspace_id = p_workspace_id
      and upload.id = target_run.source_id
      and upload.media_id = p_media_id
      and upload.status = 'completed';
    if not found then
      raise exception using errcode = '23514', message = 'validated upload source is unavailable';
    end if;
    source_mime_type := target_upload.observed_mime_type;
    source_byte_size := target_upload.observed_byte_size;
    source_checksum := target_upload.observed_checksum_sha256;
    source_width := target_upload.width;
    source_height := target_upload.height;
  else
    select file.* into target_source_file
    from public.media_files file
    where file.workspace_id = p_workspace_id
      and file.id = target_run.source_id
      and file.media_id = p_media_id
      and file.file_class = 'vehicle_photo_raw'
      and file.deleted_at is null;
    if not found then
      raise exception using errcode = '23514', message = 'retained media source is unavailable';
    end if;
    source_mime_type := target_source_file.mime_type;
    source_byte_size := target_source_file.byte_size;
    source_checksum := target_source_file.checksum_sha256;
    source_width := target_source_file.width;
    source_height := target_source_file.height;
  end if;

  if p_receipt ->> 'workspaceId' <> p_workspace_id::text
    or p_receipt ->> 'mediaId' <> p_media_id::text
    or p_receipt ->> 'processingRunId' <> p_processing_run_id::text
    or p_receipt ->> 'jobId' <> p_job_id::text
    or p_receipt ->> 'workerId' <> p_worker_id
    or p_receipt ->> 'leaseId' <> p_lease_token::text
    or coalesce((p_receipt ->> 'attempt')::integer, 0) <> p_attempt_number
    or coalesce((p_receipt ->> 'schemaVersion')::integer, 0) <> 1
    or p_receipt ->> 'profileChecksumSha256' <> target_run.profile_checksum_sha256
    or p_receipt ->> 'sourceChecksumSha256' <> source_checksum then
    raise exception using errcode = '23514', message = 'media completion identity is inconsistent';
  end if;

  raw_object := p_receipt -> 'rawObject';
  processor_receipt := p_receipt -> 'processorReceipt';
  derivative_objects := p_receipt -> 'derivativeObjects';
  processor_outputs := processor_receipt -> 'outputs';

  if pg_catalog.jsonb_typeof(raw_object) <> 'object'
    or pg_catalog.jsonb_typeof(processor_receipt) <> 'object'
    or pg_catalog.jsonb_typeof(derivative_objects) <> 'array'
    or pg_catalog.jsonb_typeof(processor_outputs) <> 'array'
    or pg_catalog.jsonb_array_length(derivative_objects) <> 4
    or pg_catalog.jsonb_array_length(processor_outputs) <> 4
    or processor_receipt ->> 'profileChecksumSha256' <> target_run.profile_checksum_sha256
    or processor_receipt ->> 'sourceChecksumSha256' <> source_checksum
    or pg_catalog.btrim(coalesce(processor_receipt #>> '{processor,name}', '')) = ''
    or pg_catalog.btrim(coalesce(processor_receipt #>> '{processor,version}', '')) = '' then
    raise exception using errcode = '23514', message = 'media processor receipt is invalid';
  end if;

  raw_extension := case source_mime_type
    when 'image/jpeg' then 'jpg'
    when 'image/png' then 'png'
    when 'image/webp' then 'webp'
    when 'image/heic' then 'heic'
    when 'image/heif' then 'heif'
    else null
  end;
  expected_object_key := 'workspaces/' || p_workspace_id::text
    || '/media/' || p_media_id::text || '/raw/' || source_checksum
    || '.' || raw_extension;

  if raw_extension is null
    or raw_object ->> 'bucket' <> 'media-private'
    or raw_object ->> 'objectKey' <> expected_object_key
    or coalesce((raw_object ->> 'byteSize')::bigint, 0) <> source_byte_size
    or raw_object ->> 'mimeType' <> source_mime_type
    or raw_object ->> 'checksumSha256' <> source_checksum then
    raise exception using errcode = '23514', message = 'media raw-object receipt is invalid';
  end if;

  foreach expected_variant in array array[
    'normalized_master', 'website_1080', 'thumbnail_640', 'thumbnail_320'
  ] loop
    select element.value into output_receipt
    from pg_catalog.jsonb_array_elements(processor_outputs) element
    where element.value ->> 'variant' = expected_variant;

    if not found then
      raise exception using errcode = '23514', message = 'media derivative receipt is incomplete';
    end if;

    expected_role := case expected_variant
      when 'normalized_master' then 'normalized_master'
      when 'website_1080' then 'website'
      else 'thumbnail'
    end;
    expected_object_key := 'workspaces/' || p_workspace_id::text
      || '/media/' || p_media_id::text || '/runs/' || p_processing_run_id::text
      || '/' || expected_variant || '/' || (output_receipt ->> 'checksumSha256')
      || '.webp';

    select element.value into stored_object
    from pg_catalog.jsonb_array_elements(derivative_objects) element
    where element.value ->> 'objectKey' = expected_object_key;

    if not found
      or output_receipt ->> 'role' <> expected_role
      or output_receipt ->> 'mimeType' <> 'image/webp'
      or coalesce((output_receipt ->> 'width')::integer, 0) < 1
      or coalesce((output_receipt ->> 'height')::integer, 0) < 1
      or coalesce((output_receipt ->> 'byteSize')::bigint, 0) < 1
      or output_receipt ->> 'checksumSha256' !~ '^[a-f0-9]{64}$'
      or coalesce((output_receipt ->> 'orientationPolicyApplied')::boolean, false) is false
      or coalesce((output_receipt ->> 'normalizedOrientation')::integer, 0) <> 1
      or output_receipt ->> 'outputColorSpace' <> 'srgb'
      or coalesce((output_receipt ->> 'upscaled')::boolean, true)
      or coalesce((output_receipt #>> '{metadata,exifPresent}')::boolean, true)
      or coalesce((output_receipt #>> '{metadata,gpsPresent}')::boolean, true)
      or coalesce((output_receipt #>> '{metadata,iptcPresent}')::boolean, true)
      or coalesce((output_receipt #>> '{metadata,xmpPresent}')::boolean, true)
      or stored_object ->> 'bucket' <> 'media-private'
      or stored_object ->> 'mimeType' <> 'image/webp'
      or stored_object ->> 'checksumSha256' <> output_receipt ->> 'checksumSha256'
      or coalesce((stored_object ->> 'byteSize')::bigint, 0)
        <> coalesce((output_receipt ->> 'byteSize')::bigint, -1) then
      raise exception using errcode = '23514', message = 'media derivative receipt is unsafe';
    end if;
  end loop;

  receipt_checksum := app.job_request_fingerprint(p_receipt);

  select completion.* into existing_completion
  from public.media_processing_completions completion
  where completion.workspace_id = p_workspace_id
    and completion.processing_run_id = p_processing_run_id;

  if found then
    if existing_completion.receipt_checksum_sha256 <> receipt_checksum
      or existing_completion.worker_id <> p_worker_id
      or existing_completion.lease_token <> p_lease_token
      or existing_completion.attempt_number <> p_attempt_number then
      raise exception using errcode = '23505', message = 'media completion replay conflicts';
    end if;

    return query select
      p_media_id,
      p_processing_run_id,
      'ready'::text,
      target_media.version,
      (
        select file.id from public.media_files file
        where file.workspace_id = p_workspace_id
          and file.processing_run_id = p_processing_run_id
          and file.variant = 'raw_original'
      ),
      (
        select file.id from public.media_files file
        where file.workspace_id = p_workspace_id
          and file.processing_run_id = p_processing_run_id
          and file.variant = 'normalized_master'
      ),
      (
        select file.delete_after from public.media_files file
        where file.workspace_id = p_workspace_id
          and file.processing_run_id = p_processing_run_id
          and file.variant = 'raw_original'
      ),
      true,
      (
        select audit.id from public.audit_events audit
        where audit.workspace_id = p_workspace_id
          and audit.action = 'media.processing_succeeded'
          and audit.entity_id = p_media_id
          and audit.metadata ->> 'processing_run_id' = p_processing_run_id::text
        order by audit.occurred_at desc limit 1
      ),
      (
        select event.id from public.outbox_events event
        where event.workspace_id = p_workspace_id
          and event.event_name = 'media.processing_succeeded'
          and event.aggregate_id = p_media_id
          and event.payload ->> 'processing_run_id' = p_processing_run_id::text
        order by event.occurred_at desc limit 1
      );
    return;
  end if;

  if target_run.status <> 'processing' or target_media.status <> 'processing' then
    raise exception using errcode = '55000', message = 'media completion state is inconsistent';
  end if;

  insert into public.media_processing_completions (
    workspace_id, media_id, processing_run_id, job_id, worker_id, lease_token,
    attempt_number, receipt_schema_version, receipt, receipt_checksum_sha256
  ) values (
    p_workspace_id, p_media_id, p_processing_run_id, p_job_id, p_worker_id,
    p_lease_token, p_attempt_number, 1, p_receipt, receipt_checksum
  );

  insert into public.media_files (
    id, workspace_id, media_id, processing_run_id, file_class, variant,
    storage_bucket, storage_object_key, mime_type, byte_size, checksum_sha256,
    width, height, metadata_stripped, retention_policy, delete_after
  ) values (
    new_raw_file_id, p_workspace_id, p_media_id, p_processing_run_id,
    'vehicle_photo_raw', 'raw_original', raw_object ->> 'bucket',
    raw_object ->> 'objectKey', source_mime_type, source_byte_size,
    source_checksum, source_width, source_height, false,
    'delete_after_verified_master', new_raw_delete_after
  );

  foreach expected_variant in array array[
    'normalized_master', 'website_1080', 'thumbnail_640', 'thumbnail_320'
  ] loop
    select element.value into output_receipt
    from pg_catalog.jsonb_array_elements(processor_outputs) element
    where element.value ->> 'variant' = expected_variant;
    expected_object_key := 'workspaces/' || p_workspace_id::text
      || '/media/' || p_media_id::text || '/runs/' || p_processing_run_id::text
      || '/' || expected_variant || '/' || (output_receipt ->> 'checksumSha256')
      || '.webp';
    select element.value into stored_object
    from pg_catalog.jsonb_array_elements(derivative_objects) element
    where element.value ->> 'objectKey' = expected_object_key;
    new_file_id := pg_catalog.gen_random_uuid();
    if expected_variant = 'normalized_master' then
      new_master_file_id := new_file_id;
    end if;
    insert into public.media_files (
      id, workspace_id, media_id, processing_run_id, file_class, variant,
      storage_bucket, storage_object_key, mime_type, byte_size, checksum_sha256,
      width, height, metadata_stripped, retention_policy
    ) values (
      new_file_id, p_workspace_id, p_media_id, p_processing_run_id,
      'vehicle_photo_derivative', expected_variant,
      stored_object ->> 'bucket', stored_object ->> 'objectKey', 'image/webp',
      (stored_object ->> 'byteSize')::bigint,
      stored_object ->> 'checksumSha256',
      (output_receipt ->> 'width')::integer,
      (output_receipt ->> 'height')::integer,
      true, 'retain_until_archive'
    );
  end loop;

  update public.media_processing_runs run
  set status = 'succeeded',
      terminal_receipt_checksum_sha256 = receipt_checksum,
      completed_at = pg_catalog.statement_timestamp(),
      last_error_classification = null,
      last_error_code = null
  where run.workspace_id = p_workspace_id
    and run.id = p_processing_run_id;

  next_media_version := target_media.version + 1;
  update public.media_assets asset
  set status = 'ready',
      version = next_media_version,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, correlation_id,
    causation_id
  ) values (
    p_workspace_id, 'media.processing_succeeded', 'media_asset', p_media_id,
    next_media_version, 1,
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'processing_run_id', p_processing_run_id,
      'generation', target_run.generation,
      'raw_file_id', new_raw_file_id,
      'normalized_master_file_id', new_master_file_id,
      'raw_delete_after', new_raw_delete_after
    ),
    p_correlation_id, target_job.outbox_event_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.processing_succeeded',
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', target_media.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'ready',
      'version', next_media_version,
      'generation', target_run.generation
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'worker_id', p_worker_id,
      'job_id', p_job_id,
      'processing_run_id', p_processing_run_id,
      'attempt_number', p_attempt_number,
      'receipt_checksum_sha256', receipt_checksum,
      'outbox_event_id', new_outbox_event_id
    )
  );

  return query select
    p_media_id, p_processing_run_id, 'ready'::text, next_media_version,
    new_raw_file_id, new_master_file_id, new_raw_delete_after, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.record_vehicle_photo_processing_failure(
  p_workspace_id uuid,
  p_media_id uuid,
  p_processing_run_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_error_classification text,
  p_error_code text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
  processing_run_id uuid,
  media_status text,
  terminal boolean,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  target_run public.media_processing_runs%rowtype;
  target_media public.media_assets%rowtype;
  is_terminal boolean;
  next_media_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_worker_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    or p_error_classification not in (
      'transient', 'rate_limited', 'permanent', 'validation',
      'permission', 'provider_auth', 'unknown'
    )
    or p_error_code !~ '^[a-z][a-z0-9_.-]{0,119}$'
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid safe media failure contract';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.id = p_job_id
  for update;

  if not found
    or target_job.job_type <> 'media.process_vehicle_photo'
    or target_job.entity_id <> p_media_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number
    or target_job.correlation_id <> p_correlation_id then
    raise exception using
      errcode = '55000',
      message = 'only the active media job lease can record failure';
  end if;

  select run.* into target_run
  from public.media_processing_runs run
  where run.workspace_id = p_workspace_id
    and run.id = p_processing_run_id
    and run.media_id = p_media_id
    and run.job_id = p_job_id
  for update;
  if not found or target_run.status not in ('queued', 'processing') then
    raise exception using errcode = '55000', message = 'media processing run cannot fail';
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
  for update;
  if not found or target_media.status not in ('quarantined', 'processing') then
    raise exception using errcode = '55000', message = 'media state cannot fail';
  end if;

  is_terminal := p_error_classification in (
    'permanent', 'validation', 'permission', 'provider_auth'
  ) or p_attempt_number >= target_job.max_attempts;
  next_media_version := target_media.version + case when is_terminal then 1 else 0 end;

  update public.media_processing_runs run
  set status = case when is_terminal then 'failed' else 'processing' end,
      started_at = coalesce(run.started_at, pg_catalog.statement_timestamp()),
      completed_at = case when is_terminal then pg_catalog.statement_timestamp() else null end,
      last_error_classification = p_error_classification,
      last_error_code = p_error_code
  where run.workspace_id = p_workspace_id
    and run.id = p_processing_run_id;

  if is_terminal then
    update public.media_assets asset
    set status = 'failed',
        version = next_media_version,
        updated_at = pg_catalog.statement_timestamp()
    where asset.workspace_id = p_workspace_id
      and asset.id = p_media_id;
  end if;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, correlation_id,
    causation_id
  ) values (
    p_workspace_id,
    case when is_terminal then 'media.processing_failed' else 'media.processing_retry_pending' end,
    'media_asset', p_media_id, next_media_version, 1,
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'processing_run_id', p_processing_run_id,
      'attempt_number', p_attempt_number,
      'classification', p_error_classification,
      'error_code', p_error_code,
      'terminal', is_terminal
    ),
    p_correlation_id, target_job.outbox_event_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => case
      when is_terminal then 'media.processing_failed'
      else 'media.processing_retry_pending'
    end,
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', target_media.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', case when is_terminal then 'failed' else 'processing' end,
      'version', next_media_version,
      'terminal', is_terminal
    ),
    p_reason => p_error_code,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'worker_id', p_worker_id,
      'job_id', p_job_id,
      'processing_run_id', p_processing_run_id,
      'attempt_number', p_attempt_number,
      'classification', p_error_classification,
      'outbox_event_id', new_outbox_event_id
    )
  );

  return query select
    p_media_id, p_processing_run_id,
    case when is_terminal then 'failed' else 'processing' end,
    is_terminal, next_media_version, new_audit_event_id, new_outbox_event_id;
end;
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
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
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
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
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
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
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

create function app.enqueue_due_vehicle_raw_retention(
  p_limit integer default 100,
  p_correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (
  media_file_id uuid,
  job_id uuid,
  created boolean,
  job_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  due_file record;
  queued record;
begin
  if p_limit not between 1 and 1000 or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid retention enqueue request';
  end if;

  for due_file in
    select
      file.id,
      file.workspace_id,
      file.media_id,
      asset.version
    from public.media_files file
    join public.media_assets asset
      on asset.workspace_id = file.workspace_id
     and asset.id = file.media_id
    where file.file_class = 'vehicle_photo_raw'
      and file.retention_policy = 'delete_after_verified_master'
      and file.delete_after <= pg_catalog.statement_timestamp()
      and file.deleted_at is null
      and not file.retention_hold
      and asset.status in ('ready', 'archived')
      and exists (
        select 1
        from public.media_files master
        where master.workspace_id = file.workspace_id
          and master.media_id = file.media_id
          and master.processing_run_id = file.processing_run_id
          and master.variant = 'normalized_master'
          and master.deleted_at is null
      )
    order by file.delete_after, file.id
    for update of file skip locked
    limit p_limit
  loop
    select result.* into queued
    from app.enqueue_outbox_job(
      p_workspace_id => due_file.workspace_id,
      p_event_name => 'media.raw_retention_queued',
      p_aggregate_type => 'media_asset',
      p_aggregate_id => due_file.media_id,
      p_aggregate_version => due_file.version,
      p_job_type => 'media.delete_retained_raw',
      p_entity_type => 'media_file',
      p_entity_id => due_file.id,
      p_payload_schema_version => 1,
      p_payload => pg_catalog.jsonb_build_object(
        'media_file_id', due_file.id,
        'media_id', due_file.media_id
      ),
      p_idempotency_key => 'media:retention:' || due_file.id::text,
      p_correlation_id => p_correlation_id,
      p_priority => 20,
      p_max_attempts => 8,
      p_backoff_base_seconds => 60,
      p_backoff_max_seconds => 7200,
      p_request_id => 'scheduler:media-retention'
    ) result;

    media_file_id := due_file.id;
    job_id := queued.job_id;
    created := queued.created;
    job_status := queued.job_status;
    return next;
  end loop;
end;
$$;

create function app.load_vehicle_raw_retention(
  p_workspace_id uuid,
  p_media_file_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer
)
returns table (
  media_file_id uuid,
  media_id uuid,
  storage_bucket text,
  storage_object_key text,
  checksum_sha256 text,
  already_deleted boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  target_file public.media_files%rowtype;
begin
  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.id = p_job_id
  for update;
  if not found
    or target_job.job_type <> 'media.delete_retained_raw'
    or target_job.entity_type <> 'media_file'
    or target_job.entity_id <> p_media_file_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using
      errcode = '55000',
      message = 'only the active retention job lease can load a file';
  end if;

  select file.* into target_file
  from public.media_files file
  where file.workspace_id = p_workspace_id
    and file.id = p_media_file_id
    and file.file_class = 'vehicle_photo_raw'
  for update;
  if not found
    or target_file.retention_policy <> 'delete_after_verified_master'
    or target_file.retention_hold
    or target_file.delete_after > pg_catalog.statement_timestamp()
    or not exists (
      select 1 from public.media_files master
      where master.workspace_id = p_workspace_id
        and master.media_id = target_file.media_id
        and master.processing_run_id = target_file.processing_run_id
        and master.variant = 'normalized_master'
        and master.deleted_at is null
  ) then
    raise exception using errcode = '55000', message = 'raw retention is not due';
  end if;

  if target_file.deleted_at is not null then
    return query select
      target_file.id, target_file.media_id, target_file.storage_bucket,
      target_file.storage_object_key, target_file.checksum_sha256, true;
    return;
  end if;
  if target_file.retention_delete_job_id is not null
    and target_file.retention_delete_job_id <> p_job_id then
    raise exception using
      errcode = '55000',
      message = 'raw deletion is already fenced by another job';
  end if;

  update public.media_files file
  set retention_delete_job_id = p_job_id,
      retention_delete_lease_token = p_lease_token,
      retention_delete_attempt_number = p_attempt_number,
      retention_delete_started_at = pg_catalog.statement_timestamp()
  where file.workspace_id = p_workspace_id
    and file.id = p_media_file_id
  returning file.* into target_file;

  return query select
    target_file.id, target_file.media_id, target_file.storage_bucket,
    target_file.storage_object_key, target_file.checksum_sha256,
    target_file.deleted_at is not null;
end;
$$;

create function app.complete_vehicle_raw_retention(
  p_workspace_id uuid,
  p_media_file_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_storage_result text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_file_id uuid,
  media_id uuid,
  deleted_at timestamptz,
  replayed boolean,
  aggregate_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  target_file public.media_files%rowtype;
  target_media public.media_assets%rowtype;
  deletion_time timestamptz := pg_catalog.statement_timestamp();
  next_media_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  if p_storage_result not in ('deleted', 'not_found')
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid retention completion contract';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.id = p_job_id
  for update;
  if not found
    or target_job.job_type <> 'media.delete_retained_raw'
    or target_job.entity_id <> p_media_file_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= deletion_time
    or target_job.attempts_started <> p_attempt_number
    or target_job.correlation_id <> p_correlation_id then
    raise exception using
      errcode = '55000',
      message = 'only the active retention job lease can complete deletion';
  end if;

  select file.* into target_file
  from public.media_files file
  where file.workspace_id = p_workspace_id
    and file.id = p_media_file_id
    and file.file_class = 'vehicle_photo_raw'
  for update;
  if not found
    or target_file.retention_policy <> 'delete_after_verified_master'
    or target_file.retention_hold
    or target_file.delete_after > deletion_time
    or target_file.retention_delete_job_id is distinct from p_job_id
    or target_file.retention_delete_lease_token is distinct from p_lease_token
    or target_file.retention_delete_attempt_number is distinct from p_attempt_number then
    raise exception using errcode = '55000', message = 'raw retention is not due';
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = target_file.media_id
  for update;
  if not found or target_media.status not in ('ready', 'archived') then
    raise exception using errcode = '55000', message = 'media master is not retention-safe';
  end if;

  if target_file.deleted_at is not null then
    return query select
      target_file.id,
      target_file.media_id,
      target_file.deleted_at,
      true,
      (
        select event.aggregate_version from public.outbox_events event
        where event.workspace_id = p_workspace_id
          and event.event_name = 'media.raw_deleted'
          and event.payload ->> 'media_file_id' = p_media_file_id::text
        order by event.occurred_at desc limit 1
      ),
      (
        select audit.id from public.audit_events audit
        where audit.workspace_id = p_workspace_id
          and audit.action = 'media.raw_deleted'
          and audit.entity_id = p_media_file_id
        order by audit.occurred_at desc limit 1
      ),
      (
        select event.id from public.outbox_events event
        where event.workspace_id = p_workspace_id
          and event.event_name = 'media.raw_deleted'
          and event.payload ->> 'media_file_id' = p_media_file_id::text
        order by event.occurred_at desc limit 1
      );
    return;
  end if;

  if not exists (
    select 1
    from public.media_files master
    where master.workspace_id = p_workspace_id
      and master.media_id = target_file.media_id
      and master.processing_run_id = target_file.processing_run_id
      and master.variant = 'normalized_master'
      and master.deleted_at is null
  ) then
    raise exception using errcode = '55000', message = 'media master is not retention-safe';
  end if;

  next_media_version := target_media.version + 1;

  update public.media_files file
  set deleted_at = deletion_time
  where file.workspace_id = p_workspace_id
    and file.id = p_media_file_id;
  update public.media_assets asset
  set version = next_media_version,
      updated_at = deletion_time
  where asset.workspace_id = p_workspace_id
    and asset.id = target_file.media_id;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, correlation_id,
    causation_id
  ) values (
    p_workspace_id, 'media.raw_deleted', 'media_asset', target_file.media_id,
    next_media_version, 1,
    pg_catalog.jsonb_build_object(
      'media_id', target_file.media_id,
      'media_file_id', p_media_file_id,
      'aggregate_version', next_media_version,
      'deleted_at', deletion_time,
      'storage_result', p_storage_result
    ),
    p_correlation_id, target_job.outbox_event_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.raw_deleted',
    p_entity_type => 'media_file',
    p_entity_id => p_media_file_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object(
      'deleted_at', null,
      'aggregate_version', target_media.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'deleted_at', deletion_time,
      'aggregate_version', next_media_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'worker_id', p_worker_id,
      'job_id', p_job_id,
      'storage_result', p_storage_result,
      'outbox_event_id', new_outbox_event_id
    )
  );

  return query select
    p_media_file_id, target_file.media_id, deletion_time, false,
    next_media_version, new_audit_event_id, new_outbox_event_id;
end;
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
      || case p_owner_entity_type
        when 'document' then 'documents'
        when 'deal' then 'deals'
        else 'inventory-units'
      end || '/' || p_owner_entity_id::text || '/%' then
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
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
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
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
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

create function app.authorize_managed_media_download(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_file_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_file_id uuid,
  storage_bucket text,
  storage_object_key text,
  storage_generation text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  media_kind text,
  replayed boolean,
  audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  target_file public.media_files%rowtype;
  target_asset public.media_assets%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_idempotency_key text;
  request_fingerprint text;
  new_audit_event_id uuid;
begin
  normalized_idempotency_key := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  if actor_user_id is null
    or pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_media_file_id is null
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200) then
    raise exception using errcode = '22023', message = 'invalid managed media download request';
  end if;

  select file, asset into target_file, target_asset
  from public.media_files file
  join public.media_assets asset
    on asset.workspace_id = file.workspace_id
   and asset.id = file.media_id
  where file.workspace_id = p_workspace_id
    and file.id = p_media_file_id
    and file.deleted_at is null;

  if not found
    or (
      target_asset.media_kind = 'vehicle_photo'
      and not app.has_permission(p_workspace_id, 'media.read')
    )
    or (
      target_asset.media_kind <> 'vehicle_photo'
      and not app.has_permission(p_workspace_id, 'documents.read')
    ) then
    raise exception using errcode = '42501', message = 'managed media download is not authorized';
  end if;
  if target_asset.media_kind <> 'vehicle_photo'
    and not app.has_recent_strong_auth() then
    raise exception using errcode = '42501', message = 'recent strong authentication is required';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'actor_user_id', actor_user_id,
      'media_file_id', p_media_file_id
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.authorize_download\x1f'
        || normalized_idempotency_key,
      0
    )
  );
  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.command_type = 'media.authorize_download'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.request_fingerprint <> request_fingerprint
      or existing_receipt.actor_user_id <> actor_user_id then
      raise exception using errcode = '23505', message = 'download authorization replay conflicts';
    end if;
    return query select
      target_file.id, target_file.storage_bucket, target_file.storage_object_key,
      target_file.storage_generation, target_file.mime_type, target_file.byte_size,
      target_file.checksum_sha256, target_asset.media_kind, true,
      (existing_receipt.result ->> 'audit_event_id')::uuid;
    return;
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.download_authorized',
    p_entity_type => 'media_file',
    p_entity_id => p_media_file_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'media_kind', target_asset.media_kind,
      'byte_size', target_file.byte_size::text,
      'checksum_sha256', target_file.checksum_sha256
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object('signed_grant_required', true)
  );
  insert into public.media_command_receipts (
    workspace_id, command_type, idempotency_key, request_fingerprint,
    result, actor_user_id
  ) values (
    p_workspace_id, 'media.authorize_download', normalized_idempotency_key,
    request_fingerprint,
    pg_catalog.jsonb_build_object(
      'media_file_id', p_media_file_id,
      'audit_event_id', new_audit_event_id
    ),
    actor_user_id
  );

  return query select
    target_file.id, target_file.storage_bucket, target_file.storage_object_key,
    target_file.storage_generation, target_file.mime_type, target_file.byte_size,
    target_file.checksum_sha256, target_asset.media_kind, false,
    new_audit_event_id;
end;
$$;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'media-private',
  'media-private',
  false,
  50000000,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.media_processing_profiles enable row level security;
alter table public.media_processing_profiles force row level security;
alter table public.inventory_media_collections enable row level security;
alter table public.inventory_media_collections force row level security;
alter table public.media_assets enable row level security;
alter table public.media_assets force row level security;
alter table public.media_upload_sessions enable row level security;
alter table public.media_upload_sessions force row level security;
alter table public.media_processing_runs enable row level security;
alter table public.media_processing_runs force row level security;
alter table public.media_processing_completions enable row level security;
alter table public.media_processing_completions force row level security;
alter table public.media_files enable row level security;
alter table public.media_files force row level security;
alter table public.media_retention_hold_events enable row level security;
alter table public.media_retention_hold_events force row level security;
alter table public.media_command_receipts enable row level security;
alter table public.media_command_receipts force row level security;

create policy media_processing_profiles_select
on public.media_processing_profiles
for select to authenticated
using (app.has_permission(workspace_id, 'media.read'));

create policy inventory_media_collections_select
on public.inventory_media_collections
for select to authenticated
using (app.has_permission(workspace_id, 'media.read'));

create policy media_assets_select
on public.media_assets
for select to authenticated
using (
  (
    media_kind = 'vehicle_photo'
    and app.has_permission(workspace_id, 'media.read')
  )
  or (
    media_kind <> 'vehicle_photo'
    and app.has_permission(workspace_id, 'documents.read')
  )
);

create policy media_upload_sessions_select
on public.media_upload_sessions
for select to authenticated
using (app.has_permission(workspace_id, 'media.read'));

create policy media_processing_runs_select
on public.media_processing_runs
for select to authenticated
using (app.has_permission(workspace_id, 'media.read'));

create policy media_files_select
on public.media_files
for select to authenticated
using (
  exists (
    select 1
    from public.media_assets asset
    where asset.workspace_id = media_files.workspace_id
      and asset.id = media_files.media_id
      and (
        (
          asset.media_kind = 'vehicle_photo'
          and app.has_permission(asset.workspace_id, 'media.read')
        )
        or (
          asset.media_kind <> 'vehicle_photo'
          and app.has_permission(asset.workspace_id, 'documents.read')
        )
      )
  )
);

create policy media_retention_hold_events_select
on public.media_retention_hold_events
for select to authenticated
using (app.has_permission(workspace_id, 'media.archive'));

revoke all on table
  public.media_processing_profiles,
  public.inventory_media_collections,
  public.media_assets,
  public.media_upload_sessions,
  public.media_processing_runs,
  public.media_processing_completions,
  public.media_files,
  public.media_retention_hold_events,
  public.media_command_receipts
from public, anon, authenticated, service_role;

grant select on
  public.media_processing_profiles,
  public.inventory_media_collections,
  public.media_assets,
  public.media_upload_sessions,
  public.media_processing_runs,
  public.media_files,
  public.media_retention_hold_events
to authenticated;

grant select on
  public.media_processing_profiles,
  public.inventory_media_collections,
  public.media_assets,
  public.media_upload_sessions,
  public.media_processing_runs,
  public.media_processing_completions,
  public.media_files,
  public.media_retention_hold_events,
  public.media_command_receipts
to service_role;

revoke all on function app.prevent_media_history_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app.protect_media_processing_profile()
  from public, anon, authenticated, service_role;
revoke all on function app.guard_media_file_update()
  from public, anon, authenticated, service_role;
revoke all on function app.require_media_permission(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.ensure_default_vehicle_photo_profile(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.create_vehicle_photo_upload_session(
  uuid, text, uuid, text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.complete_vehicle_photo_upload(
  uuid, uuid, text, uuid, uuid, text, bigint, text, boolean,
  integer, integer, integer, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.start_vehicle_photo_processing(
  uuid, uuid, uuid, uuid, text, uuid, integer, text
) from public, anon, authenticated, service_role;
revoke all on function app.complete_vehicle_photo_processing(
  uuid, uuid, uuid, uuid, text, uuid, integer, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.record_vehicle_photo_processing_failure(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
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
revoke all on function app.enqueue_due_vehicle_raw_retention(integer, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.load_vehicle_raw_retention(
  uuid, uuid, uuid, text, uuid, integer
) from public, anon, authenticated, service_role;
revoke all on function app.complete_vehicle_raw_retention(
  uuid, uuid, uuid, text, uuid, integer, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.record_preserved_legal_original(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint, text,
  jsonb, uuid, text, uuid, integer, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.set_managed_media_retention_hold(
  uuid, text, uuid, bigint, boolean, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.authorize_managed_media_download(
  uuid, text, uuid, text, uuid
)
  from public, anon, authenticated, service_role;

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
grant execute on function app.authorize_managed_media_download(
  uuid, text, uuid, text, uuid
)
  to authenticated;

grant execute on function app.complete_vehicle_photo_upload(
  uuid, uuid, text, uuid, uuid, text, bigint, text, boolean,
  integer, integer, integer, jsonb, text, uuid
) to service_role;
grant execute on function app.start_vehicle_photo_processing(
  uuid, uuid, uuid, uuid, text, uuid, integer, text
) to service_role;
grant execute on function app.complete_vehicle_photo_processing(
  uuid, uuid, uuid, uuid, text, uuid, integer, jsonb, text, uuid
) to service_role;
grant execute on function app.record_vehicle_photo_processing_failure(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) to service_role;
grant execute on function app.enqueue_due_vehicle_raw_retention(integer, uuid)
  to service_role;
grant execute on function app.load_vehicle_raw_retention(
  uuid, uuid, uuid, text, uuid, integer
) to service_role;
grant execute on function app.complete_vehicle_raw_retention(
  uuid, uuid, uuid, text, uuid, integer, text, text, uuid
) to service_role;
grant execute on function app.record_preserved_legal_original(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint, text,
  jsonb, uuid, text, uuid, integer, text, uuid
) to service_role;

comment on table public.media_processing_profiles is
  'Immutable workspace image-processing profile snapshots; historical runs retain checksum and source.';
comment on table public.media_assets is
  'Workspace-scoped media aggregates with phone-safe collection order and one-cover invariants.';
comment on table public.media_upload_sessions is
  'Private bounded quarantine upload intents whose object keys never contain user filenames.';
comment on table public.media_processing_runs is
  'Durable processing lineage bound to one immutable profile, source reference, outbox event, and job.';
comment on table public.media_processing_completions is
  'Append-only exact worker, lease, attempt, and receipt provenance for successful image processing.';
comment on table public.media_files is
  'Private object provenance separating expiring vehicle raw files, stripped derivatives, and preserved legal originals.';
comment on table public.media_retention_hold_events is
  'Append-only, audited legal and incident hold lifecycle for managed media retention.';
comment on function app.create_vehicle_photo_upload_session(
  uuid, text, uuid, text, text, bigint, text, text, uuid
) is 'Authenticated media intent; the application issues a short-lived private upload grant for the returned exact object.';
comment on function app.complete_vehicle_photo_processing(
  uuid, uuid, uuid, uuid, text, uuid, integer, jsonb, text, uuid
) is 'Service-only exact-lease processing completion with deterministic raw/derivative verification and idempotent receipt.';
comment on function app.record_preserved_legal_original(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint, text,
  jsonb, uuid, text, uuid, integer, text, uuid
) is 'Service-only byte-preserved legal/signed original provenance; no retention deletion command accepts these rows.';
comment on function app.set_managed_media_retention_hold(
  uuid, text, uuid, bigint, boolean, text, text, text, uuid
) is 'Authenticated, step-up protected, idempotent legal/incident hold lifecycle with optimistic retention fencing.';
comment on function app.authorize_managed_media_download(
  uuid, text, uuid, text, uuid
) is 'Authenticated exact-object download authorization; callers must exchange the result for a short-lived server-side storage grant.';
