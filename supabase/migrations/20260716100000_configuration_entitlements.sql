-- VYN-AUD-001, VYN-WF-001, VYN-FIELD-001, VYN-E02
-- Milestone 1 workspace configuration, approvals, activations, and entitlement history.

create table public.approval_records (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  artifact_type text not null
    check (artifact_type ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  artifact_key text not null
    check (artifact_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'),
  artifact_version bigint not null check (artifact_version > 0),
  artifact_id uuid not null,
  artifact_checksum text not null check (artifact_checksum ~ '^[0-9a-f]{64}$'),
  approval_type text not null
    check (approval_type ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  decision text not null check (decision in ('approved', 'rejected', 'revoked')),
  decided_by uuid not null references auth.users (id) on delete restrict,
  professional_role text,
  professional_organization text,
  conditions jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(conditions) = 'object'),
  attachment_reference text,
  expires_at timestamptz,
  review_due_at timestamptz,
  supersedes_approval_id uuid,
  idempotency_key text not null check (pg_catalog.btrim(idempotency_key) <> ''),
  reason text not null check (pg_catalog.btrim(reason) <> ''),
  decided_at timestamptz not null default pg_catalog.clock_timestamp(),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, idempotency_key),
  foreign key (workspace_id, supersedes_approval_id)
    references public.approval_records (workspace_id, id) on delete restrict,
  check (expires_at is null or expires_at > decided_at),
  check (review_due_at is null or review_due_at > decided_at),
  check (
    (decision = 'revoked' and supersedes_approval_id is not null)
    or (decision in ('approved', 'rejected') and supersedes_approval_id is null)
  )
);

create index approval_records_artifact_idx on public.approval_records (
  workspace_id,
  artifact_type,
  artifact_key,
  artifact_version,
  decided_at desc
);

create table public.workspace_configuration_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  configuration_key text not null
    check (configuration_key ~ '^workspace\.[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  version bigint not null check (version > 0),
  status text not null default 'draft'
    check (
      status in (
        'draft',
        'validated',
        'reviewed',
        'approved',
        'active',
        'superseded',
        'retired'
      )
    ),
  configuration jsonb not null
    check (pg_catalog.jsonb_typeof(configuration) = 'object'),
  checksum text not null check (checksum ~ '^[0-9a-f]{64}$'),
  provenance jsonb not null
    check (
      pg_catalog.jsonb_typeof(provenance) = 'object'
      and provenance ? 'source'
      and pg_catalog.jsonb_typeof(provenance -> 'source') = 'string'
      and pg_catalog.btrim(provenance ->> 'source') <> ''
    ),
  configuration_schema_version integer not null check (configuration_schema_version > 0),
  minimum_platform_schema_version integer not null
    check (minimum_platform_schema_version > 0),
  maximum_platform_schema_version integer not null
    check (maximum_platform_schema_version >= minimum_platform_schema_version),
  effective_from timestamptz not null default pg_catalog.statement_timestamp(),
  effective_until timestamptz,
  based_on_version_id uuid,
  idempotency_key text not null check (pg_catalog.btrim(idempotency_key) <> ''),
  validation_evidence jsonb,
  review_evidence jsonb,
  approval_record_id uuid,
  created_by uuid references auth.users (id) on delete restrict,
  validated_by uuid references auth.users (id) on delete restrict,
  reviewed_by uuid references auth.users (id) on delete restrict,
  approved_by uuid references auth.users (id) on delete restrict,
  activated_by uuid references auth.users (id) on delete restrict,
  superseded_by uuid references auth.users (id) on delete restrict,
  retired_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  validated_at timestamptz,
  reviewed_at timestamptz,
  approved_at timestamptz,
  activated_at timestamptz,
  superseded_at timestamptz,
  retired_at timestamptz,
  activation_count bigint not null default 0 check (activation_count >= 0),
  unique (workspace_id, id),
  unique (workspace_id, configuration_key, version),
  unique (workspace_id, idempotency_key),
  foreign key (workspace_id, based_on_version_id)
    references public.workspace_configuration_versions (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id) on delete restrict,
  check (effective_until is null or effective_until > effective_from),
  check (
    validation_evidence is null
    or pg_catalog.jsonb_typeof(validation_evidence) = 'object'
  ),
  check (
    review_evidence is null
    or pg_catalog.jsonb_typeof(review_evidence) = 'object'
  ),
  check (
    (status = 'draft'
      and validated_at is null
      and reviewed_at is null
      and approved_at is null
      and approval_record_id is null
      and activated_at is null
      and retired_at is null)
    or (status = 'validated'
      and validated_at is not null
      and reviewed_at is null
      and approved_at is null
      and approval_record_id is null
      and activated_at is null
      and retired_at is null)
    or (status = 'reviewed'
      and validated_at is not null
      and reviewed_at is not null
      and approved_at is null
      and approval_record_id is null
      and activated_at is null
      and retired_at is null)
    or (status = 'approved'
      and validated_at is not null
      and reviewed_at is not null
      and approved_at is not null
      and approval_record_id is not null
      and retired_at is null)
    or (status = 'active'
      and validated_at is not null
      and reviewed_at is not null
      and approved_at is not null
      and approval_record_id is not null
      and activated_at is not null
      and activation_count > 0
      and retired_at is null)
    or (status = 'superseded'
      and validated_at is not null
      and reviewed_at is not null
      and approved_at is not null
      and approval_record_id is not null
      and activated_at is not null
      and superseded_at is not null
      and activation_count > 0
      and retired_at is null)
    or (status = 'retired' and retired_at is not null)
  )
);

create unique index workspace_configuration_versions_active_uidx
  on public.workspace_configuration_versions (workspace_id, configuration_key)
  where status = 'active';
create index workspace_configuration_versions_history_idx
  on public.workspace_configuration_versions (
    workspace_id,
    configuration_key,
    version desc
  );

create table public.workspace_configuration_activations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  configuration_version_id uuid not null,
  previous_configuration_version_id uuid,
  configuration_key text not null,
  configuration_version bigint not null check (configuration_version > 0),
  checksum text not null check (checksum ~ '^[0-9a-f]{64}$'),
  activation_kind text not null check (activation_kind in ('activate', 'rollback')),
  effective_at timestamptz not null,
  idempotency_key text not null check (pg_catalog.btrim(idempotency_key) <> ''),
  reason text not null check (pg_catalog.btrim(reason) <> ''),
  activated_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, idempotency_key),
  foreign key (workspace_id, configuration_version_id)
    references public.workspace_configuration_versions (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, previous_configuration_version_id)
    references public.workspace_configuration_versions (workspace_id, id)
    on delete restrict,
  check (previous_configuration_version_id is distinct from configuration_version_id)
);

create index workspace_configuration_activations_history_idx
  on public.workspace_configuration_activations (
    workspace_id,
    configuration_key,
    effective_at desc
  );

