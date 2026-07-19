-- VYN-DOC-001, VYN-STOR-001, VYN-SEC-001, VYN-AUD-001
-- M4-DOC-AC-006 through M4-DOC-AC-010 and T-DOC-004/T-DOC-005/T-DOC-006.
-- Idempotent sensitive document lifecycle commands and opaque file grants.

create table public.document_commands (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_id uuid not null,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  action text not null check (action in ('mark_signed', 'void', 'retry_render')),
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  result jsonb not null check (pg_catalog.jsonb_typeof(result) = 'object'),
  audit_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, idempotency_key),
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict
);

create table public.document_file_download_authorizations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_file_id uuid not null,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  signed_url_ttl_seconds integer not null check (
    signed_url_ttl_seconds between 30 and 300
  ),
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  expires_at timestamptz not null,
  request_id text check (request_id is null or pg_catalog.char_length(request_id) <= 200),
  correlation_id uuid not null,
  audit_event_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, idempotency_key),
  foreign key (workspace_id, document_file_id)
    references public.document_files (workspace_id, id) on delete restrict,
  foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  check (
    expires_at > created_at
    and expires_at <= created_at + interval '5 minutes'
  )
);

create trigger document_commands_immutable
before update or delete on public.document_commands
for each row execute function app.m4_prevent_row_mutation();
create trigger document_file_download_authorizations_immutable
before update or delete on public.document_file_download_authorizations
for each row execute function app.m4_prevent_row_mutation();

alter table public.document_commands enable row level security;
alter table public.document_commands force row level security;
alter table public.document_file_download_authorizations enable row level security;
alter table public.document_file_download_authorizations force row level security;

create policy document_commands_select on public.document_commands
for select to authenticated using (
  app.has_permission(workspace_id, 'documents.read')
  and (actor_user_id = auth.uid() or app.has_permission(workspace_id, 'audit.read'))
);
create policy document_file_download_authorizations_select
on public.document_file_download_authorizations
for select to authenticated using (
  actor_user_id = auth.uid() and app.has_permission(workspace_id, 'documents.read')
);

revoke all on table public.document_commands,
  public.document_file_download_authorizations
from public, anon, authenticated;
grant select on table public.document_commands,
  public.document_file_download_authorizations
to authenticated;
grant select, insert, update, delete on table public.document_commands,
  public.document_file_download_authorizations
to service_role;

create function app.m4_mark_document_signed(
  p_workspace_id uuid,
  p_document_id uuid,
  p_expected_version bigint,
  p_idempotency_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_id uuid,
  document_status text,
  aggregate_version bigint,
  signed_at timestamptz,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target public.documents%rowtype;
  existing public.document_commands%rowtype;
  fingerprint text;
  audit_id uuid;
  signed_timestamp timestamptz := pg_catalog.statement_timestamp();
  normalized_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id, 'documents.mark_signed', true
  );
  if p_expected_version is null or p_expected_version <= 0
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid mark-signed command';
  end if;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'documentId', p_document_id,
    'expectedVersion', p_expected_version,
    'reason', normalized_reason
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fdocument_command\x1f' || actor_user_id::text
      || E'\x1f' || normalized_key, 0
  ));
  select command.* into existing from public.document_commands command
  where command.workspace_id = p_workspace_id
    and command.actor_user_id = app.current_user_id()
    and command.idempotency_key = normalized_key;
  if found then
    if existing.action <> 'mark_signed'
      or existing.document_id <> p_document_id
      or existing.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'document command idempotency conflict';
    end if;
    return query select
      existing.document_id, existing.result ->> 'status',
      (existing.result ->> 'aggregateVersion')::bigint,
      (existing.result ->> 'signedAt')::timestamptz,
      existing.audit_event_id, true;
    return;
  end if;
  select document.* into target from public.documents document
  where document.workspace_id = p_workspace_id and document.id = p_document_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'document was not found';
  end if;
  if target.aggregate_version <> p_expected_version then
    raise exception using errcode = '40001', message = 'document version changed';
  end if;
  if target.mode <> 'official' or target.status <> 'generated'
    or not exists (
      select 1 from public.document_files file
      where file.workspace_id = p_workspace_id
        and file.document_id = target.id
        and file.role = 'signed_scan' and file.current
    ) then
    raise exception using errcode = '23514', message = 'verified signed file and generated official document are required';
  end if;
  update public.documents document set
    status = 'signed_received', signed_at = signed_timestamp,
    aggregate_version = document.aggregate_version + 1
  where document.workspace_id = p_workspace_id and document.id = p_document_id;
  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.marked_signed',
    p_entity_type => 'document',
    p_entity_id => p_document_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target.status, 'aggregateVersion', target.aggregate_version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'signed_received', 'aggregateVersion', target.aggregate_version + 1,
      'signedAt', signed_timestamp
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2'
  );
  insert into public.document_commands (
    workspace_id, document_id, actor_user_id, action, idempotency_key,
    command_fingerprint, reason, result, audit_event_id
  ) values (
    p_workspace_id, p_document_id, actor_user_id, 'mark_signed', normalized_key,
    fingerprint, normalized_reason, pg_catalog.jsonb_build_object(
      'status', 'signed_received',
      'aggregateVersion', target.aggregate_version + 1,
      'signedAt', signed_timestamp
    ), audit_id
  );
  return query select p_document_id, 'signed_received'::text,
    target.aggregate_version + 1, signed_timestamp, audit_id, false;
