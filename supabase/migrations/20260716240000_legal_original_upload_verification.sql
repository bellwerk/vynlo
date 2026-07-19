-- M2-MEDIA-AC-021: byte-preserved document original upload verification.
-- Upload intent metadata is advisory until a lease-bound worker derives the
-- stored checksum, size, generation, MIME signature and clean malware receipt.

create table public.legal_original_upload_sessions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_id uuid not null,
  media_kind text not null check (media_kind in ('legal_document', 'signed_document')),
  original_filename text not null check (
    pg_catalog.char_length(original_filename) between 1 and 255
    and original_filename !~ '[[:cntrl:]]'
  ),
  expected_mime_type text not null check (expected_mime_type in (
    'application/pdf', 'image/jpeg', 'image/png', 'image/webp',
    'image/heic', 'image/heif'
  )),
  expected_byte_size bigint not null check (expected_byte_size between 1 and 50000000),
  expected_checksum_sha256 text not null check (expected_checksum_sha256 ~ '^[a-f0-9]{64}$'),
  upload_bucket text not null default 'media-private' check (upload_bucket = 'media-private'),
  upload_object_key text not null check (pg_catalog.char_length(upload_object_key) between 1 and 1000),
  status text not null default 'awaiting_upload' check (
    status in ('awaiting_upload', 'verification_requested', 'completed', 'rejected', 'expired')
  ),
  expires_at timestamptz not null,
  verification_job_id uuid,
  verification_outbox_event_id uuid,
  verification_audit_event_id uuid,
  verification_requested_at timestamptz,
  observed_mime_type text,
  observed_byte_size bigint,
  observed_checksum_sha256 text,
  storage_generation text,
  verification_receipt jsonb,
  media_id uuid,
  media_file_id uuid,
  rejection_code text check (rejection_code is null or pg_catalog.char_length(rejection_code) between 1 and 120),
  completed_at timestamptz,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (upload_bucket, upload_object_key),
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, verification_job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, verification_outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, media_id)
    references public.media_assets (workspace_id, id) on delete restrict,
  foreign key (workspace_id, media_file_id)
    references public.media_files (workspace_id, id) on delete restrict,
  constraint legal_original_upload_object_key_check check (
    upload_object_key = 'workspaces/' || workspace_id::text
      || '/documents/' || document_id::text
      || '/upload-intents/' || id::text || '/source'
  ),
  constraint legal_original_upload_state_check check (
    (status = 'awaiting_upload'
      and verification_job_id is null and verification_outbox_event_id is null
      and verification_audit_event_id is null and verification_requested_at is null
      and observed_mime_type is null and observed_byte_size is null
      and observed_checksum_sha256 is null and storage_generation is null
      and verification_receipt is null and media_id is null and media_file_id is null
      and rejection_code is null and completed_at is null)
    or (status = 'verification_requested'
      and verification_job_id is not null and verification_outbox_event_id is not null
      and verification_audit_event_id is not null and verification_requested_at is not null
      and observed_mime_type is null and observed_byte_size is null
      and observed_checksum_sha256 is null and storage_generation is null
      and verification_receipt is null and media_id is null and media_file_id is null
      and rejection_code is null and completed_at is null)
    or (status = 'completed'
      and verification_job_id is not null and verification_outbox_event_id is not null
      and verification_audit_event_id is not null and verification_requested_at is not null
      and observed_mime_type = expected_mime_type
      and observed_byte_size = expected_byte_size
      and observed_checksum_sha256 = expected_checksum_sha256
      and pg_catalog.btrim(storage_generation) <> ''
      and pg_catalog.jsonb_typeof(verification_receipt) = 'object'
      and media_id is not null and media_file_id is not null
      and rejection_code is null and completed_at is not null)
    or (status = 'rejected'
      and verification_job_id is not null and verification_outbox_event_id is not null
      and verification_audit_event_id is not null and verification_requested_at is not null
      and observed_mime_type is null and observed_byte_size is null
      and observed_checksum_sha256 is null and storage_generation is null
      and verification_receipt is null and media_id is null and media_file_id is null
      and rejection_code is not null and completed_at is not null)
    or (status = 'expired'
      and verification_job_id is null and verification_outbox_event_id is null
      and verification_audit_event_id is null and verification_requested_at is null
      and observed_mime_type is null and observed_byte_size is null
      and observed_checksum_sha256 is null and storage_generation is null
      and verification_receipt is null and media_id is null and media_file_id is null
      and rejection_code is null and completed_at is null)
  )
);

