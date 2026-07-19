-- VYN-MEDIA-001, VYN-STOR-001, VYN-TEN-001, VYN-SEC-001,
-- M2-MEDIA-AC-001, M2-MEDIA-AC-002, T-STOR-001, T-RBAC-001
begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(16);

grant execute on function app.create_inventory_unit(
  uuid, uuid, text, text, integer, text, text, date, bigint, text, text,
  bigint, text, text, uuid
) to authenticated;

create function pg_temp.authenticate_as(
  fixture_user_id uuid,
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
    'role', 'authenticated',
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
  perform pg_catalog.set_config(
    'request.jwt.claim.sub', fixture_user_id::text, true
  );
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claims', claims::text, true);
end;
$$;

create temporary table pg_temp.vehicle_storage_inventory (
  inventory_unit_id uuid primary key
);
create temporary table pg_temp.vehicle_storage_intent (
  media_id uuid primary key,
  upload_session_id uuid not null,
  upload_bucket text not null,
  upload_object_key text not null
);
grant all on pg_temp.vehicle_storage_inventory,
  pg_temp.vehicle_storage_intent to authenticated;

-- Actor B receives the same active administrator role so the negative probes
-- isolate intent ownership, not permission or assurance differences.
insert into public.membership_roles (
  id, workspace_id, membership_id, role_id, status
) values (
  '61000000-0000-4000-8000-000000000022',
  '10000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '51000000-0000-4000-8000-000000000001',
  'active'
);

select extensions.ok(
  pg_catalog.to_regprocedure(
    'app.vehicle_photo_upload_object_is_authorized(text,text,jsonb)'
  ) is not null
    and (
      select pg_catalog.pg_get_function_result(proc.oid) = 'boolean'
      from pg_catalog.pg_proc proc
      where proc.oid = pg_catalog.to_regprocedure(
        'app.vehicle_photo_upload_object_is_authorized(text,text,jsonb)'
      )
    ),
  'T-STOR-001 vehicle Storage authorization exposes only a boolean result'
);
select extensions.ok(
  (
    select proc.prosecdef
      and exists (
        select 1
        from pg_catalog.unnest(
          coalesce(proc.proconfig, array[]::text[])
        ) setting
        where setting in ('search_path=', 'search_path=""')
      )
      and proc.prosrc like '%upload.created_by = auth.uid()%'
      and proc.prosrc like '%upload.verification_job_id is null%'
      and proc.prosrc like '%upload.expected_byte_size%'
      and proc.prosrc like '%upload.expected_mime_type%'
    from pg_catalog.pg_proc proc
    where proc.oid = pg_catalog.to_regprocedure(
      'app.vehicle_photo_upload_object_is_authorized(text,text,jsonb)'
    )
  ),
  'T-RBAC-001 vehicle predicate is strict SECURITY DEFINER and exact-intent scoped'
);
select extensions.ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'app.vehicle_photo_upload_object_is_authorized(text,text,jsonb)',
    'EXECUTE'
  )
    and not pg_catalog.has_function_privilege(
      'anon',
      'app.vehicle_photo_upload_object_is_authorized(text,text,jsonb)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'service_role',
      'app.vehicle_photo_upload_object_is_authorized(text,text,jsonb)',
      'EXECUTE'
    ),
  'only authenticated Storage policy evaluation can invoke the vehicle predicate'
);
select extensions.ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.media_upload_sessions', 'SELECT'
  )
    and not pg_catalog.has_column_privilege(
      'authenticated', 'public.media_upload_sessions',
      'quarantine_bucket', 'SELECT'
    )
    and not pg_catalog.has_column_privilege(
      'authenticated', 'public.media_upload_sessions',
      'quarantine_object_key', 'SELECT'
    )
    and not pg_catalog.has_column_privilege(
      'authenticated', 'public.media_upload_sessions',
      'expected_checksum_sha256', 'SELECT'
    )
    and not pg_catalog.has_column_privilege(
      'authenticated', 'public.media_upload_sessions',
      'verification_job_id', 'SELECT'
    ),
  'authenticated callers cannot read vehicle upload coordinates or verification state'
);
select extensions.ok(
  not exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'media_upload_sessions'
      and 'authenticated' = any(policy.roles)
      and policy.cmd = 'SELECT'
  ),
  'no latent authenticated SELECT policy exposes vehicle upload-session rows'
);
select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.policyname = 'managed_media_uploads_insert'
      and policy.cmd = 'INSERT'
      and policy.with_check like
        '%vehicle_photo_upload_object_is_authorized%'
      and policy.with_check not like '%media_upload_sessions%'
  ),
  'Storage delegates vehicle eligibility without a caller-visible table subquery'
);
select extensions.ok(
  (
    select pg_catalog.bool_and(
      not pg_catalog.has_function_privilege(
        'anon', restricted.signature, 'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'authenticated', restricted.signature, 'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'service_role', restricted.signature, 'EXECUTE'
      )
    )
    from (
      values
        ('app.complete_vehicle_photo_upload(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)'),
        ('app.record_preserved_legal_original(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)'),
        ('app.complete_vehicle_photo_upload_actor_key_impl(uuid,uuid,text,uuid,uuid,text,bigint,text,boolean,integer,integer,integer,jsonb,text,uuid)'),
        ('app.record_preserved_legal_original_actor_key_impl(uuid,uuid,text,text,text,uuid,text,text,text,text,bigint,text,jsonb,uuid,text,uuid,integer,text,uuid)')
    ) restricted(signature)
  ),
  'the 30000 and 31000 completion-helper revocations remain intact'
);

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into pg_temp.vehicle_storage_inventory (inventory_unit_id)
    select result.inventory_unit_id
    from app.create_inventory_unit(
      '10000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      'vehicle-storage-policy-create-022',
      '1HGCM82633A732022',
      2025,
      'Synthetic',
      'Storage Policy Fixture',
      date '2026-07-16',
      22022,
      'km',
      'CAD',
      2800000,
      'Fictional vehicle Storage policy fixture',
      'request-vehicle-storage-create-022',
      'fb200000-0000-4000-8000-000000000001'
    ) result
  $$,
  'actor A creates one canonical inventory fixture'
);
select extensions.lives_ok(
  $$
    insert into pg_temp.vehicle_storage_intent (
      media_id, upload_session_id, upload_bucket, upload_object_key
    )
    select
      result.media_id, result.upload_session_id,
      result.upload_bucket, result.upload_object_key
    from app.create_vehicle_photo_upload_session(
      '10000000-0000-4000-8000-000000000001',
      'vehicle-storage-policy-intent-022',
      (select inventory_unit_id from pg_temp.vehicle_storage_inventory),
      'vehicle-storage-policy.jpg',
      'image/jpeg',
      1024,
      repeat('2', 64),
      'request-vehicle-storage-intent-022',
      'fb200000-0000-4000-8000-000000000002'
    ) result
  $$,
  'actor A creates one exact bounded vehicle-photo upload intent'
);
select extensions.is(
  app.vehicle_photo_upload_object_is_authorized(
    (select upload_bucket from pg_temp.vehicle_storage_intent),
    (select upload_object_key from pg_temp.vehicle_storage_intent),
    '{"size":1024,"mimetype":"IMAGE/JPEG"}'::jsonb
  ),
  true,
  'the predicate accepts only the current actor exact key, size, and normalized MIME'
);
select extensions.throws_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata) values (
      'fb600000-0000-4000-8000-000000000001',
      (select upload_bucket from pg_temp.vehicle_storage_intent),
      (select upload_object_key from pg_temp.vehicle_storage_intent),
      '{"size":1025,"mimetype":"image/jpeg"}'::jsonb
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'vehicle Storage rejects a byte-size mismatch without reading session rows'
);
select extensions.throws_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata) values (
      'fb600000-0000-4000-8000-000000000002',
      (select upload_bucket from pg_temp.vehicle_storage_intent),
      (select upload_object_key from pg_temp.vehicle_storage_intent),
      '{"size":1024,"mimetype":"image/png"}'::jsonb
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'vehicle Storage rejects a normalized MIME mismatch'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000002');
set local role authenticated;
select extensions.is(
  app.vehicle_photo_upload_object_is_authorized(
    (select upload_bucket from pg_temp.vehicle_storage_intent),
    (select upload_object_key from pg_temp.vehicle_storage_intent),
    '{"size":1024,"mimetype":"image/jpeg"}'::jsonb
  ),
  false,
  'an equally permitted actor receives only false for another actor intent'
);
select extensions.throws_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata) values (
      'fb600000-0000-4000-8000-000000000003',
      (select upload_bucket from pg_temp.vehicle_storage_intent),
      (select upload_object_key from pg_temp.vehicle_storage_intent),
      '{"size":1024,"mimetype":"image/jpeg"}'::jsonb
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'another workspace member cannot borrow the exact vehicle upload intent'
);
reset role;

select pg_temp.authenticate_as('31000000-0000-4000-8000-000000000001');
set local role authenticated;
select extensions.lives_ok(
  $$
    insert into storage.objects (id, bucket_id, name, metadata) values (
      'fb600000-0000-4000-8000-000000000004',
      (select upload_bucket from pg_temp.vehicle_storage_intent),
      (select upload_object_key from pg_temp.vehicle_storage_intent),
      '{"size":1024,"mimetype":"IMAGE/JPEG"}'::jsonb
    )
  $$,
  'the exact actor-owned object remains uploadable after SELECT revocation'
);
select extensions.throws_ok(
  $$select pg_catalog.count(*) from public.media_upload_sessions$$,
  '42501',
  'permission denied for table media_upload_sessions',
  'authenticated callers cannot read coordinate-bearing vehicle sessions'
);
reset role;

select * from extensions.finish();
rollback;
