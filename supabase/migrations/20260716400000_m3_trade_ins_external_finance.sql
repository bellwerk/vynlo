-- VYN-DEAL-001, VYN-FIN-001, VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, VYN-JOB-001
-- M3-DEAL-AC-003 / M3-FIN-AC-001 / T-DEAL-002 / T-FIN-001
-- Workspace-owned trade-in and external-lender tracking. This migration stores
-- exact facts and lender-reported outcomes only: it does not calculate tax,
-- originate credit, call a provider, or create repayment/servicing schedules.

create function app.m3_inert_json_is_safe(candidate jsonb, current_depth integer)
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
  if current_depth > 16 then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(candidate) = 'object' then
    for entry_key, entry_value in
      select item.key, item.value
      from pg_catalog.jsonb_each(candidate) item
    loop
      if entry_key = ''
        or pg_catalog.char_length(entry_key) > 128
        or pg_catalog.lower(
          pg_catalog.regexp_replace(entry_key, '[^a-z0-9]', '', 'g')
        ) in (
          'command', 'eval', 'fetch', 'filesystem', 'function', 'http',
          'import', 'javascript', 'module', 'network', 'script', 'shell',
          'sql', 'url'
        )
        or not app.m3_inert_json_is_safe(entry_value, current_depth + 1) then
        return false;
      end if;
    end loop;
  elsif pg_catalog.jsonb_typeof(candidate) = 'array' then
    if pg_catalog.jsonb_array_length(candidate) > 200 then
      return false;
    end if;
    for entry_value in
      select item.value from pg_catalog.jsonb_array_elements(candidate) item
    loop
      if not app.m3_inert_json_is_safe(entry_value, current_depth + 1) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end;
$$;

create function app.m3_inert_json_is_safe(candidate jsonb)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.octet_length(candidate::text) <= 16384
    and app.m3_inert_json_is_safe(candidate, 0);
$$;

create table public.trade_ins (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  deal_id uuid not null,
  owner_party_id uuid not null,
  vehicle_id uuid,
  entered_vehicle_facts jsonb,
  allowance_minor bigint not null check (allowance_minor >= 0),
  lien_amount_minor bigint not null check (lien_amount_minor >= 0),
  payoff_amount_minor bigint not null check (payoff_amount_minor >= 0),
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
  lender_party_id uuid,
  odometer_value bigint check (odometer_value is null or odometer_value >= 0),
  odometer_unit text check (odometer_unit is null or odometer_unit in ('km', 'mi')),
  condition_key text check (
    condition_key is null or condition_key ~ '^[a-z][a-z0-9_.-]{0,127}$'
  ),
  tax_eligibility_inputs jsonb not null default '{}'::jsonb,
  resulting_inventory_unit_id uuid,
  status text not null default 'active' check (
    status in ('active', 'confirmed', 'cancelled')
  ),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, owner_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, lender_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, vehicle_id)
    references public.vehicles (workspace_id, id) on delete restrict,
  foreign key (workspace_id, resulting_inventory_unit_id)
    references public.inventory_units (workspace_id, id) on delete restrict,
  check (vehicle_id is not null or entered_vehicle_facts is not null),
  check (
    entered_vehicle_facts is null or (
      pg_catalog.jsonb_typeof(entered_vehicle_facts) = 'object'
      and app.m3_inert_json_is_safe(entered_vehicle_facts)
    )
  ),
  check (
    pg_catalog.jsonb_typeof(tax_eligibility_inputs) = 'object'
    and app.m3_inert_json_is_safe(tax_eligibility_inputs)
  ),
  check ((odometer_value is null) = (odometer_unit is null)),
  check (
    (status = 'confirmed' and resulting_inventory_unit_id is not null)
    or (status in ('active', 'cancelled') and resulting_inventory_unit_id is null)
  )
);

create index trade_ins_deal_idx
  on public.trade_ins (workspace_id, deal_id, status, created_at, id);
create unique index trade_ins_resulting_inventory_uidx
  on public.trade_ins (workspace_id, resulting_inventory_unit_id)
  where resulting_inventory_unit_id is not null;
create unique index deal_inventory_units_active_trade_in_uidx
  on public.deal_inventory_units (workspace_id, inventory_unit_id)
  where role_key = 'trade_in' and status = 'active';

create table public.finance_applications (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  deal_id uuid not null,
  applicant_party_id uuid not null,
  lender_party_id uuid not null,
  requested_amount_minor bigint not null check (requested_amount_minor > 0),
  approved_amount_minor bigint check (
    approved_amount_minor is null or approved_amount_minor > 0
  ),
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
  external_reference text check (
    external_reference is null or pg_catalog.char_length(external_reference) <= 500
  ),
  lender_reported_annual_rate_text text check (
    lender_reported_annual_rate_text is null
    or lender_reported_annual_rate_text ~ '^(?:0|[1-9][0-9]{0,2})(?:\.[0-9]{1,6})?$'
  ),
  lender_reported_annual_rate numeric(9, 6) generated always as (
    lender_reported_annual_rate_text::numeric
  ) stored,
  lender_reported_term_months integer check (
    lender_reported_term_months is null
    or lender_reported_term_months between 1 and 1200
  ),
  notes text check (notes is null or pg_catalog.char_length(notes) <= 4000),
  submitted_at timestamptz,
  decision_at timestamptz,
  approval_expires_at timestamptz,
  customer_accepted_at timestamptz,
  funded_at timestamptz,
  funding_reference text check (
    funding_reference is null or pg_catalog.char_length(funding_reference) <= 500
  ),
  status text not null default 'preparing' check (status in (
    'preparing', 'submitted', 'additional_information_required',
    'conditionally_approved', 'approved', 'declined', 'customer_declined',
    'funded', 'cancelled', 'expired'
  )),
  status_reason text check (
    status_reason is null or (
      pg_catalog.btrim(status_reason) <> ''
      and pg_catalog.char_length(status_reason) <= 2000
    )
  ),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, applicant_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  foreign key (workspace_id, lender_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  check (approval_expires_at is null or submitted_at is not null),
  check (decision_at is null or submitted_at is not null),
  check (customer_accepted_at is null or approved_amount_minor is not null),
  check (funding_reference is null or funded_at is not null),
  check (
    submitted_at is null or approval_expires_at is null
    or approval_expires_at > submitted_at
  ),
  check (
    submitted_at is null or customer_accepted_at is null
    or customer_accepted_at >= submitted_at
  ),
  check (
    submitted_at is null or funded_at is null or funded_at >= submitted_at
  ),
  check (
    customer_accepted_at is null or funded_at is null
    or funded_at >= customer_accepted_at
  ),
  check (
    status not in ('submitted', 'additional_information_required',
      'conditionally_approved', 'approved', 'declined', 'customer_declined',
      'funded', 'expired')
    or submitted_at is not null
  ),
  check (
    status not in ('conditionally_approved', 'approved', 'funded')
    or (approved_amount_minor is not null and decision_at is not null)
  ),
  check (
    status <> 'funded'
    or (funded_at is not null and customer_accepted_at is not null)
  ),
  check (status <> 'expired' or approval_expires_at is not null),
  check (
    status not in ('declined', 'customer_declined', 'cancelled')
    or status_reason is not null
  )
);

create index finance_applications_deal_idx
  on public.finance_applications (workspace_id, deal_id, updated_at desc, id);
create index finance_applications_status_idx
  on public.finance_applications (workspace_id, status, updated_at desc, id);

create table public.finance_application_conditions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  finance_application_id uuid not null,
  logical_condition_id uuid not null,
  condition_key text not null check (
    condition_key ~ '^[a-z][a-z0-9_.-]{0,127}$'
  ),
  description text not null check (
    pg_catalog.btrim(description) <> ''
    and pg_catalog.char_length(description) <= 2000
  ),
  required boolean not null,
  satisfied_at timestamptz,
  due_at timestamptz,
  supporting_file_id uuid,
  version bigint not null default 1 check (version > 0),
  status text not null default 'active' check (
    status in ('active', 'replaced')
  ),
  replaces_condition_id uuid,
  replaced_at timestamptz,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  unique (
    workspace_id, finance_application_id, logical_condition_id, version
  ),
  foreign key (workspace_id, finance_application_id)
    references public.finance_applications (workspace_id, id) on delete restrict,
  foreign key (workspace_id, supporting_file_id)
    references public.media_files (workspace_id, id) on delete restrict,
  foreign key (workspace_id, replaces_condition_id)
    references public.finance_application_conditions (workspace_id, id)
    on delete restrict,
  check (
    (version = 1 and replaces_condition_id is null)
    or (version > 1 and replaces_condition_id is not null)
  ),
  check (
    (status = 'active' and replaced_at is null)
    or (status = 'replaced' and replaced_at is not null)
  )
);

create index finance_application_conditions_application_idx
  on public.finance_application_conditions (
    workspace_id, finance_application_id, status, created_at, id
  );
create unique index finance_application_conditions_active_key_uidx
  on public.finance_application_conditions (
    workspace_id, finance_application_id, condition_key
  ) where status = 'active';

alter table public.deal_command_receipts
  drop constraint deal_command_receipts_command_type_check;
alter table public.deal_command_receipts
  add constraint deal_command_receipts_command_type_check check (command_type in (
    'm3_create_deal', 'm3_update_deal', 'm3_transition_deal',
    'm3_add_deal_participant', 'm3_release_deal_participant',
    'm3_add_deal_inventory', 'm3_release_deal_inventory',
    'm3_add_deal_line_item', 'm3_update_deal_line_item',
    'm3_create_trade_in', 'm3_update_trade_in',
    'm3_confirm_trade_in_inventory',
    'm3_create_finance_application', 'm3_update_finance_application',
    'm3_transition_finance_application', 'm3_add_finance_condition',
    'm3_update_finance_condition'
  ));

