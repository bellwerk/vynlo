-- VYN-PAY-001, VYN-DEAL-001, VYN-AUTH-002, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001
-- M3-PAY-AC-001..003 / T-PAY-001..003
-- Append-only, workspace-owned one-time money events. Normal event keys come
-- from the deal's pinned immutable configuration. This ledger does not create
-- recurring schedules, allocate principal/interest, or call payment providers.

create table public.payment_transactions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete restrict,
  deal_id uuid not null,
  transaction_type text not null check (
    transaction_type ~ '^[a-z][a-z0-9_.-]{0,127}$'
  ),
  amount_minor bigint not null check (amount_minor <> 0),
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
  method_key text check (
    method_key is null or method_key ~ '^[a-z][a-z0-9_.-]{0,127}$'
  ),
  reference text check (
    reference is null or (
      reference = pg_catalog.btrim(reference)
      and reference <> ''
      and pg_catalog.char_length(reference) <= 500
    )
  ),
  occurred_at timestamptz not null,
  settled_at timestamptz,
  proof_file_id uuid,
  notes text check (
    notes is null or (
      notes = pg_catalog.btrim(notes)
      and notes <> ''
      and pg_catalog.char_length(notes) <= 4000
    )
  ),
  correction_reason text check (
    correction_reason is null or (
      correction_reason = pg_catalog.btrim(correction_reason)
      and correction_reason <> ''
      and pg_catalog.char_length(correction_reason) <= 2000
    )
  ),
  corrects_transaction_id uuid,
  status text not null default 'recorded' check (
    status in ('recorded', 'settled', 'cancelled')
  ),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  unique (workspace_id, id),
  foreign key (workspace_id, deal_id)
    references public.deals (workspace_id, id) on delete restrict,
  foreign key (workspace_id, proof_file_id)
    references public.media_files (workspace_id, id) on delete restrict,
  foreign key (workspace_id, corrects_transaction_id)
    references public.payment_transactions (workspace_id, id) on delete restrict,
  check (settled_at is null or settled_at >= occurred_at),
  check (
    (
      corrects_transaction_id is null
      and transaction_type not in ('refund', 'reversal')
      and amount_minor > 0
      and method_key is not null
      and correction_reason is null
      and (
        (status = 'recorded' and settled_at is null)
        or (status = 'settled' and settled_at is not null)
        or (status = 'cancelled' and settled_at is null)
      )
    )
    or (
      corrects_transaction_id is not null
      and transaction_type in ('refund', 'reversal')
      and amount_minor < 0
      and method_key is null
      and reference is null
      and proof_file_id is null
      and notes is null
      and correction_reason is not null
      and status = 'settled'
      and settled_at is not null
    )
  )
);

create index payment_transactions_deal_idx
  on public.payment_transactions (
    workspace_id, deal_id, occurred_at desc, created_at desc, id
  );
create index payment_transactions_correction_idx
  on public.payment_transactions (
    workspace_id, corrects_transaction_id, created_at, id
  ) where corrects_transaction_id is not null;

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
    'm3_update_finance_condition',
    'm3_record_payment_transaction', 'm3_settle_payment_transaction',
    'm3_correct_payment_transaction'
  ));

create function app.assert_payment_transaction_links()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  deal_currency text;
  deal_lifecycle text;
  money_mode text;
  allowed_event_types jsonb;
  original_transaction public.payment_transactions%rowtype;
  corrected_amount numeric;
  remaining_amount numeric;
