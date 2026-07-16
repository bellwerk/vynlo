-- M2 / R2-MEDIA-002, R2-MEDIA-003
-- Quarantine objects are deleted only by a durable, exact-key worker after the
-- database has fenced workspace, upload session, media generation, and source
-- checksum. Legal/document originals are deliberately outside this lifecycle.

create table public.media_quarantine_cleanups (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  upload_session_id uuid not null,
  media_id uuid not null,
  reason text not null check (
    reason in ('expired_intent', 'terminal_rejection', 'verified_raw_copy')
  ),
  processing_run_id uuid,
  generation integer not null check (generation > 0),
  expected_checksum_sha256 text check (
    expected_checksum_sha256 is null
    or expected_checksum_sha256 ~ '^[a-f0-9]{64}$'
  ),
  object_checksum_sha256 text check (
    object_checksum_sha256 is null
    or object_checksum_sha256 ~ '^[a-f0-9]{64}$'
  ),
  observed_byte_size bigint check (
    observed_byte_size is null or observed_byte_size between 1 and 50000000
  ),
  job_id uuid not null,
  outbox_event_id uuid not null,
  queued_audit_event_id uuid not null,
  status text not null default 'queued' check (
    status in ('queued', 'fenced', 'deleted', 'not_found')
  ),
  storage_result text check (storage_result in ('deleted', 'not_found')),
  fenced_at timestamptz,
  completed_at timestamptz,
  completion_audit_event_id uuid,
  completion_outbox_event_id uuid,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, upload_session_id),
  unique (workspace_id, job_id),
  foreign key (workspace_id, upload_session_id)
    references public.media_upload_sessions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, media_id)
    references public.media_assets (workspace_id, id) on delete restrict,
  foreign key (workspace_id, processing_run_id)
    references public.media_processing_runs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, completion_outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  constraint media_quarantine_cleanups_reason_shape_check check (
    (
      reason = 'verified_raw_copy'
      and processing_run_id is not null
      and expected_checksum_sha256 is not null
    )
    or (
      reason in ('expired_intent', 'terminal_rejection')
      and processing_run_id is null
    )
  ),
  constraint media_quarantine_cleanups_lifecycle_shape_check check (
    (
      status = 'queued'
      and object_checksum_sha256 is null
      and observed_byte_size is null
      and fenced_at is null
      and storage_result is null
      and completed_at is null
      and completion_audit_event_id is null
      and completion_outbox_event_id is null
    )
    or (
      status = 'fenced'
      and object_checksum_sha256 is not null
      and observed_byte_size is not null
      and fenced_at is not null
      and storage_result is null
      and completed_at is null
      and completion_audit_event_id is null
      and completion_outbox_event_id is null
    )
    or (
      status = 'deleted'
      and object_checksum_sha256 is not null
      and observed_byte_size is not null
      and fenced_at is not null
      and storage_result = 'deleted'
      and completed_at is not null
      and completion_audit_event_id is not null
      and completion_outbox_event_id is not null
    )
    or (
      status = 'not_found'
      and storage_result = 'not_found'
      and completed_at is not null
      and completion_audit_event_id is not null
      and completion_outbox_event_id is not null
      and (
        (
          object_checksum_sha256 is null
          and observed_byte_size is null
          and fenced_at is null
        )
        or (
          object_checksum_sha256 is not null
          and observed_byte_size is not null
          and fenced_at is not null
        )
      )
    )
  )
);

create index media_quarantine_cleanups_status_idx
  on public.media_quarantine_cleanups (status, created_at, id)
  where status in ('queued', 'fenced');

create function app.guard_media_quarantine_cleanup()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.id is distinct from new.id
    or old.workspace_id is distinct from new.workspace_id
    or old.upload_session_id is distinct from new.upload_session_id
    or old.media_id is distinct from new.media_id
    or old.reason is distinct from new.reason
    or old.processing_run_id is distinct from new.processing_run_id
    or old.generation is distinct from new.generation
    or old.expected_checksum_sha256 is distinct from new.expected_checksum_sha256
    or old.job_id is distinct from new.job_id
    or old.outbox_event_id is distinct from new.outbox_event_id
    or old.queued_audit_event_id is distinct from new.queued_audit_event_id
    or old.created_at is distinct from new.created_at
    or old.status in ('deleted', 'not_found')
    or (
      old.status = 'queued'
      and new.status not in ('fenced', 'not_found')
    )
    or (
      old.status = 'fenced'
      and new.status not in ('deleted', 'not_found')
    ) then
    raise exception using
      errcode = '55000',
      message = 'media quarantine cleanup history is immutable';
  end if;
  return new;
