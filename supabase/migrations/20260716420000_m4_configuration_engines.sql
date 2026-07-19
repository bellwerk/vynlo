-- VYN-NUM-001, VYN-CALC-001, VYN-TAX-001, VYN-EXP-001, VYN-APP-001
-- M4-CFG-AC-001 through M4-CFG-AC-005
-- M4-NUM-AC-001 through M4-NUM-AC-005
-- M4-CALC-AC-001 through M4-CALC-AC-005
-- M4-TAX-AC-001 through M4-TAX-AC-005
-- M4-EXP-AC-001 through M4-EXP-AC-005
-- Forward-only tenant-neutral configuration engines and immutable run history.

insert into public.permissions (key, source)
values ('tax.override', 'platform')
on conflict (key) where workspace_id is null do nothing;

create function app.m4_prevent_row_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = pg_catalog.format('%I is append-only', tg_table_name);
end;
$$;

create function app.m4_guard_tax_assignment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (pg_catalog.to_jsonb(new)
      - array['retired_at', 'superseded_effective_to']::text[])
    is distinct from (pg_catalog.to_jsonb(old)
      - array['retired_at', 'superseded_effective_to']::text[]) then
    raise exception using
      errcode = '55000',
      message = 'tax assignment configuration is immutable';
  end if;
  if new.retired_at is not distinct from old.retired_at
    and new.superseded_effective_to
      is not distinct from old.superseded_effective_to then
    return new;
  end if;
  if old.retired_at is not null
    or old.superseded_effective_to is not null
    or new.retired_at is null
    or new.superseded_effective_to is null
    or new.superseded_effective_to < old.effective_from
    or (old.effective_to is not null
      and new.superseded_effective_to > old.effective_to) then
    raise exception using
      errcode = '23514',
      message = 'tax assignment may only be superseded once at a bounded effective date';
  end if;
  return new;
end;
$$;

create function app.m4_guard_export_run()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (pg_catalog.to_jsonb(new)
      - array['status', 'row_count', 'generated_checksum', 'failure_code', 'updated_at']::text[])
    is distinct from (pg_catalog.to_jsonb(old)
      - array['status', 'row_count', 'generated_checksum', 'failure_code', 'updated_at']::text[]) then
    raise exception using
      errcode = '55000',
      message = 'export run request evidence is immutable';
  end if;
  if old.status = new.status then
    if new.row_count is distinct from old.row_count
      or new.generated_checksum is distinct from old.generated_checksum
      or new.failure_code is distinct from old.failure_code then
      raise exception using
        errcode = '55000',
        message = 'export run outcome is immutable without a state transition';
    end if;
    return new;
  end if;
  if not (
    (old.status = 'queued' and new.status in ('running', 'retry_wait', 'dead_letter'))
    or (old.status = 'retry_wait' and new.status in ('running', 'dead_letter'))
    or (old.status = 'running' and new.status in ('retry_wait', 'generated', 'failed', 'dead_letter'))
    or (old.status = 'generated' and new.status = 'expired')
  ) then
    raise exception using
      errcode = '23514',
      message = 'invalid export run lifecycle transition';
  end if;
  if new.status = 'generated' then
    if new.row_count is null or new.generated_checksum is null
      or new.failure_code is not null then
      raise exception using errcode = '23514', message = 'generated export outcome is incomplete';
    end if;
  elsif new.status in ('failed', 'dead_letter') then
    if new.failure_code is null or new.row_count is not null
      or new.generated_checksum is not null then
      raise exception using errcode = '23514', message = 'failed export outcome is incomplete';
    end if;
  elsif new.status = 'expired' then
    if old.generated_checksum is null
      or new.generated_checksum is distinct from old.generated_checksum
      or new.row_count is distinct from old.row_count
      or new.failure_code is not null then
      raise exception using errcode = '23514', message = 'expired export must preserve its generated receipt';
    end if;
  elsif new.row_count is not null or new.generated_checksum is not null
    or new.failure_code is not null then
    raise exception using errcode = '23514', message = 'pending export cannot contain an outcome';
  end if;
  return new;
end;
$$;

