# Milestone 1 document-preview pipeline

Status: implemented as a forward-only database contract.

## Scope and traceability

This increment closes the deferred preview-render enqueue boundary from the first
vertical slice. It remains tenant-neutral and implements `M1-DOC-REQ-002`,
`M1-JOB-REQ-001`, `M1-TEN-REQ-001`, and `M1-AUD-REQ-001` through
`M1-DOC-AC-006` to `M1-DOC-AC-013`.

| Acceptance | Implementation evidence | Test evidence |
| --- | --- | --- |
| `M1-DOC-AC-006` | Forced-RLS `document_preview_jobs` binds a workspace document, outbox event, and durable job | `T-DOC-JOB-001`, `T-DOC-JOB-002`, `T-DOC-JOB-006` |
| `M1-DOC-AC-007` | The authenticated wrapper calls the preview command and generic enqueue in one transaction | `T-DOC-JOB-001` atomic failure probe |
| `M1-DOC-AC-008` | Canonical job type is `documents.render_preview`; payload schema 1 has four reference-only fields | `T-DOC-JOB-002`, `T-DOC-JOB-003` |
| `M1-DOC-AC-009` | Workspace/idempotency uniqueness and immutable mapping return the original document, event, and job | `T-DOC-JOB-004` |
| `M1-DOC-AC-010` | Base preview request and completion RPC grants are revoked after wrappers are installed | `T-DOC-JOB-001`, `T-DOC-JOB-007` |
| `M1-DOC-AC-011` | Service completion accepts only the worker HTML contract and an active durable-job lease | `T-DOC-JOB-007`, `T-DOC-JOB-009` |
| `M1-DOC-AC-012` | Forced-RLS append-only artifact provenance records storage, checksum, media, bytes, and renderer | `T-DOC-JOB-006`, `T-DOC-JOB-007`, `T-DOC-JOB-010` |
| `M1-DOC-AC-013` | Authenticated storage reads require an exact visible artifact bucket/path match | `T-DOC-JOB-006` storage policy and grant assertions |

## Transaction and API contracts

The browser calls:

```sql
app.request_document_preview_job(
  workspace_id uuid,
  idempotency_key text,
  deal_id uuid,
  template_version_id uuid,
  locale text,
  request_id text,
  correlation_id uuid
)
```

It returns `document_id`, preview state, watermark, `outbox_event_id`, `job_id`,
job state, and `replayed`. The security-definer wrapper still derives the user
from the authenticated session and delegates all permission, active-membership,
MFA, deal, template, and locale checks to the existing preview command. It then
calls `app.enqueue_outbox_job` before returning. PostgreSQL statement semantics
roll back the document, immutable render snapshot, audit rows, outbox event, job,
and mapping if any part fails.

The job contract is fixed to:

```json
{
  "document_id": "uuid",
  "locale": "en-CA",
  "render_input_checksum": "sha256",
  "template_version_id": "uuid"
}
```

No render snapshot, party, vehicle, template source, credential, or provider
payload crosses the durable queue boundary.

The worker calls:

```sql
app.complete_document_preview_artifact(
  workspace_id uuid,
  document_id uuid,
  job_id uuid,
  worker_id text,
  lease_token uuid,
  storage_bucket text,
  storage_object_path text,
  filename text,
  mime_type text,
  byte_size bigint,
  checksum text,
  renderer_version text,
  request_id text,
  correlation_id uuid
)
```

It returns `document_file_id`, `document_status`, and `replayed`. The current
synthetic renderer contract is deliberately narrow:

- filename: `preview.html`
- MIME: `text/html; charset=utf-8`
- renderer: `synthetic-html-v1`
- size: 1 to 10,000,000 bytes
- object path:
  `<workspace_id>/documents/<document_id>/preview/<sha256>.html`

Completion requires the supplied worker ID and lease token to match the
canonical mapped job's current unexpired active lease. This prevents a stale
worker from writing artifact or document terminal state after another worker
reclaims the job. It calls the existing document completion primitive and
appends artifact provenance in the same transaction. An exact replay under the
current lease returns the original file ID; changed storage, checksum, media,
byte count, renderer, document, job, lease, or correlation data fails closed.
The job runner separately calls
`app.complete_job` after the artifact RPC returns so the generic lease-fenced
attempt lifecycle remains authoritative.

## Authorization, RLS, and storage

Both pipeline tables explicitly enable and force RLS. An authenticated user may
read a row with `documents.read`, or their own requested row with
`documents.preview`. Cross-workspace rows remain hidden. Browser and service
roles have no direct insert, update, or delete access; all rows are append-only
even for trusted database roles.

`storage.objects` receives one authenticated `SELECT` policy. It permits a row
only when `(bucket_id, name)` exactly matches a `document_preview_artifacts` row
already visible through that table's workspace/requester RLS. Authenticated
storage insert, update, and delete privileges are revoked. This is sufficient
for the client storage API to request short-lived signed reads without exposing
a service-role route or allowing arbitrary bucket listing.

The deployment must create the worker-configured bucket as private. The database
validates its identifier and the deterministic object path, while the worker's
private-storage adapter owns the service-role write and byte-checksum validation.
Bucket public/private configuration is deployment state and is not inferred from
the bucket name.

## Audit, failure, and retry behavior

New requests append `document.preview_requested`, `job.queued`, and
`document.preview_job_queued`. Successful artifact registration appends
`document.preview_generated` and `document.preview_artifact_recorded`; generic
job completion appends `job.succeeded`. Exact replays do not duplicate these
events.

Render or storage failures continue through `app.fail_job`, bounded retries,
backoff, and dead-letter review. The preview document remains queued until a
valid artifact is recorded. The artifact RPC does not expose the old direct
failure transition; a terminal failed preview state should be introduced later
only with an explicit retry/dead-letter product policy.

The original preview-request audit metadata still contains
`outbox_enqueue_deferred: true` because that lower-level primitive remains usable
internally by the wrapper. `document.preview_job_queued` is the authoritative
evidence that the public wrapper completed the enqueue in the same transaction.

## Migration and verification notes

The change is forward-only in
`supabase/migrations/20260716130000_document_preview_pipeline.sql`. It adds two
tables, two wrappers, one deterministic-path helper, append-only triggers, RLS
policies, a storage read policy, and narrower function/table grants. It does not
rewrite existing preview documents. A legacy queued preview created before this
migration can acquire its mapping and job on its first wrapper replay; a legacy
terminal preview cannot be re-enqueued.

`supabase/tests/005_document_preview_pipeline.test.sql` contains 54 pgTAP
assertions covering schema, grants, forced RLS, MFA/permission/tenant denial,
atomic rollback, exact payload safety, idempotency conflicts, job claim state,
stale worker/lease rejection, deterministic artifact validation, audit events,
immutable history, storage authorization, and cross-workspace visibility.

Validated locally without a database runtime:

- the complete migration chain and pgTAP file parse with `pglast`;
- `pnpm check:supabase` passes with 33 forced-RLS tables and 364 total pgTAP
  assertions.

Runtime pgTAP still requires the local Supabase/PostgreSQL stack. Rollback is a
new corrective migration; do not delete populated mapping or artifact history.
