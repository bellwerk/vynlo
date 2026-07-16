-- M2-MEDIA-AC-021, VYN-MEDIA-001, VYN-STOR-001, VYN-JOB-001,
-- VYN-TEN-001, VYN-SEC-001, VYN-AUD-001, T-MED-002, T-MED-003,
-- T-MED-004, T-STOR-001, T-JOB-001, T-TEN-001, T-RBAC-001, T-AUD-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(44);

create function pg_temp.authenticate_as(fixture_user_id uuid, assurance text default 'aal2')
returns void language plpgsql as $$
declare claims jsonb;
begin
  claims := pg_catalog.jsonb_build_object(
    'sub', fixture_user_id::text, 'role', 'authenticated', 'aal', assurance,
    'amr', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'method', case when assurance = 'aal2' then 'totp' else 'password' end,
      'timestamp', pg_catalog.floor(pg_catalog.extract(epoch from pg_catalog.statement_timestamp()))::bigint)));
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end; $$;

insert into public.document_types (
  id, workspace_id, type_key, version, name, field_schema, production_enabled, status
) values (
  'e5100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'legal_original_fixture', 1, 'Legal original fixture', '{}', false, 'active'
);
insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_checksum, renderer_version, field_schema,
  production_approved, watermark, status
) values (
  'e5200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'e5100000-0000-4000-8000-000000000001', 1, 'en-CA',
  'synthetic_non_production', '<html><body>fixture</body></html>',
  repeat('1', 64), 'synthetic-html-v1', '{}', false,
  'DRAFT / NON-PRODUCTION', 'active'
);
insert into public.deals (
  id, workspace_id, deal_type_key, status, currency_code,
  owner_membership_id, idempotency_key, command_fingerprint, created_by
) values (
  'e5300000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'retail.cash', 'draft', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'legal-original-fixture-deal', repeat('2', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.documents (
  id, workspace_id, document_type_id, template_version_id, deal_id,
  locale, render_input_snapshot, render_input_checksum,
  idempotency_key, command_fingerprint, created_by
) values (
  'e5400000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'e5100000-0000-4000-8000-000000000001',
  'e5200000-0000-4000-8000-000000000001',
  'e5300000-0000-4000-8000-000000000001',
  'en-CA', '{}', repeat('3', 64), 'legal-original-fixture-document',
  repeat('4', 64), '31000000-0000-4000-8000-000000000001'
);

create temporary table pg_temp.legal_intents (
  upload_session_id uuid, document_id uuid, media_kind text,
  upload_bucket text, upload_object_key text, expires_at timestamptz,
  replayed boolean, audit_event_id uuid, probe text
);
create temporary table pg_temp.legal_requests (
  upload_session_id uuid, document_id uuid, job_id uuid, job_status text,
  replayed boolean, audit_event_id uuid, outbox_event_id uuid, probe text
);
create temporary table pg_temp.legal_claims (
  job_id uuid, workspace_id uuid, outbox_event_id uuid, job_type text,
  entity_type text, entity_id uuid, payload_schema_version integer,
  payload jsonb, idempotency_key text, attempt_number integer,
  max_attempts integer, lease_token uuid, lease_expires_at timestamptz,
  correlation_id uuid, causation_id uuid, probe text
);
create temporary table pg_temp.legal_completions (
  media_id uuid, media_file_id uuid, replayed boolean, probe text
);
create temporary table pg_temp.legal_rejections (
  upload_session_id uuid, upload_status text, replayed boolean,
  audit_event_id uuid, outbox_event_id uuid, probe text
);
grant all on pg_temp.legal_intents, pg_temp.legal_requests,
  pg_temp.legal_claims, pg_temp.legal_completions, pg_temp.legal_rejections
to authenticated, service_role;

select extensions.has_table('public', 'legal_original_upload_sessions',
  'document original upload sessions exist');
select extensions.ok((select relation.relrowsecurity and relation.relforcerowsecurity
  from pg_catalog.pg_class relation join pg_catalog.pg_namespace namespace
    on namespace.oid = relation.relnamespace
  where namespace.nspname = 'public' and relation.relname = 'legal_original_upload_sessions'),
  'legal original upload sessions enforce RLS');
