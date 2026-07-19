-- VYN-MEDIA-001, VYN-STOR-001, VYN-TEN-001, VYN-SEC-001,
-- VYN-AUD-001, VYN-API-001, M2-MEDIA-MGMT-AC-003, T-STOR-001,
-- T-TEN-001, T-RBAC-001, T-AUD-001, T-API-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(27);

grant execute on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) to authenticated;

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  fixture_role text default 'authenticated',
  assurance text default 'aal2'
)
returns void
language plpgsql
as $$
declare
  claims jsonb;
begin
  claims := pg_catalog.jsonb_build_object(
    'sub', fixture_user_id::text,
    'role', fixture_role,
    'aal', assurance,
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', case when assurance = 'aal2' then 'totp' else 'password' end,
        'timestamp', pg_catalog.floor(
          pg_catalog.extract('epoch', pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', fixture_role, true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

-- This actor intentionally receives documents.read without the immutable
-- restricted-file capability. It proves that a broad document read role does
-- not authorize signed-original bytes.
insert into public.roles (
  id, workspace_id, key, name, source, status, requires_mfa
) values (
  'f8100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fixture_documents_reader',
  'Fixture documents reader',
  'workspace',
  'active',
  false
);
insert into public.role_permissions (
  workspace_id, role_id, permission_id, status
)
select
  '10000000-0000-4000-8000-000000000001',
  'f8100000-0000-4000-8000-000000000001',
  permission.id,
  'active'
from public.permissions permission
where permission.workspace_id is null
  and permission.key = 'documents.read';
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  'f8200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  'f8100000-0000-4000-8000-000000000001',
  'active'
);

insert into public.document_types (
  id, workspace_id, key, version, display_name, field_schema,
  production_enabled, status, labels, field_schema_checksum, checksum
) values (
  'f8300000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'managed_download_fixture', 1, 'Managed download fixture', '{}', false,
  'active', '{"en":"Managed download fixture","fr":"Telechargement gere fictif"}',
  repeat('d', 64), repeat('e', 64)
);
insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_checksum, renderer_version, field_schema,
  production_approved, watermark, status, source_bundle_checksum,
  field_schema_checksum
) values (
  'f8400000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'f8300000-0000-4000-8000-000000000001', 1, 'en-CA',
  'synthetic_non_production', '<html><body>fixture</body></html>',
  repeat('1', 64), 'synthetic-html-v1', '{}', false,
  'DRAFT / NON-PRODUCTION', 'active', repeat('f', 64), repeat('d', 64)
);
insert into public.deals (
  id, workspace_id, deal_type_key, status, currency_code,
  owner_membership_id, idempotency_key, command_fingerprint, created_by
) values (
  'f8500000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'retail.cash', 'draft', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'managed-download-fixture-deal', repeat('2', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.documents (
  id, workspace_id, document_type_id, template_version_id, deal_id,
  locale, render_input_snapshot, render_input_checksum,
  idempotency_key, command_fingerprint, created_by
) values (
  'f8600000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'f8300000-0000-4000-8000-000000000001',
  'f8400000-0000-4000-8000-000000000001',
  'f8500000-0000-4000-8000-000000000001',
  'en-CA', '{}', repeat('3', 64), 'managed-download-fixture-document',
  repeat('4', 64), '31000000-0000-4000-8000-000000000001'
);

insert into public.media_assets (
  id,
  workspace_id,
  document_id,
  owner_entity_type,
  owner_entity_id,
  media_kind,
  status,
  created_by
) values
  (
    'f9100000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    null,
    'test_attachment',
    'f9100000-0000-4000-8000-000000000002',
    'attachment',
    'ready',
    '31000000-0000-4000-8000-000000000001'
  ),
  (
    'f9100000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    'f8600000-0000-4000-8000-000000000001',
    'document',
    'f8600000-0000-4000-8000-000000000001',
    'signed_document',
    'ready',
    '31000000-0000-4000-8000-000000000001'
  );

insert into public.media_files (
  id,
  workspace_id,
  media_id,
  file_class,
  variant,
  storage_bucket,
  storage_object_key,
  storage_generation,
  mime_type,
  byte_size,
  checksum_sha256,
  metadata_stripped,
  retention_policy,
  verification_receipt
) values
  (
    'f9200000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'f9100000-0000-4000-8000-000000000001',
    'document_preview',
    'preview',
    'media-private',
    'workspaces/10000000-0000-4000-8000-000000000001/attachments/'
      || 'f9200000-0000-4000-8000-000000000001/fixture.pdf',
    'provider-generation-download-001',
    'application/pdf',
    4,
    repeat('a', 64),
    false,
    'retain_until_archive',
    null
  ),
  (
    'f9200000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    'f9100000-0000-4000-8000-000000000003',
    -- This M2 authorization fixture classifies restricted access from the
    -- signed_document asset. A preview-class byte fixture deliberately avoids
    -- manufacturing M4 official-document lineage outside its issuance command.
    'document_preview',
    'preview',
    'media-private',
    'workspaces/10000000-0000-4000-8000-000000000001/documents/'
      || 'f8600000-0000-4000-8000-000000000001/files/'
      || 'f9200000-0000-4000-8000-000000000003/' || repeat('b', 64)
      || '.pdf',
    'provider-generation-signed-download-001',
    'application/pdf',
    1024,
    repeat('b', 64),
    false,
    'retain_until_archive',
    pg_catalog.jsonb_build_object(
      'schemaVersion', 1,
      'verifier', pg_catalog.jsonb_build_object(
        'name', 'fixture-verifier', 'version', '1.0.0'
      ),
      'storage', pg_catalog.jsonb_build_object(
        'bucket', 'media-private',
        'objectKey',
          'workspaces/10000000-0000-4000-8000-000000000001/documents/'
          || 'f8600000-0000-4000-8000-000000000001/files/'
          || 'f9200000-0000-4000-8000-000000000003/' || repeat('b', 64)
          || '.pdf',
        'generation', 'provider-generation-signed-download-001',
        'byteSize', '1024',
        'checksumSha256', repeat('b', 64)
      ),
      'malwareScan', pg_catalog.jsonb_build_object(
        'verdict', 'clean',
        'sourceChecksumSha256', repeat('b', 64),
        'scanner', 'fixture-clamd',
        'signatureVersion', 'fixture-1'
      )
    )
  );

create temporary table pg_temp.media_inventory (
  inventory_unit_id uuid,
  vehicle_id uuid,
  stock_number text,
  replayed boolean
);
create temporary table pg_temp.vehicle_uploads (
  media_id uuid,
  upload_session_id uuid,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  collection_version bigint,
  aggregate_version bigint,
  replayed boolean,
  audit_event_id uuid,
  outbox_event_id uuid
);
create temporary table pg_temp.safe_authorizations (
  authorization_id uuid,
  media_file_id uuid,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  media_kind text,
  authorization_expires_at timestamptz,
  replayed boolean,
  audit_event_id uuid,
  probe text
);
grant all on pg_temp.media_inventory, pg_temp.vehicle_uploads,
  pg_temp.safe_authorizations to authenticated, service_role;

create temporary table pg_temp.service_authorizations (
  authorization_id uuid,
  workspace_id uuid,
  media_file_id uuid,
  media_kind text,
  storage_bucket text,
  storage_object_key text,
  storage_generation text,
  mime_type text,
  byte_size bigint,
  checksum_sha256 text,
  signed_url_ttl_seconds integer,
  authorization_expires_at timestamptz,
  probe text
);
grant all on pg_temp.service_authorizations to authenticated, service_role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.media_inventory
select result.*
from app.create_inventory_unit(
  '10000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'managed-download-generation-fixture',
  '1HGCM82633A925019',
  2026,
  'Synthetic',
  'Download Generation',
  date '2026-07-16',
  18,
  'km',
  'CAD',
  4300000,
  'Fictional managed download generation fixture',
  'request-managed-download-inventory-001',
  'f8700000-0000-4000-8000-000000000001'
) result;
insert into pg_temp.vehicle_uploads
select result.*
from app.create_vehicle_photo_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'managed-download-vehicle-upload-001',
  (select inventory_unit_id from pg_temp.media_inventory),
  'front.webp',
  'image/webp',
  2048,
  repeat('c', 64),
  'request-managed-download-vehicle-upload-001',
  'f8700000-0000-4000-8000-000000000002'
) result;
reset role;

