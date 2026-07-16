# Milestone 2 media and managed-storage pipeline

**Status:** persistence, upload verification, Sharp/ClamD processing, worker
orchestration, and private-storage adapters are implemented and statically
verified. Live Supabase acceptance and an atomic conditional-delete provider
remain open; all automated media deletion consumers/producers are disabled.

This delivery advances `VYN-MEDIA-001`, `VYN-STOR-001`, `VYN-JOB-001`,
`VYN-TEN-001`, `VYN-SEC-001`, and `VYN-AUD-001` without claiming that the
Milestone 2 media exit criteria are runtime-complete.

## Acceptance IDs

| ID | Contract | Evidence |
|---|---|---|
| `M2-MEDIA-AC-001` | A media intent creates a bounded private upload session with an opaque workspace-scoped key | `app.create_vehicle_photo_upload_session`, `T-STOR-001` |
| `M2-MEDIA-AC-002` | Completion requires exact size, MIME, checksum, signature, dimensions, clean scan receipt, a validated actor, and the active verification-job lease | `app.complete_vehicle_photo_upload_verification`, `T-MED-003` |
| `M2-MEDIA-AC-003` | The authoritative save commits a reference-only outbox job with an immutable profile snapshot | `media_processing_runs`, `media.process_vehicle_photo` payload schema 1 |
| `M2-MEDIA-AC-004` | Processing start/completion/failure is fenced by job, stable worker ID, lease token, attempt, workspace, media, and run | worker RPCs and `media_processing_completions` |
| `M2-MEDIA-AC-005` | Completion records one raw original and the four configured WebP outputs | `app.complete_vehicle_photo_processing`, `T-MED-001` |
| `M2-MEDIA-AC-006` | Processor receipts require orientation normalization, sRGB, no upscaling, and stripped EXIF/GPS/IPTC/XMP metadata | `@vynlo/media` receipt validation, `T-MED-002` |
| `M2-MEDIA-AC-007` | Reprocess is versioned, idempotent, and reuses only a retained exact source | `app.reprocess_vehicle_photo`, `T-MED-004` |
| `M2-MEDIA-AC-008` | Failures remain visible and use the existing bounded durable-job retry/dead-letter lifecycle | `app.record_vehicle_photo_processing_failure`, generic jobs |
| `M2-MEDIA-AC-009` | Reorder and cover commands lock one collection and reject stale versions | `app.reorder_inventory_media`, `app.set_inventory_media_cover`, `T-MED-005` |
| `M2-MEDIA-AC-010` | Raw vehicle originals become eligible seven days after a verified master and delete through a conditional durable job | retention enqueue/load/complete RPCs |
| `M2-MEDIA-AC-011` | Legal and signed originals are byte-preserved under an exact verification lease/receipt, have no deletion date, and cannot enter the vehicle-raw deletion command | `app.complete_legal_original_upload_verification`, owner-internal preservation helper, `media_files` constraints/triggers |
| `M2-MEDIA-AC-012` | Managed downloads idempotently authorize and audit one exact visible file before a short-lived server grant is issued | `app.authorize_managed_media_download`, managed-storage adapter |
| `M2-MEDIA-AC-013` | Cost evidence is a ready, undeleted preserved file owned by the same workspace and inventory aggregate | workspace file FK plus `app.post_inventory_cost_entry` semantic fence |
| `M2-MEDIA-AC-014` | Expired abandoned intents enqueue a bounded durable quarantine cleanup | `app.enqueue_due_media_quarantine_cleanup`, `013_media_quarantine_cleanup.test.sql` |
| `M2-MEDIA-AC-015` | Terminal verification rejection becomes cleanup-eligible only after durable dead letter | cleanup safety fence and pgTAP terminal-rejection scenario |
| `M2-MEDIA-AC-016` | Successful uploads become cleanup-eligible only after deterministic raw and normalized-master rows exist | `verified_raw_copy` scheduler predicate |
| `M2-MEDIA-AC-017` | Cleanup load/fence/completion binds workspace, session, generation, checksum, job, lease, and attempt | cleanup worker RPCs and strict job payload schema 1 |
| `M2-MEDIA-AC-018` | Cleanup has bounded retries, idempotency, audit, outbox, attempt, and dead-letter telemetry | jobs plus `media_quarantine_cleanups` provenance |
| `M2-MEDIA-AC-019` | A provider incapable of atomic conditional delete performs no delete request | `SupabaseManagedMediaStorage.delete` fail-closed adapter and replacement-race tests |
| `M2-MEDIA-AC-020` | Legal originals cannot enter quarantine or raw-retention deletion | vehicle-only scheduler joins, retention constraints, pgTAP legal fixture |
| `M2-MEDIA-AC-021` | Legal and signed originals use an exact private intent; only a lease-bound worker may derive generation, checksum, MIME, size, and a clean scan receipt | `20260716240000_legal_original_upload_verification.sql`, `014_legal_original_upload_verification.test.sql` |
| `M2-MEDIA-AC-022` | Signed-original intent and completion require `documents.upload_signed` plus strong authentication within 15 minutes; legal originals use `media.create` | command RPCs, Storage INSERT policy, pgTAP AAL test |
| `M2-MEDIA-AC-023` | The operations UI is phone-usable, bilingual, keyboard-labelled, exposes upload progress, durable queued state, retry, and signed-original step-up guidance | `LegalOriginalUpload`, legal-original browser contract tests |
| `M2-MEDIA-AC-024` | Expired or terminally rejected unaccepted document uploads enter a separate bounded cleanup lineage; completed originals are structurally ineligible | legal-original cleanup scheduler/safety predicate, pgTAP and worker tests |
| `M2-MEDIA-AC-025` | Legal quarantine cleanup fences exact key, provider generation, checksum, MIME, size, job, lease, attempt, workspace, and reason before conditional deletion | cleanup worker RPCs and strict job schema 1 |
| `M2-MEDIA-AC-026` | An upload owner can poll a safe translated-client projection and reason-retry only the active dead-letter verification job; signed originals repeat recent step-up, and rejected uploads require a new intent | status/retry RPCs and `023_legal_original_failure_visibility_retry.test.sql`; typed application service, `/api/v1` routes, strict browser parser, and `legal-original-upload.spec.ts` EN/FR viewport matrix |
| `M2-MEDIA-AC-027` | A vehicle-photo upload owner can poll a safe projection and reason-retry only the exact active dead-letter verification job; retry preserves actor, workspace, payload, bounded policy, causation, replay, audit, outbox, and aggregate fences, while terminal rejection requires a new upload | `20260716340000_vehicle_upload_failure_visibility_retry.sql`, `024_vehicle_upload_failure_visibility_retry.test.sql`, typed application and `/api/v1` status/retry contracts, strict EN/FR browser recovery flow |

