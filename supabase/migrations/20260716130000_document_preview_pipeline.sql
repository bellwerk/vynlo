-- M1-DOC-REQ-002, M1-JOB-REQ-001, M1-TEN-REQ-001, M1-AUD-REQ-001
-- M1-DOC-AC-006 through M1-DOC-AC-013
-- Forward-only transactional document-preview job and artifact pipeline.

create table public.document_preview_jobs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_id uuid not null,
  outbox_event_id uuid not null,
  job_id uuid not null,
  idempotency_key text not null
    check (idempotency_key = pg_catalog.btrim(idempotency_key))
    check (pg_catalog.char_length(idempotency_key) between 8 and 200),
  request_fingerprint text not null
    check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  requested_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, document_id),
  unique (workspace_id, outbox_event_id),
  unique (workspace_id, job_id),
  unique (workspace_id, idempotency_key),
  unique (workspace_id, id, document_id, job_id),
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict
);

create index document_preview_jobs_requester_idx
  on public.document_preview_jobs (workspace_id, requested_by, created_at desc);

create table public.document_preview_artifacts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_id uuid not null,
  preview_job_id uuid not null,
  job_id uuid not null,
  storage_bucket text not null check (
    storage_bucket ~ '^[a-z0-9][a-z0-9_-]{2,62}$'
  ),
  storage_object_path text not null check (
    pg_catalog.char_length(storage_object_path) between 1 and 1000
    and storage_object_path = pg_catalog.btrim(storage_object_path)
    and storage_object_path !~ '[\\]'
    and storage_object_path !~ '(^|/)\.\.(/|$)'
    and storage_object_path !~ '(^|/)[.](/|$)'
    and storage_object_path !~ '^/'
    and storage_object_path !~ '/$'
    and storage_object_path !~ '//'
    and storage_object_path !~* '^https?://'
  ),
  filename text not null check (filename = 'preview.html'),
  mime_type text not null check (mime_type = 'text/html; charset=utf-8'),
  byte_size bigint not null check (byte_size between 1 and 10000000),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  renderer_version text not null check (renderer_version = 'synthetic-html-v1'),
  requested_by uuid not null references auth.users (id) on delete restrict,
  correlation_id uuid not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, document_id),
  unique (workspace_id, job_id),
  unique (workspace_id, storage_bucket, storage_object_path),
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, preview_job_id, document_id, job_id)
    references public.document_preview_jobs (
      workspace_id,
      id,
      document_id,
      job_id
    ) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict
);

create index document_preview_artifacts_requester_idx
  on public.document_preview_artifacts (
    workspace_id,
    requested_by,
    created_at desc
  );
create index document_preview_artifacts_storage_lookup_idx
  on public.document_preview_artifacts (
    storage_bucket,
    storage_object_path,
    workspace_id
  );

create function app.document_preview_storage_object_path(
  p_workspace_id uuid,
  p_document_id uuid,
  p_checksum text
)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  normalized_checksum text := pg_catalog.lower(
    pg_catalog.btrim(p_checksum)
  );
begin
  if normalized_checksum !~ '^[a-f0-9]{64}$' then
    raise exception using
      errcode = '22023',
      message = 'valid preview artifact checksum is required';
  end if;

  return pg_catalog.format(
    '%s/documents/%s/preview/%s.html',
    p_workspace_id,
    p_document_id,
    normalized_checksum
  );
end;
$$;