insert into public.media_processing_runs (
  id, workspace_id, media_id, generation, source_kind, source_id,
  processing_profile_id, profile_snapshot, profile_checksum_sha256,
  status, terminal_receipt_checksum_sha256, started_at, completed_at
)
select
  'f8800000-0000-4000-8000-000000000001',
  asset.workspace_id,
  asset.id,
  1,
  'upload_session',
  upload.upload_session_id,
  profile.id,
  profile.profile_snapshot,
  profile.checksum_sha256,
  'succeeded',
  repeat('d', 64),
  pg_catalog.statement_timestamp(),
  pg_catalog.statement_timestamp()
from pg_temp.vehicle_uploads upload
join public.media_assets asset on asset.id = upload.media_id
join public.media_processing_profiles profile
  on profile.workspace_id = asset.workspace_id
 and profile.id = asset.processing_profile_id;

update public.media_assets asset
set status = 'ready',
    updated_at = pg_catalog.statement_timestamp()
where asset.id = (select media_id from pg_temp.vehicle_uploads);

insert into public.media_files (
  id, workspace_id, media_id, processing_run_id, file_class, variant,
  storage_bucket, storage_object_key, storage_generation, mime_type,
  byte_size, checksum_sha256, width, height, metadata_stripped,
  retention_policy
)
select
  'f8900000-0000-4000-8000-000000000001',
  asset.workspace_id,
  asset.id,
  'f8800000-0000-4000-8000-000000000001',
  'vehicle_photo_derivative',
  'thumbnail_320',
  'media-private',
  'workspaces/' || asset.workspace_id::text || '/media/' || asset.id::text
    || '/runs/f8800000-0000-4000-8000-000000000001/thumbnail_320/'
    || repeat('e', 64) || '.webp',
  'provider-generation-vehicle-download-001',
  'image/webp',
  320,
  repeat('e', 64),
  320,
  213,
  true,
  'retain_until_archive'
