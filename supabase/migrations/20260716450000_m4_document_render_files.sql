-- VYN-DOC-001, VYN-JOB-001, VYN-STOR-001, VYN-AUD-001
-- M4-DOC-AC-004 through M4-DOC-AC-007 and T-DOC-003/T-DOC-005/T-DOC-006.
-- Lease-fenced official PDF attempts and verified immutable signed-file linkage.

alter table public.document_files
  drop constraint document_files_mime_type_check,
  add column storage_generation text,
  add column verification_receipt jsonb,
  add constraint document_files_mime_type_check check (
    mime_type in (
      'application/pdf', 'image/jpeg', 'image/png', 'image/webp',
      'image/heic', 'image/heif'
    )
  ),
  add constraint document_files_verification_shape_check check (
    (
      role in ('generated_original', 'signed_scan')
      and storage_generation is not null
      and verification_receipt is not null
      and pg_catalog.btrim(storage_generation) <> ''
      and pg_catalog.jsonb_typeof(verification_receipt)
        is not distinct from 'object'
      and pg_catalog.jsonb_typeof(verification_receipt -> 'storage')
        is not distinct from 'object'
      and pg_catalog.jsonb_typeof(
        verification_receipt -> 'storage' -> 'bucket'
      ) is not distinct from 'string'
      and pg_catalog.jsonb_typeof(
        verification_receipt -> 'storage' -> 'objectKey'
      ) is not distinct from 'string'
      and pg_catalog.jsonb_typeof(
        verification_receipt -> 'storage' -> 'generation'
      ) is not distinct from 'string'
      and pg_catalog.jsonb_typeof(
        verification_receipt -> 'storage' -> 'byteSize'
      ) is not distinct from 'number'
      and pg_catalog.jsonb_typeof(
        verification_receipt -> 'storage' -> 'checksumSha256'
      ) is not distinct from 'string'
      and verification_receipt -> 'storage' ->> 'bucket'
        is not distinct from storage_bucket
      and verification_receipt -> 'storage' ->> 'objectKey'
        is not distinct from storage_object_path
      and verification_receipt -> 'storage' ->> 'generation'
        is not distinct from storage_generation
      and verification_receipt -> 'storage' ->> 'byteSize'
        is not distinct from byte_size::text
      and verification_receipt -> 'storage' ->> 'checksumSha256'
        is not distinct from checksum
    )
    or (
      role not in ('generated_original', 'signed_scan')
      and storage_generation is null
      and verification_receipt is null
    )
  );

create function app.m4_official_document_filename(p_official_number text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  source_value text := p_official_number;
  portable_stem text;
  first_segment text;
  requires_checksum boolean;
begin
  if source_value is null
    or pg_catalog.char_length(source_value) not between 1 and 128
    or pg_catalog.btrim(source_value) is distinct from source_value
    or source_value ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'invalid official document number';
  end if;
  portable_stem := pg_catalog.regexp_replace(
    source_value, '[^A-Za-z0-9._-]+', '-', 'g'
  );
  portable_stem := pg_catalog.regexp_replace(portable_stem, '^[.-]+', '');
  portable_stem := pg_catalog.regexp_replace(portable_stem, '[.-]+$', '');
  if portable_stem = '' then portable_stem := 'document'; end if;
  first_segment := pg_catalog.split_part(portable_stem, '.', 1);
  requires_checksum := portable_stem is distinct from source_value
    or pg_catalog.lower(first_segment) ~ '^(con|prn|aux|nul|com[1-9]|lpt[1-9])$'
    or source_value in ('.', '..');
  if requires_checksum then
    portable_stem := pg_catalog.left(portable_stem, 100) || '-'
      || pg_catalog.left(pg_catalog.encode(
        extensions.digest(source_value, 'sha256'), 'hex'
      ), 16);
  end if;
  return portable_stem || '.pdf';
end;
$$;

revoke all on function app.m4_official_document_filename(text)
from public, anon, authenticated;
grant execute on function app.m4_official_document_filename(text) to service_role;

drop trigger document_files_immutable_content on public.document_files;
create trigger document_files_immutable_content
before update on public.document_files
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'document_id', 'role', 'version', 'media_file_id',
  'storage_bucket', 'storage_object_path', 'storage_generation', 'filename',
  'mime_type', 'byte_size', 'checksum', 'verification_receipt',
  'generated_by_job_id', 'recorded_by', 'recorded_at'
);

