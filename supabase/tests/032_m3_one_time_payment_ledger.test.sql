-- VYN-PAY-001, VYN-DEAL-001, VYN-AUTH-002, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-JOB-001, VYN-API-001
-- M3-PAY-AC-001..003 / T-PAY-001..003
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(58);

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  assurance text default 'aal2',
  factor_age_seconds integer default 0
)
returns void
language plpgsql
as $$
declare
  claims jsonb;
begin
  claims := pg_catalog.jsonb_build_object(
    'sub', fixture_user_id::text,
    'role', 'authenticated',
    'aal', assurance,
    'amr', case when assurance = 'aal2' then pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', 'totp',
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint - factor_age_seconds
      )
    ) else pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', 'password',
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint - factor_age_seconds
      )
    ) end
  );
  perform pg_catalog.set_config(
    'request.jwt.claim.sub', fixture_user_id::text, true
  );
  perform pg_catalog.set_config(
    'request.jwt.claim.role', 'authenticated', true
  );
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create function pg_temp.legal_file_receipt(
  object_key text,
  generation text,
  byte_size bigint,
  checksum text
)
returns jsonb
language sql
immutable
as $$
  select pg_catalog.jsonb_build_object(
    'schemaVersion', 1,
    'verifier', pg_catalog.jsonb_build_object(
      'name', 'fixture-verifier', 'version', '1.0.0'
    ),
    'storage', pg_catalog.jsonb_build_object(
      'bucket', 'media-private',
      'objectKey', object_key,
      'generation', generation,
      'byteSize', byte_size::text,
      'checksumSha256', checksum
    ),
    'malwareScan', pg_catalog.jsonb_build_object(
      'verdict', 'clean',
      'sourceChecksumSha256', checksum,
      'scanner', 'fixture-scanner',
      'signatureVersion', 'fixture-signatures-1'
    )
  );
$$;

