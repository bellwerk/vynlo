-- VYN-CFG-001, VYN-APP-001, VYN-DOC-001, VYN-NUM-001, VYN-CALC-001, VYN-TAX-001,
-- VYN-TEN-001, VYN-SEC-001, VYN-AUD-001
-- M4-CFG-AC-001..005, M4-NUM-AC-001..005, M4-CALC-AC-004..005,
-- M4-TAX-AC-002..003, M4-DOC-AC-001, M4-DOC-AC-004 /
-- T-CFG-003..004, T-DOC-002, T-NUM-001..003,
-- T-CALC-001, T-TAX-001, T-TEN-001, T-RBAC-001, T-AUD-001.
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(64);

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
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', case when assurance = 'aal2' then 'totp' else 'password' end,
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint - factor_age_seconds
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create function pg_temp.authenticate_service()
returns void
language plpgsql
as $$
declare
  claims jsonb;
begin
  claims := pg_catalog.jsonb_build_object(
    'sub', '31000000-0000-4000-8000-000000000001',
    'role', 'service_role',
    'aal', 'aal2',
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', 'service_role',
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config(
    'request.jwt.claim.sub', '31000000-0000-4000-8000-000000000001', true
  );
  perform pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.numbering_payloads (
  phase text primary key,
  payload jsonb not null,
  checksum text not null
);
create temporary table pg_temp.numbering_results (
  phase text primary key,
  numbering_definition_id uuid,
  numbering_version_id uuid,
  version bigint,
  artifact_status text,
  audit_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.approval_results (
  phase text primary key,
  approval_record_id uuid,
  audit_event_id uuid,
  replayed boolean
);
create temporary table pg_temp.allocation_results (
  phase text primary key,
  allocation_id uuid,
  formatted_value text,
  sequence_value bigint,
  period_key text,
  replayed boolean
);
create temporary table pg_temp.runtime_fixture (
  phase text primary key,
  definition jsonb not null,
  definition_checksum text not null,
  evidence jsonb not null
);
create temporary table pg_temp.runtime_results (
  phase text primary key,
  evidence_id uuid
);
create temporary table pg_temp.artifact_checksums (
  phase text primary key,
  checksum text not null
);
grant all on
  pg_temp.numbering_payloads,
  pg_temp.numbering_results,
  pg_temp.approval_results,
  pg_temp.allocation_results,
  pg_temp.runtime_fixture,
  pg_temp.runtime_results,
  pg_temp.artifact_checksums
to authenticated, service_role;

insert into pg_temp.numbering_payloads (phase, payload, checksum)
select fixture.phase, fixture.payload, app.m4_canonical_fingerprint(fixture.payload)
from (values
  (
    'v1'::text,
    '{
      "semanticVersion":"1.0.0",
      "scopeType":"workspace",
      "prefix":"DOC-",
      "suffix":"",
      "numericWidth":6,
      "startingValue":100,
      "incrementBy":1,
      "resetPolicy":"never",
      "periodMonths":null,
      "periodAnchor":null,
      "timezone":"UTC",
      "formatPattern":"{{prefix}}{{sequence}}{{suffix}}",
      "importPolicy":"authorized_reservation",
      "reusePolicy":"never",
      "allocationEvent":"official_document_created"
    }'::jsonb
  ),
  (
    'v2'::text,
    '{
      "semanticVersion":"1.1.0",
      "scopeType":"workspace",
      "prefix":"DOC-",
      "suffix":"",
      "numericWidth":7,
      "startingValue":1000,
      "incrementBy":1,
      "resetPolicy":"never",
      "periodMonths":null,
      "periodAnchor":null,
      "timezone":"UTC",
      "formatPattern":"{{prefix}}{{sequence}}{{suffix}}",
      "importPolicy":"authorized_reservation",
      "reusePolicy":"never",
      "allocationEvent":"official_document_created"
    }'::jsonb
  )
) fixture(phase, payload);

-- 1. Every M4 configuration/history table exposed through PostgREST is forced-RLS.
select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'numbering_definitions', 'numbering_definition_versions',
        'numbering_counters', 'number_allocations', 'calculation_definitions',
        'calculation_versions', 'calculation_snapshots', 'tax_packs',
        'tax_pack_versions', 'tax_pack_assignments',
        'tax_calculation_snapshots', 'export_definitions', 'export_versions',
        'export_runs', 'export_files', 'export_download_authorizations',
        'configuration_artifact_commands', 'runtime_evidence_records',
        'runtime_evidence_consumptions'
      ])
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  19::bigint,
  'M4-CFG-AC-003 all configuration, execution, and authorization history is forced-RLS'
);

-- 2. Browser sessions never receive raw mutation privileges on configuration tables.
select extensions.ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.numbering_definition_versions', 'INSERT')
  and not pg_catalog.has_table_privilege('authenticated', 'public.numbering_definition_versions', 'UPDATE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.numbering_definition_versions', 'DELETE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.calculation_versions', 'INSERT')
  and not pg_catalog.has_table_privilege('authenticated', 'public.calculation_versions', 'UPDATE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.tax_pack_versions', 'INSERT')
  and not pg_catalog.has_table_privilege('authenticated', 'public.export_versions', 'INSERT'),
  'T-RBAC-001 browser configuration changes are available only through commands'
);

-- 3. Runtime results can be recorded only at the trusted service boundary.
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.m4_record_runtime_evidence(uuid,uuid,text,uuid,uuid,uuid,jsonb,text,text,uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'service_role',
    'app.m4_record_runtime_evidence(uuid,uuid,text,uuid,uuid,uuid,jsonb,text,text,uuid)',
    'EXECUTE'
  ),
  'M4-CALC-AC-004 runtime evidence recorder is service-only'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.numbering_results
select 'v1', result.*
from app.m4_create_numbering_version(
  '10000000-0000-4000-8000-000000000001',
  'fixture_document',
  '{"en":"Fixture document","fr":"Document fictif"}',
  (select payload from pg_temp.numbering_payloads where phase = 'v1'),
  (select checksum from pg_temp.numbering_payloads where phase = 'v1'),
  null,
  'm4-numbering-create-v1',
  'Create rolled-back numbering fixture version one',
  'm4-numbering-create-v1',
  '34000000-0000-4000-8000-000000000001'
) result;

-- 4. Creation pins an inert checksum-tested version without activating it.
select extensions.results_eq(
  $$select version, artifact_status, replayed from pg_temp.numbering_results where phase = 'v1'$$,
  $$values (1::bigint, 'test_passed'::text, false)$$,
  'M4-NUM-AC-001 numbering version creation persists explicit tested lifecycle state'
);

insert into pg_temp.numbering_results
select 'v1-replay', result.*
from app.m4_create_numbering_version(
  '10000000-0000-4000-8000-000000000001',
  'fixture_document',
  '{"en":"Fixture document","fr":"Document fictif"}',
  (select payload from pg_temp.numbering_payloads where phase = 'v1'),
  (select checksum from pg_temp.numbering_payloads where phase = 'v1'),
  null,
  'm4-numbering-create-v1',
  'Create rolled-back numbering fixture version one',
  'm4-numbering-create-v1-replay',
  '34000000-0000-4000-8000-000000000001'
) result;

-- 5. The exact create command replays the same immutable version and audit evidence.
select extensions.ok(
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1-replay')
    = (select numbering_version_id from pg_temp.numbering_results where phase = 'v1')
  and (select audit_event_id from pg_temp.numbering_results where phase = 'v1-replay')
    = (select audit_event_id from pg_temp.numbering_results where phase = 'v1')
  and (select replayed from pg_temp.numbering_results where phase = 'v1-replay'),
  'M4-CFG-AC-001 exact configuration create replay is idempotent'
);

insert into pg_temp.numbering_results
select 'v2', result.*
from app.m4_create_numbering_version(
  '10000000-0000-4000-8000-000000000001',
  'fixture_document',
  '{"en":"Fixture document","fr":"Document fictif"}',
  (select payload from pg_temp.numbering_payloads where phase = 'v2'),
  (select checksum from pg_temp.numbering_payloads where phase = 'v2'),
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
  'm4-numbering-create-v2',
  'Create rolled-back numbering fixture version two',
  'm4-numbering-create-v2',
  '34000000-0000-4000-8000-000000000002'
) result;

-- 6. A compatible correction creates a new version and preserves version one.
select extensions.ok(
  (select version from pg_temp.numbering_results where phase = 'v2') = 2
  and (select pg_catalog.count(*) from public.numbering_definition_versions
       where numbering_definition_id = (
         select numbering_definition_id from pg_temp.numbering_results where phase = 'v1'
       )) = 2,
  'M4-CFG-AC-003 correction creates a second immutable numbering version'
);

reset role;
savepoint artifact_evidence_fail_closed;

-- Trusted imports cannot bypass the lifecycle by inserting a later state.
select extensions.throws_ok(
  $$
    insert into public.numbering_definition_versions (
      id, workspace_id, numbering_definition_id, version, semantic_version,
      status, scope_type, prefix, suffix, numeric_width, starting_value,
      increment_by, reset_policy, timezone_name, format_pattern,
      import_policy, reuse_policy, allocation_event, checksum, created_by
    ) values (
      '34010000-0000-4000-8000-000000000098',
      '10000000-0000-4000-8000-000000000001',
      (select numbering_definition_id from pg_temp.numbering_results where phase = 'v1'),
      98, '98.0.0', 'active', 'workspace', 'BAD-', '', 6, 1, 1,
      'never', 'UTC', '{{prefix}}{{sequence}}{{suffix}}',
      'authorized_reservation', 'never', 'official_document_created',
      repeat('8', 64), '31000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  'configuration artifact versions must be inserted as draft',
  'M4-CFG-AC-002 direct non-draft artifact insertion fails closed'
);

insert into public.numbering_definition_versions (
  id, workspace_id, numbering_definition_id, version, semantic_version,
  status, scope_type, prefix, suffix, numeric_width, starting_value,
  increment_by, reset_policy, timezone_name, format_pattern,
  import_policy, reuse_policy, allocation_event, checksum, created_by
) values (
  '34010000-0000-4000-8000-000000000099',
  '10000000-0000-4000-8000-000000000001',
  (select numbering_definition_id from pg_temp.numbering_results where phase = 'v1'),
  99, '99.0.0', 'draft', 'workspace', 'SAFE-', '', 6, 1, 1,
  'never', 'UTC', '{{prefix}}{{sequence}}{{suffix}}',
  'authorized_reservation', 'never', 'official_document_created',
  repeat('9', 64), '31000000-0000-4000-8000-000000000001'
);

select extensions.throws_ok(
  $$
    update public.numbering_definition_versions
    set status = 'validated', validation_evidence = '{}'::jsonb
    where id = '34010000-0000-4000-8000-000000000099'
  $$,
  '23514',
  'passing validation evidence is required',
  'M4-CFG-AC-002 empty validation evidence cannot exploit missing JSON keys'
);

update public.numbering_definition_versions
set status = 'validated',
    validation_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'validator', 'fixture-validator-v1',
      'artifactChecksum', checksum
    )