from pg_temp.vehicle_uploads upload
join public.media_assets asset on asset.id = upload.media_id;

select extensions.has_table(
  'public',
  'managed_media_download_authorizations',
  'M2-MEDIA-MGMT-AC-003 audited managed-media authorizations exist'
);
select extensions.ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'managed_media_download_authorizations'
  ),
  'M2-MEDIA-MGMT-AC-003 authorization provenance forces RLS'
);
select extensions.ok(
  pg_catalog.to_regprocedure(
    'app.authorize_managed_media_download(uuid,text,uuid,integer,text,uuid)'
  ) is not null
    and pg_catalog.to_regprocedure(
      'app.authorize_managed_media_download(uuid,text,uuid,text,uuid)'
    ) is null,
  'browser authorization uses the bounded-TTL opaque contract only'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.authorize_managed_media_download(uuid,text,uuid,integer,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.load_managed_media_download_authorization(uuid)',
      'EXECUTE'
    ),
  'authenticated users can authorize but cannot resolve provider coordinates'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.load_managed_media_download_authorization(uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'service_role',
      'app.authorize_managed_media_download(uuid,text,uuid,integer,text,uuid)',
      'EXECUTE'
    ),
  'service role can load only an already-audited authorization'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.managed_media_download_authorizations', 'SELECT'
  )
    and not pg_catalog.has_table_privilege(
      'service_role', 'public.managed_media_download_authorizations', 'SELECT'
    ),
  'authorization rows are not directly selectable by API roles'
);
select extensions.ok(
  exists (
    select 1
    from public.permissions permission
    where permission.workspace_id is null
      and permission.key = 'files.read_restricted'
      and permission.source = 'platform'
      and permission.status = 'active'
  )
  and exists (
    select 1
    from public.role_permissions role_permission
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role_permission.workspace_id =
      '10000000-0000-4000-8000-000000000001'
      and role_permission.role_id = 'f8100000-0000-4000-8000-000000000001'
      and role_permission.status = 'active'
      and permission.key = 'documents.read'
  )
  and not exists (
    select 1
    from public.role_permissions role_permission
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role_permission.workspace_id =
      '10000000-0000-4000-8000-000000000001'
      and role_permission.role_id = 'f8100000-0000-4000-8000-000000000001'
      and role_permission.status = 'active'
      and permission.key = 'files.read_restricted'
  ),
  'signed-original authorization uses the immutable restricted-file permission key'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'signed-download-documents-only',
      'f9200000-0000-4000-8000-000000000003',
      60,
      'request-signed-download-documents-only',
      'f9300000-0000-4000-8000-000000000010'
    )
  $$,
  '42501',
  'managed media download is not authorized',
  'documents.read alone cannot authorize a signed original'
);
reset role;

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'authenticated',
  'aal1'
);
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'signed-download-stale-auth',
      'f9200000-0000-4000-8000-000000000003',
      60,
      'request-signed-download-stale-auth',
      'f9300000-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'managed media download is not authorized',
  'an AAL1 session cannot exercise the MFA-bound restricted-file permission'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.safe_authorizations
    select result.*, 'signed'
    from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'signed-download-restricted-aal2',
      'f9200000-0000-4000-8000-000000000003',
      60,
      'request-signed-download-restricted-aal2',
      'f9300000-0000-4000-8000-000000000012'
    ) result
  $$,
  'files.read_restricted plus recent AAL2 authorizes a signed original'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.safe_authorizations
    select result.*, 'first'
    from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'managed-media-download-opaque-001',
      'f9200000-0000-4000-8000-000000000001',
      60,
      'request-managed-media-download-001',
      'f9300000-0000-4000-8000-000000000001'
    ) result
  $$,
  'an eligible user authorizes one exact managed file'
);
reset role;