end;
$$;

create function app.m4_void_document(
  p_workspace_id uuid,
  p_document_id uuid,
  p_expected_version bigint,
  p_idempotency_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_id uuid,
  document_status text,
  aggregate_version bigint,
  voided_at timestamptz,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target public.documents%rowtype;
  existing public.document_commands%rowtype;
  fingerprint text;
  audit_id uuid;
  void_timestamp timestamptz := pg_catalog.statement_timestamp();
  normalized_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id, 'documents.void', true
  );
  if p_expected_version is null or p_expected_version <= 0
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid document void command';
  end if;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'documentId', p_document_id,
    'expectedVersion', p_expected_version,
    'reason', normalized_reason
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fdocument_command\x1f' || actor_user_id::text
      || E'\x1f' || normalized_key, 0
  ));
  select command.* into existing from public.document_commands command
  where command.workspace_id = p_workspace_id
    and command.actor_user_id = app.current_user_id()
    and command.idempotency_key = normalized_key;
  if found then
    if existing.action <> 'void' or existing.document_id <> p_document_id
      or existing.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'document command idempotency conflict';
    end if;
    return query select
      existing.document_id, existing.result ->> 'status',
      (existing.result ->> 'aggregateVersion')::bigint,
      (existing.result ->> 'voidedAt')::timestamptz,
      existing.audit_event_id, true;
    return;
  end if;
  select document.* into target from public.documents document
  where document.workspace_id = p_workspace_id and document.id = p_document_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'document was not found';
  end if;
  if target.aggregate_version <> p_expected_version then
    raise exception using errcode = '40001', message = 'document version changed';
  end if;
  if target.mode <> 'official'
    or target.status not in (
      'generated', 'generation_failed', 'signed_received', 'completed'
    ) then
    raise exception using errcode = '23514', message = 'document is not eligible to void';
  end if;
  if target.status in ('signed_received', 'completed') or exists (
    select 1 from public.document_files file
    where file.workspace_id = p_workspace_id and file.document_id = target.id
      and file.role = 'signed_scan' and file.current
  ) then
    perform app.require_vertical_slice_permission(
      p_workspace_id, 'documents.void_signed', true
    );
  end if;
  update public.documents document set
    status = 'voided', void_reason = normalized_reason,
    voided_by = actor_user_id, voided_at = void_timestamp,
    aggregate_version = document.aggregate_version + 1
  where document.workspace_id = p_workspace_id and document.id = p_document_id;
  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.voided',
    p_entity_type => 'document',
    p_entity_id => p_document_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', target.status,
      'aggregateVersion', target.aggregate_version,
      'officialNumber', target.official_number,
      'failureCode', target.failure_code
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'voided', 'aggregateVersion', target.aggregate_version + 1,
      'voidedAt', void_timestamp,
      'officialNumber', target.official_number,
      'failureCode', target.failure_code
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2'
  );
  insert into public.document_commands (
    workspace_id, document_id, actor_user_id, action, idempotency_key,
    command_fingerprint, reason, result, audit_event_id
  ) values (
    p_workspace_id, p_document_id, actor_user_id, 'void', normalized_key,
    fingerprint, normalized_reason, pg_catalog.jsonb_build_object(
      'status', 'voided',
      'aggregateVersion', target.aggregate_version + 1,
      'voidedAt', void_timestamp
    ), audit_id
  );
  return query select p_document_id, 'voided'::text,
    target.aggregate_version + 1, void_timestamp, audit_id, false;
