-- VYN-EXP-001, VYN-JOB-001, VYN-STOR-001, VYN-AUD-001
-- M4-EXP-AC-001 through M4-EXP-AC-004 and T-EXP-001/T-EXP-002.
-- Authorized immutable export plans, durable jobs, artifacts, and opaque grants.

alter table public.export_files
  add column storage_generation text not null,
  add column verification_receipt jsonb not null,
  add constraint export_files_receipt_check check (
    pg_catalog.jsonb_typeof(verification_receipt)
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
  );

alter table public.export_download_authorizations
  add column idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  add column request_fingerprint text not null check (
    request_fingerprint ~ '^[a-f0-9]{64}$'
  ),
  add column signed_url_ttl_seconds integer not null check (
    signed_url_ttl_seconds between 30 and 300
  ),
  add column request_id text check (
    request_id is null or pg_catalog.char_length(request_id) <= 200
  ),
  add column correlation_id uuid not null,
  add column audit_event_id uuid not null,
  add constraint export_download_authorizations_actor_key_unique
    unique (workspace_id, requested_by, idempotency_key),
  add constraint export_download_authorizations_audit_fk
    foreign key (workspace_id, audit_event_id)
    references public.audit_events (workspace_id, id) on delete restrict,
  add constraint export_download_authorizations_ttl_check check (
    expires_at <= created_at + interval '5 minutes'
  );

drop trigger export_files_immutable on public.export_files;
create trigger export_files_immutable
before update or delete on public.export_files
for each row execute function app.m4_prevent_row_mutation();

create table public.export_run_jobs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  export_run_id uuid not null,
  outbox_event_id uuid not null,
  job_id uuid not null,
  requested_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, export_run_id),
  unique (workspace_id, outbox_event_id),
  unique (workspace_id, job_id),
  foreign key (workspace_id, export_run_id)
    references public.export_runs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, outbox_event_id)
    references public.outbox_events (workspace_id, id) on delete restrict,
  foreign key (workspace_id, job_id)
    references public.jobs (workspace_id, id) on delete restrict
);

create trigger export_run_jobs_immutable
before update or delete on public.export_run_jobs
for each row execute function app.m4_prevent_row_mutation();
alter table public.export_run_jobs enable row level security;
alter table public.export_run_jobs force row level security;
create policy export_run_jobs_select on public.export_run_jobs
for select to authenticated using (
  app.has_permission(workspace_id, 'exports.read')
  and (requested_by = auth.uid() or app.has_permission(workspace_id, 'jobs.read'))
);
revoke all on table public.export_run_jobs from public, anon, authenticated;
grant select on table public.export_run_jobs to authenticated;
grant select, insert, update, delete on table public.export_run_jobs to service_role;

create function app.m4_export_storage_object_path(
  p_workspace_id uuid,
  p_export_run_id uuid,
  p_checksum text,
  p_format text
)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if p_checksum !~ '^[a-f0-9]{64}$' or p_format not in ('csv', 'xlsx') then
    raise exception using errcode = '22023', message = 'invalid export storage path inputs';
  end if;
  return p_workspace_id::text || '/exports/' || p_export_run_id::text
    || '/v1/' || p_checksum || '.' || p_format;
end;
$$;