select extensions.ok(
  (
    select
      safe_authorization.media_file_id = 'f9200000-0000-4000-8000-000000000001'
      and safe_authorization.mime_type = 'application/pdf'
      and safe_authorization.byte_size = 4
      and safe_authorization.checksum_sha256 = repeat('a', 64)
      and safe_authorization.media_kind = 'attachment'
      and not safe_authorization.replayed
      and pg_catalog.to_jsonb(safe_authorization)::text
        !~* '(storage_bucket|storage_object|storage_generation|provider-generation)'
    from pg_temp.safe_authorizations safe_authorization
    where safe_authorization.probe = 'first'
  ),
  'browser authorization metadata is exact and contains no provider coordinates'
);
select extensions.ok(
  exists (
    select 1
    from public.managed_media_download_authorizations stored_authorization
    join public.audit_events audit
      on audit.workspace_id = stored_authorization.workspace_id
     and audit.id = stored_authorization.audit_event_id
    where stored_authorization.id = (
      select safe.authorization_id
      from pg_temp.safe_authorizations safe
      where safe.probe = 'first'
    )
      and stored_authorization.signed_url_ttl_seconds = 60
      and audit.action = 'media.download_authorized'
      and audit.entity_id = stored_authorization.media_file_id
      and audit.metadata ->> 'authorization_id' = stored_authorization.id::text
      and audit.metadata ->> 'provider_coordinates_server_only' = 'true'
  ),
  'authorization, audit, TTL, and file lineage commit together'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.safe_authorizations
    select result.*, 'vehicle-generation-1'
    from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'vehicle-download-generation-1',
      'f8900000-0000-4000-8000-000000000001',
      60,
      'request-vehicle-download-generation-1',
      'f9300000-0000-4000-8000-000000000020'
    ) result
  $$,
  'the current successful vehicle-photo generation can be authorized'
);
reset role;