end;
$$;

create function app.m4_retry_document_render(
  p_workspace_id uuid,
  p_document_id uuid,
  p_expected_version bigint,
  p_idempotency_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_id uuid,
  document_status text,
  aggregate_version bigint,
  job_id uuid,
  job_status text,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target public.documents%rowtype;
  existing public.document_commands%rowtype;
  prior_attempt public.document_render_attempts%rowtype;
  prior_job public.jobs%rowtype;
  superseded_document public.documents%rowtype;
  replay_job public.jobs%rowtype;
  next_attempt integer;
  replay_job_id uuid;
  fingerprint text;
  audit_id uuid;
  normalized_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id, 'documents.generate_approved', true
  );
  perform app.require_vertical_slice_permission(p_workspace_id, 'jobs.manage', true);
  if p_expected_version is null or p_expected_version <= 0
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid document retry command';
  end if;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'documentId', p_document_id,
    'expectedVersion', p_expected_version,
    'reason', normalized_reason
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fdocument_command\x1f' || actor_user_id::text
      || E'\x1f' || normalized_key, 0
  ));
  select command.* into existing from public.document_commands command
  where command.workspace_id = p_workspace_id
    and command.actor_user_id = app.current_user_id()
    and command.idempotency_key = normalized_key;
  if found then
    if existing.action <> 'retry_render' or existing.document_id <> p_document_id
      or existing.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'document command idempotency conflict';
    end if;
    return query select
      existing.document_id, existing.result ->> 'status',
      (existing.result ->> 'aggregateVersion')::bigint,
      (existing.result ->> 'jobId')::uuid,
      existing.result ->> 'jobStatus', existing.audit_event_id, true;
    return;
  end if;
  select document.* into target from public.documents document
  where document.workspace_id = p_workspace_id and document.id = p_document_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'document was not found';
  end if;
  if target.aggregate_version <> p_expected_version then
    raise exception using errcode = '40001', message = 'document version changed';
  end if;
  if target.mode <> 'official' or target.status <> 'generation_failed' then
    raise exception using errcode = '23514', message = 'only a failed official render may be retried';
  end if;
  if target.supersedes_document_id is not null then
    select document.* into superseded_document
    from public.documents document
    where document.workspace_id = p_workspace_id
      and document.id = target.supersedes_document_id
    for update;
    if not found
      or superseded_document.mode <> 'official'
      or superseded_document.status not in ('generated', 'signed_received', 'completed')
      or superseded_document.superseded_by_document_id is not null
      or superseded_document.aggregate_version is distinct from target.supersedes_expected_version then
      raise exception using
        errcode = '40001',
        message = 'document.supersession_prior_changed';
    end if;
  end if;
  select attempt.* into prior_attempt
  from public.document_render_attempts attempt
  where attempt.workspace_id = p_workspace_id
    and attempt.document_id = p_document_id
  order by attempt.attempt_number desc
  limit 1;
  if found then
    select job.* into prior_job
    from public.jobs job
    where job.workspace_id = prior_attempt.workspace_id
      and job.id = prior_attempt.job_id;
  end if;
  if prior_attempt.id is null or prior_job.status <> 'dead_letter'
    or not prior_job.review_required then
    raise exception using errcode = '23514', message = 'render job is not awaiting dead-letter review';
  end if;
  replay_job_id := app.replay_dead_letter_job(
    prior_job.id,
    'document-retry:' || app.vertical_slice_fingerprint(
      pg_catalog.jsonb_build_object('idempotencyKey', normalized_key)
    ),
    actor_user_id,
    normalized_reason, p_correlation_id
  );
  select job.* into replay_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = replay_job_id;
  if not found or replay_job.status <> 'queued' then
    raise exception using errcode = '55000', message = 'document render replay was not queued';
  end if;
  next_attempt := prior_attempt.attempt_number + 1;
  insert into public.document_render_attempts (
    workspace_id, document_id, attempt_number, outbox_event_id, job_id,
    replay_of_job_id, requested_by, reason
  ) values (
    p_workspace_id, p_document_id, next_attempt, replay_job.outbox_event_id,
    replay_job.id, prior_job.id, actor_user_id, normalized_reason
  );
  update public.documents document set
    status = 'generating', failure_code = null,
    aggregate_version = document.aggregate_version + 1
  where document.workspace_id = p_workspace_id and document.id = p_document_id;
  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.render_retried',
    p_entity_type => 'document',
    p_entity_id => p_document_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', 'generation_failed', 'jobId', prior_job.id
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'generating', 'jobId', replay_job.id,
      'attemptNumber', next_attempt,
      'aggregateVersion', target.aggregate_version + 1
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'aal2'
  );
  insert into public.document_commands (
    workspace_id, document_id, actor_user_id, action, idempotency_key,
    command_fingerprint, reason, result, audit_event_id
  ) values (
    p_workspace_id, p_document_id, actor_user_id, 'retry_render', normalized_key,
    fingerprint, normalized_reason, pg_catalog.jsonb_build_object(
      'status', 'generating',
      'aggregateVersion', target.aggregate_version + 1,
      'jobId', replay_job.id,
      'jobStatus', replay_job.status
    ), audit_id
  );
  return query select p_document_id, 'generating'::text,
    target.aggregate_version + 1, replay_job.id, replay_job.status,
    audit_id, false;