select extensions.ok(exists(select 1 from pg_catalog.pg_policies policy
  where policy.schemaname = 'storage' and policy.tablename = 'objects'
    and policy.policyname = 'legal_original_uploads_insert'
    and policy.cmd = 'INSERT' and 'authenticated' = any(policy.roles)
    and policy.with_check like '%legal_original_upload_object_is_authorized%'
    and policy.with_check not like '%legal_original_upload_sessions%'),
  'storage insert policy delegates exact metadata fencing without table exposure');
select extensions.ok(pg_catalog.has_function_privilege('authenticated',
  'app.create_legal_original_upload_session(uuid,text,uuid,text,text,text,bigint,text,text,uuid)', 'EXECUTE'),
  'authenticated actors can create a legal original intent');
select extensions.ok(pg_catalog.has_function_privilege('authenticated',
  'app.request_legal_original_upload_verification(uuid,text,uuid,uuid,text,uuid)', 'EXECUTE'),
  'authenticated actors can request durable verification');
select extensions.ok(pg_catalog.has_function_privilege('service_role',
  'app.load_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer)', 'EXECUTE')
  and pg_catalog.has_function_privilege('service_role',
  'app.complete_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,text,jsonb,text,uuid)', 'EXECUTE'),
  'trusted workers alone can load and complete verification');
select extensions.ok(not pg_catalog.has_function_privilege('authenticated',
  'app.complete_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,text,jsonb,text,uuid)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated',
  'app.reject_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,text,text,uuid)', 'EXECUTE'),
  'browser roles cannot attest or reject stored bytes');

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legal_intents select result.*, 'first'
from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001', 'legal-upload-intent-001',
  'e5400000-0000-4000-8000-000000000001', 'legal_document',
  'registration.pdf', 'application/pdf', 1000, repeat('a', 64),
  'request-legal-upload-001', 'e6000000-0000-4000-8000-000000000001') result;
select extensions.ok(exists(select 1 from pg_temp.legal_intents
  where probe = 'first' and upload_bucket = 'media-private' and not replayed),
  'actor creates one private bounded upload intent');
select extensions.ok(exists(select 1 from pg_temp.legal_intents intent
  where intent.probe = 'first' and intent.upload_object_key =
    'workspaces/10000000-0000-4000-8000-000000000001/documents/'
    || intent.document_id::text || '/upload-intents/'
    || intent.upload_session_id::text || '/source'),
  'intent returns a server-derived opaque exact object key');
insert into pg_temp.legal_intents select result.*, 'replay'
from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001', 'legal-upload-intent-001',
  'e5400000-0000-4000-8000-000000000001', 'legal_document',
  'registration.pdf', 'application/pdf', 1000, repeat('a', 64),
  'request-legal-upload-replay', 'e6000000-0000-4000-8000-000000000002') result;
select extensions.ok((select original.upload_session_id = replay.upload_session_id and replay.replayed
  from pg_temp.legal_intents original join pg_temp.legal_intents replay on replay.probe = 'replay'
  where original.probe = 'first'), 'same intent idempotency key returns the original target');
select extensions.throws_ok($$
  insert into storage.objects (id, bucket_id, name, metadata) values (
    'e6100000-0000-4000-8000-000000000001',
    (select upload_bucket from pg_temp.legal_intents where probe = 'first'),
    (select upload_object_key from pg_temp.legal_intents where probe = 'first'),
    '{"size":999,"mimetype":"application/pdf"}'::jsonb)
$$, '42501', 'new row violates row-level security policy for table "objects"',
  'storage rejects a byte-size mismatch');