insert into public.media_processing_runs (
  id, workspace_id, media_id, generation, source_kind, source_id,
  processing_profile_id, profile_snapshot, profile_checksum_sha256,
  status, terminal_receipt_checksum_sha256, started_at, completed_at
)
select
  'f8800000-0000-4000-8000-000000000002',
  asset.workspace_id,
  asset.id,
  2,
  'media_file',
  'f8900000-0000-4000-8000-000000000001',
  profile.id,
  profile.profile_snapshot,
  profile.checksum_sha256,
  'succeeded',
  repeat('f', 64),
  pg_catalog.statement_timestamp(),
  pg_catalog.statement_timestamp()
from pg_temp.vehicle_uploads upload
join public.media_assets asset on asset.id = upload.media_id
join public.media_processing_profiles profile
  on profile.workspace_id = asset.workspace_id
 and profile.id = asset.processing_profile_id;

update public.media_assets asset
set generation = 2,
    version = asset.version + 1,
    updated_at = pg_catalog.statement_timestamp()
where asset.id = (select media_id from pg_temp.vehicle_uploads);

insert into public.media_files (
  id, workspace_id, media_id, processing_run_id, file_class, variant,
  storage_bucket, storage_object_key, storage_generation, mime_type,
  byte_size, checksum_sha256, width, height, metadata_stripped,
  retention_policy
)
select
  'f8900000-0000-4000-8000-000000000002',
  asset.workspace_id,
  asset.id,
  'f8800000-0000-4000-8000-000000000002',
  'vehicle_photo_derivative',
  'thumbnail_320',
  'media-private',
  'workspaces/' || asset.workspace_id::text || '/media/' || asset.id::text
    || '/runs/f8800000-0000-4000-8000-000000000002/thumbnail_320/'
    || repeat('9', 64) || '.webp',
  'provider-generation-vehicle-download-002',
  'image/webp',
  321,
  repeat('9', 64),
  320,
  213,
  true,
  'retain_until_archive'
