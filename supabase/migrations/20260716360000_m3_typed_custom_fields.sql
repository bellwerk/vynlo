-- VYN-FIELD-001, VYN-WF-001, VYN-CFG-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, T-FIELD-001, T-FIELD-002, T-FIELD-003, T-CFG-004,
-- T-TEN-001, T-RBAC-001, T-AUD-001.
-- M3-FIELD-AC-001 through M3-FIELD-AC-009.
-- Tenant-neutral, typed custom-field definition versions and value commands.

create table public.custom_field_definitions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  entity_type text not null check (entity_type in (
    'inventory_unit', 'party', 'lead', 'deal', 'trade_in',
    'finance_application'
  )),
  key text not null check (
    key ~ '^[a-z][a-z0-9_]{0,127}$'
    and key not in (
      'workspace_id', 'organization_id', 'vin', 'stock', 'stock_number',
      'currency', 'currency_code', 'official_number', 'workflow_state',
      'workflow_state_key', 'provider_id', 'provider_ids'
    )
  ),
  status text not null default 'active'
    check (status in ('active', 'retired')),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, entity_type, key)
);

create table public.custom_field_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  custom_field_definition_id uuid not null,
  version bigint not null check (version > 0),
  value_type text not null check (value_type in (
    'short_text', 'long_text', 'integer', 'decimal', 'money', 'boolean',
    'date', 'datetime', 'single_select', 'multi_select',
    'party_reference', 'inventory_reference', 'location_reference',
    'user_reference'
  )),
  labels jsonb not null check (
    pg_catalog.jsonb_typeof(labels) = 'object'
    and labels ? 'en' and labels ? 'fr'
    and pg_catalog.btrim(labels ->> 'en') <> ''
    and pg_catalog.btrim(labels ->> 'fr') <> ''
  ),
  help_text jsonb not null check (
    pg_catalog.jsonb_typeof(help_text) = 'object'
    and help_text ? 'en' and help_text ? 'fr'
    and pg_catalog.btrim(help_text ->> 'en') <> ''
    and pg_catalog.btrim(help_text ->> 'fr') <> ''
  ),
  validation jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(validation) = 'object'),
  default_value jsonb,
  options jsonb not null default '[]'::jsonb
    check (pg_catalog.jsonb_typeof(options) = 'array'),
  required boolean not null default false,
  visibility_permission_key text check (
    visibility_permission_key is null
    or visibility_permission_key ~ '^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})+$'
  ),
  edit_permission_key text check (
    edit_permission_key is null
    or edit_permission_key ~ '^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})+$'
  ),
  sensitive boolean not null default false,
  searchable boolean not null default false,
  section_key text not null check (
    section_key ~ '^[a-z][a-z0-9_.-]{0,127}$'
  ),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
  created_by uuid not null references auth.users (id) on delete restrict,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, custom_field_definition_id, version),
  foreign key (workspace_id, custom_field_definition_id)
    references public.custom_field_definitions (workspace_id, id)
    on delete restrict,
  check (not sensitive or visibility_permission_key is not null),
  check (
    (status = 'draft' and activated_at is null and retired_at is null)
    or (status = 'active' and activated_at is not null and retired_at is null)
    or (status = 'retired' and activated_at is not null and retired_at is not null)
  )
);

create unique index custom_field_versions_active_definition_uidx
  on public.custom_field_versions (workspace_id, custom_field_definition_id)
  where status = 'active';

create table public.custom_field_values (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  custom_field_definition_id uuid not null,
  custom_field_version_id uuid not null,
  entity_type text not null check (entity_type in (
    'inventory_unit', 'party', 'lead', 'deal', 'trade_in',
    'finance_application'
  )),
  entity_id uuid not null,
  value_type text not null check (value_type in (
    'short_text', 'long_text', 'integer', 'decimal', 'money', 'boolean',
    'date', 'datetime', 'single_select', 'multi_select',
    'party_reference', 'inventory_reference', 'location_reference',
    'user_reference'
  )),
  is_set boolean not null default true,
  text_value text,
  integer_value numeric(38, 0),
  decimal_value numeric(38, 18),
  money_minor bigint,
  money_currency char(3) check (
    money_currency is null or money_currency ~ '^[A-Z]{3}$'
  ),
  boolean_value boolean,
  date_value date,
  datetime_value timestamptz,
  selected_keys text[],
  reference_id uuid,
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, entity_type, entity_id, custom_field_definition_id),
  foreign key (workspace_id, custom_field_definition_id)
    references public.custom_field_definitions (workspace_id, id)
    on delete restrict,
  foreign key (workspace_id, custom_field_version_id)
    references public.custom_field_versions (workspace_id, id)
    on delete restrict,
  check (
    (
      not is_set
      and pg_catalog.num_nonnulls(
        text_value, integer_value, decimal_value, money_minor,
        money_currency, boolean_value, date_value, datetime_value,
        selected_keys, reference_id
      ) = 0
    )
    or (
      is_set and case value_type
        when 'short_text' then text_value is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'long_text' then text_value is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'integer' then integer_value is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'decimal' then decimal_value is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'money' then money_minor is not null and money_currency is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 2
        when 'boolean' then boolean_value is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'date' then date_value is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'datetime' then datetime_value is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'single_select' then selected_keys is not null
          and pg_catalog.cardinality(selected_keys) = 1
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'multi_select' then selected_keys is not null
          and pg_catalog.cardinality(selected_keys) between 0 and 100
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'party_reference' then reference_id is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'inventory_reference' then reference_id is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'location_reference' then reference_id is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        when 'user_reference' then reference_id is not null
          and pg_catalog.num_nonnulls(
            text_value, integer_value, decimal_value, money_minor,
            money_currency, boolean_value, date_value, datetime_value,
            selected_keys, reference_id
          ) = 1
        else false
      end
    )
  )
);

create index custom_field_values_entity_idx
  on public.custom_field_values (
    workspace_id, entity_type, entity_id, custom_field_definition_id
  );

create index custom_field_values_search_text_idx
  on public.custom_field_values (workspace_id, custom_field_definition_id, text_value)
  where is_set and text_value is not null;

create table public.custom_field_command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  actor_user_id uuid not null references auth.users (id) on delete restrict,
  command_type text not null check (command_type in (
    'create_custom_field_version', 'activate_custom_field_version',
    'set_custom_field_value'
  )),
  idempotency_key text not null check (
    idempotency_key = pg_catalog.btrim(idempotency_key)
    and pg_catalog.char_length(idempotency_key) between 8 and 200
  ),
  command_fingerprint text not null check (command_fingerprint ~ '^[a-f0-9]{64}$'),
  custom_field_definition_id uuid not null,
  entity_type text,
  entity_id uuid,
  result jsonb not null check (pg_catalog.jsonb_typeof(result) = 'object'),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (workspace_id, actor_user_id, command_type, idempotency_key),
  foreign key (workspace_id, custom_field_definition_id)
    references public.custom_field_definitions (workspace_id, id)
    on delete restrict
);