create function app.assert_trade_in_links()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  deal_currency text;
  deal_lifecycle text;
  allowed_inventory_roles text[];
  inventory_vehicle_id uuid;
  inventory_currency text;
  inventory_status text;
begin
  select
    deal.currency_code::text,
    deal.lifecycle_status,
    version.allowed_inventory_roles
  into deal_currency, deal_lifecycle, allowed_inventory_roles
  from public.deals deal
  join public.deal_type_versions version
    on version.workspace_id = deal.workspace_id
   and version.id = deal.deal_type_version_id
  where deal.workspace_id = new.workspace_id and deal.id = new.deal_id;
  if not found or deal_lifecycle <> 'active' then
    raise exception using errcode = '23514', message = 'active configured deal is required for a trade-in';
  end if;
  if not ('trade_in' = any(allowed_inventory_roles)) then
    raise exception using errcode = '23514', message = 'trade-in role is not allowed by the pinned deal type';
  end if;
  if new.currency_code::text <> deal_currency then
    raise exception using errcode = '23514', message = 'trade-in currency must match deal currency';
  end if;
  if not exists (
    select 1 from public.parties party
    where party.workspace_id = new.workspace_id
      and party.id = new.owner_party_id
      and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace trade-in owner is required';
  end if;
  if new.lender_party_id is not null and not exists (
    select 1 from public.parties party
    where party.workspace_id = new.workspace_id
      and party.id = new.lender_party_id
      and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace trade-in lender is required';
  end if;
  if new.resulting_inventory_unit_id is not null then
    select inventory.vehicle_id, inventory.currency_code::text, inventory.status
      into inventory_vehicle_id, inventory_currency, inventory_status
    from public.inventory_units inventory
    where inventory.workspace_id = new.workspace_id
      and inventory.id = new.resulting_inventory_unit_id;
    if not found or inventory_status not in ('draft', 'active') then
      raise exception using errcode = '23514', message = 'available independently created inventory unit is required';
    end if;
    if inventory_currency <> deal_currency
      or (new.vehicle_id is not null and new.vehicle_id <> inventory_vehicle_id) then
      raise exception using errcode = '23514', message = 'trade-in and resulting inventory unit do not match';
    end if;
  end if;
  return new;
end;
$$;

create trigger trade_ins_validate_links
before insert or update on public.trade_ins
for each row execute function app.assert_trade_in_links();
create trigger trade_ins_updated_at
before update on public.trade_ins
for each row execute function app.set_updated_at();
create trigger trade_ins_immutable_ownership
before update on public.trade_ins
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'deal_id', 'created_by', 'created_at'
);
create trigger trade_ins_prevent_hard_delete
before delete on public.trade_ins
for each row execute function app.prevent_hard_delete();

create function app.assert_finance_application_links()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  deal_currency text;
  deal_lifecycle text;
  finance_mode text;
begin
  select
    deal.currency_code::text,
    deal.lifecycle_status,
    coalesce(version.behavior_flags ->> 'finance_mode', 'none')
  into deal_currency, deal_lifecycle, finance_mode
  from public.deals deal
  join public.deal_type_versions version
    on version.workspace_id = deal.workspace_id
   and version.id = deal.deal_type_version_id
  where deal.workspace_id = new.workspace_id and deal.id = new.deal_id;
  if not found or deal_lifecycle <> 'active'
    or finance_mode <> 'external_lender_tracking' then
    raise exception using errcode = '23514', message = 'active external-finance deal configuration is required';
  end if;
  if new.currency_code::text <> deal_currency then
    raise exception using errcode = '23514', message = 'finance application currency must match deal currency';
  end if;
  if not exists (
    select 1 from public.parties party
    where party.workspace_id = new.workspace_id
      and party.id = new.applicant_party_id
      and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace finance applicant is required';
  end if;
  if not exists (
    select 1 from public.parties party
    where party.workspace_id = new.workspace_id
      and party.id = new.lender_party_id
      and party.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'active workspace finance lender is required';
  end if;
  return new;
end;
$$;

create trigger finance_applications_validate_links
before insert or update on public.finance_applications
for each row execute function app.assert_finance_application_links();
create trigger finance_applications_updated_at
before update on public.finance_applications
for each row execute function app.set_updated_at();
create trigger finance_applications_immutable_ownership
before update on public.finance_applications
for each row execute function app.enforce_immutable_columns(
  'id', 'workspace_id', 'deal_id', 'applicant_party_id', 'lender_party_id',
  'requested_amount_minor', 'currency_code', 'created_by', 'created_at'
);
create trigger finance_applications_prevent_hard_delete
before delete on public.finance_applications
for each row execute function app.prevent_hard_delete();

create function app.assert_finance_condition_attachment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_deal_id uuid;
  replaced_condition public.finance_application_conditions%rowtype;
begin
  select application.deal_id into target_deal_id
  from public.finance_applications application
  where application.workspace_id = new.workspace_id
    and application.id = new.finance_application_id;
  if not found then
    raise exception using errcode = '23514', message = 'workspace finance application is required for a condition';
  end if;
  if new.status <> 'active' then
    raise exception using errcode = '23514', message = 'new finance condition version must be active';
  end if;
  if new.version = 1 then
    if new.logical_condition_id <> new.id
      or new.replaces_condition_id is not null then
      raise exception using errcode = '23514', message = 'initial finance condition lineage is invalid';
    end if;
  else
    select condition.* into replaced_condition
    from public.finance_application_conditions condition
    where condition.workspace_id = new.workspace_id
      and condition.id = new.replaces_condition_id;
    if not found
      or replaced_condition.finance_application_id <> new.finance_application_id
      or replaced_condition.logical_condition_id <> new.logical_condition_id
      or replaced_condition.condition_key <> new.condition_key
      or replaced_condition.version + 1 <> new.version
      or replaced_condition.status <> 'replaced' then
      raise exception using errcode = '23514', message = 'replacement finance condition lineage is invalid';
    end if;
  end if;
  if new.supporting_file_id is not null and not exists (
    select 1
    from public.media_files file
    join public.media_assets asset
      on asset.workspace_id = file.workspace_id
     and asset.id = file.media_id
    where file.workspace_id = new.workspace_id
      and file.id = new.supporting_file_id
      and file.file_class = 'legal_document_original'
      and file.variant = 'legal_original'
      and file.retention_policy = 'preserve_original'
      and file.deleted_at is null
      and asset.media_kind = 'legal_document'
      and asset.status = 'ready'
      and asset.owner_entity_type = 'deal'
      and asset.owner_entity_id = target_deal_id
      and asset.deal_id = target_deal_id
  ) then
    raise exception using errcode = '23514', message = 'condition attachment must be a ready preserved legal original owned by the same deal';
  end if;
  return new;
end;
$$;

create trigger finance_application_conditions_validate_attachment
before insert on public.finance_application_conditions
for each row execute function app.assert_finance_condition_attachment();

create function app.protect_finance_condition_history()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'finance condition history is append-only';
  end if;
  if old.status = 'active'
    and new.status = 'replaced'
    and new.replaced_at is not null
    and pg_catalog.to_jsonb(new) - array['status', 'replaced_at']::text[]
      = pg_catalog.to_jsonb(old) - array['status', 'replaced_at']::text[] then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'finance condition versions are immutable except controlled replacement';
end;
$$;

create trigger finance_application_conditions_protect_history
before update or delete on public.finance_application_conditions
for each row execute function app.protect_finance_condition_history();

create function app.require_finance_permission(
  p_workspace_id uuid,
  p_finance_permission_key text,
  p_deal_permission_key text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
begin
  actor_user_id := app.require_deal_permission(
    p_workspace_id, p_deal_permission_key
  );
  if not app.is_feature_entitled(
      p_workspace_id, 'third_party_finance', pg_catalog.statement_timestamp()
    ) or not app.has_permission(p_workspace_id, p_finance_permission_key) then
    raise exception using errcode = '42501', message = 'active third-party-finance entitlement and permission are required';
  end if;
  return actor_user_id;
end;
$$;

create function app.can_read_finance_workspace(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.can_read_deal_workspace(p_workspace_id)
    and app.is_feature_entitled(
      p_workspace_id, 'third_party_finance', pg_catalog.statement_timestamp()
    )
    and app.has_permission(p_workspace_id, 'finance_applications.read');
$$;

create function app.lock_current_finance_deal(
  p_workspace_id uuid,
  p_deal_id uuid
)
returns public.deals
language plpgsql
security definer
set search_path = ''
as $$
declare
  locked_deal public.deals%rowtype;
  finance_mode text;
begin
  select deal.* into locked_deal
  from public.deals deal
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  if locked_deal.lifecycle_status <> 'active' then
    raise exception using errcode = '55000', message = 'completed deal cannot be changed';
  end if;
  select coalesce(version.behavior_flags ->> 'finance_mode', 'none')
    into finance_mode
  from public.deal_type_versions version
  where version.workspace_id = p_workspace_id
    and version.id = locked_deal.deal_type_version_id;
  if finance_mode <> 'external_lender_tracking' then
    raise exception using errcode = '23514', message = 'deal type does not allow external finance tracking';
  end if;
  return locked_deal;
end;
$$;

create or replace function app.deal_external_finance_approved(
  p_workspace_id uuid,
  p_deal_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.finance_applications application
    where application.workspace_id = p_workspace_id
      and application.deal_id = p_deal_id
      and (
        application.status = 'funded'
        or (
          application.status = 'approved'
          and (
            application.approval_expires_at is null
            or application.approval_expires_at > pg_catalog.statement_timestamp()
          )
        )
      )
  );
$$;

create function app.m3_list_trade_ins(
  p_workspace_id uuid,
  p_deal_id uuid
)
returns table (
  trade_in_id uuid,
  deal_id uuid,
  owner_party_id uuid,
  vehicle_id uuid,
  entered_vehicle_facts jsonb,
  allowance_minor text,
  lien_amount_minor text,
  payoff_amount_minor text,
  currency_code text,
  lender_party_id uuid,
  odometer_value bigint,
  odometer_unit text,
  condition_key text,
  tax_eligibility_inputs jsonb,
  resulting_inventory_unit_id uuid,
  status text,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_deal_permission(p_workspace_id, 'deals.read');
  if not exists (
    select 1 from public.deals deal
    where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  ) then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  return query
  select
    trade_in.id,
    trade_in.deal_id,
    trade_in.owner_party_id,
    trade_in.vehicle_id,
    trade_in.entered_vehicle_facts,
    trade_in.allowance_minor::text,
    trade_in.lien_amount_minor::text,
    trade_in.payoff_amount_minor::text,
    trade_in.currency_code::text,
    trade_in.lender_party_id,
    trade_in.odometer_value,
    trade_in.odometer_unit,
    trade_in.condition_key,
    trade_in.tax_eligibility_inputs,
    trade_in.resulting_inventory_unit_id,
    trade_in.status,
    trade_in.version,
    trade_in.created_at,
    trade_in.updated_at
  from public.trade_ins trade_in
  where trade_in.workspace_id = p_workspace_id
    and trade_in.deal_id = p_deal_id
  order by trade_in.created_at, trade_in.id
  limit 100;
end;
$$;

create function app.m3_create_trade_in(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_expected_version bigint,
  p_owner_party_id uuid,
  p_vehicle_id uuid,
  p_entered_vehicle_facts jsonb,
  p_allowance_minor text,
  p_currency_code text,
  p_lien_amount_minor text,
  p_payoff_amount_minor text,
  p_lender_party_id uuid,
  p_odometer_value bigint,
  p_odometer_unit text,
  p_condition_key text,
  p_tax_eligibility_inputs jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  trade_in_id uuid,
  trade_in_version bigint,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
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
  normalized_idempotency_key text;
  normalized_currency text;
  normalized_condition_key text;
  normalized_odometer_unit text;
  exact_allowance bigint;
  exact_lien bigint;
  exact_payoff bigint;
  safe_tax_inputs jsonb;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  updated_deal public.deals%rowtype;
  new_trade_in_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_condition_key := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_condition_key, ''))), ''
  );
  normalized_odometer_unit := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_odometer_unit, ''))), ''
  );
  exact_allowance := app.parse_deal_minor_units(p_allowance_minor);
  exact_lien := app.parse_deal_minor_units(p_lien_amount_minor);
  exact_payoff := app.parse_deal_minor_units(p_payoff_amount_minor);
  if normalized_currency !~ '^[A-Z]{3}$'
    or exact_allowance < 0 or exact_lien < 0 or exact_payoff < 0 then
    raise exception using errcode = '22023', message = 'invalid exact trade-in money';
  end if;
  if normalized_condition_key is not null
    and normalized_condition_key !~ '^[a-z][a-z0-9_.-]{0,127}$' then
    raise exception using errcode = '22023', message = 'invalid trade-in condition key';
  end if;
  if (p_odometer_value is null) <> (normalized_odometer_unit is null)
    or (p_odometer_value is not null and p_odometer_value < 0)
    or (normalized_odometer_unit is not null
      and normalized_odometer_unit not in ('km', 'mi')) then
    raise exception using errcode = '22023', message = 'invalid trade-in odometer pair';
  end if;
  if p_vehicle_id is null and p_entered_vehicle_facts is null then
    raise exception using errcode = '23514', message = 'trade-in vehicle or entered facts are required';
  end if;
  if p_entered_vehicle_facts is not null and (
      pg_catalog.jsonb_typeof(p_entered_vehicle_facts) <> 'object'
      or not app.m3_inert_json_is_safe(p_entered_vehicle_facts)
    ) then
    raise exception using errcode = '23514', message = 'entered trade-in facts must be bounded inert data';
  end if;
  safe_tax_inputs := p_tax_eligibility_inputs;
  if safe_tax_inputs is null
    or pg_catalog.jsonb_typeof(safe_tax_inputs) <> 'object'
    or not app.m3_inert_json_is_safe(safe_tax_inputs) then
    raise exception using errcode = '23514', message = 'tax eligibility inputs must be bounded inert data';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'expectedVersion', p_expected_version,
    'ownerPartyId', p_owner_party_id,
    'vehicleId', p_vehicle_id,
    'enteredVehicleFacts', p_entered_vehicle_facts,
    'allowanceMinor', p_allowance_minor,
    'currencyCode', normalized_currency,
    'lienAmountMinor', p_lien_amount_minor,
    'payoffAmountMinor', p_payoff_amount_minor,
    'lenderPartyId', p_lender_party_id,
    'odometerValue', p_odometer_value,
    'odometerUnit', normalized_odometer_unit,
    'conditionKey', normalized_condition_key,
    'taxEligibilityInputs', safe_tax_inputs
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_create_trade_in',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_create_trade_in'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'tradeInId')::uuid,
      (existing_receipt.result ->> 'tradeInVersion')::bigint,
      existing_receipt.deal_id,
      existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey',
      true,
      existing_receipt.audit_event_id,
      existing_receipt.outbox_event_id;
    return;
  end if;
  locked_deal := app.lock_active_deal(
    p_workspace_id, p_deal_id, p_expected_version
  );
  if normalized_currency <> locked_deal.currency_code::text then
    raise exception using errcode = '23514', message = 'trade-in currency must match deal currency';
  end if;
  new_trade_in_id := pg_catalog.gen_random_uuid();
  insert into public.trade_ins (
    id, workspace_id, deal_id, owner_party_id, vehicle_id,
    entered_vehicle_facts, allowance_minor, lien_amount_minor,
    payoff_amount_minor, currency_code, lender_party_id, odometer_value,
    odometer_unit, condition_key, tax_eligibility_inputs,
    created_by, updated_by
  ) values (
    new_trade_in_id, p_workspace_id, p_deal_id, p_owner_party_id,
    p_vehicle_id, p_entered_vehicle_facts, exact_allowance, exact_lien,
    exact_payoff, normalized_currency, p_lender_party_id, p_odometer_value,
    normalized_odometer_unit, normalized_condition_key, safe_tax_inputs,
    actor_user_id, actor_user_id
  );
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.trade_in_created',
    p_entity_type => 'trade_in',
    p_entity_id => new_trade_in_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'deal_id', p_deal_id,
      'owner_party_id', p_owner_party_id,
      'vehicle_id', p_vehicle_id,
      'allowance_minor', p_allowance_minor,
      'lien_amount_minor', p_lien_amount_minor,
      'payoff_amount_minor', p_payoff_amount_minor,
      'currency_code', normalized_currency,
      'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.trade_in_created', p_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'tradeInId', new_trade_in_id,
      'tradeInVersion', 1
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'tradeInId', new_trade_in_id,
    'tradeInVersion', 1,
    'dealId', p_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_create_trade_in',
    normalized_idempotency_key, fingerprint, p_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    new_trade_in_id, 1::bigint, p_deal_id, updated_deal.version,
    updated_deal.status, updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_update_trade_in(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_expected_version bigint,
  p_trade_in_id uuid,
  p_expected_trade_in_version bigint,
  p_owner_party_id uuid,
  p_vehicle_id uuid,
  p_entered_vehicle_facts jsonb,
  p_allowance_minor text,
  p_currency_code text,
  p_lien_amount_minor text,
  p_payoff_amount_minor text,
  p_lender_party_id uuid,
  p_odometer_value bigint,
  p_odometer_unit text,
  p_condition_key text,
  p_tax_eligibility_inputs jsonb,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  trade_in_id uuid,
  trade_in_version bigint,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
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
  normalized_idempotency_key text;
  normalized_currency text;
  normalized_condition_key text;
  normalized_odometer_unit text;
  exact_allowance bigint;
  exact_lien bigint;
  exact_payoff bigint;
  safe_tax_inputs jsonb;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  target_deal_id uuid;
  locked_deal public.deals%rowtype;
  existing_trade_in public.trade_ins%rowtype;
  updated_trade_in public.trade_ins%rowtype;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_trade_in_version is null or p_expected_trade_in_version < 1 then
    raise exception using errcode = '22023', message = 'expected trade-in version must be positive';
  end if;
  normalized_currency := pg_catalog.upper(pg_catalog.btrim(coalesce(p_currency_code, '')));
  normalized_condition_key := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_condition_key, ''))), ''
  );
  normalized_odometer_unit := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_odometer_unit, ''))), ''
  );
  exact_allowance := app.parse_deal_minor_units(p_allowance_minor);
  exact_lien := app.parse_deal_minor_units(p_lien_amount_minor);
  exact_payoff := app.parse_deal_minor_units(p_payoff_amount_minor);
  if normalized_currency !~ '^[A-Z]{3}$'
    or exact_allowance < 0 or exact_lien < 0 or exact_payoff < 0 then
    raise exception using errcode = '22023', message = 'invalid exact trade-in money';
  end if;
  if normalized_condition_key is not null
    and normalized_condition_key !~ '^[a-z][a-z0-9_.-]{0,127}$' then
    raise exception using errcode = '22023', message = 'invalid trade-in condition key';
  end if;
  if (p_odometer_value is null) <> (normalized_odometer_unit is null)
    or (p_odometer_value is not null and p_odometer_value < 0)
    or (normalized_odometer_unit is not null
      and normalized_odometer_unit not in ('km', 'mi')) then
    raise exception using errcode = '22023', message = 'invalid trade-in odometer pair';
  end if;
  if p_vehicle_id is null and p_entered_vehicle_facts is null then
    raise exception using errcode = '23514', message = 'trade-in vehicle or entered facts are required';
  end if;
  if p_entered_vehicle_facts is not null and (
      pg_catalog.jsonb_typeof(p_entered_vehicle_facts) <> 'object'
      or not app.m3_inert_json_is_safe(p_entered_vehicle_facts)
    ) then
    raise exception using errcode = '23514', message = 'entered trade-in facts must be bounded inert data';
  end if;
  safe_tax_inputs := p_tax_eligibility_inputs;
  if safe_tax_inputs is null
    or pg_catalog.jsonb_typeof(safe_tax_inputs) <> 'object'
    or not app.m3_inert_json_is_safe(safe_tax_inputs) then
    raise exception using errcode = '23514', message = 'tax eligibility inputs must be bounded inert data';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'tradeInId', p_trade_in_id,
    'expectedVersion', p_expected_version,
    'expectedTradeInVersion', p_expected_trade_in_version,
    'ownerPartyId', p_owner_party_id,
    'vehicleId', p_vehicle_id,
    'enteredVehicleFacts', p_entered_vehicle_facts,
    'allowanceMinor', p_allowance_minor,
    'currencyCode', normalized_currency,
    'lienAmountMinor', p_lien_amount_minor,
    'payoffAmountMinor', p_payoff_amount_minor,
    'lenderPartyId', p_lender_party_id,
    'odometerValue', p_odometer_value,
    'odometerUnit', normalized_odometer_unit,
    'conditionKey', normalized_condition_key,
    'taxEligibilityInputs', safe_tax_inputs
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_update_trade_in',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_update_trade_in'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'tradeInId')::uuid,
      (existing_receipt.result ->> 'tradeInVersion')::bigint,
      existing_receipt.deal_id,
      existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  select trade_in.deal_id into target_deal_id
  from public.trade_ins trade_in
  where trade_in.workspace_id = p_workspace_id and trade_in.id = p_trade_in_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'trade-in not found';
  end if;
  locked_deal := app.lock_active_deal(
    p_workspace_id, target_deal_id, p_expected_version
  );
  select trade_in.* into existing_trade_in
  from public.trade_ins trade_in
  where trade_in.workspace_id = p_workspace_id
    and trade_in.id = p_trade_in_id
    and trade_in.deal_id = target_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'trade-in not found';
  end if;
  if existing_trade_in.version <> p_expected_trade_in_version then
    raise exception using errcode = '40001', message = 'stale trade-in version';
  end if;
  if existing_trade_in.status <> 'active' then
    raise exception using errcode = '55000', message = 'confirmed or cancelled trade-in cannot be changed';
  end if;
  if normalized_currency <> locked_deal.currency_code::text then
    raise exception using errcode = '23514', message = 'trade-in currency must match deal currency';
  end if;
  update public.trade_ins trade_in
  set owner_party_id = p_owner_party_id,
      vehicle_id = p_vehicle_id,
      entered_vehicle_facts = p_entered_vehicle_facts,
      allowance_minor = exact_allowance,
      lien_amount_minor = exact_lien,
      payoff_amount_minor = exact_payoff,
      currency_code = normalized_currency,
      lender_party_id = p_lender_party_id,
      odometer_value = p_odometer_value,
      odometer_unit = normalized_odometer_unit,
      condition_key = normalized_condition_key,
      tax_eligibility_inputs = safe_tax_inputs,
      version = trade_in.version + 1,
      updated_by = actor_user_id
  where trade_in.workspace_id = p_workspace_id and trade_in.id = p_trade_in_id
  returning * into updated_trade_in;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, target_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.trade_in_updated',
    p_entity_type => 'trade_in',
    p_entity_id => p_trade_in_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'owner_party_id', existing_trade_in.owner_party_id,
      'vehicle_id', existing_trade_in.vehicle_id,
      'allowance_minor', existing_trade_in.allowance_minor::text,
      'lien_amount_minor', existing_trade_in.lien_amount_minor::text,
      'payoff_amount_minor', existing_trade_in.payoff_amount_minor::text,
      'currency_code', existing_trade_in.currency_code::text,
      'version', existing_trade_in.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'owner_party_id', updated_trade_in.owner_party_id,
      'vehicle_id', updated_trade_in.vehicle_id,
      'allowance_minor', updated_trade_in.allowance_minor::text,
      'lien_amount_minor', updated_trade_in.lien_amount_minor::text,
      'payoff_amount_minor', updated_trade_in.payoff_amount_minor::text,
      'currency_code', updated_trade_in.currency_code::text,
      'version', updated_trade_in.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.trade_in_updated', target_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', target_deal_id,
      'tradeInId', p_trade_in_id,
      'tradeInVersion', updated_trade_in.version
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'tradeInId', p_trade_in_id,
    'tradeInVersion', updated_trade_in.version,
    'dealId', target_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_update_trade_in',
    normalized_idempotency_key, fingerprint, target_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    p_trade_in_id, updated_trade_in.version, target_deal_id,
    updated_deal.version, updated_deal.status,
    updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_confirm_trade_in_inventory(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_trade_in_id uuid,
  p_expected_trade_in_version bigint,
  p_expected_version bigint,
  p_inventory_unit_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  trade_in_id uuid,
  trade_in_version bigint,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
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
  normalized_idempotency_key text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  target_deal_id uuid;
  locked_deal public.deals%rowtype;
  existing_trade_in public.trade_ins%rowtype;
  updated_trade_in public.trade_ins%rowtype;
  inventory_vehicle_id uuid;
  inventory_currency text;
  inventory_status text;
  new_inventory_link_id uuid;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_deal_permission(p_workspace_id, 'deals.update');
  if not app.has_permission(p_workspace_id, 'inventory.read')
    or not app.has_permission(p_workspace_id, 'inventory.update') then
    raise exception using errcode = '42501', message = 'inventory read and update permissions are required for trade-in confirmation';
  end if;
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_trade_in_version is null or p_expected_trade_in_version < 1 then
    raise exception using errcode = '22023', message = 'expected trade-in version must be positive';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'tradeInId', p_trade_in_id,
    'expectedTradeInVersion', p_expected_trade_in_version,
    'expectedVersion', p_expected_version,
    'inventoryUnitId', p_inventory_unit_id
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_confirm_trade_in_inventory',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_confirm_trade_in_inventory'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'tradeInId')::uuid,
      (existing_receipt.result ->> 'tradeInVersion')::bigint,
      existing_receipt.deal_id,
      existing_receipt.aggregate_version,
      existing_receipt.result ->> 'canonicalStatus',
      existing_receipt.result ->> 'stateKey', true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  select trade_in.deal_id into target_deal_id
  from public.trade_ins trade_in
  where trade_in.workspace_id = p_workspace_id and trade_in.id = p_trade_in_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'trade-in not found';
  end if;
  locked_deal := app.lock_active_deal(
    p_workspace_id, target_deal_id, p_expected_version
  );
  select trade_in.* into existing_trade_in
  from public.trade_ins trade_in
  where trade_in.workspace_id = p_workspace_id
    and trade_in.id = p_trade_in_id
    and trade_in.deal_id = target_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'trade-in not found';
  end if;
  if existing_trade_in.version <> p_expected_trade_in_version then
    raise exception using errcode = '40001', message = 'stale trade-in version';
  end if;
  if existing_trade_in.status <> 'active'
    or existing_trade_in.resulting_inventory_unit_id is not null then
    raise exception using errcode = '55000', message = 'trade-in inventory was already confirmed';
  end if;
  select inventory.vehicle_id, inventory.currency_code::text, inventory.status
    into inventory_vehicle_id, inventory_currency, inventory_status
  from public.inventory_units inventory
  where inventory.workspace_id = p_workspace_id
    and inventory.id = p_inventory_unit_id
  for update;
  if not found or inventory_status not in ('draft', 'active') then
    raise exception using errcode = '23514', message = 'available independently created inventory unit is required';
  end if;
  if inventory_currency <> locked_deal.currency_code::text
    or (
      existing_trade_in.vehicle_id is not null
      and existing_trade_in.vehicle_id <> inventory_vehicle_id
    ) then
    raise exception using errcode = '23514', message = 'trade-in and resulting inventory unit do not match';
  end if;
  if exists (
    select 1 from public.deal_inventory_units inventory_link
    where inventory_link.workspace_id = p_workspace_id
      and inventory_link.inventory_unit_id = p_inventory_unit_id
      and inventory_link.role_key = 'trade_in'
      and inventory_link.status = 'active'
  ) then
    raise exception using errcode = '23505', message = 'inventory unit already has an active trade-in link';
  end if;
  new_inventory_link_id := pg_catalog.gen_random_uuid();
  insert into public.deal_inventory_units (
    id, workspace_id, deal_id, inventory_unit_id, role_key, status,
    amount_minor, currency_code, metadata, created_by
  ) values (
    new_inventory_link_id, p_workspace_id, target_deal_id,
    p_inventory_unit_id, 'trade_in', 'active',
    existing_trade_in.allowance_minor, existing_trade_in.currency_code,
    pg_catalog.jsonb_build_object(
      'source', 'trade_in_confirmation',
      'trade_in_id', p_trade_in_id
    ),
    actor_user_id
  );
  update public.trade_ins trade_in
  set resulting_inventory_unit_id = p_inventory_unit_id,
      status = 'confirmed',
      version = trade_in.version + 1,
      updated_by = actor_user_id
  where trade_in.workspace_id = p_workspace_id and trade_in.id = p_trade_in_id
  returning * into updated_trade_in;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, target_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.trade_in_inventory_confirmed',
    p_entity_type => 'trade_in',
    p_entity_id => p_trade_in_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', existing_trade_in.status,
      'version', existing_trade_in.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', updated_trade_in.status,
      'inventory_unit_id', p_inventory_unit_id,
      'inventory_link_id', new_inventory_link_id,
      'version', updated_trade_in.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.trade_in_inventory_confirmed', target_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', target_deal_id,
      'tradeInId', p_trade_in_id,
      'tradeInVersion', updated_trade_in.version,
      'inventoryUnitId', p_inventory_unit_id,
      'inventoryLinkId', new_inventory_link_id
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'tradeInId', p_trade_in_id,
    'tradeInVersion', updated_trade_in.version,
    'dealId', target_deal_id,
    'aggregateVersion', updated_deal.version,
    'canonicalStatus', updated_deal.status,
    'stateKey', updated_deal.workflow_state_key
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_confirm_trade_in_inventory',
    normalized_idempotency_key, fingerprint, target_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    p_trade_in_id, updated_trade_in.version, target_deal_id,
    updated_deal.version, updated_deal.status,
    updated_deal.workflow_state_key, false,
    new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_create_finance_application(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_applicant_party_id uuid,
  p_lender_party_id uuid,
  p_requested_amount_minor text,
  p_requested_currency_code text,
  p_external_reference text,
  p_lender_reported_annual_rate text,
  p_lender_reported_term_months integer,
  p_notes text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  finance_application_id uuid,
  status text,
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
  normalized_idempotency_key text;
  normalized_currency text;
  normalized_external_reference text;
  normalized_rate text;
  normalized_notes text;
  exact_requested_amount bigint;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  updated_deal public.deals%rowtype;
  new_finance_application_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_finance_permission(
    p_workspace_id, 'finance_applications.create', 'deals.update'
  );
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_currency := pg_catalog.upper(
    pg_catalog.btrim(coalesce(p_requested_currency_code, ''))
  );
  normalized_external_reference := case when p_external_reference is null
    then null else pg_catalog.btrim(p_external_reference) end;
  normalized_rate := case when p_lender_reported_annual_rate is null
    then null else pg_catalog.btrim(p_lender_reported_annual_rate) end;
  normalized_notes := case when p_notes is null
    then null else pg_catalog.btrim(p_notes) end;
  exact_requested_amount := app.parse_deal_minor_units(
    p_requested_amount_minor
  );
  if exact_requested_amount <= 0 or normalized_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'requested finance money must be positive and exact';
  end if;
  if normalized_external_reference is not null
      and pg_catalog.char_length(normalized_external_reference) > 500
    or normalized_notes is not null
      and pg_catalog.char_length(normalized_notes) > 4000 then
    raise exception using errcode = '22023', message = 'finance text exceeds its bounded length';
  end if;
  if normalized_rate is not null
    and normalized_rate !~ '^(?:0|[1-9][0-9]{0,2})(?:\.[0-9]{1,6})?$' then
    raise exception using errcode = '22023', message = 'invalid exact lender-reported annual rate';
  end if;
  if p_lender_reported_term_months is not null
    and p_lender_reported_term_months not between 1 and 1200 then
    raise exception using errcode = '22023', message = 'invalid lender-reported term';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'applicantPartyId', p_applicant_party_id,
    'lenderPartyId', p_lender_party_id,
    'requestedAmountMinor', p_requested_amount_minor,
    'requestedCurrencyCode', normalized_currency,
    'externalReference', normalized_external_reference,
    'lenderReportedAnnualRate', normalized_rate,
    'lenderReportedTermMonths', p_lender_reported_term_months,
    'notes', normalized_notes
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_create_finance_application',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_create_finance_application'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'financeApplicationId')::uuid,
      existing_receipt.result ->> 'status',
      existing_receipt.aggregate_version,
      true,
      existing_receipt.audit_event_id,
      existing_receipt.outbox_event_id;
    return;
  end if;
  locked_deal := app.lock_current_finance_deal(p_workspace_id, p_deal_id);
  if normalized_currency <> locked_deal.currency_code::text then
    raise exception using errcode = '23514', message = 'finance application currency must match deal currency';
  end if;
  new_finance_application_id := pg_catalog.gen_random_uuid();
  insert into public.finance_applications (
    id, workspace_id, deal_id, applicant_party_id, lender_party_id,
    requested_amount_minor, currency_code, external_reference,
    lender_reported_annual_rate_text, lender_reported_term_months,
    notes, created_by, updated_by
  ) values (
    new_finance_application_id, p_workspace_id, p_deal_id,
    p_applicant_party_id, p_lender_party_id, exact_requested_amount,
    normalized_currency, normalized_external_reference, normalized_rate,
    p_lender_reported_term_months, normalized_notes,
    actor_user_id, actor_user_id
  );
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.finance_application_created',
    p_entity_type => 'finance_application',
    p_entity_id => new_finance_application_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'deal_id', p_deal_id,
      'applicant_party_id', p_applicant_party_id,
      'lender_party_id', p_lender_party_id,
      'requested_amount_minor', p_requested_amount_minor,
      'currency_code', normalized_currency,
      'status', 'preparing',
      'version', 1
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.finance_application_created', p_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'financeApplicationId', new_finance_application_id,
      'status', 'preparing',
      'financeApplicationVersion', 1
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'financeApplicationId', new_finance_application_id,
    'status', 'preparing',
    'aggregateVersion', updated_deal.version
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_create_finance_application',
    normalized_idempotency_key, fingerprint, p_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    new_finance_application_id, 'preparing'::text,
    updated_deal.version, false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_update_finance_application(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_finance_application_id uuid,
  p_expected_version bigint,
  p_approved_amount_minor text,
  p_approved_currency_code text,
  p_lender_reported_annual_rate text,
  p_lender_reported_term_months integer,
  p_external_reference text,
  p_submitted_at timestamptz,
  p_approval_expires_at timestamptz,
  p_customer_accepted_at timestamptz,
  p_funded_at timestamptz,
  p_funding_reference text,
  p_notes text,
  p_update_approval_amount boolean,
  p_update_lender_rate boolean,
  p_update_lender_term boolean,
  p_update_external_reference boolean,
  p_update_submitted_at boolean,
  p_update_approval_expiry boolean,
  p_update_customer_acceptance boolean,
  p_update_funded_at boolean,
  p_update_funding_reference boolean,
  p_update_notes boolean,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  finance_application_id uuid,
  status text,
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
  normalized_idempotency_key text;
  normalized_approved_currency text;
  normalized_rate text;
  normalized_external_reference text;
  normalized_funding_reference text;
  normalized_notes text;
  exact_approved_amount bigint;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  target_deal_id uuid;
  locked_deal public.deals%rowtype;
  existing_application public.finance_applications%rowtype;
  updated_application public.finance_applications%rowtype;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_finance_permission(
    p_workspace_id, 'finance_applications.update', 'deals.update'
  );
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected finance application version must be positive';
  end if;
  if p_update_approval_amount is null
    or p_update_lender_rate is null
    or p_update_lender_term is null
    or p_update_external_reference is null
    or p_update_submitted_at is null
    or p_update_approval_expiry is null
    or p_update_customer_acceptance is null
    or p_update_funded_at is null
    or p_update_funding_reference is null
    or p_update_notes is null
    or not (
      p_update_approval_amount or p_update_lender_rate
      or p_update_lender_term or p_update_external_reference
      or p_update_submitted_at or p_update_approval_expiry
      or p_update_customer_acceptance or p_update_funded_at
      or p_update_funding_reference or p_update_notes
    ) then
    raise exception using errcode = '22023', message = 'at least one explicit finance field update is required';
  end if;
  normalized_approved_currency := case
    when p_approved_currency_code is null then null
    else pg_catalog.upper(pg_catalog.btrim(p_approved_currency_code))
  end;
  if p_update_approval_amount then
    if (p_approved_amount_minor is null)
      <> (normalized_approved_currency is null) then
      raise exception using errcode = '23514', message = 'approved amount and currency must be supplied together';
    end if;
    if p_approved_amount_minor is not null then
      exact_approved_amount := app.parse_deal_minor_units(
        p_approved_amount_minor
      );
      if exact_approved_amount <= 0
        or normalized_approved_currency !~ '^[A-Z]{3}$' then
        raise exception using errcode = '22023', message = 'approved finance money must be positive and exact';
      end if;
    end if;
  end if;
  normalized_rate := case when p_lender_reported_annual_rate is null
    then null else pg_catalog.btrim(p_lender_reported_annual_rate) end;
  if p_update_lender_rate and normalized_rate is not null
    and normalized_rate !~ '^(?:0|[1-9][0-9]{0,2})(?:\.[0-9]{1,6})?$' then
    raise exception using errcode = '22023', message = 'invalid exact lender-reported annual rate';
  end if;
  if p_update_lender_term and p_lender_reported_term_months is not null
    and p_lender_reported_term_months not between 1 and 1200 then
    raise exception using errcode = '22023', message = 'invalid lender-reported term';
  end if;
  normalized_external_reference := case when p_external_reference is null
    then null else pg_catalog.btrim(p_external_reference) end;
  normalized_funding_reference := case when p_funding_reference is null
    then null else pg_catalog.btrim(p_funding_reference) end;
  normalized_notes := case when p_notes is null
    then null else pg_catalog.btrim(p_notes) end;
  if p_update_external_reference
      and normalized_external_reference is not null
      and pg_catalog.char_length(normalized_external_reference) > 500
    or p_update_funding_reference
      and normalized_funding_reference is not null
      and pg_catalog.char_length(normalized_funding_reference) > 500
    or p_update_notes and normalized_notes is not null
      and pg_catalog.char_length(normalized_notes) > 4000 then
    raise exception using errcode = '22023', message = 'finance text exceeds its bounded length';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'financeApplicationId', p_finance_application_id,
    'expectedVersion', p_expected_version,
    'approvedAmountMinor', p_approved_amount_minor,
    'approvedCurrencyCode', normalized_approved_currency,
    'lenderReportedAnnualRate', normalized_rate,
    'lenderReportedTermMonths', p_lender_reported_term_months,
    'externalReference', normalized_external_reference,
    'submittedAt', p_submitted_at,
    'approvalExpiresAt', p_approval_expires_at,
    'customerAcceptedAt', p_customer_accepted_at,
    'fundedAt', p_funded_at,
    'fundingReference', normalized_funding_reference,
    'notes', normalized_notes,
    'updateApprovalAmount', p_update_approval_amount,
    'updateLenderRate', p_update_lender_rate,
    'updateLenderTerm', p_update_lender_term,
    'updateExternalReference', p_update_external_reference,
    'updateSubmittedAt', p_update_submitted_at,
    'updateApprovalExpiry', p_update_approval_expiry,
    'updateCustomerAcceptance', p_update_customer_acceptance,
    'updateFundedAt', p_update_funded_at,
    'updateFundingReference', p_update_funding_reference,
    'updateNotes', p_update_notes
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_update_finance_application',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_update_finance_application'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'financeApplicationId')::uuid,
      existing_receipt.result ->> 'status',
      existing_receipt.aggregate_version, true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  select application.deal_id into target_deal_id
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
  locked_deal := app.lock_current_finance_deal(
    p_workspace_id, target_deal_id
  );
  select application.* into existing_application
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id
    and application.deal_id = target_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
  if existing_application.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale finance application version';
  end if;
  if existing_application.status in (
    'declined', 'customer_declined', 'funded', 'cancelled', 'expired'
  ) then
    raise exception using errcode = '55000', message = 'terminal finance application cannot be changed';
  end if;
  if p_update_approval_amount and exact_approved_amount is not null
    and normalized_approved_currency <> locked_deal.currency_code::text then
    raise exception using errcode = '23514', message = 'approved amount currency must match deal currency';
  end if;
  update public.finance_applications application
  set approved_amount_minor = case when p_update_approval_amount
        then exact_approved_amount else application.approved_amount_minor end,
      lender_reported_annual_rate_text = case when p_update_lender_rate
        then normalized_rate else application.lender_reported_annual_rate_text end,
      lender_reported_term_months = case when p_update_lender_term
        then p_lender_reported_term_months else application.lender_reported_term_months end,
      external_reference = case when p_update_external_reference
        then normalized_external_reference else application.external_reference end,
      submitted_at = case when p_update_submitted_at
        then p_submitted_at else application.submitted_at end,
      approval_expires_at = case when p_update_approval_expiry
        then p_approval_expires_at else application.approval_expires_at end,
      customer_accepted_at = case when p_update_customer_acceptance
        then p_customer_accepted_at else application.customer_accepted_at end,
      funded_at = case when p_update_funded_at
        then p_funded_at else application.funded_at end,
      funding_reference = case when p_update_funding_reference
        then normalized_funding_reference else application.funding_reference end,
      notes = case when p_update_notes
        then normalized_notes else application.notes end,
      version = application.version + 1,
      updated_by = actor_user_id
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id
  returning * into updated_application;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, target_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.finance_application_updated',
    p_entity_type => 'finance_application',
    p_entity_id => p_finance_application_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', existing_application.status,
      'approved_amount_minor', existing_application.approved_amount_minor::text,
      'currency_code', existing_application.currency_code::text,
      'version', existing_application.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', updated_application.status,
      'approved_amount_minor', updated_application.approved_amount_minor::text,
      'currency_code', updated_application.currency_code::text,
      'version', updated_application.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.finance_application_updated', target_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', target_deal_id,
      'financeApplicationId', p_finance_application_id,
      'financeApplicationVersion', updated_application.version,
      'status', updated_application.status
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'financeApplicationId', p_finance_application_id,
    'status', updated_application.status,
    'aggregateVersion', updated_deal.version
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_update_finance_application',
    normalized_idempotency_key, fingerprint, target_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    p_finance_application_id, updated_application.status,
    updated_deal.version, false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_transition_finance_application(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_finance_application_id uuid,
  p_expected_version bigint,
  p_target_status text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  finance_application_id uuid,
  status text,
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
  normalized_idempotency_key text;
  normalized_target_status text;
  normalized_reason text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  target_deal_id uuid;
  locked_deal public.deals%rowtype;
  existing_application public.finance_applications%rowtype;
  updated_application public.finance_applications%rowtype;
  allowed_transition boolean;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_finance_permission(
    p_workspace_id, 'finance_applications.update', 'deals.update'
  );
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected finance application version must be positive';
  end if;
  normalized_target_status := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_target_status, ''))
  );
  if normalized_target_status not in (
    'preparing', 'submitted', 'additional_information_required',
    'conditionally_approved', 'approved', 'declined', 'customer_declined',
    'funded', 'cancelled', 'expired'
  ) then
    raise exception using errcode = '22023', message = 'invalid finance application status';
  end if;
  normalized_reason := nullif(
    pg_catalog.btrim(coalesce(p_reason, '')), ''
  );
  if normalized_reason is not null
    and pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using errcode = '22023', message = 'finance transition reason exceeds its bounded length';
  end if;
  if normalized_target_status in (
      'declined', 'customer_declined', 'cancelled'
    ) and normalized_reason is null then
    raise exception using errcode = '23514', message = 'finance transition reason is required';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'financeApplicationId', p_finance_application_id,
    'expectedVersion', p_expected_version,
    'targetStatus', normalized_target_status,
    'reason', normalized_reason
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_transition_finance_application',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_transition_finance_application'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'financeApplicationId')::uuid,
      existing_receipt.result ->> 'status',
      existing_receipt.aggregate_version, true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  select application.deal_id into target_deal_id
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
  locked_deal := app.lock_current_finance_deal(
    p_workspace_id, target_deal_id
  );
  select application.* into existing_application
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id
    and application.deal_id = target_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
  if existing_application.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale finance application version';
  end if;
  allowed_transition := case existing_application.status
    when 'preparing' then normalized_target_status in ('submitted', 'cancelled')
    when 'submitted' then normalized_target_status in (
      'additional_information_required', 'conditionally_approved',
      'approved', 'declined', 'cancelled'
    )
    when 'additional_information_required' then normalized_target_status in (
      'submitted', 'conditionally_approved', 'approved', 'declined',
      'cancelled'
    )
    when 'conditionally_approved' then normalized_target_status in (
      'approved', 'funded', 'customer_declined', 'expired', 'cancelled'
    )
    when 'approved' then normalized_target_status in (
      'funded', 'customer_declined', 'expired', 'cancelled'
    )
    else false
  end;
  if not allowed_transition then
    raise exception using errcode = '23514', message = 'finance application transition is not allowed';
  end if;
  if normalized_target_status in (
      'conditionally_approved', 'approved', 'funded'
    ) and existing_application.approved_amount_minor is null then
    raise exception using errcode = '23514', message = 'approved amount is required for lender approval or funding';
  end if;
  if normalized_target_status in ('approved', 'funded') and exists (
    select 1
    from public.finance_application_conditions condition
    where condition.workspace_id = p_workspace_id
      and condition.finance_application_id = p_finance_application_id
      and condition.status = 'active'
      and condition.required
      and condition.satisfied_at is null
  ) then
    raise exception using errcode = '23514', message = 'all required finance conditions must be satisfied';
  end if;
  if normalized_target_status = 'approved'
    and existing_application.approval_expires_at is not null
    and existing_application.approval_expires_at
      <= pg_catalog.statement_timestamp() then
    raise exception using errcode = '23514', message = 'expired lender approval cannot be recorded as approved';
  end if;
  if normalized_target_status = 'funded'
    and existing_application.customer_accepted_at is null then
    raise exception using errcode = '23514', message = 'customer acceptance is required before funding';
  end if;
  if normalized_target_status = 'expired' and (
      existing_application.approval_expires_at is null
      or existing_application.approval_expires_at
        > pg_catalog.statement_timestamp()
    ) then
    raise exception using errcode = '23514', message = 'finance approval has not expired';
  end if;
  update public.finance_applications application
  set status = normalized_target_status,
      status_reason = normalized_reason,
      submitted_at = case
        when normalized_target_status = 'submitted'
          then coalesce(application.submitted_at, pg_catalog.statement_timestamp())
        else application.submitted_at end,
      decision_at = case
        when normalized_target_status in (
          'conditionally_approved', 'approved', 'declined'
        ) then pg_catalog.statement_timestamp()
        else application.decision_at end,
      funded_at = case
        when normalized_target_status = 'funded'
          then coalesce(application.funded_at, pg_catalog.statement_timestamp())
        else application.funded_at end,
      version = application.version + 1,
      updated_by = actor_user_id
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id
  returning * into updated_application;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, target_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.finance_application_transitioned',
    p_entity_type => 'finance_application',
    p_entity_id => p_finance_application_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', existing_application.status,
      'version', existing_application.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', updated_application.status,
      'version', updated_application.version
    ),
    p_reason => normalized_reason,
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.finance_application_transitioned', target_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', target_deal_id,
      'financeApplicationId', p_finance_application_id,
      'financeApplicationVersion', updated_application.version,
      'fromStatus', existing_application.status,
      'toStatus', updated_application.status
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'financeApplicationId', p_finance_application_id,
    'status', updated_application.status,
    'aggregateVersion', updated_deal.version
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_transition_finance_application',
    normalized_idempotency_key, fingerprint, target_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    p_finance_application_id, updated_application.status,
    updated_deal.version, false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_add_finance_condition(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_finance_application_id uuid,
  p_expected_version bigint,
  p_condition_key text,
  p_description text,
  p_required boolean,
  p_satisfied_at timestamptz,
  p_due_at timestamptz,
  p_supporting_file_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  condition_id uuid,
  finance_application_id uuid,
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
  normalized_idempotency_key text;
  normalized_condition_key text;
  normalized_description text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  target_deal_id uuid;
  locked_deal public.deals%rowtype;
  existing_application public.finance_applications%rowtype;
  updated_application public.finance_applications%rowtype;
  updated_deal public.deals%rowtype;
  new_condition_id uuid;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_finance_permission(
    p_workspace_id, 'finance_applications.update', 'deals.update'
  );
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'expected finance application version must be positive';
  end if;
  normalized_condition_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_condition_key, ''))
  );
  normalized_description := pg_catalog.btrim(coalesce(p_description, ''));
  if normalized_condition_key !~ '^[a-z][a-z0-9_.-]{0,127}$'
    or normalized_description = ''
    or pg_catalog.char_length(normalized_description) > 2000
    or p_required is null then
    raise exception using errcode = '22023', message = 'invalid bounded finance condition';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'financeApplicationId', p_finance_application_id,
    'expectedVersion', p_expected_version,
    'conditionKey', normalized_condition_key,
    'description', normalized_description,
    'required', p_required,
    'satisfiedAt', p_satisfied_at,
    'dueAt', p_due_at,
    'supportingFileId', p_supporting_file_id
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_add_finance_condition',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_add_finance_condition'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'conditionId')::uuid,
      (existing_receipt.result ->> 'financeApplicationId')::uuid,
      existing_receipt.aggregate_version, true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  select application.deal_id into target_deal_id
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
  locked_deal := app.lock_current_finance_deal(
    p_workspace_id, target_deal_id
  );
  select application.* into existing_application
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id
    and application.deal_id = target_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
  if existing_application.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale finance application version';
  end if;
  if existing_application.status not in (
    'preparing', 'submitted', 'additional_information_required',
    'conditionally_approved'
  ) then
    raise exception using errcode = '55000', message = 'finance conditions cannot be appended after approval or termination';
  end if;
  if p_supporting_file_id is not null
    and not app.has_permission(p_workspace_id, 'files.read_restricted') then
    raise exception using errcode = '42501', message = 'restricted-file read permission is required for a finance condition attachment';
  end if;
  if (
    select pg_catalog.count(*)
    from public.finance_application_conditions condition
    where condition.workspace_id = p_workspace_id
      and condition.finance_application_id = p_finance_application_id
      and condition.status = 'active'
  ) >= 100 then
    raise exception using errcode = '54000', message = 'finance condition limit reached';
  end if;
  new_condition_id := pg_catalog.gen_random_uuid();
  insert into public.finance_application_conditions (
    id, workspace_id, finance_application_id, logical_condition_id,
    condition_key,
    description, required, satisfied_at, due_at, supporting_file_id,
    version, status, created_by
  ) values (
    new_condition_id, p_workspace_id, p_finance_application_id,
    new_condition_id, normalized_condition_key, normalized_description,
    p_required, p_satisfied_at, p_due_at, p_supporting_file_id,
    1, 'active', actor_user_id
  );
  update public.finance_applications application
  set version = application.version + 1,
      updated_by = actor_user_id
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id
  returning * into updated_application;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, target_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.finance_condition_added',
    p_entity_type => 'finance_application',
    p_entity_id => p_finance_application_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'condition_id', new_condition_id,
      'condition_key', normalized_condition_key,
      'required', p_required,
      'satisfied', p_satisfied_at is not null,
      'due_at', p_due_at,
      'supporting_file_id', p_supporting_file_id,
      'condition_version', 1,
      'version', updated_application.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.finance_condition_added', target_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', target_deal_id,
      'financeApplicationId', p_finance_application_id,
      'financeApplicationVersion', updated_application.version,
      'conditionId', new_condition_id,
      'conditionKey', normalized_condition_key,
      'conditionVersion', 1,
      'required', p_required,
      'satisfied', p_satisfied_at is not null,
      'dueAt', p_due_at,
      'supportingFileId', p_supporting_file_id
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'conditionId', new_condition_id,
    'financeApplicationId', p_finance_application_id,
    'aggregateVersion', updated_deal.version
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_add_finance_condition',
    normalized_idempotency_key, fingerprint, target_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    new_condition_id, p_finance_application_id, updated_deal.version,
    false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_update_finance_condition(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_finance_application_id uuid,
  p_condition_id uuid,
  p_expected_version bigint,
  p_expected_condition_version bigint,
  p_description text,
  p_required boolean,
  p_satisfied_at timestamptz,
  p_due_at timestamptz,
  p_supporting_file_id uuid,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  condition_id uuid,
  finance_application_id uuid,
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
  normalized_idempotency_key text;
  normalized_description text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  target_deal_id uuid;
  locked_deal public.deals%rowtype;
  existing_application public.finance_applications%rowtype;
  updated_application public.finance_applications%rowtype;
  existing_condition public.finance_application_conditions%rowtype;
  new_condition_id uuid;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_finance_permission(
    p_workspace_id, 'finance_applications.update', 'deals.update'
  );
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_version is null or p_expected_version < 1
    or p_expected_condition_version is null
    or p_expected_condition_version < 1 then
    raise exception using errcode = '22023', message = 'expected finance and condition versions must be positive';
  end if;
  normalized_description := pg_catalog.btrim(coalesce(p_description, ''));
  if normalized_description = ''
    or pg_catalog.char_length(normalized_description) > 2000
    or p_required is null then
    raise exception using errcode = '22023', message = 'invalid bounded finance condition replacement';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'financeApplicationId', p_finance_application_id,
    'conditionId', p_condition_id,
    'expectedVersion', p_expected_version,
    'expectedConditionVersion', p_expected_condition_version,
    'description', normalized_description,
    'required', p_required,
    'satisfiedAt', p_satisfied_at,
    'dueAt', p_due_at,
    'supportingFileId', p_supporting_file_id
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_update_finance_condition',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_update_finance_condition'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using errcode = '23505', message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'conditionId')::uuid,
      (existing_receipt.result ->> 'financeApplicationId')::uuid,
      existing_receipt.aggregate_version, true,
      existing_receipt.audit_event_id, existing_receipt.outbox_event_id;
    return;
  end if;
  select application.deal_id into target_deal_id
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
  locked_deal := app.lock_current_finance_deal(
    p_workspace_id, target_deal_id
  );
  select application.* into existing_application
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id
    and application.deal_id = target_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
  if existing_application.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale finance application version';
  end if;
  if existing_application.status not in (
    'preparing', 'submitted', 'additional_information_required',
    'conditionally_approved'
  ) then
    raise exception using errcode = '55000', message = 'finance conditions cannot be replaced after approval or termination';
  end if;
  select condition.* into existing_condition
  from public.finance_application_conditions condition
  where condition.workspace_id = p_workspace_id
    and condition.finance_application_id = p_finance_application_id
    and condition.id = p_condition_id
    and condition.status = 'active'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'active finance condition not found';
  end if;
  if existing_condition.version <> p_expected_condition_version then
    raise exception using errcode = '40001', message = 'stale finance condition version';
  end if;
  if p_supporting_file_id is not null
    and not app.has_permission(p_workspace_id, 'files.read_restricted') then
    raise exception using errcode = '42501', message = 'restricted-file read permission is required for a finance condition attachment';
  end if;
  update public.finance_application_conditions condition
  set status = 'replaced',
      replaced_at = pg_catalog.statement_timestamp()
  where condition.workspace_id = p_workspace_id
    and condition.id = p_condition_id;
  new_condition_id := pg_catalog.gen_random_uuid();
  insert into public.finance_application_conditions (
    id, workspace_id, finance_application_id, logical_condition_id,
    condition_key, description, required, satisfied_at, due_at,
    supporting_file_id, version, status, replaces_condition_id,
    created_by
  ) values (
    new_condition_id, p_workspace_id, p_finance_application_id,
    existing_condition.logical_condition_id, existing_condition.condition_key,
    normalized_description, p_required, p_satisfied_at, p_due_at,
    p_supporting_file_id, existing_condition.version + 1, 'active',
    p_condition_id, actor_user_id
  );
  update public.finance_applications application
  set version = application.version + 1,
      updated_by = actor_user_id
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id
  returning * into updated_application;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, target_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.finance_condition_updated',
    p_entity_type => 'finance_application',
    p_entity_id => p_finance_application_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'condition_id', existing_condition.id,
      'logical_condition_id', existing_condition.logical_condition_id,
      'condition_key', existing_condition.condition_key,
      'required', existing_condition.required,
      'satisfied', existing_condition.satisfied_at is not null,
      'condition_version', existing_condition.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'condition_id', new_condition_id,
      'logical_condition_id', existing_condition.logical_condition_id,
      'condition_key', existing_condition.condition_key,
      'required', p_required,
      'satisfied', p_satisfied_at is not null,
      'due_at', p_due_at,
      'supporting_file_id', p_supporting_file_id,
      'condition_version', existing_condition.version + 1,
      'version', updated_application.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.finance_condition_updated', target_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', target_deal_id,
      'financeApplicationId', p_finance_application_id,
      'financeApplicationVersion', updated_application.version,
      'conditionId', new_condition_id,
      'logicalConditionId', existing_condition.logical_condition_id,
      'conditionKey', existing_condition.condition_key,
      'conditionVersion', existing_condition.version + 1,
      'replacesConditionId', p_condition_id,
      'required', p_required,
      'satisfied', p_satisfied_at is not null,
      'dueAt', p_due_at,
      'supportingFileId', p_supporting_file_id
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'conditionId', new_condition_id,
    'financeApplicationId', p_finance_application_id,
    'aggregateVersion', updated_deal.version
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_update_finance_condition',
    normalized_idempotency_key, fingerprint, target_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    new_condition_id, p_finance_application_id, updated_deal.version,
    false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_list_finance_applications(
  p_workspace_id uuid,
  p_deal_id uuid default null
)
returns table (
  finance_application_id uuid,
  deal_id uuid,
  applicant_party_id uuid,
  lender_party_id uuid,
  requested_amount_minor text,
  approved_amount_minor text,
  currency_code text,
  status text,
  version bigint,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_finance_permission(
    p_workspace_id, 'finance_applications.read', 'deals.read'
  );
  if p_deal_id is not null and not exists (
    select 1 from public.deals deal
    where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  ) then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  return query
  select
    application.id,
    application.deal_id,
    application.applicant_party_id,
    application.lender_party_id,
    application.requested_amount_minor::text,
    application.approved_amount_minor::text,
    application.currency_code::text,
    application.status,
    application.version,
    application.updated_at
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and (p_deal_id is null or application.deal_id = p_deal_id)
  order by application.updated_at desc, application.id desc
  limit 500;
end;
$$;

create function app.m3_get_finance_application(
  p_workspace_id uuid,
  p_finance_application_id uuid
)
returns table (
  finance_application_id uuid,
  deal_id uuid,
  applicant_party_id uuid,
  lender_party_id uuid,
  requested_amount_minor text,
  approved_amount_minor text,
  currency_code text,
  external_reference text,
  lender_reported_annual_rate text,
  lender_reported_term_months integer,
  notes text,
  submitted_at timestamptz,
  decision_at timestamptz,
  approval_expires_at timestamptz,
  customer_accepted_at timestamptz,
  funded_at timestamptz,
  funding_reference text,
  status text,
  status_reason text,
  conditions jsonb,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_finance_permission(
    p_workspace_id, 'finance_applications.read', 'deals.read'
  );
  return query
  select
    application.id,
    application.deal_id,
    application.applicant_party_id,
    application.lender_party_id,
    application.requested_amount_minor::text,
    application.approved_amount_minor::text,
    application.currency_code::text,
    application.external_reference,
    application.lender_reported_annual_rate_text,
    application.lender_reported_term_months,
    application.notes,
    application.submitted_at,
    application.decision_at,
    application.approval_expires_at,
    application.customer_accepted_at,
    application.funded_at,
    application.funding_reference,
    application.status,
    application.status_reason,
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'condition_id', bounded_condition.id,
          'logical_condition_id', bounded_condition.logical_condition_id,
          'condition_key', bounded_condition.condition_key,
          'description', bounded_condition.description,
          'required', bounded_condition.required,
          'satisfied_at', bounded_condition.satisfied_at,
          'due_at', bounded_condition.due_at,
          'supporting_file_id', case
            when app.has_permission(
              application.workspace_id, 'files.read_restricted'
            ) then bounded_condition.supporting_file_id
            else null
          end,
          'version', bounded_condition.version,
          'status', bounded_condition.status,
          'replaces_condition_id', bounded_condition.replaces_condition_id,
          'created_at', bounded_condition.created_at
        ) order by
          bounded_condition.required desc,
          bounded_condition.created_at,
          bounded_condition.id
      )
      from (
        select condition.*
        from public.finance_application_conditions condition
        where condition.workspace_id = application.workspace_id
          and condition.finance_application_id = application.id
          and condition.status = 'active'
        order by condition.required desc, condition.created_at, condition.id
        limit 100
      ) bounded_condition
    ), '[]'::jsonb),
    application.version,
    application.created_at,
    application.updated_at
  from public.finance_applications application
  where application.workspace_id = p_workspace_id
    and application.id = p_finance_application_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'finance application not found';
  end if;