create temporary table pg_temp.deal_results (
  phase text primary key,
  deal_id uuid,
  aggregate_version bigint,
  canonical_status text,
  state_key text,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.payment_results (
  phase text primary key,
  payment_transaction_id uuid,
  status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.correction_results (
  phase text primary key,
  correction_transaction_id uuid,
  original_transaction_id uuid,
  remaining_minor text,
  status text,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
grant all on
  pg_temp.deal_results,
  pg_temp.payment_results,
  pg_temp.correction_results
to authenticated, service_role;

select extensions.has_table(
  'public', 'payment_transactions',
  'M3-PAY-AC-001 one-time payment ledger exists'
);
select extensions.has_function(
  'app', 'm3_list_payment_transactions', array['uuid','uuid'],
  'bounded payment list RPC matches the application contract'
);
select extensions.ok(
  (
    select procedure.proargnames[3:21]
    from pg_catalog.pg_proc procedure
    where procedure.oid = to_regprocedure(
      'app.m3_list_payment_transactions(uuid,uuid)'
    )
  ) = array[
    'payment_transaction_id', 'deal_id', 'transaction_type',
    'amount_minor', 'currency_code', 'method_key', 'reference',
    'occurred_at', 'settled_at', 'proof_file_id', 'notes',
    'correction_reason', 'recorded_by_user_id',
    'last_updated_by_user_id', 'created_at', 'updated_at', 'status',
    'corrects_transaction_id', 'version'
  ]::text[],
  'T-PAY-001 list result exposes the strict operator-ledger contract'
);
select extensions.has_function(
  'app', 'm3_record_payment_transaction',
  array[
    'uuid','text','uuid','text','text','text','text','text',
    'timestamp with time zone','uuid','text','text','uuid'
  ],
  'payment record RPC matches the application contract'
);
select extensions.has_function(
  'app', 'm3_settle_payment_transaction',
  array[
    'uuid','text','uuid','bigint','timestamp with time zone','text','uuid'
  ],
  'versioned payment settlement RPC matches the application contract'
);
select extensions.has_function(
  'app', 'm3_correct_payment_transaction',
  array[
    'uuid','text','uuid','bigint','text','text','text','text','text','uuid'
  ],
  'row-locked refund/reversal RPC matches the application contract'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'payment_transactions'
  ),
  'T-TEN-001 payment ledger has forced RLS'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.payment_transactions', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.payment_transactions', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.payment_transactions', 'DELETE'
  ),
  'T-PAY-001 browsers cannot bypass payment commands or immutability'
);
select extensions.ok(
  not pg_catalog.has_column_privilege(
    'authenticated', 'public.payment_transactions', 'proof_file_id', 'SELECT'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated', 'public.payment_transactions', 'notes', 'SELECT'
  )
  and not pg_catalog.has_column_privilege(
    'authenticated', 'public.payment_transactions', 'correction_reason', 'SELECT'
  ),
  'T-RBAC-001 direct payment projection excludes restricted proof and private text'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'app.can_read_payment_workspace(uuid)', 'EXECUTE'
  ),
  'T-TEN-001 authenticated RLS policies can execute their safe read helper'
);
select extensions.ok(
  (
    select pg_catalog.count(*) >= 3
    from pg_catalog.pg_constraint constraint_info
    where constraint_info.contype = 'f'
      and constraint_info.conrelid
        = 'public.payment_transactions'::pg_catalog.regclass
      and pg_catalog.pg_get_constraintdef(constraint_info.oid)
        like '%FOREIGN KEY (workspace_id,%'
  ),
  'T-TEN-001 payment deal, proof, and correction links preserve workspace context'
);
select extensions.ok(
  exists (
    select 1 from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'payment_transactions'
      and column_info.column_name = 'amount_minor'
      and column_info.data_type = 'bigint'
  ),
  'M3-PAY-AC-001 payment money is exact signed bigint minor units'
);
select extensions.ok(
  not exists (
    select 1 from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'payment_transactions'
      and column_info.column_name ~ '(schedule|installment|principal|interest|recurring|provider|credential|token|servic)'
  ),
  'Milestone 3 payment ledger has no provider, schedule, recurring, or servicing fields'
);
select extensions.ok(
  pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'app.m3_record_payment_transaction(uuid,text,uuid,text,text,text,text,text,timestamptz,uuid,text,text,uuid)'::pg_catalog.regprocedure
  )) like '%one_time_event_types%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'app.m3_record_payment_transaction(uuid,text,uuid,text,text,text,text,text,timestamptz,uuid,text,text,uuid)'::pg_catalog.regprocedure
  )) not like '%''deposit''%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'app.require_payment_permission(uuid,text,text)'::pg_catalog.regprocedure
  )) like '%one_time_payments%',
  'normal payment keys are pinned configuration and both payment/deal entitlements gate access'
);
select extensions.ok(
  pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'app.m3_correct_payment_transaction(uuid,text,uuid,bigint,text,text,text,text,text,uuid)'::pg_catalog.regprocedure
  )) like '%has_recent_strong_auth(900)%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'app.m3_correct_payment_transaction(uuid,text,uuid,bigint,text,text,text,text,text,uuid)'::pg_catalog.regprocedure
  )) like '%for update%'
  and pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'app.m3_correct_payment_transaction(uuid,text,uuid,bigint,text,text,text,text,text,uuid)'::pg_catalog.regprocedure
  )) like '%sum(%',
  'M3-PAY-AC-003 corrections require recent step-up and lock before aggregation'
);
select extensions.ok(
  pg_catalog.pg_get_constraintdef(
    (
      select constraint_info.oid
      from pg_catalog.pg_constraint constraint_info
      where constraint_info.conrelid
          = 'public.deal_command_receipts'::pg_catalog.regclass
        and constraint_info.conname = 'deal_command_receipts_command_type_check'
    )
  ) like '%m3_record_payment_transaction%'
  and pg_catalog.pg_get_constraintdef(
    (
      select constraint_info.oid
      from pg_catalog.pg_constraint constraint_info
      where constraint_info.conrelid
          = 'public.deal_command_receipts'::pg_catalog.regclass
        and constraint_info.conname = 'deal_command_receipts_command_type_check'
    )
  ) like '%m3_correct_payment_transaction%',
  'T-PAY-003 actor-scoped receipts admit every payment command'
);

insert into public.role_permissions (
  workspace_id, role_id, permission_id, status
)
select
  '10000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000002',
  permission.id,
  'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key in (
    'deals.read', 'deals.update', 'payments.read', 'payments.record',
    'payments.settle', 'payments.refund'
  );

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');

set local role authenticated;