select extensions.lives_ok($$
  insert into storage.objects (id, bucket_id, name, metadata) values (
    'e6100000-0000-4000-8000-000000000002',
    (select upload_bucket from pg_temp.legal_intents where probe = 'first'),
    (select upload_object_key from pg_temp.legal_intents where probe = 'first'),
    '{"size":1000,"mimetype":"APPLICATION/PDF"}'::jsonb)
$$, 'storage accepts only the exact unexpired owner intent');
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001', 'aal1');
select extensions.throws_ok($$
  select * from app.create_legal_original_upload_session(
    '10000000-0000-4000-8000-000000000001', 'signed-upload-without-stepup',
    'e5400000-0000-4000-8000-000000000001', 'signed_document',
    'signed.pdf', 'application/pdf', 900, repeat('b', 64),
    'request-signed-no-stepup', 'e6000000-0000-4000-8000-000000000003')
$$, '42501', 'recent strong authentication is required',
  'signed originals require recent step-up authentication');
select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
insert into pg_temp.legal_requests select result.*, 'first'
from app.request_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'legal-verify-request-001',
  'e5400000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_intents where probe = 'first'),
  'request-legal-verify-001', 'e6000000-0000-4000-8000-000000000004') result;
select extensions.ok(exists(select 1 from pg_temp.legal_requests
  where probe = 'first' and job_status = 'queued' and not replayed
    and audit_event_id is not null and outbox_event_id is not null),
  'completion request atomically audits and queues durable verification');
select extensions.ok(exists(select 1 from pg_temp.legal_requests request
  join public.jobs job on job.id = request.job_id where request.probe = 'first'
    and job.job_type = 'media.verify_legal_original'
    and job.entity_type = 'document' and job.entity_id = request.document_id
    and job.payload = pg_catalog.jsonb_build_object('upload_session_id', request.upload_session_id)),
  'legal verification job contains the upload reference only');
insert into pg_temp.legal_requests select result.*, 'replay'
from app.request_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'legal-verify-request-001',
  'e5400000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_intents where probe = 'first'),
  'request-legal-verify-replay', 'e6000000-0000-4000-8000-000000000005') result;
select extensions.ok((select original.job_id = replay.job_id and replay.replayed
  from pg_temp.legal_requests original join pg_temp.legal_requests replay on replay.probe = 'replay'
  where original.probe = 'first'), 'verification request replay returns the original job');
reset role;
select pg_temp.authenticate_as('32000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok($$
  select * from app.request_legal_original_upload_verification(
    '20000000-0000-4000-8000-000000000002', 'cross-tenant-legal-verify',
    'e5400000-0000-4000-8000-000000000001',
    (select upload_session_id from pg_temp.legal_intents where probe = 'first'),
    'request-cross-tenant', 'e6000000-0000-4000-8000-000000000006')
$$, 'P0002', 'legal upload intent was not found',
  'a different workspace cannot borrow the upload intent');
reset role;

set local role service_role;
insert into pg_temp.legal_claims select claimed.*, 'first'
from app.claim_jobs('legal-verifier.fixture-01', 1, 300,
  array['media.verify_legal_original']) claimed;
select extensions.is((select pg_catalog.count(*) from pg_temp.legal_claims where probe = 'first'),
  1::bigint, 'legal verification is claimable through the bounded durable queue');
select extensions.throws_ok($$
  select * from app.load_legal_original_upload_verification(
    '10000000-0000-4000-8000-000000000001',
    'e5400000-0000-4000-8000-000000000001',
    (select upload_session_id from pg_temp.legal_intents where probe = 'first'),
    (select job_id from pg_temp.legal_claims where probe = 'first'),
    'legal-verifier.stale',
    (select lease_token from pg_temp.legal_claims where probe = 'first'),
    (select attempt_number from pg_temp.legal_claims where probe = 'first'))
$$, '55000', 'only the active legal verification lease can load an upload',
  'stale worker identity cannot load private object provenance');
select extensions.ok(exists(select 1 from app.load_legal_original_upload_verification(
    '10000000-0000-4000-8000-000000000001',
    'e5400000-0000-4000-8000-000000000001',
    (select upload_session_id from pg_temp.legal_intents where probe = 'first'),
    (select job_id from pg_temp.legal_claims where probe = 'first'),
    'legal-verifier.fixture-01',
    (select lease_token from pg_temp.legal_claims where probe = 'first'),
    (select attempt_number from pg_temp.legal_claims where probe = 'first')) source
  where source.expected_byte_size = 1000 and source.expected_mime_type = 'application/pdf'
    and source.expected_checksum_sha256 = repeat('a', 64)),
  'active lease loads only bounded expected object metadata');
