-- M2 / R2-MEDIA-002, R2-MEDIA-003
-- A browser may upload only to its exact, unexpired quarantine intent. A
-- durable worker then verifies the stored object before the existing trusted
-- completion command can enqueue image processing.

alter table public.media_upload_sessions
  add column verification_job_id uuid,
  add column verification_outbox_event_id uuid,
  add column verification_audit_event_id uuid,
  add column verification_requested_at timestamptz,
  add foreign key (workspace_id, verification_job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  add foreign key (workspace_id, verification_outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  add constraint media_upload_sessions_verification_shape_check check (
    (
      verification_job_id is null
      and verification_outbox_event_id is null
      and verification_audit_event_id is null
      and verification_requested_at is null
    )
    or (
      verification_job_id is not null
      and verification_outbox_event_id is not null
      and verification_audit_event_id is not null
      and verification_requested_at is not null
    )
  );

create policy managed_media_uploads_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media-private'
  and exists (
    select 1
    from public.media_upload_sessions upload
    where upload.quarantine_bucket = storage.objects.bucket_id
      and upload.quarantine_object_key = storage.objects.name
      and upload.created_by = auth.uid()
      and upload.status = 'awaiting_upload'
      and upload.expires_at > pg_catalog.statement_timestamp()
      and upload.verification_job_id is null
      and app.has_permission(upload.workspace_id, 'media.create')
  )
);

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
        || normalized_idempotency_key,
      0
    )
  );

  select receipt.* into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
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