insert into pg_temp.deal_results
select 'payment-deal', command.*
from app.m3_create_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-deal-001', 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001',
  (select legal_entity.id from public.legal_entities legal_entity
    where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      and legal_entity.status = 'active'
    order by legal_entity.id limit 1),
  '41000000-0000-4000-8000-000000000001',
  null, null, 'request-payment-deal-001',
  '85060000-0000-4000-8000-000000000001'
) command;
insert into pg_temp.deal_results
select 'other-deal', command.*
from app.m3_create_deal(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-other-deal', 'retail.cash', 'CAD',
  '73000000-0000-4000-8000-000000000001',
  (select legal_entity.id from public.legal_entities legal_entity
    where legal_entity.workspace_id = '10000000-0000-4000-8000-000000000001'
      and legal_entity.status = 'active'
    order by legal_entity.id limit 1),
  '41000000-0000-4000-8000-000000000001',
  null, null, 'request-payment-other-deal',
  '85060000-0000-4000-8000-000000000002'
) command;

reset role;
insert into public.media_assets (
  id, workspace_id, deal_id, owner_entity_type, owner_entity_id,
  media_kind, status, created_by
) values
  (
    '85070000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
    'deal',
    (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
    'legal_document', 'ready',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '85070000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    (select deal_id from pg_temp.deal_results where phase = 'other-deal'),
    'deal',
    (select deal_id from pg_temp.deal_results where phase = 'other-deal'),
    'legal_document', 'ready',
    '31000000-0000-4000-8000-000000000001'
  );
insert into public.media_files (
  id, workspace_id, media_id, file_class, variant, storage_bucket,
  storage_object_key, storage_generation, mime_type, byte_size,
  checksum_sha256, metadata_stripped, retention_policy,
  verification_receipt
) values
  (
    '85071000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '85070000-0000-4000-8000-000000000001',
    'legal_document_original', 'legal_original', 'media-private',
    'workspaces/10000000-0000-4000-8000-000000000001/deals/'
      || (select deal_id::text from pg_temp.deal_results
          where phase = 'payment-deal')
      || '/payments/proof.pdf',
    'm3-payment-proof-generation-001', 'application/pdf', 1024,
    repeat('8', 64), false, 'preserve_original',
    pg_temp.legal_file_receipt(
      'workspaces/10000000-0000-4000-8000-000000000001/deals/'
        || (select deal_id::text from pg_temp.deal_results
            where phase = 'payment-deal')
        || '/payments/proof.pdf',
      'm3-payment-proof-generation-001', 1024, repeat('8', 64)
    )
  ),
  (
    '85071000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '85070000-0000-4000-8000-000000000002',
    'legal_document_original', 'legal_original', 'media-private',
    'workspaces/10000000-0000-4000-8000-000000000001/deals/'
      || (select deal_id::text from pg_temp.deal_results
          where phase = 'other-deal')
      || '/payments/wrong-proof.pdf',
    'm3-payment-proof-generation-002', 'application/pdf', 1024,
    repeat('9', 64), false, 'preserve_original',
    pg_temp.legal_file_receipt(
      'workspaces/10000000-0000-4000-8000-000000000001/deals/'
        || (select deal_id::text from pg_temp.deal_results
            where phase = 'other-deal')
        || '/payments/wrong-proof.pdf',
      'm3-payment-proof-generation-002', 1024, repeat('9', 64)
    )
  );
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

select extensions.throws_ok(
  $$
    select * from app.m3_record_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-record-zero',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
      'deposit', '0', 'CAD', 'bank_transfer', null,
      timestamptz '2026-07-16 12:00:00+00', null, null,
      'request-payment-record-zero',
      '85060000-0000-4000-8000-000000000003'
    )
  $$,
  '22023',
  'payment amount must be positive exact minor units',
  'M3-PAY-AC-001 zero or negative normal money fails closed'
);
select extensions.throws_ok(
  $$
    select * from app.m3_record_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-record-reserved',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
      'refund', '1000', 'CAD', 'bank_transfer', null,
      timestamptz '2026-07-16 12:00:00+00', null, null,
      'request-payment-record-reserved',
      '85060000-0000-4000-8000-000000000004'
    )
  $$,
  '22023',
  'normal payment transaction type must be a configured non-correction key',
  'refund and reversal are reserved to the correction command'
);
select extensions.throws_ok(
  $$
    select * from app.m3_record_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-record-type',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
      'tenant.custom_credit', '1000', 'CAD', 'bank_transfer', null,
      timestamptz '2026-07-16 12:00:00+00', null, null,
      'request-payment-record-type',
      '85060000-0000-4000-8000-000000000005'
    )
  $$,
  '23514',
  'payment transaction type is not enabled by the pinned deal type',
  'normal payment type must be enabled by immutable pinned configuration'
);
select extensions.throws_ok(
  $$
    select * from app.m3_record_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-record-currency',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
      'deposit', '1000', 'USD', 'bank_transfer', null,
      timestamptz '2026-07-16 12:00:00+00', null, null,
      'request-payment-record-currency',
      '85060000-0000-4000-8000-000000000006'
    )
  $$,
  '23514',
  'payment transaction currency must match deal currency',
  'M3-PAY-AC-001 payment currency is pinned to the deal'
);
select extensions.throws_ok(
  $$
    select * from app.m3_record_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-record-wrong-proof',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
      'deposit', '1000', 'CAD', 'bank_transfer', null,
      timestamptz '2026-07-16 12:00:00+00',
      '85071000-0000-4000-8000-000000000002', null,
      'request-payment-record-wrong-proof',
      '85060000-0000-4000-8000-000000000007'
    )
  $$,
  '23514',
  'payment proof must be a ready preserved legal original owned by the same deal',
  'payment proof rejects a preserved file owned by another deal'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.throws_ok(
  $$
    select * from app.m3_record_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-record-proof-denied',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
      'deposit', '1000', 'CAD', 'bank_transfer', null,
      timestamptz '2026-07-16 12:00:00+00',
      '85071000-0000-4000-8000-000000000001', null,
      'request-payment-record-proof-denied',
      '85060000-0000-4000-8000-000000000008'
    )
  $$,
  '42501',
  'restricted-file read permission is required for payment proof',
  'T-RBAC-001 payment recorder cannot attach a restricted file it cannot read'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