begin
  select
    deal.currency_code::text,
    deal.lifecycle_status,
    coalesce(version.behavior_flags ->> 'money_mode', 'none'),
    coalesce(version.behavior_flags -> 'one_time_event_types', '[]'::jsonb)
  into deal_currency, deal_lifecycle, money_mode, allowed_event_types
  from public.deals deal
  join public.deal_type_versions version
    on version.workspace_id = deal.workspace_id
   and version.id = deal.deal_type_version_id
  where deal.workspace_id = new.workspace_id and deal.id = new.deal_id;
  if not found or money_mode <> 'one_time' then
    raise exception using
      errcode = '23514',
      message = 'configured one-time-money deal is required';
  end if;
  if new.currency_code::text <> deal_currency then
    raise exception using
      errcode = '23514',
      message = 'payment transaction currency must match deal currency';
  end if;

  if new.corrects_transaction_id is null then
    if deal_lifecycle <> 'active' then
      raise exception using
        errcode = '55000',
        message = 'new payment transactions require an active deal';
    end if;
    if new.transaction_type in ('refund', 'reversal')
      or not exists (
        select 1
        from pg_catalog.jsonb_array_elements_text(allowed_event_types) entry(value)
        where entry.value = new.transaction_type
      ) then
      raise exception using
        errcode = '23514',
        message = 'payment transaction type is not enabled by the pinned deal type';
    end if;
  else
    select original.* into original_transaction
    from public.payment_transactions original
    where original.workspace_id = new.workspace_id
      and original.id = new.corrects_transaction_id
    for update;
    if not found
      or original_transaction.deal_id <> new.deal_id
      or original_transaction.currency_code <> new.currency_code
      or original_transaction.amount_minor <= 0
      or original_transaction.corrects_transaction_id is not null
      or original_transaction.transaction_type in ('refund', 'reversal')
      or original_transaction.status <> 'settled' then
      raise exception using
        errcode = '23514',
        message = 'correction must link a settled original payment in the same deal';
    end if;
    perform correction.id
    from public.payment_transactions correction
    where correction.workspace_id = new.workspace_id
      and correction.corrects_transaction_id = new.corrects_transaction_id
    order by correction.id
    for update;
    select coalesce(pg_catalog.sum(-correction.amount_minor), 0)
      into corrected_amount
    from public.payment_transactions correction
    where correction.workspace_id = new.workspace_id
      and correction.corrects_transaction_id = new.corrects_transaction_id;
    remaining_amount := original_transaction.amount_minor - corrected_amount;
    if remaining_amount <= 0 or -new.amount_minor > remaining_amount then
      raise exception using
        errcode = '23514',
        message = 'payment correction exceeds remaining settled amount';
    end if;
    if new.transaction_type = 'reversal'
      and -new.amount_minor <> remaining_amount then
      raise exception using
        errcode = '23514',
        message = 'payment reversal must equal the exact remaining amount';
    end if;
  end if;

  if new.proof_file_id is not null and not exists (
    select 1
    from public.media_files file
    join public.media_assets asset
      on asset.workspace_id = file.workspace_id
     and asset.id = file.media_id
    where file.workspace_id = new.workspace_id
      and file.id = new.proof_file_id
      and file.file_class = 'legal_document_original'
      and file.variant = 'legal_original'
      and file.retention_policy = 'preserve_original'
      and file.deleted_at is null
      and asset.media_kind = 'legal_document'
      and asset.status = 'ready'
      and asset.owner_entity_type = 'deal'
      and asset.owner_entity_id = new.deal_id
      and asset.deal_id = new.deal_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'payment proof must be a ready preserved legal original owned by the same deal';
  end if;
  return new;
end;
$$;

create trigger payment_transactions_validate_links
before insert on public.payment_transactions
for each row execute function app.assert_payment_transaction_links();

create function app.protect_payment_transaction_history()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '55000',
      message = 'payment transaction history is append-only';
  end if;
  if old.corrects_transaction_id is null
    and old.status = 'recorded'
    and new.status = 'settled'
    and new.settled_at is not null
    and new.version = old.version + 1
    and pg_catalog.to_jsonb(new) - array[
      'status', 'settled_at', 'version', 'updated_by', 'updated_at'
    ]::text[] = pg_catalog.to_jsonb(old) - array[
      'status', 'settled_at', 'version', 'updated_by', 'updated_at'
    ]::text[] then
    return new;
  end if;
  raise exception using
    errcode = '55000',
    message = 'payment transactions are immutable except controlled settlement';
end;
$$;

create trigger payment_transactions_protect_history
before update or delete on public.payment_transactions
for each row execute function app.protect_payment_transaction_history();
create trigger payment_transactions_updated_at
before update on public.payment_transactions
for each row execute function app.set_updated_at();

create function app.require_payment_permission(
  p_workspace_id uuid,
  p_payment_permission_key text,
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
      p_workspace_id, 'one_time_payments', pg_catalog.statement_timestamp()
    ) or not app.has_permission(p_workspace_id, p_payment_permission_key) then
    raise exception using
      errcode = '42501',
      message = 'active one-time-payments entitlement and permission are required';
  end if;
  return actor_user_id;
end;
$$;

create function app.can_read_payment_workspace(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.can_read_deal_workspace(p_workspace_id)
    and app.is_feature_entitled(
      p_workspace_id, 'one_time_payments', pg_catalog.statement_timestamp()
    )
    and app.has_permission(p_workspace_id, 'payments.read');
$$;

create function app.lock_one_time_payment_deal(
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
  money_mode text;
begin
  select deal.* into locked_deal
  from public.deals deal
  where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  select coalesce(version.behavior_flags ->> 'money_mode', 'none')
    into money_mode
  from public.deal_type_versions version
  where version.workspace_id = p_workspace_id
    and version.id = locked_deal.deal_type_version_id;
  if money_mode <> 'one_time' then
    raise exception using
      errcode = '23514',
      message = 'deal type does not allow one-time money events';
  end if;
  return locked_deal;
end;
$$;

create function app.m3_list_payment_transactions(
  p_workspace_id uuid,
  p_deal_id uuid
)
returns table (
  payment_transaction_id uuid,
  deal_id uuid,
  transaction_type text,
  amount_minor text,
  currency_code text,
  method_key text,
  reference text,
  occurred_at timestamptz,
  settled_at timestamptz,
  proof_file_id uuid,
  notes text,
  correction_reason text,
  recorded_by_user_id uuid,
  last_updated_by_user_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  status text,
  corrects_transaction_id uuid,
  version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_payment_permission(
    p_workspace_id, 'payments.read', 'deals.read'
  );
  if not exists (
    select 1 from public.deals deal
    where deal.workspace_id = p_workspace_id and deal.id = p_deal_id
  ) then
    raise exception using errcode = 'P0002', message = 'deal not found';
  end if;
  return query
  select
    transaction.id,
    transaction.deal_id,
    transaction.transaction_type,
    transaction.amount_minor::text,
    transaction.currency_code::text,
    transaction.method_key,
    transaction.reference,
    transaction.occurred_at,
    transaction.settled_at,
    case
      when app.has_permission(p_workspace_id, 'files.read_restricted')
        then transaction.proof_file_id
      else null
    end,
    transaction.notes,
    transaction.correction_reason,
    transaction.created_by,
    transaction.updated_by,
    transaction.created_at,
    transaction.updated_at,
    transaction.status,
    transaction.corrects_transaction_id,
    transaction.version
  from public.payment_transactions transaction
  where transaction.workspace_id = p_workspace_id
    and transaction.deal_id = p_deal_id
  order by transaction.occurred_at desc, transaction.created_at desc,
    transaction.id desc
  limit 500;
end;
$$;

create function app.m3_record_payment_transaction(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_deal_id uuid,
  p_transaction_type text,
  p_amount_minor text,
  p_currency_code text,
  p_method_key text,
  p_reference text,
  p_occurred_at timestamptz,
  p_proof_file_id uuid,
  p_notes text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  payment_transaction_id uuid,
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
  normalized_transaction_type text;
  exact_amount bigint;
  normalized_currency text;
  normalized_method_key text;
  normalized_reference text;
  normalized_notes text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  locked_deal public.deals%rowtype;
  allowed_event_types jsonb;
  new_payment_transaction_id uuid;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_payment_permission(
    p_workspace_id, 'payments.record', 'deals.update'
  );
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  normalized_transaction_type := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_transaction_type, ''))
  );
  exact_amount := app.parse_deal_minor_units(p_amount_minor);
  normalized_currency := pg_catalog.upper(
    pg_catalog.btrim(coalesce(p_currency_code, ''))
  );
  normalized_method_key := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_method_key, ''))
  );
  normalized_reference := nullif(
    pg_catalog.btrim(coalesce(p_reference, '')), ''
  );
  normalized_notes := nullif(
    pg_catalog.btrim(coalesce(p_notes, '')), ''
  );
  if normalized_transaction_type !~ '^[a-z][a-z0-9_.-]{0,127}$'
    or normalized_transaction_type in ('refund', 'reversal') then
    raise exception using
      errcode = '22023',
      message = 'normal payment transaction type must be a configured non-correction key';
  end if;
  if exact_amount is null or exact_amount <= 0
    or normalized_currency !~ '^[A-Z]{3}$' then
    raise exception using
      errcode = '22023',
      message = 'payment amount must be positive exact minor units';
  end if;
  if normalized_method_key !~ '^[a-z][a-z0-9_.-]{0,127}$' then
    raise exception using errcode = '22023', message = 'invalid payment method key';
  end if;
  if normalized_reference is not null
      and pg_catalog.char_length(normalized_reference) > 500
    or normalized_notes is not null
      and pg_catalog.char_length(normalized_notes) > 4000 then
    raise exception using errcode = '22023', message = 'payment text exceeds its bounded length';
  end if;
  if p_occurred_at is null then
    raise exception using errcode = '23502', message = 'payment occurrence time is required';
  end if;
  if p_proof_file_id is not null
    and not app.has_permission(p_workspace_id, 'files.read_restricted') then
    raise exception using
      errcode = '42501',
      message = 'restricted-file read permission is required for payment proof';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'dealId', p_deal_id,
    'transactionType', normalized_transaction_type,
    'amountMinor', exact_amount::text,
    'currencyCode', normalized_currency,
    'methodKey', normalized_method_key,
    'reference', normalized_reference,
    'occurredAt', p_occurred_at,
    'proofFileId', p_proof_file_id,
    'notes', normalized_notes
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_record_payment_transaction',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_record_payment_transaction'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using
        errcode = '23505',
        message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'paymentTransactionId')::uuid,
      existing_receipt.result ->> 'status',
      existing_receipt.aggregate_version,
      true,
      existing_receipt.audit_event_id,
      existing_receipt.outbox_event_id;
    return;
  end if;

  locked_deal := app.lock_one_time_payment_deal(p_workspace_id, p_deal_id);
  if locked_deal.lifecycle_status <> 'active' then
    raise exception using
      errcode = '55000',
      message = 'new payment transactions require an active deal';
  end if;
  if normalized_currency <> locked_deal.currency_code::text then
    raise exception using
      errcode = '23514',
      message = 'payment transaction currency must match deal currency';
  end if;
  select coalesce(version.behavior_flags -> 'one_time_event_types', '[]'::jsonb)
    into allowed_event_types
  from public.deal_type_versions version
  where version.workspace_id = p_workspace_id
    and version.id = locked_deal.deal_type_version_id;
  if not exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(allowed_event_types) entry(value)
    where entry.value = normalized_transaction_type
  ) then
    raise exception using
      errcode = '23514',
      message = 'payment transaction type is not enabled by the pinned deal type';
  end if;

  new_payment_transaction_id := pg_catalog.gen_random_uuid();
  insert into public.payment_transactions (
    id, workspace_id, deal_id, transaction_type, amount_minor,
    currency_code, method_key, reference, occurred_at, proof_file_id,
    notes, status, version, created_by, updated_by
  ) values (
    new_payment_transaction_id, p_workspace_id, p_deal_id,
    normalized_transaction_type, exact_amount, normalized_currency,
    normalized_method_key, normalized_reference, p_occurred_at,
    p_proof_file_id, normalized_notes, 'recorded', 1,
    actor_user_id, actor_user_id
  );
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, p_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.payment_transaction_recorded',
    p_entity_type => 'payment_transaction',
    p_entity_id => new_payment_transaction_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_after_data => pg_catalog.jsonb_build_object(
      'deal_id', p_deal_id,
      'transaction_type', normalized_transaction_type,
      'amount_minor', exact_amount::text,
      'currency_code', normalized_currency,
      'status', 'recorded',
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
    p_workspace_id, 'deal.payment_transaction_recorded', p_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', p_deal_id,
      'paymentTransactionId', new_payment_transaction_id,
      'transactionType', normalized_transaction_type,
      'amountMinor', exact_amount::text,
      'currencyCode', normalized_currency,
      'status', 'recorded',
      'paymentTransactionVersion', 1
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'paymentTransactionId', new_payment_transaction_id,
    'status', 'recorded',
    'aggregateVersion', updated_deal.version
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_record_payment_transaction',
    normalized_idempotency_key, fingerprint, p_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    new_payment_transaction_id, 'recorded'::text, updated_deal.version,
    false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_settle_payment_transaction(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_payment_transaction_id uuid,
  p_expected_version bigint,
  p_settled_at timestamptz,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  payment_transaction_id uuid,
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
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  target_deal_id uuid;
  locked_deal public.deals%rowtype;
  existing_transaction public.payment_transactions%rowtype;
  updated_transaction public.payment_transactions%rowtype;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  actor_user_id := app.require_payment_permission(
    p_workspace_id, 'payments.settle', 'deals.update'
  );
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using
      errcode = '22023',
      message = 'expected payment transaction version must be positive';
  end if;
  if p_settled_at is null then
    raise exception using errcode = '23502', message = 'payment settlement time is required';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'paymentTransactionId', p_payment_transaction_id,
    'expectedVersion', p_expected_version,
    'settledAt', p_settled_at
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_settle_payment_transaction',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_settle_payment_transaction'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using
        errcode = '23505',
        message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'paymentTransactionId')::uuid,
      existing_receipt.result ->> 'status',
      existing_receipt.aggregate_version,
      true,
      existing_receipt.audit_event_id,
      existing_receipt.outbox_event_id;
    return;
  end if;

  select transaction.deal_id into target_deal_id
  from public.payment_transactions transaction
  where transaction.workspace_id = p_workspace_id
    and transaction.id = p_payment_transaction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment transaction not found';
  end if;
  locked_deal := app.lock_one_time_payment_deal(
    p_workspace_id, target_deal_id
  );
  select transaction.* into existing_transaction
  from public.payment_transactions transaction
  where transaction.workspace_id = p_workspace_id
    and transaction.id = p_payment_transaction_id
    and transaction.deal_id = target_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment transaction not found';
  end if;
  if existing_transaction.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale payment transaction version';
  end if;
  if existing_transaction.status <> 'recorded'
    or existing_transaction.corrects_transaction_id is not null
    or existing_transaction.transaction_type in ('refund', 'reversal') then
    raise exception using
      errcode = '55000',
      message = 'only a recorded original payment transaction can be settled';
  end if;
  if p_settled_at < existing_transaction.occurred_at then
    raise exception using
      errcode = '23514',
      message = 'payment settlement cannot precede occurrence';
  end if;
  update public.payment_transactions transaction
  set status = 'settled',
      settled_at = p_settled_at,
      version = transaction.version + 1,
      updated_by = actor_user_id
  where transaction.workspace_id = p_workspace_id
    and transaction.id = p_payment_transaction_id
  returning * into updated_transaction;
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, target_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.payment_transaction_settled',
    p_entity_type => 'payment_transaction',
    p_entity_id => p_payment_transaction_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'status', existing_transaction.status,
      'version', existing_transaction.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'status', updated_transaction.status,
      'settled_at', updated_transaction.settled_at,
      'version', updated_transaction.version
    ),
    p_request_id => p_request_id,
    p_correlation_id => p_correlation_id,
    p_auth_assurance => coalesce(auth.jwt() ->> 'aal', 'unknown'),
    p_metadata => pg_catalog.jsonb_build_object(
      'idempotency_key', normalized_idempotency_key
    )
  );
  new_outbox_event_id := app.append_deal_outbox_event(
    p_workspace_id, 'deal.payment_transaction_settled', target_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', target_deal_id,
      'paymentTransactionId', p_payment_transaction_id,
      'transactionType', updated_transaction.transaction_type,
      'amountMinor', updated_transaction.amount_minor::text,
      'currencyCode', updated_transaction.currency_code::text,
      'status', updated_transaction.status,
      'settledAt', updated_transaction.settled_at,
      'paymentTransactionVersion', updated_transaction.version
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'paymentTransactionId', p_payment_transaction_id,
    'status', updated_transaction.status,
    'aggregateVersion', updated_deal.version
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_settle_payment_transaction',
    normalized_idempotency_key, fingerprint, target_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    p_payment_transaction_id, updated_transaction.status,
    updated_deal.version, false, new_audit_event_id, new_outbox_event_id;
end;
$$;

create function app.m3_correct_payment_transaction(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_original_transaction_id uuid,
  p_expected_version bigint,
  p_correction_type text,
  p_amount_minor text,
  p_currency_code text,
  p_reason text,
  p_request_id text,
  p_correlation_id uuid
)
returns table (
  correction_transaction_id uuid,
  original_transaction_id uuid,
  remaining_minor text,
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
  normalized_correction_type text;
  exact_amount bigint;
  normalized_currency text;
  normalized_reason text;
  fingerprint text;
  existing_receipt public.deal_command_receipts%rowtype;
  target_deal_id uuid;
  locked_deal public.deals%rowtype;
  original_transaction public.payment_transactions%rowtype;
  corrected_amount numeric;
  remaining_amount numeric;
  remaining_after numeric;
  correction_occurred_at timestamptz;
  new_correction_transaction_id uuid;
  updated_deal public.deals%rowtype;
  new_audit_event_id uuid;
  new_outbox_event_id uuid;
  result_payload jsonb;
begin
  normalized_correction_type := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_correction_type, ''))
  );
  if normalized_correction_type not in ('refund', 'reversal') then
    raise exception using
      errcode = '22023',
      message = 'payment correction type must be refund or reversal';
  end if;
  actor_user_id := app.require_payment_permission(
    p_workspace_id,
    case normalized_correction_type
      when 'refund' then 'payments.refund'
      else 'payments.reverse'
    end,
    'deals.update'
  );
  if not app.has_recent_strong_auth(900) then
    raise exception using
      errcode = '42501',
      message = 'recent strong authentication is required for payment correction';
  end if;
  normalized_idempotency_key := app.assert_deal_command_metadata(
    p_idempotency_key, p_correlation_id
  );
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using
      errcode = '22023',
      message = 'expected payment transaction version must be positive';
  end if;
  exact_amount := app.parse_deal_minor_units(p_amount_minor);
  normalized_currency := pg_catalog.upper(
    pg_catalog.btrim(coalesce(p_currency_code, ''))
  );
  normalized_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if exact_amount is null or exact_amount <= 0
    or normalized_currency !~ '^[A-Z]{3}$' then
    raise exception using
      errcode = '22023',
      message = 'payment correction amount must be positive exact minor units';
  end if;
  if normalized_reason = ''
    or pg_catalog.char_length(normalized_reason) > 2000 then
    raise exception using
      errcode = '22023',
      message = 'non-empty bounded payment correction reason is required';
  end if;
  fingerprint := app.deal_command_fingerprint(pg_catalog.jsonb_build_object(
    'originalTransactionId', p_original_transaction_id,
    'expectedVersion', p_expected_version,
    'correctionType', normalized_correction_type,
    'amountMinor', exact_amount::text,
    'currencyCode', normalized_currency,
    'reason', normalized_reason
  ));
  perform app.lock_deal_command(
    p_workspace_id, actor_user_id, 'm3_correct_payment_transaction',
    normalized_idempotency_key
  );
  select receipt.* into existing_receipt
  from public.deal_command_receipts receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.actor_user_id = app.current_user_id()
    and receipt.command_type = 'm3_correct_payment_transaction'
    and receipt.idempotency_key = normalized_idempotency_key;
  if found then
    if existing_receipt.command_fingerprint <> fingerprint then
      raise exception using
        errcode = '23505',
        message = 'deal idempotency key was reused with different input';
    end if;
    return query select
      (existing_receipt.result ->> 'correctionTransactionId')::uuid,
      (existing_receipt.result ->> 'originalTransactionId')::uuid,
      existing_receipt.result ->> 'remainingMinor',
      existing_receipt.result ->> 'status',
      existing_receipt.aggregate_version,
      true,
      existing_receipt.audit_event_id,
      existing_receipt.outbox_event_id;
    return;
  end if;

  select transaction.deal_id into target_deal_id
  from public.payment_transactions transaction
  where transaction.workspace_id = p_workspace_id
    and transaction.id = p_original_transaction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment transaction not found';
  end if;
  locked_deal := app.lock_one_time_payment_deal(
    p_workspace_id, target_deal_id
  );
  select transaction.* into original_transaction
  from public.payment_transactions transaction
  where transaction.workspace_id = p_workspace_id
    and transaction.id = p_original_transaction_id
    and transaction.deal_id = target_deal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment transaction not found';
  end if;
  if original_transaction.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale payment transaction version';
  end if;
  if original_transaction.status <> 'settled'
    or original_transaction.amount_minor <= 0
    or original_transaction.corrects_transaction_id is not null
    or original_transaction.transaction_type in ('refund', 'reversal') then
    raise exception using
      errcode = '55000',
      message = 'only a settled original payment transaction can be corrected';
  end if;
  if normalized_currency <> original_transaction.currency_code::text
    or normalized_currency <> locked_deal.currency_code::text then
    raise exception using
      errcode = '23514',
      message = 'payment correction currency must match original and deal currency';
  end if;

  perform correction.id
  from public.payment_transactions correction
  where correction.workspace_id = p_workspace_id
    and correction.corrects_transaction_id = p_original_transaction_id
  order by correction.id
  for update;
  select coalesce(pg_catalog.sum(-correction.amount_minor), 0)
    into corrected_amount
  from public.payment_transactions correction
  where correction.workspace_id = p_workspace_id
    and correction.corrects_transaction_id = p_original_transaction_id;
  remaining_amount := original_transaction.amount_minor - corrected_amount;
  if remaining_amount <= 0 or exact_amount > remaining_amount then
    raise exception using
      errcode = '23514',
      message = 'payment correction exceeds remaining settled amount';
  end if;
  if normalized_correction_type = 'reversal'
    and exact_amount <> remaining_amount then
    raise exception using
      errcode = '23514',
      message = 'payment reversal must equal the exact remaining amount';
  end if;
  remaining_after := remaining_amount - exact_amount;
  correction_occurred_at := pg_catalog.statement_timestamp();
  new_correction_transaction_id := pg_catalog.gen_random_uuid();
  insert into public.payment_transactions (
    id, workspace_id, deal_id, transaction_type, amount_minor,
    currency_code, method_key, reference, occurred_at, settled_at,
    proof_file_id, notes, correction_reason, corrects_transaction_id,
    status, version, created_by, updated_by
  ) values (
    new_correction_transaction_id, p_workspace_id, target_deal_id,
    normalized_correction_type, -exact_amount,
    original_transaction.currency_code, null, null,
    correction_occurred_at, correction_occurred_at, null, null,
    normalized_reason, p_original_transaction_id, 'settled', 1,
    actor_user_id, actor_user_id
  );
  updated_deal := app.bump_deal_aggregate_version(
    p_workspace_id, target_deal_id, locked_deal.workflow_instance_id,
    locked_deal.version
  );
  new_audit_event_id := app.write_audit_event(
    p_workspace_id => p_workspace_id,
    p_action => 'deal.payment_transaction_corrected',
    p_entity_type => 'payment_transaction',
    p_entity_id => new_correction_transaction_id,
    p_actor_user_id => actor_user_id,
    p_actor_type => 'user',
    p_before_data => pg_catalog.jsonb_build_object(
      'original_transaction_id', p_original_transaction_id,
      'remaining_minor', remaining_amount::bigint::text,
      'original_version', original_transaction.version
    ),
    p_after_data => pg_catalog.jsonb_build_object(
      'correction_transaction_id', new_correction_transaction_id,
      'correction_type', normalized_correction_type,
      'amount_minor', (-exact_amount)::text,
      'currency_code', normalized_currency,
      'remaining_minor', remaining_after::bigint::text,
      'status', 'settled',
      'version', 1
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
    p_workspace_id, 'deal.payment_transaction_corrected', target_deal_id,
    updated_deal.version,
    pg_catalog.jsonb_build_object(
      'dealId', target_deal_id,
      'correctionTransactionId', new_correction_transaction_id,
      'originalTransactionId', p_original_transaction_id,
      'correctionType', normalized_correction_type,
      'amountMinor', (-exact_amount)::text,
      'currencyCode', normalized_currency,
      'remainingMinor', remaining_after::bigint::text,
      'status', 'settled',
      'paymentTransactionVersion', 1
    ),
    actor_user_id, p_correlation_id
  );
  result_payload := pg_catalog.jsonb_build_object(
    'correctionTransactionId', new_correction_transaction_id,
    'originalTransactionId', p_original_transaction_id,
    'remainingMinor', remaining_after::bigint::text,
    'status', 'settled',
    'aggregateVersion', updated_deal.version
  );
  perform app.record_deal_command_receipt(
    p_workspace_id, actor_user_id, 'm3_correct_payment_transaction',
    normalized_idempotency_key, fingerprint, target_deal_id,
    updated_deal.version, result_payload, new_audit_event_id,
    new_outbox_event_id
  );
  return query select
    new_correction_transaction_id, p_original_transaction_id,
    remaining_after::bigint::text, 'settled'::text, updated_deal.version,
    false, new_audit_event_id, new_outbox_event_id;
end;
$$;

alter table public.payment_transactions enable row level security;
alter table public.payment_transactions force row level security;

create policy payment_transactions_select
on public.payment_transactions
for select to authenticated
using (app.can_read_payment_workspace(workspace_id));

revoke all on table public.payment_transactions
  from public, anon, authenticated, service_role;
grant select on public.payment_transactions to service_role;
grant select (
  id,
  workspace_id,
  deal_id,
  transaction_type,
  amount_minor,
  currency_code,
  occurred_at,
  settled_at,
  status,
  corrects_transaction_id,
  version,
  created_at,
  updated_at
) on public.payment_transactions to authenticated;

revoke all on function app.assert_payment_transaction_links()
  from public, anon, authenticated, service_role;
revoke all on function app.protect_payment_transaction_history()
  from public, anon, authenticated, service_role;
revoke all on function app.require_payment_permission(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function app.can_read_payment_workspace(uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.lock_one_time_payment_deal(uuid, uuid)
  from public, anon, authenticated, service_role;

revoke all on function app.m3_list_payment_transactions(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.m3_record_payment_transaction(
  uuid, text, uuid, text, text, text, text, text, timestamptz, uuid,
  text, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_settle_payment_transaction(
  uuid, text, uuid, bigint, timestamptz, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.m3_correct_payment_transaction(
  uuid, text, uuid, bigint, text, text, text, text, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function app.m3_list_payment_transactions(uuid, uuid)
  to authenticated;
grant execute on function app.can_read_payment_workspace(uuid)
  to authenticated;
grant execute on function app.m3_record_payment_transaction(
  uuid, text, uuid, text, text, text, text, text, timestamptz, uuid,
  text, text, uuid
) to authenticated;
grant execute on function app.m3_settle_payment_transaction(
  uuid, text, uuid, bigint, timestamptz, text, uuid
) to authenticated;
grant execute on function app.m3_correct_payment_transaction(
  uuid, text, uuid, bigint, text, text, text, text, text, uuid
) to authenticated;

comment on table public.payment_transactions is
  'Append-only one-time money ledger. Normal configured events are positive; settled reasoned refunds/reversals are linked negative events. No provider, recurring, schedule, interest, or servicing behavior is stored.';
comment on column public.payment_transactions.amount_minor is
  'Exact integer minor units: positive for configured original events and negative only for linked refund/reversal corrections.';
comment on column public.payment_transactions.proof_file_id is
  'Optional same-deal ready preserved legal original. It is excluded from direct authenticated table projection.';
comment on function app.m3_list_payment_transactions(uuid, uuid) is
  'Bounded permissioned ledger projection with method, reference, private notes, actors, timestamps, correction lineage, and proof ID masked unless the caller may read restricted files.';
comment on function app.m3_correct_payment_transaction(
  uuid, text, uuid, bigint, text, text, text, text, text, uuid
) is
  'Actor-idempotent, row-locked refund/reversal command with dedicated permission, recent 15-minute strong authentication, exact remaining-balance enforcement, audit, and inert outbox evidence.';

-- Compatibility and rollback: this slice extends the existing deal aggregate,
-- actor receipt, audit, outbox, entitlement, permission, and media contracts.
-- Rollback must first retire callers and preserve/export all payment, receipt,
-- audit, and outbox history. Hard deletion of ledger history is unsupported.
