# Milestone 4 document and export worker execution

**Status:** Complete (verified 2026-07-17).

This worker slice implements only the tenant-neutral Milestone 4 durable jobs:

- `documents.render_pdf` loads a lease-fenced official snapshot, runs the
  bounded `@vynlo/documents` Liquid-style template compiler, disables browser
  JavaScript and external requests, prints genuine PDF bytes with
  Playwright/Chromium, verifies the exact private object, and records the
  generated-original receipt;
- `exports.generate` loads a lease-fenced authorized column plan, atomically
  captures one immutable workspace-scoped inventory, lead, or deal source
  manifest, pages only that manifest, generates deterministic CSV or Open XML
  XLSX through `@vynlo/exports`, verifies the exact private object, and records
  a receipt bound to the source-manifest ID, timestamp, row count, and checksum.

There is no provider adapter, tenant branch, arbitrary SQL, template
JavaScript, unrestricted URL, or Milestone 5 integration in either path.

## Durable settlement and retry behavior

The application transaction creates the outbox event and durable job before
the worker can observe it. The worker then uses the current worker ID and lease
token for every load, completion, and failure-evidence RPC.

The domain completion RPC records the immutable file and aggregate state but
does not settle the durable job. The domain failure RPC verifies the current
lease without predicting retry or dead-letter state. The handler rethrows the
original classified `JobExecutionError`; `DurableJobRunner` remains the single
authority that calls `complete_job` or `fail_job`. The canonical job-status
trigger then records the document/export lifecycle state and audit evidence.
This preserves the existing heartbeat, attempt, exponential-backoff, and
dead-letter behavior and prevents a double settlement race.

Storage writes are create-only (`x-upsert: false`) at checksum-derived keys.
Every write is read back by exact key. Byte count, SHA-256, MIME type, and the
provider generation/ETag must all match before database completion. A replay
with different bytes fails permanently instead of overwriting history.

## PDF safety and determinism

The official renderer accepts only `playwright-pdf-v1`. Template compilation
enforces the domain package's source, node, loop, asset, output, and checksum
limits. Only manifest assets with verified inline bytes are converted to data
URLs. A restrictive Content Security Policy is injected, browser JavaScript is
disabled, and every non-`about:`/non-`data:` request is aborted.

Chromium creation/modification timestamps are not business input. The worker
replaces only same-width timestamp digits, preserving PDF offsets while making
retry bytes stable. A result must have a PDF header, terminal EOF marker, and
stay below 50 MiB. Its completion receipt binds the authoritative official
number, source-bundle checksum, render-input checksum, version-snapshot
checksum, renderer version, and verified private-storage provenance.

## Export source registry

The registry allows only the starter platform report families and their
tenant-neutral fields:

| Family | Registered definitions | Source fields |
| --- | --- | --- |
| Inventory | `inventory_summary`, `inventory_aging`, `inventory_gross` | stock/workflow/acquisition/price/currency, vehicle identity/display, exact cost/gross, deterministic aging |
| Leads | `leads` | opaque reference, state, source, assignee display name, creation time |
| Deals | `deals` | opaque reference, type/state, exact line-item total, currency, update time |

Column plans are recompiled against this allowlist before source projection.
Filter names and values must satisfy the approved bounded JSON Schema at the
command boundary. Sort sources, permissions, row count, and source key are also
bounded. The snapshot function derives workspace scope from the lease-bound
run and writes source rows plus a manifest in the same transaction. Subsequent
pages and crash retries read only those append-only records.

PostgreSQL `bigint` money is cast to canonical decimal text while constructing
the snapshot JSON, before it crosses PostgREST or JavaScript. Deal quantity
multiplication then uses `BigInt` decimal scaling and half-away-from-zero
minor-unit rounding, never binary floating point. Inventory aging uses the
immutable snapshot capture timestamp as its clock. At run creation, the
approved sort specification is resolved against the post-authorization column
plan and persisted with an opaque unique source-ID tie-breaker. An empty sort
uses the first authorized output source, never a hidden business field. The
durable job and completion receipt both bind the resolved plan checksum.

Date-time filters require canonical RFC 3339 text with `Z` or an explicit
numeric offset, so PostgreSQL session time zones cannot reinterpret a filter.

Run idempotency is resolved from the stable actor command before current
activation and approval checks, so exact retries return the original pinned run
after configuration rotation. The fingerprint includes the normalized audit
reason, so a reused key cannot silently change why the export was requested.
Downloads reauthorize the definition permission, sensitivity step-up, and every
permission captured in the immutable column plan.

## Runtime configuration

All values are server-only:

| Variable | Rule |
| --- | --- |
| `VYNLO_DOCUMENT_BUCKET` | Existing private bucket for official generated originals |
| `VYNLO_EXPORT_BUCKET` | Existing private bucket for expiring exports |
| `PDF_RENDERER` | Must be `playwright` |
| `VYNLO_PDF_JOB_CONCURRENCY` | Integer 1–4; default 2 |
| `VYNLO_PDF_RENDER_TIMEOUT_MS` | 1,000–120,000 ms; default 60,000 |
| `VYNLO_EXPORT_JOB_CONCURRENCY` | Integer 1–4; default 2 |

The worker places PDF and export generation into separate bounded execution
lanes. Media concurrency remains separate, and ordinary invitation, VIN, and
preview jobs stay in the lightweight lane.

## Telemetry and operator response

Existing structured runner logs provide workspace, job type, job ID,
correlation ID, and attempt number without storage coordinates or customer
payloads. Completion summaries contain only opaque IDs, checksums, byte/row
counts, format/renderer version, aggregate version, and replay state.

Operators should:

1. retry transient browser, database, or storage failures through the durable
   job lifecycle;
2. inspect dead-letter jobs and the document/export audit event before a manual
   retry;
3. treat deterministic-path conflicts, snapshot mismatches, unsupported source
   paths, and unsafe bigint transport as configuration/data incidents, not as
   overwrite candidates;
4. never edit an active version or official snapshot to repair output—create
   and approve a new version or superseding official document.

Focused evidence is in the `official-document-*`, `export-*`, immutable storage,
runtime configuration, worker entrypoint, and durable-runner Vitest suites.
They cover `T-DOC-001`, `T-DOC-002`, `T-DOC-004..006`, `T-EXP-001..002`,
`T-JOB-003`, `T-STOR-001`, and `T-TEN-001` at the worker boundary.

## Exit evidence

The centralized install and full repository verification passed, including 846
Vitest tests and both production builds. All 36 database suites passed 1,976 of
1,976 assertions on fresh PostgreSQL after all 41 migrations and two seed
applications; the three Milestone 4 suites passed 199 of 199 assertions. The
portable runtime foundation gate passed against the same database.

An installed Chromium rendered the bounded official-document path twice. Both
outputs were valid PDFs and canonicalized to identical bytes and SHA-256 digest,
proving the retry determinism used by immutable storage completion. The final
phone/tablet/desktop browser matrix passed 174 journeys, including accessibility
and both supported locales. No provider adapter or Milestone 5 integration was
introduced.