create table public.workspace_feature_entitlements (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  entitlement_key text not null
    check (entitlement_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$'),
  version bigint not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'superseded', 'retired')),
  enabled boolean not null,
  limits jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(limits) = 'object'),
  checksum text not null check (checksum ~ '^[0-9a-f]{64}$'),
  provenance jsonb not null
    check (
      pg_catalog.jsonb_typeof(provenance) = 'object'
      and provenance ? 'source'
      and pg_catalog.jsonb_typeof(provenance -> 'source') = 'string'
      and pg_catalog.btrim(provenance ->> 'source') <> ''
    ),
  effective_from timestamptz not null,
  effective_until timestamptz,
  idempotency_key text not null check (pg_catalog.btrim(idempotency_key) <> ''),
  created_by uuid references auth.users (id) on delete restrict,
  activated_by uuid references auth.users (id) on delete restrict,
  superseded_by uuid references auth.users (id) on delete restrict,
  retired_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  activated_at timestamptz,
  superseded_at timestamptz,
  retired_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, entitlement_key, version),
  unique (workspace_id, idempotency_key),
  check (effective_until is null or effective_until > effective_from),
  check (
    (status = 'draft'
      and activated_at is null
      and superseded_at is null
      and retired_at is null)
    or (status = 'active'
      and activated_at is not null
      and superseded_at is null
      and retired_at is null)
    or (status = 'superseded'
      and activated_at is not null
      and superseded_at is not null
      and retired_at is null)
    or (status = 'retired' and retired_at is not null)
  )
);

create unique index workspace_feature_entitlements_active_uidx
  on public.workspace_feature_entitlements (workspace_id, entitlement_key)
  where status = 'active';
create index workspace_feature_entitlements_history_idx
  on public.workspace_feature_entitlements (
    workspace_id,
    entitlement_key,
    version desc
  );

create function app.configuration_payload_checksum(payload jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(coalesce(payload, 'null'::jsonb)::text, 'sha256'),
    'hex'
  );
$$;

create function app.entitlement_payload_checksum(
  entitlement_enabled boolean,
  entitlement_limits jsonb
)
returns text
language sql
immutable
set search_path = ''
as $$
  select app.configuration_payload_checksum(
    pg_catalog.jsonb_build_object(
      'enabled', entitlement_enabled,
      'limits', entitlement_limits
    )
  );
$$;

create function app.configuration_invoker_role()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  invoker_role text;
begin
  invoker_role := pg_catalog.current_setting('role', true);
  if invoker_role is null or invoker_role in ('', 'none') then
    invoker_role := session_user;
  end if;
  return invoker_role;
end;
$$;

create function app.configuration_actor_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when app.configuration_invoker_role() = 'authenticated'
      and coalesce(auth.jwt() ->> 'role', '') = 'authenticated'
      then auth.uid()
    else null
  end;
$$;