end;
$$;

create function app.m4_authorize_document_file_download(
  p_workspace_id uuid,
  p_document_file_id uuid,
  p_idempotency_key text,
  p_expires_in_seconds integer,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  authorization_id uuid,
  document_file_id uuid,
  document_id uuid,
  filename text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  authorization_expires_at timestamptz,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_file public.document_files%rowtype;
  existing public.document_file_download_authorizations%rowtype;
  normalized_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  fingerprint text;
  new_id uuid := pg_catalog.gen_random_uuid();
  expires_at_value timestamptz;
  audit_id uuid;
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id, 'documents.read'
  );
  if pg_catalog.char_length(normalized_key) not between 8 and 200
    or p_expires_in_seconds not between 30 and 300
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid document file download command';
  end if;
  select file.* into target_file from public.document_files file
  where file.workspace_id = p_workspace_id and file.id = p_document_file_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'document file was not found';
  end if;
  if target_file.role = 'signed_scan' then
    perform app.require_vertical_slice_permission(
      p_workspace_id, 'files.read_restricted', true
    );
  end if;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'documentFileId', p_document_file_id,
    'expiresInSeconds', p_expires_in_seconds,
    'reason', normalized_reason
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fdocument_file_download\x1f'
      || actor_user_id::text || E'\x1f' || normalized_key, 0
  ));
  select download_authorization.* into existing
  from public.document_file_download_authorizations download_authorization
  where download_authorization.workspace_id = p_workspace_id
    and download_authorization.actor_user_id = app.current_user_id()
    and download_authorization.idempotency_key = normalized_key;
  if found then
    if existing.request_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'document download idempotency conflict';
    end if;
    if existing.expires_at <= pg_catalog.statement_timestamp() then
      raise exception using errcode = '55000', message = 'document download authorization expired';
    end if;
    return query select
      existing.id, target_file.id, target_file.document_id,
      target_file.filename, target_file.mime_type, target_file.byte_size,
      target_file.checksum, existing.expires_at, existing.audit_event_id, true;
    return;
  end if;
  expires_at_value := pg_catalog.statement_timestamp()
    + pg_catalog.make_interval(secs => p_expires_in_seconds);
  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.file_download_authorized',
    p_entity_type => 'document_file',
    p_entity_id => target_file.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'documentId', target_file.document_id,
      'role', target_file.role,
      'version', target_file.version,
      'checksum', target_file.checksum,
      'expiresAt', expires_at_value
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => case when target_file.role = 'signed_scan'
      then 'aal2' else coalesce(auth.jwt() ->> 'aal', 'unknown') end
  );
  insert into public.document_file_download_authorizations (
    id, workspace_id, document_file_id, actor_user_id, idempotency_key,
    request_fingerprint, signed_url_ttl_seconds, reason, expires_at,
    request_id, correlation_id, audit_event_id
  ) values (
    new_id, p_workspace_id, target_file.id, actor_user_id, normalized_key,
    fingerprint, p_expires_in_seconds, normalized_reason, expires_at_value,
    p_request_id, p_correlation_id, audit_id
  );
  return query select
    new_id, target_file.id, target_file.document_id, target_file.filename,
    target_file.mime_type, target_file.byte_size, target_file.checksum,
    expires_at_value, audit_id, false;
