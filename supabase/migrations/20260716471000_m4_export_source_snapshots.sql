-- VYN-EXP-001, VYN-JOB-001, VYN-STOR-001, VYN-TEN-001
-- M4-EXP-AC-002/M4-EXP-AC-003 and T-EXP-001/T-EXP-002/T-JOB-003.
-- First-execution source snapshots make paged exports immutable and replay-safe.

create table public.export_run_source_snapshots (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  export_run_id uuid not null,
  source_key text not null check (source_key ~ '^[a-z][a-z0-9_]{0,95}$'),
  source_row_count integer not null check (source_row_count between 0 and 100001),
  source_fingerprint text not null check (source_fingerprint ~ '^[a-f0-9]{64}$'),
  captured_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, export_run_id),
  foreign key (workspace_id, export_run_id)
    references public.export_runs (workspace_id, id) on delete restrict
);

create table public.export_run_source_snapshot_rows (
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  export_run_id uuid not null,
  row_ordinal integer not null check (row_ordinal between 1 and 100001),
  source_row_id uuid not null,
  source_record jsonb not null check (
    pg_catalog.jsonb_typeof(source_record) is not distinct from 'object'
    and pg_catalog.jsonb_typeof(source_record -> 'workspace_id')
      is not distinct from 'string'
    and pg_catalog.jsonb_typeof(source_record -> 'id')
      is not distinct from 'string'
    and source_record ->> 'workspace_id' is not distinct from workspace_id::text
    and source_record ->> 'id' is not distinct from source_row_id::text
    and app.m3_inert_json_is_safe(source_record, 0)
    and pg_catalog.octet_length(source_record::text) <= 1048576
  ),
  record_fingerprint text not null check (record_fingerprint ~ '^[a-f0-9]{64}$'),
  primary key (workspace_id, export_run_id, row_ordinal),
  unique (workspace_id, export_run_id, source_row_id),
  foreign key (workspace_id, export_run_id)
    references public.export_runs (workspace_id, id) on delete restrict
);

create trigger export_run_source_snapshots_immutable
before update or delete on public.export_run_source_snapshots
for each row execute function app.m4_prevent_row_mutation();

create trigger export_run_source_snapshot_rows_immutable
before update or delete on public.export_run_source_snapshot_rows
for each row execute function app.m4_prevent_row_mutation();

alter table public.export_run_source_snapshots enable row level security;
alter table public.export_run_source_snapshots force row level security;
alter table public.export_run_source_snapshot_rows enable row level security;
alter table public.export_run_source_snapshot_rows force row level security;

revoke all on table
  public.export_run_source_snapshots,
  public.export_run_source_snapshot_rows
from public, anon, authenticated, service_role;

