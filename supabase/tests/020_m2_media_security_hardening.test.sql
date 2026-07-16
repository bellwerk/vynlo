-- VYN-MEDIA-001, VYN-STOR-001, VYN-SEC-001, VYN-TEN-001,
-- M2-MEDIA-AC-002, M2-MEDIA-AC-021, T-MED-002, T-MED-003,
-- T-STOR-001, T-TEN-001, T-RBAC-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(22);

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
  fixture_role text default 'authenticated'
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
    'aal', 'aal2',
    'amr', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'method', 'totp',
        'timestamp', pg_catalog.floor(
          pg_catalog.extract(epoch from pg_catalog.statement_timestamp())
        )::bigint
      )
    )
  );
  perform pg_catalog.set_config('request.jwt.claim.sub', fixture_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', fixture_role, true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

insert into public.document_types (
  id, workspace_id, type_key, version, name, field_schema,
  production_enabled, status
) values (
  'fa100000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'media_security_fixture', 1, 'Media security fixture', '{}', false, 'active'
);
insert into public.document_template_versions (
  id, workspace_id, document_type_id, version, locale, template_class,
  source_html, source_checksum, renderer_version, field_schema,
  production_approved, watermark, status
) values (
  'fa200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fa100000-0000-4000-8000-000000000001', 1, 'en-CA',
  'synthetic_non_production', '<html><body>security fixture</body></html>',
  repeat('1', 64), 'synthetic-html-v1', '{}', false,
  'DRAFT / NON-PRODUCTION', 'active'
);
insert into public.deals (
  id, workspace_id, deal_type_key, status, currency_code,
  owner_membership_id, idempotency_key, command_fingerprint, created_by
) values (
  'fa300000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'synthetic.media-security', 'draft', 'CAD',
  '41000000-0000-4000-8000-000000000001',
  'media-security-fixture-deal', repeat('2', 64),
  '31000000-0000-4000-8000-000000000001'
);
insert into public.documents (
  id, workspace_id, document_type_id, template_version_id, deal_id,
  locale, render_input_snapshot, render_input_checksum,
  idempotency_key, command_fingerprint, created_by
) values (
  'fa400000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fa100000-0000-4000-8000-000000000001',
  'fa200000-0000-4000-8000-000000000001',
  'fa300000-0000-4000-8000-000000000001',
  'en-CA', '{}', repeat('3', 64), 'media-security-fixture-document',
  repeat('4', 64), '31000000-0000-4000-8000-000000000001'
);

create temporary table pg_temp.legal_intents (
  upload_session_id uuid,
  document_id uuid,
  media_kind text,
  upload_bucket text,
  upload_object_key text,
  expires_at timestamptz,
  replayed boolean,
  audit_event_id uuid
);
grant all on pg_temp.legal_intents to authenticated, service_role;

select extensions.ok(
  pg_catalog.to_regprocedure(
    'app.legal_original_upload_object_is_authorized(text,text,jsonb)'
  ) is not null
    and (
      select pg_catalog.pg_get_function_result(proc.oid) = 'boolean'
      from pg_catalog.pg_proc proc
      where proc.oid = pg_catalog.to_regprocedure(
        'app.legal_original_upload_object_is_authorized(text,text,jsonb)'
      )
    ),
  'T-STOR-001 the Storage policy uses a boolean-only authorization contract'
);
select extensions.ok(
  (
    select proc.prosecdef
      and exists (
        select 1
        from pg_catalog.unnest(coalesce(proc.proconfig, array[]::text[])) setting
        where setting in ('search_path=', 'search_path=""')
      )
    from pg_catalog.pg_proc proc
    where proc.oid = pg_catalog.to_regprocedure(
      'app.legal_original_upload_object_is_authorized(text,text,jsonb)'
    )
  ),
  'T-RBAC-001 the boolean Storage predicate is SECURITY DEFINER with an empty search path'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.legal_original_upload_object_is_authorized(text,text,jsonb)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'anon',
      'app.legal_original_upload_object_is_authorized(text,text,jsonb)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'service_role',
      'app.legal_original_upload_object_is_authorized(text,text,jsonb)',
      'EXECUTE'
    ),
  'only authenticated Storage policy evaluation can invoke the boolean predicate'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'app.complete_vehicle_photo_upload(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.complete_vehicle_photo_upload(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'service_role',
      'app.complete_vehicle_photo_upload(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)',
      'EXECUTE'
    ),
  'M2-MEDIA-AC-002 no API role can execute the vehicle-photo implementation helper'
);
select extensions.ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'app.record_preserved_legal_original(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.record_preserved_legal_original(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'service_role',
      'app.record_preserved_legal_original(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)',
      'EXECUTE'
    ),
  'M2-MEDIA-AC-021 no API role can execute the preserved-original implementation helper'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.complete_vehicle_photo_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,integer,integer,integer,jsonb,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.complete_vehicle_photo_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,integer,integer,integer,jsonb,text,uuid)',
      'EXECUTE'
    ),
  'only the service role can execute the lease-fenced vehicle-photo wrapper'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.complete_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,text,jsonb,text,uuid)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.complete_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,text,jsonb,text,uuid)',
      'EXECUTE'
    ),
  'only the service role can execute the session- and lease-fenced legal wrapper'
);
select extensions.ok(
  (
    select implementation.proowner = wrapper.proowner
    from pg_catalog.pg_proc implementation
    cross join pg_catalog.pg_proc wrapper
    where implementation.oid = pg_catalog.to_regprocedure(
      'app.complete_vehicle_photo_upload(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)'
    )
      and wrapper.oid = pg_catalog.to_regprocedure(
        'app.complete_vehicle_photo_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,integer,integer,integer,jsonb,text,uuid)'
      )
  ),
  'the vehicle wrapper retains same-owner access to its revoked implementation helper'
);
select extensions.ok(
  (
    select implementation.proowner = wrapper.proowner
    from pg_catalog.pg_proc implementation
    cross join pg_catalog.pg_proc wrapper
    where implementation.oid = pg_catalog.to_regprocedure(
      'app.record_preserved_legal_original(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)'
    )
      and wrapper.oid = pg_catalog.to_regprocedure(
        'app.complete_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,text,jsonb,text,uuid)'
      )
  ),
  'the legal wrapper retains same-owner access to its revoked implementation helper'
);
select extensions.ok(
  (
    select pg_catalog.count(*) = 4
      and pg_catalog.bool_and(
        proc.prosecdef
          and exists (
            select 1
            from pg_catalog.unnest(
              coalesce(proc.proconfig, array[]::text[])
            ) setting
            where setting in ('search_path=', 'search_path=""')
          )
      )
    from pg_catalog.pg_proc proc
    where proc.oid in (
      pg_catalog.to_regprocedure(
        'app.complete_vehicle_photo_upload(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)'
      ),
      pg_catalog.to_regprocedure(
        'app.complete_vehicle_photo_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,integer,integer,integer,jsonb,text,uuid)'
      ),
      pg_catalog.to_regprocedure(
        'app.record_preserved_legal_original(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)'
      ),
      pg_catalog.to_regprocedure(
        'app.complete_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer,text,bigint,text,text,jsonb,text,uuid)'
      )
    )
  ),
  'both owner-internal helpers and canonical wrappers retain fixed empty search paths'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.legal_original_upload_sessions', 'SELECT'
  )
    and not pg_catalog.has_column_privilege(
      'authenticated', 'public.legal_original_upload_sessions',
      'upload_object_key', 'SELECT'
    )
    and not pg_catalog.has_column_privilege(
      'authenticated', 'public.legal_original_upload_sessions',
      'verification_receipt', 'SELECT'
    ),
  'authenticated clients have no table or sensitive-column legal-session read grant'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'service_role', 'public.legal_original_upload_sessions', 'SELECT'
  ),
  'workers must use lease-fenced loaders instead of scanning legal upload sessions'
);
select extensions.ok(
  not exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'legal_original_upload_sessions'
      and 'authenticated' = any(policy.roles)
      and policy.cmd = 'SELECT'
  ),
  'no latent authenticated SELECT policy exposes legal upload-session rows'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.policyname = 'legal_original_uploads_insert'
      and policy.cmd = 'INSERT'
      and policy.with_check like '%legal_original_upload_object_is_authorized%'
      and policy.with_check not like '%legal_original_upload_sessions%'
  ),
  'Storage delegates exact upload eligibility without a caller-visible table subquery'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'app.load_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'authenticated',
      'app.load_legal_original_upload_verification(uuid,uuid,uuid,uuid,text,uuid,integer)',
      'EXECUTE'
    ),
  'provider coordinates remain available only through the active-lease worker loader'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
