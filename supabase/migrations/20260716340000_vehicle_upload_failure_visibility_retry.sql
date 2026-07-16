-- M2-MEDIA-AC-027: owner-safe vehicle-upload verification visibility and
-- reasoned manual recovery from an exhausted durable verification job.
-- Browser roles receive no object coordinates, checksums, scan receipts, or
-- worker/provider error detail.

-- Preserve the actor-key implementation for exact initial-command replay, but
-- place a final state guard in front of it so a new completion command cannot
-- become an unreasoned dead-letter retry.
alter function app.request_vehicle_photo_upload_verification_actor_key_impl(
  uuid, text, uuid, uuid, text, uuid
) rename to request_vehicle_photo_upload_verification_pre_retry_impl;

revoke all on function app.request_vehicle_photo_upload_verification_pre_retry_impl(
  uuid, text, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;

create function app.request_vehicle_photo_upload_verification_actor_key_impl(
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
  target_upload public.media_upload_sessions%rowtype;
  target_job public.jobs%rowtype;
  existing_receipt public.media_command_receipts%rowtype;
  normalized_key text := pg_catalog.btrim(
    pg_catalog.coalesce(p_idempotency_key, '')
  );
  request_fingerprint text;
  current_media_version bigint;
  result_payload jsonb;
begin
  actor_user_id := app.require_media_permission(p_workspace_id, 'media.create');

  if pg_catalog.char_length(normalized_key) not between 8 and 200
    or p_media_id is null
    or p_upload_session_id is null
    or p_correlation_id is null
    or (
      p_request_id is not null
      and pg_catalog.char_length(p_request_id) > 200
    ) then
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
        || normalized_key,
      0
    )
  );

  -- Existing actor-scoped receipts must remain replayable even after the job
  -- later dead-letters or the aggregate reaches a terminal state. The preserved
  -- implementation performs the fingerprint conflict check and exact replay.
  select receipt.*
    into existing_receipt
  from public.media_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = actor_user_id
    and receipt.command_type = 'media.request_upload_verification'
    and receipt.idempotency_key = normalized_key;

  if found then
    return query
    select result.*
    from app.request_vehicle_photo_upload_verification_pre_retry_impl(
      p_workspace_id,
      normalized_key,
      p_media_id,
      p_upload_session_id,
      p_request_id,
      p_correlation_id
    ) result;
    return;
  end if;

  select upload.*
    into target_upload
  from public.media_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id
    and upload.media_id = p_media_id
    and upload.created_by = actor_user_id
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'media upload intent is not owned by the actor';
  end if;

  if target_upload.verification_job_id is not null then
    select job.*
      into target_job
    from public.jobs job
    where job.workspace_id = target_upload.workspace_id
      and job.id = target_upload.verification_job_id
      and job.job_type = 'media.verify_vehicle_photo_upload'
      and job.entity_type = 'media_upload_session'
      and job.entity_id = target_upload.id
      and job.payload = pg_catalog.jsonb_build_object(
        'media_id', target_upload.media_id,
        'upload_session_id', target_upload.id
      );

    if not found then
      raise exception using
        errcode = '55000',
        message = 'vehicle upload verification state is unavailable';
    end if;

    if target_job.status = 'dead_letter' then
      raise exception using
        errcode = '55000',
        message = 'dead-letter vehicle verification requires the reasoned retry command';
    end if;

    if target_job.status = 'cancelled' then
      raise exception using
        errcode = '55000',
        message = 'cancelled vehicle verification requires a new upload';
    end if;

    if target_job.status in ('queued', 'running', 'retry_wait', 'succeeded') then
      select asset.version
        into current_media_version
      from public.media_assets asset
      where asset.workspace_id = p_workspace_id
        and asset.id = p_media_id
        and asset.media_kind = 'vehicle_photo';

      if not found then
        raise exception using
          errcode = '55000',
          message = 'vehicle upload state is unavailable';
      end if;

      result_payload := pg_catalog.jsonb_build_object(
        'media_id', p_media_id,
        'upload_session_id', p_upload_session_id,
        'job_id', target_job.id,
        'job_status', target_job.status,
        'aggregate_version', current_media_version,
        'audit_event_id', target_upload.verification_audit_event_id,
        'outbox_event_id', target_upload.verification_outbox_event_id
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
        'media.request_upload_verification',
        normalized_key,
        request_fingerprint,
        result_payload,
        actor_user_id
      );

      return query
      select
        p_media_id,
        p_upload_session_id,
        target_job.id,
        target_job.status,
        current_media_version,
        true,
        target_upload.verification_audit_event_id,
        target_upload.verification_outbox_event_id;
      return;
    end if;
  end if;

  return query
  select result.*
  from app.request_vehicle_photo_upload_verification_pre_retry_impl(
    p_workspace_id,
    normalized_key,
    p_media_id,
    p_upload_session_id,
    p_request_id,
    p_correlation_id
  ) result;