create function app.m4_guard_artifact_version()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  content_column text;
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'draft'
      or new.validation_evidence is not null
      or new.fixture_evidence is not null
      or new.approval_record_id is not null
      or new.activated_by is not null
      or new.activated_at is not null
      or new.retired_by is not null
      or new.retired_at is not null then
      raise exception using
        errcode = '23514',
        message = 'configuration artifact versions must be inserted as draft';
    end if;
    return new;
  end if;

  foreach content_column in array tg_argv loop
    if (pg_catalog.to_jsonb(new) -> content_column)
      is distinct from (pg_catalog.to_jsonb(old) -> content_column) then
      raise exception using
        errcode = '23514',
        message = pg_catalog.format(
          '%I.%I is immutable after version creation',
          tg_table_name,
          content_column
        );
    end if;
  end loop;

  if (new.validation_evidence is distinct from old.validation_evidence
      and not (old.status = 'draft' and new.status = 'validated'))
    or (new.fixture_evidence is distinct from old.fixture_evidence
      and not (old.status = 'validated' and new.status = 'test_passed'))
    or (new.approval_record_id is distinct from old.approval_record_id
      and not (old.status = 'test_passed' and new.status = 'approved'))
    or (new.activated_by is distinct from old.activated_by
      and not (old.status = 'approved' and new.status = 'active'))
    or (new.activated_at is distinct from old.activated_at
      and not (old.status = 'approved' and new.status = 'active'))
    or (new.retired_by is distinct from old.retired_by
      and not (old.status in ('approved', 'active') and new.status = 'retired'))
    or (new.retired_at is distinct from old.retired_at
      and not (old.status in ('approved', 'active') and new.status = 'retired')) then
    raise exception using
      errcode = '55000',
      message = 'configuration artifact lifecycle evidence is immutable';
  end if;

  if old.status = new.status then
    return new;
  end if;

  if not (
    (old.status = 'draft' and new.status = 'validated')
    or (old.status = 'validated' and new.status = 'test_passed')
    or (old.status = 'test_passed' and new.status = 'approved')
    or (old.status = 'approved' and new.status in ('active', 'retired'))
    or (old.status = 'active' and new.status = 'retired')
  ) then
    raise exception using
      errcode = '23514',
      message = 'invalid configuration artifact lifecycle transition';
  end if;

  if new.status in ('approved', 'active')
    and new.approval_record_id is null then
    raise exception using
      errcode = '23514',
      message = 'exact-version approval is required';
  end if;
  if new.status in ('test_passed', 'approved', 'active')
    and new.fixture_evidence is null then
    raise exception using
      errcode = '23514',
      message = 'fixture evidence is required';
  end if;
  if new.status = 'active'
    and (new.activated_at is null or new.activated_by is null) then
    raise exception using
      errcode = '23514',
      message = 'activation timestamp is required';
  end if;
  if new.status = 'retired'
    and (new.retired_at is null or new.retired_by is null) then
    raise exception using
      errcode = '23514',
      message = 'retirement timestamp is required';
  end if;

  if old.status = 'draft' and new.status = 'validated' then
    if pg_catalog.jsonb_typeof(new.validation_evidence) is distinct from 'object'
      or new.validation_evidence -> 'passed' is distinct from 'true'::jsonb
      or pg_catalog.jsonb_typeof(new.validation_evidence -> 'validator')
        is distinct from 'string'
      or pg_catalog.btrim(coalesce(new.validation_evidence ->> 'validator', '')) = ''
      or pg_catalog.jsonb_typeof(new.validation_evidence -> 'artifactChecksum')
        is distinct from 'string'
      or new.validation_evidence ->> 'artifactChecksum'
        is distinct from new.checksum then
      raise exception using errcode = '23514', message = 'passing validation evidence is required';
    end if;
  elsif old.status = 'validated' and new.status = 'test_passed' then
    if pg_catalog.jsonb_typeof(new.fixture_evidence) is distinct from 'object'
      or new.fixture_evidence -> 'passed' is distinct from 'true'::jsonb
      or pg_catalog.jsonb_typeof(new.fixture_evidence -> 'runner')
        is distinct from 'string'
      or pg_catalog.btrim(coalesce(new.fixture_evidence ->> 'runner', '')) = ''
      or pg_catalog.jsonb_typeof(new.fixture_evidence -> 'artifactChecksum')
        is distinct from 'string'
      or new.fixture_evidence ->> 'artifactChecksum'
        is distinct from new.checksum
      or pg_catalog.jsonb_typeof(new.fixture_evidence -> 'tests')
        is distinct from 'array' then
      raise exception using errcode = '23514', message = 'passing fixture evidence is required';
    end if;
    if pg_catalog.jsonb_array_length(new.fixture_evidence -> 'tests') = 0 then
      raise exception using errcode = '23514', message = 'passing fixture evidence is required';
    end if;
  end if;

  return new;
end;
$$;

create function app.m4_currency_codes_valid(values_to_check text[])
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.cardinality(values_to_check) between 1 and 20
    and (
      select pg_catalog.bool_and(code ~ '^[A-Z]{3}$')
        and pg_catalog.count(distinct code) = pg_catalog.count(*)
      from pg_catalog.unnest(values_to_check) code
    );
$$;

-- Domain packages hash JSON after recursively sorting object keys and removing
-- insignificant whitespace. PostgreSQL jsonb::text adds spaces, so the older
-- vertical-slice fingerprint is intentionally not used for portable artifact
-- or execution evidence checksums.
create function app.m4_canonical_json(p_value jsonb)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  canonical_value text;
begin
  if pg_catalog.jsonb_typeof(p_value) = 'object' then
    select '{' || coalesce(pg_catalog.string_agg(
      pg_catalog.to_jsonb(member.key)::text || ':'
        || app.m4_canonical_json(member.value),
      ',' order by member.key
    ), '') || '}'
    into canonical_value
    from pg_catalog.jsonb_each(p_value) member;
    return canonical_value;
  end if;

  if pg_catalog.jsonb_typeof(p_value) = 'array' then
    select '[' || coalesce(pg_catalog.string_agg(
      app.m4_canonical_json(member.value),
      ',' order by member.ordinality
    ), '') || ']'
    into canonical_value
    from pg_catalog.jsonb_array_elements(p_value)
      with ordinality member(value, ordinality);
    return canonical_value;
  end if;

  return p_value::text;