insert into pg_temp.legal_intents
select result.*
from app.create_legal_original_upload_session(
  '10000000-0000-4000-8000-000000000001',
  'media-security-legal-intent-001',
  'fa400000-0000-4000-8000-000000000001',
  'legal_document', 'security.pdf', 'application/pdf', 777,
  repeat('a', 64), 'request-media-security-intent-001',
  'fa500000-0000-4000-8000-000000000001'
) result;
select extensions.ok(
  exists (
    select 1
    from pg_temp.legal_intents intent
    where intent.upload_bucket = 'media-private'
      and intent.upload_object_key like 'workspaces/%/upload-intents/%/source'
      and not intent.replayed
  ),
  'the canonical actor command still returns its one exact bounded upload target'
);
select extensions.throws_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata) values (
      'fa600000-0000-4000-8000-000000000001',
      (select upload_bucket from pg_temp.legal_intents),
      (select upload_object_key from pg_temp.legal_intents),
      '{"size":778,"mimetype":"application/pdf"}'::jsonb
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'the boolean predicate rejects mismatched object metadata'
);
select extensions.lives_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata) values (
      'fa600000-0000-4000-8000-000000000002',
      (select upload_bucket from pg_temp.legal_intents),
      (select upload_object_key from pg_temp.legal_intents),
      '{"size":777,"mimetype":"APPLICATION/PDF"}'::jsonb
    )
  $$,
  'the exact actor-owned legal object remains uploadable after table SELECT revocation'
);
select extensions.throws_ok(
  $$select pg_catalog.count(*) from public.legal_original_upload_sessions$$,
  '42501',
  'permission denied for table legal_original_upload_sessions',
  'authenticated callers cannot read coordinate-bearing session rows'
);
reset role;