create function app.m4_resolve_export_sort_plan(
  p_authorized_column_plan jsonb,
  p_sort_specification jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  requested_sort jsonb;
  requested_key text;
  requested_source text;
  requested_direction text;
  resolved_source text;
  matching_columns integer;
  resolved_plan jsonb := '[]'::jsonb;
begin
  if pg_catalog.jsonb_typeof(p_authorized_column_plan) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_authorized_column_plan) not between 1 and 100
    or pg_catalog.jsonb_typeof(p_sort_specification) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_sort_specification) > 100
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_authorized_column_plan) column_plan(value)
      where pg_catalog.jsonb_typeof(column_plan.value) is distinct from 'object'
        or pg_catalog.jsonb_typeof(column_plan.value -> 'key') is distinct from 'string'
        or pg_catalog.jsonb_typeof(column_plan.value -> 'source') is distinct from 'string'
        or column_plan.value ->> 'key' !~ '^[a-z][a-z0-9_]{0,95}$'
        or column_plan.value ->> 'source'
          !~ '^[a-z][a-z0-9_]{0,95}(?:\.[a-z][a-z0-9_]{0,95})+$'
    )
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_authorized_column_plan) column_plan(value)
      group by column_plan.value ->> 'key'
      having pg_catalog.count(*) > 1
    ) then
    raise exception using
      errcode = '23514',
      message = 'authorized export columns are invalid';
  end if;

  if pg_catalog.jsonb_array_length(p_sort_specification) = 0 then
    select column_plan.value ->> 'source' into resolved_source
    from pg_catalog.jsonb_array_elements(p_authorized_column_plan)
      with ordinality column_plan(value, ordinal)
    order by column_plan.ordinal
    limit 1;
    resolved_plan := pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'direction', 'asc',
        'source', resolved_source
      )
    );
  else
    for requested_sort in
      select sort_entry.value
      from pg_catalog.jsonb_array_elements(p_sort_specification)
        with ordinality sort_entry(value, ordinal)
      order by sort_entry.ordinal
    loop
      if pg_catalog.jsonb_typeof(requested_sort) is distinct from 'object'
        or pg_catalog.jsonb_typeof(requested_sort -> 'direction')
          is distinct from 'string'
        or requested_sort ->> 'direction' not in ('asc', 'desc')
        or pg_catalog.jsonb_array_length(
          pg_catalog.jsonb_path_query_array(requested_sort, '$.keyvalue()')
        ) <> 2
        or ((requested_sort ? 'key') = (requested_sort ? 'source'))
        or exists (
          select 1 from pg_catalog.jsonb_object_keys(requested_sort) property(key)
          where property.key not in ('direction', 'key', 'source')
        ) then
        raise exception using
          errcode = '23514',
          message = 'export sort specification is invalid';
      end if;

      requested_direction := requested_sort ->> 'direction';
      requested_key := case when requested_sort ? 'key'
        then requested_sort ->> 'key' else null end;
      requested_source := case when requested_sort ? 'source'
        then requested_sort ->> 'source' else null end;
      if requested_key is not null then
        if pg_catalog.jsonb_typeof(requested_sort -> 'key') is distinct from 'string'
          or requested_key !~ '^[a-z][a-z0-9_]{0,95}$' then
          raise exception using
            errcode = '23514',
            message = 'export sort specification is invalid';
        end if;
        select pg_catalog.count(*)::integer, pg_catalog.min(column_plan.value ->> 'source')
        into matching_columns, resolved_source
        from pg_catalog.jsonb_array_elements(p_authorized_column_plan) column_plan(value)
        where column_plan.value ->> 'key' = requested_key;
      else
        if pg_catalog.jsonb_typeof(requested_sort -> 'source') is distinct from 'string'
          or requested_source
            !~ '^[a-z][a-z0-9_]{0,95}(?:\.[a-z][a-z0-9_]{0,95})+$' then
          raise exception using
            errcode = '23514',
            message = 'export sort specification is invalid';
        end if;
        select pg_catalog.count(*)::integer
        into matching_columns
        from pg_catalog.jsonb_array_elements(p_authorized_column_plan) column_plan(value)
        where column_plan.value ->> 'source' = requested_source;
        resolved_source := requested_source;
      end if;
      if matching_columns = 0 then
        raise exception using
          errcode = '42501',
          message = 'export sort references an unauthorized column';
      end if;
      resolved_plan := resolved_plan || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'direction', requested_direction,
          'source', resolved_source
        )
      );
    end loop;
  end if;

  return resolved_plan || pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'direction', 'asc',
      'opaque', true,
      'source', '__vynlo_source_id'
    )
  );
end;
$$;

create function app.m4_request_export_run(
  p_workspace_id uuid,
  p_definition_key text,
  p_requested_format text,
  p_locale text,
  p_filters jsonb,
  p_idempotency_key text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  export_run_id uuid,
  run_status text,
  job_id uuid,
  job_status text,
  expires_at timestamptz,
  audit_event_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  definition public.export_definitions%rowtype;
  version public.export_versions%rowtype;
  existing public.export_runs%rowtype;
  mapping public.export_run_jobs%rowtype;
  existing_job public.jobs%rowtype;
  authorized_plan jsonb;
  authorized_sort_plan jsonb;
  unknown_filter text;
  fingerprint text;
  new_run_id uuid := pg_catalog.gen_random_uuid();
  expiry timestamptz;
  queued record;
  audit_id uuid;
  normalized_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  normalized_definition_key text := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_definition_key, ''))
  );
