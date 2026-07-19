# Milestone 1 document preview worker

**Recorded:** 2026-07-16

**Status:** Worker source implemented and locally verified; live Supabase/Storage
acceptance pending

**Scope:** Worker half of `VYN-JOB-001`, `VYN-DOC-001`, and the
`documents.render_preview` Milestone 1 pipeline

## Delivered behavior

The preview handler consumes only the canonical `documents.render_preview` job.
The same durable worker process also handles the separately documented
[`auth.invitation.deliver` flow](MILESTONE_1_INVITATION_DELIVERY_WORKER.md). The
preview path uses
the service-only durable-job functions from the
[outbox migration](../../supabase/migrations/20260716110000_outbox_jobs.sql)
and the artifact transaction from the
[preview-pipeline migration](../../supabase/migrations/20260716130000_document_preview_pipeline.sql).
It contains no tenant branch, official-number path, template JavaScript,
browser credential, or public artifact URL.

The implementation adds:

- strict mapping of the claim RPC, including the stable `idempotency_key`;
- expired-lease reclaim before each claim batch;
- runner-managed, non-overlapping lease heartbeats independent of handler code;
- heartbeat failure cancellation through `AbortSignal`, with the heartbeat
  drained before a fenced `complete_job` or `fail_job` call;
- strict preview payload and authoritative document/template validation;
- deterministic HTML interpolation with an explicit placeholder allowlist and
  HTML escaping;
- fixed `DRAFT / NON-PRODUCTION` watermarking with no official number;
- deterministic SHA-256 checksum and workspace/document-scoped object path;
- private Supabase Storage REST upload with create-only semantics and
  byte/checksum verification on an exact retry;
- transactional artifact provenance through
  `app.complete_document_preview_artifact`; and
- an import-safe, Node 24 ESM bundled process entrypoint with bounded
  polling/backoff, structured secret-free logs, and graceful
  `SIGINT`/`SIGTERM` draining.

## Acceptance mapping

| Acceptance ID | Criterion | Evidence | Status |
|---|---|---|---|
| `M1-WORKER-AC-001` | Claims preserve workspace, correlation, attempt, lease, payload version, and stable idempotency context. | `PostgrestJobStore` mapping and contract tests. | Implemented. |
| `M1-WORKER-AC-002` | Long handlers renew their lease without handler cooperation; each renewal has an abortable deadline before lease expiry, renewals never overlap, and they stop before terminal job mutation. | Managed heartbeat plus long-handler, stalled-heartbeat timeout, heartbeat-failure, in-flight-drain, and no-overlap tests. | Implemented. |
| `M1-WORKER-AC-003` | Lost heartbeat aborts new handler I/O and becomes a classified transient failure without persisting transport details. | Handler `AbortSignal`, safe `worker.heartbeat_failed`, negative leakage test. | Implemented. |
| `M1-WORKER-AC-004` | Preview jobs accept only payload schema 1 for the matching document entity and four minimized routing fields. | Exact-key parser and malformed/extra/mismatched payload tests. | Implemented. |
| `M1-WORKER-AC-005` | Rendering is deterministic, escaped, watermarked, unnumbered, non-production, and free of executable/remote template content. | Renderer invariants, source checksum check, explicit placeholder allowlist, deterministic-output tests. | Implemented. |
| `M1-WORKER-AC-006` | Artifacts use a deterministic private key/checksum and an identical retry cannot overwrite different bytes. | Storage adapter create-only upload, authenticated replay readback, collision tests, database deterministic-key validation. | Implemented; live bucket pending. |
| `M1-WORKER-AC-007` | Document/file provenance is recorded transactionally under the matching current worker lease before the durable job is completed, and exact retries return the same artifact. | Lease-token/worker-ID `complete_document_preview_artifact` adapter, stale-lease pgTAP cases, and replay handler/repository tests. | Implemented; database runtime pending. |
| `M1-WORKER-AC-008` | The process has validated server-only configuration, bounded idle/error timing, structured safe logs, and graceful draining. | Runtime config, poll service, direct-entry guard, shutdown/backoff tests. | Implemented. |

## Preview render contract

The claimed job must have:

- job type `documents.render_preview`;
- entity type `document` and an entity ID matching `payload.document_id`;
- payload schema version `1`; and
- exactly `document_id`, `template_version_id`,
  `render_input_checksum`, and `locale` in its payload.

The worker reloads the document and template through service-role PostgREST
reads scoped by both `workspace_id` and ID. It verifies the exact template,
locale, snapshot checksum, preview mode, null official number, fixed watermark,
synthetic template class, non-production approval state, renderer version, and
SHA-256 source checksum before rendering. A retired immutable template version
may finish already-queued work; altered or unrelated source may not.

Only these placeholders are supported:

```text
{{ watermark }}
{{ deal.id }}
{{ deal.deal_type_key }}
{{ deal.currency_code }}
{{ participants[0].display_name }}
{{ inventory_units[0].stock_number }}
{{ inventory_units[0].vin }}
```