create table public.document_render_attempts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  document_id uuid not null,
  attempt_number integer not null check (attempt_number > 0),
  outbox_event_id uuid not null,
  job_id uuid not null,
  replay_of_job_id uuid,
  requested_by uuid not null references auth.users (id) on delete restrict,
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, document_id, attempt_number),
  unique (workspace_id, job_id),
  unique (workspace_id, outbox_event_id),
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, replay_of_job_id)
    references public.jobs (workspace_id, id) on delete restrict
);

create trigger document_render_attempts_immutable
before update or delete on public.document_render_attempts
for each row execute function app.m4_prevent_row_mutation();

alter table public.document_render_attempts enable row level security;
alter table public.document_render_attempts force row level security;
create policy document_render_attempts_select
on public.document_render_attempts
for select to authenticated using (
  app.has_permission(workspace_id, 'documents.read')
  and (requested_by = auth.uid() or app.has_permission(workspace_id, 'jobs.read'))
);
revoke all on table public.document_render_attempts
from public, anon, authenticated;
grant select on table public.document_render_attempts to authenticated;
grant select, insert, update, delete on table public.document_render_attempts to service_role;

create function app.m4_record_initial_render_attempt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.document_render_attempts (
    workspace_id, document_id, attempt_number, outbox_event_id, job_id,
    requested_by, reason
  ) values (
    new.workspace_id, new.document_id, 1, new.outbox_event_id, new.job_id,
    new.requested_by, 'initial official render request'
  );
  return new;
end;
$$;

insert into public.document_render_attempts (
  workspace_id, document_id, attempt_number, outbox_event_id, job_id,
  requested_by, reason
)
select
  mapping.workspace_id, mapping.document_id, 1, mapping.outbox_event_id,
  mapping.job_id, mapping.requested_by, 'initial official render request'
from public.document_render_jobs mapping
where mapping.render_mode = 'official'
on conflict (workspace_id, document_id, attempt_number) do nothing;

create trigger document_render_jobs_record_initial_attempt
after insert on public.document_render_jobs
for each row when (new.render_mode = 'official')
execute function app.m4_record_initial_render_attempt();

create function app.m4_document_storage_object_path(
  p_workspace_id uuid,
  p_document_id uuid,
  p_role text,
  p_version integer,
  p_checksum text,
  p_extension text
)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if p_role not in ('generated_original', 'void_notice')
    or p_version <= 0
    or p_checksum !~ '^[a-f0-9]{64}$'
    or p_extension not in ('pdf', 'jpg', 'png') then
    raise exception using errcode = '22023', message = 'invalid document storage path inputs';
  end if;
  return p_workspace_id::text || '/documents/' || p_document_id::text || '/'
    || p_role || '/v' || p_version::text || '/' || p_checksum || '.' || p_extension;
end;
$$;

create function app.m4_assert_signed_upload_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.documents%rowtype;
begin
  if new.media_kind <> 'signed_document' then
    return new;
  end if;
  select document.* into target
  from public.documents document
  where document.workspace_id = new.workspace_id and document.id = new.document_id;
  if not found or target.mode <> 'official'
    or target.status not in ('generated', 'signed_received', 'completed') then
    raise exception using errcode = '23514', message = 'signed upload requires an eligible official document';
  end if;
  return new;
end;
$$;

create trigger legal_original_upload_sessions_document_guard
before insert on public.legal_original_upload_sessions
for each row execute function app.m4_assert_signed_upload_document();