create index legal_original_upload_sessions_expiry_idx
  on public.legal_original_upload_sessions (expires_at, id)
  where status = 'awaiting_upload';

create trigger legal_original_upload_sessions_no_delete
before delete on public.legal_original_upload_sessions
for each row execute function app.prevent_media_history_mutation();

alter table public.legal_original_upload_sessions enable row level security;
alter table public.legal_original_upload_sessions force row level security;

create policy legal_original_upload_sessions_select
on public.legal_original_upload_sessions
for select to authenticated
using (
  created_by = auth.uid()
  and app.has_permission(
    workspace_id,
    case when media_kind = 'signed_document'
      then 'documents.upload_signed' else 'media.create' end
  )
);

create policy legal_original_uploads_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media-private'
  and pg_catalog.jsonb_typeof(metadata) = 'object'
  and exists (
    select 1
    from public.legal_original_upload_sessions upload
    where upload.upload_bucket = storage.objects.bucket_id
      and upload.upload_object_key = storage.objects.name
      and upload.created_by = auth.uid()
      and upload.status = 'awaiting_upload'
      and upload.expires_at > pg_catalog.statement_timestamp()
      and upload.verification_job_id is null
      and case
        when storage.objects.metadata ->> 'size' ~ '^(0|[1-9][0-9]{0,18})$'
          then (storage.objects.metadata ->> 'size')::numeric
            = upload.expected_byte_size::numeric
        else false
      end
      and pg_catalog.lower(pg_catalog.btrim(coalesce(metadata ->> 'mimetype', '')))
        = upload.expected_mime_type
      and app.has_permission(
        upload.workspace_id,
        case when upload.media_kind = 'signed_document'
          then 'documents.upload_signed' else 'media.create' end
      )
      and (upload.media_kind <> 'signed_document' or app.has_recent_strong_auth())
  )
);

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

create function app.load_legal_original_upload_verification(
  p_workspace_id uuid, p_document_id uuid, p_upload_session_id uuid,
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_attempt_number integer
)
returns table (
  upload_session_id uuid, document_id uuid, actor_user_id uuid,
  media_kind text, upload_bucket text, upload_object_key text,
  expected_mime_type text, expected_byte_size bigint,
  expected_checksum_sha256 text
)
language plpgsql security definer set search_path = '' as $$
declare target_job public.jobs%rowtype; target public.legal_original_upload_sessions%rowtype;
begin
  select job.* into target_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id for update;
  if not found or target_job.job_type <> 'media.verify_legal_original'
    or target_job.entity_type <> 'document' or target_job.entity_id <> p_document_id
    or target_job.status <> 'running' or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using errcode = '55000', message = 'only the active legal verification lease can load an upload';
  end if;
  select upload.* into target from public.legal_original_upload_sessions upload
  where upload.workspace_id = p_workspace_id and upload.id = p_upload_session_id
    and upload.document_id = p_document_id and upload.verification_job_id = p_job_id;
  if not found or target.status <> 'verification_requested' then
    raise exception using errcode = '55000', message = 'legal upload cannot be verified';
  end if;
  return query select target.id, target.document_id, target.created_by,
    target.media_kind, target.upload_bucket, target.upload_object_key,
    target.expected_mime_type, target.expected_byte_size,
    target.expected_checksum_sha256;
end; $$;

create function app.complete_legal_original_upload_verification(
  p_workspace_id uuid, p_document_id uuid, p_upload_session_id uuid,
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_attempt_number integer,
  p_observed_mime_type text, p_observed_byte_size bigint,
  p_observed_checksum_sha256 text, p_storage_generation text,
  p_verification_receipt jsonb, p_request_id text, p_correlation_id uuid
)
returns table (media_id uuid, media_file_id uuid, replayed boolean)
language plpgsql security definer set search_path = '' as $$
declare
  target_job public.jobs%rowtype;
  target public.legal_original_upload_sessions%rowtype;
  recorded record;
  normalized_checksum text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_observed_checksum_sha256, '')));
  normalized_generation text := pg_catalog.btrim(coalesce(p_storage_generation, ''));