create function app.request_document_preview_job(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_template_version_id uuid,
  p_locale text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_id uuid,
  preview_status text,
  watermark text,
  outbox_event_id uuid,
  job_id uuid,
  job_status text,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  normalized_idempotency_key text := pg_catalog.btrim(
    coalesce(p_idempotency_key, '')
  );
  requested_preview record;
  preview_document public.documents%rowtype;
  existing_mapping public.document_preview_jobs%rowtype;
  linked_job public.jobs%rowtype;
  linked_event public.outbox_events%rowtype;
  enqueued_job record;
  render_payload jsonb;
  pipeline_fingerprint text;
  new_mapping_id uuid := pg_catalog.gen_random_uuid();
begin
  select requested.*
    into requested_preview
  from app.request_document_preview(
    p_workspace_id => p_workspace_id,
    p_idempotency_key => normalized_idempotency_key,
    p_deal_id => p_deal_id,
    p_template_version_id => p_template_version_id,
    p_locale => p_locale,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id
  ) requested;

  select document.*
    into preview_document
  from public.documents document
  where document.workspace_id = p_workspace_id
    and document.id = requested_preview.document_id;

  if not found then
    raise exception using
      errcode = '55000',
      message = 'requested preview document is missing';
  end if;
  if actor_user_id is null
    or preview_document.created_by is distinct from actor_user_id then
    raise exception using
      errcode = '42501',
      message = 'preview idempotency is scoped to its authenticated requester';
  end if;

  render_payload := pg_catalog.jsonb_build_object(
    'document_id', preview_document.id,
    'template_version_id', preview_document.template_version_id,
    'render_input_checksum', preview_document.render_input_checksum,
    'locale', preview_document.locale
  );
  pipeline_fingerprint := app.vertical_slice_fingerprint(render_payload);

  select mapping.*
    into existing_mapping
  from public.document_preview_jobs mapping
  where mapping.workspace_id = p_workspace_id
    and mapping.idempotency_key = normalized_idempotency_key
  for update;

  if found then
    if existing_mapping.document_id is distinct from preview_document.id
      or existing_mapping.request_fingerprint is distinct from pipeline_fingerprint
      or existing_mapping.requested_by is distinct from actor_user_id then
      raise exception using
        errcode = '23505',
        message = 'preview pipeline idempotency key was used for a different request';
    end if;

    select queued.*
      into linked_job
    from public.jobs queued
    where queued.workspace_id = p_workspace_id
      and queued.id = existing_mapping.job_id;

    if not found
      or linked_job.outbox_event_id is distinct from existing_mapping.outbox_event_id
      or linked_job.job_type is distinct from 'documents.render_preview'
      or linked_job.entity_type is distinct from 'document'
      or linked_job.entity_id is distinct from preview_document.id
      or linked_job.payload_schema_version is distinct from 1
      or linked_job.payload is distinct from render_payload
      or linked_job.idempotency_key is distinct from normalized_idempotency_key then
      raise exception using
        errcode = '55000',
        message = 'preview pipeline job linkage is inconsistent';
    end if;

    select event.*
      into linked_event
    from public.outbox_events event
    where event.workspace_id = p_workspace_id
      and event.id = existing_mapping.outbox_event_id;

    if not found
      or linked_event.event_name is distinct from 'document.preview_requested'
      or linked_event.aggregate_type is distinct from 'document'
      or linked_event.aggregate_id is distinct from preview_document.id
      or linked_event.aggregate_version is distinct from 1
      or linked_event.payload_schema_version is distinct from 1
      or linked_event.payload is distinct from render_payload then
      raise exception using
        errcode = '55000',
        message = 'preview pipeline outbox linkage is inconsistent';
    end if;

    return query
    select
      preview_document.id,
      preview_document.status,
      preview_document.watermark,
      existing_mapping.outbox_event_id,
      existing_mapping.job_id,
      linked_job.status,
      true;
    return;
  end if;

  if preview_document.status <> 'queued' then
    raise exception using
      errcode = '55000',
      message = 'only a queued preview can receive a render job';
  end if;

  select queued.*
    into enqueued_job
  from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'document.preview_requested',
    p_aggregate_type => 'document',
    p_aggregate_id => preview_document.id,
    p_aggregate_version => 1,
    p_job_type => 'documents.render_preview',
    p_entity_type => 'document',
    p_entity_id => preview_document.id,
    p_payload_schema_version => 1,
    p_payload => render_payload,
    p_idempotency_key => normalized_idempotency_key,
    p_correlation_id => p_correlation_id,
    p_actor_user_id => actor_user_id,
    p_request_id => p_request_id
  ) queued;

  insert into public.document_preview_jobs (
    id,
    workspace_id,
    document_id,
    outbox_event_id,
    job_id,
    idempotency_key,
    request_fingerprint,
    requested_by
  ) values (
    new_mapping_id,
    p_workspace_id,
    preview_document.id,
    enqueued_job.outbox_event_id,
    enqueued_job.job_id,
    normalized_idempotency_key,
    pipeline_fingerprint,
    actor_user_id
  );

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.preview_job_queued',
    p_entity_type => 'document_preview_job',
    p_entity_id => new_mapping_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'document_id', preview_document.id,
      'outbox_event_id', enqueued_job.outbox_event_id,
      'job_id', enqueued_job.job_id,
      'job_type', 'documents.render_preview',
      'status', enqueued_job.job_status
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key,
      'render_input_checksum', preview_document.render_input_checksum
    )
  );

  return query
  select
    preview_document.id,
    preview_document.status,
    preview_document.watermark,
    enqueued_job.outbox_event_id,
    enqueued_job.job_id,
    enqueued_job.job_status,
    false;