create function app.m4_attach_verified_signed_file()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  asset public.media_assets%rowtype;
  document public.documents%rowtype;
  next_version integer;
  new_file_id uuid := pg_catalog.gen_random_uuid();
  extension text;
  generated_filename text;
begin
  if new.file_class <> 'legal_document_original'
    or new.variant <> 'legal_original' then
    return new;
  end if;
  select candidate.* into asset
  from public.media_assets candidate
  where candidate.workspace_id = new.workspace_id and candidate.id = new.media_id;
  if not found or asset.media_kind <> 'signed_document' then
    return new;
  end if;
  select target.* into document
  from public.documents target
  where target.workspace_id = new.workspace_id and target.id = asset.document_id
  for update;
  if not found or document.mode <> 'official'
    or document.status not in ('generated', 'signed_received', 'completed') then
    raise exception using errcode = '23514', message = 'verified signed file has no eligible official document';
  end if;
  if new.deleted_at is not null
    or new.retention_policy <> 'preserve_original'
    or new.storage_generation is null
    or pg_catalog.jsonb_typeof(new.verification_receipt -> 'malwareScan')
      is distinct from 'object'
    or pg_catalog.jsonb_typeof(
      new.verification_receipt -> 'malwareScan' -> 'verdict'
    ) is distinct from 'string'
    or new.verification_receipt -> 'malwareScan' ->> 'verdict'
      is distinct from 'clean' then
    raise exception using errcode = '23514', message = 'signed file must be a verified clean preserved original';
  end if;

  select coalesce(pg_catalog.max(file.version), 0) + 1 into next_version
  from public.document_files file
  where file.workspace_id = new.workspace_id
    and file.document_id = document.id
    and file.role = 'signed_scan';
  update public.document_files file set current = false
  where file.workspace_id = new.workspace_id
    and file.document_id = document.id
    and file.role = 'signed_scan'
    and file.current;
  extension := case new.mime_type
    when 'application/pdf' then 'pdf'
    when 'image/jpeg' then 'jpg'
    when 'image/png' then 'png'
    when 'image/webp' then 'webp'
    when 'image/heic' then 'heic'
    else 'heif'
  end;
  generated_filename := 'signed-scan-v' || next_version::text || '.' || extension;
  insert into public.document_files (
    id, workspace_id, document_id, role, version, media_file_id,
    storage_bucket, storage_object_path, storage_generation, filename,
    mime_type, byte_size, checksum, verification_receipt, recorded_by
  ) values (
    new_file_id, new.workspace_id, document.id, 'signed_scan', next_version,
    new.id, new.storage_bucket, new.storage_object_key, new.storage_generation,
    generated_filename, new.mime_type, new.byte_size, new.checksum_sha256,
    new.verification_receipt, asset.created_by
  );
  update public.documents target set
    aggregate_version = target.aggregate_version + 1
  where target.workspace_id = new.workspace_id and target.id = document.id;
  perform app.write_audit_event(
    p_workspace_id => new.workspace_id,
    p_action => 'document.signed_file_verified',
    p_entity_type => 'document',
    p_entity_id => document.id,
    p_actor_user_id => asset.created_by,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'documentFileId', new_file_id,
      'mediaFileId', new.id,
      'version', next_version,
      'checksum', new.checksum_sha256
    ),
    p_auth_assurance => 'step_up',
    p_metadata => pg_catalog.jsonb_build_object('storageScope', 'private')
  );
  return new;
end;
$$;

create trigger media_files_attach_verified_signed_document
after insert on public.media_files
for each row execute function app.m4_attach_verified_signed_file();