end;
$$;

create function app.m4_canonical_fingerprint(p_value jsonb)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(app.m4_canonical_json(p_value), 'sha256'),
    'hex'
  );
$$;

create table public.numbering_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null check (
    key::text ~ '^[a-z][a-z0-9_]{0,127}$'
  ),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and labels ? 'en'
    and labels ? 'fr'
    and pg_catalog.btrim(labels ->> 'en') <> ''
    and pg_catalog.btrim(labels ->> 'fr') <> ''
  ),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key)
);

create table public.numbering_definition_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  numbering_definition_id uuid not null,
  version bigint not null check (version > 0),
  semantic_version text not null check (
    semantic_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
  ),
  status text not null default 'draft' check (
    status in ('draft', 'validated', 'test_passed', 'approved', 'active', 'retired')
  ),
  scope_type text not null check (
    scope_type in ('workspace', 'legal_entity', 'location', 'document_type', 'combined')
  ),
  prefix text not null default '' check (pg_catalog.char_length(prefix) <= 64),
  suffix text not null default '' check (pg_catalog.char_length(suffix) <= 64),
  numeric_width integer not null check (numeric_width between 1 and 18),
  starting_value bigint not null check (starting_value >= 0),
  increment_by bigint not null default 1 check (increment_by > 0),
  reset_policy text not null default 'never' check (
    reset_policy in ('never', 'yearly', 'monthly', 'configured_period')
  ),
  period_months integer check (
    (reset_policy = 'configured_period' and period_months between 1 and 120)
    or (reset_policy <> 'configured_period' and period_months is null)
  ),
  period_anchor date,
  timezone_name text not null default 'UTC' check (timezone_name = 'UTC'),
  format_pattern text not null default '{{prefix}}{{sequence}}{{suffix}}' check (
    pg_catalog.char_length(format_pattern) between 1 and 200
    and format_pattern like '%{{sequence}}%'
    and format_pattern !~ '[;`$]'
    and (scope_type = 'workspace' or format_pattern like '%{{scope}}%')
    and (
      (reset_policy = 'never' and format_pattern not like '%{{period}}%')
      or (reset_policy <> 'never' and format_pattern like '%{{period}}%')
    )
  ),
  import_policy text not null default 'authorized_reservation' check (
    import_policy in ('prohibited', 'authorized_reservation')
  ),
  reuse_policy text not null default 'never' check (reuse_policy = 'never'),
  allocation_event text not null check (
    allocation_event = 'official_document_created'
  ),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  validation_evidence jsonb,
  fixture_evidence jsonb,
  approval_record_id uuid,
  created_by uuid not null references auth.users (id) on delete restrict,
  activated_by uuid references auth.users (id) on delete restrict,
  retired_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  activated_at timestamptz,
  retired_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, numbering_definition_id, version),
  unique (workspace_id, numbering_definition_id, semantic_version),
  foreign key (workspace_id, numbering_definition_id)
    references public.numbering_definitions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id) on delete restrict,
  check (validation_evidence is null or pg_catalog.jsonb_typeof(validation_evidence) = 'object'),
  check (fixture_evidence is null or pg_catalog.jsonb_typeof(fixture_evidence) = 'object'),
  check (
    (reset_policy = 'configured_period' and period_anchor is not null)
    or (reset_policy <> 'configured_period' and period_anchor is null)
  )
);

create unique index numbering_definition_versions_active_uidx
  on public.numbering_definition_versions (workspace_id, numbering_definition_id)
  where status = 'active';

create table public.numbering_counters (
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  numbering_version_id uuid not null,
  scope_key text not null check (
    pg_catalog.btrim(scope_key) <> '' and pg_catalog.char_length(scope_key) <= 500
  ),
  period_key text not null check (
    pg_catalog.btrim(period_key) <> '' and pg_catalog.char_length(period_key) <= 100
  ),
  next_value bigint not null check (next_value >= 0),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  primary key (workspace_id, numbering_version_id, scope_key, period_key),
  foreign key (workspace_id, numbering_version_id)
    references public.numbering_definition_versions (workspace_id, id) on delete restrict
);