end;
$$;

create function app.complete_document_preview_artifact(
  p_workspace_id uuid,
  p_document_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_storage_bucket text,
  p_storage_object_path text,
  p_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_checksum text,
  p_renderer_version text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_file_id uuid,
  document_status text,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_checksum text := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_checksum, ''))
  );
  normalized_mime_type text := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_mime_type, ''))
  );
  expected_storage_object_path text;
  preview_mapping public.document_preview_jobs%rowtype;
  preview_document public.documents%rowtype;
  render_job public.jobs%rowtype;
  existing_artifact public.document_preview_artifacts%rowtype;
  expected_payload jsonb;
  new_artifact_id uuid := pg_catalog.gen_random_uuid();
  completed_document_status text;
begin
  if p_correlation_id is null then
    raise exception using errcode = '23502', message = 'correlation ID is required';
  end if;
  if pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_lease_token is null then
    raise exception using
      errcode = '22023',
      message = 'valid preview worker lease identifiers are required';
  end if;
  if coalesce(p_storage_bucket, '') !~ '^[a-z0-9][a-z0-9_-]{2,62}$' then
    raise exception using
      errcode = '22023',
      message = 'valid private preview storage bucket is required';
  end if;
  if normalized_checksum !~ '^[a-f0-9]{64}$' then
    raise exception using
      errcode = '22023',
      message = 'valid preview artifact checksum is required';
  end if;
  if p_filename is distinct from 'preview.html' then
    raise exception using
      errcode = '22023',
      message = 'preview artifact filename must be preview.html';
  end if;
  if normalized_mime_type <> 'text/html; charset=utf-8' then
    raise exception using
      errcode = '22023',
      message = 'preview artifact MIME type must be text/html; charset=utf-8';
  end if;
  if p_byte_size is null or p_byte_size not between 1 and 10000000 then
    raise exception using
      errcode = '22023',
      message = 'preview artifact byte size is outside the allowed range';
  end if;
  if p_renderer_version is distinct from 'synthetic-html-v1' then
    raise exception using
      errcode = '22023',
      message = 'preview artifact renderer version is unsupported';
  end if;

  expected_storage_object_path := app.document_preview_storage_object_path(
    p_workspace_id,
    p_document_id,
    normalized_checksum
  );
  if p_storage_object_path is distinct from expected_storage_object_path then
    raise exception using
      errcode = '23514',
      message = 'preview artifact object path is not the deterministic private key';
  end if;

  select mapping.*
    into preview_mapping
  from public.document_preview_jobs mapping
  where mapping.workspace_id = p_workspace_id
    and mapping.document_id = p_document_id
    and mapping.job_id = p_job_id;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'preview artifact must match its workspace document job mapping';
  end if;

  select document.*
    into preview_document
  from public.documents document
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  for update;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'preview document must belong to the workspace';
  end if;

  expected_payload := pg_catalog.jsonb_build_object(
    'document_id', preview_document.id,
    'template_version_id', preview_document.template_version_id,
    'render_input_checksum', preview_document.render_input_checksum,
    'locale', preview_document.locale
  );

  select queued.*
    into render_job
  from public.jobs queued
  where queued.workspace_id = p_workspace_id
    and queued.id = p_job_id
  for update;

  if not found
    or render_job.outbox_event_id is distinct from preview_mapping.outbox_event_id
    or render_job.job_type is distinct from 'documents.render_preview'
    or render_job.entity_type is distinct from 'document'
    or render_job.entity_id is distinct from p_document_id
    or render_job.payload_schema_version is distinct from 1
    or render_job.payload is distinct from expected_payload
    or render_job.correlation_id is distinct from p_correlation_id then
    raise exception using
      errcode = '23514',
      message = 'preview render job contract does not match the artifact';
  end if;

  if render_job.status <> 'running'
    or render_job.lease_owner is distinct from p_worker_id
    or render_job.lease_token is distinct from p_lease_token
    or render_job.lease_expires_at <= pg_catalog.statement_timestamp() then
    raise exception using
      errcode = '55000',
      message = 'only the matching active lease owner can record an artifact';
  end if;

  select artifact.*
    into existing_artifact
  from public.document_preview_artifacts artifact
  where artifact.workspace_id = p_workspace_id
    and artifact.document_id = p_document_id
  for update;

  if found then
    if existing_artifact.preview_job_id is distinct from preview_mapping.id
      or existing_artifact.job_id is distinct from p_job_id
      or existing_artifact.storage_bucket is distinct from p_storage_bucket
      or existing_artifact.storage_object_path is distinct from expected_storage_object_path
      or existing_artifact.filename is distinct from p_filename
      or existing_artifact.mime_type is distinct from normalized_mime_type
      or existing_artifact.byte_size is distinct from p_byte_size
      or existing_artifact.checksum is distinct from normalized_checksum
      or existing_artifact.renderer_version is distinct from p_renderer_version
      or existing_artifact.requested_by is distinct from preview_mapping.requested_by
      or existing_artifact.correlation_id is distinct from p_correlation_id then
      raise exception using
        errcode = '23505',
        message = 'preview artifact completion conflicts with the immutable result';
    end if;

    if preview_document.status <> 'generated'
      or preview_document.generated_checksum is distinct from normalized_checksum then
      raise exception using
        errcode = '55000',
        message = 'completed preview artifact has inconsistent terminal state';
    end if;

    return query
    select
      existing_artifact.id,
      preview_document.status,
      true;
    return;
  end if;

  completed_document_status := app.complete_document_preview(
    p_workspace_id => p_workspace_id,
    p_document_id => p_document_id,
    p_succeeded => true,
    p_generated_checksum => normalized_checksum,
    p_failure_code => null,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id
  );

  insert into public.document_preview_artifacts (
    id,
    workspace_id,
    document_id,
    preview_job_id,
    job_id,
    storage_bucket,
    storage_object_path,
    filename,
    mime_type,
    byte_size,
    checksum,
    renderer_version,
    requested_by,
    correlation_id
  ) values (
    new_artifact_id,
    p_workspace_id,
    p_document_id,
    preview_mapping.id,
    p_job_id,
    p_storage_bucket,
    expected_storage_object_path,
    p_filename,
    normalized_mime_type,
    p_byte_size,
    normalized_checksum,
    p_renderer_version,
    preview_mapping.requested_by,
    p_correlation_id
  );

  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.preview_artifact_recorded',
    p_entity_type => 'document_preview_artifact',
    p_entity_id => new_artifact_id,
    p_actor_type => 'worker',
    p_after_data => pg_catalog.jsonb_build_object(
      'document_id', p_document_id,
      'job_id', p_job_id,
      'checksum', normalized_checksum,
      'mime_type', normalized_mime_type,
      'byte_size', p_byte_size,
      'renderer_version', p_renderer_version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'storage_bucket', p_storage_bucket,
      'storage_scope', 'private'
    )
  );

  return query
  select new_artifact_id, completed_document_status, false;