begin
  select job.* into target_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id for update;
  if not found or target_job.job_type <> 'media.verify_legal_original'
    or target_job.entity_type <> 'document' or target_job.entity_id <> p_document_id
    or target_job.status <> 'running' or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number
    or target_job.correlation_id <> p_correlation_id then
    raise exception using errcode = '55000', message = 'only the active legal verification lease can complete an upload';
  end if;
  select upload.* into target from public.legal_original_upload_sessions upload
  where upload.workspace_id = p_workspace_id and upload.id = p_upload_session_id
    and upload.document_id = p_document_id and upload.verification_job_id = p_job_id
  for update;
  if not found then raise exception using errcode = '55000', message = 'legal upload verification is unavailable'; end if;
  if target.status = 'completed' then
    return query select target.media_id, target.media_file_id, true; return;
  end if;
  if target.status <> 'verification_requested'
    or p_observed_mime_type <> target.expected_mime_type
    or p_observed_byte_size <> target.expected_byte_size
    or normalized_checksum <> target.expected_checksum_sha256
    or normalized_generation = '' or pg_catalog.char_length(normalized_generation) > 200
    or p_verification_receipt ->> 'schemaVersion' <> '1'
    or p_verification_receipt ->> 'jobId' <> p_job_id::text
    or p_verification_receipt ->> 'workerId' <> p_worker_id
    or p_verification_receipt ->> 'leaseId' <> p_lease_token::text
    or p_verification_receipt ->> 'attempt' <> p_attempt_number::text
    or p_verification_receipt -> 'storage' ->> 'bucket' <> target.upload_bucket
    or p_verification_receipt -> 'storage' ->> 'objectKey' <> target.upload_object_key
    or p_verification_receipt -> 'storage' ->> 'generation' <> normalized_generation
    or p_verification_receipt -> 'storage' ->> 'mimeType' <> p_observed_mime_type
    or p_verification_receipt -> 'storage' ->> 'byteSize' <> p_observed_byte_size::text
    or p_verification_receipt -> 'storage' ->> 'checksumSha256' <> normalized_checksum
    or p_verification_receipt -> 'malwareScan' ->> 'verdict' <> 'clean'
    or p_verification_receipt -> 'malwareScan' ->> 'sourceChecksumSha256' <> normalized_checksum then
    raise exception using errcode = '23514', message = 'legal original verification does not match upload intent';
  end if;
  select result.* into recorded from app.record_preserved_legal_original(
    p_workspace_id => p_workspace_id, p_actor_user_id => target.created_by,
    p_idempotency_key => 'media:record-legal:' || p_upload_session_id::text,
    p_media_kind => target.media_kind, p_owner_entity_type => 'document',
    p_owner_entity_id => target.document_id, p_storage_bucket => target.upload_bucket,
    p_storage_object_key => target.upload_object_key,
    p_storage_generation => normalized_generation, p_mime_type => p_observed_mime_type,
    p_byte_size => p_observed_byte_size, p_checksum_sha256 => normalized_checksum,
    p_verification_receipt => p_verification_receipt, p_job_id => p_job_id,
    p_worker_id => p_worker_id, p_lease_token => p_lease_token,
    p_attempt_number => p_attempt_number, p_request_id => p_request_id,
    p_correlation_id => p_correlation_id
  ) result;
  update public.legal_original_upload_sessions upload set
    status = 'completed', observed_mime_type = p_observed_mime_type,
    observed_byte_size = p_observed_byte_size,
    observed_checksum_sha256 = normalized_checksum,
    storage_generation = normalized_generation,
    verification_receipt = p_verification_receipt,
    media_id = recorded.media_id, media_file_id = recorded.media_file_id,
    completed_at = pg_catalog.statement_timestamp()
  where upload.workspace_id = p_workspace_id and upload.id = p_upload_session_id;
  return query select recorded.media_id, recorded.media_file_id, recorded.replayed;
end; $$;

create function app.reject_legal_original_upload_verification(
  p_workspace_id uuid, p_document_id uuid, p_upload_session_id uuid,
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_attempt_number integer,
  p_error_code text, p_error_classification text,
  p_request_id text, p_correlation_id uuid
)
returns table (upload_session_id uuid, upload_status text, replayed boolean, audit_event_id uuid, outbox_event_id uuid)
language plpgsql security definer set search_path = '' as $$
declare
  target_job public.jobs%rowtype;
  target public.legal_original_upload_sessions%rowtype;
  next_aggregate_version bigint;
  new_outbox uuid; new_audit uuid;