where id = '34010000-0000-4000-8000-000000000099';

select extensions.throws_ok(
  $$
    update public.numbering_definition_versions
    set status = 'test_passed',
        fixture_evidence = pg_catalog.jsonb_build_object(
          'passed', true, 'runner', 'fixture-runner-v1',
          'artifactChecksum', checksum
        )
    where id = '34010000-0000-4000-8000-000000000099'
  $$,
  '23514',
  'passing fixture evidence is required',
  'M4-CFG-AC-002 partial fixture evidence cannot omit its tests array'
);

rollback to savepoint artifact_evidence_fail_closed;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 7. The expected-latest token closes a stale concurrent version creation.
select extensions.throws_ok(
  $$
    select * from app.m4_create_numbering_version(
      '10000000-0000-4000-8000-000000000001', 'fixture_document',
      '{"en":"Fixture document","fr":"Document fictif"}',
      (select payload from pg_temp.numbering_payloads where phase = 'v2'),
      (select checksum from pg_temp.numbering_payloads where phase = 'v2'),
      (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
      'm4-numbering-stale-v3', 'Stale concurrent numbering edit',
      'm4-numbering-stale-v3', '34000000-0000-4000-8000-000000000003'
    )
  $$,
  '40001',
  'numbering definition latest version changed',
  'M4-CFG-AC-003 stale optimistic numbering edits fail safely'
);

insert into pg_temp.approval_results
select 'v1', result.*
from app.m4_record_artifact_approval(
  '10000000-0000-4000-8000-000000000001',
  'numbering_definition',
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
  (select checksum from pg_temp.numbering_payloads where phase = 'v1'),
  'operational', 'approved', 'm4-numbering-approve-v1',
  'Approve the rolled-back numbering fixture',
  'operations_reviewer', 'Fixture Review Lab',
  '{"scope":"synthetic-only"}', 'fixture://numbering-approval',
  pg_catalog.statement_timestamp() + interval '1 day',
  pg_catalog.statement_timestamp() + interval '12 hours',
  null, 'm4-numbering-approve-v1',
  '34000000-0000-4000-8000-000000000004'
) result;

-- 8. Approval is exact-version/checksum bound and records professional provenance.
select extensions.ok(
  exists (
    select 1 from public.approval_records approval
    where approval.id = (
      select approval_record_id from pg_temp.approval_results where phase = 'v1'
    )
      and approval.artifact_id = (
        select numbering_version_id from pg_temp.numbering_results where phase = 'v1'
      )
      and approval.artifact_checksum = (
        select checksum from pg_temp.numbering_payloads where phase = 'v1'
      )
      and approval.professional_role = 'operations_reviewer'
      and approval.professional_organization = 'Fixture Review Lab'
  ),
  'M4-CFG-AC-005 approval preserves exact artifact and provenance'
);

insert into pg_temp.approval_results
select 'v1-replay', result.*
from app.m4_record_artifact_approval(
  '10000000-0000-4000-8000-000000000001',
  'numbering_definition',
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
  (select checksum from pg_temp.numbering_payloads where phase = 'v1'),
  'operational', 'approved', 'm4-numbering-approve-v1',
  'Approve the rolled-back numbering fixture',
  'operations_reviewer', 'Fixture Review Lab',
  '{"scope":"synthetic-only"}', 'fixture://numbering-approval',
  (select expires_at from public.approval_records where id = (
    select approval_record_id from pg_temp.approval_results where phase = 'v1'
  )),
  (select review_due_at from public.approval_records where id = (
    select approval_record_id from pg_temp.approval_results where phase = 'v1'
  )),
  null, 'm4-numbering-approve-v1-replay',
  '34000000-0000-4000-8000-000000000004'
) result;

-- 9. Exact approval replay returns the original row without a second audit.
select extensions.ok(
  (select approval_record_id from pg_temp.approval_results where phase = 'v1-replay')
    = (select approval_record_id from pg_temp.approval_results where phase = 'v1')
  and (select audit_event_id from pg_temp.approval_results where phase = 'v1-replay')
    = (select audit_event_id from pg_temp.approval_results where phase = 'v1')
  and (select replayed from pg_temp.approval_results where phase = 'v1-replay'),
  'M4-CFG-AC-005 approval command replays the exact approval and audit evidence'
);

create temporary table pg_temp.transition_results (
  phase text primary key,
  artifact_id uuid,
  artifact_status text,
  approval_record_id uuid,
  audit_event_id uuid,
  replayed boolean
);
grant all on pg_temp.transition_results to authenticated;
insert into pg_temp.transition_results
select 'active', result.*
from app.m4_transition_artifact_version(
  '10000000-0000-4000-8000-000000000001',
  'numbering_definition',
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
  (select checksum from pg_temp.numbering_payloads where phase = 'v1'),
  'active', '{"expectedVersion":1}', 'm4-numbering-activate-v1',
  'Activate rolled-back approved numbering fixture',
  'm4-numbering-activate-v1',
  '34000000-0000-4000-8000-000000000005'
) result;

-- 10. Activation passes only with permission, recent AAL2, fixtures, and exact approval.
select extensions.results_eq(
  $$select artifact_status, replayed from pg_temp.transition_results where phase = 'active'$$,
  $$values ('active'::text, false)$$,
  'M4-CFG-AC-002 exact approved numbering version activates'
);

-- 11. The active version remains bound to the exact approval used by the command.
select extensions.ok(
  exists (
    select 1 from public.numbering_definition_versions version
    where version.id = (
      select numbering_version_id from pg_temp.numbering_results where phase = 'v1'
    )
      and version.status = 'active'
      and version.approval_record_id = (
        select approval_record_id from pg_temp.approval_results where phase = 'v1'
      )
      and version.timezone_name = 'UTC'
      and version.allocation_event = 'official_document_created'
      and version.fixture_evidence ->> 'passed' = 'true'
  ),
  'M4-CFG-AC-002 active numbering version retains gate evidence'
);

reset role;

-- Activation revalidates persisted evidence even if storage was corrupted
-- outside the normal trigger path.
savepoint activation_evidence_corruption;
alter table public.numbering_definition_versions
  disable trigger numbering_versions_lifecycle_guard;
update public.numbering_definition_versions version
set status = 'approved',
    validation_evidence = version.validation_evidence - 'artifactChecksum',
    activated_by = null,
    activated_at = null
where version.id = (
  select numbering_version_id from pg_temp.numbering_results where phase = 'v1'
);
alter table public.numbering_definition_versions
  enable trigger numbering_versions_lifecycle_guard;
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.m4_transition_artifact_version(
      '10000000-0000-4000-8000-000000000001',
      'numbering_definition',
      (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
      (select checksum from pg_temp.numbering_payloads where phase = 'v1'),
      'active', '{"expectedVersion":1}', 'm4-numbering-corrupt-evidence',
      'Reject activation with missing checksum-bound evidence',
      'm4-numbering-corrupt-evidence',
      '34000000-0000-4000-8000-000000000050'
    )
  $$,
  '23514',
  'activation gates are incomplete',
  'M4-CFG-AC-002 activation rejects persisted evidence with a missing required key'
);
rollback to savepoint activation_evidence_corruption;

-- 12. Even trusted writes cannot edit content of an activated version.
select extensions.throws_ok(
  $$
    update public.numbering_definition_versions
    set numeric_width = numeric_width + 1
    where id = (select numbering_version_id from pg_temp.numbering_results where phase = 'v1')
  $$,
  '23514',
  'numbering_definition_versions.numeric_width is immutable after version creation',
  'M4-CFG-AC-003 active artifact content is immutable'
);

-- 13. Approval decisions are append-only even to trusted roles.
select extensions.throws_ok(
  $$
    update public.approval_records set reason = 'attempted rewrite'
    where id = (select approval_record_id from pg_temp.approval_results where phase = 'v1')
  $$,
  '55000',
  'approval_records records are append-only',
  'M4-CFG-AC-005 approval evidence cannot be rewritten'
);

insert into pg_temp.allocation_results
select 'first', result.*
from app.m4_allocate_number(
  '10000000-0000-4000-8000-000000000001',
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
  '10000000-0000-4000-8000-000000000001', date '2026-07-16',
  'document', '34100000-0000-4000-8000-000000000001',
  'm4-number-allocation-first', 'Allocate fixture official number',
  '31000000-0000-4000-8000-000000000001', ''
) result;
insert into pg_temp.allocation_results
select 'second', result.*
from app.m4_allocate_number(
  '10000000-0000-4000-8000-000000000001',
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
  '10000000-0000-4000-8000-000000000001', date '2026-07-16',
  'document', '34100000-0000-4000-8000-000000000002',
  'm4-number-allocation-second', 'Allocate another fixture official number',
  '31000000-0000-4000-8000-000000000001', ''
) result;

-- 14. Two committed allocations atomically create two permanent rows.
select extensions.is(
  (select pg_catalog.count(*) from pg_temp.allocation_results where not replayed),
  2::bigint,
  'M4-NUM-AC-002 committed allocations persist exactly once'
);

-- 15. Locked allocation advances monotonically and produces unique formatted values.
select extensions.ok(
  (select sequence_value from pg_temp.allocation_results where phase = 'second')
    = (select sequence_value + 1 from pg_temp.allocation_results where phase = 'first')
  and (select formatted_value from pg_temp.allocation_results where phase = 'second')
    <> (select formatted_value from pg_temp.allocation_results where phase = 'first'),
  'T-NUM-001 locked sequence allocations are unique and monotonic'
);

insert into pg_temp.allocation_results
select 'first-replay', result.*
from app.m4_allocate_number(
  '10000000-0000-4000-8000-000000000001',
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
  '10000000-0000-4000-8000-000000000001', date '2026-07-16',
  'document', '34100000-0000-4000-8000-000000000001',
  'm4-number-allocation-first', 'Allocate fixture official number',
  '31000000-0000-4000-8000-000000000001', ''
) result;

-- 16. Retry returns the same allocation and never advances the counter.
select extensions.ok(
  (select allocation_id from pg_temp.allocation_results where phase = 'first-replay')
    = (select allocation_id from pg_temp.allocation_results where phase = 'first')
  and (select replayed from pg_temp.allocation_results where phase = 'first-replay')
  and (select pg_catalog.count(*) from public.number_allocations
       where numbering_version_id = (
         select numbering_version_id from pg_temp.numbering_results where phase = 'v1'
       )) = 2,
  'M4-NUM-AC-003 allocation retry returns the original permanent number'
);

-- 17. Reusing an allocation key for a different entity fails closed.
select extensions.throws_ok(
  $$
    select * from app.m4_allocate_number(
      '10000000-0000-4000-8000-000000000001',
      (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
      '10000000-0000-4000-8000-000000000001', date '2026-07-16',
      'document', '34100000-0000-4000-8000-000000000099',
      'm4-number-allocation-first', 'Conflicting fixture allocation',
      '31000000-0000-4000-8000-000000000001', ''
    )
  $$,
  '23505',
  'numbering idempotency conflict',
  'M4-NUM-AC-003 allocation idempotency conflicts are explicit'
);

-- 18. A committed number cannot be edited back into an allocation pool.
select extensions.throws_ok(
  $$
    update public.number_allocations set allocation_reason = 'attempted reuse'
    where id = (select allocation_id from pg_temp.allocation_results where phase = 'first')
  $$,
  '55000',
  'number_allocations is append-only',
  'T-NUM-003 committed allocation cannot be changed'
);

-- 19. A committed number cannot be deleted after failure, void, or supersession.
select extensions.throws_ok(
  $$delete from public.number_allocations
    where id = (select allocation_id from pg_temp.allocation_results where phase = 'first')$$,
  '55000',
  'number_allocations is append-only',
  'M4-NUM-AC-004 committed allocation cannot be deleted'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.transition_results
select 'retired', result.*
from app.m4_transition_artifact_version(
  '10000000-0000-4000-8000-000000000001',
  'numbering_definition',
  (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
  (select checksum from pg_temp.numbering_payloads where phase = 'v1'),
  'retired', '{"expectedVersion":1}', 'm4-numbering-retire-v1',
  'Retire rolled-back numbering fixture without reusing values',
  'm4-numbering-retire-v1',
  '34000000-0000-4000-8000-000000000006'
) result;

-- 20. Retirement is a reasoned audited state, not deletion.
select extensions.ok(
  (select artifact_status from pg_temp.transition_results where phase = 'retired') = 'retired'
  and exists (
    select 1 from public.numbering_definition_versions
    where id = (select numbering_version_id from pg_temp.numbering_results where phase = 'v1')
      and status = 'retired' and retired_at is not null
  ),
  'M4-CFG-AC-003 retirement preserves immutable numbering history'
);
reset role;

-- 21. Retired versions cannot allocate, while their committed values remain present.
select extensions.throws_ok(
  $$
    select * from app.m4_allocate_number(
      '10000000-0000-4000-8000-000000000001',
      (select numbering_version_id from pg_temp.numbering_results where phase = 'v1'),
      '10000000-0000-4000-8000-000000000001', date '2026-07-16',
      'document', '34100000-0000-4000-8000-000000000003',
      'm4-number-after-retire', 'Attempt retired allocation',
      '31000000-0000-4000-8000-000000000001', ''
    )
  $$,
  '23514',
  'active numbering version is required',
  'M4-NUM-AC-004 retired sequence never reissues a committed value'
);

-- Future-effective tax activation must bound, not erase, the historical
-- assignment used by already-effective transactions.
insert into public.tax_packs (
  id, workspace_id, key, labels, source_kind
) values (
  '34500000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture_tax_history',
  '{"en":"Fixture historical tax","fr":"Taxe historique fictive"}',
  'portable_pack'
);

insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version, artifact_id,
  artifact_checksum, approval_type, decision, decided_by,
  professional_role, professional_organization, conditions,
  attachment_reference, idempotency_key, reason
) values
  (
    '34520000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'tax_pack', 'tax.fixture_tax_history', 1,
    '34510000-0000-4000-8000-000000000001',
    app.m4_canonical_fingerprint(
      '{"semanticVersion":"1.0.0","sources":[],"rules":{"rate":"0.10"}}'
    ),
    'tax_review', 'approved', '31000000-0000-4000-8000-000000000001',
    'fixture_reviewer', 'Synthetic Review Lab', '{"fixture":true}',
    'fixture://tax/v1', 'm4-tax-history-approval-v1',
    'Approve rolled-back historical tax version'
  ),
  (
    '34520000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'tax_pack', 'tax.fixture_tax_history', 2,
    '34510000-0000-4000-8000-000000000002',
    app.m4_canonical_fingerprint(
      '{"semanticVersion":"2.0.0","sources":[],"rules":{"rate":"0.11"}}'
    ),
    'tax_review', 'approved', '31000000-0000-4000-8000-000000000001',
    'fixture_reviewer', 'Synthetic Review Lab', '{"fixture":true}',
    'fixture://tax/v2', 'm4-tax-history-approval-v2',
    'Approve rolled-back future tax version'
  );

insert into public.tax_pack_versions (
  id, workspace_id, tax_pack_id, version, semantic_version, status,
  jurisdiction_code, contexts, currency_codes, effective_from, effective_to,
  rules, source_metadata, input_schema, output_schema, override_policy,
  golden_fixtures, engine_version, checksum, validation_evidence,
  fixture_evidence, created_by
) values
  (
    '34510000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '34500000-0000-4000-8000-000000000001', 1, '1.0.0', 'draft',
    'CA', array['retail'], array['CAD'], date '2026-01-01', null,
    '{"components":[{"key":"fixture_tax","rate":"0.10"}]}',
    '{"sources":[]}', '{"type":"object"}', '{"type":"object"}',
    '{"allowed":false}', '[{"case":"historical"}]', 'fixture-tax-v1',
    app.m4_canonical_fingerprint(
      '{"semanticVersion":"1.0.0","sources":[],"rules":{"rate":"0.10"}}'
    ),
    null, null,
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '34510000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '34500000-0000-4000-8000-000000000001', 2, '2.0.0', 'draft',
    'CA', array['retail'], array['CAD'], date '2027-01-01', null,
    '{"components":[{"key":"fixture_tax","rate":"0.11"}]}',
    '{"sources":[]}', '{"type":"object"}', '{"type":"object"}',
    '{"allowed":false}', '[{"case":"future"}]', 'fixture-tax-v2',
    app.m4_canonical_fingerprint(
      '{"semanticVersion":"2.0.0","sources":[],"rules":{"rate":"0.11"}}'
    ),
    null, null,
    '31000000-0000-4000-8000-000000000001'
  );

update public.tax_pack_versions version
set status = 'validated',
    validation_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'validator', 'fixture-tax-validator-v1',
      'artifactChecksum', version.checksum
    )
where version.id in (
  '34510000-0000-4000-8000-000000000001',
  '34510000-0000-4000-8000-000000000002'
);
update public.tax_pack_versions version
set status = 'test_passed',
    fixture_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'runner', 'fixture-tax-runner-v1',
      'artifactChecksum', version.checksum,
      'tests', pg_catalog.jsonb_build_array('fixture-tax-' || version.version::text)
    )
where version.id in (
  '34510000-0000-4000-8000-000000000001',
  '34510000-0000-4000-8000-000000000002'
);

insert into pg_temp.artifact_checksums (phase, checksum)
select
  case version.id
    when '34510000-0000-4000-8000-000000000001' then 'tax-v1'
    else 'tax-v2'
  end,
  version.checksum
from public.tax_pack_versions version
where version.id in (
  '34510000-0000-4000-8000-000000000001',
  '34510000-0000-4000-8000-000000000002'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.transition_results
select 'tax-v1-active', result.*
from app.m4_transition_artifact_version(
  '10000000-0000-4000-8000-000000000001', 'tax_pack',
  '34510000-0000-4000-8000-000000000001',
  (select checksum from pg_temp.artifact_checksums where phase = 'tax-v1'),
  'active', '{"expectedVersion":1}', 'm4-tax-history-activate-v1',
  'Activate rolled-back historical tax version',
  'm4-tax-history-activate-v1', '34530000-0000-4000-8000-000000000001'
) result;
insert into pg_temp.transition_results
select 'tax-v2-active', result.*
from app.m4_transition_artifact_version(
  '10000000-0000-4000-8000-000000000001', 'tax_pack',
  '34510000-0000-4000-8000-000000000002',
  (select checksum from pg_temp.artifact_checksums where phase = 'tax-v2'),
  'active', '{"expectedVersion":2}', 'm4-tax-history-activate-v2',
  'Activate rolled-back future tax version',
  'm4-tax-history-activate-v2', '34530000-0000-4000-8000-000000000002'
) result;
reset role;

insert into pg_temp.runtime_fixture (phase, definition, definition_checksum, evidence)
select
  fixture.phase,
  fixture.pack,
  app.m4_canonical_fingerprint(fixture.pack),
  evidence.payload || pg_catalog.jsonb_build_object(
    'checksum', app.m4_canonical_fingerprint(evidence.payload)
  )
from (values
  (
    'tax-v1-historical'::text,
    '34510000-0000-4000-8000-000000000001'::uuid,
    '1.0.0'::text,
    'fixture-tax-v1'::text,
    date '2026-06-01',
    '{"semanticVersion":"1.0.0","sources":[],"rules":{"rate":"0.10"}}'::jsonb
  ),
  (
    'tax-v1-future'::text,
    '34510000-0000-4000-8000-000000000001'::uuid,
    '1.0.0'::text,
    'fixture-tax-v1'::text,
    date '2027-01-02',
    '{"semanticVersion":"1.0.0","sources":[],"rules":{"rate":"0.10"}}'::jsonb
  ),
  (
    'tax-v2-future'::text,
    '34510000-0000-4000-8000-000000000002'::uuid,
    '2.0.0'::text,
    'fixture-tax-v2'::text,
    date '2027-01-02',
    '{"semanticVersion":"2.0.0","sources":[],"rules":{"rate":"0.11"}}'::jsonb
  )
) fixture(phase, version_id, semantic_version, engine_version, transaction_date, pack)
join public.tax_pack_assignments assignment
  on assignment.workspace_id = '10000000-0000-4000-8000-000000000001'
 and assignment.tax_pack_version_id = fixture.version_id
cross join lateral (
  select pg_catalog.jsonb_build_object(
    'versionId', fixture.version_id,
    'packKey', 'fixture_tax_history',
    'packVersion', fixture.semantic_version,
    'packChecksum', app.m4_canonical_fingerprint(fixture.pack),
    'engineVersion', fixture.engine_version,
    'assignmentId', assignment.id,
    'pack', fixture.pack,
    'jurisdiction', 'CA',
    'context', 'retail',
    'currency', 'CAD',
    'transactionDate', fixture.transaction_date,
    'input', pg_catalog.jsonb_build_object('subtotalMinor', '10000'),
    'output', pg_catalog.jsonb_build_object('taxMinor', '1000')
  ) as payload
) evidence;

-- Build a portable calculation definition and trusted execution fixture.
insert into pg_temp.runtime_fixture (phase, definition, definition_checksum, evidence)
select
  'calculation',
  base.definition,
  base.definition_checksum,
  base.evidence_without_checksum || pg_catalog.jsonb_build_object(
    'checksum', app.m4_canonical_fingerprint(base.evidence_without_checksum)
  )
from (
  select
    definition,
    app.m4_canonical_fingerprint(definition) as definition_checksum,
    pg_catalog.jsonb_build_object(
      'versionId', '34200000-0000-4000-8000-000000000001',
      'definitionKey', 'fixture_total',
      'definitionVersion', '1.0.0',
      'definitionChecksum', app.m4_canonical_fingerprint(definition),
      'engineVersion', 'fixture-calculation-v1',
      'definition', definition,
      'input', pg_catalog.jsonb_build_object('subtotalMinor', '10000'),
      'output', pg_catalog.jsonb_build_object('totalMinor', '10000'),
      'components', pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('key', 'subtotal', 'amountMinor', '10000')
      ),
      'taxComponents', '[]'::jsonb,
      'rounding', pg_catalog.jsonb_build_object('mode', 'half_up', 'scale', 0)
    ) as evidence_without_checksum
  from (values (
    '{
      "key":"fixture_total",
      "semantic_version":"1.0.0",
      "input_schema":{"type":"object"},
      "output_schema":{"type":"object"},
      "expression_ast":{"type":"field","path":"subtotalMinor"},
      "rounding_policy":{"mode":"half_up","scale":0},
      "resource_limits":{"max_nodes":100},
      "fixtures":[],
      "engine_version":"fixture-calculation-v1"
    }'::jsonb
  )) source(definition)
) base;