## Transaction and worker boundaries

The browser may call only upload-intent, reprocess, reorder, cover, retention
hold, and exact download-authorization commands. Direct table writes and
persistent Storage reads remain revoked; browser Storage INSERT is limited by
RLS to the exact key, size, and normalized MIME of one live upload intent.
Upload completion is service-only because the server must read
the quarantined bytes, validate the signature and dimensions, verify the exact
checksum, and obtain a clean scanner receipt before it commits the processing
job.

The worker claims the existing durable job and calls
`app.start_vehicle_photo_processing`. A successful handler stores immutable
raw and derivative keys and calls `app.complete_vehicle_photo_processing`
before generic `app.complete_job`. The media completion RPC independently
checks the current unexpired job lease and records the stable machine worker ID,
lease token, attempt number, and full validated receipt. Exact replay under the
same lease returns the original files. A changed receipt or stale lease fails
closed.

`apps/worker/src/media-handler.ts` is concrete orchestration around injected
scanner and binary-processor ports. It validates source signatures and profile
checksums, scans before writes, stores deterministic objects, validates every
processor/storage receipt, and records classified media failure state before
the generic job retry transaction. `SupabaseManagedMediaStorage` implements
private exact-key upload/download grants, reads, immutable writes, and checksum
verification without bucket listing. Its delete method deliberately refuses
provider I/O because the available Supabase REST delete operation has no proven
atomic checksum or generation precondition.