end;
$$;

create trigger document_preview_jobs_immutable
before update or delete on public.document_preview_jobs
for each row execute function app.prevent_job_history_mutation();

create trigger document_preview_artifacts_immutable
before update or delete on public.document_preview_artifacts
for each row execute function app.prevent_job_history_mutation();

alter table public.document_preview_jobs enable row level security;
alter table public.document_preview_jobs force row level security;
alter table public.document_preview_artifacts enable row level security;
alter table public.document_preview_artifacts force row level security;

create policy document_preview_jobs_select
on public.document_preview_jobs
for select to authenticated
using (
  app.has_permission(workspace_id, 'documents.read')
  or (
    requested_by = app.current_user_id()
    and app.has_permission(workspace_id, 'documents.preview')
  )
);

create policy document_preview_artifacts_select
on public.document_preview_artifacts
for select to authenticated
using (
  app.has_permission(workspace_id, 'documents.read')
  or (
    requested_by = app.current_user_id()
    and app.has_permission(workspace_id, 'documents.preview')
  )
);

create policy document_preview_artifact_objects_select
on storage.objects
for select to authenticated
using (
  exists (
    select 1
    from public.document_preview_artifacts artifact
    where artifact.storage_bucket = storage.objects.bucket_id
      and artifact.storage_object_path = storage.objects.name
  )
);

