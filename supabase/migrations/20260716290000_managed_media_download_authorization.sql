-- VYN-MEDIA-001, VYN-STOR-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-API-001, M2-MEDIA-MGMT-AC-003
-- Browser authorization returns only an opaque, expiring reference. Provider
-- coordinates are resolved by a service-role-only loader immediately before
-- immutable byte verification and short-lived signing.

create table public.managed_media_download_authorizations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  media_file_id uuid not null,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 8 and 200
    and idempotency_key = pg_catalog.btrim(idempotency_key)
  ),
  request_fingerprint text not null check (
    request_fingerprint ~ '^[a-f0-9]{64}$'
  ),
  signed_url_ttl_seconds integer not null check (
    signed_url_ttl_seconds between 30 and 300
  ),
  expires_at timestamptz not null,
  request_id text check (
    request_id is null or pg_catalog.char_length(request_id) <= 200
  ),
  correlation_id uuid not null,
  audit_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, idempotency_key),
  foreign key (workspace_id, media_file_id)
    references public.media_files (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id)
    on delete restrict,
  check (
    expires_at > created_at
    and expires_at <= created_at + interval '5 minutes'
  )
);

create index managed_media_download_authorizations_expiry_idx
  on public.managed_media_download_authorizations (
    expires_at,
    workspace_id,
    id
  );

create trigger managed_media_download_authorizations_append_only
before update or delete on public.managed_media_download_authorizations
for each row execute function app.prevent_job_history_mutation();

drop function app.authorize_managed_media_download(
  uuid, text, uuid, text, uuid
);

create function app.authorize_managed_media_download(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_file_id uuid,
  p_expires_in_seconds integer,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  authorization_id uuid,
  media_file_id uuid,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  media_kind text,
  authorization_expires_at timestamptz,
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
  existing_authorization public.managed_media_download_authorizations%rowtype;
  normalized_idempotency_key text := pg_catalog.btrim(
    pg_catalog.coalesce(p_idempotency_key, '')
  );
  request_fingerprint text;
  new_authorization_id uuid := pg_catalog.gen_random_uuid();
  new_authorization_expires_at timestamptz :=
    pg_catalog.statement_timestamp() + interval '5 minutes';
  new_audit_event_id uuid;
begin
  if actor_user_id is null
    or p_workspace_id is null
    or p_media_file_id is null
    or pg_catalog.char_length(normalized_idempotency_key) not between 8 and 200
    or p_expires_in_seconds is null
    or p_expires_in_seconds not between 30 and 300
    or p_correlation_id is null
    or (
      p_request_id is not null
      and pg_catalog.char_length(p_request_id) > 200
    ) then
    raise exception using
      errcode = '22023',
      message = 'invalid managed media download authorization';
  end if;

  select file, asset
    into target_file, target_asset
  from public.media_files file
  join public.media_assets asset
    on asset.workspace_id = file.workspace_id
   and asset.id = file.media_id
  where file.workspace_id = p_workspace_id
    and file.id = p_media_file_id
    and file.deleted_at is null
    and (
      asset.media_kind <> 'vehicle_photo'
      or exists (
        select 1
        from public.media_processing_runs processing_run
        where processing_run.workspace_id = asset.workspace_id
          and processing_run.media_id = asset.id
          and processing_run.id = file.processing_run_id
          and processing_run.generation = asset.generation
          and processing_run.status = 'succeeded'
      )
    );

  if not found
    or (
      target_asset.media_kind = 'vehicle_photo'
      and not app.has_permission(p_workspace_id, 'media.read')
    )
    or (
      target_asset.media_kind <> 'vehicle_photo'
      and not app.has_permission(p_workspace_id, 'documents.read')
    )
    or (
      target_asset.media_kind = 'signed_document'
      and not app.has_permission(p_workspace_id, 'files.read_restricted')
    ) then
    raise exception using
      errcode = '42501',
      message = 'managed media download is not authorized';
  end if;
  if target_asset.media_kind <> 'vehicle_photo'
    and not app.has_recent_strong_auth() then
    raise exception using
      errcode = '42501',
      message = 'recent strong authentication is required';
  end if;

  request_fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'media_file_id', p_media_file_id,
      'expires_in_seconds', p_expires_in_seconds
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fmedia.authorize_download\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select authorization.*
    into existing_authorization
  from public.managed_media_download_authorizations authorization
  where authorization.workspace_id = p_workspace_id
    and authorization.actor_user_id = actor_user_id
    and authorization.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_authorization.request_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'managed media download idempotency key was reused';
    end if;
    if existing_authorization.expires_at <= pg_catalog.statement_timestamp() then
      raise exception using
        errcode = '55000',
        message = 'managed media download authorization expired';
    end if;
    return query select
      existing_authorization.id,
      target_file.id,
      target_file.mime_type,
      target_file.byte_size,
      target_file.checksum_sha256,
      target_asset.media_kind,
      existing_authorization.expires_at,
      true,
      existing_authorization.audit_event_id;
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
    p_auth_assurance => pg_catalog.coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'authorization_id', new_authorization_id,
      'signed_url_ttl_seconds', p_expires_in_seconds,
      'provider_coordinates_server_only', true
    )
  );

  insert into public.managed_media_download_authorizations (
    id,
    workspace_id,
    media_file_id,
    actor_user_id,
    idempotency_key,
    request_fingerprint,
    signed_url_ttl_seconds,
    expires_at,
    request_id,
    correlation_id,
    audit_event_id
  ) values (
    new_authorization_id,
    p_workspace_id,
    p_media_file_id,
    actor_user_id,
    normalized_idempotency_key,
    request_fingerprint,
    p_expires_in_seconds,
    new_authorization_expires_at,
    p_request_id,
    p_correlation_id,
    new_audit_event_id
  );

  return query select
    new_authorization_id,
    target_file.id,
    target_file.mime_type,
    target_file.byte_size,
    target_file.checksum_sha256,
    target_asset.media_kind,
    new_authorization_expires_at,
    false,
    new_audit_event_id;