create table public.number_allocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  numbering_version_id uuid not null,
  scope_key text not null check (
    pg_catalog.btrim(scope_key) <> '' and pg_catalog.char_length(scope_key) <= 500
  ),
  period_key text not null check (
    pg_catalog.btrim(period_key) <> '' and pg_catalog.char_length(period_key) <= 100
  ),
  sequence_value bigint not null check (sequence_value >= 0),
  deterministic_suffix text not null default '' check (
    pg_catalog.char_length(deterministic_suffix) <= 64
  ),
  formatted_value extensions.citext not null check (
    pg_catalog.btrim(formatted_value::text) <> ''
    and pg_catalog.char_length(formatted_value::text) <= 128
  ),
  entity_type text not null check (
    entity_type ~ '^[a-z][a-z0-9_]{0,127}$'
  ),
  entity_id uuid not null,
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  allocation_reason text not null check (
    pg_catalog.btrim(allocation_reason) <> ''
    and pg_catalog.char_length(allocation_reason) <= 2000
  ),
  imported boolean not null default false,
  import_source text,
  imported_by uuid references auth.users (id) on delete restrict,
  allocated_by uuid not null references auth.users (id) on delete restrict,
  allocated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (
    workspace_id,
    numbering_version_id,
    scope_key,
    period_key,
    sequence_value,
    deterministic_suffix
  ),
  unique (workspace_id, formatted_value),
  unique (workspace_id, numbering_version_id, idempotency_key),
  unique (workspace_id, entity_type, entity_id),
  foreign key (workspace_id, numbering_version_id)
    references public.numbering_definition_versions (workspace_id, id) on delete restrict,
  check (
    (imported and import_source is not null and imported_by is not null)
    or (not imported and import_source is null and imported_by is null)
  )
);

create table public.calculation_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null check (key::text ~ '^[a-z][a-z0-9_]{0,127}$'),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and labels ? 'en' and labels ? 'fr'
  ),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key)
);

create table public.calculation_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  calculation_definition_id uuid not null,
  version bigint not null check (version > 0),
  semantic_version text not null check (
    semantic_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
  ),
  status text not null default 'draft' check (
    status in ('draft', 'validated', 'test_passed', 'approved', 'active', 'retired')
  ),
  input_schema jsonb not null check (pg_catalog.jsonb_typeof(input_schema) = 'object'),
  output_schema jsonb not null check (pg_catalog.jsonb_typeof(output_schema) = 'object'),
  expression_ast jsonb not null check (pg_catalog.jsonb_typeof(expression_ast) = 'object'),
  rounding_policy jsonb not null check (pg_catalog.jsonb_typeof(rounding_policy) = 'object'),
  resource_limits jsonb not null check (pg_catalog.jsonb_typeof(resource_limits) = 'object'),
  fixtures jsonb not null default '[]'::jsonb check (pg_catalog.jsonb_typeof(fixtures) = 'array'),
  engine_version text not null check (
    pg_catalog.btrim(engine_version) <> '' and pg_catalog.char_length(engine_version) <= 100
  ),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  validation_evidence jsonb,
  fixture_evidence jsonb,
  approval_record_id uuid,
  created_by uuid not null references auth.users (id) on delete restrict,
  activated_by uuid references auth.users (id) on delete restrict,
  retired_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  activated_at timestamptz,
  retired_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, calculation_definition_id, version),
  unique (workspace_id, calculation_definition_id, semantic_version),
  foreign key (workspace_id, calculation_definition_id)
    references public.calculation_definitions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id) on delete restrict
);

create unique index calculation_versions_active_uidx
  on public.calculation_versions (workspace_id, calculation_definition_id)
  where status = 'active';

create table public.calculation_snapshots (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  calculation_version_id uuid not null,
  document_id uuid,
  deal_id uuid,
  input_snapshot jsonb not null check (pg_catalog.jsonb_typeof(input_snapshot) = 'object'),
  output_snapshot jsonb not null check (pg_catalog.jsonb_typeof(output_snapshot) = 'object'),
  component_snapshot jsonb not null check (pg_catalog.jsonb_typeof(component_snapshot) = 'array'),
  rounding_snapshot jsonb not null check (pg_catalog.jsonb_typeof(rounding_snapshot) = 'object'),
  engine_version text not null check (pg_catalog.btrim(engine_version) <> ''),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  executed_by uuid not null references auth.users (id) on delete restrict,
  executed_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, calculation_version_id)
    references public.calculation_versions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  check (document_id is not null or deal_id is not null)
);

create table public.tax_packs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null check (key::text ~ '^[a-z][a-z0-9_-]{0,127}$'),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and labels ? 'en' and labels ? 'fr'
  ),
  source_kind text not null default 'portable_pack' check (
    source_kind in ('portable_pack', 'workspace_import')
  ),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key)
);