Document originals use a separate `media.verify_legal_original` lane. The
browser submits only an exact intent and opaque upload-session identifier; it
cannot attest bytes. The worker streams a bounded private object, hashes the
unchanged bytes, scans before any parser use, verifies signature/MIME, size,
checksum, and provider generation, then records the original with
`preserve_original`. Signed originals repeat the recent strong-auth check at
intent creation, Storage INSERT, and verification request.

Authenticated and service API roles cannot execute the underlying
`app.complete_vehicle_photo_upload` or
`app.record_preserved_legal_original` implementation helpers. The same-owner
SECURITY DEFINER verification wrappers are the only worker entry points, so an
API credential cannot choose a different actor, idempotency scope, upload
session, job lease, or receipt lineage. Legal upload-session rows are likewise
not directly selectable by authenticated or service roles; vehicle upload-
session rows are not selectable by authenticated roles. Both Storage INSERT
policies call boolean-only SECURITY DEFINER predicates for the actor's exact
live intent. They return no bucket/key, generation, checksum, observed metadata,
or verification evidence and do not require browser table reads.

The legal-original status RPC applies the same workspace, media-kind
permission, owner, and signed-step-up fences while returning only a projected
state, bounded attempt policy, retry time, and safe failure identifiers. The UI
maps those values to English/French copy and never prints machine status or
error codes. Only a still-active upload whose current verification job is
`dead_letter` may be manually retried. Retry requires a reason, stores the raw
external command key in the actor-aware receipt, copies the source job's opaque
payload and bounded scheduling policy, and links the fresh job/outbox through
causation and `replay_of_job_id`. Terminal rejection is never revived; the user
must reset and create a new exact upload intent.

Vehicle upload verification exposes the same recovery shape through a separate
owner-only RPC pair without sharing legal/signed-document policy. The status
projection contains only lifecycle, bounded attempt/retry, and safe failure
identifiers; it never exposes the quarantine key, provider generation,
checksum, scan receipt, or worker detail. A manual retry locks the exact upload,
media aggregate, and current dead-letter job, requires an explicit reason, and
copies only the existing reference payload and bounded scheduling policy into a
fresh causation/replay-linked job. Actor-scoped receipt replay is evaluated
before current-state eligibility so a lost response replays deterministically
even if the fresh job later completes or rejects. A new command can never
revive rejected bytes; the browser starts a new exact upload instead.

Every user-attributed media command now preserves its validated raw idempotency
key while including workspace, actor, and command domain in the advisory lock,
receipt lookup, and composite unique index. This covers upload intents and
verification, reprocess, reorder, cover, caption, archive, legal intents, and
retention holds.
Worker-only completion/preservation paths use the actor already fenced by the
lease-bound wrapper. Pre-cutover receipts replay only for their recorded actor.

## Storage and retention

`media-private` is forced private. Quarantine, raw, derivative, and legal object
keys contain workspace and opaque IDs/checksums, never user filenames. Browsers
cannot SELECT `storage.objects`. The application authorizes one undeleted
`media_files` row with the relevant media/document permission and writes an
append-only audit authorization. The browser receives only that opaque
authorization ID. A service-role-only loader then correlates authorization,
workspace, file, expiry, bucket, key, provider generation, checksum, MIME, and
size; the server verifies the immutable bytes before signing a short-lived
grant. Provider coordinates never cross the authenticated browser RPC.