from pg_temp.vehicle_uploads upload
join public.media_assets asset on asset.id = upload.media_id;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'vehicle-download-stale-generation',
      'f8900000-0000-4000-8000-000000000001',
      60,
      'request-vehicle-download-stale-generation',
      'f9300000-0000-4000-8000-000000000021'
    )
  $$,
  '42501',
  'managed media download is not authorized',
  'a retained stale vehicle-photo generation cannot receive a new authorization'
);
reset role;

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'service_role'
);
set local role service_role;
select extensions.throws_ok(
  $$
    select * from app.load_managed_media_download_authorization(
      (
        select authorization_id
        from pg_temp.safe_authorizations
        where probe = 'vehicle-generation-1'
      )
    )
  $$,
  'P0002',
  'managed media download authorization was not found',
  'an existing grant cannot resolve after its vehicle generation becomes stale'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.safe_authorizations
    select result.*, 'vehicle-generation-2'
    from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'vehicle-download-generation-2',
      'f8900000-0000-4000-8000-000000000002',
      60,
      'request-vehicle-download-generation-2',
      'f9300000-0000-4000-8000-000000000022'
    ) result
  $$,
  'the replacement successful vehicle-photo generation can be authorized'
);
reset role;

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'service_role'
);
set local role service_role;
select extensions.ok(
  (
    select loaded.media_file_id = 'f8900000-0000-4000-8000-000000000002'
      and loaded.storage_generation =
        'provider-generation-vehicle-download-002'
      and loaded.media_kind = 'vehicle_photo'
    from app.load_managed_media_download_authorization(
      (
        select authorization_id
        from pg_temp.safe_authorizations
        where probe = 'vehicle-generation-2'
      )
    ) loaded
  ),
  'the loader resolves only the asset current successful processing run'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.safe_authorizations
    select result.*, 'replay'
    from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'managed-media-download-opaque-001',
      'f9200000-0000-4000-8000-000000000001',
      60,
      'request-managed-media-download-replay',
      'f9300000-0000-4000-8000-000000000002'
    ) result
  $$,
  'an identical authorization safely replays'
);
reset role;
select extensions.ok(
  (
    select replay.authorization_id = original.authorization_id
      and replay.audit_event_id = original.audit_event_id
      and replay.replayed
    from pg_temp.safe_authorizations replay
    cross join pg_temp.safe_authorizations original
    where replay.probe = 'replay' and original.probe = 'first'
  ),
  'replay returns the original opaque authorization and audit evidence'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '10000000-0000-4000-8000-000000000001',
      'managed-media-download-opaque-001',
      'f9200000-0000-4000-8000-000000000001',
      120,
      'request-managed-media-download-conflict',
      'f9300000-0000-4000-8000-000000000003'
    )
  $$,
  '23505',
  'managed media download idempotency key was reused',
  'a key cannot be reused with a different requested TTL'
);
select extensions.throws_ok(
  $$
    select * from app.authorize_managed_media_download(
      '20000000-0000-4000-8000-000000000002',
      'managed-media-download-cross-001',
      'f9200000-0000-4000-8000-000000000001',
      60,
      'request-managed-media-download-cross',
      'f9300000-0000-4000-8000-000000000004'
    )
  $$,
  '42501',
  'managed media download is not authorized',
  'cross-workspace authorization fails closed'
);
select extensions.throws_ok(
  $$
    select * from app.load_managed_media_download_authorization(
      (select authorization_id from pg_temp.safe_authorizations where probe = 'first')
    )
  $$,
  '42501',
  'permission denied for function load_managed_media_download_authorization',
  'authenticated callers cannot invoke the provider-coordinate loader'
);
reset role;

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001',
  'service_role'
);
set local role service_role;
select extensions.lives_ok(
  $$
    insert into pg_temp.service_authorizations
    select result.*, 'service'
    from app.load_managed_media_download_authorization(
      (select authorization_id from pg_temp.safe_authorizations where probe = 'first')
    ) result
  $$,
  'service role resolves one unexpired audited authorization'
);
reset role;
select extensions.ok(
  (
    select
      loaded.authorization_id = safe.authorization_id
      and loaded.workspace_id = '10000000-0000-4000-8000-000000000001'
      and loaded.media_file_id = safe.media_file_id
      and loaded.media_kind = safe.media_kind
      and loaded.storage_bucket = 'media-private'
      and loaded.storage_object_key like 'workspaces/%/fixture.pdf'
      and loaded.storage_generation = 'provider-generation-download-001'
      and loaded.mime_type = safe.mime_type
      and loaded.byte_size = safe.byte_size
      and loaded.checksum_sha256 = safe.checksum_sha256
      and loaded.signed_url_ttl_seconds = 60
      and loaded.authorization_expires_at = safe.authorization_expires_at
    from pg_temp.service_authorizations loaded
    cross join pg_temp.safe_authorizations safe
    where loaded.probe = 'service' and safe.probe = 'first'
  ),
  'service loader returns provider coordinates only with exact authorization lineage'
);

select extensions.throws_ok(
  $$
    update public.managed_media_download_authorizations
    set idempotency_key = 'managed-media-download-tampered'
    where id = (
      select authorization_id from pg_temp.safe_authorizations where probe = 'first'
    )
  $$,
  '55000',
  'managed_media_download_authorizations is append-only',
  'authorization provenance is append-only even for the table owner'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.throws_ok(
  $$select pg_catalog.count(*) from public.managed_media_download_authorizations$$,
  '42501',
  'permission denied for table managed_media_download_authorizations',
  'authenticated callers cannot select authorization rows directly'
);
reset role;

select * from extensions.finish();
rollback;