create table public.tax_pack_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  tax_pack_id uuid not null,
  version bigint not null check (version > 0),
  semantic_version text not null check (
    semantic_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
  ),
  status text not null default 'draft' check (
    status in ('draft', 'validated', 'test_passed', 'approved', 'active', 'retired')
  ),
  jurisdiction_code text not null check (
    jurisdiction_code ~ '^[A-Z]{2}(?:-[A-Z0-9]{1,3})?$'
  ),
  contexts text[] not null check (pg_catalog.cardinality(contexts) between 1 and 100),
  currency_codes text[] not null check (app.m4_currency_codes_valid(currency_codes)),
  effective_from date not null,
  effective_to date,
  rules jsonb not null check (pg_catalog.jsonb_typeof(rules) = 'object'),
  source_metadata jsonb not null check (pg_catalog.jsonb_typeof(source_metadata) = 'object'),
  input_schema jsonb not null check (pg_catalog.jsonb_typeof(input_schema) = 'object'),
  output_schema jsonb not null check (pg_catalog.jsonb_typeof(output_schema) = 'object'),
  override_policy jsonb not null check (pg_catalog.jsonb_typeof(override_policy) = 'object'),
  golden_fixtures jsonb not null check (pg_catalog.jsonb_typeof(golden_fixtures) = 'array'),
  engine_version text not null check (pg_catalog.btrim(engine_version) <> ''),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  validation_evidence jsonb,
  fixture_evidence jsonb,
  approval_record_id uuid,
  created_by uuid not null references auth.users (id) on delete restrict,
  activated_by uuid references auth.users (id) on delete restrict,
  retired_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  activated_at timestamptz,
  retired_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, tax_pack_id, version),
  unique (workspace_id, tax_pack_id, semantic_version),
  foreign key (workspace_id, tax_pack_id)
    references public.tax_packs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id) on delete restrict,
  check (effective_to is null or effective_to >= effective_from)
);

create table public.tax_pack_assignments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  tax_pack_version_id uuid not null,
  jurisdiction_code text not null,
  context_key text not null check (context_key ~ '^[a-z][a-z0-9_]{0,127}$'),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  effective_from date not null,
  effective_to date,
  superseded_effective_to date,
  approval_record_id uuid not null,
  activated_by uuid not null references auth.users (id) on delete restrict,
  activation_reason text not null check (
    pg_catalog.btrim(activation_reason) <> ''
    and pg_catalog.char_length(activation_reason) <= 2000
  ),
  activated_at timestamptz not null default pg_catalog.statement_timestamp(),
  retired_at timestamptz,
  unique (workspace_id, id),
  foreign key (workspace_id, tax_pack_version_id)
    references public.tax_pack_versions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id) on delete restrict,
  check (effective_to is null or effective_to >= effective_from),
  check (
    superseded_effective_to is null
    or superseded_effective_to >= effective_from
  )
);

create unique index tax_pack_assignments_active_uidx
  on public.tax_pack_assignments (
    workspace_id, jurisdiction_code, context_key, currency_code
  ) where retired_at is null;

create table public.tax_calculation_snapshots (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  tax_pack_version_id uuid not null,
  assignment_id uuid not null,
  document_id uuid,
  deal_id uuid,
  transaction_context text not null,
  jurisdiction_code text not null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  transaction_date date not null,
  input_snapshot jsonb not null check (pg_catalog.jsonb_typeof(input_snapshot) = 'object'),
  output_snapshot jsonb not null check (pg_catalog.jsonb_typeof(output_snapshot) = 'object'),
  override_snapshot jsonb,
  override_reason text,
  engine_version text not null check (pg_catalog.btrim(engine_version) <> ''),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  executed_by uuid not null references auth.users (id) on delete restrict,
  executed_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, tax_pack_version_id)
    references public.tax_pack_versions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, assignment_id)
    references public.tax_pack_assignments (workspace_id, id) on delete restrict,
  foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete restrict,
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  check (document_id is not null or deal_id is not null),
  check (
    (override_snapshot is null and override_reason is null)
    or (
      pg_catalog.jsonb_typeof(override_snapshot) = 'object'
      and pg_catalog.btrim(override_reason) <> ''
    )
  )
);

create table public.export_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  key extensions.citext not null check (key::text ~ '^[a-z][a-z0-9_]{0,95}$'),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and labels ? 'en' and labels ? 'fr'
  ),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, key)
);

create table public.export_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  export_definition_id uuid not null,
  version bigint not null check (version > 0),
  semantic_version text not null check (
    semantic_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
  ),
  status text not null default 'draft' check (
    status in ('draft', 'validated', 'test_passed', 'approved', 'active', 'retired')
  ),
  source_key text not null check (source_key ~ '^[a-z][a-z0-9_]{0,95}$'),
  formats text[] not null check (
    pg_catalog.cardinality(formats) between 1 and 2
    and formats <@ array['csv', 'xlsx']::text[]
  ),
  columns jsonb not null check (pg_catalog.jsonb_typeof(columns) = 'array'),
  filter_schema jsonb not null check (pg_catalog.jsonb_typeof(filter_schema) = 'object'),
  sort_specification jsonb not null check (pg_catalog.jsonb_typeof(sort_specification) = 'array'),
  sensitivity text not null default 'standard' check (
    sensitivity in ('standard', 'sensitive', 'restricted')
  ),
  permission_key text not null default 'exports.run' check (
    permission_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'
  ),
  step_up_required boolean not null default false,
  maximum_rows integer not null default 10000 check (maximum_rows between 1 and 100000),
  expires_after_seconds integer not null default 3600 check (
    expires_after_seconds between 60 and 86400
  ),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  validation_evidence jsonb,
  fixture_evidence jsonb,
  approval_record_id uuid,
  created_by uuid not null references auth.users (id) on delete restrict,
  activated_by uuid references auth.users (id) on delete restrict,
  retired_by uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  activated_at timestamptz,
  retired_at timestamptz,
  unique (workspace_id, id),
  unique (workspace_id, export_definition_id, version),
  unique (workspace_id, export_definition_id, semantic_version),
  foreign key (workspace_id, export_definition_id)
    references public.export_definitions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, approval_record_id)
    references public.approval_records (workspace_id, id) on delete restrict,
  check (not step_up_required or sensitivity <> 'standard')
);