insert into pg_temp.runtime_fixture (phase, definition, definition_checksum, evidence)
select
  'calculation-conflict',
  definition,
  definition_checksum,
  changed.payload || pg_catalog.jsonb_build_object(
    'checksum', app.m4_canonical_fingerprint(changed.payload)
  )
from pg_temp.runtime_fixture initial
cross join lateral (
  select (initial.evidence - 'checksum')
    || '{"input":{"subtotalMinor":"20000"}}'::jsonb as payload
) changed
where initial.phase = 'calculation';

insert into public.calculation_definitions (
  id, workspace_id, key, labels
) values (
  '34210000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture_total', '{"en":"Fixture total","fr":"Total fictif"}'
);
insert into public.calculation_versions (
  id, workspace_id, calculation_definition_id, version, semantic_version,
  status, input_schema, output_schema, expression_ast, rounding_policy,
  resource_limits, fixtures, engine_version, checksum,
  validation_evidence, fixture_evidence, created_by
) values (
  '34200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '34210000-0000-4000-8000-000000000001', 1, '1.0.0', 'draft',
  '{"type":"object"}', '{"type":"object"}',
  '{"type":"field","path":"subtotalMinor"}',
  '{"mode":"half_up","scale":0}', '{"max_nodes":100}', '[]',
  'fixture-calculation-v1',
  (select definition_checksum from pg_temp.runtime_fixture where phase = 'calculation'),
  null, null,
  '31000000-0000-4000-8000-000000000001'
);

