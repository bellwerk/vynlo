-- M2-MEDIA-AC-026: owner-safe legal-original verification visibility and
-- reasoned manual recovery from an exhausted durable verification job.
-- Browser roles continue to receive no table access, provider coordinates,
-- checksums, scan receipts, or worker/provider error detail.

create function app.get_legal_original_upload_status(
  p_workspace_id uuid,
  p_document_id uuid,
  p_upload_session_id uuid
)
returns table (
  upload_session_id uuid,
  document_id uuid,
  media_kind text,
  status text,
  job_id uuid,
  attempt_count integer,
  maximum_attempts integer,
  retry_at timestamptz,
  retryable boolean,
  error_classification text,
  error_code text,
  completed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_upload public.legal_original_upload_sessions%rowtype;
  target_job public.jobs%rowtype;
  projected_status text;
begin
  actor_user_id := auth.uid();

  select upload.*
    into target_upload
  from public.legal_original_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.document_id = p_document_id
    and upload.id = p_upload_session_id
    and upload.created_by = actor_user_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'legal upload intent was not found';
  end if;

  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    case
      when target_upload.media_kind = 'signed_document'
        then 'documents.upload_signed'
      else 'media.create'
    end,
    target_upload.media_kind = 'signed_document'
  );

  if target_upload.created_by is distinct from actor_user_id then
    raise exception using
      errcode = 'P0002',
      message = 'legal upload intent was not found';
  end if;

  if target_upload.verification_job_id is not null then
    select job.*
      into target_job
    from public.jobs job
    where job.workspace_id = target_upload.workspace_id
      and job.id = target_upload.verification_job_id
      and job.job_type = 'media.verify_legal_original'
      and job.entity_type = 'document'
      and job.entity_id = target_upload.document_id
      and job.payload = pg_catalog.jsonb_build_object(
        'upload_session_id', target_upload.id
      );

    if not found then
      raise exception using
        errcode = '55000',
        message = 'legal upload verification state is unavailable';
    end if;
  end if;

  projected_status := case target_upload.status
    when 'completed' then 'completed'
    when 'rejected' then 'rejected'
    when 'expired' then 'rejected'
    when 'awaiting_upload' then 'awaiting_upload'
    when 'verification_requested' then case target_job.status
      when 'queued' then 'queued'
      when 'running' then 'running'
      when 'retry_wait' then 'retry_wait'
      when 'dead_letter' then 'dead_letter'
      when 'succeeded' then 'completed'
      else 'rejected'
    end
    else 'rejected'
  end;

  return query
  select
    target_upload.id,
    target_upload.document_id,
    target_upload.media_kind,
    projected_status,
    target_job.id,
    pg_catalog.coalesce(target_job.attempts_started, 0),
    target_job.max_attempts,
    case
      when target_job.status = 'retry_wait' then target_job.available_at
      else null
    end,
    target_upload.status = 'verification_requested'
      and target_job.status = 'dead_letter',
    case
      when projected_status in ('retry_wait', 'dead_letter', 'rejected')
        then target_job.last_error_classification
      else null
    end,
    case
      when target_upload.status = 'rejected'
        and target_upload.rejection_code ~ '^[a-z][a-z0-9_.-]{0,119}$'
        then target_upload.rejection_code
      when target_upload.status = 'rejected'
        then 'media.verification_rejected'
      when target_upload.status = 'expired' then 'media.upload_intent_expired'
      when projected_status in ('retry_wait', 'dead_letter')
        and target_job.last_error_code ~ '^[a-z][a-z0-9_.-]{0,119}$'
        then target_job.last_error_code
      when projected_status in ('retry_wait', 'dead_letter')
        then 'media.verification_failed'
      when target_upload.status = 'verification_requested'
        and target_job.status = 'cancelled'
        then 'media.verification_cancelled'
      when projected_status = 'rejected' then 'media.verification_failed'
      else null
    end,
    target_upload.completed_at;
end;
$$;

