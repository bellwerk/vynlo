-- M2 forward hardening: exact upload metadata and server-signed reads.
-- Browser object uploads remain restricted to one live vehicle-photo intent;
-- browser object reads are removed in favor of audited exact signed grants.

drop policy if exists managed_media_uploads_insert on storage.objects;
create policy managed_media_uploads_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'media-private'
  and pg_catalog.jsonb_typeof(metadata) = 'object'
  and exists (
    select 1
    from public.media_upload_sessions upload
    where upload.quarantine_bucket = storage.objects.bucket_id
      and upload.quarantine_object_key = storage.objects.name
      and upload.created_by = auth.uid()
      and upload.status = 'awaiting_upload'
      and upload.expires_at > pg_catalog.statement_timestamp()
      and upload.verification_job_id is null
      and upload.expected_byte_size between 1 and 20000000
      and case
        when storage.objects.metadata ->> 'size' ~ '^(0|[1-9][0-9]{0,18})$'
          then (storage.objects.metadata ->> 'size')::numeric
            = upload.expected_byte_size::numeric
        else false
      end
      and pg_catalog.lower(
        pg_catalog.btrim(coalesce(storage.objects.metadata ->> 'mimetype', ''))
      ) = upload.expected_mime_type
      and app.has_permission(upload.workspace_id, 'media.create')
  )
);

drop policy if exists managed_media_objects_select on storage.objects;
drop policy if exists document_preview_artifact_objects_select on storage.objects;
revoke select, update, delete on storage.objects from authenticated;
grant insert on storage.objects to authenticated;