begin
  if p_error_classification not in ('permanent', 'permission', 'validation')
    or pg_catalog.btrim(coalesce(p_error_code, '')) = ''
    or pg_catalog.char_length(p_error_code) > 120 or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid legal verification rejection';
  end if;
  select job.* into target_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id for update;
  if not found or target_job.job_type <> 'media.verify_legal_original'
    or target_job.entity_type <> 'document' or target_job.entity_id <> p_document_id
    or target_job.status <> 'running' or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using errcode = '55000', message = 'only the active legal verification lease can reject an upload';
  end if;
  select upload.* into target from public.legal_original_upload_sessions upload
  where upload.workspace_id = p_workspace_id and upload.id = p_upload_session_id
    and upload.document_id = p_document_id and upload.verification_job_id = p_job_id
  for update;
  if not found then raise exception using errcode = '55000', message = 'legal upload verification is unavailable'; end if;
  if target.status = 'rejected' then
    return query select target.id, target.status, true, null::uuid, null::uuid; return;
  end if;
  if target.status <> 'verification_requested' then
    raise exception using errcode = '55000', message = 'legal upload cannot be rejected';
  end if;
  select coalesce(pg_catalog.max(event.aggregate_version), 0) + 1
    into next_aggregate_version
  from public.outbox_events event
  where event.workspace_id = p_workspace_id
    and event.aggregate_type = 'legal_original_upload_session'
    and event.aggregate_id = p_upload_session_id;
  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id, aggregate_version,
    payload_schema_version, payload, correlation_id
  ) values (
    p_workspace_id, 'media.legal_original_verification_rejected',
    'legal_original_upload_session', p_upload_session_id,
    next_aggregate_version, 1,
    pg_catalog.jsonb_build_object('upload_session_id', p_upload_session_id,
      'document_id', p_document_id, 'job_id', p_job_id,
      'error_code', p_error_code, 'error_classification', p_error_classification),
    p_correlation_id
  ) returning id into new_outbox;
  new_audit := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.legal_original_verification_rejected',
    p_entity_type => 'legal_original_upload_session', p_entity_id => p_upload_session_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object('status', target.status),
    p_after_data => pg_catalog.jsonb_build_object('status', 'rejected'),
    p_reason => p_error_code, p_request_id => p_request_id,
    p_correlation_id => p_correlation_id, p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object('job_id', p_job_id,
      'worker_id', p_worker_id, 'attempt_number', p_attempt_number,
      'error_classification', p_error_classification,
      'outbox_event_id', new_outbox)
  );
  update public.legal_original_upload_sessions upload set
    status = 'rejected', rejection_code = p_error_code,
    completed_at = pg_catalog.statement_timestamp()
  where upload.workspace_id = p_workspace_id and upload.id = p_upload_session_id;
  return query select p_upload_session_id, 'rejected'::text, false, new_audit, new_outbox;
end; $$;

-- Unaccepted objects remain quarantine objects. Expired intents and terminal
-- verification rejections enter a separate durable deletion lineage; completed
-- preserved originals can never satisfy the cleanup safety predicate.
create table public.legal_original_quarantine_cleanups (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null,
  upload_session_id uuid not null,
  reason text not null check (reason in ('expired_intent', 'terminal_rejection')),
  job_id uuid not null,
  outbox_event_id uuid not null,
  queued_audit_event_id uuid not null,
  status text not null default 'queued' check (
    status in ('queued', 'fenced', 'deleted', 'not_found')
  ),
  observed_mime_type text,
  observed_byte_size bigint,
  observed_checksum_sha256 text,
  storage_generation text,
  storage_result text check (storage_result is null or storage_result in ('deleted', 'not_found')),
  completion_audit_event_id uuid,
  completion_outbox_event_id uuid,
  completed_at timestamptz,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, upload_session_id),
  unique (workspace_id, job_id),
  foreign key (workspace_id, upload_session_id)
    references public.legal_original_upload_sessions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  constraint legal_original_cleanup_state_check check (
    (status = 'queued'
      and observed_mime_type is null and observed_byte_size is null
      and observed_checksum_sha256 is null and storage_generation is null
      and storage_result is null and completion_audit_event_id is null
      and completion_outbox_event_id is null and completed_at is null)
    or (status = 'fenced'
      and pg_catalog.btrim(observed_mime_type) <> ''
      and observed_byte_size between 1 and 50000000
      and observed_checksum_sha256 ~ '^[a-f0-9]{64}$'
      and pg_catalog.btrim(storage_generation) <> ''
      and storage_result is null and completion_audit_event_id is null
      and completion_outbox_event_id is null and completed_at is null)
    or (status = 'deleted'
      and pg_catalog.btrim(observed_mime_type) <> ''
      and observed_byte_size between 1 and 50000000
      and observed_checksum_sha256 ~ '^[a-f0-9]{64}$'
      and pg_catalog.btrim(storage_generation) <> ''
      and storage_result = 'deleted' and completion_audit_event_id is not null
      and completion_outbox_event_id is not null and completed_at is not null)
    or (status = 'not_found'
      and observed_mime_type is null and observed_byte_size is null
      and observed_checksum_sha256 is null and storage_generation is null
      and storage_result = 'not_found' and completion_audit_event_id is not null
      and completion_outbox_event_id is not null and completed_at is not null)
  )
);