create function app.retry_legal_original_upload_verification(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_document_id uuid,
  p_upload_session_id uuid,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  upload_session_id uuid,
  document_id uuid,
  source_job_id uuid,
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
  target_upload public.legal_original_upload_sessions%rowtype;
  source_job public.jobs%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  existing_job public.jobs%rowtype;
  normalized_key text := pg_catalog.btrim(
    pg_catalog.coalesce(p_idempotency_key, '')
  );
  normalized_reason text := pg_catalog.btrim(pg_catalog.coalesce(p_reason, ''));
  fingerprint text;
  aggregate_version bigint;
  queued record;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  if p_workspace_id is null
    or p_document_id is null
    or p_upload_session_id is null
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or pg_catalog.char_length(normalized_reason) not between 1 and 2000
    or p_correlation_id is null
    or (
      p_request_id is not null
      and pg_catalog.char_length(p_request_id) > 200
    ) then
    raise exception using
      errcode = '22023',
      message = 'legal verification retry requires a safe reason and correlation ID';
  end if;

  actor_user_id := auth.uid();

  select upload.*
    into target_upload
  from public.legal_original_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.document_id = p_document_id
    and upload.id = p_upload_session_id
    and upload.created_by = actor_user_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'legal upload intent was not found';
  end if;

  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id,
    case
      when target_upload.media_kind = 'signed_document'
        then 'documents.upload_signed'
      else 'media.create'
    end,
    target_upload.media_kind = 'signed_document'
  );

  if target_upload.created_by is distinct from actor_user_id then
    raise exception using
      errcode = 'P0002',
      message = 'legal upload intent was not found';
  end if;

  fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'document_id', p_document_id,
      'upload_session_id', p_upload_session_id,
      'reason', normalized_reason
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text
        || E'\x1fmedia.retry_legal_verify\x1f'
        || actor_user_id::text
        || E'\x1f'
        || normalized_key,
      0
    )
  );

  select receipt.*
    into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = actor_user_id
    and receipt.command_type = 'media.retry_legal_verify'
    and receipt.idempotency_key = normalized_key;

  if found then
    if existing_receipt.request_fingerprint <> fingerprint then
      raise exception using
        errcode = '23505',
        message = 'legal verification retry replay conflicts';
    end if;

    select job.*
      into existing_job
    from public.jobs job
    where job.workspace_id = p_workspace_id
      and job.id = (existing_receipt.result ->> 'job_id')::uuid;

    if not found then
      raise exception using
        errcode = '55000',
        message = 'legal verification retry receipt is unavailable';
    end if;

    return query
    select
      (existing_receipt.result ->> 'upload_session_id')::uuid,
      (existing_receipt.result ->> 'document_id')::uuid,
      (existing_receipt.result ->> 'source_job_id')::uuid,
      existing_job.id,
      existing_job.status,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      existing_job.outbox_event_id;
    return;
  end if;

  if target_upload.status <> 'verification_requested' then
    raise exception using
      errcode = '55000',
      message = 'only an active legal verification can be retried';
  end if;

  select job.*
    into source_job
  from public.jobs job
  where job.workspace_id = target_upload.workspace_id
    and job.id = target_upload.verification_job_id
    and job.job_type = 'media.verify_legal_original'
    and job.entity_type = 'document'
    and job.entity_id = target_upload.document_id
    and job.payload = pg_catalog.jsonb_build_object(
      'upload_session_id', target_upload.id
    )
  for update;

  if not found or source_job.status <> 'dead_letter' then
    raise exception using
      errcode = '55000',
      message = 'only a dead-letter legal verification job can be manually retried';
  end if;

  select pg_catalog.coalesce(pg_catalog.max(event.aggregate_version), 0) + 1
    into aggregate_version
  from public.outbox_events event
  where event.workspace_id = p_workspace_id
    and event.aggregate_type = 'legal_original_upload_session'
    and event.aggregate_id = p_upload_session_id;

  select result.*
    into queued
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'media.legal_original_verification_retry_requested',
    p_aggregate_type => 'legal_original_upload_session',
    p_aggregate_id => p_upload_session_id,
    p_aggregate_version => aggregate_version,
    p_job_type => source_job.job_type,
    p_entity_type => source_job.entity_type,
    p_entity_id => source_job.entity_id,
    p_payload_schema_version => source_job.payload_schema_version,
    p_payload => source_job.payload,
    p_idempotency_key => 'media:retry-legal:'
      || p_upload_session_id::text || ':' || source_job.id::text,
    p_correlation_id => p_correlation_id,
    p_causation_id => source_job.outbox_event_id,
    p_actor_user_id => actor_user_id,
    p_priority => source_job.priority,
    p_max_attempts => source_job.max_attempts,
    p_backoff_base_seconds => source_job.backoff_base_seconds,
    p_backoff_max_seconds => source_job.backoff_max_seconds,
    p_replay_of_job_id => source_job.id,
    p_request_id => p_request_id
  ) result;

  if not queued.created then
    raise exception using
      errcode = '55000',
      message = 'legal verification retry job already exists without a receipt';
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.legal_original_verification_retry_requested',
    p_entity_type => 'legal_original_upload_session',
    p_entity_id => p_upload_session_id,
    p_actor_type => 'user',
    p_actor_user_id => actor_user_id,
    p_before_data => pg_catalog.jsonb_build_object(
      'job_id', source_job.id,
      'job_status', source_job.status
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'job_id', queued.job_id,
      'job_status', queued.job_status
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => case
      when target_upload.media_kind = 'signed_document' then 'step_up'
      else 'session'
    end,
    p_metadata => pg_catalog.jsonb_build_object(
      'source_job_id', source_job.id,
      'job_id', queued.job_id,
      'outbox_event_id', queued.outbox_event_id,
      'causation_id', source_job.outbox_event_id,
      'replay_of_job_id', source_job.id
    )
  );

  update public.legal_original_upload_sessions upload
  set verification_job_id = queued.job_id,
      verification_outbox_event_id = queued.outbox_event_id,
      verification_audit_event_id = new_audit_event_id,
      verification_requested_at = pg_catalog.statement_timestamp()
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id;

  result_payload := pg_catalog.jsonb_build_object(
    'upload_session_id', p_upload_session_id,
    'document_id', p_document_id,
    'source_job_id', source_job.id,
    'job_id', queued.job_id,
    'job_status', queued.job_status,
    'audit_event_id', new_audit_event_id,
    'outbox_event_id', queued.outbox_event_id
  );

  insert into public.media_command_receipts (
    workspace_id,
    command_type,
    idempotency_key,
    request_fingerprint,
    result,
    actor_user_id
  ) values (
    p_workspace_id,
    'media.retry_legal_verify',
    normalized_key,
    fingerprint,
    result_payload,
    actor_user_id
  );

  return query
  select
    p_upload_session_id,
    p_document_id,
    source_job.id,
    queued.job_id,
    queued.job_status,
    false,
    new_audit_event_id,
    queued.outbox_event_id;
end;
$$;

drop policy if exists legal_original_upload_sessions_select
  on public.legal_original_upload_sessions;
revoke select on table public.legal_original_upload_sessions
  from public, anon, authenticated;

revoke all on function app.get_legal_original_upload_status(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.retry_legal_original_upload_verification(
  uuid, text, uuid, uuid, text, text, uuid
)
  from public, anon, authenticated, service_role;

grant execute on function app.get_legal_original_upload_status(uuid, uuid, uuid)
  to authenticated;
grant execute on function app.retry_legal_original_upload_verification(
  uuid, text, uuid, uuid, text, text, uuid
)
  to authenticated;

comment on function app.get_legal_original_upload_status(uuid, uuid, uuid) is
  'Owner-only browser projection of legal-original verification state and bounded safe failure fields; inaccessible and absent identifiers share not-found semantics, and no object coordinates, checksums, receipts, or error detail are returned.';
comment on function app.retry_legal_original_upload_verification(
  uuid, text, uuid, uuid, text, text, uuid
) is
  'Owner-only reasoned retry of the active dead-letter legal-original verification job with actor-scoped raw command-key replay and copied bounded job policy; inaccessible and absent identifiers share not-found semantics.';