create function app.m4_load_official_document_render(
  p_workspace_id uuid,
  p_document_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid
)
returns table (
  document_id uuid,
  official_number text,
  locale text,
  source_html text,
  source_css text,
  asset_manifest jsonb,
  font_manifest jsonb,
  renderer_version text,
  source_bundle_checksum text,
  render_input_snapshot jsonb,
  render_input_checksum text,
  version_snapshot jsonb,
  version_snapshot_checksum text,
  completed_file_id uuid,
  completed_checksum text,
  completed_byte_size bigint,
  completed_aggregate_version bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_document public.documents%rowtype;
  prior_document public.documents%rowtype;
  target_template public.document_template_versions%rowtype;
  target_job public.jobs%rowtype;
  completed_file public.document_files%rowtype;
begin
  if auth.role() is distinct from 'service_role'
    or pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or pg_catalog.char_length(p_worker_id) > 200
    or p_lease_token is null then
    raise exception using errcode = '42501', message = 'active service worker lease is required';
  end if;
  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if not found or target_job.job_type is distinct from 'documents.render_pdf'
    or target_job.entity_type is distinct from 'document'
    or target_job.entity_id is distinct from p_document_id
    or target_job.status is distinct from 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at is null
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp() then
    raise exception using errcode = '55000', message = 'official render lease is invalid or expired';
  end if;
  perform 1 from public.document_render_attempts attempt
  where attempt.workspace_id = p_workspace_id
    and attempt.document_id = p_document_id and attempt.job_id = p_job_id;
  if not found then
    raise exception using errcode = '23514', message = 'official render attempt mapping is missing';
  end if;
  select document.* into target_document
  from public.documents document
  where document.workspace_id = p_workspace_id and document.id = p_document_id
  for update;
  if not found or target_document.mode is distinct from 'official'
    or pg_catalog.jsonb_typeof(target_job.payload) is distinct from 'object'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'document_id')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'template_version_id')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'render_input_checksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'version_snapshot_checksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'mode')
      is distinct from 'string'
    or target_job.payload ->> 'document_id'
      is distinct from target_document.id::text
    or target_job.payload ->> 'template_version_id'
      is distinct from target_document.template_version_id::text
    or target_job.payload ->> 'render_input_checksum'
      is distinct from target_document.render_input_checksum
    or target_job.payload ->> 'version_snapshot_checksum'
      is distinct from target_document.version_snapshot_checksum
    or target_job.payload ->> 'mode' is distinct from 'official' then
    raise exception using errcode = '23514', message = 'official render snapshot or job linkage is invalid';
  end if;
  select file.* into completed_file
  from public.document_files file
  where file.workspace_id = p_workspace_id
    and file.document_id = p_document_id
    and file.role = 'generated_original'
    and file.current
  order by file.version desc, file.id desc
  limit 1;
  if target_document.status in (
    'generated', 'signed_received', 'completed', 'voided', 'superseded'
  ) then
    if completed_file.id is null
      or completed_file.checksum <> target_document.generated_checksum then
      raise exception using errcode = '23514', message = 'completed official render file is missing or inconsistent';
    end if;
  elsif target_document.status not in ('generating', 'generation_failed')
    or completed_file.id is not null then
    raise exception using errcode = '23514', message = 'official document is not renderable';
  end if;
  if target_document.status = 'generation_failed' then
    update public.documents document set
      status = 'generating', failure_code = null,
      aggregate_version = document.aggregate_version + 1
    where document.workspace_id = p_workspace_id and document.id = p_document_id;
  end if;
  select template.* into target_template
  from public.document_template_versions template
  where template.workspace_id = p_workspace_id
    and template.id = target_document.template_version_id;
  if not found
    or target_template.source_bundle_checksum
      <> target_document.version_snapshot ->> 'templateBundleChecksum'
    or target_template.renderer_version <> target_document.renderer_version then
    raise exception using errcode = '23514', message = 'official template snapshot no longer matches';
  end if;
  return query select
    target_document.id, target_document.official_number::text,
    target_document.locale, target_template.source_html, target_template.source_css,
    target_template.asset_manifest, target_template.font_manifest,
    target_template.renderer_version, target_template.source_bundle_checksum,
    target_document.render_input_snapshot, target_document.render_input_checksum,
    target_document.version_snapshot, target_document.version_snapshot_checksum,
    completed_file.id, completed_file.checksum, completed_file.byte_size,
    case when completed_file.id is null then null
      else target_document.aggregate_version end;