select extensions.throws_ok($$
  select * from app.complete_legal_original_upload_verification(
    '10000000-0000-4000-8000-000000000001',
    'e5400000-0000-4000-8000-000000000001',
    (select upload_session_id from pg_temp.legal_intents where probe = 'first'),
    (select job_id from pg_temp.legal_claims where probe = 'first'),
    'legal-verifier.fixture-01',
    (select lease_token from pg_temp.legal_claims where probe = 'first'),
    (select attempt_number from pg_temp.legal_claims where probe = 'first'),
    'application/pdf', 999, repeat('a', 64), 'etag-1', '{}'::jsonb,
    'job:mismatch', (select correlation_id from pg_temp.legal_claims where probe = 'first'))
$$, '23514', 'legal original verification does not match upload intent',
  'worker completion rejects observed byte mismatch');

insert into pg_temp.legal_completions
select result.*, 'first' from app.complete_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'e5400000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_intents where probe = 'first'),
  (select job_id from pg_temp.legal_claims where probe = 'first'),
  'legal-verifier.fixture-01',
  (select lease_token from pg_temp.legal_claims where probe = 'first'),
  (select attempt_number from pg_temp.legal_claims where probe = 'first'),
  'application/pdf', 1000, repeat('a', 64), 'etag-1',
  pg_catalog.jsonb_build_object(
    'schemaVersion', 1,
    'jobId', (select job_id from pg_temp.legal_claims where probe = 'first'),
    'workerId', 'legal-verifier.fixture-01',
    'leaseId', (select lease_token from pg_temp.legal_claims where probe = 'first'),
    'attempt', (select attempt_number from pg_temp.legal_claims where probe = 'first'),
    'verifier', pg_catalog.jsonb_build_object('name', 'vynlo-legal-original-verifier', 'version', '1'),
    'storage', pg_catalog.jsonb_build_object('bucket', 'media-private',
      'objectKey', (select upload_object_key from pg_temp.legal_intents where probe = 'first'),
      'generation', 'etag-1', 'mimeType', 'application/pdf',
      'byteSize', 1000, 'checksumSha256', repeat('a', 64)),
    'malwareScan', pg_catalog.jsonb_build_object('scanner', 'clamd',
      'scannerVersion', '1.4.2', 'signatureVersion', '27345',
      'sourceChecksumSha256', repeat('a', 64), 'verdict', 'clean')),
  'job:complete-legal',
  (select correlation_id from pg_temp.legal_claims where probe = 'first')) result;
select extensions.ok(exists(select 1 from pg_temp.legal_completions
  where probe = 'first' and media_id is not null and media_file_id is not null and not replayed),
  'active lease records one immutable preserved original');
select extensions.ok(exists(select 1 from pg_temp.legal_completions completion
  join public.media_files file on file.id = completion.media_file_id
  join public.media_assets asset on asset.id = completion.media_id
  where completion.probe = 'first' and file.retention_policy = 'preserve_original'
    and file.storage_generation = 'etag-1' and file.verification_receipt -> 'malwareScan' ->> 'verdict' = 'clean'
    and asset.status = 'ready' and asset.document_id = 'e5400000-0000-4000-8000-000000000001'),
  'completion preserves exact private bytes, generation and clean receipt');
insert into pg_temp.legal_completions
select result.*, 'replay' from app.complete_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'e5400000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_intents where probe = 'first'),
  (select job_id from pg_temp.legal_claims where probe = 'first'),
  'legal-verifier.fixture-01',
  (select lease_token from pg_temp.legal_claims where probe = 'first'),
  (select attempt_number from pg_temp.legal_claims where probe = 'first'),
  'application/pdf', 1000, repeat('a', 64), 'etag-1', '{}'::jsonb,
  'job:complete-legal-replay',
  (select correlation_id from pg_temp.legal_claims where probe = 'first')) result;