update public.calculation_versions version
set status = 'validated',
    validation_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'validator', 'fixture-calculation-validator-v1',
      'artifactChecksum', version.checksum
    )
where version.id = '34200000-0000-4000-8000-000000000001';
update public.calculation_versions version
set status = 'test_passed',
    fixture_evidence = pg_catalog.jsonb_build_object(
      'passed', true, 'runner', 'fixture-calculation-runner-v1',
      'artifactChecksum', version.checksum,
      'tests', pg_catalog.jsonb_build_array('fixture-total')
    )
where version.id = '34200000-0000-4000-8000-000000000001';
insert into public.approval_records (
  id, workspace_id, artifact_type, artifact_key, artifact_version,
  artifact_id, artifact_checksum, approval_type, decision, decided_by,
  professional_role, professional_organization, conditions,
  attachment_reference, idempotency_key, reason
) values (
  '34220000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'calculation', 'formula.fixture_total', 1,
  '34200000-0000-4000-8000-000000000001',
  (select definition_checksum from pg_temp.runtime_fixture where phase = 'calculation'),
  'formula_review', 'approved', '31000000-0000-4000-8000-000000000001',
  'fixture_reviewer', 'Synthetic Review Lab', '{"fixture":true}',
  'fixture://calculation/runtime', 'm4-runtime-calculation-approval',
  'Approve rolled-back runtime calculation fixture'
);
update public.calculation_versions version
set status = 'approved',
    approval_record_id = '34220000-0000-4000-8000-000000000001'
where version.id = '34200000-0000-4000-8000-000000000001';
update public.calculation_versions version
set status = 'active',
    activated_by = '31000000-0000-4000-8000-000000000001',
    activated_at = pg_catalog.statement_timestamp()
where version.id = '34200000-0000-4000-8000-000000000001';

-- 22. Client-tampered calculation evidence is rejected before persistence.
select pg_temp.authenticate_service();
set local role service_role;
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'calculation',
      '34200000-0000-4000-8000-000000000001', null, null,
      (select evidence || '{"output":{"totalMinor":"99999"}}'::jsonb
       from pg_temp.runtime_fixture where phase = 'calculation'),
      'm4-runtime-tampered', 'm4-runtime-tampered',
      '34300000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  'runtime_evidence.checksum_invalid',
  'M4-CALC-AC-004 tampered execution evidence fails closed'
);
reset role;

-- 23. Authenticated callers cannot forge a trusted runtime receipt.
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'app.m4_record_runtime_evidence(uuid,uuid,text,uuid,uuid,uuid,jsonb,text,text,uuid)',
    'EXECUTE'
  ),
  'M4-CALC-AC-004 browser cannot invoke trusted evidence persistence'
);

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.runtime_results
select 'initial', result.evidence_id
from app.m4_record_runtime_evidence(
  '10000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001', 'calculation',
  '34200000-0000-4000-8000-000000000001', null, null,
  (select evidence from pg_temp.runtime_fixture where phase = 'calculation'),
  'm4-runtime-calc-initial', 'm4-runtime-calc-initial',
  '34300000-0000-4000-8000-000000000002'
) result;

-- 24. The service records actor/workspace/version-bound exact evidence.
select extensions.ok(
  exists (
    select 1 from public.runtime_evidence_records evidence
    where evidence.id = (select evidence_id from pg_temp.runtime_results where phase = 'initial')
      and evidence.workspace_id = '10000000-0000-4000-8000-000000000001'
      and evidence.actor_user_id = '31000000-0000-4000-8000-000000000001'
      and evidence.calculation_version_id = '34200000-0000-4000-8000-000000000001'
      and evidence.snapshot_checksum = evidence.snapshot ->> 'checksum'
  ),
  'T-CALC-001 trusted runtime result preserves exact version and checksum'
);

insert into pg_temp.runtime_results
select 'replay', result.evidence_id
from app.m4_record_runtime_evidence(
  '10000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001', 'calculation',
  '34200000-0000-4000-8000-000000000001', null, null,
  (select evidence from pg_temp.runtime_fixture where phase = 'calculation'),
  'm4-runtime-calc-initial', 'm4-runtime-calc-replay',
  '34300000-0000-4000-8000-000000000002'
) result;

-- 25. Runtime evidence retry returns the same receipt.
select extensions.is(
  (select evidence_id from pg_temp.runtime_results where phase = 'replay'),
  (select evidence_id from pg_temp.runtime_results where phase = 'initial'),
  'M4-CALC-AC-004 exact runtime evidence replay is idempotent'
);

-- 26. One actor key cannot be reused for a different valid execution result.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'calculation',
      '34200000-0000-4000-8000-000000000001', null, null,
      (select evidence from pg_temp.runtime_fixture where phase = 'calculation-conflict'),
      'm4-runtime-calc-initial', 'm4-runtime-calc-conflict',
      '34300000-0000-4000-8000-000000000003'
    )
  $$,
  '23505',
  'runtime_evidence.idempotency_conflict',
  'M4-CALC-AC-004 conflicting runtime replay is rejected'
);

-- 27. Service authority cannot manufacture permissions for a foreign actor/workspace pair.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '20000000-0000-4000-8000-000000000002',
      '31000000-0000-4000-8000-000000000001', 'calculation',
      '34200000-0000-4000-8000-000000000001', null, null,
      (select evidence from pg_temp.runtime_fixture where phase = 'calculation'),
      'm4-runtime-foreign-workspace', 'm4-runtime-foreign-workspace',
      '34300000-0000-4000-8000-000000000004'
    )
  $$,
  '42501',
  'runtime_evidence.permission_denied',
  'T-TEN-001 trusted recorder still enforces actor membership and permission'
);

-- 28. Trusted receipts have a bounded 24-hour consumption lifetime.
select extensions.ok(
  exists (
    select 1 from public.runtime_evidence_records evidence
    where evidence.id = (select evidence_id from pg_temp.runtime_results where phase = 'initial')
      and evidence.expires_at > evidence.created_at + interval '23 hours 59 minutes'
      and evidence.expires_at <= evidence.created_at + interval '24 hours 1 minute'
  ),
  'M4-CALC-AC-004 runtime receipt expiry is bounded'
);
reset role;