create unique index export_versions_active_uidx
  on public.export_versions (workspace_id, export_definition_id)
  where status = 'active';

create table public.export_runs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  export_definition_id uuid not null,
  export_version_id uuid not null,
  requested_format text not null check (requested_format in ('csv', 'xlsx')),
  locale text not null check (locale ~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'),
  filters jsonb not null check (pg_catalog.jsonb_typeof(filters) = 'object'),
  authorized_column_plan jsonb not null check (
    pg_catalog.jsonb_typeof(authorized_column_plan) = 'array'
  ),
  authorized_sort_plan jsonb not null check (
    pg_catalog.jsonb_typeof(authorized_sort_plan) = 'array'
    and pg_catalog.jsonb_array_length(authorized_sort_plan) between 2 and 101
  ),
  status text not null default 'queued' check (
    status in ('queued', 'running', 'retry_wait', 'generated', 'failed', 'dead_letter', 'expired')
  ),
  row_count bigint check (row_count is null or row_count >= 0),
  generated_checksum text check (
    generated_checksum is null or generated_checksum ~ '^[a-f0-9]{64}$'
  ),
  failure_code text check (
    failure_code is null or (
      pg_catalog.btrim(failure_code) <> '' and pg_catalog.char_length(failure_code) <= 100
    )
  ),
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  requested_by uuid not null references auth.users (id) on delete restrict,
  correlation_id uuid not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, requested_by, idempotency_key),
  foreign key (workspace_id, export_definition_id)
    references public.export_definitions (workspace_id, id) on delete restrict,
  foreign key (workspace_id, export_version_id)
    references public.export_versions (workspace_id, id) on delete restrict,
  check (expires_at > created_at),
  constraint export_runs_state_shape_check check (
    (status in ('queued', 'running', 'retry_wait') and row_count is null and generated_checksum is null and failure_code is null)
    or (status = 'generated' and row_count is not null and generated_checksum is not null and failure_code is null)
    or (status in ('failed', 'dead_letter') and generated_checksum is null and failure_code is not null)
    or (status = 'expired' and generated_checksum is not null)
  )
);

create table public.export_files (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  export_run_id uuid not null,
  version integer not null check (version > 0),
  format text not null check (format in ('csv', 'xlsx')),
  storage_bucket text not null check (storage_bucket ~ '^[a-z0-9][a-z0-9_-]{2,62}$'),
  storage_object_path text not null check (
    pg_catalog.char_length(storage_object_path) between 1 and 1000
    and storage_object_path = pg_catalog.btrim(storage_object_path)
    and storage_object_path !~ '[\\]'
    and storage_object_path !~ '(^|/)\.\.(/|$)'
    and storage_object_path !~* '^https?://'
  ),
  filename text not null check (
    pg_catalog.btrim(filename) <> '' and pg_catalog.char_length(filename) <= 255
  ),
  mime_type text not null check (
    mime_type in (
      'text/csv; charset=utf-8',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    )
  ),
  byte_size bigint not null check (byte_size between 1 and 104857600),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  current boolean not null default true,
  expires_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, export_run_id, format, version),
  unique (workspace_id, storage_bucket, storage_object_path),
  foreign key (workspace_id, export_run_id)
    references public.export_runs (workspace_id, id) on delete restrict
);

create unique index export_files_current_uidx
  on public.export_files (workspace_id, export_run_id, format)
  where current;

create table public.export_download_authorizations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  export_run_id uuid not null,
  export_file_id uuid not null,
  requested_by uuid not null references auth.users (id) on delete restrict,
  grant_token_hash text not null check (grant_token_hash ~ '^[a-f0-9]{64}$'),
  file_checksum text not null check (file_checksum ~ '^[a-f0-9]{64}$'),
  reason text not null check (
    pg_catalog.btrim(reason) <> '' and pg_catalog.char_length(reason) <= 2000
  ),
  expires_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (grant_token_hash),
  foreign key (workspace_id, export_run_id)
    references public.export_runs (workspace_id, id) on delete restrict,
  foreign key (workspace_id, export_file_id)
    references public.export_files (workspace_id, id) on delete restrict,
  check (expires_at > created_at)
);

create trigger numbering_versions_lifecycle_guard
before insert or update on public.numbering_definition_versions
for each row execute function app.m4_guard_artifact_version(
  'workspace_id', 'numbering_definition_id', 'version', 'semantic_version',
  'scope_type', 'prefix', 'suffix', 'numeric_width', 'starting_value',
  'increment_by', 'reset_policy', 'period_months', 'period_anchor',
  'timezone_name', 'format_pattern', 'import_policy', 'reuse_policy',
  'allocation_event', 'checksum', 'created_by', 'created_at'
);