end;
$$;

create function app.m4_complete_official_document_render(
  p_workspace_id uuid,
  p_document_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_storage_bucket text,
  p_storage_object_path text,
  p_storage_generation text,
  p_byte_size bigint,
  p_checksum text,
  p_renderer_version text,
  p_verification_receipt jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_file_id uuid,
  document_status text,
  aggregate_version bigint,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_document public.documents%rowtype;
  prior_document public.documents%rowtype;
  target_job public.jobs%rowtype;
  target_attempt public.document_render_attempts%rowtype;
  existing_file public.document_files%rowtype;
  expected_path text;
  new_file_id uuid := pg_catalog.gen_random_uuid();
begin
  if auth.role() <> 'service_role'
    or pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or p_lease_token is null
    or p_storage_bucket !~ '^[a-z0-9][a-z0-9_-]{2,62}$'
    or pg_catalog.btrim(coalesce(p_storage_generation, '')) = ''
    or p_byte_size not between 1 and 52428800
    or p_checksum !~ '^[a-f0-9]{64}$'
    or pg_catalog.jsonb_typeof(p_verification_receipt) is distinct from 'object'
    or app.job_payload_contains_forbidden_key(p_verification_receipt)
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid official render completion receipt';
  end if;
  select document.* into target_document
  from public.documents document
  where document.workspace_id = p_workspace_id and document.id = p_document_id
  for update;
  if not found or target_document.mode <> 'official' then
    raise exception using errcode = '23514', message = 'official document was not found';
  end if;
  expected_path := app.m4_document_storage_object_path(
    p_workspace_id, p_document_id, 'generated_original', 1, p_checksum, 'pdf'
  );
  if p_storage_object_path <> expected_path
    or p_renderer_version <> target_document.renderer_version
    or pg_catalog.jsonb_typeof(p_verification_receipt -> 'storage')
      is distinct from 'object'
    or pg_catalog.jsonb_typeof(p_verification_receipt -> 'renderer')
      is distinct from 'object'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'storage' -> 'bucket'
    ) is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'storage' -> 'objectKey'
    ) is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'storage' -> 'generation'
    ) is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'storage' -> 'byteSize'
    ) is distinct from 'number'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'storage' -> 'checksumSha256'
    ) is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'renderer' -> 'version'
    ) is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_verification_receipt -> 'officialNumber')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'sourceBundleChecksum'
    ) is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'renderInputChecksum'
    ) is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'versionSnapshotChecksum'
    ) is distinct from 'string'
    or p_verification_receipt -> 'storage' ->> 'bucket'
      is distinct from p_storage_bucket
    or p_verification_receipt -> 'storage' ->> 'objectKey'
      is distinct from p_storage_object_path
    or p_verification_receipt -> 'storage' ->> 'generation'
      is distinct from p_storage_generation
    or p_verification_receipt -> 'storage' ->> 'byteSize'
      is distinct from p_byte_size::text
    or p_verification_receipt -> 'storage' ->> 'checksumSha256'
      is distinct from p_checksum
    or p_verification_receipt -> 'renderer' ->> 'version'
      is distinct from p_renderer_version
    or p_verification_receipt ->> 'officialNumber'
      is distinct from target_document.official_number
    or p_verification_receipt ->> 'sourceBundleChecksum'
      is distinct from target_document.version_snapshot ->> 'templateBundleChecksum'
    or p_verification_receipt ->> 'renderInputChecksum'
      is distinct from target_document.render_input_checksum
    or p_verification_receipt ->> 'versionSnapshotChecksum'
      is distinct from target_document.version_snapshot_checksum then
    raise exception using errcode = '23514', message = 'official render receipt does not match the immutable snapshot';
  end if;
  select file.* into existing_file
  from public.document_files file
  where file.workspace_id = p_workspace_id
    and file.document_id = p_document_id
    and file.role = 'generated_original' and file.current;
  if found then
    if existing_file.storage_bucket <> p_storage_bucket
      or existing_file.storage_object_path <> p_storage_object_path
      or existing_file.storage_generation <> p_storage_generation
      or existing_file.byte_size <> p_byte_size
      or existing_file.checksum <> p_checksum
      or existing_file.verification_receipt is distinct from p_verification_receipt then
      raise exception using errcode = '23505', message = 'official render completion conflicts with existing file';
    end if;
    return query select existing_file.id, target_document.status,
      target_document.aggregate_version, true;
    return;
  end if;
  select attempt.* into target_attempt
  from public.document_render_attempts attempt
  where attempt.workspace_id = p_workspace_id
    and attempt.document_id = p_document_id and attempt.job_id = p_job_id;
  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if target_attempt.id is null or target_job.id is null
    or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_document.status <> 'generating' then
    raise exception using errcode = '55000', message = 'only the active official render lease may complete';
  end if;
  insert into public.document_files (
    id, workspace_id, document_id, role, version, storage_bucket,
    storage_object_path, storage_generation, filename, mime_type, byte_size,
    checksum, verification_receipt, generated_by_job_id, recorded_by
  ) values (
    new_file_id, p_workspace_id, p_document_id, 'generated_original', 1,
    p_storage_bucket, p_storage_object_path, p_storage_generation,
    app.m4_official_document_filename(
      coalesce(target_document.official_number::text, p_document_id::text)
    ),
    'application/pdf', p_byte_size, p_checksum, p_verification_receipt,
    p_job_id, target_attempt.requested_by
  );
  update public.documents document set
    status = 'generated', generated_checksum = p_checksum, failure_code = null,
    aggregate_version = document.aggregate_version + 1
  where document.workspace_id = p_workspace_id and document.id = p_document_id;

  -- Supersession becomes authoritative only after the replacement PDF and
  -- checksum have committed. A failed render therefore leaves the prior legal
  -- document usable, while the pending-successor guard prevents a race.
  if target_document.supersedes_document_id is not null then
    select prior.* into prior_document
    from public.documents prior
    where prior.workspace_id = p_workspace_id
      and prior.id = target_document.supersedes_document_id
    for update;
    if not found
      or prior_document.mode <> 'official'
      or prior_document.status not in ('generated', 'signed_received', 'completed')
      or prior_document.superseded_by_document_id is not null
      or prior_document.aggregate_version is distinct from target_document.supersedes_expected_version then
      raise exception using errcode = '55000', message = 'document.supersession_prior_changed';
    end if;
    update public.documents prior set
      status = 'superseded',
      superseded_by_document_id = p_document_id,
      aggregate_version = prior.aggregate_version + 1
    where prior.workspace_id = p_workspace_id
      and prior.id = target_document.supersedes_document_id;
    perform app.write_audit_event(
      p_workspace_id => p_workspace_id,
      p_action => 'document.superseded',
      p_entity_type => 'document',
      p_entity_id => target_document.supersedes_document_id,
      p_actor_type => 'worker',
      p_before_data => pg_catalog.jsonb_build_object(
        'status', prior_document.status,
        'aggregateVersion', prior_document.aggregate_version
      ),
      p_after_data => pg_catalog.jsonb_build_object(
        'status', 'superseded',
        'aggregateVersion', prior_document.aggregate_version + 1,
        'supersededByDocumentId', p_document_id
      ),
      p_reason => 'Replacement rendered successfully.',
      p_request_id => p_request_id,
      p_correlation_id => p_correlation_id,
      p_auth_assurance => 'service',
      p_metadata => pg_catalog.jsonb_build_object(
        'replacementDocumentFileId', new_file_id,
        'replacementChecksum', p_checksum,
        'jobId', p_job_id
      )
    );
  end if;
  -- The generic DurableJobRunner owns job settlement after this domain
  -- transaction returns. Keeping the job lease running here avoids a second
  -- completion attempt and preserves the runner's one-settler invariant.
  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'document.official_generated',
    p_entity_type => 'document',
    p_entity_id => p_document_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object('status', 'generating'),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'generated', 'documentFileId', new_file_id,
      'checksum', p_checksum, 'jobId', p_job_id
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object(
      'storageScope', 'private', 'rendererVersion', p_renderer_version
    )
  );
  return query select new_file_id, 'generated'::text,
    target_document.aggregate_version + 1, false;