end;
$$;

create function app.m4_load_document_file_download_authorization(
  p_authorization_id uuid
)
returns table (
  authorization_id uuid,
  workspace_id uuid,
  document_file_id uuid,
  document_id uuid,
  storage_bucket text,
  storage_object_path text,
  storage_generation text,
  filename text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  verification_receipt jsonb,
  signed_url_ttl_seconds integer,
  authorization_expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' or p_authorization_id is null then
    raise exception using errcode = '42501', message = 'service role and authorization ID are required';
  end if;
  return query select
    download_authorization.id, download_authorization.workspace_id, file.id, file.document_id,
    file.storage_bucket, file.storage_object_path, file.storage_generation,
    file.filename, file.mime_type, file.byte_size, file.checksum,
    file.verification_receipt, download_authorization.signed_url_ttl_seconds,
    download_authorization.expires_at
  from public.document_file_download_authorizations download_authorization
  join public.document_files file
    on file.workspace_id = download_authorization.workspace_id
   and file.id = download_authorization.document_file_id
  where download_authorization.id = p_authorization_id
    and download_authorization.expires_at > pg_catalog.statement_timestamp();
  if not found then
    raise exception using errcode = 'P0002', message = 'document file authorization was not found';
  end if;
end;
$$;

revoke all on function app.m4_mark_document_signed(uuid, uuid, bigint, text, text, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_void_document(uuid, uuid, bigint, text, text, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_retry_document_render(uuid, uuid, bigint, text, text, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function app.m4_authorize_document_file_download(
  uuid, uuid, text, integer, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_load_document_file_download_authorization(uuid)
from public, anon, authenticated;

grant execute on function app.m4_mark_document_signed(uuid, uuid, bigint, text, text, text, uuid)
to authenticated;
grant execute on function app.m4_void_document(uuid, uuid, bigint, text, text, text, uuid)
to authenticated;
grant execute on function app.m4_retry_document_render(uuid, uuid, bigint, text, text, text, uuid)
to authenticated;
grant execute on function app.m4_authorize_document_file_download(
  uuid, uuid, text, integer, text, text, uuid
) to authenticated;
grant execute on function app.m4_load_document_file_download_authorization(uuid)
to service_role;

comment on table public.document_commands is
  'Append-only idempotency and audit outcomes for sensitive official-document lifecycle commands.';
comment on table public.document_file_download_authorizations is
  'Short-lived audited opaque grants; provider coordinates remain service-only.';