end;
$$;

create trigger media_quarantine_cleanups_guard
before update on public.media_quarantine_cleanups
for each row execute function app.guard_media_quarantine_cleanup();

create trigger media_quarantine_cleanups_no_delete
before delete on public.media_quarantine_cleanups
for each row execute function app.prevent_media_history_mutation();

create function app.media_quarantine_cleanup_still_safe(
  p_workspace_id uuid,
  p_cleanup_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.media_quarantine_cleanups cleanup
    join public.media_upload_sessions upload
      on upload.workspace_id = cleanup.workspace_id
     and upload.id = cleanup.upload_session_id
     and upload.media_id = cleanup.media_id
    join public.media_assets asset
      on asset.workspace_id = cleanup.workspace_id
     and asset.id = cleanup.media_id
     and asset.media_kind = 'vehicle_photo'
    where cleanup.workspace_id = p_workspace_id
      and cleanup.id = p_cleanup_id
      and (
        (
          cleanup.reason = 'expired_intent'
          and upload.status = 'expired'
          and upload.verification_job_id is null
          and asset.status = 'awaiting_upload'
          and asset.generation = cleanup.generation
        )
        or (
          cleanup.reason = 'terminal_rejection'
          and upload.status = 'awaiting_upload'
          and upload.verification_job_id is not null
          and asset.status = 'failed'
          and asset.generation = cleanup.generation
          and exists (
            select 1
            from public.jobs verification_job
            where verification_job.workspace_id = cleanup.workspace_id
              and verification_job.id = upload.verification_job_id
              and verification_job.job_type = 'media.verify_vehicle_photo_upload'
              and verification_job.entity_type = 'media_upload_session'
              and verification_job.entity_id = cleanup.upload_session_id
              and verification_job.status = 'dead_letter'
          )
        )
        or (
          cleanup.reason = 'verified_raw_copy'
          and upload.status = 'completed'
          and upload.observed_checksum_sha256 = cleanup.expected_checksum_sha256
          and exists (
            select 1
            from public.media_processing_runs run
            join public.media_files raw_file
              on raw_file.workspace_id = run.workspace_id
             and raw_file.media_id = run.media_id
             and raw_file.processing_run_id = run.id
             and raw_file.file_class = 'vehicle_photo_raw'
             and raw_file.variant = 'raw_original'
             and raw_file.deleted_at is null
             and raw_file.checksum_sha256 = cleanup.expected_checksum_sha256
             and raw_file.storage_bucket = 'media-private'
             and raw_file.storage_object_key = 'workspaces/'
               || cleanup.workspace_id::text || '/media/'
               || cleanup.media_id::text || '/raw/'
               || cleanup.expected_checksum_sha256 || '.' || case upload.observed_mime_type
                 when 'image/jpeg' then 'jpg'
                 when 'image/png' then 'png'
                 when 'image/webp' then 'webp'
                 when 'image/heic' then 'heic'
                 when 'image/heif' then 'heif'
               end
            where run.workspace_id = cleanup.workspace_id
              and run.id = cleanup.processing_run_id
              and run.media_id = cleanup.media_id
              and run.source_kind = 'upload_session'
              and run.source_id = cleanup.upload_session_id
              and run.generation = cleanup.generation
              and run.status = 'succeeded'
              and exists (
                select 1
                from public.media_files master
                where master.workspace_id = run.workspace_id
                  and master.media_id = run.media_id
                  and master.processing_run_id = run.id
                  and master.variant = 'normalized_master'
                  and master.deleted_at is null
                  and master.storage_bucket = 'media-private'
                  and master.storage_object_key = 'workspaces/'
                    || cleanup.workspace_id::text || '/media/'
                    || cleanup.media_id::text || '/runs/' || run.id::text
                    || '/normalized_master/' || master.checksum_sha256 || '.webp'
              )
          )
        )
      )
  );