create function app.m4_read_export_source_snapshot_page(
  p_workspace_id uuid,
  p_export_run_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_after_ordinal integer default 0,
  p_page_size integer default 500
)
returns table (
  source_snapshot_id uuid,
  snapshot_captured_at timestamptz,
  source_row_count integer,
  source_snapshot_fingerprint text,
  next_ordinal integer,
  source_rows jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.jobs%rowtype;
  target_run public.export_runs%rowtype;
  target_version public.export_versions%rowtype;
  target_snapshot public.export_run_source_snapshots%rowtype;
  inserted_count integer;
  calculated_fingerprint text;
  page_last integer;
  page_records jsonb;
begin
  if auth.role() is distinct from 'service_role'
    or p_lease_token is null
    or pg_catalog.btrim(coalesce(p_worker_id, '')) = ''
    or p_after_ordinal not between 0 and 100001
    or p_page_size not between 1 and 500 then
    raise exception using
      errcode = '42501',
      message = 'active service worker lease and bounded snapshot page are required';
  end if;

  -- The run lock serializes domain completion while the first job read stays
  -- non-blocking so the durable runner can heartbeat during a long capture.
  select run.* into target_run
  from public.export_runs run
  where run.workspace_id = p_workspace_id
    and run.id = p_export_run_id
  for update;
  if not found
    or target_run.status is distinct from 'running'
    or target_run.expires_at is null
    or target_run.expires_at <= pg_catalog.clock_timestamp() then
    raise exception using errcode = '23514', message = 'export run is not executable';
  end if;

  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.id = p_job_id;
  if not found
    or target_job.job_type is distinct from 'exports.generate'
    or target_job.entity_type is distinct from 'export_run'
    or target_job.entity_id is distinct from p_export_run_id
    or target_job.status is distinct from 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at is null
    or target_job.lease_expires_at <= pg_catalog.clock_timestamp() then
    raise exception using errcode = '55000', message = 'export worker lease is invalid or expired';
  end if;

  perform 1
  from public.export_run_jobs mapping
  where mapping.workspace_id = p_workspace_id
    and mapping.export_run_id = p_export_run_id
    and mapping.job_id = p_job_id;
  if not found then
    raise exception using errcode = '23514', message = 'export run job mapping is missing';
  end if;

  select version.* into target_version
  from public.export_versions version
  where version.workspace_id = p_workspace_id
    and version.id = target_run.export_version_id;
  if not found
    or pg_catalog.jsonb_typeof(target_job.payload) is distinct from 'object'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'export_version_id')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'source_key')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'filters_checksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'column_plan_checksum')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(target_job.payload -> 'sort_plan_checksum')
      is distinct from 'string'
    or target_job.payload ->> 'export_version_id'
      is distinct from target_version.id::text
    or target_job.payload ->> 'source_key' is distinct from target_version.source_key
    or target_job.payload ->> 'filters_checksum'
      is distinct from app.vertical_slice_fingerprint(target_run.filters)
    or target_job.payload ->> 'column_plan_checksum'
      is distinct from app.vertical_slice_fingerprint(target_run.authorized_column_plan)
    or target_job.payload ->> 'sort_plan_checksum'
      is distinct from app.vertical_slice_fingerprint(target_run.authorized_sort_plan) then
    raise exception using errcode = '23514', message = 'export job snapshot is inconsistent';
  end if;

  select snapshot.* into target_snapshot
  from public.export_run_source_snapshots snapshot
  where snapshot.workspace_id = p_workspace_id
    and snapshot.export_run_id = p_export_run_id;

  if not found then
    if target_version.source_key in (
      'inventory', 'inventory_unit', 'inventory_summary',
      'inventory_aging', 'inventory_gross'
    ) then
      with candidates as (
        select
          unit.id as source_row_id,
          pg_catalog.jsonb_build_object(
            'id', unit.id,
            'workspace_id', unit.workspace_id,
            'stock_number', unit.stock_number::text,
            'status', unit.status,
            'acquisition_date', unit.acquisition_date,
            'acquired_at', unit.acquired_at,
            'workflow_state_key', unit.workflow_state_key,
            'currency_code', pg_catalog.btrim(unit.currency_code::text),
            'advertised_price_minor', case
              when unit.advertised_price_minor is null then null
              else unit.advertised_price_minor::text
            end,
            'vehicle', pg_catalog.jsonb_build_object(
              'vin', vehicle.vin::text,
              'model_year', vehicle.model_year,
              'make', vehicle.make,
              'model', vehicle.model
            ),
            'metrics', case when metrics.inventory_unit_id is null then null else
              pg_catalog.jsonb_build_object(
                'posted_cost_minor', metrics.posted_cost_minor::text,
                'estimated_gross_minor', case
                  when metrics.estimated_gross_minor is null then null
                  else metrics.estimated_gross_minor::text
                end
              )
            end
          ) as source_record
        from public.inventory_units unit
        join public.vehicles vehicle
          on vehicle.workspace_id = unit.workspace_id
         and vehicle.id = unit.vehicle_id
        left join public.inventory_cost_metrics metrics
          on metrics.workspace_id = unit.workspace_id
         and metrics.inventory_unit_id = unit.id
        where unit.workspace_id = p_workspace_id
          and (
            coalesce((target_run.filters ->> 'include_archived')::boolean, false)
            or unit.status <> 'archived'
          )
          and (
            nullif(target_run.filters ->> 'location_id', '') is null
            or unit.location_id = (target_run.filters ->> 'location_id')::uuid
          )
          and (
            not (target_run.filters ? 'states')
            or unit.workflow_state_key = any (
              array(
                select state.value
                from pg_catalog.jsonb_array_elements_text(
                  target_run.filters -> 'states'
                ) state(value)
              )
            )
          )
          and (
            nullif(target_run.filters ->> 'acquired_before', '') is null
            or unit.acquisition_date <= (target_run.filters ->> 'acquired_before')::date
          )
        order by unit.id
        limit target_version.maximum_rows + 1
      ), ranked as (
        select
          candidate.source_row_id,
          candidate.source_record,
          pg_catalog.row_number() over (order by candidate.source_row_id)::integer
            as row_ordinal
        from candidates candidate
      )
      insert into public.export_run_source_snapshot_rows (
        workspace_id, export_run_id, row_ordinal, source_row_id,
        source_record, record_fingerprint
      )
      select
        p_workspace_id, p_export_run_id, ranked.row_ordinal,
        ranked.source_row_id, ranked.source_record,
        app.vertical_slice_fingerprint(ranked.source_record)
      from ranked;
    elsif target_version.source_key in ('lead', 'leads') then
      with candidates as (
        select
          lead.id as source_row_id,
          pg_catalog.jsonb_build_object(
            'id', lead.id,
            'workspace_id', lead.workspace_id,
            'state_key', lead.state_key,
            'source_key', lead.source_key,
            'created_at', lead.created_at,
            'assignee_membership_id', lead.assignee_membership_id,
            'assignee_name', nullif(
              pg_catalog.btrim(profile.display_name), ''
            )
          ) as source_record
        from public.leads lead
        left join public.workspace_memberships membership
          on membership.workspace_id = lead.workspace_id
         and membership.id = lead.assignee_membership_id
        left join public.user_profiles profile
          on profile.user_id = membership.user_id
        where lead.workspace_id = p_workspace_id
          and (
            not (target_run.filters ? 'statuses')
            or lead.state_key = any (
              array(
                select state.value
                from pg_catalog.jsonb_array_elements_text(
                  target_run.filters -> 'statuses'
                ) state(value)
              )
            )
          )
          and (
            nullif(target_run.filters ->> 'assignee_id', '') is null
            or lead.assignee_membership_id
              = (target_run.filters ->> 'assignee_id')::uuid
          )
          and (
            nullif(target_run.filters ->> 'created_from', '') is null
            or lead.created_at >= (target_run.filters ->> 'created_from')::timestamptz
          )
          and (
            nullif(target_run.filters ->> 'created_to', '') is null
            or lead.created_at <= (target_run.filters ->> 'created_to')::timestamptz
          )
        order by lead.id
        limit target_version.maximum_rows + 1
      ), ranked as (
        select
          candidate.source_row_id,
          candidate.source_record,
          pg_catalog.row_number() over (order by candidate.source_row_id)::integer
            as row_ordinal
        from candidates candidate
      )
      insert into public.export_run_source_snapshot_rows (
        workspace_id, export_run_id, row_ordinal, source_row_id,
        source_record, record_fingerprint
      )
      select
        p_workspace_id, p_export_run_id, ranked.row_ordinal,
        ranked.source_row_id, ranked.source_record,
        app.vertical_slice_fingerprint(ranked.source_record)
      from ranked;
    elsif target_version.source_key in ('deal', 'deals') then
      with candidates as (
        select
          deal.id as source_row_id,
          pg_catalog.jsonb_build_object(
            'id', deal.id,
            'workspace_id', deal.workspace_id,
            'deal_type_key', deal.deal_type_key,
            'status', deal.status,
            'workflow_state_key', deal.workflow_state_key,
            'currency_code', pg_catalog.btrim(deal.currency_code::text),
            'updated_at', deal.updated_at,
            'line_items', coalesce((
              select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                  'unit_amount_minor', line.unit_amount_minor::text,
                  'quantity_text', line.quantity_text,
                  'currency_code', pg_catalog.btrim(line.currency_code::text),
                  'status', line.status
                ) order by line.sort_order, line.id
              )
              from public.deal_line_items line
              where line.workspace_id = deal.workspace_id
                and line.deal_id = deal.id
            ), '[]'::jsonb)
          ) as source_record
        from public.deals deal
        where deal.workspace_id = p_workspace_id
          and (
            not (target_run.filters ? 'workflow_states')
            or deal.workflow_state_key = any (
              array(
                select state.value
                from pg_catalog.jsonb_array_elements_text(
                  target_run.filters -> 'workflow_states'
                ) state(value)
              )
            )
          )
          and (
            not (target_run.filters ? 'deal_type_keys')
            or deal.deal_type_key = any (
              array(
                select deal_type.value
                from pg_catalog.jsonb_array_elements_text(
                  target_run.filters -> 'deal_type_keys'
                ) deal_type(value)
              )
            )
          )
          and (
            nullif(target_run.filters ->> 'updated_from', '') is null
            or deal.updated_at >= (target_run.filters ->> 'updated_from')::timestamptz
          )
          and (
            nullif(target_run.filters ->> 'updated_to', '') is null
            or deal.updated_at <= (target_run.filters ->> 'updated_to')::timestamptz
          )
        order by deal.id
        limit target_version.maximum_rows + 1
      ), ranked as (
        select
          candidate.source_row_id,
          candidate.source_record,
          pg_catalog.row_number() over (order by candidate.source_row_id)::integer
            as row_ordinal
        from candidates candidate
      )
      insert into public.export_run_source_snapshot_rows (
        workspace_id, export_run_id, row_ordinal, source_row_id,
        source_record, record_fingerprint
      )
      select
        p_workspace_id, p_export_run_id, ranked.row_ordinal,
        ranked.source_row_id, ranked.source_record,
        app.vertical_slice_fingerprint(ranked.source_record)
      from ranked;
    else
      raise exception using errcode = '23514', message = 'export source is not registered';
    end if;

    get diagnostics inserted_count = row_count;
    select pg_catalog.encode(extensions.digest(
      target_version.source_key || E'\x1f' || inserted_count::text || E'\x1f'
        || coalesce(pg_catalog.string_agg(
          row.record_fingerprint, '' order by row.row_ordinal
        ), ''),
      'sha256'
    ), 'hex')
    into calculated_fingerprint
    from public.export_run_source_snapshot_rows row
    where row.workspace_id = p_workspace_id
      and row.export_run_id = p_export_run_id;

    insert into public.export_run_source_snapshots (
      workspace_id, export_run_id, source_key, source_row_count,
      source_fingerprint
    ) values (
      p_workspace_id, p_export_run_id, target_version.source_key,
      inserted_count, calculated_fingerprint
    )
    returning * into target_snapshot;
  elsif target_snapshot.source_key is distinct from target_version.source_key then
    raise exception using errcode = '23514', message = 'export source snapshot is inconsistent';
  end if;

  if p_after_ordinal > target_snapshot.source_row_count then
    raise exception using errcode = '22023', message = 'export snapshot cursor is invalid';
  end if;

  select
    coalesce(pg_catalog.max(page.row_ordinal), p_after_ordinal),
    coalesce(
      pg_catalog.jsonb_agg(page.source_record order by page.row_ordinal),
      '[]'::jsonb
    )
  into page_last, page_records
  from (
    select row.row_ordinal, row.source_record
    from public.export_run_source_snapshot_rows row
    where row.workspace_id = p_workspace_id
      and row.export_run_id = p_export_run_id
      and row.row_ordinal > p_after_ordinal
    order by row.row_ordinal
    limit p_page_size
  ) page;

  -- Fence commit, rather than capture, with the job lock. A heartbeat remains
  -- free to extend the lease while source rows are assembled; reclaim or
  -- expiry observed here rolls the uncommitted snapshot back atomically.
  select job.* into target_job
  from public.jobs job
  where job.workspace_id = p_workspace_id
    and job.id = p_job_id
  for update;
  if not found
    or target_job.job_type is distinct from 'exports.generate'
    or target_job.entity_type is distinct from 'export_run'
    or target_job.entity_id is distinct from p_export_run_id
    or target_job.status is distinct from 'running'
    or target_job.lease_owner is distinct from p_worker_id
    or target_job.lease_token is distinct from p_lease_token
    or target_job.lease_expires_at is null
    or target_job.lease_expires_at <= pg_catalog.clock_timestamp() then
    raise exception using
      errcode = '55000',
      message = 'export worker lease is invalid or expired';
  end if;

  return query select
    target_snapshot.id,
    target_snapshot.captured_at,
    target_snapshot.source_row_count,
    target_snapshot.source_fingerprint,
    page_last,
    page_records;