end;
$$;

alter table public.trade_ins enable row level security;
alter table public.trade_ins force row level security;
alter table public.finance_applications enable row level security;
alter table public.finance_applications force row level security;
alter table public.finance_application_conditions enable row level security;
alter table public.finance_application_conditions force row level security;

create policy trade_ins_select
on public.trade_ins
for select to authenticated
using (app.can_read_deal_workspace(workspace_id));

create policy finance_applications_select
on public.finance_applications
for select to authenticated
using (app.can_read_finance_workspace(workspace_id));

create policy finance_application_conditions_select
on public.finance_application_conditions
for select to authenticated
using (app.can_read_finance_workspace(workspace_id));

revoke all on table
  public.trade_ins,
  public.finance_applications,
  public.finance_application_conditions
from public, anon, authenticated, service_role;

grant select on
  public.trade_ins,
  public.finance_applications
to authenticated, service_role;
grant select on public.finance_application_conditions to service_role;
grant select (
  id,
  workspace_id,
  finance_application_id,
  logical_condition_id,
  condition_key,
  description,
  required,
  satisfied_at,
  due_at,
  version,
  status,
  replaces_condition_id,
  replaced_at,
  created_by,
  created_at
) on public.finance_application_conditions to authenticated;

revoke all on function app.m3_inert_json_is_safe(jsonb, integer)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_inert_json_is_safe(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function app.assert_trade_in_links()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_finance_application_links()
  from public, anon, authenticated, service_role;
revoke all on function app.assert_finance_condition_attachment()
  from public, anon, authenticated, service_role;
revoke all on function app.protect_finance_condition_history()
  from public, anon, authenticated, service_role;
revoke all on function app.require_finance_permission(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function app.can_read_finance_workspace(uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.lock_current_finance_deal(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.deal_external_finance_approved(uuid, uuid)
  from public, anon, authenticated, service_role;

revoke all on function app.m3_list_trade_ins(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_create_trade_in(
  uuid, text, uuid, bigint, uuid, uuid, jsonb, text, text, text, text,
  uuid, bigint, text, text, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_update_trade_in(
  uuid, text, bigint, uuid, bigint, uuid, uuid, jsonb, text, text, text,
  text, uuid, bigint, text, text, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_confirm_trade_in_inventory(
  uuid, text, uuid, bigint, bigint, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_create_finance_application(
  uuid, text, uuid, uuid, uuid, text, text, text, text, integer, text,
  text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_update_finance_application(
  uuid, text, uuid, bigint, text, text, text, integer, text,
  timestamptz, timestamptz, timestamptz, timestamptz, text, text,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean,
  boolean, boolean, boolean, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_transition_finance_application(
  uuid, text, uuid, bigint, text, text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_add_finance_condition(
  uuid, text, uuid, bigint, text, text, boolean, timestamptz,
  timestamptz, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_update_finance_condition(
  uuid, text, uuid, uuid, bigint, bigint, text, boolean,
  timestamptz, timestamptz, uuid, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_list_finance_applications(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_get_finance_application(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Authenticated SELECT policies invoke this deliberately narrow boolean helper.
-- Keep every mutation/helper boundary private while allowing the policy itself
-- to execute for the role named in the policy.
grant execute on function app.can_read_finance_workspace(uuid)
  to authenticated;

grant execute on function app.m3_list_trade_ins(uuid, uuid)
  to authenticated;
grant execute on function app.m3_create_trade_in(
  uuid, text, uuid, bigint, uuid, uuid, jsonb, text, text, text, text,
  uuid, bigint, text, text, jsonb, text, uuid
) to authenticated;
grant execute on function app.m3_update_trade_in(
  uuid, text, bigint, uuid, bigint, uuid, uuid, jsonb, text, text, text,
  text, uuid, bigint, text, text, jsonb, text, uuid
) to authenticated;
grant execute on function app.m3_confirm_trade_in_inventory(
  uuid, text, uuid, bigint, bigint, uuid, text, uuid
) to authenticated;
grant execute on function app.m3_create_finance_application(
  uuid, text, uuid, uuid, uuid, text, text, text, text, integer, text,
  text, uuid
) to authenticated;
grant execute on function app.m3_update_finance_application(
  uuid, text, uuid, bigint, text, text, text, integer, text,
  timestamptz, timestamptz, timestamptz, timestamptz, text, text,
  boolean, boolean, boolean, boolean, boolean, boolean, boolean,
  boolean, boolean, boolean, text, uuid
) to authenticated;
grant execute on function app.m3_transition_finance_application(
  uuid, text, uuid, bigint, text, text, text, uuid
) to authenticated;
grant execute on function app.m3_add_finance_condition(
  uuid, text, uuid, bigint, text, text, boolean, timestamptz,
  timestamptz, uuid, text, uuid
) to authenticated;
grant execute on function app.m3_update_finance_condition(
  uuid, text, uuid, uuid, bigint, bigint, text, boolean,
  timestamptz, timestamptz, uuid, text, uuid
) to authenticated;
grant execute on function app.m3_list_finance_applications(uuid, uuid)
  to authenticated;
grant execute on function app.m3_get_finance_application(uuid, uuid)
  to authenticated;

comment on table public.trade_ins is
  'Workspace-owned trade-in facts with exact same-currency money, bounded inert tax inputs, optimistic versions, and explicit links to independently created inventory.';
comment on table public.finance_applications is
  'External-lender-reported application state only. Exact requested/approved money and decimal rate are stored without credit origination, provider calls, schedules, or servicing calculations.';
comment on table public.finance_application_conditions is
  'Immutable versioned lender condition evidence with optional due date and same-deal preserved legal-original attachment; only active versions are projected and drive approval.';
comment on column public.trade_ins.tax_eligibility_inputs is
  'Inert versioned inputs only; this column never executes or calculates tax eligibility.';
comment on column public.finance_applications.lender_reported_annual_rate_text is
  'Canonical exact lender-reported decimal text. It is not used to calculate principal, interest, APR payments, or a schedule.';
comment on function app.m3_get_finance_application(uuid, uuid) is
  'Permission- and entitlement-gated safe finance detail with at most 100 active condition versions, restricted-file masking, and no credentials or provider payloads.';

-- Compatibility and rollback: all new entity references use composite
-- workspace foreign keys and existing deal aggregate/outbox contracts. A
-- rollback must first retire callers and preserve/export audit, receipt,
-- finance, condition, trade-in, and inventory-link history; hard deletion is
-- intentionally unsupported.