Vehicle raw originals use `delete_after_verified_master` and can be deleted
only after the seven-day deadline, without a hold, with a verified normalized
master, by an active `media.delete_retained_raw` lease, and with a matching
checksum. Load establishes a database deletion fence before returning the
provider key: a hold acquired first blocks the load, while a hold cannot race an
already-authorized physical deletion. Legal/incident hold changes are
optimistically versioned, audited, and append-only. Legal originals use
`preserve_original`; their constraint requires a null deletion date and the
immutable file trigger prohibits a terminal delete transition.

Quarantine cleanup has three database-owned reasons: `expired_intent`,
`terminal_rejection`, and `verified_raw_copy`. The bounded scheduler locks each
upload intent, creates one idempotent `media.delete_quarantine_upload` job, and
stores queue/audit/outbox provenance. The active worker lease receives the
exact private key, fences the observed checksum, and may attest deletion or
absence only while the reason-specific safety predicate still holds. Successful
upload cleanup additionally requires the same processing generation, source
checksum, deterministic raw file, and normalized master. Legal/document media
has no upload-session path into this table.

Expired or rejected document-upload quarantine uses the separate
`legal_original_quarantine_cleanups` lineage and
`media.delete_legal_original_quarantine` contract. Its safety predicate
requires an unaccepted `expired` or `rejected` session with no media/file or
verification receipt. The worker re-reads the exact private object, persists
generation/checksum/MIME/size, and can finish only through an atomic
checksum-conditional delete. Completed preserved originals cannot satisfy this
predicate or enter the cleanup table.

## Compatibility and rollback

The forward-only migrations are
`supabase/migrations/20260716190000_media_pipeline.sql`,
`20260716210000_media_upload_verification.sql`, and
`20260716220000_media_quarantine_cleanup.sql`, followed by the additive
`20260716230000_m2_sql_domain_hardening.sql` policy cutover. They add the media
and hold tables with forced RLS, a private Storage bucket/upload policy,
command/worker functions, the durable cleanup table, and the nullable
workspace-scoped supporting-file FK on inventory costs. They do not rewrite
inventory or cost rows. Rollback is
forward repair: disable new command exposure and jobs, preserve all
file/outbox/audit history, and ship a corrective migration. Never drop or
rewrite legal originals or official provenance.

`20260716240000_legal_original_upload_verification.sql` is additive. It adds
document-owned intents, exact Storage policy, verification/cleanup RPCs, and
immutable lineage without rewriting existing documents or media. Rollback is
forward repair: stop issuing new intents/jobs while retaining sessions, files,
receipts, audit, and outbox history.

`20260716290000_managed_media_download_authorization.sql` is the additive
opaque-download cutover. Deploy it with the server loader: older clients see an
unchanged `/api/v1` envelope, while direct PostgREST consumers can no longer
obtain storage coordinates. Rollback is forward repair and retains every
authorization/audit receipt.

`20260716300000_m2_media_security_hardening.sql` is a forward-only privilege
cutover. It revokes API-role execution of the two media implementation helpers,
retains same-owner wrapper composition, removes direct legal upload-session
reads, and replaces the Storage policy's table subquery with a strict
boolean-only predicate. It does not rewrite media, jobs, files, receipts,
audit, or outbox history. Rollback is another reviewed forward privilege
change; never reopen the helpers or coordinate-bearing table as an API surface.

`20260716310000_m2_actor_idempotency_hardening.sql` is a forward-only command
namespace cutover. It replaces the shared global receipt constraint with an
actor-scoped partial index for attributed commands and a separate actorless
worker index, then makes every reviewed lock and replay lookup actor-aware. It
preserves raw keys and all media, job, receipt, audit, and outbox history;
rollback is another reviewed forward change rather than a receipt rewrite.