end;
$$;

create function app.m4_fail_official_document_render(
  p_workspace_id uuid,
  p_document_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_error_classification text,
  p_error_code text,
  p_error_detail_safe text,
  p_retry_after_seconds integer,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  document_status text,
  job_status text,
  retry_at timestamptz,
  review_required boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_document public.documents%rowtype;
  target_job public.jobs%rowtype;
begin
  if auth.role() <> 'service_role' or p_correlation_id is null then
    raise exception using errcode = '42501', message = 'service role and correlation ID are required';
  end if;
  perform 1 from public.document_render_attempts attempt
  where attempt.workspace_id = p_workspace_id
    and attempt.document_id = p_document_id and attempt.job_id = p_job_id;
  if not found then
    raise exception using errcode = '23514', message = 'official render attempt mapping is missing';
  end if;
  select document.* into target_document
  from public.documents document
  where document.workspace_id = p_workspace_id and document.id = p_document_id
  for update;
  if not found or target_document.mode <> 'official'
    or target_document.status <> 'generating' then
    raise exception using errcode = '23514', message = 'official document is not rendering';
  end if;
  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if not found or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or p_error_classification not in (
      'transient', 'rate_limited', 'permanent', 'validation', 'permission',
      'provider_auth', 'unknown'
    )
    or pg_catalog.btrim(coalesce(p_error_code, '')) = ''
    or pg_catalog.btrim(coalesce(p_error_detail_safe, '')) = '' then
    raise exception using errcode = '55000', message = 'only the active official render lease may report failure';
  end if;
  -- DurableJobRunner calls app.fail_job after the handler rethrows. The jobs
  -- status trigger installed by the M4 API/read migration then updates the
  -- document and audit evidence from that authoritative settlement.
  return query select target_document.status, 'running'::text,
    null::timestamptz, false;
end;
$$;

-- Provider coordinates are never exposed through authenticated table reads.
revoke all on table public.document_files from authenticated;
grant select (
  id, workspace_id, document_id, role, version, media_file_id, filename,
  mime_type, byte_size, checksum, current, generated_by_job_id,
  recorded_by, recorded_at
) on public.document_files to authenticated;

revoke all on function app.m4_record_initial_render_attempt()
from public, anon, authenticated, service_role;
revoke all on function app.m4_document_storage_object_path(uuid, uuid, text, integer, text, text)
from public, anon, authenticated, service_role;
revoke all on function app.m4_assert_signed_upload_document()
from public, anon, authenticated, service_role;
revoke all on function app.m4_attach_verified_signed_file()
from public, anon, authenticated, service_role;
revoke all on function app.m4_load_official_document_render(uuid, uuid, uuid, text, uuid)
from public, anon, authenticated;
revoke all on function app.m4_complete_official_document_render(
  uuid, uuid, uuid, text, uuid, text, text, text, bigint, text, text, jsonb, text, uuid
) from public, anon, authenticated;
revoke all on function app.m4_fail_official_document_render(
  uuid, uuid, uuid, text, uuid, text, text, text, integer, text, uuid
) from public, anon, authenticated;

grant execute on function app.m4_load_official_document_render(uuid, uuid, uuid, text, uuid)
to service_role;
grant execute on function app.m4_complete_official_document_render(
  uuid, uuid, uuid, text, uuid, text, text, text, bigint, text, text, jsonb, text, uuid
) to service_role;
grant execute on function app.m4_fail_official_document_render(
  uuid, uuid, uuid, text, uuid, text, text, text, integer, text, uuid
) to service_role;

comment on table public.document_render_attempts is
  'Append-only initial and dead-letter replay jobs for one immutable numbered document snapshot.';