insert into pg_temp.payment_results
select 'record', command.*
from app.m3_record_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-record-001',
  (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
  'deposit', '100000', 'CAD', 'bank_transfer', 'SYNTHETIC-REF-001',
  timestamptz '2026-07-16 12:00:00+00',
  '85071000-0000-4000-8000-000000000001',
  'Synthetic one-time proof only', 'request-payment-record-001',
  '85060000-0000-4000-8000-000000000009'
) command;
insert into pg_temp.payment_results
select 'record-replay', command.*
from app.m3_record_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-record-001',
  (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
  'deposit', '100000', 'CAD', 'bank_transfer', 'SYNTHETIC-REF-001',
  timestamptz '2026-07-16 12:00:00+00',
  '85071000-0000-4000-8000-000000000001',
  'Synthetic one-time proof only', 'request-payment-record-001',
  '85060000-0000-4000-8000-000000000009'
) command;
select extensions.ok(
  (
    select first_result.status = 'recorded'
      and first_result.aggregate_version = 2
      and not first_result.replayed
      and replay_result.replayed
      and first_result.payment_transaction_id
        = replay_result.payment_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.payment_results first_result
    cross join pg_temp.payment_results replay_result
    where first_result.phase = 'record'
      and replay_result.phase = 'record-replay'
  ),
  'T-PAY-003 payment record replays original aggregate and evidence exactly'
);
select extensions.throws_ok(
  $$
    select * from app.m3_record_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-record-001',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal'),
      'deposit', '100001', 'CAD', 'bank_transfer', 'SYNTHETIC-REF-001',
      timestamptz '2026-07-16 12:00:00+00',
      '85071000-0000-4000-8000-000000000001',
      'Synthetic one-time proof only', 'request-payment-record-mismatch',
      '85060000-0000-4000-8000-000000000010'
    )
  $$,
  '23505',
  'deal idempotency key was reused with different input',
  'record idempotency mismatch fails without a second transaction'
);

