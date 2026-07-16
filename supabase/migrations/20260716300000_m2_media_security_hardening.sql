-- VYN-MEDIA-001, VYN-STOR-001, VYN-SEC-001, M2-MEDIA-AC-002,
-- M2-MEDIA-AC-021: direct helper execution and upload-coordinate reads are
-- closed. Only the canonical actor/session or worker/lease boundaries remain.

create function app.legal_original_upload_object_is_authorized(
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
      and pg_catalog.char_length(coalesce(p_object_name, '')) between 1 and 1000
      and pg_catalog.jsonb_typeof(p_metadata) = 'object'
      and exists (
        select 1
        from public.legal_original_upload_sessions upload
        where upload.upload_bucket = p_bucket_id
          and upload.upload_object_key = p_object_name
          and upload.created_by = auth.uid()
          and upload.status = 'awaiting_upload'
          and upload.expires_at > pg_catalog.statement_timestamp()
          and upload.verification_job_id is null
          and case
            when p_metadata ->> 'size' ~ '^(0|[1-9][0-9]{0,18})$'
              then (p_metadata ->> 'size')::numeric
                = upload.expected_byte_size::numeric
            else false
          end
          and pg_catalog.lower(
            pg_catalog.btrim(coalesce(p_metadata ->> 'mimetype', ''))
          ) = upload.expected_mime_type
          and app.has_permission(
            upload.workspace_id,
            case
              when upload.media_kind = 'signed_document'
                then 'documents.upload_signed'
              else 'media.create'
            end
          )
          and (
            upload.media_kind <> 'signed_document'
            or app.has_recent_strong_auth()
          )
      ),
    false
  );
$$;

-- Storage evaluates a boolean owner-and-intent predicate. Authenticated roles
-- no longer need SELECT on the coordinate-bearing upload-session relation.
drop policy if exists legal_original_uploads_insert on storage.objects;
create policy legal_original_uploads_insert
on storage.objects
for insert to authenticated
with check (
  app.legal_original_upload_object_is_authorized(
    storage.objects.bucket_id,
    storage.objects.name,
    storage.objects.metadata
  )
);

drop policy if exists legal_original_upload_sessions_select
  on public.legal_original_upload_sessions;

revoke all on table public.legal_original_upload_sessions
  from public, anon, authenticated, service_role;

-- These implementation helpers are callable only by their same-owner
-- SECURITY DEFINER wrappers. API roles cannot bypass verification-job leases,
-- upload-session correlation, or the wrapper-selected actor/idempotency data.
revoke all on function app.complete_vehicle_photo_upload(
  uuid, uuid, text, uuid, uuid, text, bigint, text, boolean,
  integer, integer, integer, jsonb, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function app.record_preserved_legal_original(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint, text,
  jsonb, uuid, text, uuid, integer, text, uuid
) from public, anon, authenticated, service_role;

-- Restate the narrow worker surface explicitly so future ACL drift cannot
-- accidentally make the implementation helpers the public integration point.
revoke all on function app.complete_vehicle_photo_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, bigint, text,
  integer, integer, integer, jsonb, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.complete_vehicle_photo_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, bigint, text,
  integer, integer, integer, jsonb, text, uuid
) to service_role;

revoke all on function app.complete_legal_original_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, bigint, text, text,
  jsonb, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function app.complete_legal_original_upload_verification(
  uuid, uuid, uuid, uuid, text, uuid, integer, text, bigint, text, text,
  jsonb, text, uuid
) to service_role;

revoke all on function app.legal_original_upload_object_is_authorized(
  text, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function app.legal_original_upload_object_is_authorized(
  text, text, jsonb
) to authenticated;

comment on function app.legal_original_upload_object_is_authorized(
  text, text, jsonb
) is
  'Boolean-only Storage INSERT predicate for one exact live actor-owned legal-original intent; it returns no provider coordinates or verification evidence.';
comment on function app.complete_vehicle_photo_upload(
  uuid, uuid, text, uuid, uuid, text, bigint, text, boolean,
  integer, integer, integer, jsonb, text, uuid
) is
  'Owner-internal vehicle-photo completion helper; API roles must use the lease-fenced upload-verification wrapper.';
comment on function app.record_preserved_legal_original(
  uuid, uuid, text, text, text, uuid, text, text, text, text, bigint, text,
  jsonb, uuid, text, uuid, integer, text, uuid
) is
  'Owner-internal preserved-original helper; API roles must use the session- and lease-fenced legal verification wrapper.';