end;
$$;

create function app.load_managed_media_download_authorization(
  p_authorization_id uuid
)
returns table (
  authorization_id uuid,
  workspace_id uuid,
  media_file_id uuid,
  media_kind text,
  storage_bucket text,
  storage_object_key text,
  storage_generation text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  signed_url_ttl_seconds integer,
  authorization_expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'service role is required';
  end if;
  if p_authorization_id is null then
    raise exception using
      errcode = '22023',
      message = 'managed media download authorization ID is required';
  end if;

  return query
  select
    authorization.id,
    authorization.workspace_id,
    file.id,
    asset.media_kind,
    file.storage_bucket,
    file.storage_object_key,
    file.storage_generation,
    file.mime_type,
    file.byte_size,
    file.checksum_sha256,
    authorization.signed_url_ttl_seconds,
    authorization.expires_at
  from public.managed_media_download_authorizations authorization
  join public.media_files file
    on file.workspace_id = authorization.workspace_id
   and file.id = authorization.media_file_id
  join public.media_assets asset
    on asset.workspace_id = file.workspace_id
   and asset.id = file.media_id
  where authorization.id = p_authorization_id
    and authorization.expires_at > pg_catalog.statement_timestamp()
    and file.deleted_at is null
    and (
      asset.media_kind <> 'vehicle_photo'
      or exists (
        select 1
        from public.media_processing_runs processing_run
        where processing_run.workspace_id = asset.workspace_id
          and processing_run.media_id = asset.id
          and processing_run.id = file.processing_run_id
          and processing_run.generation = asset.generation
          and processing_run.status = 'succeeded'
      )
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'managed media download authorization was not found';
  end if;
end;
$$;

alter table public.managed_media_download_authorizations enable row level security;
alter table public.managed_media_download_authorizations force row level security;

revoke all on public.managed_media_download_authorizations
  from public, anon, authenticated, service_role;
revoke all on function app.authorize_managed_media_download(
  uuid, text, uuid, integer, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.load_managed_media_download_authorization(uuid)
  from public, anon, authenticated, service_role;

grant execute on function app.authorize_managed_media_download(
  uuid, text, uuid, integer, text, uuid
) to authenticated;
grant execute on function app.load_managed_media_download_authorization(uuid)
  to service_role;

comment on table public.managed_media_download_authorizations is
  'Append-only audited authorization for one exact managed media file; no provider coordinate is browser-readable.';
comment on function app.authorize_managed_media_download(
  uuid, text, uuid, integer, text, uuid
) is
  'Audits one authorized managed media file, requiring restricted-file permission for signed originals and the current successful run for vehicle media, and returns only opaque expiring metadata.';
comment on function app.load_managed_media_download_authorization(uuid) is
  'Service-only exact provider metadata load for one unexpired audited authorization, revalidating the current successful vehicle-media generation before signing.';