select extensions.ok((select original.media_id = replay.media_id
  and original.media_file_id = replay.media_file_id and replay.replayed
  from pg_temp.legal_completions original join pg_temp.legal_completions replay on replay.probe = 'replay'
  where original.probe = 'first'), 'completion replay cannot duplicate the preserved original');
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legal_intents select result.*, 'rejected'
from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001', 'legal-upload-intent-rejected',
  'e5400000-0000-4000-8000-000000000001', 'legal_document',
  'infected.pdf', 'application/pdf', 700, repeat('c', 64),
  'request-legal-rejected', 'e6000000-0000-4000-8000-000000000007') result;
insert into pg_temp.legal_requests select result.*, 'rejected'
from app.request_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001', 'legal-verify-request-rejected',
  'e5400000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_intents where probe = 'rejected'),
  'request-legal-reject-verify', 'e6000000-0000-4000-8000-000000000008') result;
reset role;
set local role service_role;
insert into pg_temp.legal_claims select claimed.*, 'rejected'
from app.claim_jobs('legal-verifier.fixture-01', 1, 300,
  array['media.verify_legal_original']) claimed;
select extensions.ok(exists(select 1 from pg_temp.legal_claims claim
  join pg_temp.legal_requests request on request.job_id = claim.job_id
  where claim.probe = 'rejected' and request.probe = 'rejected'),
  'independent original receives an independent durable lease');
insert into pg_temp.legal_rejections select result.*, 'first'
from app.reject_legal_original_upload_verification(
  '10000000-0000-4000-8000-000000000001',
  'e5400000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_intents where probe = 'rejected'),
  (select job_id from pg_temp.legal_claims where probe = 'rejected'),
  'legal-verifier.fixture-01',
  (select lease_token from pg_temp.legal_claims where probe = 'rejected'),
  (select attempt_number from pg_temp.legal_claims where probe = 'rejected'),
  'media.malware_detected', 'validation', 'job:reject-legal',
  (select correlation_id from pg_temp.legal_claims where probe = 'rejected')) result;
select extensions.ok(exists(select 1 from pg_temp.legal_rejections rejection
  join public.legal_original_upload_sessions upload on upload.id = rejection.upload_session_id
  where rejection.probe = 'first' and rejection.upload_status = 'rejected'
    and upload.rejection_code = 'media.malware_detected' and not rejection.replayed),
  'malware verdict records a terminal rejected upload without a media file');
select extensions.ok(exists(select 1 from pg_temp.legal_rejections rejection
  join public.audit_events audit on audit.id = rejection.audit_event_id
  join public.outbox_events event on event.id = rejection.outbox_event_id
  where rejection.probe = 'first'
    and audit.action = 'media.legal_original_verification_rejected'
    and event.event_name = 'media.legal_original_verification_rejected'),
  'terminal rejection is audited and emitted through the outbox');
select extensions.ok(not exists(select 1 from public.jobs job
  where job.job_type = 'media.verify_legal_original'
    and app.job_payload_contains_forbidden_key(job.payload)),
  'legal verification payloads never persist credential-bearing fields');

reset role;

create temporary table pg_temp.legal_cleanup_schedules (
  cleanup_id uuid, upload_session_id uuid, cleanup_reason text,
  job_id uuid, outbox_event_id uuid
);
create temporary table pg_temp.legal_cleanup_completions (
  cleanup_id uuid, cleanup_status text, replayed boolean, probe text
);
grant all on pg_temp.legal_cleanup_schedules, pg_temp.legal_cleanup_completions
to authenticated, service_role;

select extensions.has_table('public', 'legal_original_quarantine_cleanups',
  'unaccepted legal originals have durable cleanup lineage');
select extensions.ok((select relation.relrowsecurity and relation.relforcerowsecurity
  from pg_catalog.pg_class relation join pg_catalog.pg_namespace namespace
    on namespace.oid = relation.relnamespace
  where namespace.nspname = 'public'
    and relation.relname = 'legal_original_quarantine_cleanups'),
  'legal original cleanup lineage enforces RLS');