create index legal_original_quarantine_cleanups_status_idx
  on public.legal_original_quarantine_cleanups (status, created_at, id)
  where status in ('queued', 'fenced');

create trigger legal_original_quarantine_cleanups_no_delete
before delete on public.legal_original_quarantine_cleanups
for each row execute function app.prevent_media_history_mutation();

alter table public.legal_original_quarantine_cleanups enable row level security;
alter table public.legal_original_quarantine_cleanups force row level security;

create function app.legal_original_quarantine_cleanup_still_safe(
  p_workspace_id uuid, p_cleanup_id uuid
)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.legal_original_quarantine_cleanups cleanup
    join public.legal_original_upload_sessions upload
      on upload.workspace_id = cleanup.workspace_id
     and upload.id = cleanup.upload_session_id
    where cleanup.workspace_id = p_workspace_id
      and cleanup.id = p_cleanup_id
      and upload.media_id is null and upload.media_file_id is null
      and upload.verification_receipt is null
      and (
        (cleanup.reason = 'expired_intent' and upload.status = 'expired')
        or (cleanup.reason = 'terminal_rejection' and upload.status = 'rejected')
      )
  );
$$;

create function app.enqueue_due_legal_original_quarantine_cleanup(
  p_limit integer, p_correlation_id uuid
)
returns table (
  cleanup_id uuid, upload_session_id uuid, cleanup_reason text,
  job_id uuid, outbox_event_id uuid
)
language plpgsql security definer set search_path = '' as $$
declare
  due record;
  queued record;
  new_cleanup_id uuid;
  new_audit_id uuid;
  normalized_reason text;
  next_aggregate_version bigint;