Every value is rendered as an HTML-escaped scalar. Unknown/missing/non-scalar
placeholders, Liquid control syntax, scripts, event handlers, embedded objects,
JavaScript URLs, remote sources, checksum drift, or production/official state
fail closed without retrying a configuration defect.

The output is UTF-8 `text/html; charset=utf-8`, named `preview.html`, rendered by
`synthetic-html-v1`, and limited to 10 MB. Its object path matches the database
function exactly:

```text
<workspace_id>/documents/<document_id>/preview/<sha256>.html
```

The worker uploads with `x-upsert: false` to
`/storage/v1/object/<bucket>/<path>`. A conflict is successful only after an
authenticated private read proves the existing byte count and checksum are
identical. The adapter never calls the public-object endpoint.

After storage, the worker calls the app-schema RPC with
`Content-Profile: app`:

```text
app.complete_document_preview_artifact(
  workspace_id, document_id, job_id,
  worker_id, lease_token,
  storage_bucket, storage_object_path,
  filename, mime_type, byte_size, checksum,
  renderer_version, request_id, correlation_id
)
```

The artifact transaction rejects a stale worker ID or lease token even if a
replacement worker currently owns an otherwise valid running lease. Only after
that transaction returns does the runner call `app.complete_job`. All worker RPC
requests set `Content-Profile: app`; ordinary `public` table reads retain the
default profile.

## Runtime configuration

Required server-only environment:

| Variable | Purpose |
|---|---|
| `VYNLO_SUPABASE_URL` | HTTPS Supabase project URL; HTTP is accepted only for loopback development. |
| `VYNLO_SUPABASE_SERVICE_ROLE_KEY` | Server-only service credential used for app RPCs, private storage, and exact source reads. Never expose or log it. |
| `VYNLO_WORKER_ID` | Stable non-secret worker instance identifier, maximum 200 characters. |
| `VYNLO_PREVIEW_BUCKET` | Existing private Storage bucket identifier. The worker does not create or make a bucket public. |

Optional bounded tuning:

| Variable | Default | Bounds |
|---|---:|---:|
| `VYNLO_WORKER_LEASE_SECONDS` | `60` | `5..900` |
| `VYNLO_WORKER_HEARTBEAT_INTERVAL_MS` | one third of lease | `100 ms..half of lease` |
| `VYNLO_WORKER_BATCH_SIZE` | `10` | `1..100` |
| `VYNLO_WORKER_POLL_INTERVAL_MS` | `1000` | `100..60000` |
| `VYNLO_WORKER_ERROR_BACKOFF_BASE_MS` | `1000` | `100..60000` |
| `VYNLO_WORKER_ERROR_BACKOFF_MAX_MS` | `30000` | base through `300000` |

Build and run:

```sh
pnpm --filter @vynlo/worker build
pnpm --filter @vynlo/worker start
```

Importing `src/index.ts` does not start polling. The process starts only when
the built module is the direct Node entrypoint. `SIGINT` or `SIGTERM` stops new
polls and waits for the active batch, including its managed heartbeats, to
settle before exit.

## Operations and failure behavior

Each batch reclaims expired leases through the app-schema RPC, claims only
registered job types with `FOR UPDATE SKIP LOCKED`, then runs the bounded batch.
An empty queue sleeps for the configured poll interval. Poll failures use
capped exponential equal jitter; successful polls reset the failure count.

Logs contain stable operational fields such as worker/job/workspace IDs,
correlation ID, job type, attempt number, claimed/reclaimed counts,
classification, machine error code, and retry delay. They omit job payloads,
snapshots, rendered HTML, customer fields, service credentials, Storage response
bodies, and database error details.

The process should be paused before rotating the private bucket or service
credential. On repeated dead letters, preserve artifact/job/audit evidence,
inspect the safe machine code, verify the immutable template/source checksum and
private bucket policy, correct the configuration or adapter, and replay through
the authorized database command. Do not edit job, document, artifact, or audit
history.

## Verification and remaining runtime acceptance

Local verification on 2026-07-16 passed:

- 13 worker Vitest files and 68 tests covering unit, invariant, failure, replay,
  lease, escaping, storage, RPC shape, configuration, polling, and graceful
  shutdown behavior;
- strict worker TypeScript typecheck, bundled production build, and direct
  import smoke assertion;
- targeted ESLint with zero warnings (apart from the repository's informational
  React-version detection message for this non-React package);
- Prettier, Secretlint, `git diff --check`, and repository Markdown link checks.

These source gates do not prove a live private Storage policy, PostgREST schema
profile, database function execution, lease timing over a real network, or
process-signal behavior in the deployment runtime.

Still required in an environment with local Supabase/Storage:

1. create or verify the configured bucket is private;
2. reset the database through migration `20260716130000` and seed the exact
   synthetic templates;
3. request one preview through `app.request_document_preview_job` and run the
   worker until both document and job succeed;
4. verify the stored bytes/checksum/path and same-request replay;
5. kill a worker during upload and after artifact completion to exercise lease
   reclaim and ambiguous-response recovery; and
6. confirm no public Storage URL, payload, snapshot, rendered customer data, or
   service credential appears in logs or browser responses.