end;
$$;

create function app.m4_validate_export_snapshot_receipt()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  snapshot public.export_run_source_snapshots%rowtype;
begin
  select source_snapshot.* into snapshot
  from public.export_run_source_snapshots source_snapshot
  where source_snapshot.workspace_id = new.workspace_id
    and source_snapshot.export_run_id = new.export_run_id;
  if not found
    or pg_catalog.jsonb_typeof(new.verification_receipt) is distinct from 'object'
    or pg_catalog.jsonb_typeof(new.verification_receipt -> 'sourceSnapshotId')
      is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      new.verification_receipt -> 'sourceSnapshotFingerprint'
    ) is distinct from 'string'
    or pg_catalog.jsonb_typeof(
      new.verification_receipt -> 'sourceSnapshotRowCount'
    ) is distinct from 'number'
    or pg_catalog.jsonb_typeof(
      new.verification_receipt -> 'sourceSnapshotCapturedAt'
    ) is distinct from 'string'
    or new.verification_receipt ->> 'sourceSnapshotId'
      is distinct from snapshot.id::text
    or new.verification_receipt ->> 'sourceSnapshotFingerprint'
      is distinct from snapshot.source_fingerprint
    or new.verification_receipt ->> 'sourceSnapshotRowCount'
      is distinct from snapshot.source_row_count::text
    or (new.verification_receipt ->> 'sourceSnapshotCapturedAt')::timestamptz
      is distinct from snapshot.captured_at then
    raise exception using
      errcode = '23514',
      message = 'export file receipt is not bound to its immutable source snapshot';
  end if;
  return new;
exception
  when invalid_datetime_format or datetime_field_overflow then
    raise exception using
      errcode = '23514',
      message = 'export file receipt is not bound to its immutable source snapshot';
end;
$$;

create trigger export_files_source_snapshot_receipt
before insert on public.export_files
for each row execute function app.m4_validate_export_snapshot_receipt();

revoke all on function app.m4_read_export_source_snapshot_page(
  uuid, uuid, uuid, text, uuid, integer, integer
) from public, anon, authenticated;
grant execute on function app.m4_read_export_source_snapshot_page(
  uuid, uuid, uuid, text, uuid, integer, integer
) to service_role;
revoke all on function app.m4_validate_export_snapshot_receipt()
from public, anon, authenticated, service_role;

comment on table public.export_run_source_snapshots is
  'Immutable first-execution manifests for retry-stable, workspace-scoped export rows.';
comment on table public.export_run_source_snapshot_rows is
  'Immutable source records ordered by a unique source-row tie-breaker; bigint money is stored as text.';
comment on function app.m4_read_export_source_snapshot_page(
  uuid, uuid, uuid, text, uuid, integer, integer
) is
  'Lease-fenced keyset paging over one immutable export source snapshot.';