begin
  if p_limit is null or p_limit not between 1 and 500 or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid legal cleanup enqueue request';
  end if;
  for due in
    select upload.*
    from public.legal_original_upload_sessions upload
    where (
      (upload.status = 'awaiting_upload'
        and upload.expires_at <= pg_catalog.statement_timestamp())
      or upload.status = 'rejected'
    )
      and upload.media_id is null and upload.media_file_id is null
      and not exists (
        select 1 from public.legal_original_quarantine_cleanups cleanup
        where cleanup.workspace_id = upload.workspace_id
          and cleanup.upload_session_id = upload.id
      )
    order by upload.expires_at, upload.id
    for update of upload skip locked
    limit p_limit
  loop
    normalized_reason := case when due.status = 'rejected'
      then 'terminal_rejection' else 'expired_intent' end;
    if due.status = 'awaiting_upload' then
      update public.legal_original_upload_sessions upload
      set status = 'expired'
      where upload.workspace_id = due.workspace_id and upload.id = due.id
        and upload.status = 'awaiting_upload';
      if not found then continue; end if;
    end if;
    new_cleanup_id := pg_catalog.gen_random_uuid();
    select coalesce(pg_catalog.max(event.aggregate_version), 0) + 1
      into next_aggregate_version
    from public.outbox_events event
    where event.workspace_id = due.workspace_id
      and event.aggregate_type = 'legal_original_upload_session'
      and event.aggregate_id = due.id;
    select result.* into queued from app.enqueue_outbox_job(
      p_workspace_id => due.workspace_id,
      p_event_name => 'media.legal_original_quarantine_cleanup_queued',
      p_aggregate_type => 'legal_original_upload_session',
      p_aggregate_id => due.id,
      p_aggregate_version => next_aggregate_version,
      p_job_type => 'media.delete_legal_original_quarantine',
      p_entity_type => 'legal_original_upload_session', p_entity_id => due.id,
      p_payload_schema_version => 1,
      p_payload => pg_catalog.jsonb_build_object(
        'upload_session_id', due.id, 'reason', normalized_reason),
      p_idempotency_key => 'media:delete-legal-quarantine:' || due.id::text,
      p_correlation_id => p_correlation_id, p_priority => 25,
      p_max_attempts => 8, p_backoff_base_seconds => 60,
      p_backoff_max_seconds => 3600,
      p_request_id => 'scheduler:legal-original-quarantine-cleanup'
    ) result;
    new_audit_id := app.write_audit_event(
      p_workspace_id => due.workspace_id,
      p_action => 'media.legal_original_quarantine_cleanup_queued',
      p_entity_type => 'legal_original_upload_session', p_entity_id => due.id,
      p_actor_type => 'system',
      p_before_data => pg_catalog.jsonb_build_object('status', due.status),
      p_after_data => pg_catalog.jsonb_build_object(
        'status', case when due.status = 'awaiting_upload' then 'expired' else due.status end,
        'cleanup_id', new_cleanup_id, 'reason', normalized_reason,
        'job_id', queued.job_id, 'outbox_event_id', queued.outbox_event_id),
      p_request_id => 'scheduler:legal-original-quarantine-cleanup',
      p_correlation_id => p_correlation_id, p_auth_assurance => 'service'
    );
    insert into public.legal_original_quarantine_cleanups (
      id, workspace_id, upload_session_id, reason, job_id,
      outbox_event_id, queued_audit_event_id
    ) values (
      new_cleanup_id, due.workspace_id, due.id, normalized_reason,
      queued.job_id, queued.outbox_event_id, new_audit_id
    );
    cleanup_id := new_cleanup_id;
    upload_session_id := due.id;
    cleanup_reason := normalized_reason;
    job_id := queued.job_id;
    outbox_event_id := queued.outbox_event_id;
    return next;
  end loop;
end; $$;

create function app.load_legal_original_quarantine_cleanup(
  p_workspace_id uuid, p_upload_session_id uuid, p_job_id uuid,
  p_worker_id text, p_lease_token uuid, p_attempt_number integer
)
returns table (
  cleanup_id uuid, cleanup_reason text, storage_bucket text,
  storage_object_key text, already_deleted boolean
)
language plpgsql security definer set search_path = '' as $$
declare target_job public.jobs%rowtype; target public.legal_original_quarantine_cleanups%rowtype;
begin
  select job.* into target_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id for update;
  if not found or target_job.job_type <> 'media.delete_legal_original_quarantine'
    or target_job.entity_type <> 'legal_original_upload_session'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running' or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using errcode = '55000', message = 'only the active legal cleanup lease can load an object';
  end if;
  select cleanup.* into target from public.legal_original_quarantine_cleanups cleanup
  where cleanup.workspace_id = p_workspace_id
    and cleanup.upload_session_id = p_upload_session_id
    and cleanup.job_id = p_job_id;
  if not found or (target.status not in ('deleted', 'not_found')
    and not app.legal_original_quarantine_cleanup_still_safe(p_workspace_id, target.id)) then
    raise exception using errcode = '55000', message = 'legal quarantine cleanup is unavailable or unsafe';
  end if;
  return query select target.id, target.reason, upload.upload_bucket,
    upload.upload_object_key, target.status in ('deleted', 'not_found')
  from public.legal_original_upload_sessions upload
  where upload.workspace_id = p_workspace_id and upload.id = p_upload_session_id;
end; $$;