reset role;
select extensions.ok(
  (
    select transaction.amount_minor = 100000
      and transaction.currency_code = 'CAD'
      and transaction.status = 'recorded'
      and transaction.version = 1
      and transaction.proof_file_id
        = '85071000-0000-4000-8000-000000000001'
    from public.payment_transactions transaction
    where transaction.id = (
      select payment_transaction_id from pg_temp.payment_results
      where phase = 'record'
    )
  ),
  'M3-PAY-AC-001 record persists exact money and same-deal preserved proof'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.payment_transactions transaction
    where transaction.deal_id = (
      select deal_id from pg_temp.deal_results where phase = 'payment-deal'
    )
  ),
  1::bigint,
  'payments.read grants a safe RLS projection without restricted proof columns'
);
select extensions.is(
  (
    select pg_catalog.count(*)
    from app.m3_list_payment_transactions(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal')
    )
  ),
  1::bigint,
  'bounded payment list exposes the recorded event to an authorized reader'
);
select extensions.ok(
  exists (
    select 1
    from app.m3_list_payment_transactions(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal')
    ) transaction
    where transaction.payment_transaction_id = (
      select payment_transaction_id from pg_temp.payment_results
      where phase = 'record'
    )
      and transaction.method_key = 'bank_transfer'
      and transaction.reference = 'SYNTHETIC-REF-001'
      and transaction.notes = 'Synthetic one-time proof only'
      and transaction.recorded_by_user_id
        = '31000000-0000-4000-8000-000000000001'
      and transaction.last_updated_by_user_id
        = '31000000-0000-4000-8000-000000000001'
      and transaction.created_at is not null
      and transaction.updated_at is not null
      and transaction.proof_file_id is null
  ),
  'T-RBAC-001 ledger metadata is readable while restricted proof stays masked'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');

select extensions.ok(
  exists (
    select 1
    from app.m3_list_payment_transactions(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal')
    ) transaction
    where transaction.payment_transaction_id = (
      select payment_transaction_id from pg_temp.payment_results
      where phase = 'record'
    )
      and transaction.proof_file_id
        = '85071000-0000-4000-8000-000000000001'
  ),
  'T-PAY-001 restricted-file reader receives the same-deal proof reference'
);

select extensions.throws_ok(
  $$
    select * from app.m3_settle_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-settle-stale',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, timestamptz '2026-07-16 13:00:00+00',
      'request-payment-settle-stale',
      '85060000-0000-4000-8000-000000000011'
    )
  $$,
  '40001',
  'stale payment transaction version',
  'T-PAY-001 stale settlement version fails before mutation'
);
select extensions.throws_ok(
  $$
    select * from app.m3_settle_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-settle-before-occurrence',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      1, timestamptz '2026-07-16 11:59:59+00',
      'request-payment-settle-before-occurrence',
      '85060000-0000-4000-8000-000000000012'
    )
  $$,
  '23514',
  'payment settlement cannot precede occurrence',
  'settlement time cannot precede the recorded event'
);
insert into pg_temp.payment_results
select 'settle', command.*
from app.m3_settle_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-settle-001',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'record'),
  1, timestamptz '2026-07-16 13:00:00+00',
  'request-payment-settle-001',
  '85060000-0000-4000-8000-000000000013'
) command;
insert into pg_temp.payment_results
select 'settle-replay', command.*
from app.m3_settle_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-settle-001',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'record'),
  1, timestamptz '2026-07-16 13:00:00+00',
  'request-payment-settle-001',
  '85060000-0000-4000-8000-000000000013'
) command;
select extensions.ok(
  (
    select first_result.status = 'settled'
      and first_result.aggregate_version = 3
      and not first_result.replayed
      and replay_result.replayed
      and first_result.payment_transaction_id
        = replay_result.payment_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.payment_results first_result
    cross join pg_temp.payment_results replay_result
    where first_result.phase = 'settle'
      and replay_result.phase = 'settle-replay'
  ),
  'T-PAY-003 settlement increments versions once and replays original evidence'
);
select extensions.throws_ok(
  $$
    select * from app.m3_settle_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-settle-001',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      1, timestamptz '2026-07-16 14:00:00+00',
      'request-payment-settle-mismatch',
      '85060000-0000-4000-8000-000000000014'
    )
  $$,
  '23505',
  'deal idempotency key was reused with different input',
  'settlement idempotency mismatch fails before current status checks'
);
select extensions.throws_ok(
  $$
    select * from app.m3_settle_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-settle-again',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, timestamptz '2026-07-16 14:00:00+00',
      'request-payment-settle-again',
      '85060000-0000-4000-8000-000000000015'
    )
  $$,
  '55000',
  'only a recorded original payment transaction can be settled',
  'T-PAY-001 a settled transaction cannot settle twice'
);
select extensions.ok(
  (
    select transaction.status = 'settled'
      and transaction.version = 2
      and transaction.settled_at
        = timestamptz '2026-07-16 13:00:00+00'
      and transaction.amount_minor = '100000'
    from app.m3_list_payment_transactions(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal')
    ) transaction
    where transaction.payment_transaction_id = (
      select payment_transaction_id from pg_temp.payment_results
      where phase = 'record'
    )
  ),
  'M3-PAY-AC-001 safe list reflects exact versioned settlement'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-reversal-permission',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'reversal', '100000', 'CAD', 'Permission probe reversal',
      'request-payment-reversal-permission',
      '85060000-0000-4000-8000-000000000016'
    )
  $$,
  '42501',
  'active one-time-payments entitlement and permission are required',
  'T-RBAC-001 reversal requires its dedicated immutable permission key'
);
select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000002', 'aal1'
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-refund-aal1',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'refund', '1000', 'CAD', 'AAL1 refund probe',
      'request-payment-refund-aal1',
      '85060000-0000-4000-8000-000000000017'
    )
  $$,
  '42501',
  'recent strong authentication is required for payment correction',
  'M3-PAY-AC-002 AAL1 cannot refund even with refund permission'
);
select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001', 'aal2', 901
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-refund-expired-stepup',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'refund', '1000', 'CAD', 'Expired step-up probe',
      'request-payment-refund-expired-stepup',
      '85060000-0000-4000-8000-000000000018'
    )
  $$,
  '42501',
  'recent strong authentication is required for payment correction',
  'M3-PAY-AC-002 strong factor older than 15 minutes fails closed'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-refund-no-reason',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'refund', '1000', 'CAD', '   ',
      'request-payment-refund-no-reason',
      '85060000-0000-4000-8000-000000000019'
    )
  $$,
  '22023',
  'non-empty bounded payment correction reason is required',
  'T-PAY-002 correction reason is mandatory and bounded'
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-refund-stale',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      1, 'refund', '1000', 'CAD', 'Stale version probe',
      'request-payment-refund-stale',
      '85060000-0000-4000-8000-000000000020'
    )
  $$,
  '40001',
  'stale payment transaction version',
  'M3-PAY-AC-003 stale correction version fails under the original row lock'
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-refund-currency',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'refund', '1000', 'USD', 'Currency mismatch probe',
      'request-payment-refund-currency',
      '85060000-0000-4000-8000-000000000021'
    )
  $$,
  '23514',
  'payment correction currency must match original and deal currency',
  'T-PAY-002 correction currency must match original and deal'
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-reversal-partial',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'reversal', '50000', 'CAD', 'Partial reversal probe',
      'request-payment-reversal-partial',
      '85060000-0000-4000-8000-000000000022'
    )
  $$,
  '23514',
  'payment reversal must equal the exact remaining amount',
  'T-PAY-002 reversal cannot be partial'
);