create function app.load_vehicle_photo_upload_verification(
  p_workspace_id uuid,
  p_media_id uuid,
  p_upload_session_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer
)
returns table (
  media_id uuid,
  upload_session_id uuid,
  actor_user_id uuid,
  upload_bucket text,
  upload_object_key text,
  expected_mime_type text,
  expected_byte_size bigint,
  expected_checksum_sha256 text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  target_upload public.media_upload_sessions%rowtype;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_worker_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    or p_lease_token is null
    or p_attempt_number is null or p_attempt_number < 1 then
    raise exception using errcode = '22023', message = 'invalid media verification worker identity';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;

  if not found
    or target_job.job_type <> 'media.verify_vehicle_photo_upload'
    or target_job.entity_type <> 'media_upload_session'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using
      errcode = '55000',
      message = 'only the active media verification lease can load an upload';
  end if;

  select upload.* into target_upload
  from public.media_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id
    and upload.media_id = p_media_id
    and upload.verification_job_id = p_job_id;

  if not found
    or target_upload.status <> 'awaiting_upload'
    or target_upload.expires_at <= pg_catalog.statement_timestamp() then
    raise exception using errcode = '55000', message = 'media upload cannot be verified';
  end if;

  return query select
    p_media_id, p_upload_session_id, target_upload.created_by,
    target_upload.quarantine_bucket, target_upload.quarantine_object_key,
    target_upload.expected_mime_type, target_upload.expected_byte_size,
    target_upload.expected_checksum_sha256, target_upload.expires_at;
end;
$$;

create function app.complete_vehicle_photo_upload_verification(
  p_workspace_id uuid,
  p_media_id uuid,
  p_upload_session_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_observed_mime_type text,
  p_observed_byte_size bigint,
  p_observed_checksum_sha256 text,
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
  target_job public.jobs%rowtype;
  target_upload public.media_upload_sessions%rowtype;
begin
  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;

  if not found
    or target_job.job_type <> 'media.verify_vehicle_photo_upload'
    or target_job.entity_type <> 'media_upload_session'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using
      errcode = '55000',
      message = 'only the active media verification lease can complete an upload';
  end if;

  select upload.* into target_upload
  from public.media_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id
    and upload.media_id = p_media_id
    and upload.verification_job_id = p_job_id;

  if not found then
    raise exception using errcode = '55000', message = 'media upload verification is unavailable';
  end if;

  return query
  select completed.*
  from app.complete_vehicle_photo_upload(
    p_workspace_id => p_workspace_id,
    p_actor_user_id => target_upload.created_by,
    p_idempotency_key => 'media:verify-complete:' || p_job_id::text,
    p_media_id => p_media_id,
    p_upload_session_id => p_upload_session_id,
    p_observed_mime_type => p_observed_mime_type,
    p_observed_byte_size => p_observed_byte_size,
    p_observed_checksum_sha256 => p_observed_checksum_sha256,
    p_signature_verified => true,
    p_width => p_width,
    p_height => p_height,
    p_exif_orientation => p_exif_orientation,
    p_malware_scan_receipt => p_malware_scan_receipt,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id
  ) completed;
end;
$$;

create function app.reject_vehicle_photo_upload_verification(
  p_workspace_id uuid,
  p_media_id uuid,
  p_upload_session_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_error_code text,
  p_error_classification text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  media_id uuid,
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
  target_job public.jobs%rowtype;
  target_media public.media_assets%rowtype;
  next_media_version bigint;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  if p_error_classification not in ('permanent', 'validation', 'permission', 'provider_auth')
    or pg_catalog.btrim(coalesce(p_error_code, '')) = ''
    or pg_catalog.char_length(p_error_code) > 120
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid terminal media verification failure';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if not found
    or target_job.job_type <> 'media.verify_vehicle_photo_upload'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using errcode = '55000', message = 'only the active media verification lease can reject an upload';
  end if;
  if not exists (
    select 1 from public.media_upload_sessions upload
    where upload.workspace_id = p_workspace_id
      and upload.id = p_upload_session_id
      and upload.media_id = p_media_id
      and upload.verification_job_id = p_job_id
  ) then
    raise exception using errcode = '55000', message = 'media upload verification is unavailable';
  end if;

  select asset.* into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id and asset.id = p_media_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'media was not found';
  end if;
  if target_media.status = 'failed' then
    return query select p_media_id, 'failed'::text, target_media.version,
      true, null::uuid, null::uuid;
    return;
  end if;
  if target_media.status <> 'awaiting_upload' then
    raise exception using errcode = '55000', message = 'media cannot be rejected from its current state';
  end if;

  next_media_version := target_media.version + 1;
  update public.media_assets asset
  set status = 'failed', version = next_media_version,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id and asset.id = p_media_id;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, correlation_id
  ) values (
    p_workspace_id, 'media.upload_rejected', 'media_asset', p_media_id,
    next_media_version, 1,
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'upload_session_id', p_upload_session_id,
      'job_id', p_job_id,
      'error_code', p_error_code,
      'error_classification', p_error_classification
    ),
    p_correlation_id
  ) returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.upload_rejected',
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', target_media.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'failed',
      'version', next_media_version
    ),
    p_reason => p_error_code,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'worker_id', p_worker_id,
      'job_id', p_job_id,
      'attempt_number', p_attempt_number,
      'error_classification', p_error_classification,
      'outbox_event_id', new_outbox_event_id
    )
  );

  return query select p_media_id, 'failed'::text, next_media_version,
    false, new_audit_event_id, new_outbox_event_id;
end;
$$;

revoke all on function app.request_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.load_vehicle_photo_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer
) from public, anon, authenticated, service_role;
revoke all on function app.complete_vehicle_photo_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, bigint, text,
  integer, integer, integer, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.reject_vehicle_photo_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.request_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) to authenticated;
grant execute on function app.load_vehicle_photo_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer
) to service_role;
grant execute on function app.complete_vehicle_photo_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, bigint, text,
  integer, integer, integer, jsonb, text, uuid
) to service_role;
grant execute on function app.reject_vehicle_photo_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) to service_role;

comment on function app.request_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) is 'Authenticated exact-upload handoff to a durable server verification job; clients never attest MIME, checksum, dimensions, or malware status.';