select extensions.ok(pg_catalog.has_function_privilege('service_role',
  'app.enqueue_due_legal_original_quarantine_cleanup(integer,uuid)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated',
  'app.enqueue_due_legal_original_quarantine_cleanup(integer,uuid)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated',
  'app.complete_legal_original_quarantine_cleanup(uuid,uuid,uuid,text,uuid,integer,text,text,text,uuid)', 'EXECUTE'),
  'only trusted maintenance and worker roles can schedule or attest deletion');

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legal_intents select result.*, 'expired'
from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001', 'legal-upload-intent-expired',
  'e5400000-0000-4000-8000-000000000001', 'legal_document',
  'abandoned.pdf', 'application/pdf', 600, repeat('d', 64),
  'request-legal-expired', 'e6000000-0000-4000-8000-000000000009') result;
reset role;
update public.legal_original_upload_sessions upload
set expires_at = pg_catalog.statement_timestamp() - interval '1 minute'
where upload.id = (select upload_session_id from pg_temp.legal_intents where probe = 'expired');

set local role service_role;
insert into pg_temp.legal_cleanup_schedules
select * from app.enqueue_due_legal_original_quarantine_cleanup(
  10, 'e6000000-0000-4000-8000-000000000010');
select extensions.is((select pg_catalog.count(*) from pg_temp.legal_cleanup_schedules),
  2::bigint, 'bounded scheduler queues expired and rejected quarantine objects');
select extensions.ok(exists(select 1 from public.legal_original_upload_sessions upload
  where upload.id = (select upload_session_id from pg_temp.legal_intents where probe = 'expired')
    and upload.status = 'expired'),
  'scheduler atomically expires an abandoned awaiting-upload session');
select extensions.ok(not exists(select 1 from public.legal_original_quarantine_cleanups cleanup
  where cleanup.upload_session_id = (select upload_session_id from pg_temp.legal_intents where probe = 'first')),
  'a completed byte-preserved original can never enter quarantine cleanup');
select extensions.ok(not exists(select 1 from public.jobs job
  where job.job_type = 'media.delete_legal_original_quarantine'
    and (app.job_payload_contains_forbidden_key(job.payload)
      or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(job.payload)) <> 2
      or not job.payload ?& array['upload_session_id', 'reason'])),
  'legal cleanup jobs contain only the opaque session and bounded reason');

insert into pg_temp.legal_claims select claimed.*, 'cleanup'
from app.claim_jobs('legal-cleanup.fixture-01', 2, 300,
  array['media.delete_legal_original_quarantine']) claimed;
select extensions.is((select pg_catalog.count(*) from pg_temp.legal_claims where probe = 'cleanup'),
  2::bigint, 'both legal cleanup jobs receive independent bounded leases');
select extensions.throws_ok($$
  select * from app.load_legal_original_quarantine_cleanup(
    '10000000-0000-4000-8000-000000000001',
    (select upload_session_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'expired_intent'),
    (select job_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'expired_intent'),
    'legal-cleanup.stale',
    (select lease_token from pg_temp.legal_claims claim
      join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
      where schedule.cleanup_reason = 'expired_intent'),
    (select attempt_number from pg_temp.legal_claims claim
      join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
      where schedule.cleanup_reason = 'expired_intent'))
$$, '55000', 'only the active legal cleanup lease can load an object',
  'a stale worker identity cannot address the private quarantine key');
select extensions.ok(exists(select 1 from app.load_legal_original_quarantine_cleanup(
    '10000000-0000-4000-8000-000000000001',
    (select upload_session_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'expired_intent'),
    (select job_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'expired_intent'),
    'legal-cleanup.fixture-01',
    (select lease_token from pg_temp.legal_claims claim
      join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
      where schedule.cleanup_reason = 'expired_intent'),
    (select attempt_number from pg_temp.legal_claims claim
      join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
      where schedule.cleanup_reason = 'expired_intent')) source
  where source.cleanup_reason = 'expired_intent'
    and source.storage_bucket = 'media-private' and not source.already_deleted),
  'active lease resolves one exact private object key');
