-- VYN-DOC-001, VYN-STOR-001, VYN-SEC-001, VYN-AUD-001, VYN-API-001
-- M1-DOC-AC-013, T-DOC-JOB-006: preview bytes are reachable only through
-- a short-lived, audited server grant. Provider coordinates remain server-only.

create table public.document_preview_download_authorizations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  artifact_id uuid not null,
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
  foreign key (workspace_id, artifact_id)
    references public.document_preview_artifacts (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id)
    on delete restrict,
  check (
    expires_at > created_at
    and expires_at <= created_at + interval '5 minutes'
  )
);

create index document_preview_download_authorizations_expiry_idx
  on public.document_preview_download_authorizations (
    expires_at,
    workspace_id,
    id
  );

create trigger document_preview_download_authorizations_append_only
before update or delete on public.document_preview_download_authorizations
for each row execute function app.prevent_job_history_mutation();

create function app.authorize_document_preview_download(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_artifact_id uuid,
  p_expires_in_seconds integer,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  authorization_id uuid,
  artifact_id uuid,
  document_id uuid,
  filename text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  authorization_expires_at timestamptz,
  replayed boolean,
  audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  normalized_idempotency_key text;
  request_fingerprint text;
  target_artifact public.document_preview_artifacts%rowtype;
  existing_authorization public.document_preview_download_authorizations%rowtype;
  new_authorization_id uuid := pg_catalog.gen_random_uuid();
  new_authorization_expires_at timestamptz :=
    pg_catalog.statement_timestamp() + interval '5 minutes';
  new_audit_event_id uuid;
begin
  actor_user_id := auth.uid();
  normalized_idempotency_key := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );

  if actor_user_id is null
    or not (
      app.has_permission(p_workspace_id, 'documents.read')
      or app.has_permission(p_workspace_id, 'documents.preview')
    ) then
    raise exception using
      errcode = '42501',
      message = 'active workspace membership and document permission are required';
  end if;
  if p_workspace_id is null
    or p_artifact_id is null
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
      message = 'invalid document preview download authorization';
  end if;

  select artifact.*
    into target_artifact
  from public.document_preview_artifacts artifact
  where artifact.workspace_id = p_workspace_id
    and artifact.id = p_artifact_id;

  if not found
    or (
      not app.has_permission(p_workspace_id, 'documents.read')
      and target_artifact.requested_by <> actor_user_id
    ) then
    raise exception using
      errcode = 'P0002',
      message = 'document preview artifact was not found';
  end if;

  request_fingerprint := app.vertical_slice_fingerprint(
    pg_catalog.jsonb_build_object(
      'artifact_id', p_artifact_id,
      'expires_in_seconds', p_expires_in_seconds
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fdocument_preview_download\x1f'
        || actor_user_id::text || E'\x1f' || normalized_idempotency_key,
      0
    )
  );

  select download_authorization.*
    into existing_authorization
  from public.document_preview_download_authorizations download_authorization
  where download_authorization.workspace_id = p_workspace_id
    and download_authorization.actor_user_id = app.current_user_id()
    and download_authorization.idempotency_key = normalized_idempotency_key;

  if found then
    if existing_authorization.request_fingerprint <> request_fingerprint then
      raise exception using
        errcode = '23505',
        message = 'preview download idempotency key was reused';
    end if;
    if existing_authorization.expires_at <= pg_catalog.statement_timestamp() then
      raise exception using
        errcode = '55000',
        message = 'preview download authorization expired';
    end if;
    return query select
      existing_authorization.id,
      target_artifact.id,
      target_artifact.document_id,
      target_artifact.filename,
      target_artifact.mime_type,
      target_artifact.byte_size,
      target_artifact.checksum,
      existing_authorization.expires_at,
      true,
      existing_authorization.audit_event_id;
    return;
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document_preview.download_authorized',
    p_entity_type => 'document_preview_artifact',
    p_entity_id => target_artifact.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'authorization_id', new_authorization_id,
      'document_id', target_artifact.document_id,
      'byte_size', target_artifact.byte_size,
      'checksum_sha256', target_artifact.checksum,
      'signed_url_ttl_seconds', p_expires_in_seconds
    )
  );

  insert into public.document_preview_download_authorizations (
    id,
    workspace_id,
    artifact_id,
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
    target_artifact.id,
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
    target_artifact.id,
    target_artifact.document_id,
    target_artifact.filename,
    target_artifact.mime_type,
    target_artifact.byte_size,
    target_artifact.checksum,
    new_authorization_expires_at,
    false,
    new_audit_event_id;
end;
$$;

create function app.load_document_preview_download_authorization(
  p_authorization_id uuid
)
returns table (
  authorization_id uuid,
  workspace_id uuid,
  artifact_id uuid,
  document_id uuid,
  storage_bucket text,
  storage_object_path text,
  filename text,
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
      message = 'preview download authorization ID is required';
  end if;

  return query
  select
    download_authorization.id,
    download_authorization.workspace_id,
    artifact.id,
    artifact.document_id,
    artifact.storage_bucket,
    artifact.storage_object_path,
    artifact.filename,
    artifact.mime_type,
    artifact.byte_size,
    artifact.checksum,
    download_authorization.signed_url_ttl_seconds,
    download_authorization.expires_at
  from public.document_preview_download_authorizations download_authorization
  join public.document_preview_artifacts artifact
    on artifact.workspace_id = download_authorization.workspace_id
   and artifact.id = download_authorization.artifact_id
  where download_authorization.id = p_authorization_id
    and download_authorization.expires_at > pg_catalog.statement_timestamp();

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'preview download authorization was not found';
  end if;
end;
$$;

alter table public.document_preview_download_authorizations enable row level security;
alter table public.document_preview_download_authorizations force row level security;

-- RLS continues to scope the safe artifact projection. Provider coordinates are
-- not selectable by authenticated clients even when they can see the artifact.
revoke all on public.document_preview_artifacts from authenticated;
grant select (
  id,
  workspace_id,
  document_id,
  filename,
  mime_type,
  byte_size,
  checksum,
  renderer_version,
  created_at
) on public.document_preview_artifacts to authenticated;

revoke all on public.document_preview_download_authorizations
  from public, anon, authenticated, service_role;
revoke all on function app.authorize_document_preview_download(
  uuid, text, uuid, integer, text, uuid
) from public, anon, service_role;
revoke all on function app.load_document_preview_download_authorization(uuid)
  from public, anon, authenticated;

grant execute on function app.authorize_document_preview_download(
  uuid, text, uuid, integer, text, uuid
) to authenticated;
grant execute on function app.load_document_preview_download_authorization(uuid)
  to service_role;

comment on function app.authorize_document_preview_download(
  uuid, text, uuid, integer, text, uuid
) is
  'Audits one visible immutable preview artifact and returns no provider coordinates.';
comment on function app.load_document_preview_download_authorization(uuid) is
  'Service-only exact provider metadata load for one unexpired audited preview download_authorization.';