insert into pg_temp.correction_results
select 'refund-1', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-refund-001',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'record'),
  2, 'refund', '25000', 'CAD', 'Customer-requested partial refund',
  'request-payment-refund-001',
  '85060000-0000-4000-8000-000000000023'
) command;
insert into pg_temp.correction_results
select 'refund-1-replay', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-refund-001',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'record'),
  2, 'refund', '25000', 'CAD', 'Customer-requested partial refund',
  'request-payment-refund-001',
  '85060000-0000-4000-8000-000000000023'
) command;
select extensions.ok(
  (
    select first_result.remaining_minor = '75000'
      and first_result.status = 'settled'
      and first_result.aggregate_version = 4
      and first_result.correction_transaction_id
        <> first_result.original_transaction_id
      and replay_result.replayed
      and first_result.correction_transaction_id
        = replay_result.correction_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.correction_results first_result
    cross join pg_temp.correction_results replay_result
    where first_result.phase = 'refund-1'
      and replay_result.phase = 'refund-1-replay'
  ),
  'T-PAY-003 refund appends one linked negative event and replays exact evidence'
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-refund-001',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'refund', '25001', 'CAD', 'Changed replay input',
      'request-payment-refund-mismatch',
      '85060000-0000-4000-8000-000000000024'
    )
  $$,
  '23505',
  'deal idempotency key was reused with different input',
  'correction idempotency mismatch fails before remaining-balance checks'
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-refund-over',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'refund', '80000', 'CAD', 'Over-refund probe',
      'request-payment-refund-over',
      '85060000-0000-4000-8000-000000000025'
    )
  $$,
  '23514',
  'payment correction exceeds remaining settled amount',
  'T-PAY-002 aggregate prior corrections prevent over-refund'
);
insert into pg_temp.correction_results
select 'refund-2', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-refund-002',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'record'),
  2, 'refund', '25000', 'CAD', 'Second partial refund',
  'request-payment-refund-002',
  '85060000-0000-4000-8000-000000000026'
) command;
select extensions.is(
  (
    select result.remaining_minor || ':' || result.aggregate_version::text
    from pg_temp.correction_results result
    where result.phase = 'refund-2'
  ),
  '50000:5',
  'sequential refund recomputes exact remaining money under row locks'
);
insert into pg_temp.correction_results
select 'reversal', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-reversal-001',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'record'),
  2, 'reversal', '50000', 'CAD', 'Reverse exact remaining amount',
  'request-payment-reversal-001',
  '85060000-0000-4000-8000-000000000027'
) command;
insert into pg_temp.correction_results
select 'reversal-replay', command.*
from app.m3_correct_payment_transaction(
  '10000000-0000-4000-8000-000000000001',
  'm3-payment-reversal-001',
  (select payment_transaction_id from pg_temp.payment_results
    where phase = 'record'),
  2, 'reversal', '50000', 'CAD', 'Reverse exact remaining amount',
  'request-payment-reversal-001',
  '85060000-0000-4000-8000-000000000027'
) command;
select extensions.ok(
  (
    select first_result.remaining_minor = '0'
      and first_result.status = 'settled'
      and first_result.aggregate_version = 6
      and replay_result.replayed
      and first_result.correction_transaction_id
        = replay_result.correction_transaction_id
      and first_result.audit_event_id = replay_result.audit_event_id
      and first_result.outbox_event_id = replay_result.outbox_event_id
    from pg_temp.correction_results first_result
    cross join pg_temp.correction_results replay_result
    where first_result.phase = 'reversal'
      and replay_result.phase = 'reversal-replay'
  ),
  'T-PAY-003 exact remainder reversal reaches zero and replays after exhaustion'
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-refund-after-zero',
      (select payment_transaction_id from pg_temp.payment_results
        where phase = 'record'),
      2, 'refund', '1', 'CAD', 'Post-exhaustion probe',
      'request-payment-refund-after-zero',
      '85060000-0000-4000-8000-000000000028'
    )
  $$,
  '23514',
  'payment correction exceeds remaining settled amount',
  'T-PAY-002 no correction can exceed a fully consumed original'
);
select extensions.throws_ok(
  $$
    select * from app.m3_correct_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-correct-correction',
      (select correction_transaction_id from pg_temp.correction_results
        where phase = 'refund-1'),
      1, 'refund', '1', 'CAD', 'Correction-of-correction probe',
      'request-payment-correct-correction',
      '85060000-0000-4000-8000-000000000029'
    )
  $$,
  '55000',
  'only a settled original payment transaction can be corrected',
  'T-PAY-002 a correction event can never itself be corrected'
);
select extensions.throws_ok(
  $$
    select * from app.m3_settle_payment_transaction(
      '10000000-0000-4000-8000-000000000001',
      'm3-payment-settle-correction',
      (select correction_transaction_id from pg_temp.correction_results
        where phase = 'refund-1'),
      1, pg_catalog.statement_timestamp(),
      'request-payment-settle-correction',
      '85060000-0000-4000-8000-000000000030'
    )
  $$,
  '55000',
  'only a recorded original payment transaction can be settled',
  'correction events are born settled and cannot enter settlement flow'
);

