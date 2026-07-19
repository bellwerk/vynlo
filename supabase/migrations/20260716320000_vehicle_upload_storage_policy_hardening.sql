-- VYN-MEDIA-001, VYN-STOR-001, VYN-TEN-001, VYN-SEC-001,
-- M2-MEDIA-AC-001, M2-MEDIA-AC-002
--
-- Vehicle-photo upload coordinates remain private after the authenticated
-- media_upload_sessions SELECT grant is revoked. Storage evaluates only this
-- boolean owner/intent predicate; callers cannot read session rows through the
-- policy or obtain any coordinate, checksum, or verification evidence from it.

create function app.vehicle_photo_upload_object_is_authorized(
  p_bucket_id text,
  p_object_name text,
  p_metadata jsonb
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    p_bucket_id = 'media-private'
      and pg_catalog.char_length(
        coalesce(p_object_name, '')
      ) between 1 and 1000
      and pg_catalog.jsonb_typeof(p_metadata) = 'object'
      and exists (
        select 1
        from public.media_upload_sessions upload
        where upload.quarantine_bucket = p_bucket_id
          and upload.quarantine_object_key = p_object_name
          and upload.created_by = auth.uid()
          and upload.status = 'awaiting_upload'
          and upload.expires_at > pg_catalog.statement_timestamp()
          and upload.verification_job_id is null
          and upload.expected_byte_size between 1 and 20000000
          and case
            when p_metadata ->> 'size' ~ '^(0|[1-9][0-9]{0,18})$'
              then (p_metadata ->> 'size')::numeric
                = upload.expected_byte_size::numeric
            else false
          end
          and pg_catalog.lower(
            pg_catalog.btrim(
              coalesce(p_metadata ->> 'mimetype', '')
            )
          ) = upload.expected_mime_type
          and app.has_permission(upload.workspace_id, 'media.create')
      ),
    false
  );
$$;

drop policy if exists managed_media_uploads_insert on storage.objects;
create policy managed_media_uploads_insert
on storage.objects
for insert to authenticated
with check (
  app.vehicle_photo_upload_object_is_authorized(
    storage.objects.bucket_id,
    storage.objects.name,
    storage.objects.metadata
  )
);

-- Remove the now-unused row policy as well as the browser grant so a later
-- broad table grant cannot silently restore coordinate-bearing reads.
drop policy if exists media_upload_sessions_select
  on public.media_upload_sessions;
revoke select on table public.media_upload_sessions
  from public, anon, authenticated;

revoke all on function app.vehicle_photo_upload_object_is_authorized(
  text, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function app.vehicle_photo_upload_object_is_authorized(
  text, text, jsonb
) to authenticated;

comment on function app.vehicle_photo_upload_object_is_authorized(
  text, text, jsonb
) is
  'Boolean-only Storage INSERT predicate for one exact live actor-owned vehicle-photo intent; it returns no upload coordinates or verification evidence.';