-- 29. Runtime evidence is append-only after the service records it.
select extensions.throws_ok(
  $$
    update public.runtime_evidence_records set expires_at = expires_at + interval '1 day'
    where id = (select evidence_id from pg_temp.runtime_results where phase = 'initial')
  $$,
  '55000',
  'runtime_evidence_records is append-only',
  'M4-CALC-AC-004 exact execution evidence cannot be rewritten'
);

-- 30. Service-recorded evidence emits actor-attributed audit proof.
select extensions.ok(
  exists (
    select 1 from public.audit_events event
    where event.workspace_id = '10000000-0000-4000-8000-000000000001'
      and event.entity_id = (select evidence_id from pg_temp.runtime_results where phase = 'initial')
      and event.action = 'runtime_evidence.recorded'
      and event.actor_user_id = '31000000-0000-4000-8000-000000000001'
      and event.metadata ->> 'serviceRecorded' = 'true'
  ),
  'T-AUD-001 trusted runtime receipt is audited with actor provenance'
);

-- 31. Lifecycle commands retain their command and audit evidence exactly once.
select extensions.ok(
  (select pg_catalog.count(*) from public.configuration_artifact_commands
   where artifact_id = (select numbering_version_id from pg_temp.numbering_results where phase = 'v1')) = 3
  and (select pg_catalog.count(*) from public.audit_events
       where entity_id = (select numbering_version_id from pg_temp.numbering_results where phase = 'v1')
         and action in (
           'configuration.numbering_version_created',
           'configuration.artifact_activate',
           'configuration.artifact_retire'
         )) = 3,
  'M4-CFG-AC-001 lifecycle command and audit histories are exactly-once'
);

-- 32. The database-level uniqueness contract prevents duplicate formatted values.
select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_index index_definition
    where index_definition.indrelid = 'public.number_allocations'::pg_catalog.regclass
      and index_definition.indisunique
      and pg_catalog.pg_get_indexdef(index_definition.indexrelid)
        like '%(workspace_id, formatted_value)%'
  ),
  'M4-NUM-AC-005 formatted official values are workspace-unique'
);

-- A foreign definition gives the RLS test a positive row to hide.
insert into public.numbering_definitions (
  id, workspace_id, key, labels
) values (
  '34400000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000002',
  'foreign_fixture', '{"en":"Foreign fixture","fr":"Fixture etrangere"}'
);
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 33. Forced RLS hides otherwise valid configuration rows in another workspace.
select extensions.is(
  (select pg_catalog.count(*) from public.numbering_definitions
   where id = '34400000-0000-4000-8000-000000000001'),
  0::bigint,
  'T-TEN-001 configuration reads are isolated by authenticated workspace membership'
);

reset role;

-- 34. Future activation keeps a bounded historical assignment and one active successor.
select extensions.ok(
  exists (
    select 1
    from public.tax_pack_assignments assignment
    where assignment.tax_pack_version_id = '34510000-0000-4000-8000-000000000001'
      and assignment.effective_from = date '2026-01-01'
      and assignment.superseded_effective_to = date '2026-12-31'
      and assignment.retired_at is not null
  )
  and exists (
    select 1
    from public.tax_pack_assignments assignment
    where assignment.tax_pack_version_id = '34510000-0000-4000-8000-000000000002'
      and assignment.effective_from = date '2027-01-01'
      and assignment.superseded_effective_to is null
      and assignment.retired_at is null
  )
  and (select status from public.tax_pack_versions
       where id = '34510000-0000-4000-8000-000000000001') = 'retired'
  and (select status from public.tax_pack_versions
       where id = '34510000-0000-4000-8000-000000000002') = 'active',
  'M4-TAX-AC-003 successor activation preserves the exact historical effective window'
);

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.runtime_results
select 'tax-historical', result.evidence_id
from app.m4_record_runtime_evidence(
  '10000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001', 'tax',
  '34510000-0000-4000-8000-000000000001',
  (select id from public.tax_pack_assignments
   where tax_pack_version_id = '34510000-0000-4000-8000-000000000001'),
  null,
  (select evidence from pg_temp.runtime_fixture where phase = 'tax-v1-historical'),
  'm4-runtime-tax-historical', 'm4-runtime-tax-historical',
  '34540000-0000-4000-8000-000000000001'
) result;

-- 35. A retired pack remains executable only through its retained historical assignment.
select extensions.ok(
  exists (
    select 1 from public.runtime_evidence_records evidence
    where evidence.id = (
      select evidence_id from pg_temp.runtime_results where phase = 'tax-historical'
    )
      and evidence.tax_pack_version_id = '34510000-0000-4000-8000-000000000001'
      and evidence.tax_assignment_id = (
        select id from public.tax_pack_assignments
        where tax_pack_version_id = '34510000-0000-4000-8000-000000000001'
      )
  ),
  'M4-TAX-AC-002 historical transactions retain their exact retired pack and assignment'
);

-- 36. The historical assignment cannot authorize a transaction after its cutover date.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'tax',
      '34510000-0000-4000-8000-000000000001',
      (select id from public.tax_pack_assignments
       where tax_pack_version_id = '34510000-0000-4000-8000-000000000001'),
      null,
      (select evidence from pg_temp.runtime_fixture where phase = 'tax-v1-future'),
      'm4-runtime-tax-old-future', 'm4-runtime-tax-old-future',
      '34540000-0000-4000-8000-000000000002'
    )
  $$,
  '23514',
  'runtime_evidence.tax_assignment_invalid',
  'M4-TAX-AC-003 superseded assignment fails closed for future transactions'
);

insert into pg_temp.runtime_results
select 'tax-future', result.evidence_id
from app.m4_record_runtime_evidence(
  '10000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001', 'tax',
  '34510000-0000-4000-8000-000000000002',
  (select id from public.tax_pack_assignments
   where tax_pack_version_id = '34510000-0000-4000-8000-000000000002'),
  null,
  (select evidence from pg_temp.runtime_fixture where phase = 'tax-v2-future'),
  'm4-runtime-tax-future', 'm4-runtime-tax-future',
  '34540000-0000-4000-8000-000000000003'
) result;

-- 37. The same future transaction resolves only through the active successor assignment.
select extensions.ok(
  exists (
    select 1 from public.runtime_evidence_records evidence
    where evidence.id = (
      select evidence_id from pg_temp.runtime_results where phase = 'tax-future'
    )
      and evidence.tax_pack_version_id = '34510000-0000-4000-8000-000000000002'
      and evidence.snapshot ->> 'transactionDate' = '2027-01-02'
  ),
  'M4-TAX-AC-002 future transactions pin the active successor tax evidence'
);

reset role;

-- Workspace configuration import installs immutable test-passed document
-- rows. Approval and activation remain separate authenticated commands.
insert into public.document_types (
  id, workspace_id, key, version, display_name, labels, field_schema,
  field_schema_checksum, numbering_definition_version_id,
  preview_generation_enabled, official_generation_enabled,
  production_enabled, activation_status, activation_gates, checksum,
  validation_evidence, fixture_evidence, status
)
select
  '34600000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture.provisioned', 1, 'Provisioned fixture document',
  '{"en":"Provisioned fixture document","fr":"Document fictif importe"}',
  '{"type":"object","additionalProperties":false,"properties":{}}',
  repeat('7', 64), version.id,
  false, false, true, 'test_passed', '[]', repeat('6', 64),
  pg_catalog.jsonb_build_object(
    'passed', true, 'validator', 'document-import-validator-v1',
    'artifactChecksum', repeat('6', 64)
  ),
  pg_catalog.jsonb_build_object(
    'passed', true, 'runner', 'document-import-fixtures-v1',
    'artifactChecksum', repeat('6', 64),
    'tests', pg_catalog.jsonb_build_array('document-type-import')
  ),
  'active'
from public.numbering_definition_versions version
where version.workspace_id = '10000000-0000-4000-8000-000000000001'
order by version.version, version.id
limit 1;

insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_css, source_checksum, source_bundle_checksum,
  asset_manifest, font_manifest, renderer_version, field_schema,
  field_schema_checksum, production_approved, watermark, activation_status,
  validation_evidence, fixture_evidence, status
) values (
  '34610000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '34600000-0000-4000-8000-000000000001', 1, 'en-CA',
  'tenant_approved',
  '<!doctype html><html><body><h1>{{ document.fields.title }}</h1></body></html>',
  'body { font-family: sans-serif; }', repeat('9', 64), repeat('8', 64),
  '{}', '{}', 'fixture-pdf-v1',
  '{"type":"object","additionalProperties":false,"properties":{}}',
  repeat('7', 64), false, null, 'test_passed',
  '{"passed":true,"validator":"template-import-validator-v1","artifactChecksum":"8888888888888888888888888888888888888888888888888888888888888888"}',
  '{"passed":true,"runner":"template-import-fixtures-v1","artifactChecksum":"8888888888888888888888888888888888888888888888888888888888888888","tests":["template-import"]}',
  'active'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

insert into pg_temp.approval_results
select 'document-type', result.*
from app.m4_record_artifact_approval(
  '10000000-0000-4000-8000-000000000001', 'document_type',
  '34600000-0000-4000-8000-000000000001', repeat('6', 64),
  'legal', 'approved', 'm4-document-type-approval',
  'Approve exact imported document type', 'legal_reviewer',
  'Fixture Review Lab', '{"scope":"fixture"}',
  'fixture://document-type-approval', null, null, null,
  'm4-document-type-approval',
  '34620000-0000-4000-8000-000000000001'
) result;

insert into pg_temp.approval_results
select 'document-template', result.*
from app.m4_record_artifact_approval(
  '10000000-0000-4000-8000-000000000001', 'document_template',
  '34610000-0000-4000-8000-000000000001', repeat('8', 64),
  'legal', 'approved', 'm4-document-template-approval',
  'Approve exact imported document template', 'legal_reviewer',
  'Fixture Review Lab', '{"scope":"fixture"}',
  'fixture://document-template-approval', null, null, null,
  'm4-document-template-approval',
  '34620000-0000-4000-8000-000000000002'
) result;

-- 42. Both imported artifacts receive exact checksum-bound approvals.
select extensions.ok(
  exists (
    select 1 from public.approval_records approval
    where approval.id = (
      select approval_record_id from pg_temp.approval_results
      where phase = 'document-type'
    )
      and approval.artifact_type = 'document_type'
      and approval.artifact_key = 'document.fixture_provisioned'
      and approval.artifact_checksum = repeat('6', 64)
  )
  and exists (
    select 1 from public.approval_records approval
    where approval.id = (
      select approval_record_id from pg_temp.approval_results
      where phase = 'document-template'
    )
      and approval.artifact_type = 'document_template'
      and approval.artifact_key = 'template.fixture_provisioned.en_ca'
      and approval.artifact_checksum = repeat('8', 64)
  ),
  'M4-CFG-AC-005 imported document artifacts receive exact approvals'
);

insert into pg_temp.transition_results
select 'document-template-active', result.*
from app.m4_transition_artifact_version(
  '10000000-0000-4000-8000-000000000001', 'document_template',
  '34610000-0000-4000-8000-000000000001', repeat('8', 64),
  'active', '{"expectedVersion":1}', 'm4-document-template-activate',
  'Activate exact imported document template',
  'm4-document-template-activate',
  '34630000-0000-4000-8000-000000000001'
) result;

insert into pg_temp.transition_results
select 'document-type-active', result.*
from app.m4_transition_artifact_version(
  '10000000-0000-4000-8000-000000000001', 'document_type',
  '34600000-0000-4000-8000-000000000001', repeat('6', 64),
  'active', '{"expectedVersion":1}', 'm4-document-type-activate',
  'Activate exact imported document type', 'm4-document-type-activate',
  '34630000-0000-4000-8000-000000000002'
) result;

-- 43. Activation preserves exact approval, evidence, and production gating.
select extensions.ok(
  exists (
    select 1 from public.document_types document_type
    where document_type.id = '34600000-0000-4000-8000-000000000001'
      and document_type.activation_status = 'active'
      and document_type.production_enabled
      and document_type.official_generation_enabled
      and document_type.approval_record_id = (
        select approval_record_id from pg_temp.approval_results
        where phase = 'document-type'
      )
  )
  and exists (
    select 1 from public.document_template_versions template
    where template.id = '34610000-0000-4000-8000-000000000001'
      and template.activation_status = 'active'
      and template.production_approved
      and template.approval_record_id = (
        select approval_record_id from pg_temp.approval_results
        where phase = 'document-template'
      )
  ),
  'M4-CFG-AC-002 exact imported document type and template activate'
);

insert into pg_temp.transition_results
select 'document-type-retired', result.*
from app.m4_transition_artifact_version(
  '10000000-0000-4000-8000-000000000001', 'document_type',
  '34600000-0000-4000-8000-000000000001', repeat('6', 64),
  'retired', '{"expectedVersion":1}', 'm4-document-type-retire',
  'Retire exact imported document type', 'm4-document-type-retire',
  '34630000-0000-4000-8000-000000000003'
) result;

insert into pg_temp.transition_results
select 'document-template-retired', result.*
from app.m4_transition_artifact_version(
  '10000000-0000-4000-8000-000000000001', 'document_template',
  '34610000-0000-4000-8000-000000000001', repeat('8', 64),
  'retired', '{"expectedVersion":1}', 'm4-document-template-retire',
  'Retire exact imported document template',
  'm4-document-template-retire',
  '34630000-0000-4000-8000-000000000004'
) result;

-- 44. Retirement disables official use before approval revocation.
select extensions.ok(
  (select activation_status = 'retired' and not official_generation_enabled
   from public.document_types
   where id = '34600000-0000-4000-8000-000000000001')
  and (select activation_status = 'retired'
       from public.document_template_versions
       where id = '34610000-0000-4000-8000-000000000001'),
  'M4-CFG-AC-003 retirement disables both exact document artifacts'
);

insert into pg_temp.approval_results
select 'document-type-revoked', result.*
from app.m4_record_artifact_approval(
  '10000000-0000-4000-8000-000000000001', 'document_type',
  '34600000-0000-4000-8000-000000000001', repeat('6', 64),
  'legal', 'revoked', 'm4-document-type-revoke',
  'Revoke retired document type approval', null, null, '{}', null,
  null, null,
  (select approval_record_id from pg_temp.approval_results
   where phase = 'document-type'),
  'm4-document-type-revoke',
  '34640000-0000-4000-8000-000000000001'
) result;

insert into pg_temp.approval_results
select 'document-template-revoked', result.*
from app.m4_record_artifact_approval(
  '10000000-0000-4000-8000-000000000001', 'document_template',
  '34610000-0000-4000-8000-000000000001', repeat('8', 64),
  'legal', 'revoked', 'm4-document-template-revoke',
  'Revoke retired document template approval', null, null, '{}', null,
  null, null,
  (select approval_record_id from pg_temp.approval_results
   where phase = 'document-template'),
  'm4-document-template-revoke',
  '34640000-0000-4000-8000-000000000002'
) result;

reset role;
-- 45. Revocations are append-only and invalidate both exact approvals.
select extensions.ok(
  not app.m4_exact_approval_valid(
    '10000000-0000-4000-8000-000000000001',
    (select approval_record_id from pg_temp.approval_results
     where phase = 'document-type'),
    'document_type', 'document.fixture_provisioned', 1,
    '34600000-0000-4000-8000-000000000001', repeat('6', 64)
  )
  and not app.m4_exact_approval_valid(
    '10000000-0000-4000-8000-000000000001',
    (select approval_record_id from pg_temp.approval_results
     where phase = 'document-template'),
    'document_template', 'template.fixture_provisioned.en_ca', 1,
    '34610000-0000-4000-8000-000000000001', repeat('8', 64)
  ),
  'M4-CFG-AC-005 retired document approvals revoke without rewriting history'
);

set local role authenticated;
-- 46. A production-disabled placeholder document type cannot be approved.
select extensions.throws_ok(
  $$
    select * from app.m4_record_artifact_approval(
      '10000000-0000-4000-8000-000000000001', 'document_type',
      '81000000-0000-4000-8000-000000000001',
      (select checksum from public.document_types
       where id = '81000000-0000-4000-8000-000000000001'),
      'legal', 'approved', 'm4-placeholder-type-approval',
      'Reject placeholder document type approval', null, null, '{}', null,
      null, null, null, 'm4-placeholder-type-approval',
      '34650000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  'configuration artifact is production-disabled',
  'M4-DOC-AC-004 production-disabled document types cannot be approved'
);

-- 47. A synthetic watermarked template cannot enter the legal lifecycle.
select extensions.throws_ok(
  $$
    select * from app.m4_record_artifact_approval(
      '10000000-0000-4000-8000-000000000001', 'document_template',
      '91000000-0000-4000-8000-000000000001',
      (select source_bundle_checksum from public.document_template_versions
       where id = '91000000-0000-4000-8000-000000000001'),
      'legal', 'approved', 'm4-placeholder-template-approval',
      'Reject placeholder document template approval', null, null, '{}', null,
      null, null, null, 'm4-placeholder-template-approval',
      '34650000-0000-4000-8000-000000000002'
    )
  $$,
  '23514',
  'configuration artifact is production-disabled',
  'M4-DOC-AC-004 synthetic legal placeholders cannot be approved or activated'
);

reset role;

-- Canonical, deal-bound runtime inputs are built only by the authenticated
-- loader and are independently re-derived by the service recorder.
insert into public.deals (
  id, workspace_id, deal_type_key, currency_code, owner_membership_id,
  notes, idempotency_key, command_fingerprint, created_by
) values
  (
    '34700000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001', 'retail.cash', 'CAD',
    '41000000-0000-4000-8000-000000000001',
    'Canonical runtime input fixture one', 'm4-runtime-bound-deal-one',
    repeat('7', 64), '31000000-0000-4000-8000-000000000001'
  ),
  (
    '34700000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001', 'retail.cash', 'CAD',
    '41000000-0000-4000-8000-000000000001',
    'Canonical runtime input fixture two', 'm4-runtime-bound-deal-two',
    repeat('8', 64), '31000000-0000-4000-8000-000000000001'
  );

insert into public.deal_line_items (
  id, workspace_id, deal_id, key, item_type, label, quantity_text,
  unit_amount_minor, currency_code, tax_classification_key, sort_order,
  created_by, updated_by
) values
  (
    '34710000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '34700000-0000-4000-8000-000000000001', 'vehicle_price', 'vehicle',
    'Vehicle price', '1', 1000000, 'CAD', null, 10,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '34710000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '34700000-0000-4000-8000-000000000001', 'taxable_fee', 'fee',
    'Taxable fee', '1', 20000, 'CAD', 'taxable', 20,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '34710000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '34700000-0000-4000-8000-000000000001', 'taxable_discount', 'discount',
    'Taxable discount', '1', -50000, 'CAD', 'taxable', 30,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '34710000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000001',
    '34700000-0000-4000-8000-000000000001', 'non_taxable_fee', 'fee',
    'Non-taxable fee', '1', 10000, 'CAD', 'non_taxable', 40,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    '34710000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000001',
    '34700000-0000-4000-8000-000000000001', 'non_taxable_discount', 'discount',
    'Non-taxable discount', '1', -15000, 'CAD', 'non_taxable', 50,
    '31000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001'
  );

create temporary table pg_temp.bound_runtime_fixture (
  phase text primary key,
  evidence jsonb not null
);
create temporary table pg_temp.bound_runtime_results (
  phase text primary key,
  evidence_id uuid not null
);
grant all on pg_temp.bound_runtime_fixture, pg_temp.bound_runtime_results
to authenticated, service_role;

with context as (
  select app.m4_deal_source_snapshot(
    '10000000-0000-4000-8000-000000000001',
    '34700000-0000-4000-8000-000000000001'
  ) as value
), unsigned as (
  select (fixture.evidence - 'checksum') || pg_catalog.jsonb_build_object(
    'input', context.value,
    'inputBinding', pg_catalog.jsonb_build_object(
      'mapperVersion', 'deal-runtime-input-v1',
      'dealContextChecksum', app.m4_canonical_fingerprint(context.value),
      'inputProjectionChecksum', app.m4_canonical_fingerprint(context.value)
    )
  ) as value
  from pg_temp.runtime_fixture fixture
  cross join context
  where fixture.phase = 'calculation'
)
insert into pg_temp.bound_runtime_fixture (phase, evidence)
select 'calculation', value || pg_catalog.jsonb_build_object(
  'checksum', app.m4_canonical_fingerprint(value)
)
from unsigned;

with context as (
  select app.m4_deal_source_snapshot(
    '10000000-0000-4000-8000-000000000001',
    '34700000-0000-4000-8000-000000000001'
  ) as value
), projection as (
  select value, app.m4_deal_tax_input(value, 'CA') as tax_input
  from context
), unsigned as (
  select (fixture.evidence - 'checksum') || pg_catalog.jsonb_build_object(
    'input', projection.tax_input,
    'inputBinding', pg_catalog.jsonb_build_object(
      'mapperVersion', 'deal-runtime-input-v1',
      'dealContextChecksum', app.m4_canonical_fingerprint(projection.value),
      'inputProjectionChecksum', app.m4_canonical_fingerprint(projection.tax_input)
    )
  ) as value
  from pg_temp.runtime_fixture fixture
  cross join projection
  where fixture.phase = 'tax-v2-future'
)
insert into pg_temp.bound_runtime_fixture (phase, evidence)
select 'tax', value || pg_catalog.jsonb_build_object(
  'checksum', app.m4_canonical_fingerprint(value)
)
from unsigned;

with unsigned as (
  select (evidence - 'checksum') || pg_catalog.jsonb_build_object(
    'input', (evidence -> 'input') || '{"vehicle_price_minor":"1"}'::jsonb
  ) as value
  from pg_temp.bound_runtime_fixture where phase = 'tax'
)
insert into pg_temp.bound_runtime_fixture (phase, evidence)
select 'tax-total-drift', value || pg_catalog.jsonb_build_object(
  'checksum', app.m4_canonical_fingerprint(value)
)
from unsigned;

with unsigned as (
  select (evidence - 'checksum') || '{"currency":"USD"}'::jsonb as value
  from pg_temp.bound_runtime_fixture where phase = 'tax'
)
insert into pg_temp.bound_runtime_fixture (phase, evidence)
select 'tax-currency-drift', value || pg_catalog.jsonb_build_object(
  'checksum', app.m4_canonical_fingerprint(value)
)
from unsigned;

with unsigned as (
  select (evidence - 'checksum') || '{"jurisdiction":"CA-QC"}'::jsonb as value
  from pg_temp.bound_runtime_fixture where phase = 'tax'
)
insert into pg_temp.bound_runtime_fixture (phase, evidence)
select 'tax-jurisdiction-drift', value || pg_catalog.jsonb_build_object(
  'checksum', app.m4_canonical_fingerprint(value)
)
from unsigned;

with unsigned as (
  select (evidence - 'checksum') || '{"context":"wholesale"}'::jsonb as value
  from pg_temp.bound_runtime_fixture where phase = 'tax'
)
insert into pg_temp.bound_runtime_fixture (phase, evidence)
select 'tax-context-drift', value || pg_catalog.jsonb_build_object(
  'checksum', app.m4_canonical_fingerprint(value)
)
from unsigned;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 48. Loader output is portable, canonical, and exposes the deal currency.
select extensions.ok(
  exists (
    select 1
    from app.m4_load_deal_runtime_input(
      '10000000-0000-4000-8000-000000000001',
      '34700000-0000-4000-8000-000000000001', 'CA'
    ) loaded
    where loaded.deal_currency_code = 'CAD'
      and loaded.calculation_input_checksum = loaded.deal_context_checksum
      and loaded.calculation_input_checksum ~ '^[a-f0-9]{64}$'
      and loaded.tax_input_checksum ~ '^[a-f0-9]{64}$'
      and pg_catalog.jsonb_typeof(loaded.calculation_input) = 'object'
      and pg_catalog.jsonb_typeof(loaded.tax_input) = 'object'
  ),
  'M4-CALC-AC-004 loader returns canonical deal runtime projections'
);
reset role;

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.bound_runtime_results
select 'calculation', result.evidence_id
from app.m4_record_runtime_evidence(
  '10000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001', 'calculation',
  '34200000-0000-4000-8000-000000000001', null,
  '34700000-0000-4000-8000-000000000001',
  (select evidence from pg_temp.bound_runtime_fixture where phase = 'calculation'),
  'm4-bound-calc-valid', 'm4-bound-calc-valid',
  '34710000-0000-4000-8000-000000000001'
) result;

-- 49. Valid calculation evidence pins the exact deal-source checksum.
select extensions.ok(
  exists (
    select 1 from public.runtime_evidence_records evidence
    where evidence.id = (
      select evidence_id from pg_temp.bound_runtime_results where phase = 'calculation'
    )
      and evidence.deal_id = '34700000-0000-4000-8000-000000000001'
      and evidence.official_eligible
      and evidence.deal_context_checksum =
        evidence.snapshot -> 'inputBinding' ->> 'dealContextChecksum'
      and exists (
        select 1 from public.audit_events event
        where event.entity_id = evidence.id
          and event.action = 'runtime_evidence.recorded'
          and event.after_data -> 'officialEligible' = 'true'::jsonb
          and event.metadata -> 'officialEligible' = 'true'::jsonb
      )
  ),
  'M4-CALC-AC-004 calculation receipt is bound to canonical deal input'
);

-- 50. Deal-one input cannot manufacture a receipt for deal two.
select extensions.throws_ok(
  $$select * from app.m4_record_runtime_evidence(
    '10000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001', 'calculation',
    '34200000-0000-4000-8000-000000000001', null,
    '34700000-0000-4000-8000-000000000002',
    (select evidence from pg_temp.bound_runtime_fixture where phase = 'calculation'),
    'm4-bound-calc-wrong-deal', 'm4-bound-calc-wrong-deal',
    '34710000-0000-4000-8000-000000000002'
  )$$,
  '23514', 'runtime_evidence.calculation_input_binding_invalid',
  'M4-CALC-AC-004 calculation input cannot cross deal boundaries'
);

-- 51. Arbitrary non-deal previews cannot carry a manufactured binding.
select extensions.throws_ok(
  $$select * from app.m4_record_runtime_evidence(
    '10000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001', 'calculation',
    '34200000-0000-4000-8000-000000000001', null, null,
    (select evidence from pg_temp.bound_runtime_fixture where phase = 'calculation'),
    'm4-unbound-fake-binding', 'm4-unbound-fake-binding',
    '34710000-0000-4000-8000-000000000003'
  )$$,
  '23514', 'runtime_evidence.input_binding_invalid',
  'M4-CALC-AC-004 arbitrary previews remain explicitly non-official'
);

insert into pg_temp.bound_runtime_results
select 'tax', result.evidence_id
from app.m4_record_runtime_evidence(
  '10000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001', 'tax',
  '34510000-0000-4000-8000-000000000002',
  (select id from public.tax_pack_assignments
   where tax_pack_version_id = '34510000-0000-4000-8000-000000000002'),
  '34700000-0000-4000-8000-000000000001',
  (select evidence from pg_temp.bound_runtime_fixture where phase = 'tax'),
  'm4-bound-tax-valid', 'm4-bound-tax-valid',
  '34710000-0000-4000-8000-000000000004'
) result;

-- 52. Valid tax evidence pins the canonical projection and deal currency.
select extensions.ok(
  exists (
    select 1 from public.runtime_evidence_records evidence
    where evidence.id = (
      select evidence_id from pg_temp.bound_runtime_results where phase = 'tax'
    )
      and evidence.snapshot ->> 'currency' = 'CAD'
      and evidence.snapshot -> 'inputBinding' ->> 'mapperVersion'
        = 'deal-runtime-input-v1'
  ),
  'M4-TAX-AC-002 tax receipt is bound to the canonical deal projection'
);

-- 53. Re-signed client totals cannot replace canonical deal amounts.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'tax',
      '34510000-0000-4000-8000-000000000002',
      (select id from public.tax_pack_assignments
       where tax_pack_version_id = '34510000-0000-4000-8000-000000000002'),
      '34700000-0000-4000-8000-000000000001',
      (select evidence from pg_temp.bound_runtime_fixture
       where phase = 'tax-total-drift'),
      'm4-bound-tax-total-drift', 'm4-bound-tax-total-drift',
      '34710000-0000-4000-8000-000000000005'
    )
  $$,
  '23514', 'runtime_evidence.tax_input_binding_invalid',
  'M4-TAX-AC-002 deal-bound tax totals cannot be client-authored'
);