create trigger calculation_versions_lifecycle_guard
before insert or update on public.calculation_versions
for each row execute function app.m4_guard_artifact_version(
  'workspace_id', 'calculation_definition_id', 'version', 'semantic_version',
  'input_schema', 'output_schema', 'expression_ast', 'rounding_policy',
  'resource_limits', 'fixtures', 'engine_version', 'checksum', 'created_by',
  'created_at'
);

create trigger tax_pack_versions_lifecycle_guard
before insert or update on public.tax_pack_versions
for each row execute function app.m4_guard_artifact_version(
  'workspace_id', 'tax_pack_id', 'version', 'semantic_version',
  'jurisdiction_code', 'contexts', 'currency_codes', 'effective_from',
  'effective_to', 'rules', 'source_metadata', 'input_schema', 'output_schema',
  'override_policy', 'golden_fixtures', 'engine_version', 'checksum',
  'created_by', 'created_at'
);

create trigger export_versions_lifecycle_guard
before insert or update on public.export_versions
for each row execute function app.m4_guard_artifact_version(
  'workspace_id', 'export_definition_id', 'version', 'semantic_version',
  'source_key', 'formats', 'columns', 'filter_schema', 'sort_specification',
  'sensitivity', 'permission_key', 'step_up_required', 'maximum_rows',
  'expires_after_seconds', 'checksum', 'created_by', 'created_at'
);

create trigger numbering_versions_no_delete
before delete on public.numbering_definition_versions
for each row execute function app.m4_prevent_row_mutation();
create trigger calculation_versions_no_delete
before delete on public.calculation_versions
for each row execute function app.m4_prevent_row_mutation();
create trigger tax_pack_versions_no_delete
before delete on public.tax_pack_versions
for each row execute function app.m4_prevent_row_mutation();
create trigger export_versions_no_delete
before delete on public.export_versions
for each row execute function app.m4_prevent_row_mutation();

create trigger number_allocations_immutable
before update or delete on public.number_allocations
for each row execute function app.m4_prevent_row_mutation();
create trigger calculation_snapshots_immutable
before update or delete on public.calculation_snapshots
for each row execute function app.m4_prevent_row_mutation();
create trigger tax_assignments_no_delete
before delete on public.tax_pack_assignments
for each row execute function app.m4_prevent_row_mutation();
create trigger tax_assignments_lifecycle_guard
before update on public.tax_pack_assignments
for each row execute function app.m4_guard_tax_assignment();
revoke all on function app.m4_guard_tax_assignment()
from public, anon, authenticated, service_role;
create trigger tax_snapshots_immutable
before update or delete on public.tax_calculation_snapshots
for each row execute function app.m4_prevent_row_mutation();
create trigger export_files_immutable
before update or delete on public.export_files
for each row execute function app.m4_prevent_row_mutation();
create trigger export_download_authorizations_immutable
before update or delete on public.export_download_authorizations
for each row execute function app.m4_prevent_row_mutation();
create trigger export_runs_updated_at
before update on public.export_runs
for each row execute function app.set_updated_at();
create trigger export_runs_lifecycle_guard
before update on public.export_runs
for each row execute function app.m4_guard_export_run();

alter table public.numbering_definitions enable row level security;
alter table public.numbering_definitions force row level security;
alter table public.numbering_definition_versions enable row level security;
alter table public.numbering_definition_versions force row level security;
alter table public.numbering_counters enable row level security;
alter table public.numbering_counters force row level security;
alter table public.number_allocations enable row level security;
alter table public.number_allocations force row level security;
alter table public.calculation_definitions enable row level security;
alter table public.calculation_definitions force row level security;
alter table public.calculation_versions enable row level security;
alter table public.calculation_versions force row level security;
alter table public.calculation_snapshots enable row level security;
alter table public.calculation_snapshots force row level security;
alter table public.tax_packs enable row level security;
alter table public.tax_packs force row level security;
alter table public.tax_pack_versions enable row level security;
alter table public.tax_pack_versions force row level security;
alter table public.tax_pack_assignments enable row level security;
alter table public.tax_pack_assignments force row level security;
alter table public.tax_calculation_snapshots enable row level security;
alter table public.tax_calculation_snapshots force row level security;
alter table public.export_definitions enable row level security;
alter table public.export_definitions force row level security;
alter table public.export_versions enable row level security;
alter table public.export_versions force row level security;
alter table public.export_runs enable row level security;
alter table public.export_runs force row level security;
alter table public.export_files enable row level security;
alter table public.export_files force row level security;
alter table public.export_download_authorizations enable row level security;
alter table public.export_download_authorizations force row level security;