begin
  actor_user_id := app.require_vertical_slice_permission(
    p_workspace_id, 'exports.run'
  );
  perform app.require_vertical_slice_permission(p_workspace_id, 'exports.read');
  if p_requested_format not in ('csv', 'xlsx')
    or coalesce(p_locale, '') !~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'
    or pg_catalog.jsonb_typeof(p_filters) <> 'object'
    or not app.m3_inert_json_is_safe(p_filters)
    or pg_catalog.octet_length(p_filters::text) > 65536
    or normalized_definition_key !~ '^[a-z][a-z0-9_]{0,95}$'
    or pg_catalog.char_length(normalized_key) not between 8 and 200
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid export run command';
  end if;

  -- Idempotency is bound only to the caller's stable command. Resolve it
  -- before consulting mutable activation/approval state so an exact retry
  -- keeps returning the original immutable run after configuration rotates.
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'exportDefinitionKey', normalized_definition_key,
    'format', p_requested_format,
    'locale', p_locale,
    'filters', p_filters,
    'reason', normalized_reason
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fexport_run\x1f' || actor_user_id::text
      || E'\x1f' || normalized_key, 0
  ));
  select run.* into existing from public.export_runs run
  where run.workspace_id = p_workspace_id
    and run.requested_by = actor_user_id
    and run.idempotency_key = normalized_key;
  if found then
    if existing.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'export run idempotency conflict';
    end if;
    select link.* into mapping from public.export_run_jobs link
    where link.workspace_id = p_workspace_id and link.export_run_id = existing.id;
    select job.* into existing_job from public.jobs job
    where job.workspace_id = p_workspace_id and job.id = mapping.job_id;
    if mapping.id is null or existing_job.id is null then
      raise exception using errcode = '23514', message = 'export run job mapping is missing';
    end if;
    return query select existing.id, existing.status, existing_job.id,
      existing_job.status, existing.expires_at,
      (select event.id from public.audit_events event
       where event.workspace_id = p_workspace_id
         and event.entity_type = 'export_run' and event.entity_id = existing.id
         and event.action = 'export.run_requested'
       order by event.occurred_at, event.id limit 1), true;
    return;
  end if;

  select target.* into definition from public.export_definitions target
  where target.workspace_id = p_workspace_id
    and target.key = normalized_definition_key;
  select candidate.* into version from public.export_versions candidate
  where candidate.workspace_id = p_workspace_id
    and candidate.export_definition_id = definition.id
    and candidate.status = 'active';
  if definition.id is null or version.id is null
    or not p_requested_format = any(version.formats)
    or not app.m4_exact_approval_valid(
      p_workspace_id, version.approval_record_id, 'export_definition',
      'export.' || definition.key::text, version.version, version.id,
      version.checksum
    ) then
    raise exception using errcode = '23514', message = 'active approved export definition is required';
  end if;
  perform app.require_vertical_slice_permission(
    p_workspace_id, version.permission_key, version.step_up_required
  );
  if version.sensitivity <> 'standard' then
    perform app.require_vertical_slice_permission(
      p_workspace_id, 'exports.run_sensitive', true
    );
  end if;
  select filter.key into unknown_filter
  from pg_catalog.jsonb_object_keys(p_filters) filter(key)
  where not (coalesce(version.filter_schema -> 'properties', '{}'::jsonb) ? filter.key)
  limit 1;
  if unknown_filter is not null then
    raise exception using errcode = '23514', message = 'export filter is not declared';
  end if;
  if not app.m4_json_schema_value_valid(
    version.filter_schema, version.filter_schema, p_filters, 0
  ) then
    raise exception using errcode = '23514', message = 'export filters do not match the approved schema';
  end if;
  select pg_catalog.jsonb_agg(column_value order by ordinal) into authorized_plan
  from pg_catalog.jsonb_array_elements(version.columns) with ordinality
    column_plan(column_value, ordinal)
  where pg_catalog.jsonb_typeof(column_value) = 'object'
    and (
      nullif(column_value ->> 'permission', '') is null
      or app.has_permission(p_workspace_id, column_value ->> 'permission')
    )
    and (
      coalesce((column_value ->> 'sensitive')::boolean, false) is false
      or (
        app.has_permission(p_workspace_id, 'exports.run_sensitive')
        and app.has_recent_strong_auth(900)
      )
    );
  if authorized_plan is null or pg_catalog.jsonb_array_length(authorized_plan) = 0 then
    raise exception using errcode = '42501', message = 'no export columns are authorized';
  end if;
  authorized_sort_plan := app.m4_resolve_export_sort_plan(
    authorized_plan, version.sort_specification
  );
  expiry := pg_catalog.statement_timestamp()
    + pg_catalog.make_interval(secs => version.expires_after_seconds);
  insert into public.export_runs (
    id, workspace_id, export_definition_id, export_version_id,
    requested_format, locale, filters, authorized_column_plan,
    authorized_sort_plan, idempotency_key, command_fingerprint,
    requested_by, correlation_id, expires_at
  ) values (
    new_run_id, p_workspace_id, definition.id, version.id, p_requested_format,
    p_locale, p_filters, authorized_plan, authorized_sort_plan,
    normalized_key, fingerprint, actor_user_id, p_correlation_id, expiry
  );
  select job.* into queued from app.enqueue_outbox_job(
    p_workspace_id => p_workspace_id,
    p_event_name => 'export.run_requested',
    p_aggregate_type => 'export_run',
    p_aggregate_id => new_run_id,
    p_aggregate_version => 1,
    p_job_type => 'exports.generate',
    p_entity_type => 'export_run',
    p_entity_id => new_run_id,
    p_payload_schema_version => 1,
    p_payload => pg_catalog.jsonb_build_object(
      'export_run_id', new_run_id,
      'export_version_id', version.id,
      'source_key', version.source_key,
      'format', p_requested_format,
      'locale', p_locale,
      'filters_checksum', app.vertical_slice_fingerprint(p_filters),
      'column_plan_checksum', app.vertical_slice_fingerprint(authorized_plan),
      'sort_plan_checksum', app.vertical_slice_fingerprint(authorized_sort_plan)
    ),
    p_idempotency_key => 'export:' || normalized_key,
    p_correlation_id => p_correlation_id,
    p_actor_user_id => actor_user_id,
    p_request_id => p_request_id
  ) job;
  insert into public.export_run_jobs (
    workspace_id, export_run_id, outbox_event_id, job_id, requested_by
  ) values (
    p_workspace_id, new_run_id, queued.outbox_event_id, queued.job_id, actor_user_id
  );
  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'export.run_requested',
    p_entity_type => 'export_run',
    p_entity_id => new_run_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'queued', 'exportVersionId', version.id,
      'format', p_requested_format, 'locale', p_locale,
      'filtersChecksum', app.vertical_slice_fingerprint(p_filters),
      'columnPlanChecksum', app.vertical_slice_fingerprint(authorized_plan),
      'sortPlanChecksum', app.vertical_slice_fingerprint(authorized_sort_plan),
      'jobId', queued.job_id, 'expiresAt', expiry
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => case when version.step_up_required
      or version.sensitivity <> 'standard' then 'aal2'
      else coalesce(auth.jwt() ->> 'aal', 'unknown') end
  );
  return query select new_run_id, 'queued'::text, queued.job_id,
    queued.job_status, expiry, audit_id, false;