select pg_temp.authenticate_as(
  '31000000-0000-4000-8000-000000000001', 'service_role'
);
set local role service_role;
select extensions.throws_ok(
  $$select pg_catalog.count(*) from public.legal_original_upload_sessions$$,
  '42501',
  'permission denied for table legal_original_upload_sessions',
  'service callers cannot bypass exact lease loaders with a table scan'
);
select extensions.throws_ok(
  $$
    select * from app.complete_vehicle_photo_upload(
      null::uuid, null::uuid, null::text, null::uuid, null::uuid,
      null::text, null::bigint, null::text, null::boolean,
      null::integer, null::integer, null::integer, null::jsonb,
      null::text, null::uuid
    )
  $$,
  '42501',
  'permission denied for function complete_vehicle_photo_upload',
  'service callers cannot bypass the vehicle verification wrapper'
);
select extensions.throws_ok(
  $$
    select * from app.record_preserved_legal_original(
      null::uuid, null::uuid, null::text, null::text, null::text,
      null::uuid, null::text, null::text, null::text, null::text,
      null::bigint, null::text, null::jsonb, null::uuid, null::text,
      null::uuid, null::integer, null::text, null::uuid
    )
  $$,
  '42501',
  'permission denied for function record_preserved_legal_original',
  'service callers cannot bypass the legal verification wrapper'
);
reset role;

select * from extensions.finish();
rollback;