$$;

create function app.enqueue_due_media_quarantine_cleanup(
  p_limit integer default 100,
  p_correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (
  cleanup_id uuid,
  upload_session_id uuid,
  job_id uuid,
  cleanup_reason text,
  created boolean,
  job_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  due_upload record;
  queued record;
  new_cleanup_id uuid;
  new_audit_event_id uuid;
begin
  if p_limit is null
    or p_limit not between 1 and 500
    or p_correlation_id is null then
    raise exception using
      errcode = '22023',
      message = 'invalid quarantine cleanup enqueue request';
  end if;

  for due_upload in
    select
      upload.workspace_id,
      upload.id as upload_session_id,
      upload.media_id,
      upload.expected_checksum_sha256,
      upload.observed_checksum_sha256,
      upload.expires_at,
      asset.generation as asset_generation,
      asset.version as asset_version,
      case
        when successful_run.processing_run_id is not null then 'verified_raw_copy'
        when verification_job.status = 'dead_letter' then 'terminal_rejection'
        else 'expired_intent'
      end as cleanup_reason,
      successful_run.processing_run_id,
      successful_run.generation as processing_generation,
      successful_run.raw_checksum_sha256,
      case
        when successful_run.processing_run_id is not null
          then successful_run.processing_outbox_event_id
        when verification_job.status = 'dead_letter'
          then verification_job.outbox_event_id
        else null
      end as causation_id
    from public.media_upload_sessions upload
    join public.media_assets asset
      on asset.workspace_id = upload.workspace_id
     and asset.id = upload.media_id
     and asset.media_kind = 'vehicle_photo'
    left join public.jobs verification_job
      on verification_job.workspace_id = upload.workspace_id
     and verification_job.id = upload.verification_job_id
     and verification_job.job_type = 'media.verify_vehicle_photo_upload'
     and verification_job.entity_type = 'media_upload_session'
     and verification_job.entity_id = upload.id
    left join lateral (
      select
        run.id as processing_run_id,
        run.generation,
        run.outbox_event_id as processing_outbox_event_id,
        raw_file.checksum_sha256 as raw_checksum_sha256
      from public.media_processing_runs run
      join public.media_files raw_file
        on raw_file.workspace_id = run.workspace_id
       and raw_file.media_id = run.media_id
       and raw_file.processing_run_id = run.id
       and raw_file.file_class = 'vehicle_photo_raw'
       and raw_file.variant = 'raw_original'
       and raw_file.deleted_at is null
       and raw_file.checksum_sha256 = upload.observed_checksum_sha256
       and raw_file.storage_bucket = 'media-private'
       and raw_file.storage_object_key = 'workspaces/'
         || upload.workspace_id::text || '/media/' || upload.media_id::text
         || '/raw/' || upload.observed_checksum_sha256 || '.'
         || case upload.observed_mime_type
           when 'image/jpeg' then 'jpg'
           when 'image/png' then 'png'
           when 'image/webp' then 'webp'
           when 'image/heic' then 'heic'
           when 'image/heif' then 'heif'
         end
      where run.workspace_id = upload.workspace_id
        and run.media_id = upload.media_id
        and run.source_kind = 'upload_session'
        and run.source_id = upload.id
        and run.status = 'succeeded'
        and exists (
          select 1
          from public.media_files master
          where master.workspace_id = run.workspace_id
            and master.media_id = run.media_id
            and master.processing_run_id = run.id
            and master.variant = 'normalized_master'
            and master.deleted_at is null
            and master.storage_bucket = 'media-private'
            and master.storage_object_key = 'workspaces/'
              || upload.workspace_id::text || '/media/' || upload.media_id::text
              || '/runs/' || run.id::text || '/normalized_master/'
              || master.checksum_sha256 || '.webp'
        )
      order by run.generation desc, run.id desc
      limit 1
    ) successful_run on true
    where not exists (
      select 1
      from public.media_quarantine_cleanups cleanup
      where cleanup.workspace_id = upload.workspace_id
        and cleanup.upload_session_id = upload.id
    )
      and (
        (
          upload.status = 'completed'
          and successful_run.processing_run_id is not null
        )
        or (
          upload.status = 'awaiting_upload'
          and asset.status = 'failed'
          and verification_job.status = 'dead_letter'
        )
        or (
          upload.status = 'awaiting_upload'
          and upload.expires_at <= pg_catalog.statement_timestamp()
          and upload.verification_job_id is null
          and asset.status = 'awaiting_upload'
        )
      )
    order by
      case
        when successful_run.processing_run_id is not null then 0
        when verification_job.status = 'dead_letter' then 1
        else 2
      end,
      upload.expires_at,
      upload.id
    for update of upload skip locked
    limit p_limit
  loop
    if due_upload.cleanup_reason = 'expired_intent' then
      update public.media_upload_sessions upload
      set status = 'expired'
      where upload.workspace_id = due_upload.workspace_id
        and upload.id = due_upload.upload_session_id
        and upload.status = 'awaiting_upload'
        and upload.verification_job_id is null;
      if not found then
        continue;
      end if;
    end if;

    new_cleanup_id := pg_catalog.gen_random_uuid();
    select result.* into queued
    from app.enqueue_outbox_job(
      p_workspace_id => due_upload.workspace_id,
      p_event_name => 'media.quarantine_cleanup_queued',
      p_aggregate_type => 'media_asset',
      p_aggregate_id => due_upload.media_id,
      p_aggregate_version => due_upload.asset_version,
      p_job_type => 'media.delete_quarantine_upload',
      p_entity_type => 'media_upload_session',
      p_entity_id => due_upload.upload_session_id,
      p_payload_schema_version => 1,
      p_payload => pg_catalog.jsonb_build_object(
        'checksum_sha256', case
          when due_upload.cleanup_reason = 'verified_raw_copy'
            then due_upload.raw_checksum_sha256
          else null
        end,
        'generation', coalesce(
          due_upload.processing_generation,
          due_upload.asset_generation
        ),
        'media_id', due_upload.media_id,
        'reason', due_upload.cleanup_reason,
        'upload_session_id', due_upload.upload_session_id
      ),
      p_idempotency_key => 'media:quarantine-cleanup:'
        || due_upload.upload_session_id::text,
      p_correlation_id => p_correlation_id,
      p_causation_id => due_upload.causation_id,
      p_priority => 35,
      p_max_attempts => 8,
      p_backoff_base_seconds => 60,
      p_backoff_max_seconds => 3600,
      p_request_id => 'scheduler:media-quarantine-cleanup'
    ) result;

    new_audit_event_id := app.write_audit_event(
      p_workspace_id => due_upload.workspace_id,
      p_action => 'media.quarantine_cleanup_queued',
      p_entity_type => 'media_upload_session',
      p_entity_id => due_upload.upload_session_id,
      p_actor_type => 'service',
      p_after_data => pg_catalog.jsonb_build_object(
        'status', 'queued',
        'reason', due_upload.cleanup_reason,
        'generation', coalesce(
          due_upload.processing_generation,
          due_upload.asset_generation
        )
      ),
      p_request_id => 'scheduler:media-quarantine-cleanup',
      p_correlation_id => p_correlation_id,
      p_auth_assurance => 'system',
      p_metadata => pg_catalog.jsonb_build_object(
        'job_id', queued.job_id,
        'outbox_event_id', queued.outbox_event_id,
        'checksum_sha256', case
          when due_upload.cleanup_reason = 'verified_raw_copy'
            then due_upload.raw_checksum_sha256
          else null
        end
      )
    );

    insert into public.media_quarantine_cleanups (
      id, workspace_id, upload_session_id, media_id, reason,
      processing_run_id, generation, expected_checksum_sha256,
      job_id, outbox_event_id, queued_audit_event_id
    ) values (
      new_cleanup_id, due_upload.workspace_id, due_upload.upload_session_id,
      due_upload.media_id, due_upload.cleanup_reason,
      due_upload.processing_run_id,
      coalesce(due_upload.processing_generation, due_upload.asset_generation),
      case
        when due_upload.cleanup_reason = 'verified_raw_copy'
          then due_upload.raw_checksum_sha256
        else null
      end,
      queued.job_id, queued.outbox_event_id, new_audit_event_id
    );

    cleanup_id := new_cleanup_id;
    upload_session_id := due_upload.upload_session_id;
    job_id := queued.job_id;
    cleanup_reason := due_upload.cleanup_reason;
    created := queued.created;
    job_status := queued.job_status;
    return next;
  end loop;
end;
$$;

create function app.load_media_quarantine_cleanup(
  p_workspace_id uuid,
  p_upload_session_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer
)
returns table (
  cleanup_id uuid,
  media_id uuid,
  cleanup_reason text,
  generation integer,
  storage_bucket text,
  storage_object_key text,
  expected_checksum_sha256 text,
  already_deleted boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  target_cleanup public.media_quarantine_cleanups%rowtype;
  target_upload public.media_upload_sessions%rowtype;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_worker_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    or p_lease_token is null
    or p_attempt_number is null or p_attempt_number < 1 then
    raise exception using
      errcode = '22023',
      message = 'invalid quarantine cleanup worker identity';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if not found
    or target_job.job_type <> 'media.delete_quarantine_upload'
    or target_job.entity_type <> 'media_upload_session'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using
      errcode = '55000',
      message = 'only the active quarantine cleanup lease can load an object';
  end if;

  select cleanup.* into target_cleanup
  from public.media_quarantine_cleanups cleanup
  where cleanup.workspace_id = p_workspace_id
    and cleanup.upload_session_id = p_upload_session_id
    and cleanup.job_id = p_job_id
  for update;
  if not found
    or target_job.payload <> pg_catalog.jsonb_build_object(
      'checksum_sha256', target_cleanup.expected_checksum_sha256,
      'generation', target_cleanup.generation,
      'media_id', target_cleanup.media_id,
      'reason', target_cleanup.reason,
      'upload_session_id', target_cleanup.upload_session_id
    ) then
    raise exception using errcode = '55000', message = 'quarantine cleanup fence is inconsistent';
  end if;

  select upload.* into target_upload
  from public.media_upload_sessions upload
  where upload.workspace_id = p_workspace_id
    and upload.id = p_upload_session_id
    and upload.media_id = target_cleanup.media_id;
  if not found then
    raise exception using errcode = '55000', message = 'quarantine upload session is unavailable';
  end if;

  if target_cleanup.status not in ('deleted', 'not_found')
    and not app.media_quarantine_cleanup_still_safe(
      p_workspace_id, target_cleanup.id
    ) then
    raise exception using errcode = '55000', message = 'quarantine cleanup is no longer safe';
  end if;

  return query select
    target_cleanup.id, target_cleanup.media_id, target_cleanup.reason,
    target_cleanup.generation, target_upload.quarantine_bucket,
    target_upload.quarantine_object_key,
    coalesce(
      target_cleanup.object_checksum_sha256,
      target_cleanup.expected_checksum_sha256
    ),
    target_cleanup.status in ('deleted', 'not_found');
end;
$$;

create function app.fence_media_quarantine_cleanup_checksum(
  p_workspace_id uuid,
  p_upload_session_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_observed_checksum_sha256 text,
  p_observed_byte_size bigint
)
returns table (
  cleanup_id uuid,
  checksum_sha256 text,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  target_cleanup public.media_quarantine_cleanups%rowtype;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_worker_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    or p_lease_token is null
    or p_attempt_number is null or p_attempt_number < 1
    or p_observed_checksum_sha256 is null
    or p_observed_checksum_sha256 !~ '^[a-f0-9]{64}$'
    or p_observed_byte_size is null
    or p_observed_byte_size not between 1 and 50000000 then
    raise exception using errcode = '22023', message = 'invalid quarantine object fence';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if not found
    or target_job.job_type <> 'media.delete_quarantine_upload'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_job.attempts_started <> p_attempt_number then
    raise exception using
      errcode = '55000',
      message = 'only the active quarantine cleanup lease can fence an object';
  end if;

  select cleanup.* into target_cleanup
  from public.media_quarantine_cleanups cleanup
  where cleanup.workspace_id = p_workspace_id
    and cleanup.upload_session_id = p_upload_session_id
    and cleanup.job_id = p_job_id
  for update;
  if not found or target_cleanup.status in ('deleted', 'not_found') then
    raise exception using errcode = '55000', message = 'quarantine cleanup is already terminal';
  end if;
  if not app.media_quarantine_cleanup_still_safe(
    p_workspace_id, target_cleanup.id
  ) then
    raise exception using errcode = '55000', message = 'quarantine cleanup is no longer safe';
  end if;
  if target_cleanup.expected_checksum_sha256 is not null
    and target_cleanup.expected_checksum_sha256 <> p_observed_checksum_sha256 then
    raise exception using errcode = '23514', message = 'quarantine object checksum changed';
  end if;

  if target_cleanup.status = 'fenced' then
    if target_cleanup.object_checksum_sha256 <> p_observed_checksum_sha256
      or target_cleanup.observed_byte_size <> p_observed_byte_size then
      raise exception using errcode = '23505', message = 'quarantine object fence replay conflicts';
    end if;
    return query select target_cleanup.id, p_observed_checksum_sha256, true;
    return;
  end if;

  update public.media_quarantine_cleanups cleanup
  set status = 'fenced',
      object_checksum_sha256 = p_observed_checksum_sha256,
      observed_byte_size = p_observed_byte_size,
      fenced_at = pg_catalog.statement_timestamp()
  where cleanup.workspace_id = p_workspace_id
    and cleanup.id = target_cleanup.id;

  return query select target_cleanup.id, p_observed_checksum_sha256, false;
end;
$$;

create function app.complete_media_quarantine_cleanup(
  p_workspace_id uuid,
  p_upload_session_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_attempt_number integer,
  p_object_checksum_sha256 text,
  p_storage_result text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  cleanup_id uuid,
  media_id uuid,
  cleanup_status text,
  completed_at timestamptz,
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
  target_cleanup public.media_quarantine_cleanups%rowtype;
  completion_time timestamptz := pg_catalog.statement_timestamp();
  new_status text;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
begin
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_worker_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    or p_lease_token is null
    or p_attempt_number is null or p_attempt_number < 1
    or p_storage_result is null
    or p_storage_result not in ('deleted', 'not_found')
    or p_correlation_id is null
    or (p_request_id is not null and pg_catalog.char_length(p_request_id) > 200)
    or (
      p_object_checksum_sha256 is not null
      and p_object_checksum_sha256 !~ '^[a-f0-9]{64}$'
    ) then
    raise exception using errcode = '22023', message = 'invalid quarantine cleanup completion';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if not found
    or target_job.job_type <> 'media.delete_quarantine_upload'
    or target_job.entity_type <> 'media_upload_session'
    or target_job.entity_id <> p_upload_session_id
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= completion_time
    or target_job.attempts_started <> p_attempt_number
    or target_job.correlation_id <> p_correlation_id then
    raise exception using
      errcode = '55000',
      message = 'only the active quarantine cleanup lease can complete deletion';
  end if;

  select cleanup.* into target_cleanup
  from public.media_quarantine_cleanups cleanup
  where cleanup.workspace_id = p_workspace_id
    and cleanup.upload_session_id = p_upload_session_id
    and cleanup.job_id = p_job_id
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'quarantine cleanup is unavailable';
  end if;

  if target_cleanup.status in ('deleted', 'not_found') then
    if target_cleanup.storage_result <> p_storage_result
      or target_cleanup.object_checksum_sha256 is distinct from p_object_checksum_sha256 then
      raise exception using errcode = '23505', message = 'quarantine cleanup replay conflicts';
    end if;
    return query select
      target_cleanup.id, target_cleanup.media_id, target_cleanup.status,
      target_cleanup.completed_at, true, target_cleanup.completion_audit_event_id,
      target_cleanup.completion_outbox_event_id;
    return;
  end if;

  if not app.media_quarantine_cleanup_still_safe(
    p_workspace_id, target_cleanup.id
  ) then
    raise exception using errcode = '55000', message = 'quarantine cleanup is no longer safe';
  end if;
  if p_storage_result = 'deleted' and (
    target_cleanup.status <> 'fenced'
    or target_cleanup.object_checksum_sha256 is distinct from p_object_checksum_sha256
  ) then
    raise exception using errcode = '23514', message = 'deleted object does not match its checksum fence';
  end if;
  if p_storage_result = 'not_found'
    and target_cleanup.status = 'fenced'
    and target_cleanup.object_checksum_sha256 is distinct from p_object_checksum_sha256 then
    raise exception using errcode = '23514', message = 'missing object does not match its checksum fence';
  end if;

  new_status := case when p_storage_result = 'deleted' then 'deleted' else 'not_found' end;

  insert into public.outbox_events (
    workspace_id, event_name, aggregate_type, aggregate_id,
    aggregate_version, payload_schema_version, payload, correlation_id,
    causation_id
  )
  select
    p_workspace_id,
    case
      when p_storage_result = 'deleted' then 'media.quarantine_deleted'
      else 'media.quarantine_not_found'
    end,
    'media_asset', target_cleanup.media_id, asset.version, 1,
    pg_catalog.jsonb_build_object(
      'cleanup_id', target_cleanup.id,
      'upload_session_id', p_upload_session_id,
      'reason', target_cleanup.reason,
      'generation', target_cleanup.generation,
      'checksum_sha256', p_object_checksum_sha256,
      'storage_result', p_storage_result,
      'completed_at', completion_time
    ),
    p_correlation_id, target_job.outbox_event_id
  from public.media_assets asset
  where asset.workspace_id = p_workspace_id
    and asset.id = target_cleanup.media_id
  returning id into new_outbox_event_id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => case
      when p_storage_result = 'deleted' then 'media.quarantine_deleted'
      else 'media.quarantine_not_found'
    end,
    p_entity_type => 'media_upload_session',
    p_entity_id => p_upload_session_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target_cleanup.status
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', new_status,
      'completed_at', completion_time
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'worker_id', p_worker_id,
      'job_id', p_job_id,
      'attempt_number', p_attempt_number,
      'reason', target_cleanup.reason,
      'generation', target_cleanup.generation,
      'checksum_sha256', p_object_checksum_sha256,
      'storage_result', p_storage_result,
      'outbox_event_id', new_outbox_event_id
    )
  );

  update public.media_quarantine_cleanups cleanup
  set status = new_status,
      storage_result = p_storage_result,
      completed_at = completion_time,
      completion_audit_event_id = new_audit_event_id,
      completion_outbox_event_id = new_outbox_event_id
  where cleanup.workspace_id = p_workspace_id
    and cleanup.id = target_cleanup.id;

  return query select
    target_cleanup.id, target_cleanup.media_id, new_status, completion_time,
    false, new_audit_event_id, new_outbox_event_id;
end;
$$;

alter table public.media_quarantine_cleanups enable row level security;
alter table public.media_quarantine_cleanups force row level security;

revoke all on table public.media_quarantine_cleanups
  from public, anon, authenticated, service_role;
grant select on table public.media_quarantine_cleanups to service_role;

revoke all on function app.guard_media_quarantine_cleanup()
  from public, anon, authenticated, service_role;
revoke all on function app.media_quarantine_cleanup_still_safe(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.enqueue_due_media_quarantine_cleanup(integer, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.load_media_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer
) from public, anon, authenticated, service_role;
revoke all on function app.fence_media_quarantine_cleanup_checksum(
  uuid, uuid, uuid, text, uuid, integer, text, bigint
) from public, anon, authenticated, service_role;
revoke all on function app.complete_media_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.enqueue_due_media_quarantine_cleanup(integer, uuid)
  to service_role;
grant execute on function app.load_media_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer
) to service_role;
grant execute on function app.fence_media_quarantine_cleanup_checksum(
  uuid, uuid, uuid, text, uuid, integer, text, bigint
) to service_role;
grant execute on function app.complete_media_quarantine_cleanup(
  uuid, uuid, uuid, text, uuid, integer, text, text, text, uuid
) to service_role;

comment on table public.media_quarantine_cleanups is
  'Durable exact-key quarantine deletion lineage fenced by workspace, upload session, media generation, and checksum; legal originals never enter this table.';
comment on function app.enqueue_due_media_quarantine_cleanup(integer, uuid) is
  'Service-only bounded scheduler for expired intents, terminal verification rejection, and verified deterministic raw-copy cleanup.';