exception
  when invalid_text_representation then
    raise exception using errcode = '23514', message = 'export column sensitivity must be boolean';
end;
$$;

create function app.m4_load_export_run(
  p_workspace_id uuid,
  p_export_run_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid
)
returns table (
  export_run_id uuid,
  source_key text,
  requested_format text,
  locale text,
  filters jsonb,
  authorized_column_plan jsonb,
  sort_specification jsonb,
  maximum_rows integer,
  definition_key text,
  semantic_version text,
  definition_checksum text,
  expires_at timestamptz,
  completed_file_id uuid,
  completed_checksum text,
  completed_byte_size bigint,
  completed_row_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_run public.export_runs%rowtype;
  target_job public.jobs%rowtype;
  target_version public.export_versions%rowtype;
  target_definition public.export_definitions%rowtype;
  completed_file public.export_files%rowtype;
begin
  if auth.role() is distinct from 'service_role' or p_lease_token is null
    or pg_catalog.btrim(coalesce(p_worker_id, '')) = '' then
    raise exception using errcode = '42501', message = 'active service worker lease is required';
  end if;
  select job.* into target_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if not found or target_job.job_type is distinct from 'exports.generate'
    or target_job.entity_type is distinct from 'export_run'
    or target_job.entity_id is distinct from p_export_run_id
    or target_job.status is distinct from 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at is null
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp() then
    raise exception using errcode = '55000', message = 'export worker lease is invalid or expired';
  end if;
  perform 1 from public.export_run_jobs mapping
  where mapping.workspace_id = p_workspace_id
    and mapping.export_run_id = p_export_run_id and mapping.job_id = p_job_id;
  if not found then
    raise exception using errcode = '23514', message = 'export run job mapping is missing';
  end if;
  select run.* into target_run from public.export_runs run
  where run.workspace_id = p_workspace_id and run.id = p_export_run_id
  for update;
  if not found then
    raise exception using errcode = '23514', message = 'export run is not executable';
  end if;
  select file.* into completed_file
  from public.export_files file
  where file.workspace_id = p_workspace_id
    and file.export_run_id = p_export_run_id
    and file.format = target_run.requested_format
    and file.current
  order by file.version desc, file.id desc
  limit 1;
  if target_run.status = 'generated' then
    if completed_file.id is null
      or completed_file.checksum <> target_run.generated_checksum
      or target_run.row_count is null then
      raise exception using errcode = '23514', message = 'completed export artifact is missing or inconsistent';
    end if;
  elsif target_run.status not in ('queued', 'retry_wait', 'running')
    or target_run.expires_at <= pg_catalog.statement_timestamp()
    or completed_file.id is not null then
    raise exception using errcode = '23514', message = 'export run is not executable';
  end if;
  select version.* into target_version from public.export_versions version
  where version.workspace_id = p_workspace_id and version.id = target_run.export_version_id;
  select definition.* into target_definition from public.export_definitions definition
  where definition.workspace_id = p_workspace_id
    and definition.id = target_run.export_definition_id;
  if target_version.id is null or target_definition.id is null
    or pg_catalog.jsonb_typeof(target_job.payload) is distinct from 'object'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'export_run_id')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'export_version_id')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'filters_checksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'column_plan_checksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'sort_plan_checksum')
      is distinct from 'string'
    or target_job.payload ->> 'export_run_id'
      is distinct from target_run.id::text
    or target_job.payload ->> 'export_version_id'
      is distinct from target_version.id::text
    or target_job.payload ->> 'filters_checksum'
      is distinct from app.vertical_slice_fingerprint(target_run.filters)
    or target_job.payload ->> 'column_plan_checksum'
      is distinct from app.vertical_slice_fingerprint(target_run.authorized_column_plan)
    or target_job.payload ->> 'sort_plan_checksum'
      is distinct from app.vertical_slice_fingerprint(target_run.authorized_sort_plan) then
    raise exception using errcode = '23514', message = 'export job snapshot is inconsistent';
  end if;
  if target_run.status in ('queued', 'retry_wait') then
    update public.export_runs run set status = 'running'
    where run.workspace_id = p_workspace_id and run.id = p_export_run_id;
  end if;
  return query select
    target_run.id, target_version.source_key, target_run.requested_format,
    target_run.locale, target_run.filters, target_run.authorized_column_plan,
    target_run.authorized_sort_plan, target_version.maximum_rows,
    target_definition.key::text, target_version.semantic_version,
    target_version.checksum, target_run.expires_at,
    completed_file.id, completed_file.checksum, completed_file.byte_size,
    case when completed_file.id is null then null else target_run.row_count end;