end;
$$;

revoke all on function app.request_vehicle_photo_upload_verification_actor_key_impl(
  uuid, text, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;

comment on function app.request_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, uuid
) is
  'Actor-scoped idempotent initial vehicle-photo verification request; exact command receipts replay, but new commands cannot bypass the reasoned dead-letter retry boundary.';

create function app.get_vehicle_photo_upload_status(
  p_workspace_id uuid,
  p_media_id uuid,
  p_upload_session_id uuid
)
returns table (
  upload_session_id uuid,
  media_id uuid,
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
  target_upload public.media_upload_sessions%rowtype;
  target_media public.media_assets%rowtype;
  target_job public.jobs%rowtype;
  projected_status text;
begin
  actor_user_id := auth.uid();

  select upload.*
    into target_upload
  from public.media_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.media_id = p_media_id
    and upload.id = p_upload_session_id
    and upload.created_by = actor_user_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'vehicle upload intent was not found';
  end if;

  actor_user_id := app.require_media_permission(p_workspace_id, 'media.create');
  if target_upload.created_by is distinct from actor_user_id then
    raise exception using
      errcode = 'P0002',
      message = 'vehicle upload intent was not found';
  end if;

  select asset.*
    into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo';

  if not found then
    raise exception using
      errcode = '55000',
      message = 'vehicle upload state is unavailable';
  end if;

  if target_upload.verification_job_id is not null then
    select job.*
      into target_job
    from public.jobs job
    where job.workspace_id = target_upload.workspace_id
      and job.id = target_upload.verification_job_id
      and job.job_type = 'media.verify_vehicle_photo_upload'
      and job.entity_type = 'media_upload_session'
      and job.entity_id = target_upload.id
      and job.payload = pg_catalog.jsonb_build_object(
        'media_id', target_upload.media_id,
        'upload_session_id', target_upload.id
      );

    if not found then
      raise exception using
        errcode = '55000',
        message = 'vehicle upload verification state is unavailable';
    end if;
  end if;

  projected_status := case
    when target_upload.status = 'completed' then 'completed'
    when target_media.status = 'failed' then 'rejected'
    when target_upload.status = 'expired' then 'rejected'
    when target_upload.status <> 'awaiting_upload' then 'rejected'
    when target_job.id is null then 'awaiting_upload'
    when target_job.status = 'queued' then 'queued'
    when target_job.status = 'running' then 'running'
    when target_job.status = 'retry_wait' then 'retry_wait'
    when target_job.status = 'dead_letter' then 'dead_letter'
    when target_job.status = 'succeeded' then 'completed'
    else 'rejected'
  end;

  return query
  select
    target_upload.id,
    target_upload.media_id,
    projected_status,
    target_job.id,
    pg_catalog.coalesce(target_job.attempts_started, 0),
    target_job.max_attempts,
    case
      when target_job.status = 'retry_wait' then target_job.available_at
      else null
    end,
    pg_catalog.coalesce(
      target_upload.status = 'awaiting_upload'
        and target_media.status = 'awaiting_upload'
        and target_job.status = 'dead_letter',
      false
    ),
    case
      when projected_status in ('retry_wait', 'dead_letter')
        then target_job.last_error_classification
      else null
    end,
    case
      when target_media.status = 'failed' then 'media.verification_rejected'
      when target_upload.status = 'expired' then 'media.upload_intent_expired'
      when projected_status in ('retry_wait', 'dead_letter')
        and target_job.last_error_code ~ '^[a-z][a-z0-9_.-]{0,119}$'
        then target_job.last_error_code
      when projected_status in ('retry_wait', 'dead_letter')
        then 'media.verification_failed'
      when projected_status = 'rejected' then 'media.verification_rejected'
      else null
    end,
    target_upload.completed_at;
end;
$$;

create function app.retry_vehicle_photo_upload_verification(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_media_id uuid,
  p_upload_session_id uuid,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  upload_session_id uuid,
  media_id uuid,
  source_job_id uuid,
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
  target_upload public.media_upload_sessions%rowtype;
  target_media public.media_assets%rowtype;
  source_job public.jobs%rowtype;
  source_job_found boolean := false;
  existing_receipt public.media_command_receipts%rowtype;
  existing_job public.jobs%rowtype;
  normalized_key text := pg_catalog.btrim(
    pg_catalog.coalesce(p_idempotency_key, '')
  );
  normalized_reason text := pg_catalog.btrim(pg_catalog.coalesce(p_reason, ''));
  fingerprint text;
  next_media_version bigint;
  queued record;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  if p_workspace_id is null
    or p_media_id is null
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
      message = 'vehicle verification retry requires a safe reason and correlation ID';
  end if;

  actor_user_id := auth.uid();
  -- Probe ownership before permission evaluation so inaccessible and absent
  -- identifiers remain indistinguishable. Do not retain a row lock here: the
  -- new-command path below follows the worker-compatible job -> media -> upload
  -- order and revalidates this exact owner fence after all three locks.
  select owner_probe.*
    into target_upload
  from public.media_upload_sessions owner_probe
  where owner_probe.workspace_id = p_workspace_id
    and owner_probe.media_id = p_media_id
    and owner_probe.id = p_upload_session_id
    and owner_probe.created_by = actor_user_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'vehicle upload intent was not found';
  end if;

  actor_user_id := app.require_media_permission(p_workspace_id, 'media.create');
  if target_upload.created_by is distinct from actor_user_id then
    raise exception using
      errcode = 'P0002',
      message = 'vehicle upload intent was not found';
  end if;

  fingerprint := app.job_request_fingerprint(
    pg_catalog.jsonb_build_object(
      'media_id', p_media_id,
      'upload_session_id', p_upload_session_id,
      'reason', normalized_reason
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text
        || E'\x1fmedia.retry_upload_verify\x1f'
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
    and receipt.command_type = 'media.retry_upload_verify'
    and receipt.idempotency_key = normalized_key;

  if found then
    if existing_receipt.request_fingerprint <> fingerprint then
      raise exception using
        errcode = '23505',
        message = 'vehicle verification retry replay conflicts';
    end if;

    select job.*
      into existing_job
    from public.jobs job
    where job.workspace_id = p_workspace_id
      and job.id = (existing_receipt.result ->> 'job_id')::uuid;

    if not found then
      raise exception using
        errcode = '55000',
        message = 'vehicle verification retry receipt is unavailable';
    end if;

    return query
    select
      (existing_receipt.result ->> 'upload_session_id')::uuid,
      (existing_receipt.result ->> 'media_id')::uuid,
      (existing_receipt.result ->> 'source_job_id')::uuid,
      existing_job.id,
      existing_job.status,
      (existing_receipt.result ->> 'aggregate_version')::bigint,
      true,
      (existing_receipt.result ->> 'audit_event_id')::uuid,
      existing_job.outbox_event_id;
    return;
  end if;

  -- Terminal workers lock job -> media -> upload. Keep the same global order
  -- so a retry racing completion or rejection cannot deadlock.
  select job.*
    into source_job
  from public.jobs job
  where job.workspace_id = target_upload.workspace_id
    and job.id = target_upload.verification_job_id
    and job.job_type = 'media.verify_vehicle_photo_upload'
    and job.entity_type = 'media_upload_session'
    and job.entity_id = target_upload.id
    and job.payload = pg_catalog.jsonb_build_object(
      'media_id', target_upload.media_id,
      'upload_session_id', target_upload.id
    )
  for update;
  source_job_found := found;

  -- With no exact job there is nothing to retry. Fail before taking media or
  -- upload locks; the initial-request path locks upload before media while it
  -- creates the first job, so an invalid concurrent retry must not invert that
  -- separate no-job transition.
  if not source_job_found then
    raise exception using
      errcode = '55000',
      message = 'only a dead-letter vehicle verification job can be manually retried';
  end if;

  select asset.*
    into target_media
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id
    and asset.media_kind = 'vehicle_photo'
  for update;

  if not found then
    raise exception using
      errcode = '55000',
      message = 'vehicle upload state is unavailable';
  end if;

  -- Re-lock the exact owner fence last and revalidate any upload/job change
  -- that committed after the unlocked existence probe.
  select locked_upload.*
    into target_upload
  from public.media_upload_sessions locked_upload
  where locked_upload.workspace_id = p_workspace_id
    and locked_upload.media_id = p_media_id
    and locked_upload.id = p_upload_session_id
    and locked_upload.created_by = actor_user_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'vehicle upload intent was not found';
  end if;

  if target_upload.status <> 'awaiting_upload'
    or target_media.status <> 'awaiting_upload' then
    raise exception using
      errcode = '55000',
      message = 'only an active vehicle upload verification can be retried';
  end if;

  if target_upload.verification_job_id is distinct from source_job.id
    or source_job.status <> 'dead_letter' then
    raise exception using
      errcode = '55000',
      message = 'only a dead-letter vehicle verification job can be manually retried';
  end if;

  next_media_version := target_media.version + 1;
  select result.*
    into queued
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'media.upload_verification_retry_requested',
    p_aggregate_type => 'media_asset',
    p_aggregate_id => p_media_id,
    p_aggregate_version => next_media_version,
    p_job_type => source_job.job_type,
    p_entity_type => source_job.entity_type,
    p_entity_id => source_job.entity_id,
    p_payload_schema_version => source_job.payload_schema_version,
    p_payload => source_job.payload,
    p_idempotency_key => 'media:retry-upload:'
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
      message = 'vehicle verification retry job already exists without a receipt';
  end if;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'media.upload_verification_retry_requested',
    p_entity_type => 'media_asset',
    p_entity_id => p_media_id,
    p_actor_type => 'user',
    p_actor_user_id => actor_user_id,
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', target_media.version,
      'job_id', source_job.id,
      'job_status', source_job.status
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', target_media.status,
      'version', next_media_version,
      'job_id', queued.job_id,
      'job_status', queued.job_status
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => pg_catalog.coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'source_job_id', source_job.id,
      'job_id', queued.job_id,
      'outbox_event_id', queued.outbox_event_id,
      'causation_id', source_job.outbox_event_id,
      'replay_of_job_id', source_job.id
    )
  );

  update public.media_assets asset
  set version = next_media_version,
      updated_at = pg_catalog.statement_timestamp()
  where asset.workspace_id = p_workspace_id
    and asset.id = p_media_id;

  update public.media_upload_sessions upload
  set verification_job_id = queued.job_id,
      verification_outbox_event_id = queued.outbox_event_id,
      verification_audit_event_id = new_audit_event_id,
      verification_requested_at = pg_catalog.statement_timestamp()
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id;

  result_payload := pg_catalog.jsonb_build_object(
    'upload_session_id', p_upload_session_id,
    'media_id', p_media_id,
    'source_job_id', source_job.id,
    'job_id', queued.job_id,
    'job_status', queued.job_status,
    'aggregate_version', next_media_version,
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
    'media.retry_upload_verify',
    normalized_key,
    fingerprint,
    result_payload,
    actor_user_id
  );

  return query
  select
    p_upload_session_id,
    p_media_id,
    source_job.id,
    queued.job_id,
    queued.job_status,
    next_media_version,
    false,
    new_audit_event_id,
    queued.outbox_event_id;
end;
$$;

revoke all on function app.get_vehicle_photo_upload_status(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.retry_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, text, uuid
)
  from public, anon, authenticated, service_role;

grant execute on function app.get_vehicle_photo_upload_status(uuid, uuid, uuid)
  to authenticated;
grant execute on function app.retry_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, text, uuid
)
  to authenticated;

comment on function app.get_vehicle_photo_upload_status(uuid, uuid, uuid) is
  'Owner-only browser projection of vehicle-upload verification state and bounded safe failure fields; inaccessible and absent identifiers share not-found semantics, and no object coordinates, checksums, receipts, or error detail are returned.';
comment on function app.retry_vehicle_photo_upload_verification(
  uuid, text, uuid, uuid, text, text, uuid
) is
  'Owner-only reasoned retry of the active dead-letter vehicle-upload verification job with actor-scoped raw command-key replay and copied bounded job policy; inaccessible and absent identifiers share not-found semantics.';