select extensions.ok(
  (
    select original.amount_minor = 100000
      and original.status = 'settled'
      and original.version = 2
      and pg_catalog.count(correction.id) = 3
      and pg_catalog.sum(correction.amount_minor) = -100000
      and pg_catalog.bool_and(correction.status = 'settled')
      and pg_catalog.bool_and(
        correction.corrects_transaction_id = original.id
      )
    from public.payment_transactions original
    join public.payment_transactions correction
      on correction.workspace_id = original.workspace_id
     and correction.corrects_transaction_id = original.id
    where original.id = (
      select payment_transaction_id from pg_temp.payment_results
      where phase = 'record'
    )
    group by original.id, original.amount_minor, original.status,
      original.version
  ),
  'T-PAY-001..002 original stays immutable while linked corrections net exactly'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 4
      and pg_catalog.sum(transaction.amount_minor::bigint) = 0
      and pg_catalog.bool_and(transaction.status = 'settled')
      and pg_catalog.count(*) filter (
        where transaction.correction_reason is not null
          and transaction.corrects_transaction_id is not null
      ) = 3
    from app.m3_list_payment_transactions(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal')
    ) transaction
  ),
  'bounded list returns the signed append-only ledger without hidden totals'
);

reset role;
select extensions.throws_ok(
  $$
    update public.payment_transactions
    set amount_minor = amount_minor + 1
    where id = (
      select payment_transaction_id from pg_temp.payment_results
      where phase = 'record'
    )
  $$,
  '55000',
  'payment transactions are immutable except controlled settlement',
  'T-PAY-001 settled original money cannot be patched'
);
select extensions.throws_ok(
  $$
    delete from public.payment_transactions
    where id = (
      select correction_transaction_id from pg_temp.correction_results
      where phase = 'refund-1'
    )
  $$,
  '55000',
  'payment transaction history is append-only',
  'T-PAY-001 correction history cannot be hard deleted'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 5
    from public.deal_command_receipts receipt
    where receipt.workspace_id = '10000000-0000-4000-8000-000000000001'
      and receipt.deal_id = (
        select deal_id from pg_temp.deal_results where phase = 'payment-deal'
      )
      and receipt.command_type in (
        'm3_record_payment_transaction',
        'm3_settle_payment_transaction',
        'm3_correct_payment_transaction'
      )
  ) and (
    select pg_catalog.count(*) = 5
    from public.audit_events audit
    where audit.id in (
      select result.audit_event_id from pg_temp.payment_results result
      where result.phase in ('record', 'settle')
      union all
      select result.audit_event_id from pg_temp.correction_results result
      where result.phase in ('refund-1', 'refund-2', 'reversal')
    )
  ) and (
    select pg_catalog.count(*) = 5
    from public.outbox_events event
    where event.id in (
      select result.outbox_event_id from pg_temp.payment_results result
      where result.phase in ('record', 'settle')
      union all
      select result.outbox_event_id from pg_temp.correction_results result
      where result.phase in ('refund-1', 'refund-2', 'reversal')
    )
  ),
  'M3-PAY-AC-003 five committed payment commands have receipt/audit/outbox parity'
);
select extensions.ok(
  not exists (
    select 1
    from public.outbox_events event
    where event.aggregate_id = (
      select deal_id from pg_temp.deal_results where phase = 'payment-deal'
    )
      and (
        event.event_name ~ '(provider|recurr|schedule|servic|interest|principal)'
        or event.payload::text ~* '(provider|credential|token|recurr|schedule|servic|interest|principal)'
        or event.payload::text like '%Synthetic one-time proof only%'
        or event.payload::text like '%SYNTHETIC-REF-001%'
      )
  ),
  'T-JOB-001 payment outbox is inert and excludes provider, servicing, notes, and references'
);

select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.is(
  (
    select pg_catalog.count(*)
    from public.payment_transactions transaction
    where transaction.workspace_id = '10000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'T-TEN-001 forced RLS hides another workspace payment ledger'
);
select extensions.throws_ok(
  $$
    select * from app.m3_list_payment_transactions(
      '10000000-0000-4000-8000-000000000001',
      (select deal_id from pg_temp.deal_results where phase = 'payment-deal')
    )
  $$,
  '42501',
  'active deals entitlement, membership, and permission are required',
  'cross-workspace payment RPC fails closed before entity disclosure'
);

reset role;
select * from extensions.finish();
rollback;