end;
$$;

create function app.m4_complete_export_run(
  p_workspace_id uuid,
  p_export_run_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_storage_bucket text,
  p_storage_object_path text,
  p_storage_generation text,
  p_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_checksum text,
  p_row_count bigint,
  p_verification_receipt jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  export_file_id uuid,
  run_status text,
  row_count bigint,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_run public.export_runs%rowtype;
  target_job public.jobs%rowtype;
  existing public.export_files%rowtype;
  expected_path text;
  expected_mime text;
  new_file_id uuid := pg_catalog.gen_random_uuid();
begin
  if auth.role() <> 'service_role' or p_lease_token is null
    or p_storage_bucket !~ '^[a-z0-9][a-z0-9_-]{2,62}$'
    or pg_catalog.btrim(coalesce(p_storage_generation, '')) = ''
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_filename, ''))) not between 1 and 255
    or p_byte_size not between 1 and 104857600
    or p_checksum !~ '^[a-f0-9]{64}$'
    or p_row_count is null or p_row_count < 0
    or pg_catalog.jsonb_typeof(p_verification_receipt) is distinct from 'object'
    or app.job_payload_contains_forbidden_key(p_verification_receipt)
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid export completion receipt';
  end if;
  select run.* into target_run from public.export_runs run
  where run.workspace_id = p_workspace_id and run.id = p_export_run_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'export run was not found';
  end if;
  expected_path := app.m4_export_storage_object_path(
    p_workspace_id, p_export_run_id, p_checksum, target_run.requested_format
  );
  expected_mime := case target_run.requested_format
    when 'csv' then 'text/csv; charset=utf-8'
    else 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end;
  if p_storage_object_path <> expected_path or p_mime_type <> expected_mime
    or p_row_count > (
      select version.maximum_rows from public.export_versions version
      where version.workspace_id = p_workspace_id
        and version.id = target_run.export_version_id
    )
    or pg_catalog.jsonb_typeof(p_verification_receipt -> 'storage')
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
    or pg_catalog.jsonb_typeof(p_verification_receipt -> 'exportVersionId')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_verification_receipt -> 'filtersChecksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_verification_receipt -> 'columnPlanChecksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_verification_receipt -> 'sortPlanChecksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      p_verification_receipt -> 'sourceSnapshotRowCount'
    ) is distinct from 'number'
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
    or p_verification_receipt ->> 'exportVersionId'
      is distinct from target_run.export_version_id::text
    or p_verification_receipt ->> 'filtersChecksum'
      is distinct from app.vertical_slice_fingerprint(target_run.filters)
    or p_verification_receipt ->> 'columnPlanChecksum'
      is distinct from app.vertical_slice_fingerprint(target_run.authorized_column_plan)
    or p_verification_receipt ->> 'sortPlanChecksum'
      is distinct from app.vertical_slice_fingerprint(target_run.authorized_sort_plan)
    or p_verification_receipt ->> 'sourceSnapshotRowCount'
      is distinct from p_row_count::text then
    raise exception using errcode = '23514', message = 'export receipt does not match the authorized run';
  end if;
  select file.* into existing from public.export_files file
  where file.workspace_id = p_workspace_id and file.export_run_id = p_export_run_id
    and file.format = target_run.requested_format and file.current;
  if found then
    if existing.storage_bucket <> p_storage_bucket
      or existing.storage_object_path <> p_storage_object_path
      or existing.storage_generation <> p_storage_generation
      or existing.byte_size <> p_byte_size or existing.checksum <> p_checksum
      or existing.verification_receipt is distinct from p_verification_receipt then
      raise exception using errcode = '23505', message = 'export completion conflicts with existing file';
    end if;
    return query select existing.id, target_run.status, target_run.row_count, true;
    return;
  end if;
  select job.* into target_job from public.jobs job
  where job.workspace_id = p_workspace_id and job.id = p_job_id
  for update;
  if not found or target_job.status <> 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at <= pg_catalog.statement_timestamp()
    or target_run.status <> 'running' then
    raise exception using errcode = '55000', message = 'only the active export lease may complete';
  end if;
  perform 1 from public.export_run_jobs mapping
  where mapping.workspace_id = p_workspace_id
    and mapping.export_run_id = p_export_run_id and mapping.job_id = p_job_id;
  if not found then
    raise exception using errcode = '23514', message = 'export run job mapping is missing';
  end if;
  insert into public.export_files (
    id, workspace_id, export_run_id, version, format, storage_bucket,
    storage_object_path, storage_generation, filename, mime_type, byte_size,
    checksum, verification_receipt, expires_at
  ) values (
    new_file_id, p_workspace_id, p_export_run_id, 1,
    target_run.requested_format, p_storage_bucket, p_storage_object_path,
    p_storage_generation, p_filename, p_mime_type, p_byte_size, p_checksum,
    p_verification_receipt, target_run.expires_at
  );
  update public.export_runs run set
    status = 'generated', row_count = p_row_count,
    generated_checksum = p_checksum, failure_code = null
  where run.workspace_id = p_workspace_id and run.id = p_export_run_id;
  -- The generic DurableJobRunner remains the sole job settler after this
  -- domain completion commits.
  perform app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'export.run_generated',
    p_entity_type => 'export_run',
    p_entity_id => p_export_run_id,
    p_actor_type => 'worker',
    p_before_data => pg_catalog.jsonb_build_object('status', 'running'),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', 'generated', 'exportFileId', new_file_id,
      'checksum', p_checksum, 'rowCount', p_row_count
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => 'service',
    p_metadata => pg_catalog.jsonb_build_object('storageScope', 'private')
  );
  return query select new_file_id, 'generated'::text, p_row_count, false;