create function app.custom_field_fingerprint(payload jsonb)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(payload::text, 'UTF8'), 'sha256'),
    'hex'
  )
$$;

create function app.custom_field_json_has_executable_key(candidate jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  entry_key text;
  entry_value jsonb;
begin
  if pg_catalog.jsonb_typeof(candidate) = 'object' then
    for entry_key, entry_value in
      select item.key, item.value
      from pg_catalog.jsonb_each(candidate) item
    loop
      if pg_catalog.lower(pg_catalog.regexp_replace(entry_key, '[^a-z0-9]', '', 'g')) in (
        'command', 'endpoint', 'eval', 'fetch', 'filesystem', 'function',
        'http', 'https', 'import', 'javascript', 'js', 'module', 'network',
        'query', 'request', 'script', 'shell', 'sql', 'uri', 'url'
      ) or app.custom_field_json_has_executable_key(entry_value) then
        return true;
      end if;
    end loop;
  elsif pg_catalog.jsonb_typeof(candidate) = 'array' then
    for entry_value in
      select item.value from pg_catalog.jsonb_array_elements(candidate) item
    loop
      if app.custom_field_json_has_executable_key(entry_value) then
        return true;
      end if;
    end loop;
  end if;
  return false;
end;
$$;

create function app.normalize_custom_field_value(
  p_value_type text,
  p_validation jsonb,
  p_options jsonb,
  p_required boolean,
  p_value jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  text_value text;
  normalized_numeric numeric;
  lower_bound numeric;
  upper_bound numeric;
  scale_limit integer;
  selected_key text;
  selected_count integer;
  distinct_count integer;
  parsed_date date;
  parsed_timestamp timestamptz;
begin
  if p_value is null or p_value = 'null'::jsonb then
    if p_required then
      raise exception using errcode = '23514', message = 'required custom field value is missing';
    end if;
    return null;
  end if;

  if app.custom_field_json_has_executable_key(p_value) then
    raise exception using errcode = '23514', message = 'executable custom field value is prohibited';
  end if;

  if p_value_type in ('short_text', 'long_text') then
    if pg_catalog.jsonb_typeof(p_value) <> 'string' then
      raise exception using errcode = '23514', message = 'custom field text value is invalid';
    end if;
    text_value := pg_catalog.btrim(p_value #>> '{}');
    if text_value = '' then
      if p_required then
        raise exception using errcode = '23514', message = 'required custom field value is missing';
      end if;
      return null;
    end if;
    if pg_catalog.char_length(text_value) < coalesce((p_validation ->> 'minLength')::integer, 0)
      or pg_catalog.char_length(text_value) > least(
        coalesce(
          (p_validation ->> 'maxLength')::integer,
          case when p_value_type = 'short_text' then 500 else 50000 end
        ),
        case when p_value_type = 'short_text' then 500 else 50000 end
      ) then
      raise exception using errcode = '22003', message = 'custom field text value is out of range';
    end if;
    return pg_catalog.to_jsonb(text_value);
  end if;

  if p_value_type in ('integer', 'decimal') then
    if pg_catalog.jsonb_typeof(p_value) <> 'string' then
      raise exception using errcode = '23514', message = 'exact numeric custom field value must be text';
    end if;
    text_value := p_value #>> '{}';
    if pg_catalog.char_length(text_value) > 60
      or (p_value_type = 'integer' and text_value !~ '^-?(0|[1-9][0-9]*)$')
      or (p_value_type = 'decimal' and text_value !~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$') then
      raise exception using errcode = '23514', message = 'exact numeric custom field value is invalid';
    end if;
    if pg_catalog.char_length(
        pg_catalog.regexp_replace(text_value, '[^0-9]', '', 'g')
      ) > 38
      or (
        p_value_type = 'decimal'
        and pg_catalog.char_length(
          pg_catalog.split_part(text_value, '.', 2)
        ) > 18
      ) then
      raise exception using errcode = '22003', message = 'numeric custom field value is out of range';
    end if;
    normalized_numeric := text_value::numeric;
    if p_value_type = 'integer' and pg_catalog.scale(normalized_numeric) <> 0 then
      raise exception using errcode = '23514', message = 'integer custom field value is invalid';
    end if;
    scale_limit := coalesce((p_validation ->> 'scale')::integer, 18);
    if p_value_type = 'decimal' and pg_catalog.scale(normalized_numeric) > scale_limit then
      raise exception using errcode = '22003', message = 'decimal custom field scale is out of range';
    end if;
    lower_bound := (p_validation ->> 'minimum')::numeric;
    upper_bound := (p_validation ->> 'maximum')::numeric;
    if (lower_bound is not null and normalized_numeric < lower_bound)
      or (upper_bound is not null and normalized_numeric > upper_bound) then
      raise exception using errcode = '22003', message = 'numeric custom field value is out of range';
    end if;
    if p_value_type = 'integer' and pg_catalog.length(normalized_numeric::text) > 39 then
      raise exception using errcode = '22003', message = 'integer custom field value is out of range';
    end if;
    return pg_catalog.to_jsonb(normalized_numeric::text);
  end if;

  if p_value_type = 'money' then
    if pg_catalog.jsonb_typeof(p_value) <> 'object'
      or not (p_value ? 'amountMinor' and p_value ? 'currencyCode')
      or exists (
        select 1 from pg_catalog.jsonb_object_keys(p_value) item(key)
        where item.key not in ('amountMinor', 'currencyCode')
      )
      or pg_catalog.jsonb_typeof(p_value -> 'amountMinor') <> 'string'
      or pg_catalog.jsonb_typeof(p_value -> 'currencyCode') <> 'string'
      or p_value ->> 'amountMinor' !~ '^-?(0|[1-9][0-9]*)$'
      or p_value ->> 'currencyCode' !~ '^[A-Z]{3}$' then
      raise exception using errcode = '23514', message = 'money custom field value is invalid';
    end if;
    perform (p_value ->> 'amountMinor')::bigint;
    if p_validation ? 'allowedCurrencies'
      and not (p_validation -> 'allowedCurrencies' ? (p_value ->> 'currencyCode')) then
      raise exception using errcode = '23514', message = 'money custom field currency is not allowed';
    end if;
    return pg_catalog.jsonb_build_object(
      'amountMinor', ((p_value ->> 'amountMinor')::bigint)::text,
      'currencyCode', p_value ->> 'currencyCode'
    );
  end if;

  if p_value_type = 'boolean' then
    if pg_catalog.jsonb_typeof(p_value) <> 'boolean' then
      raise exception using errcode = '23514', message = 'boolean custom field value is invalid';
    end if;
    return p_value;
  end if;

  if p_value_type = 'date' then
    if pg_catalog.jsonb_typeof(p_value) <> 'string'
      or p_value #>> '{}' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception using errcode = '22007', message = 'date custom field value is invalid';
    end if;
    parsed_date := (p_value #>> '{}')::date;
    if pg_catalog.to_char(parsed_date, 'YYYY-MM-DD') <> p_value #>> '{}' then
      raise exception using errcode = '22007', message = 'date custom field value is invalid';
    end if;
    return pg_catalog.to_jsonb(p_value #>> '{}');
  end if;

  if p_value_type = 'datetime' then
    if pg_catalog.jsonb_typeof(p_value) <> 'string'
      or p_value #>> '{}' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$' then
      raise exception using errcode = '22007', message = 'datetime custom field value is invalid';
    end if;
    parsed_timestamp := (p_value #>> '{}')::timestamptz;
    return pg_catalog.to_jsonb(parsed_timestamp::text);
  end if;

  if p_value_type = 'single_select' then
    if pg_catalog.jsonb_typeof(p_value) <> 'string' then
      raise exception using errcode = '23514', message = 'single-select custom field value is invalid';
    end if;
    selected_key := p_value #>> '{}';
    if not exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_options) option(value)
      where option.value ->> 'key' = selected_key
        and coalesce((option.value ->> 'active')::boolean, true)
    ) then
      raise exception using errcode = '23514', message = 'custom field option is unavailable';
    end if;
    return pg_catalog.to_jsonb(selected_key);
  end if;

  if p_value_type = 'multi_select' then
    if pg_catalog.jsonb_typeof(p_value) <> 'array'
      or exists (
        select 1 from pg_catalog.jsonb_array_elements(p_value) item(value)
        where pg_catalog.jsonb_typeof(item.value) <> 'string'
      ) then
      raise exception using errcode = '23514', message = 'multi-select custom field value is invalid';
    end if;
    select pg_catalog.count(*), pg_catalog.count(distinct item.value #>> '{}')
      into selected_count, distinct_count
    from pg_catalog.jsonb_array_elements(p_value) item(value);
    if selected_count <> distinct_count
      or selected_count < coalesce((p_validation ->> 'minItems')::integer, 0)
      or selected_count > coalesce((p_validation ->> 'maxItems')::integer, 100)
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(p_value) selected(value)
        where not exists (
          select 1
          from pg_catalog.jsonb_array_elements(p_options) option(value)
          where option.value ->> 'key' = selected.value #>> '{}'
            and coalesce((option.value ->> 'active')::boolean, true)
        )
      ) then
      raise exception using errcode = '23514', message = 'multi-select option set is invalid';
    end if;
    return p_value;
  end if;

  if p_value_type in (
    'party_reference', 'inventory_reference', 'location_reference',
    'user_reference'
  ) then
    if pg_catalog.jsonb_typeof(p_value) <> 'string' then
      raise exception using errcode = '23514', message = 'custom field reference is invalid';
    end if;
    perform (p_value #>> '{}')::uuid;
    return pg_catalog.to_jsonb(pg_catalog.lower(p_value #>> '{}'));
  end if;

  raise exception using errcode = '23514', message = 'custom field type is unsupported';
exception
  when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow then
    raise exception using errcode = '22003', message = 'custom field value is out of range';
end;
$$;

create function app.validate_custom_field_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owning_definition public.custom_field_definitions%rowtype;
begin
  select definition.* into owning_definition
  from public.custom_field_definitions definition
  where definition.workspace_id = new.workspace_id
    and definition.id = new.custom_field_definition_id;
  if not found then
    raise exception using errcode = '23503', message = 'custom field definition does not exist';
  end if;

  if app.custom_field_json_has_executable_key(new.validation)
    or app.custom_field_json_has_executable_key(new.options)
    or (new.default_value is not null and app.custom_field_json_has_executable_key(new.default_value)) then
    raise exception using errcode = '23514', message = 'executable custom field configuration is prohibited';
  end if;
  if exists (
    select 1 from pg_catalog.jsonb_object_keys(new.validation) item(key)
    where item.key not in (
      'minLength', 'maxLength', 'minimum', 'maximum', 'scale',
      'minItems', 'maxItems', 'allowedCurrencies'
    )
  ) then
    raise exception using errcode = '23514', message = 'custom field validation key is unsupported';
  end if;
  if new.value_type in ('single_select', 'multi_select') then
    if pg_catalog.jsonb_array_length(new.options) = 0
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(new.options) option(value)
        where pg_catalog.jsonb_typeof(option.value) <> 'object'
          or not (option.value ? 'key' and option.value ? 'labels')
          or option.value ->> 'key' !~ '^[a-z][a-z0-9_]{0,127}$'
          or pg_catalog.jsonb_typeof(option.value -> 'labels') <> 'object'
          or not (option.value -> 'labels' ? 'en' and option.value -> 'labels' ? 'fr')
      )
      or (
        select pg_catalog.count(*)
        from pg_catalog.jsonb_array_elements(new.options) option(value)
      ) <> (
        select pg_catalog.count(distinct option.value ->> 'key')
        from pg_catalog.jsonb_array_elements(new.options) option(value)
      ) then
      raise exception using errcode = '23514', message = 'custom field options are invalid';
    end if;
  elsif pg_catalog.jsonb_array_length(new.options) <> 0 then
    raise exception using errcode = '23514', message = 'non-select custom fields cannot declare options';
  end if;

  if new.visibility_permission_key is not null and not exists (
    select 1 from public.permissions permission
    where permission.key = new.visibility_permission_key
      and permission.status = 'active'
      and (permission.workspace_id is null or permission.workspace_id = new.workspace_id)
  ) then
    raise exception using errcode = '23514', message = 'custom field visibility permission is invalid';
  end if;
  if new.edit_permission_key is not null and not exists (
    select 1 from public.permissions permission
    where permission.key = new.edit_permission_key
      and permission.status = 'active'
      and (permission.workspace_id is null or permission.workspace_id = new.workspace_id)
  ) then
    raise exception using errcode = '23514', message = 'custom field edit permission is invalid';
  end if;

  if new.default_value is not null then
    new.default_value := app.normalize_custom_field_value(
      new.value_type, new.validation, new.options, new.required, new.default_value
    );
  end if;
  return new;
end;
$$;

create function app.protect_activated_custom_field_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'draft' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'UPDATE'
    and old.status = 'active'
    and new.status = 'retired'
    and old.retired_at is null
    and new.retired_at is not null
    and row(
      new.id, new.workspace_id, new.custom_field_definition_id, new.version,
      new.value_type, new.labels, new.help_text, new.validation,
      new.default_value, new.options, new.required,
      new.visibility_permission_key, new.edit_permission_key,
      new.sensitive, new.searchable, new.section_key, new.checksum,
      new.created_by, new.activated_at, new.created_at
    ) is not distinct from row(
      old.id, old.workspace_id, old.custom_field_definition_id, old.version,
      old.value_type, old.labels, old.help_text, old.validation,
      old.default_value, old.options, old.required,
      old.visibility_permission_key, old.edit_permission_key,
      old.sensitive, old.searchable, old.section_key, old.checksum,
      old.created_by, old.activated_at, old.created_at
    ) then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'activated custom field versions are immutable';
end;
$$;

create function app.prevent_custom_field_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'custom field command history is append-only';
end;
$$;

create function app.has_custom_field_entity_permission(
  p_workspace_id uuid,
  p_entity_type text,
  p_action text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_action not in ('read', 'write') then false
    when p_entity_type in ('party', 'lead') then app.has_permission(
      p_workspace_id, case when p_action = 'read' then 'crm.read' else 'crm.update' end
    )
    when p_entity_type in ('deal', 'trade_in') then app.has_permission(
      p_workspace_id, case when p_action = 'read' then 'deals.read' else 'deals.update' end
    )
    when p_entity_type = 'finance_application' then app.has_permission(
      p_workspace_id,
      case when p_action = 'read' then 'finance_applications.read' else 'finance_applications.update' end
    )
    when p_entity_type = 'inventory_unit' then app.has_permission(
      p_workspace_id, case when p_action = 'read' then 'inventory.read' else 'inventory.update' end
    )
    else false
  end
$$;

create function app.custom_field_entity_exists(
  p_workspace_id uuid,
  p_entity_type text,
  p_entity_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return case p_entity_type
    when 'inventory_unit' then exists (
      select 1 from public.inventory_units entity
      where entity.workspace_id = p_workspace_id and entity.id = p_entity_id
    )
    when 'party' then exists (
      select 1 from public.parties entity
      where entity.workspace_id = p_workspace_id and entity.id = p_entity_id
    )
    when 'lead' then exists (
      select 1 from public.leads entity
      where entity.workspace_id = p_workspace_id and entity.id = p_entity_id
    )
    when 'deal' then exists (
      select 1 from public.deals entity
      where entity.workspace_id = p_workspace_id and entity.id = p_entity_id
    )
    when 'trade_in' then exists (
      select 1 from public.trade_ins entity
      where entity.workspace_id = p_workspace_id and entity.id = p_entity_id
    )
    when 'finance_application' then exists (
      select 1 from public.finance_applications entity
      where entity.workspace_id = p_workspace_id and entity.id = p_entity_id
    )
    else false
  end;
end;
$$;

create function app.validate_custom_field_value_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  definition_row public.custom_field_definitions%rowtype;
  version_row public.custom_field_versions%rowtype;
  selected_key text;
begin
  select definition.* into definition_row
  from public.custom_field_definitions definition
  where definition.workspace_id = new.workspace_id
    and definition.id = new.custom_field_definition_id;
  select version.* into version_row
  from public.custom_field_versions version
  where version.workspace_id = new.workspace_id
    and version.id = new.custom_field_version_id;

  if not found
    or version_row.custom_field_definition_id <> new.custom_field_definition_id
    or definition_row.entity_type <> new.entity_type
    or version_row.value_type <> new.value_type then
    raise exception using errcode = '23514', message = 'custom field value/version binding is invalid';
  end if;
  if not app.custom_field_entity_exists(new.workspace_id, new.entity_type, new.entity_id) then
    raise exception using errcode = '23503', message = 'custom field owning entity does not exist';
  end if;
  if version_row.required and not new.is_set then
    raise exception using errcode = '23514', message = 'required custom field value cannot be cleared';
  end if;
  if new.is_set and new.value_type in ('single_select', 'multi_select') then
    foreach selected_key in array new.selected_keys loop
      if not exists (
        select 1
        from pg_catalog.jsonb_array_elements(version_row.options) option(value)
        where option.value ->> 'key' = selected_key
          and coalesce((option.value ->> 'active')::boolean, true)
      ) then
        raise exception using errcode = '23514', message = 'custom field option is unavailable';
      end if;
    end loop;
    if pg_catalog.cardinality(new.selected_keys) <> (
      select pg_catalog.count(distinct item.key)
      from pg_catalog.unnest(new.selected_keys) item(key)
    ) then
      raise exception using errcode = '23514', message = 'custom field options must be unique';
    end if;
  end if;
  if new.is_set and new.value_type = 'party_reference' and not exists (
    select 1 from public.parties party
    where party.workspace_id = new.workspace_id and party.id = new.reference_id
  ) then
    raise exception using errcode = '23503', message = 'custom field party reference is outside the workspace';
  end if;
  if new.is_set and new.value_type = 'inventory_reference' and not exists (
    select 1 from public.inventory_units inventory
    where inventory.workspace_id = new.workspace_id
      and inventory.id = new.reference_id
  ) then
    raise exception using errcode = '23503', message = 'custom field inventory reference is outside the workspace';
  end if;
  if new.is_set and new.value_type = 'location_reference' and not exists (
    select 1 from public.locations location
    where location.workspace_id = new.workspace_id and location.id = new.reference_id
  ) then
    raise exception using errcode = '23503', message = 'custom field location reference is outside the workspace';
  end if;
  if new.is_set and new.value_type = 'user_reference' and not exists (
    select 1 from public.workspace_memberships membership
    where membership.workspace_id = new.workspace_id
      and membership.user_id = new.reference_id
  ) then
    raise exception using errcode = '23503', message = 'custom field user reference is outside the workspace';
  end if;
  return new;
end;
$$;

create function app.create_custom_field_version(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_entity_type text,
  p_field_key text,
  p_value_type text,
  p_labels jsonb,
  p_help_text jsonb,
  p_validation jsonb,
  p_default_value jsonb,
  p_options jsonb,
  p_required boolean,
  p_visibility_permission_key text,
  p_edit_permission_key text,
  p_sensitive boolean,
  p_searchable boolean,
  p_section_key text,
  p_checksum text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  custom_field_definition_id uuid,
  custom_field_version_id uuid,
  version bigint,
  replayed boolean,
  audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  definition_row public.custom_field_definitions%rowtype;
  receipt public.custom_field_command_receipts%rowtype;
  fingerprint text;
  next_version bigint;
  new_version_id uuid;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  if not app.is_feature_entitled(
      p_workspace_id, 'custom_workflows', pg_catalog.statement_timestamp()
    )
    or actor_user_id is null
    or not app.has_permission(p_workspace_id, 'configuration.manage')
    or not app.has_recent_strong_auth() then
    raise exception using errcode = '42501', message = 'custom field configuration permission and recent strong authentication are required';
  end if;

  fingerprint := app.custom_field_fingerprint(pg_catalog.jsonb_build_object(
    'entityType', p_entity_type,
    'fieldKey', p_field_key,
    'valueType', p_value_type,
    'labels', p_labels,
    'helpText', p_help_text,
    'validation', p_validation,
    'defaultValue', p_default_value,
    'options', p_options,
    'required', p_required,
    'visibilityPermissionKey', p_visibility_permission_key,
    'editPermissionKey', p_edit_permission_key,
    'sensitive', p_sensitive,
    'searchable', p_searchable,
    'sectionKey', p_section_key,
    'checksum', p_checksum
  ));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fcreate_custom_field_version\x1f'
        || actor_user_id::text || E'\x1f'
        || coalesce(p_idempotency_key, ''),
      0
    )
  );
  select command.* into receipt
  from public.custom_field_command_receipts command
  where command.workspace_id = p_workspace_id
    and command.actor_user_id = app.current_user_id()
    and command.command_type = 'create_custom_field_version'
    and command.idempotency_key = p_idempotency_key
  for update;
  if found then
    if receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'idempotency key was reused with different custom field definition input';
    end if;
    return query select
      (receipt.result ->> 'customFieldDefinitionId')::uuid,
      (receipt.result ->> 'customFieldVersionId')::uuid,
      (receipt.result ->> 'version')::bigint,
      true,
      (receipt.result ->> 'auditEventId')::uuid;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || ':' || p_entity_type || ':' || p_field_key,
      0
    )
  );
  insert into public.custom_field_definitions (
    workspace_id, entity_type, key, status, created_by
  ) values (
    p_workspace_id, p_entity_type, p_field_key, 'active', actor_user_id
  )
  on conflict (workspace_id, entity_type, key) do nothing;
  select definition.* into definition_row
  from public.custom_field_definitions definition
  where definition.workspace_id = p_workspace_id
    and definition.entity_type = p_entity_type
    and definition.key = p_field_key
    and definition.status = 'active'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'active custom field definition was not found';
  end if;

  select coalesce(pg_catalog.max(field_version.version), 0) + 1
    into next_version
  from public.custom_field_versions field_version
  where field_version.workspace_id = p_workspace_id
    and field_version.custom_field_definition_id = definition_row.id;
  new_version_id := pg_catalog.gen_random_uuid();
  insert into public.custom_field_versions (
    id, workspace_id, custom_field_definition_id, version, value_type,
    labels, help_text, validation, default_value, options, required,
    visibility_permission_key, edit_permission_key, sensitive, searchable,
    section_key, status, checksum, created_by
  ) values (
    new_version_id, p_workspace_id, definition_row.id, next_version,
    p_value_type, p_labels, p_help_text, coalesce(p_validation, '{}'::jsonb),
    p_default_value, coalesce(p_options, '[]'::jsonb), p_required,
    p_visibility_permission_key, p_edit_permission_key, p_sensitive,
    p_searchable, p_section_key, 'draft', p_checksum, actor_user_id
  );

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'custom_field_version.created',
    p_entity_type => 'custom_field_definition',
    p_entity_id => definition_row.id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'fieldKey', definition_row.key,
      'entityType', definition_row.entity_type,
      'customFieldVersionId', new_version_id,
      'version', next_version,
      'valueType', p_value_type,
      'checksum', p_checksum,
      'sensitiveDefaultRedacted', p_sensitive and p_default_value is not null
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown')
  );
  result_payload := pg_catalog.jsonb_build_object(
    'customFieldDefinitionId', definition_row.id,
    'customFieldVersionId', new_version_id,
    'version', next_version,
    'auditEventId', new_audit_event_id
  );
  insert into public.custom_field_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, custom_field_definition_id, result
  ) values (
    p_workspace_id, actor_user_id, 'create_custom_field_version',
    p_idempotency_key, fingerprint, definition_row.id, result_payload
  );
  return query select
    definition_row.id, new_version_id, next_version, false,
    new_audit_event_id;
end;
$$;

create function app.activate_custom_field_version(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_custom_field_version_id uuid,
  p_expected_checksum text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  custom_field_definition_id uuid,
  custom_field_version_id uuid,
  version bigint,
  replayed boolean,
  audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  target public.custom_field_versions%rowtype;
  current_active public.custom_field_versions%rowtype;
  receipt public.custom_field_command_receipts%rowtype;
  fingerprint text;
  new_audit_event_id uuid;
  result_payload jsonb;
begin
  if not app.is_feature_entitled(
      p_workspace_id, 'custom_workflows', pg_catalog.statement_timestamp()
    )
    or actor_user_id is null
    or not app.has_permission(p_workspace_id, 'configuration.manage')
    or not app.has_recent_strong_auth() then
    raise exception using errcode = '42501', message = 'custom field activation permission and recent strong authentication are required';
  end if;
  if pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) = 0 then
    raise exception using errcode = '23514', message = 'custom field activation reason is required';
  end if;

  fingerprint := app.custom_field_fingerprint(pg_catalog.jsonb_build_object(
    'customFieldVersionId', p_custom_field_version_id,
    'expectedChecksum', p_expected_checksum,
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1factivate_custom_field_version\x1f'
        || actor_user_id::text || E'\x1f'
        || coalesce(p_idempotency_key, ''),
      0
    )
  );
  select command.* into receipt
  from public.custom_field_command_receipts command
  where command.workspace_id = p_workspace_id
    and command.actor_user_id = app.current_user_id()
    and command.command_type = 'activate_custom_field_version'
    and command.idempotency_key = p_idempotency_key
  for update;
  if found then
    if receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'idempotency key was reused with different custom field activation input';
    end if;
    return query select
      (receipt.result ->> 'customFieldDefinitionId')::uuid,
      (receipt.result ->> 'customFieldVersionId')::uuid,
      (receipt.result ->> 'version')::bigint,
      true,
      (receipt.result ->> 'auditEventId')::uuid;
    return;
  end if;

  select version_row.* into target
  from public.custom_field_versions version_row
  where version_row.workspace_id = p_workspace_id
    and version_row.id = p_custom_field_version_id
  for update;
  if not found or target.status <> 'draft' or target.checksum <> p_expected_checksum then
    raise exception using errcode = 'P0002', message = 'eligible custom field version was not found';
  end if;

  select version_row.* into current_active
  from public.custom_field_versions version_row
  where version_row.workspace_id = p_workspace_id
    and version_row.custom_field_definition_id = target.custom_field_definition_id
    and version_row.status = 'active'
  for update;
  if found then
    update public.custom_field_versions
    set status = 'retired', retired_at = pg_catalog.statement_timestamp()
    where workspace_id = p_workspace_id and id = current_active.id;
  end if;
  update public.custom_field_versions
  set status = 'active', activated_at = pg_catalog.statement_timestamp()
  where workspace_id = p_workspace_id and id = target.id;

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'custom_field_version.activated',
    p_entity_type => 'custom_field_definition',
    p_entity_id => target.custom_field_definition_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => case when current_active.id is null then null else
      pg_catalog.jsonb_build_object('activeVersionId', current_active.id)
    end,
    p_after_data => pg_catalog.jsonb_build_object(
      'activeVersionId', target.id,
      'version', target.version,
      'checksum', target.checksum
    ),
    p_reason => pg_catalog.btrim(p_reason),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown')
  );
  result_payload := pg_catalog.jsonb_build_object(
    'customFieldDefinitionId', target.custom_field_definition_id,
    'customFieldVersionId', target.id,
    'version', target.version,
    'auditEventId', new_audit_event_id
  );
  insert into public.custom_field_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, custom_field_definition_id, result
  ) values (
    p_workspace_id, actor_user_id, 'activate_custom_field_version',
    p_idempotency_key, fingerprint, target.custom_field_definition_id,
    result_payload
  );
  return query select
    target.custom_field_definition_id, target.id, target.version,
    false, new_audit_event_id;
end;
$$;

create function app.set_custom_field_value(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_entity_type text,
  p_entity_id uuid,
  p_custom_field_definition_id uuid,
  p_custom_field_version_id uuid,
  p_expected_version bigint,
  p_value jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  custom_field_value_id uuid,
  value_version bigint,
  replayed boolean,
  audit_event_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  definition_row public.custom_field_definitions%rowtype;
  version_row public.custom_field_versions%rowtype;
  existing_value public.custom_field_values%rowtype;
  receipt public.custom_field_command_receipts%rowtype;
  normalized_value jsonb;
  fingerprint text;
  next_version bigint;
  target_value_id uuid;
  new_audit_event_id uuid;
  result_payload jsonb;
  selected_values text[];
begin
  if not app.is_feature_entitled(
      p_workspace_id, 'custom_workflows', pg_catalog.statement_timestamp()
    )
    or actor_user_id is null
    or not app.has_custom_field_entity_permission(p_workspace_id, p_entity_type, 'write') then
    raise exception using errcode = '42501', message = 'custom field entity update permission is required';
  end if;
  if not app.custom_field_entity_exists(p_workspace_id, p_entity_type, p_entity_id) then
    raise exception using errcode = 'P0002', message = 'custom field owning entity was not found';
  end if;

  select definition.* into definition_row
  from public.custom_field_definitions definition
  where definition.workspace_id = p_workspace_id
    and definition.id = p_custom_field_definition_id
    and definition.entity_type = p_entity_type
    and definition.status = 'active';
  select version.* into version_row
  from public.custom_field_versions version
  where version.workspace_id = p_workspace_id
    and version.id = p_custom_field_version_id
    and version.custom_field_definition_id = p_custom_field_definition_id
    and version.status = 'active';
  if definition_row.id is null or version_row.id is null then
    raise exception using errcode = 'P0002', message = 'active custom field definition version was not found';
  end if;
  if version_row.edit_permission_key is not null
    and not app.has_permission(p_workspace_id, version_row.edit_permission_key) then
    raise exception using errcode = '42501', message = 'custom field edit permission is required';
  end if;

  normalized_value := app.normalize_custom_field_value(
    version_row.value_type, version_row.validation, version_row.options,
    version_row.required, p_value
  );
  if version_row.value_type = 'inventory_reference'
    and normalized_value is not null
    and not app.has_permission(p_workspace_id, 'inventory.read') then
    raise exception using errcode = '42501', message = 'custom field inventory reference permission is required';
  end if;
  fingerprint := app.custom_field_fingerprint(pg_catalog.jsonb_build_object(
    'entityType', p_entity_type,
    'entityId', p_entity_id,
    'customFieldDefinitionId', p_custom_field_definition_id,
    'customFieldVersionId', p_custom_field_version_id,
    'expectedVersion', p_expected_version,
    'value', normalized_value
  ));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_workspace_id::text || E'\x1fset_custom_field_value\x1f'
        || actor_user_id::text || E'\x1f'
        || coalesce(p_idempotency_key, ''),
      0
    )
  );
  select command.* into receipt
  from public.custom_field_command_receipts command
  where command.workspace_id = p_workspace_id
    and command.actor_user_id = app.current_user_id()
    and command.command_type = 'set_custom_field_value'
    and command.idempotency_key = p_idempotency_key
  for update;
  if found then
    if receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'idempotency key was reused with different custom field input';
    end if;
    return query select
      (receipt.result ->> 'customFieldValueId')::uuid,
      (receipt.result ->> 'valueVersion')::bigint,
      true,
      (receipt.result ->> 'auditEventId')::uuid;
    return;
  end if;

  select field_value.* into existing_value
  from public.custom_field_values field_value
  where field_value.workspace_id = p_workspace_id
    and field_value.entity_type = p_entity_type
    and field_value.entity_id = p_entity_id
    and field_value.custom_field_definition_id = p_custom_field_definition_id
  for update;
  if (found and existing_value.version <> p_expected_version)
    or (not found and p_expected_version <> 0) then
    raise exception using errcode = '40001', message = 'custom field value version conflict';
  end if;

  target_value_id := coalesce(existing_value.id, pg_catalog.gen_random_uuid());
  next_version := coalesce(existing_value.version, 0) + 1;
  if version_row.value_type = 'single_select' and normalized_value is not null then
    selected_values := array[normalized_value #>> '{}'];
  elsif version_row.value_type = 'multi_select' and normalized_value is not null then
    select pg_catalog.array_agg(item.value #>> '{}' order by item.ordinality)
      into selected_values
    from pg_catalog.jsonb_array_elements(normalized_value)
      with ordinality item(value, ordinality);
    selected_values := coalesce(selected_values, array[]::text[]);
  else
    selected_values := null;
  end if;

  insert into public.custom_field_values (
    id, workspace_id, custom_field_definition_id, custom_field_version_id,
    entity_type, entity_id, value_type, is_set, text_value,
    integer_value, decimal_value, money_minor, money_currency,
    boolean_value, date_value, datetime_value, selected_keys, reference_id,
    version, created_by, updated_by
  ) values (
    target_value_id, p_workspace_id, p_custom_field_definition_id,
    p_custom_field_version_id, p_entity_type, p_entity_id,
    version_row.value_type, normalized_value is not null,
    case when version_row.value_type in ('short_text', 'long_text')
      then normalized_value #>> '{}' else null end,
    case when version_row.value_type = 'integer'
      then (normalized_value #>> '{}')::numeric else null end,
    case when version_row.value_type = 'decimal'
      then (normalized_value #>> '{}')::numeric else null end,
    case when version_row.value_type = 'money'
      then (normalized_value ->> 'amountMinor')::bigint else null end,
    case when version_row.value_type = 'money'
      then normalized_value ->> 'currencyCode' else null end,
    case when version_row.value_type = 'boolean'
      then (normalized_value #>> '{}')::boolean else null end,
    case when version_row.value_type = 'date'
      then (normalized_value #>> '{}')::date else null end,
    case when version_row.value_type = 'datetime'
      then (normalized_value #>> '{}')::timestamptz else null end,
    selected_values,
    case when version_row.value_type in (
      'party_reference', 'inventory_reference', 'location_reference',
      'user_reference'
    ) then (normalized_value #>> '{}')::uuid else null end,
    next_version, actor_user_id, actor_user_id
  )
  on conflict (workspace_id, entity_type, entity_id, custom_field_definition_id)
  do update set
    custom_field_version_id = excluded.custom_field_version_id,
    value_type = excluded.value_type,
    is_set = excluded.is_set,
    text_value = excluded.text_value,
    integer_value = excluded.integer_value,
    decimal_value = excluded.decimal_value,
    money_minor = excluded.money_minor,
    money_currency = excluded.money_currency,
    boolean_value = excluded.boolean_value,
    date_value = excluded.date_value,
    datetime_value = excluded.datetime_value,
    selected_keys = excluded.selected_keys,
    reference_id = excluded.reference_id,
    version = excluded.version,
    updated_by = excluded.updated_by,
    updated_at = pg_catalog.statement_timestamp();

  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => case when existing_value.id is null
      then 'custom_field_value.created' else 'custom_field_value.updated' end,
    p_entity_type => p_entity_type,
    p_entity_id => p_entity_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => case when existing_value.id is null then null else
      pg_catalog.jsonb_build_object(
        'fieldKey', definition_row.key,
        'definitionVersionId', existing_value.custom_field_version_id,
        'valueVersion', existing_value.version,
        'valueRedacted', version_row.sensitive
      )
    end,
    p_after_data => pg_catalog.jsonb_build_object(
      'fieldKey', definition_row.key,
      'definitionVersionId', version_row.id,
      'valueVersion', next_version,
      'isSet', normalized_value is not null,
      'valueRedacted', version_row.sensitive
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'customFieldDefinitionId', p_custom_field_definition_id,
      'sensitiveValueExcluded', version_row.sensitive
    )
  );
  result_payload := pg_catalog.jsonb_build_object(
    'customFieldValueId', target_value_id,
    'valueVersion', next_version,
    'auditEventId', new_audit_event_id
  );
  insert into public.custom_field_command_receipts (
    workspace_id, actor_user_id, command_type, idempotency_key,
    command_fingerprint, custom_field_definition_id, entity_type,
    entity_id, result
  ) values (
    p_workspace_id, actor_user_id, 'set_custom_field_value',
    p_idempotency_key, fingerprint, p_custom_field_definition_id,
    p_entity_type, p_entity_id, result_payload
  );
  return query select target_value_id, next_version, false, new_audit_event_id;
end;
$$;

create function app.get_custom_field_values(
  p_workspace_id uuid,
  p_entity_type text,
  p_entity_id uuid
)
returns table (
  custom_field_definition_id uuid,
  custom_field_version_id uuid,
  field_key text,
  field_type text,
  labels jsonb,
  help_text jsonb,
  section_key text,
  required boolean,
  sensitive boolean,
  searchable boolean,
  masked boolean,
  value jsonb,
  value_version bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    definition.id,
    coalesce(pinned_version.id, active_version.id),
    definition.key,
    coalesce(pinned_version.value_type, active_version.value_type),
    coalesce(pinned_version.labels, active_version.labels),
    coalesce(pinned_version.help_text, active_version.help_text),
    coalesce(pinned_version.section_key, active_version.section_key),
    coalesce(pinned_version.required, active_version.required),
    coalesce(pinned_version.sensitive, active_version.sensitive),
    coalesce(pinned_version.searchable, active_version.searchable),
    (
      coalesce(
        pinned_version.visibility_permission_key,
        active_version.visibility_permission_key
      ) is not null
        and not app.has_permission(
          p_workspace_id,
          coalesce(
            pinned_version.visibility_permission_key,
            active_version.visibility_permission_key
          )
        )
    ) or (
      coalesce(pinned_version.value_type, active_version.value_type)
        = 'inventory_reference'
      and not app.has_permission(p_workspace_id, 'inventory.read')
    ) as masked,
    case
      when coalesce(
        pinned_version.visibility_permission_key,
        active_version.visibility_permission_key
      ) is not null
        and not app.has_permission(
          p_workspace_id,
          coalesce(
            pinned_version.visibility_permission_key,
            active_version.visibility_permission_key
          )
        ) then null
      when coalesce(pinned_version.value_type, active_version.value_type)
          = 'inventory_reference'
        and not app.has_permission(p_workspace_id, 'inventory.read') then null
      when field_value.id is null then active_version.default_value
      when not field_value.is_set then null
      when field_value.value_type in ('short_text', 'long_text')
        then pg_catalog.to_jsonb(field_value.text_value)
      when field_value.value_type = 'integer'
        then pg_catalog.to_jsonb(field_value.integer_value::text)
      when field_value.value_type = 'decimal'
        then pg_catalog.to_jsonb(field_value.decimal_value::text)
      when field_value.value_type = 'money' then pg_catalog.jsonb_build_object(
        'amountMinor', field_value.money_minor::text,
        'currencyCode', field_value.money_currency
      )
      when field_value.value_type = 'boolean'
        then pg_catalog.to_jsonb(field_value.boolean_value)
      when field_value.value_type = 'date'
        then pg_catalog.to_jsonb(pg_catalog.to_char(field_value.date_value, 'YYYY-MM-DD'))
      when field_value.value_type = 'datetime'
        then pg_catalog.to_jsonb(field_value.datetime_value)
      when field_value.value_type = 'single_select'
        then pg_catalog.to_jsonb(field_value.selected_keys[1])
      when field_value.value_type = 'multi_select'
        then pg_catalog.to_jsonb(field_value.selected_keys)
      when field_value.value_type in (
        'party_reference', 'inventory_reference', 'location_reference',
        'user_reference'
      ) then pg_catalog.to_jsonb(field_value.reference_id::text)
      else null
    end,
    field_value.version
  from public.custom_field_definitions definition
  join public.custom_field_versions active_version
    on active_version.workspace_id = definition.workspace_id
   and active_version.custom_field_definition_id = definition.id
   and active_version.status = 'active'
  left join public.custom_field_values field_value
    on field_value.workspace_id = definition.workspace_id
   and field_value.custom_field_definition_id = definition.id
   and field_value.entity_type = p_entity_type
   and field_value.entity_id = p_entity_id
  left join public.custom_field_versions pinned_version
    on pinned_version.workspace_id = field_value.workspace_id
   and pinned_version.id = field_value.custom_field_version_id
  where definition.workspace_id = p_workspace_id
    and definition.entity_type = p_entity_type
    and definition.status = 'active'
    and app.is_feature_entitled(
      p_workspace_id, 'custom_workflows', pg_catalog.statement_timestamp()
    )
    and app.custom_field_entity_exists(p_workspace_id, p_entity_type, p_entity_id)
    and app.has_custom_field_entity_permission(p_workspace_id, p_entity_type, 'read')
  order by
    coalesce(pinned_version.section_key, active_version.section_key),
    definition.key
  limit 500
$$;

create trigger custom_field_definitions_immutable_ownership
before update on public.custom_field_definitions
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'entity_type', 'key', 'created_by', 'created_at'
);
create trigger custom_field_definitions_prevent_hard_delete
before delete on public.custom_field_definitions
for each row execute function app.prevent_hard_delete();
create trigger custom_field_versions_validate
before insert or update on public.custom_field_versions
for each row execute function app.validate_custom_field_version();
create trigger custom_field_versions_protect_activated
before update or delete on public.custom_field_versions
for each row execute function app.protect_activated_custom_field_version();
create trigger custom_field_values_validate
before insert or update on public.custom_field_values
for each row execute function app.validate_custom_field_value_row();
create trigger custom_field_values_immutable_ownership
before update on public.custom_field_values
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'custom_field_definition_id',
  'entity_type', 'entity_id', 'created_by', 'created_at'
);
create trigger custom_field_values_prevent_hard_delete
before delete on public.custom_field_values
for each row execute function app.prevent_hard_delete();
create trigger custom_field_command_receipts_append_only
before update or delete on public.custom_field_command_receipts
for each row execute function app.prevent_custom_field_history_mutation();

alter table public.custom_field_definitions enable row level security;
alter table public.custom_field_definitions force row level security;
alter table public.custom_field_versions enable row level security;
alter table public.custom_field_versions force row level security;
alter table public.custom_field_values enable row level security;
alter table public.custom_field_values force row level security;
alter table public.custom_field_command_receipts enable row level security;
alter table public.custom_field_command_receipts force row level security;

create policy custom_field_definitions_select
on public.custom_field_definitions
for select to authenticated
using (
  app.is_feature_entitled(
    workspace_id, 'custom_workflows', pg_catalog.statement_timestamp()
  ) and (
    app.has_permission(workspace_id, 'configuration.read')
    or app.has_custom_field_entity_permission(workspace_id, entity_type, 'read')
  )
);
create policy custom_field_versions_select
on public.custom_field_versions
for select to authenticated
using (
  app.is_feature_entitled(
    workspace_id, 'custom_workflows', pg_catalog.statement_timestamp()
  ) and (
    app.has_permission(workspace_id, 'configuration.read')
    or exists (
      select 1 from public.custom_field_definitions definition
      where definition.workspace_id = custom_field_versions.workspace_id
        and definition.id = custom_field_versions.custom_field_definition_id
        and app.has_custom_field_entity_permission(
          definition.workspace_id, definition.entity_type, 'read'
        )
    )
  )
);
create policy custom_field_values_select
on public.custom_field_values
for select to authenticated
using (
  app.is_feature_entitled(
    workspace_id, 'custom_workflows', pg_catalog.statement_timestamp()
  )
  and app.has_custom_field_entity_permission(workspace_id, entity_type, 'read')
  and exists (
    select 1 from public.custom_field_versions version
    where version.workspace_id = custom_field_values.workspace_id
      and version.id = custom_field_values.custom_field_version_id
      and (
        version.visibility_permission_key is null
        or app.has_permission(
          custom_field_values.workspace_id, version.visibility_permission_key
        )
      )
  )
);

revoke all on table
  public.custom_field_definitions,
  public.custom_field_versions,
  public.custom_field_values,
  public.custom_field_command_receipts
from public, anon, authenticated, service_role;
grant select on
  public.custom_field_definitions,
  public.custom_field_versions,
  public.custom_field_values
to authenticated, service_role;
grant select on public.custom_field_command_receipts to service_role;

revoke all on function app.custom_field_fingerprint(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.custom_field_json_has_executable_key(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.normalize_custom_field_value(text, jsonb, jsonb, boolean, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.has_custom_field_entity_permission(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function app.custom_field_entity_exists(uuid, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.validate_custom_field_version()
  from public, anon, authenticated, service_role;
revoke all on function app.protect_activated_custom_field_version()
  from public, anon, authenticated, service_role;
revoke all on function app.validate_custom_field_value_row()
  from public, anon, authenticated, service_role;
revoke all on function app.create_custom_field_version(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb,
  boolean, text, text, boolean, boolean, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.activate_custom_field_version(
  uuid, text, uuid, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.set_custom_field_value(
  uuid, text, text, uuid, uuid, uuid, bigint, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.get_custom_field_values(uuid, text, uuid)
  from public, anon, authenticated, service_role;

-- Authenticated SELECT policies invoke this narrow permission mapper.
grant execute on function app.has_custom_field_entity_permission(uuid, text, text)
  to authenticated;
grant execute on function app.activate_custom_field_version(
  uuid, text, uuid, text, text, text, uuid
) to authenticated;
grant execute on function app.create_custom_field_version(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb,
  boolean, text, text, boolean, boolean, text, text, text, uuid
) to authenticated;
grant execute on function app.set_custom_field_value(
  uuid, text, text, uuid, uuid, uuid, bigint, jsonb, text, uuid
) to authenticated;
grant execute on function app.get_custom_field_values(uuid, text, uuid)
  to authenticated;

comment on table public.custom_field_versions is
  'Immutable after activation; typed, bilingual, permission-aware custom-field configuration.';
comment on table public.custom_field_values is
  'Workspace/entity-owned typed values pinned to the exact custom-field version used for validation.';
comment on function app.create_custom_field_version(
  uuid, text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb,
  boolean, text, text, boolean, boolean, text, text, text, uuid
) is 'Actor-idempotent, entitlement-gated command that appends a validated draft definition version.';
comment on function app.set_custom_field_value(
  uuid, text, text, uuid, uuid, uuid, bigint, jsonb, text, uuid
) is 'Actor-idempotent optimistic typed-value command with cross-workspace reference validation and redacted audit.';
comment on function app.get_custom_field_values(uuid, text, uuid) is
  'Parent-entity-authorized projection that masks fields lacking their dedicated visibility permission.';