revoke all on table
  public.document_preview_jobs,
  public.document_preview_artifacts
from public, anon, authenticated, service_role;

grant select on
  public.document_preview_jobs,
  public.document_preview_artifacts
to authenticated, service_role;

-- Browser access is read-only and RLS reduces reads to artifact rows already
-- visible through the workspace/requester policy above. Workers retain their
-- service-role storage path for writes.
revoke insert, update, delete on storage.objects from authenticated;
grant select on storage.objects to authenticated;

revoke all on function app.document_preview_storage_object_path(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function app.request_document_preview_job(
  uuid, text, uuid, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.complete_document_preview_artifact(
  uuid, uuid, uuid, text, uuid, text, text, text, text, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;

revoke execute on function app.request_document_preview(
  uuid, text, uuid, uuid, text, text, uuid
) from authenticated;
revoke execute on function app.complete_document_preview(
  uuid, uuid, boolean, text, text, text, uuid
) from service_role;

grant execute on function app.request_document_preview_job(
  uuid, text, uuid, uuid, text, text, uuid
) to authenticated;
grant execute on function app.complete_document_preview_artifact(
  uuid, uuid, uuid, text, uuid, text, text, text, text, bigint, text, text, text, uuid
) to service_role;

comment on table public.document_preview_jobs is
  'Append-only workspace mapping binding one preview document to its canonical outbox event and durable render job.';
comment on table public.document_preview_artifacts is
  'Append-only workspace provenance for one deterministic private HTML artifact per preview job.';
comment on function app.request_document_preview_job(
  uuid, text, uuid, uuid, text, text, uuid
) is
  'Authenticated transaction boundary that creates an immutable preview snapshot and canonical documents.render_preview outbox job together.';
comment on function app.complete_document_preview_artifact(
  uuid, uuid, uuid, text, uuid, text, text, text, text, bigint, text, text, text, uuid
) is
  'Service-only transaction boundary that lease-fences one deterministic private HTML artifact and completes its document.';