end;
$$;

create function app.m4_fail_export_run(
  p_workspace_id uuid,
  p_export_run_id uuid,
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
returns table (run_status text, job_status text, retry_at timestamptz, review_required boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.export_runs%rowtype;
  target_job public.jobs%rowtype;
begin
  if auth.role() <> 'service_role' or p_correlation_id is null then
    raise exception using errcode = '42501', message = 'service role and correlation ID are required';
  end if;
  perform 1 from public.export_run_jobs mapping
  where mapping.workspace_id = p_workspace_id
    and mapping.export_run_id = p_export_run_id and mapping.job_id = p_job_id;
  if not found then
    raise exception using errcode = '23514', message = 'export run job mapping is missing';
  end if;
  select run.* into target from public.export_runs run
  where run.workspace_id = p_workspace_id and run.id = p_export_run_id
  for update;
  if not found or target.status <> 'running' then
    raise exception using errcode = '23514', message = 'export run is not running';
  end if;
  select job.* into target_job from public.jobs job
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
    raise exception using errcode = '55000', message = 'only the active export lease may report failure';
  end if;
  -- DurableJobRunner calls app.fail_job after the handler rethrows. The jobs
  -- status trigger installed by the M4 API/read migration synchronizes the
  -- run state and audit evidence from that canonical settlement.
  return query select target.status, 'running'::text,
    null::timestamptz, false;
end;
$$;

create function app.m4_authorize_export_download(
  p_workspace_id uuid,
  p_export_run_id uuid,
  p_idempotency_key text,
  p_expires_in_seconds integer,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  authorization_id uuid,
  export_file_id uuid,
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
  target_run public.export_runs%rowtype;
  target_version public.export_versions%rowtype;
  target_file public.export_files%rowtype;
  existing public.export_download_authorizations%rowtype;
  normalized_key text := pg_catalog.btrim(coalesce(p_idempotency_key, ''));
  normalized_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  fingerprint text;
  new_id uuid := pg_catalog.gen_random_uuid();
  expiry timestamptz;
  audit_id uuid;
  captured_column jsonb;
  captured_permission text;
  captured_sensitive boolean;
begin
  actor_user_id := app.require_vertical_slice_permission(p_workspace_id, 'exports.read');
  if pg_catalog.char_length(normalized_key) not between 8 and 200
    or p_expires_in_seconds not between 30 and 300
    or normalized_reason = '' or pg_catalog.char_length(normalized_reason) > 2000
    or p_correlation_id is null then
    raise exception using errcode = '22023', message = 'invalid export download command';
  end if;
  select run.* into target_run from public.export_runs run
  where run.workspace_id = p_workspace_id and run.id = p_export_run_id;
  select version.* into target_version from public.export_versions version
  where version.workspace_id = p_workspace_id and version.id = target_run.export_version_id;
  select file.* into target_file from public.export_files file
  where file.workspace_id = p_workspace_id and file.export_run_id = p_export_run_id
    and file.current;
  if target_run.id is null or target_version.id is null or target_file.id is null
    or target_run.status <> 'generated'
    or target_run.expires_at <= pg_catalog.statement_timestamp()
    or target_file.expires_at <= pg_catalog.statement_timestamp() then
    raise exception using errcode = 'P0002', message = 'generated export file was not found';
  end if;
  perform app.require_vertical_slice_permission(
    p_workspace_id, target_version.permission_key, target_version.step_up_required
  );
  if target_version.sensitivity <> 'standard' then
    perform app.require_vertical_slice_permission(p_workspace_id, 'exports.run_sensitive', true);
  end if;
  -- The run stores the exact column plan authorized at request time. A later
  -- download must reauthorize every captured column permission, not merely the
  -- definition-level permission, so revoked sensitive access cannot be bypassed
  -- through an older generated artifact.
  for captured_column in
    select plan.value
    from pg_catalog.jsonb_array_elements(target_run.authorized_column_plan) plan(value)
  loop
    if pg_catalog.jsonb_typeof(captured_column) <> 'object'
      or (captured_column ? 'permission'
        and pg_catalog.jsonb_typeof(captured_column -> 'permission') <> 'string')
      or (captured_column ? 'permission'
        and pg_catalog.btrim(captured_column ->> 'permission')
          !~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$')
      or (captured_column ? 'sensitive'
        and pg_catalog.jsonb_typeof(captured_column -> 'sensitive') <> 'boolean') then
      raise exception using errcode = '23514', message = 'captured export column plan is invalid';
    end if;
    captured_permission := nullif(pg_catalog.btrim(captured_column ->> 'permission'), '');
    captured_sensitive := coalesce((captured_column ->> 'sensitive')::boolean, false);
    if captured_permission is not null then
      perform app.require_vertical_slice_permission(
        p_workspace_id, captured_permission, captured_sensitive
      );
    end if;
    if captured_sensitive then
      perform app.require_vertical_slice_permission(
        p_workspace_id, 'exports.run_sensitive', true
      );
    end if;
  end loop;
  fingerprint := app.vertical_slice_fingerprint(pg_catalog.jsonb_build_object(
    'exportRunId', p_export_run_id,
    'exportFileId', target_file.id,
    'expiresInSeconds', p_expires_in_seconds,
    'reason', normalized_reason
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_workspace_id::text || E'\x1fexport_download\x1f' || actor_user_id::text
      || E'\x1f' || normalized_key, 0
  ));
  select download_authorization.* into existing
  from public.export_download_authorizations download_authorization
  where download_authorization.workspace_id = p_workspace_id
    and download_authorization.requested_by = actor_user_id
    and download_authorization.idempotency_key = normalized_key;
  if found then
    if existing.request_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'export download idempotency conflict';
    end if;
    if existing.expires_at <= pg_catalog.statement_timestamp() then
      raise exception using errcode = '55000', message = 'export download authorization expired';
    end if;
    return query select existing.id, target_file.id, target_file.filename,
      target_file.mime_type, target_file.byte_size, target_file.checksum,
      existing.expires_at, existing.audit_event_id, true;
    return;
  end if;
  expiry := pg_catalog.statement_timestamp()
    + pg_catalog.make_interval(secs => p_expires_in_seconds);
  audit_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'export.download_authorized',
    p_entity_type => 'export_run',
    p_entity_id => p_export_run_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'exportFileId', target_file.id, 'checksum', target_file.checksum,
      'expiresAt', expiry
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => case when target_version.step_up_required
      or target_version.sensitivity <> 'standard' then 'aal2'
      else coalesce(auth.jwt() ->> 'aal', 'unknown') end
  );
  insert into public.export_download_authorizations (
    id, workspace_id, export_run_id, export_file_id, requested_by,
    grant_token_hash, file_checksum, reason, expires_at, idempotency_key,
    request_fingerprint, signed_url_ttl_seconds, request_id, correlation_id,
    audit_event_id
  ) values (
    new_id, p_workspace_id, p_export_run_id, target_file.id, actor_user_id,
    pg_catalog.encode(extensions.digest(new_id::text, 'sha256'), 'hex'),
    target_file.checksum, normalized_reason, expiry, normalized_key,
    fingerprint, p_expires_in_seconds, p_request_id, p_correlation_id, audit_id
  );
  return query select new_id, target_file.id, target_file.filename,
    target_file.mime_type, target_file.byte_size, target_file.checksum,
    expiry, audit_id, false;
end;
$$;

create function app.m4_load_export_download_authorization(p_authorization_id uuid)
returns table (
  authorization_id uuid,
  workspace_id uuid,
  export_run_id uuid,
  export_file_id uuid,
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
    download_authorization.id, download_authorization.workspace_id, download_authorization.export_run_id,
    file.id, file.storage_bucket, file.storage_object_path,
    file.storage_generation, file.filename, file.mime_type, file.byte_size,
    file.checksum, file.verification_receipt,
    download_authorization.signed_url_ttl_seconds, download_authorization.expires_at
  from public.export_download_authorizations download_authorization
  join public.export_files file
    on file.workspace_id = download_authorization.workspace_id
   and file.id = download_authorization.export_file_id
  where download_authorization.id = p_authorization_id
    and download_authorization.grant_token_hash = pg_catalog.encode(
      extensions.digest(p_authorization_id::text, 'sha256'), 'hex'
    )
    and download_authorization.file_checksum = file.checksum
    and download_authorization.expires_at > pg_catalog.statement_timestamp()
    and file.expires_at > pg_catalog.statement_timestamp();
  if not found then
    raise exception using errcode = 'P0002', message = 'export authorization was not found';
  end if;
end;
$$;

-- Provider coordinates and receipts remain service-only.
revoke all on table public.export_files from authenticated;
grant select (
  id, workspace_id, export_run_id, version, format, filename, mime_type,
  byte_size, checksum, current, expires_at, created_at
) on public.export_files to authenticated;

revoke all on function app.m4_export_storage_object_path(uuid, uuid, text, text)
from public, anon, authenticated, service_role;
revoke all on function app.m4_resolve_export_sort_plan(jsonb, jsonb)
from public, anon, authenticated, service_role;
revoke all on function app.m4_request_export_run(
  uuid, text, text, text, jsonb, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_load_export_run(uuid, uuid, uuid, text, uuid)
from public, anon, authenticated;
revoke all on function app.m4_complete_export_run(
  uuid, uuid, uuid, text, uuid, text, text, text, text, text, bigint,
  text, bigint, jsonb, text, uuid
) from public, anon, authenticated;
revoke all on function app.m4_fail_export_run(
  uuid, uuid, uuid, text, uuid, text, text, text, integer, text, uuid
) from public, anon, authenticated;
revoke all on function app.m4_authorize_export_download(
  uuid, uuid, text, integer, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m4_load_export_download_authorization(uuid)
from public, anon, authenticated;

grant execute on function app.m4_request_export_run(
  uuid, text, text, text, jsonb, text, text, text, uuid
) to authenticated;
grant execute on function app.m4_load_export_run(uuid, uuid, uuid, text, uuid)
to service_role;
grant execute on function app.m4_complete_export_run(
  uuid, uuid, uuid, text, uuid, text, text, text, text, text, bigint,
  text, bigint, jsonb, text, uuid
) to service_role;
grant execute on function app.m4_fail_export_run(
  uuid, uuid, uuid, text, uuid, text, text, text, integer, text, uuid
) to service_role;
grant execute on function app.m4_authorize_export_download(
  uuid, uuid, text, integer, text, text, uuid
) to authenticated;
grant execute on function app.m4_load_export_download_authorization(uuid)
to service_role;

comment on table public.export_run_jobs is
  'Canonical durable job linkage for one exact-version, actor-authorized export plan.';