create function app.fence_legal_original_quarantine_cleanup(
  p_workspace_id uuid, p_upload_session_id uuid, p_job_id uuid,
  p_worker_id text, p_lease_token uuid, p_attempt_number integer,
  p_observed_mime_type text, p_observed_byte_size bigint,
  p_observed_checksum_sha256 text, p_storage_generation text
)
returns table (cleanup_id uuid, replayed boolean)
language plpgsql security definer set search_path = '' as $$
declare target_job public.jobs%rowtype; target public.legal_original_quarantine_cleanups%rowtype;
begin
  if pg_catalog.btrim(coalesce(p_observed_mime_type, '')) = ''
    or p_observed_byte_size not between 1 and 50000000
    or p_observed_checksum_sha256 !~ '^[a-f0-9]{64}$'
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_storage_generation, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid legal quarantine object fence';
  end if;
  select job.* into target_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id for update;
  if not found or target_job.job_type <> 'media.delete_legal_original_quarantine'
    or target_job.entity_type <> 'legal_original_upload_session'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using errcode = '55000', message = 'only the active legal cleanup lease can fence an object';
  end if;
  select cleanup.* into target from public.legal_original_quarantine_cleanups cleanup
  where cleanup.workspace_id = p_workspace_id
    and cleanup.upload_session_id = p_upload_session_id
    and cleanup.job_id = p_job_id for update;
  if not found or not app.legal_original_quarantine_cleanup_still_safe(p_workspace_id, target.id) then
    raise exception using errcode = '55000', message = 'legal quarantine cleanup is no longer safe';
  end if;
  if target.status = 'fenced' then
    if target.observed_mime_type <> p_observed_mime_type
      or target.observed_byte_size <> p_observed_byte_size
      or target.observed_checksum_sha256 <> p_observed_checksum_sha256
      or target.storage_generation <> pg_catalog.btrim(p_storage_generation) then
      raise exception using errcode = '23505', message = 'legal quarantine fence replay conflicts';
    end if;
    return query select target.id, true; return;
  end if;
  if target.status <> 'queued' then
    raise exception using errcode = '55000', message = 'legal quarantine cleanup is terminal';
  end if;
  update public.legal_original_quarantine_cleanups cleanup set
    status = 'fenced', observed_mime_type = p_observed_mime_type,
    observed_byte_size = p_observed_byte_size,
    observed_checksum_sha256 = p_observed_checksum_sha256,
    storage_generation = pg_catalog.btrim(p_storage_generation)
  where cleanup.workspace_id = p_workspace_id and cleanup.id = target.id;
  return query select target.id, false;
end; $$;

create function app.complete_legal_original_quarantine_cleanup(
  p_workspace_id uuid, p_upload_session_id uuid, p_job_id uuid,
  p_worker_id text, p_lease_token uuid, p_attempt_number integer,
  p_storage_result text, p_observed_checksum_sha256 text,
  p_request_id text, p_correlation_id uuid
)
returns table (cleanup_id uuid, cleanup_status text, replayed boolean)
language plpgsql security definer set search_path = '' as $$
declare
  target_job public.jobs%rowtype;
  target public.legal_original_quarantine_cleanups%rowtype;
  new_status text;
  next_aggregate_version bigint;
  new_audit uuid; new_outbox uuid;