create policy numbering_definitions_select on public.numbering_definitions
for select to authenticated using (app.has_permission(workspace_id, 'numbering.read'));
create policy numbering_versions_select on public.numbering_definition_versions
for select to authenticated using (app.has_permission(workspace_id, 'numbering.read'));
create policy numbering_counters_select on public.numbering_counters
for select to authenticated using (app.has_permission(workspace_id, 'numbering.read'));
create policy number_allocations_select on public.number_allocations
for select to authenticated using (app.has_permission(workspace_id, 'numbering.read'));

create policy calculation_definitions_select on public.calculation_definitions
for select to authenticated using (app.has_permission(workspace_id, 'formula.read'));
create policy calculation_versions_select on public.calculation_versions
for select to authenticated using (app.has_permission(workspace_id, 'formula.read'));
create policy calculation_snapshots_select on public.calculation_snapshots
for select to authenticated using (
  app.has_permission(workspace_id, 'formula.read')
  or app.has_permission(workspace_id, 'documents.read')
);

create policy tax_packs_select on public.tax_packs
for select to authenticated using (app.has_permission(workspace_id, 'tax.read'));
create policy tax_pack_versions_select on public.tax_pack_versions
for select to authenticated using (app.has_permission(workspace_id, 'tax.read'));
create policy tax_pack_assignments_select on public.tax_pack_assignments
for select to authenticated using (app.has_permission(workspace_id, 'tax.read'));
create policy tax_snapshots_select on public.tax_calculation_snapshots
for select to authenticated using (
  app.has_permission(workspace_id, 'tax.read')
  or app.has_permission(workspace_id, 'documents.read')
);

create policy export_definitions_select on public.export_definitions
for select to authenticated using (app.has_permission(workspace_id, 'exports.read'));
create policy export_versions_select on public.export_versions
for select to authenticated using (app.has_permission(workspace_id, 'exports.read'));
create policy export_runs_select on public.export_runs
for select to authenticated using (
  app.has_permission(workspace_id, 'exports.read')
  and (requested_by = auth.uid() or app.has_permission(workspace_id, 'jobs.read'))
);
create policy export_files_select on public.export_files
for select to authenticated using (
  app.has_permission(workspace_id, 'exports.read')
  and exists (
    select 1 from public.export_runs run
    where run.workspace_id = export_files.workspace_id
      and run.id = export_files.export_run_id
      and (run.requested_by = auth.uid() or app.has_permission(run.workspace_id, 'jobs.read'))
  )
);
create policy export_download_authorizations_select
on public.export_download_authorizations
for select to authenticated using (
  requested_by = auth.uid()
  and app.has_permission(workspace_id, 'exports.read')
);

revoke all on table
  public.numbering_definitions,
  public.numbering_definition_versions,
  public.numbering_counters,
  public.number_allocations,
  public.calculation_definitions,
  public.calculation_versions,
  public.calculation_snapshots,
  public.tax_packs,
  public.tax_pack_versions,
  public.tax_pack_assignments,
  public.tax_calculation_snapshots,
  public.export_definitions,
  public.export_versions,
  public.export_runs,
  public.export_files,
  public.export_download_authorizations
from public, anon, authenticated;

grant select on table
  public.numbering_definitions,
  public.numbering_definition_versions,
  public.numbering_counters,
  public.number_allocations,
  public.calculation_definitions,
  public.calculation_versions,
  public.calculation_snapshots,
  public.tax_packs,
  public.tax_pack_versions,
  public.tax_pack_assignments,
  public.tax_calculation_snapshots,
  public.export_definitions,
  public.export_versions,
  public.export_runs,
  public.export_files,
  public.export_download_authorizations
to authenticated;

grant select, insert, update, delete on table
  public.numbering_definitions,
  public.numbering_definition_versions,
  public.numbering_counters,
  public.number_allocations,
  public.calculation_definitions,
  public.calculation_versions,
  public.calculation_snapshots,
  public.tax_packs,
  public.tax_pack_versions,
  public.tax_pack_assignments,
  public.tax_calculation_snapshots,
  public.export_definitions,
  public.export_versions,
  public.export_runs,
  public.export_files,
  public.export_download_authorizations
to service_role;

revoke all on function app.m4_prevent_row_mutation()
from public, anon, authenticated, service_role;
revoke all on function app.m4_guard_artifact_version()
from public, anon, authenticated, service_role;
revoke all on function app.m4_guard_export_run()
from public, anon, authenticated, service_role;
revoke all on function app.m4_currency_codes_valid(text[])
from public, anon, authenticated, service_role;
revoke all on function app.m4_canonical_json(jsonb)
from public, anon, authenticated, service_role;
revoke all on function app.m4_canonical_fingerprint(jsonb)
from public, anon, authenticated, service_role;

comment on table public.number_allocations is
  'Permanent non-reusable workspace-scoped allocations pinned to an immutable numbering version.';
comment on table public.calculation_snapshots is
  'Append-only exact input/output/component/rounding evidence for an immutable calculation version.';
comment on table public.tax_calculation_snapshots is
  'Append-only explicitly selected jurisdiction/context tax execution evidence.';
comment on table public.export_runs is
  'Actor-scoped export commands pinned to an authorized immutable column plan and version.';