select extensions.ok(exists(select 1 from app.fence_legal_original_quarantine_cleanup(
    '10000000-0000-4000-8000-000000000001',
    (select upload_session_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'expired_intent'),
    (select job_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'expired_intent'),
    'legal-cleanup.fixture-01',
    (select lease_token from pg_temp.legal_claims claim
      join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
      where schedule.cleanup_reason = 'expired_intent'),
    (select attempt_number from pg_temp.legal_claims claim
      join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
      where schedule.cleanup_reason = 'expired_intent'),
    'application/pdf', 600, repeat('d', 64), 'etag-expired') result
  where not result.replayed),
  'worker fences provider generation, checksum, MIME and size before deletion');
select extensions.ok(exists(select 1 from public.legal_original_quarantine_cleanups cleanup
  where cleanup.reason = 'expired_intent' and cleanup.status = 'fenced'
    and cleanup.storage_generation = 'etag-expired'
    and cleanup.observed_checksum_sha256 = repeat('d', 64)
    and cleanup.observed_mime_type = 'application/pdf' and cleanup.observed_byte_size = 600),
  'database persists the exact immutable provider deletion fence');

insert into pg_temp.legal_cleanup_completions
select result.*, 'deleted' from app.complete_legal_original_quarantine_cleanup(
  '10000000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'expired_intent'),
  (select job_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'expired_intent'),
  'legal-cleanup.fixture-01',
  (select lease_token from pg_temp.legal_claims claim
    join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
    where schedule.cleanup_reason = 'expired_intent'),
  (select attempt_number from pg_temp.legal_claims claim
    join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
    where schedule.cleanup_reason = 'expired_intent'),
  'deleted', repeat('d', 64), 'job:legal-cleanup-deleted',
  (select correlation_id from pg_temp.legal_claims claim
    join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
    where schedule.cleanup_reason = 'expired_intent')) result;
select extensions.ok(exists(select 1 from pg_temp.legal_cleanup_completions
  where probe = 'deleted' and cleanup_status = 'deleted' and not replayed),
  'atomic checksum-conditional deletion records a terminal receipt');

insert into pg_temp.legal_cleanup_completions
select result.*, 'not-found' from app.complete_legal_original_quarantine_cleanup(
  '10000000-0000-4000-8000-000000000001',
  (select upload_session_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'terminal_rejection'),
  (select job_id from pg_temp.legal_cleanup_schedules where cleanup_reason = 'terminal_rejection'),
  'legal-cleanup.fixture-01',
  (select lease_token from pg_temp.legal_claims claim
    join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
    where schedule.cleanup_reason = 'terminal_rejection'),
  (select attempt_number from pg_temp.legal_claims claim
    join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
    where schedule.cleanup_reason = 'terminal_rejection'),
  'not_found', null, 'job:legal-cleanup-not-found',
  (select correlation_id from pg_temp.legal_claims claim
    join pg_temp.legal_cleanup_schedules schedule on schedule.job_id = claim.job_id
    where schedule.cleanup_reason = 'terminal_rejection')) result;
select extensions.ok(exists(select 1 from pg_temp.legal_cleanup_completions
  where probe = 'not-found' and cleanup_status = 'not_found' and not replayed),
  'missing rejected quarantine object records a terminal not-found receipt');
select extensions.ok(exists(select 1 from public.legal_original_quarantine_cleanups cleanup
  join public.audit_events audit on audit.id = cleanup.completion_audit_event_id
  join public.outbox_events event on event.id = cleanup.completion_outbox_event_id
  where cleanup.status in ('deleted', 'not_found')
    and audit.action = 'media.legal_original_quarantine_cleanup_completed'
    and event.event_name = 'media.legal_original_quarantine_cleanup_completed'),
  'cleanup completion remains observable through audit and outbox lineage');
select extensions.ok(exists(select 1 from public.media_files file
  where file.id = (select media_file_id from pg_temp.legal_completions where probe = 'first')
    and file.retention_policy = 'preserve_original'
    and file.deletion_requested_at is null),
  'cleanup processing leaves accepted preserved originals byte-for-byte retained');

reset role;
select * from extensions.finish();
rollback;