create function app.assert_configuration_command_authority(
  target_workspace_id uuid,
  permission_key text,
  require_recent_step_up boolean default true
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  invoker_role text;
begin
  invoker_role := app.configuration_invoker_role();

  if invoker_role in ('postgres', 'supabase_admin', 'service_role') then
    return;
  end if;

  if invoker_role <> 'authenticated'
    or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated'
    or not app.has_permission(target_workspace_id, permission_key)
    or (require_recent_step_up and not app.has_recent_strong_auth()) then
    raise exception using
      errcode = '42501',
      message = 'configuration command authorization failed';
  end if;
end;
$$;

create function app.assert_configuration_service_authority()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if app.configuration_invoker_role()
    not in ('postgres', 'supabase_admin', 'service_role') then
    raise exception using
      errcode = '42501',
      message = 'feature entitlement changes require trusted service authority';
  end if;
end;
$$;

create function app.assert_configuration_payload_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  based_on_key text;
begin
  if tg_table_name = 'workspace_configuration_versions' then
    if new.checksum <> app.configuration_payload_checksum(new.configuration) then
      raise exception using
        errcode = '23514',
        message = 'configuration checksum does not match the canonical payload';
    end if;

    if new.based_on_version_id is not null then
      select cv.configuration_key
        into based_on_key
      from public.workspace_configuration_versions cv
      where cv.workspace_id = new.workspace_id
        and cv.id = new.based_on_version_id;

      if based_on_key is null or based_on_key is distinct from new.configuration_key then
        raise exception using
          errcode = '23514',
          message = 'based-on configuration version must have the same workspace and key';
      end if;
    end if;
  elsif tg_table_name = 'workspace_feature_entitlements' then
    if new.checksum <> app.entitlement_payload_checksum(new.enabled, new.limits) then
      raise exception using
        errcode = '23514',
        message = 'entitlement checksum does not match the canonical payload';
    end if;
  else
    raise exception using
      errcode = '55000',
      message = 'unsupported configuration integrity source';
  end if;

  return new;
end;
$$;

create function app.guard_configuration_version_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  approval_row public.approval_records%rowtype;
begin
  if old.validation_evidence is not null
    and new.validation_evidence is distinct from old.validation_evidence then
    raise exception using errcode = '23514', message = 'validation evidence is immutable';
  end if;

  if old.review_evidence is not null
    and new.review_evidence is distinct from old.review_evidence then
    raise exception using errcode = '23514', message = 'review evidence is immutable';
  end if;

  if new.activation_count < old.activation_count then
    raise exception using errcode = '23514', message = 'activation count cannot decrease';
  end if;

  if new.status = old.status then
    if row(
      new.validation_evidence,
      new.review_evidence,
      new.approval_record_id,
      new.validated_by,
      new.reviewed_by,
      new.approved_by,
      new.activated_by,
      new.superseded_by,
      new.retired_by,
      new.validated_at,
      new.reviewed_at,
      new.approved_at,
      new.activated_at,
      new.superseded_at,
      new.retired_at,
      new.activation_count
    ) is distinct from row(
      old.validation_evidence,
      old.review_evidence,
      old.approval_record_id,
      old.validated_by,
      old.reviewed_by,
      old.approved_by,
      old.activated_by,
      old.superseded_by,
      old.retired_by,
      old.validated_at,
      old.reviewed_at,
      old.approved_at,
      old.activated_at,
      old.superseded_at,
      old.retired_at,
      old.activation_count
    ) then
      raise exception using
        errcode = '23514',
        message = 'lifecycle metadata cannot change without a state transition';
    end if;
    return new;
  end if;

  if not (
    (old.status = 'draft' and new.status = 'validated')
    or (old.status = 'validated' and new.status = 'reviewed')
    or (old.status = 'reviewed' and new.status = 'approved')
    or (old.status in ('approved', 'superseded') and new.status = 'active')
    or (old.status = 'active' and new.status = 'superseded')
    or (old.status <> 'retired' and new.status = 'retired')
  ) then
    raise exception using
      errcode = '23514',
      message = 'invalid workspace configuration lifecycle transition';
  end if;

  if new.status = 'validated' and (
    new.validation_evidence is null
    or coalesce((new.validation_evidence ->> 'passed')::boolean, false) is not true
    or new.validated_at is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'validation requires passing immutable evidence';
  end if;

  if new.status = 'reviewed' and (
    new.review_evidence is null
    or new.review_evidence = '{}'::jsonb
    or new.reviewed_at is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'review requires immutable evidence';
  end if;

  if new.status in ('approved', 'active', 'superseded') then
    select ar.*
      into approval_row
    from public.approval_records ar
    where ar.workspace_id = new.workspace_id
      and ar.id = new.approval_record_id;

    if not found
      or approval_row.artifact_type <> 'workspace_configuration'
      or approval_row.artifact_key <> new.configuration_key
      or approval_row.artifact_version <> new.version
      or approval_row.artifact_id <> new.id
      or approval_row.artifact_checksum <> new.checksum
      or approval_row.decision <> 'approved' then
      raise exception using
        errcode = '23514',
        message = 'configuration lifecycle requires an exact approved record';
    end if;
  end if;

  if new.status = 'active' and new.activation_count <> old.activation_count + 1 then
    raise exception using
      errcode = '23514',
      message = 'activation count must advance exactly once';
  elsif new.status <> 'active' and new.activation_count <> old.activation_count then
    raise exception using
      errcode = '23514',
      message = 'activation count changes only during activation';
  end if;

  return new;
exception
  when invalid_text_representation then
    raise exception using
      errcode = '23514',
      message = 'validation evidence passed must be boolean';
end;
$$;

create function app.guard_entitlement_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = old.status then
    if row(
      new.activated_by,
      new.superseded_by,
      new.retired_by,
      new.activated_at,
      new.superseded_at,
      new.retired_at
    ) is distinct from row(
      old.activated_by,
      old.superseded_by,
      old.retired_by,
      old.activated_at,
      old.superseded_at,
      old.retired_at
    ) then
      raise exception using
        errcode = '23514',
        message = 'entitlement lifecycle metadata requires a state transition';
    end if;
    return new;
  end if;

  if not (
    (old.status = 'draft' and new.status = 'active')
    or (old.status = 'active' and new.status = 'superseded')
    or (old.status in ('draft', 'active', 'superseded') and new.status = 'retired')
  ) then
    raise exception using
      errcode = '23514',
      message = 'invalid feature entitlement lifecycle transition';
  end if;

  return new;
end;
$$;

create function app.assert_configuration_activation_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_row public.workspace_configuration_versions%rowtype;
  previous_key text;
begin
  select cv.*
    into target_row
  from public.workspace_configuration_versions cv
  where cv.workspace_id = new.workspace_id
    and cv.id = new.configuration_version_id;

  if not found
    or target_row.configuration_key <> new.configuration_key
    or target_row.version <> new.configuration_version
    or target_row.checksum <> new.checksum
    or target_row.status <> 'active' then
    raise exception using
      errcode = '23514',
      message = 'activation must reference the exact active configuration version';
  end if;

  if new.previous_configuration_version_id is not null then
    select cv.configuration_key
      into previous_key
    from public.workspace_configuration_versions cv
    where cv.workspace_id = new.workspace_id
      and cv.id = new.previous_configuration_version_id;

    if previous_key is null or previous_key <> new.configuration_key then
      raise exception using
        errcode = '23514',
        message = 'previous activation version must share workspace and configuration key';
    end if;
  end if;

  return new;
end;
$$;

create function app.prevent_configuration_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = pg_catalog.format('%I records are append-only', tg_table_name);
end;
$$;

create function app.record_configuration_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_before jsonb;
  row_after jsonb;
  audit_workspace_id uuid;
  audit_entity_id uuid;
  audit_actor_id uuid;
  audit_reason text;
begin
  row_before := case when tg_op = 'UPDATE' then pg_catalog.to_jsonb(old) else null end;
  row_after := pg_catalog.to_jsonb(new);
  audit_workspace_id := (row_after ->> 'workspace_id')::uuid;
  audit_entity_id := (row_after ->> 'id')::uuid;
  audit_actor_id := app.configuration_actor_id();

  if audit_actor_id is not null
    and not app.has_active_membership(audit_workspace_id) then
    audit_actor_id := null;
  end if;

  audit_reason := nullif(
    pg_catalog.current_setting('app.configuration_reason', true),
    ''
  );

  insert into public.audit_events (
    workspace_id,
    actor_user_id,
    actor_type,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data,
    reason,
    auth_assurance,
    metadata
  ) values (
    audit_workspace_id,
    audit_actor_id,
    case when audit_actor_id is null then 'service' else 'user' end,
    'configuration.' || tg_table_name || '.' || pg_catalog.lower(tg_op),
    tg_table_name,
    audit_entity_id,
    row_before,
    row_after,
    audit_reason,
    case
      when audit_actor_id is null then 'system'
      else coalesce(auth.jwt() ->> 'aal', 'unknown')
    end,
    '{"source":"database_trigger"}'::jsonb
  );

  return new;
end;
$$;

create trigger workspace_configuration_versions_a_integrity
before insert or update on public.workspace_configuration_versions
for each row execute function app.assert_configuration_payload_integrity();
create trigger workspace_configuration_versions_b_immutable
before update on public.workspace_configuration_versions
for each row execute function app.enforce_immutable_columns(
  'id',
  'workspace_id',
  'configuration_key',
  'version',
  'configuration',
  'checksum',
  'provenance',
  'configuration_schema_version',
  'minimum_platform_schema_version',
  'maximum_platform_schema_version',
  'effective_from',
  'effective_until',
  'based_on_version_id',
  'idempotency_key',
  'created_by',
  'created_at'
);
create trigger workspace_configuration_versions_c_lifecycle
before update on public.workspace_configuration_versions
for each row execute function app.guard_configuration_version_transition();
create trigger workspace_configuration_versions_updated_at
before update on public.workspace_configuration_versions
for each row execute function app.set_updated_at();
create trigger workspace_configuration_versions_prevent_delete
before delete on public.workspace_configuration_versions
for each row execute function app.prevent_hard_delete();

create trigger workspace_feature_entitlements_a_integrity
before insert or update on public.workspace_feature_entitlements
for each row execute function app.assert_configuration_payload_integrity();
create trigger workspace_feature_entitlements_b_immutable
before update on public.workspace_feature_entitlements
for each row execute function app.enforce_immutable_columns(
  'id',
  'workspace_id',
  'entitlement_key',
  'version',
  'enabled',
  'limits',
  'checksum',
  'provenance',
  'effective_from',
  'effective_until',
  'idempotency_key',
  'created_by',
  'created_at'
);
create trigger workspace_feature_entitlements_c_lifecycle
before update on public.workspace_feature_entitlements
for each row execute function app.guard_entitlement_transition();
create trigger workspace_feature_entitlements_updated_at
before update on public.workspace_feature_entitlements
for each row execute function app.set_updated_at();
create trigger workspace_feature_entitlements_prevent_delete
before delete on public.workspace_feature_entitlements
for each row execute function app.prevent_hard_delete();

create trigger approval_records_immutable
before update or delete on public.approval_records
for each row execute function app.prevent_configuration_history_mutation();
create trigger workspace_configuration_activations_scope
before insert on public.workspace_configuration_activations
for each row execute function app.assert_configuration_activation_scope();
create trigger workspace_configuration_activations_immutable
before update or delete on public.workspace_configuration_activations
for each row execute function app.prevent_configuration_history_mutation();

create trigger approval_records_audit
after insert on public.approval_records
for each row execute function app.record_configuration_audit();
create trigger workspace_configuration_versions_audit
after insert or update on public.workspace_configuration_versions
for each row execute function app.record_configuration_audit();
create trigger workspace_configuration_activations_audit
after insert on public.workspace_configuration_activations
for each row execute function app.record_configuration_audit();
create trigger workspace_feature_entitlements_audit
after insert or update on public.workspace_feature_entitlements
for each row execute function app.record_configuration_audit();

create function app.create_workspace_configuration_draft(
  target_workspace_id uuid,
  target_configuration_key text,
  target_configuration jsonb,
  expected_checksum text,
  target_provenance jsonb,
  command_idempotency_key text,
  command_reason text,
  based_on_configuration_version_id uuid,
  target_configuration_schema_version integer,
  target_minimum_platform_schema_version integer,
  target_maximum_platform_schema_version integer,
  target_effective_from timestamptz,
  target_effective_until timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_row public.workspace_configuration_versions%rowtype;
  latest_version_id uuid;
  latest_version_number bigint;
  next_version bigint;
  created_version_id uuid;
begin
  perform app.assert_configuration_command_authority(
    target_workspace_id,
    'configuration.manage',
    true
  );

  if pg_catalog.btrim(coalesce(command_reason, '')) = '' then
    raise exception using errcode = '23514', message = 'configuration command reason is required';
  end if;

  if pg_catalog.btrim(coalesce(command_idempotency_key, '')) = '' then
    raise exception using errcode = '23514', message = 'idempotency key is required';
  end if;

  if expected_checksum <> app.configuration_payload_checksum(target_configuration) then
    raise exception using
      errcode = '23514',
      message = 'configuration checksum does not match the canonical payload';
  end if;

  perform pg_catalog.set_config('app.configuration_reason', command_reason, true);

  select cv.*
    into existing_row
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.idempotency_key = command_idempotency_key;

  if found then
    if existing_row.configuration_key = target_configuration_key
      and existing_row.configuration = target_configuration
      and existing_row.checksum = expected_checksum
      and existing_row.provenance = target_provenance
      and existing_row.based_on_version_id is not distinct from based_on_configuration_version_id
      and existing_row.configuration_schema_version = target_configuration_schema_version
      and existing_row.minimum_platform_schema_version = target_minimum_platform_schema_version
      and existing_row.maximum_platform_schema_version = target_maximum_platform_schema_version
      and existing_row.effective_from = target_effective_from
      and existing_row.effective_until is not distinct from target_effective_until then
      return existing_row.id;
    end if;

    raise exception using
      errcode = '23514',
      message = 'idempotency key was already used with different configuration input';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workspace_configuration:' || target_workspace_id::text || ':' || target_configuration_key,
      0
    )
  );

  select cv.*
    into existing_row
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.idempotency_key = command_idempotency_key;

  if found then
    if existing_row.configuration_key = target_configuration_key
      and existing_row.configuration = target_configuration
      and existing_row.checksum = expected_checksum
      and existing_row.provenance = target_provenance
      and existing_row.based_on_version_id is not distinct from based_on_configuration_version_id
      and existing_row.configuration_schema_version = target_configuration_schema_version
      and existing_row.minimum_platform_schema_version = target_minimum_platform_schema_version
      and existing_row.maximum_platform_schema_version = target_maximum_platform_schema_version
      and existing_row.effective_from = target_effective_from
      and existing_row.effective_until is not distinct from target_effective_until then
      return existing_row.id;
    end if;

    raise exception using
      errcode = '23514',
      message = 'idempotency key was already used with different configuration input';
  end if;

  select cv.id, cv.version
    into latest_version_id, latest_version_number
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.configuration_key = target_configuration_key
  order by cv.version desc
  limit 1;

  next_version := coalesce(latest_version_number, 0) + 1;

  if latest_version_id is null and based_on_configuration_version_id is not null then
    raise exception using
      errcode = '23514',
      message = 'the first configuration version cannot reference a predecessor';
  elsif latest_version_id is not null
    and based_on_configuration_version_id is distinct from latest_version_id then
    raise exception using
      errcode = '40001',
      message = 'configuration history advanced; base a new draft on the latest version';
  end if;

  insert into public.workspace_configuration_versions (
    workspace_id,
    configuration_key,
    version,
    status,
    configuration,
    checksum,
    provenance,
    configuration_schema_version,
    minimum_platform_schema_version,
    maximum_platform_schema_version,
    effective_from,
    effective_until,
    based_on_version_id,
    idempotency_key,
    created_by
  ) values (
    target_workspace_id,
    target_configuration_key,
    next_version,
    'draft',
    target_configuration,
    expected_checksum,
    target_provenance,
    target_configuration_schema_version,
    target_minimum_platform_schema_version,
    target_maximum_platform_schema_version,
    target_effective_from,
    target_effective_until,
    based_on_configuration_version_id,
    command_idempotency_key,
    app.configuration_actor_id()
  )
  returning id into created_version_id;

  return created_version_id;
end;
$$;

create function app.record_workspace_configuration_approval(
  target_workspace_id uuid,
  target_configuration_version_id uuid,
  expected_checksum text,
  target_approval_type text,
  target_decision text,
  command_idempotency_key text,
  command_reason text,
  target_professional_role text default null,
  target_professional_organization text default null,
  target_conditions jsonb default '{}'::jsonb,
  target_attachment_reference text default null,
  target_expires_at timestamptz default null,
  target_review_due_at timestamptz default null,
  superseded_approval_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  configuration_row public.workspace_configuration_versions%rowtype;
  existing_row public.approval_records%rowtype;
  superseded_row public.approval_records%rowtype;
  actor_user_id uuid;
  approval_id uuid;
begin
  perform app.assert_configuration_command_authority(
    target_workspace_id,
    'approvals.create',
    true
  );

  actor_user_id := app.configuration_actor_id();
  if actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'configuration approvals require an authenticated human approver';
  end if;

  if pg_catalog.btrim(coalesce(command_reason, '')) = ''
    or pg_catalog.btrim(coalesce(command_idempotency_key, '')) = '' then
    raise exception using
      errcode = '23514',
      message = 'approval reason and idempotency key are required';
  end if;

  if target_decision not in ('approved', 'rejected', 'revoked') then
    raise exception using errcode = '23514', message = 'unsupported approval decision';
  end if;

  if pg_catalog.jsonb_typeof(coalesce(target_conditions, '{}'::jsonb)) <> 'object' then
    raise exception using errcode = '23514', message = 'approval conditions must be an object';
  end if;

  perform pg_catalog.set_config('app.configuration_reason', command_reason, true);

  select ar.*
    into existing_row
  from public.approval_records ar
  where ar.workspace_id = target_workspace_id
    and ar.idempotency_key = command_idempotency_key;

  if found then
    if existing_row.artifact_id = target_configuration_version_id
      and existing_row.artifact_checksum = expected_checksum
      and existing_row.approval_type = target_approval_type
      and existing_row.decision = target_decision
      and existing_row.decided_by = actor_user_id
      and existing_row.professional_role is not distinct from target_professional_role
      and existing_row.professional_organization is not distinct from target_professional_organization
      and existing_row.conditions = coalesce(target_conditions, '{}'::jsonb)
      and existing_row.attachment_reference is not distinct from target_attachment_reference
      and existing_row.expires_at is not distinct from target_expires_at
      and existing_row.review_due_at is not distinct from target_review_due_at
      and existing_row.supersedes_approval_id is not distinct from superseded_approval_id
      and existing_row.reason = command_reason then
      return existing_row.id;
    end if;

    raise exception using
      errcode = '23514',
      message = 'idempotency key was already used with different approval input';
  end if;

  select cv.*
    into configuration_row
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.id = target_configuration_version_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'configuration version does not exist';
  end if;

  select ar.*
    into existing_row
  from public.approval_records ar
  where ar.workspace_id = target_workspace_id
    and ar.idempotency_key = command_idempotency_key;

  if found then
    if existing_row.artifact_id = target_configuration_version_id
      and existing_row.artifact_checksum = expected_checksum
      and existing_row.approval_type = target_approval_type
      and existing_row.decision = target_decision
      and existing_row.decided_by = actor_user_id
      and existing_row.professional_role is not distinct from target_professional_role
      and existing_row.professional_organization is not distinct from target_professional_organization
      and existing_row.conditions = coalesce(target_conditions, '{}'::jsonb)
      and existing_row.attachment_reference is not distinct from target_attachment_reference
      and existing_row.expires_at is not distinct from target_expires_at
      and existing_row.review_due_at is not distinct from target_review_due_at
      and existing_row.supersedes_approval_id is not distinct from superseded_approval_id
      and existing_row.reason = command_reason then
      return existing_row.id;
    end if;

    raise exception using
      errcode = '23514',
      message = 'idempotency key was already used with different approval input';
  end if;

  if configuration_row.checksum <> expected_checksum then
    raise exception using errcode = '23514', message = 'configuration checksum mismatch';
  end if;

  if configuration_row.status not in ('reviewed', 'approved', 'active', 'superseded') then
    raise exception using
      errcode = '23514',
      message = 'configuration must be reviewed before an approval decision';
  end if;

  if target_decision = 'revoked' then
    if configuration_row.status = 'active' then
      raise exception using
        errcode = '23514',
        message = 'active configuration must be superseded or retired before approval revocation';
    end if;

    select ar.*
      into superseded_row
    from public.approval_records ar
    where ar.workspace_id = target_workspace_id
      and ar.id = superseded_approval_id
    for share;

    if not found
      or superseded_row.artifact_id <> configuration_row.id
      or superseded_row.artifact_checksum <> configuration_row.checksum
      or superseded_row.decision <> 'approved' then
      raise exception using
        errcode = '23514',
        message = 'approval revocation must reference an exact approved record';
    end if;
  elsif superseded_approval_id is not null then
    raise exception using
      errcode = '23514',
      message = 'only revocation decisions may supersede an approval';
  end if;

  insert into public.approval_records (
    workspace_id,
    artifact_type,
    artifact_key,
    artifact_version,
    artifact_id,
    artifact_checksum,
    approval_type,
    decision,
    decided_by,
    professional_role,
    professional_organization,
    conditions,
    attachment_reference,
    expires_at,
    review_due_at,
    supersedes_approval_id,
    idempotency_key,
    reason,
    decided_at
  ) values (
    target_workspace_id,
    'workspace_configuration',
    configuration_row.configuration_key,
    configuration_row.version,
    configuration_row.id,
    configuration_row.checksum,
    target_approval_type,
    target_decision,
    actor_user_id,
    target_professional_role,
    target_professional_organization,
    coalesce(target_conditions, '{}'::jsonb),
    target_attachment_reference,
    target_expires_at,
    target_review_due_at,
    superseded_approval_id,
    command_idempotency_key,
    command_reason,
    pg_catalog.clock_timestamp()
  )
  returning id into approval_id;

  return approval_id;
end;
$$;

create function app.transition_workspace_configuration_version(
  target_workspace_id uuid,
  target_configuration_version_id uuid,
  expected_status text,
  target_status text,
  expected_checksum text,
  lifecycle_evidence jsonb,
  command_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  configuration_row public.workspace_configuration_versions%rowtype;
  approval_row public.approval_records%rowtype;
  actor_user_id uuid;
begin
  perform app.assert_configuration_command_authority(
    target_workspace_id,
    'configuration.manage',
    true
  );

  if pg_catalog.btrim(coalesce(command_reason, '')) = '' then
    raise exception using errcode = '23514', message = 'configuration command reason is required';
  end if;

  perform pg_catalog.set_config('app.configuration_reason', command_reason, true);

  select cv.*
    into configuration_row
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.id = target_configuration_version_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'configuration version does not exist';
  end if;

  if configuration_row.checksum <> expected_checksum then
    raise exception using errcode = '23514', message = 'configuration checksum mismatch';
  end if;

  if configuration_row.status = target_status then
    return configuration_row.id;
  end if;

  if configuration_row.status <> expected_status then
    raise exception using
      errcode = '40001',
      message = 'configuration version state changed';
  end if;

  if target_status in ('active', 'superseded') then
    raise exception using
      errcode = '23514',
      message = 'activation and supersession require the activation command';
  end if;

  actor_user_id := app.configuration_actor_id();

  if target_status = 'validated' and configuration_row.status = 'draft' then
    if pg_catalog.jsonb_typeof(coalesce(lifecycle_evidence, 'null'::jsonb)) <> 'object'
      or coalesce((lifecycle_evidence ->> 'passed')::boolean, false) is not true then
      raise exception using
        errcode = '23514',
        message = 'validation requires passing evidence';
    end if;

    update public.workspace_configuration_versions
    set status = 'validated',
        validation_evidence = lifecycle_evidence,
        validated_by = actor_user_id,
        validated_at = pg_catalog.statement_timestamp()
    where workspace_id = target_workspace_id
      and id = target_configuration_version_id;
  elsif target_status = 'reviewed' and configuration_row.status = 'validated' then
    if pg_catalog.jsonb_typeof(coalesce(lifecycle_evidence, 'null'::jsonb)) <> 'object'
      or lifecycle_evidence = '{}'::jsonb then
      raise exception using errcode = '23514', message = 'review evidence is required';
    end if;

    update public.workspace_configuration_versions
    set status = 'reviewed',
        review_evidence = lifecycle_evidence,
        reviewed_by = actor_user_id,
        reviewed_at = pg_catalog.statement_timestamp()
    where workspace_id = target_workspace_id
      and id = target_configuration_version_id;
  elsif target_status = 'approved' and configuration_row.status = 'reviewed' then
    select ar.*
      into approval_row
    from public.approval_records ar
    where ar.workspace_id = target_workspace_id
      and ar.artifact_type = 'workspace_configuration'
      and ar.artifact_id = configuration_row.id
      and ar.artifact_checksum = configuration_row.checksum
    order by ar.decided_at desc, ar.id desc
    limit 1;

    if not found
      or approval_row.decision <> 'approved'
      or (approval_row.expires_at is not null
        and approval_row.expires_at <= pg_catalog.statement_timestamp()) then
      raise exception using
        errcode = '23514',
        message = 'an unexpired exact-version approval is required';
    end if;

    update public.workspace_configuration_versions
    set status = 'approved',
        approval_record_id = approval_row.id,
        approved_by = approval_row.decided_by,
        approved_at = approval_row.decided_at
    where workspace_id = target_workspace_id
      and id = target_configuration_version_id;
  elsif target_status = 'retired' and configuration_row.status <> 'retired' then
    if configuration_row.status = 'active' then
      perform app.assert_configuration_command_authority(
        target_workspace_id,
        'workspace.manage',
        true
      );
    end if;

    update public.workspace_configuration_versions
    set status = 'retired',
        retired_by = actor_user_id,
        retired_at = pg_catalog.statement_timestamp()
    where workspace_id = target_workspace_id
      and id = target_configuration_version_id;
  else
    raise exception using
      errcode = '23514',
      message = 'invalid workspace configuration lifecycle transition';
  end if;

  return target_configuration_version_id;
exception
  when invalid_text_representation then
    raise exception using
      errcode = '23514',
      message = 'validation evidence passed must be boolean';
end;
$$;

create function app.activate_workspace_configuration_version(
  target_workspace_id uuid,
  target_configuration_version_id uuid,
  expected_checksum text,
  current_platform_schema_version integer,
  command_idempotency_key text,
  command_reason text,
  target_effective_at timestamptz default pg_catalog.statement_timestamp()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  configuration_row public.workspace_configuration_versions%rowtype;
  existing_activation public.workspace_configuration_activations%rowtype;
  previous_version_id uuid;
  approval_row public.approval_records%rowtype;
  actor_user_id uuid;
  activation_kind text;
begin
  perform app.assert_configuration_command_authority(
    target_workspace_id,
    'configuration.manage',
    true
  );
  perform app.assert_configuration_command_authority(
    target_workspace_id,
    'workspace.manage',
    true
  );

  if pg_catalog.btrim(coalesce(command_reason, '')) = ''
    or pg_catalog.btrim(coalesce(command_idempotency_key, '')) = '' then
    raise exception using
      errcode = '23514',
      message = 'activation reason and idempotency key are required';
  end if;

  if target_effective_at > pg_catalog.statement_timestamp() then
    raise exception using
      errcode = '23514',
      message = 'future activation requires a durable scheduled command';
  end if;

  perform pg_catalog.set_config('app.configuration_reason', command_reason, true);

  select activation.*
    into existing_activation
  from public.workspace_configuration_activations activation
  where activation.workspace_id = target_workspace_id
    and activation.idempotency_key = command_idempotency_key;

  if found then
    if existing_activation.configuration_version_id = target_configuration_version_id
      and existing_activation.checksum = expected_checksum then
      return existing_activation.configuration_version_id;
    end if;

    raise exception using
      errcode = '23514',
      message = 'idempotency key was already used with different activation input';
  end if;

  select cv.*
    into configuration_row
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.id = target_configuration_version_id;

  if not found then
    raise exception using errcode = '23503', message = 'configuration version does not exist';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workspace_configuration:' || target_workspace_id::text || ':'
        || configuration_row.configuration_key,
      0
    )
  );

  select activation.*
    into existing_activation
  from public.workspace_configuration_activations activation
  where activation.workspace_id = target_workspace_id
    and activation.idempotency_key = command_idempotency_key;

  if found then
    if existing_activation.configuration_version_id = target_configuration_version_id
      and existing_activation.checksum = expected_checksum then
      return existing_activation.configuration_version_id;
    end if;

    raise exception using
      errcode = '23514',
      message = 'idempotency key was already used with different activation input';
  end if;

  perform 1
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.configuration_key = configuration_row.configuration_key
  order by cv.id
  for update;

  select cv.*
    into configuration_row
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.id = target_configuration_version_id;

  if configuration_row.checksum <> expected_checksum then
    raise exception using errcode = '23514', message = 'configuration checksum mismatch';
  end if;

  if configuration_row.status = 'active' then
    return configuration_row.id;
  end if;

  if configuration_row.status not in ('approved', 'superseded') then
    raise exception using
      errcode = '23514',
      message = 'only approved or superseded configuration can activate';
  end if;

  if current_platform_schema_version
    not between configuration_row.minimum_platform_schema_version
      and configuration_row.maximum_platform_schema_version then
    raise exception using
      errcode = '23514',
      message = 'configuration is incompatible with the current platform schema';
  end if;

  if target_effective_at < configuration_row.effective_from
    or (
      configuration_row.effective_until is not null
      and target_effective_at >= configuration_row.effective_until
    ) then
    raise exception using
      errcode = '23514',
      message = 'configuration is outside its effective interval';
  end if;

  select ar.*
    into approval_row
  from public.approval_records ar
  where ar.workspace_id = target_workspace_id
    and ar.artifact_type = 'workspace_configuration'
    and ar.artifact_id = configuration_row.id
    and ar.artifact_checksum = configuration_row.checksum
  order by ar.decided_at desc, ar.id desc
  limit 1;

  if not found
    or approval_row.decision <> 'approved'
    or (approval_row.expires_at is not null
      and approval_row.expires_at <= target_effective_at) then
    raise exception using
      errcode = '23514',
      message = 'activation requires a current exact-version approval';
  end if;

  select cv.id
    into previous_version_id
  from public.workspace_configuration_versions cv
  where cv.workspace_id = target_workspace_id
    and cv.configuration_key = configuration_row.configuration_key
    and cv.status = 'active'
    and cv.id <> target_configuration_version_id;

  actor_user_id := app.configuration_actor_id();
  activation_kind := case
    when configuration_row.activation_count > 0 then 'rollback'
    else 'activate'
  end;

  if previous_version_id is not null then
    update public.workspace_configuration_versions
    set status = 'superseded',
        superseded_by = actor_user_id,
        superseded_at = target_effective_at
    where workspace_id = target_workspace_id
      and id = previous_version_id;
  end if;

  update public.workspace_configuration_versions
  set status = 'active',
      approval_record_id = approval_row.id,
      approved_by = approval_row.decided_by,
      approved_at = approval_row.decided_at,
      activated_by = actor_user_id,
      activated_at = target_effective_at,
      activation_count = activation_count + 1
  where workspace_id = target_workspace_id
    and id = target_configuration_version_id;

  insert into public.workspace_configuration_activations (
    workspace_id,
    configuration_version_id,
    previous_configuration_version_id,
    configuration_key,
    configuration_version,
    checksum,
    activation_kind,
    effective_at,
    idempotency_key,
    reason,
    activated_by
  ) values (
    target_workspace_id,
    target_configuration_version_id,
    previous_version_id,
    configuration_row.configuration_key,
    configuration_row.version,
    configuration_row.checksum,
    activation_kind,
    target_effective_at,
    command_idempotency_key,
    command_reason,
    actor_user_id
  );

  return target_configuration_version_id;
end;
$$;

create function app.install_workspace_feature_entitlement_version(
  target_workspace_id uuid,
  target_entitlement_key text,
  target_enabled boolean,
  target_limits jsonb,
  expected_checksum text,
  target_provenance jsonb,
  target_effective_from timestamptz,
  command_idempotency_key text,
  command_reason text,
  target_effective_until timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_row public.workspace_feature_entitlements%rowtype;
  next_version bigint;
  created_entitlement_id uuid;
begin
  perform app.assert_configuration_service_authority();

  if pg_catalog.btrim(coalesce(command_reason, '')) = ''
    or pg_catalog.btrim(coalesce(command_idempotency_key, '')) = '' then
    raise exception using
      errcode = '23514',
      message = 'entitlement reason and idempotency key are required';
  end if;

  if expected_checksum <> app.entitlement_payload_checksum(target_enabled, target_limits) then
    raise exception using
      errcode = '23514',
      message = 'entitlement checksum does not match the canonical payload';
  end if;

  perform pg_catalog.set_config('app.configuration_reason', command_reason, true);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workspace_entitlement:' || target_workspace_id::text || ':' || target_entitlement_key,
      0
    )
  );

  select entitlement.*
    into existing_row
  from public.workspace_feature_entitlements entitlement
  where entitlement.workspace_id = target_workspace_id
    and entitlement.idempotency_key = command_idempotency_key;

  if found then
    if existing_row.entitlement_key = target_entitlement_key
      and existing_row.enabled = target_enabled
      and existing_row.limits = target_limits
      and existing_row.checksum = expected_checksum
      and existing_row.provenance = target_provenance
      and existing_row.effective_from = target_effective_from
      and existing_row.effective_until is not distinct from target_effective_until then
      return existing_row.id;
    end if;

    raise exception using
      errcode = '23514',
      message = 'idempotency key was already used with different entitlement input';
  end if;

  select coalesce(pg_catalog.max(entitlement.version), 0) + 1
    into next_version
  from public.workspace_feature_entitlements entitlement
  where entitlement.workspace_id = target_workspace_id
    and entitlement.entitlement_key = target_entitlement_key;

  insert into public.workspace_feature_entitlements (
    workspace_id,
    entitlement_key,
    version,
    status,
    enabled,
    limits,
    checksum,
    provenance,
    effective_from,
    effective_until,
    idempotency_key
  ) values (
    target_workspace_id,
    target_entitlement_key,
    next_version,
    'draft',
    target_enabled,
    target_limits,
    expected_checksum,
    target_provenance,
    target_effective_from,
    target_effective_until,
    command_idempotency_key
  )
  returning id into created_entitlement_id;

  return created_entitlement_id;
end;
$$;

create function app.activate_workspace_feature_entitlement_version(
  target_workspace_id uuid,
  target_entitlement_version_id uuid,
  expected_checksum text,
  command_reason text,
  target_effective_at timestamptz default pg_catalog.statement_timestamp()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  entitlement_row public.workspace_feature_entitlements%rowtype;
begin
  perform app.assert_configuration_service_authority();

  if pg_catalog.btrim(coalesce(command_reason, '')) = '' then
    raise exception using errcode = '23514', message = 'entitlement activation reason is required';
  end if;

  if target_effective_at > pg_catalog.statement_timestamp() then
    raise exception using
      errcode = '23514',
      message = 'future entitlement activation requires a durable scheduled command';
  end if;

  perform pg_catalog.set_config('app.configuration_reason', command_reason, true);

  select entitlement.*
    into entitlement_row
  from public.workspace_feature_entitlements entitlement
  where entitlement.workspace_id = target_workspace_id
    and entitlement.id = target_entitlement_version_id;

  if not found then
    raise exception using errcode = '23503', message = 'entitlement version does not exist';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workspace_entitlement:' || target_workspace_id::text || ':'
        || entitlement_row.entitlement_key,
      0
    )
  );

  perform 1
  from public.workspace_feature_entitlements entitlement
  where entitlement.workspace_id = target_workspace_id
    and entitlement.entitlement_key = entitlement_row.entitlement_key
  order by entitlement.id
  for update;

  select entitlement.*
    into entitlement_row
  from public.workspace_feature_entitlements entitlement
  where entitlement.workspace_id = target_workspace_id
    and entitlement.id = target_entitlement_version_id;

  if entitlement_row.checksum <> expected_checksum then
    raise exception using errcode = '23514', message = 'entitlement checksum mismatch';
  end if;

  if entitlement_row.status = 'active' then
    return entitlement_row.id;
  end if;

  if entitlement_row.status <> 'draft' then
    raise exception using
      errcode = '23514',
      message = 'only a draft entitlement version can activate';
  end if;

  if target_effective_at < entitlement_row.effective_from
    or (
      entitlement_row.effective_until is not null
      and target_effective_at >= entitlement_row.effective_until
    ) then
    raise exception using
      errcode = '23514',
      message = 'entitlement is outside its effective interval';
  end if;

  update public.workspace_feature_entitlements
  set status = 'superseded',
      superseded_at = target_effective_at
  where workspace_id = target_workspace_id
    and entitlement_key = entitlement_row.entitlement_key
    and status = 'active'
    and id <> target_entitlement_version_id;

  update public.workspace_feature_entitlements
  set status = 'active',
      activated_at = target_effective_at
  where workspace_id = target_workspace_id
    and id = target_entitlement_version_id;

  return target_entitlement_version_id;
end;
$$;

create function app.retire_workspace_feature_entitlement_version(
  target_workspace_id uuid,
  target_entitlement_version_id uuid,
  expected_checksum text,
  command_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  entitlement_row public.workspace_feature_entitlements%rowtype;
begin
  perform app.assert_configuration_service_authority();

  if pg_catalog.btrim(coalesce(command_reason, '')) = '' then
    raise exception using errcode = '23514', message = 'entitlement retirement reason is required';
  end if;

  perform pg_catalog.set_config('app.configuration_reason', command_reason, true);

  select entitlement.*
    into entitlement_row
  from public.workspace_feature_entitlements entitlement
  where entitlement.workspace_id = target_workspace_id
    and entitlement.id = target_entitlement_version_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'entitlement version does not exist';
  end if;

  if entitlement_row.checksum <> expected_checksum then
    raise exception using errcode = '23514', message = 'entitlement checksum mismatch';
  end if;

  if entitlement_row.status = 'retired' then
    return entitlement_row.id;
  end if;

  update public.workspace_feature_entitlements
  set status = 'retired',
      retired_at = pg_catalog.statement_timestamp()
  where workspace_id = target_workspace_id
    and id = target_entitlement_version_id;

  return target_entitlement_version_id;
end;
$$;

create function app.is_feature_entitled(
  target_workspace_id uuid,
  target_entitlement_key text,
  effective_at timestamptz default pg_catalog.statement_timestamp()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (
    app.configuration_invoker_role() in ('postgres', 'supabase_admin', 'service_role')
    or app.has_active_membership(target_workspace_id)
  ) and exists (
    select 1
    from public.workspace_feature_entitlements entitlement
    where entitlement.workspace_id = target_workspace_id
      and entitlement.entitlement_key = target_entitlement_key
      and entitlement.status = 'active'
      and entitlement.enabled
      and entitlement.effective_from <= effective_at
      and (
        entitlement.effective_until is null
        or effective_at < entitlement.effective_until
      )
  );
$$;

alter table public.approval_records enable row level security;
alter table public.approval_records force row level security;
alter table public.workspace_configuration_versions enable row level security;
alter table public.workspace_configuration_versions force row level security;
alter table public.workspace_configuration_activations enable row level security;
alter table public.workspace_configuration_activations force row level security;
alter table public.workspace_feature_entitlements enable row level security;
alter table public.workspace_feature_entitlements force row level security;

create policy approval_records_select on public.approval_records
for select to authenticated
using (app.has_permission(workspace_id, 'approvals.read'));

create policy workspace_configuration_versions_select
on public.workspace_configuration_versions
for select to authenticated
using (app.has_permission(workspace_id, 'configuration.read'));

create policy workspace_configuration_activations_select
on public.workspace_configuration_activations
for select to authenticated
using (app.has_permission(workspace_id, 'configuration.read'));

create policy workspace_feature_entitlements_select
on public.workspace_feature_entitlements
for select to authenticated
using (app.has_active_membership(workspace_id));

revoke all on table
  public.approval_records,
  public.workspace_configuration_versions,
  public.workspace_configuration_activations,
  public.workspace_feature_entitlements
from public, anon, authenticated, service_role;

grant select on
  public.approval_records,
  public.workspace_configuration_versions,
  public.workspace_configuration_activations,
  public.workspace_feature_entitlements
to authenticated, service_role;

revoke all on function app.configuration_payload_checksum(jsonb)
from public, anon, authenticated, service_role;
revoke all on function app.entitlement_payload_checksum(boolean, jsonb)
from public, anon, authenticated, service_role;
revoke all on function app.configuration_invoker_role()
from public, anon, authenticated, service_role;
revoke all on function app.configuration_actor_id()
from public, anon, authenticated, service_role;
revoke all on function app.assert_configuration_command_authority(uuid, text, boolean)
from public, anon, authenticated, service_role;
revoke all on function app.assert_configuration_service_authority()
from public, anon, authenticated, service_role;
revoke all on function app.assert_configuration_payload_integrity()
from public, anon, authenticated, service_role;
revoke all on function app.guard_configuration_version_transition()
from public, anon, authenticated, service_role;
revoke all on function app.guard_entitlement_transition()
from public, anon, authenticated, service_role;
revoke all on function app.assert_configuration_activation_scope()
from public, anon, authenticated, service_role;
revoke all on function app.prevent_configuration_history_mutation()
from public, anon, authenticated, service_role;
revoke all on function app.record_configuration_audit()
from public, anon, authenticated, service_role;
revoke all on function app.create_workspace_configuration_draft(
  uuid,
  text,
  jsonb,
  text,
  jsonb,
  text,
  text,
  uuid,
  integer,
  integer,
  integer,
  timestamptz,
  timestamptz
)
from public, anon, authenticated, service_role;
revoke all on function app.record_workspace_configuration_approval(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  text,
  timestamptz,
  timestamptz,
  uuid
)
from public, anon, authenticated, service_role;
revoke all on function app.transition_workspace_configuration_version(
  uuid,
  uuid,
  text,
  text,
  text,
  jsonb,
  text
)
from public, anon, authenticated, service_role;
revoke all on function app.activate_workspace_configuration_version(
  uuid,
  uuid,
  text,
  integer,
  text,
  text,
  timestamptz
)
from public, anon, authenticated, service_role;
revoke all on function app.install_workspace_feature_entitlement_version(
  uuid,
  text,
  boolean,
  jsonb,
  text,
  jsonb,
  timestamptz,
  text,
  text,
  timestamptz
)
from public, anon, authenticated, service_role;
revoke all on function app.activate_workspace_feature_entitlement_version(
  uuid,
  uuid,
  text,
  text,
  timestamptz
)
from public, anon, authenticated, service_role;
revoke all on function app.retire_workspace_feature_entitlement_version(
  uuid,
  uuid,
  text,
  text
)
from public, anon, authenticated, service_role;
revoke all on function app.is_feature_entitled(uuid, text, timestamptz)
from public, anon, authenticated, service_role;

grant execute on function app.configuration_payload_checksum(jsonb)
to authenticated, service_role;
grant execute on function app.entitlement_payload_checksum(boolean, jsonb)
to authenticated, service_role;
grant execute on function app.create_workspace_configuration_draft(
  uuid,
  text,
  jsonb,
  text,
  jsonb,
  text,
  text,
  uuid,
  integer,
  integer,
  integer,
  timestamptz,
  timestamptz
)
to authenticated, service_role;
grant execute on function app.record_workspace_configuration_approval(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  text,
  timestamptz,
  timestamptz,
  uuid
)
to authenticated;
grant execute on function app.transition_workspace_configuration_version(
  uuid,
  uuid,
  text,
  text,
  text,
  jsonb,
  text
)
to authenticated, service_role;
grant execute on function app.activate_workspace_configuration_version(
  uuid,
  uuid,
  text,
  integer,
  text,
  text,
  timestamptz
)
to authenticated, service_role;
grant execute on function app.install_workspace_feature_entitlement_version(
  uuid,
  text,
  boolean,
  jsonb,
  text,
  jsonb,
  timestamptz,
  text,
  text,
  timestamptz
)
to service_role;
grant execute on function app.activate_workspace_feature_entitlement_version(
  uuid,
  uuid,
  text,
  text,
  timestamptz
)
to service_role;
grant execute on function app.retire_workspace_feature_entitlement_version(
  uuid,
  uuid,
  text,
  text
)
to service_role;
grant execute on function app.is_feature_entitled(uuid, text, timestamptz)
to authenticated, service_role;

comment on table public.workspace_feature_entitlements is
  'Workspace-scoped immutable commercial capability history; trusted service writes only.';
comment on table public.workspace_configuration_versions is
  'Immutable workspace configuration payloads with explicit validation, review, approval, activation, and retirement state.';
comment on table public.workspace_configuration_activations is
  'Append-only activation and rollback history for exact configuration versions.';
comment on table public.approval_records is
  'Append-only exact-version approval decisions with human provenance and expiry.';
comment on function app.is_feature_entitled(uuid, text, timestamptz) is
  'Shared fail-closed entitlement decision for authenticated workspace members and trusted jobs.';