begin
  if p_storage_result not in ('deleted', 'not_found') or p_correlation_id is null
    or (p_storage_result = 'deleted' and p_observed_checksum_sha256 !~ '^[a-f0-9]{64}$')
    or (p_storage_result = 'not_found' and p_observed_checksum_sha256 is not null) then
    raise exception using errcode = '22023', message = 'invalid legal quarantine cleanup completion';
  end if;
  select job.* into target_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id for update;
  if not found or target_job.job_type <> 'media.delete_legal_original_quarantine'
    or target_job.entity_type <> 'legal_original_upload_session'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number
    or target_job.correlation_id <> p_correlation_id then
    raise exception using errcode = '55000', message = 'only the active legal cleanup lease can complete deletion';
  end if;
  select cleanup.* into target from public.legal_original_quarantine_cleanups cleanup
  where cleanup.workspace_id = p_workspace_id
    and cleanup.upload_session_id = p_upload_session_id
    and cleanup.job_id = p_job_id for update;
  if not found then raise exception using errcode = '55000', message = 'legal quarantine cleanup is unavailable'; end if;
  if target.status in ('deleted', 'not_found') then
    if target.storage_result <> p_storage_result
      or target.observed_checksum_sha256 is distinct from p_observed_checksum_sha256 then
      raise exception using errcode = '23505', message = 'legal quarantine cleanup replay conflicts';
    end if;
    return query select target.id, target.status, true; return;
  end if;
  if not app.legal_original_quarantine_cleanup_still_safe(p_workspace_id, target.id)
    or (p_storage_result = 'deleted' and (
      target.status <> 'fenced'
      or target.observed_checksum_sha256 <> p_observed_checksum_sha256))
    or (p_storage_result = 'not_found' and target.status <> 'queued') then
    raise exception using errcode = '55000', message = 'legal quarantine cleanup is no longer safe';
  end if;
  new_status := p_storage_result;
  select coalesce(pg_catalog.max(event.aggregate_version), 0) + 1
    into next_aggregate_version
  from public.outbox_events event
  where event.workspace_id = p_workspace_id
    and event.aggregate_type = 'legal_original_upload_session'
    and event.aggregate_id = p_upload_session_id;
  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id, aggregate_version,
    payload_schema_version, payload, correlation_id, causation_id
  ) values (
    p_workspace_id, 'media.legal_original_quarantine_cleanup_completed',
    'legal_original_upload_session', p_upload_session_id,
    next_aggregate_version, 1,
    pg_catalog.jsonb_build_object('upload_session_id', p_upload_session_id,
      'cleanup_id', target.id, 'reason', target.reason,
      'storage_result', p_storage_result),
    p_correlation_id, target.outbox_event_id
  ) returning id into new_outbox;
  new_audit := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.legal_original_quarantine_cleanup_completed',
    p_entity_type => 'legal_original_upload_session', p_entity_id => p_upload_session_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object('cleanup_status', target.status),
    p_after_data => pg_catalog.jsonb_build_object('cleanup_status', new_status,
      'cleanup_id', target.id, 'storage_result', p_storage_result),
    p_request_id => p_request_id, p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object('job_id', p_job_id,
      'worker_id', p_worker_id, 'attempt_number', p_attempt_number,
      'outbox_event_id', new_outbox)
  );
  update public.legal_original_quarantine_cleanups cleanup set
    status = new_status, storage_result = p_storage_result,
    completion_audit_event_id = new_audit,
    completion_outbox_event_id = new_outbox,
    completed_at = pg_catalog.statement_timestamp()
  where cleanup.workspace_id = p_workspace_id and cleanup.id = target.id;
  return query select target.id, new_status, false;
end; $$;

revoke all on table public.legal_original_upload_sessions from public, anon, authenticated, service_role;
grant select on table public.legal_original_upload_sessions to authenticated;
grant select on table public.legal_original_upload_sessions to service_role;
revoke all on table public.legal_original_quarantine_cleanups from public, anon, authenticated, service_role;
grant select on table public.legal_original_quarantine_cleanups to service_role;

revoke all on function app.create_legal_original_upload_session(
  uuid, text, uuid, text, text, text, bigint, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.request_legal_original_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.load_legal_original_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer
) from public, anon, authenticated, service_role;
revoke all on function app.complete_legal_original_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, bigint, text, text, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.reject_legal_original_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.legal_original_quarantine_cleanup_still_safe(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.enqueue_due_legal_original_quarantine_cleanup(integer, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.load_legal_original_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer
) from public, anon, authenticated, service_role;
revoke all on function app.fence_legal_original_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer, text, bigint, text, text
) from public, anon, authenticated, service_role;
revoke all on function app.complete_legal_original_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.create_legal_original_upload_session(
  uuid, text, uuid, text, text, text, bigint, text, text, uuid
) to authenticated;
grant execute on function app.request_legal_original_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) to authenticated;
grant execute on function app.load_legal_original_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer
) to service_role;
grant execute on function app.complete_legal_original_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, bigint, text, text, jsonb, text, uuid
) to service_role;
grant execute on function app.reject_legal_original_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) to service_role;
grant execute on function app.enqueue_due_legal_original_quarantine_cleanup(integer, uuid)
  to service_role;
grant execute on function app.load_legal_original_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer
) to service_role;
grant execute on function app.fence_legal_original_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer, text, bigint, text, text
) to service_role;
grant execute on function app.complete_legal_original_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) to service_role;

comment on table public.legal_original_upload_sessions is
  'Document-owned exact upload intents; worker verification preserves original bytes and immutable provider provenance.';
comment on table public.legal_original_quarantine_cleanups is
  'Durable exact-key cleanup lineage for expired or rejected unaccepted originals; completed preserved originals never qualify.';
comment on function app.enqueue_due_legal_original_quarantine_cleanup(integer, uuid) is
  'Service-only bounded producer that expires abandoned intents and queues cleanup for unaccepted quarantine objects.';