-- 54. Tax evidence currency must equal the authoritative deal currency.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'tax',
      '34510000-0000-4000-8000-000000000002',
      (select id from public.tax_pack_assignments
       where tax_pack_version_id = '34510000-0000-4000-8000-000000000002'),
      '34700000-0000-4000-8000-000000000001',
      (select evidence from pg_temp.bound_runtime_fixture
       where phase = 'tax-currency-drift'),
      'm4-bound-tax-currency-drift', 'm4-bound-tax-currency-drift',
      '34710000-0000-4000-8000-000000000006'
    )
  $$,
  '23514', 'runtime_evidence.tax_input_binding_invalid',
  'M4-TAX-AC-002 tax currency is derived from the authoritative deal'
);

-- 55. A valid checksum cannot substitute an unassigned jurisdiction.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'tax',
      '34510000-0000-4000-8000-000000000002',
      (select id from public.tax_pack_assignments
       where tax_pack_version_id = '34510000-0000-4000-8000-000000000002'),
      '34700000-0000-4000-8000-000000000001',
      (select evidence from pg_temp.bound_runtime_fixture
       where phase = 'tax-jurisdiction-drift'),
      'm4-bound-tax-jurisdiction-drift', 'm4-bound-tax-jurisdiction-drift',
      '34710000-0000-4000-8000-000000000007'
    )
  $$,
  '23514', 'runtime_evidence.tax_assignment_invalid',
  'M4-TAX-AC-002 tax jurisdiction remains assignment-bound'
);

-- 56. A valid checksum cannot substitute an unassigned transaction context.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'tax',
      '34510000-0000-4000-8000-000000000002',
      (select id from public.tax_pack_assignments
       where tax_pack_version_id = '34510000-0000-4000-8000-000000000002'),
      '34700000-0000-4000-8000-000000000001',
      (select evidence from pg_temp.bound_runtime_fixture
       where phase = 'tax-context-drift'),
      'm4-bound-tax-context-drift', 'm4-bound-tax-context-drift',
      '34710000-0000-4000-8000-000000000008'
    )
  $$,
  '23514', 'runtime_evidence.tax_assignment_invalid',
  'M4-TAX-AC-002 tax context remains assignment-bound'
);

reset role;

-- Candidate preview executions remain useful for validation and operator
-- testing, but their recording-time provenance can never become official by
-- activating the same immutable version before the receipt expires.
alter table public.calculation_versions
  disable trigger calculation_versions_lifecycle_guard;
alter table public.tax_pack_versions
  disable trigger tax_pack_versions_lifecycle_guard;