`20260716320000_vehicle_upload_storage_policy_hardening.sql` is a forward-only
Storage-policy cutover. It removes the stale authenticated vehicle-session
SELECT policy and replaces the direct policy subquery with a boolean-only
owner/key/size/MIME predicate. Existing intents and provider objects remain
unchanged; rollback is another reviewed forward policy repair.

`20260716330000_legal_original_failure_visibility_retry.sql` is an additive
browser-read/recovery cutover. It adds owner-safe status and reasoned
dead-letter retry RPCs without granting upload-session SELECT or changing
retention/deletion behavior. Rollback is a forward command/privilege repair;
existing retry jobs, receipts, audit events, outbox events, and preserved
originals remain immutable.

`20260716340000_vehicle_upload_failure_visibility_retry.sql` is an additive
browser-read/recovery cutover for vehicle upload verification. It adds an
owner-only status projection and a reasoned retry of only the exact current
dead-letter job. It does not change legal/signed-original behavior, provider
objects, retention, or deletion. Rollback is a forward command/privilege repair
that preserves every retry job, receipt, audit event, outbox event, and media
aggregate version.

## Verification and explicit runtime gap

Local verification on 2026-07-16 passed:

- strict `@vynlo/worker` TypeScript typecheck;
- focused media, browser-boundary, application, route, and worker Vitest suites,
  including deterministic oriented JPEG/PNG/WebP golden transformations across
  every configured derivative, stripped metadata/checksum receipts, upload
  policy, collection invariants, storage grants/writes, infected-file failure,
  and exact-lease orchestration;
- `pglast` parsing for the media migrations and pgTAP SQL;
- the repository Supabase static gate, including forced-RLS coverage and
  plan-balanced pgTAP assertions across the current suite.

Sharp/libvips processing and ClamD scanning are registered only behind the
media-processing runtime gate and readiness probes. Sharp's prebuilt libvips
can advertise an AVIF-capable HEIF buffer loader without providing HEIC/HEVC.
The worker therefore reports HEIC support only when the loader advertises an
actual `.heic` or `.heif` suffix and otherwise fails those inputs with
`media.heic_codec_unavailable` before decode. A production deployment that
enables HEIC must build Sharp against a custom libvips/libheif with an HEVC
decoder and pass a genuine HEIC orientation/derivative golden probe; see the
official [Sharp custom-libvips guidance](https://sharp.pixelplumbing.com/install/#custom-libvips).
Live pgTAP, private Storage, retry, signed-grant, scanner, and that deployment
codec acceptance still require Docker or a Supabase test project.

Automated deletion is a separate explicit activation gate. Amazon S3 now
documents `DeleteObject` with an `If-Match` ETag precondition, but this runtime
stores objects in Supabase and the media port conditions deletion on the
content SHA-256 rather than an unverified provider ETag. Supabase documents
conditional operations for S3 `HeadObject`/`GetObject`, but does not document an
`If-Match` or generation precondition for `DeleteObject`; the REST deletion API
also exposes no such contract. A prior GET/check followed by unconditional
DELETE is unsafe because a replacement can land between the calls. Therefore
`media.delete_retained_raw`, `media.delete_quarantine_upload`, and
`media.delete_legal_original_quarantine` handlers, and
the bounded maintenance producer that calls both enqueue RPCs, are implemented
and tested but intentionally not registered by `createWorkerService`. The
Supabase adapter raises `media.storage_atomic_delete_unsupported` before any
provider request. Enable all deletion consumers and the producer together only
as part of the Milestone 6 production-provider activation, after a configured
adapter proves how its provider validator binds to the stored content SHA-256
and passes the replacement-between-check-and-delete adversarial test with one
atomic conditional operation. See the official
[Amazon S3 conditional-delete API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObject.html),
[Supabase S3 compatibility matrix](https://supabase.com/docs/guides/storage/s3/compatibility),
and [Supabase delete-object guidance](https://supabase.com/docs/guides/storage/management/delete-objects).