update public.calculation_versions
set status = 'test_passed'
where id = '34200000-0000-4000-8000-000000000001';
update public.tax_pack_versions
set status = 'test_passed'
where id = '34510000-0000-4000-8000-000000000002';
alter table public.calculation_versions
  enable trigger calculation_versions_lifecycle_guard;
alter table public.tax_pack_versions
  enable trigger tax_pack_versions_lifecycle_guard;

insert into pg_temp.runtime_fixture (phase, definition, definition_checksum, evidence)
select
  'tax-candidate', source.definition, source.definition_checksum,
  unsigned.value || pg_catalog.jsonb_build_object(
    'checksum', app.m4_canonical_fingerprint(unsigned.value)
  )
from pg_temp.runtime_fixture source
cross join lateral (
  select (source.evidence - 'checksum') || pg_catalog.jsonb_build_object(
    'assignmentId', null
  ) as value
) unsigned
where source.phase = 'tax-v2-future';

insert into pg_temp.runtime_fixture (phase, definition, definition_checksum, evidence)
select
  'tax-candidate-short-override', source.definition,
  source.definition_checksum,
  unsigned.value || pg_catalog.jsonb_build_object(
    'checksum', app.m4_canonical_fingerprint(unsigned.value)
  )
from pg_temp.runtime_fixture source
cross join lateral (
  select (source.evidence - 'checksum') || pg_catalog.jsonb_build_object(
    'override', pg_catalog.jsonb_build_object('reason', 'x'),
    'overrideReason', 'x'
  ) as value
) unsigned
where source.phase = 'tax-candidate';

insert into pg_temp.runtime_fixture (phase, definition, definition_checksum, evidence)
select
  'tax-candidate-spoofed-override', source.definition,
  source.definition_checksum,
  unsigned.value || pg_catalog.jsonb_build_object(
    'checksum', app.m4_canonical_fingerprint(unsigned.value)
  )
from pg_temp.runtime_fixture source
cross join lateral (
  select (source.evidence - 'checksum') || pg_catalog.jsonb_build_object(
    'override', pg_catalog.jsonb_build_object(
      'kind', 'trade_in_eligibility',
      'permissionGranted', false,
      'permissionKey', 'tax.override',
      'reason', 'Fixture candidate override',
      'recentStrongAuth', true,
      'reviewReference', 'fixture-review-001'
    ),
    'overrideReason', 'Fixture candidate override'
  ) as value
) unsigned
where source.phase = 'tax-candidate';

select pg_temp.authenticate_service();
set local role service_role;
insert into pg_temp.runtime_results
select 'candidate-calculation', result.evidence_id
from app.m4_record_runtime_evidence(
  '10000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001', 'calculation',
  '34200000-0000-4000-8000-000000000001', null, null,
  (select evidence from pg_temp.runtime_fixture where phase = 'calculation'),
  'm4-candidate-calculation', 'm4-candidate-calculation',
  '34800000-0000-4000-8000-000000000001'
) result;
insert into pg_temp.runtime_results
select 'candidate-tax', result.evidence_id
from app.m4_record_runtime_evidence(
  '10000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001', 'tax',
  '34510000-0000-4000-8000-000000000002', null, null,
  (select evidence from pg_temp.runtime_fixture where phase = 'tax-candidate'),
  'm4-candidate-tax', 'm4-candidate-tax',
  '34800000-0000-4000-8000-000000000002'
) result;

-- 57. A candidate tax pack cannot borrow an active assignment while it is
-- being evaluated outside the activation lifecycle.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'tax',
      '34510000-0000-4000-8000-000000000002',
      (select id from public.tax_pack_assignments
       where tax_pack_version_id = '34510000-0000-4000-8000-000000000002'),
      null,
      (select evidence from pg_temp.runtime_fixture where phase = 'tax-v2-future'),
      'm4-candidate-tax-assignment', 'm4-candidate-tax-assignment',
      '34800000-0000-4000-8000-000000000003'
    )
  $$,
  '23514',
  'runtime_evidence.tax_invalid',
  'M4-TAX-AC-002 candidate tax evidence is assignment-unbound'
);

-- 58. Even the trusted service cannot record an override with a professional
-- reason shorter than the exact runtime contract.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'tax',
      '34510000-0000-4000-8000-000000000002', null, null,
      (select evidence from pg_temp.runtime_fixture
       where phase = 'tax-candidate-short-override'),
      'm4-candidate-tax-short-override',
      'm4-candidate-tax-short-override',
      '34800000-0000-4000-8000-000000000004'
    )
  $$,
  '23514',
  'runtime_evidence.tax_override_invalid',
  'M4-TAX-AC-002 override evidence requires a normalized reason of at least three characters'
);

-- 59. A reason alone cannot disguise an override whose trusted permission or
-- recent-auth facts do not match the exact runtime contract.
select extensions.throws_ok(
  $$
    select * from app.m4_record_runtime_evidence(
      '10000000-0000-4000-8000-000000000001',
      '31000000-0000-4000-8000-000000000001', 'tax',
      '34510000-0000-4000-8000-000000000002', null, null,
      (select evidence from pg_temp.runtime_fixture
       where phase = 'tax-candidate-spoofed-override'),
      'm4-candidate-tax-spoofed-override',
      'm4-candidate-tax-spoofed-override',
      '34800000-0000-4000-8000-000000000005'
    )
  $$,
  '23514',
  'runtime_evidence.tax_override_invalid',
  'M4-TAX-AC-002 override evidence preserves exact permission and AAL2 facts'
);
reset role;

alter table public.calculation_versions
  disable trigger calculation_versions_lifecycle_guard;
alter table public.tax_pack_versions
  disable trigger tax_pack_versions_lifecycle_guard;
update public.calculation_versions
set status = 'active'
where id = '34200000-0000-4000-8000-000000000001';
update public.tax_pack_versions
set status = 'active'
where id = '34510000-0000-4000-8000-000000000002';
alter table public.calculation_versions
  enable trigger calculation_versions_lifecycle_guard;
alter table public.tax_pack_versions
  enable trigger tax_pack_versions_lifecycle_guard;

-- 60. Activation never upgrades preview-only receipts, and both validation
-- and issuance require the immutable eligibility bit rather than live status.
select extensions.ok(
  not exists (
    select 1 from public.runtime_evidence_records evidence
    where evidence.id in (
      select evidence_id from pg_temp.runtime_results
      where phase in ('candidate-calculation', 'candidate-tax')
    ) and evidence.official_eligible
  )
  and not exists (
    select 1
    from pg_temp.runtime_results result
    join public.audit_events event
      on event.entity_id = result.evidence_id
     and event.action = 'runtime_evidence.recorded'
    where result.phase in ('candidate-calculation', 'candidate-tax')
      and (
        event.after_data -> 'officialEligible' is distinct from 'false'::jsonb
        or event.metadata -> 'officialEligible' is distinct from 'false'::jsonb
      )
  )
  and pg_catalog.regexp_count(
    pg_catalog.pg_get_functiondef(
      'app.m4_validate_document(uuid,uuid,uuid,uuid,text,date,date,jsonb,jsonb,jsonb)'::pg_catalog.regprocedure
    ),
    'official_eligible'
  ) = 2
  and pg_catalog.regexp_count(
    pg_catalog.pg_get_functiondef(
      'app.request_official_document(uuid,text,uuid,uuid,uuid,text,date,date,jsonb,jsonb,jsonb,uuid,bigint,text,text,uuid)'::pg_catalog.regprocedure
    ),
    'official_eligible'
  ) = 2,
  'M4-CALC-AC-004 candidate receipts remain permanently preview-only'
);

-- 61. Approval mutation uses the exclusive side of the issuance lock key.
select extensions.ok(
  pg_catalog.pg_get_functiondef(
    'app.m4_record_artifact_approval(uuid,text,uuid,text,text,text,text,text,text,text,jsonb,text,timestamptz,timestamptz,uuid,text,uuid)'::regprocedure
  ) ~ '(?s)pg_advisory_xact_lock.*configuration_artifact.*p_artifact_type.*p_artifact_id',
  'M4-CFG-AC-005 approval changes hold the documented exclusive artifact lock'
);

-- 62. Activation shares the exact lock before its post-idempotency re-read.
select extensions.ok(
  source.definition
    ~ '(?s)pg_advisory_xact_lock_shared.*configuration_artifact.*p_artifact_type.*p_artifact_id'
  and pg_catalog.split_part(
    source.definition,
    'pg_advisory_xact_lock_shared',
    2
  ) ~ '(?s)select \* into descriptor.*m4_exact_approval_valid',
  'M4-CFG-AC-002 activation locks before re-reading and validating approval'
)
from (
  select pg_catalog.pg_get_functiondef(
    'app.m4_transition_artifact_version(uuid,text,uuid,text,text,jsonb,text,text,text,uuid)'::regprocedure
  ) as definition
) source;

-- 63. Canonical projection preserves signed deal discounts as separate,
-- nonnegative buckets instead of rejecting them or folding them into fees.
select extensions.is(
  app.m4_deal_tax_input(
    app.m4_deal_source_snapshot(
      '10000000-0000-4000-8000-000000000001',
      '34700000-0000-4000-8000-000000000001'
    ),
    'CA'
  ),
  '{
    "vehicle_price_minor":"1000000",
    "taxable_fees_minor":"20000",
    "taxable_discounts_minor":"50000",
    "non_taxable_fees_minor":"10000",
    "non_taxable_discounts_minor":"15000",
    "eligible_trade_in_credit_minor":"0",
    "trade_in_eligibility":null
  }'::jsonb,
  'M4-TAX-AC-002 canonical input separates explicitly classified discounts'
);

-- 64. The trusted receipt pins that exact discount projection and checksum.
select extensions.ok(
  exists (
    select 1
    from public.runtime_evidence_records evidence
    where evidence.id = (
      select evidence_id from pg_temp.bound_runtime_results where phase = 'tax'
    )
      and evidence.snapshot -> 'input' = app.m4_deal_tax_input(
        app.m4_deal_source_snapshot(
          '10000000-0000-4000-8000-000000000001',
          '34700000-0000-4000-8000-000000000001'
        ),
        'CA'
      )
      and evidence.snapshot -> 'inputBinding' ->> 'inputProjectionChecksum'
        = app.m4_canonical_fingerprint(evidence.snapshot -> 'input')
  ),
  'M4-TAX-AC-002 trusted evidence pins the exact discount projection'
);

select * from extensions.finish();
rollback;
