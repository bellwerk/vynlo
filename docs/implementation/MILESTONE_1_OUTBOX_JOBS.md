# Milestone 1 transactional outbox and durable jobs

**Recorded:** 2026-07-16

**Status:** Database and domain-policy source implemented; PostgreSQL runtime
acceptance pending

**Scope:** `VYN-JOB-001`, the job-operations portion of `VYN-OPS-001`, and the
tenant/security/audit controls needed by the first vertical slice

## Scope boundary

This is an additive foundation increment of
[Milestone 1](./IMPLEMENTATION_PLAN.md). It implements the transactional outbox
and durable-job primitives specified by
[ADR 0004](../architecture/adr/0004-transactional-outbox.md),
[API and job architecture](../architecture/API_AND_JOBS.md), and the
[job state machine](../data/STATE_MACHINES.md). It does not claim all of
Milestone 1 or `VYN-OPS-001` is complete.

The increment deliberately contains no provider adapter, tenant formula,
tenant-specific branch, browser enqueue endpoint, or direct external side
effect. Later source increments now call this contract from the
[document-preview pipeline](MILESTONE_1_DOCUMENT_PREVIEW_PIPELINE.md),
[preview worker](MILESTONE_1_PREVIEW_WORKER.md), invite-only command, and
[invitation worker](MILESTONE_1_INVITATION_DELIVERY_WORKER.md). Operational
dashboards, an accessible bilingual dead-letter UI, live provider
reconciliation, and a multi-session load test remain follow-up work.

## Persistence and security contract

The additive
[outbox/jobs migration](../../supabase/migrations/20260716110000_outbox_jobs.sql)
creates four workspace-scoped records:

- `outbox_events` is immutable event intent committed with the authoritative
  write. It preserves aggregate version, actor, schema version, correlation,
  causation, and a minimized JSON payload.
- `jobs` is the one mutable delivery projection. It preserves workspace,
  entity, payload version, stable idempotency key and request fingerprint,
  bounded attempt/backoff policy, lease fencing state, safe terminal summaries,
  correlation, causation, and optimistic version.
- `job_attempts` is append-only terminal attempt telemetry. A successful,
  failed, or reclaimed lease writes one record for the exact attempt and lease
  token.
- `job_admin_reviews` is append-only acknowledgement or replay evidence for
  dead-letter work.

Every table carries `workspace_id`, uses composite workspace foreign keys where
rows relate, enables and forces RLS, and prevents hard deletion. Authenticated
users can read only same-workspace metadata when they have `jobs.read`; job and
outbox payload columns are not granted to the browser. Browser roles have no
enqueue or lifecycle function access. The `service_role` has read access but no
direct insert/update/delete grant, so workers must use the fenced functions.

Payloads must be JSON objects and recursively reject credential-bearing keys.
They should contain identifiers, immutable version/checksum references, locale,
and other minimized routing data only. Tenant credentials remain encrypted
runtime records and are resolved by the provider adapter after claim. Safe error
text and result summaries are still application responsibilities: callers must
redact customer data and credentials before passing them to the database.

## Transaction API

An application command writes its authoritative business state and calls
`app.enqueue_outbox_job` before the same transaction commits. The function
validates the active workspace and actor membership, normalizes the
idempotency key, serializes the logical key with a transaction advisory lock,
and inserts the outbox event, job, and `job.queued` audit evidence atomically.
An exact retry returns the existing IDs with `created = false`; reuse of the key
with a changed request fingerprint raises SQLSTATE `23505`.

The service-only function signature is:

```sql
app.enqueue_outbox_job(
  p_workspace_id uuid,
  p_event_name text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_aggregate_version bigint,
  p_job_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload_schema_version integer,
  p_payload jsonb,
  p_idempotency_key text,
  p_correlation_id uuid,
  p_causation_id uuid default null,
  p_actor_user_id uuid default null,
  p_priority integer default 50,
  p_max_attempts integer default 8,
  p_available_at timestamptz default statement_timestamp(),
  p_backoff_base_seconds integer default 30,
  p_backoff_max_seconds integer default 3600,
  p_replay_of_job_id uuid default null,
  p_request_id text default null
)
returns table (
  outbox_event_id uuid,
  job_id uuid,
  created boolean,
  job_status text
)
```

The later preview wrapper implements this contract by keeping the document
insert, its domain audit event, and the enqueue call inside one database
transaction:

```sql
select queued.*
from app.enqueue_outbox_job(
  p_workspace_id => verified_workspace_id,
  p_event_name => 'document.preview_requested',
  p_aggregate_type => 'document',
  p_aggregate_id => new_document_id,
  p_aggregate_version => 1,
  p_job_type => 'documents.render_preview',
  p_entity_type => 'document',
  p_entity_id => new_document_id,
  p_payload_schema_version => 1,
  p_payload => jsonb_build_object(
    'document_id', new_document_id,
    'template_version_id', selected_template_version_id,
    'render_input_checksum', preview_snapshot_checksum,
    'locale', normalized_locale
  ),
  p_idempotency_key => normalized_preview_idempotency_key,
  p_correlation_id => request_correlation_id,
  p_actor_user_id => verified_actor_user_id,
  p_request_id => request_id
) queued;
```

The preview snapshot and credentials must not be copied into the job payload.
The worker reloads the authoritative, same-workspace document by ID and verifies
its immutable checksum/version before rendering. A failed enqueue must abort the
document insert; a failed document insert must leave no event or job.

## Worker lifecycle contract

The lifecycle API is service-only:

- `app.reclaim_expired_job_leases(limit)` records expired attempts and moves
  them to `retry_wait` or `dead_letter`.
- `app.claim_jobs(worker_id, limit, lease_seconds, job_types)` selects eligible
  work by priority and availability with `FOR UPDATE SKIP LOCKED`, increments
  the attempt, issues a unique lease token, and returns workspace/entity/payload,
  idempotency, lease, attempt, and correlation context.
- `app.heartbeat_job(job_id, worker_id, lease_token, extend_seconds)` extends
  only a live matching lease.
- `app.complete_job(...)` or `app.fail_job(...)` records exactly one terminal
  attempt and changes the job only when the worker and lease token still match.
- `app.cancel_job`, `app.acknowledge_dead_letter_job`, and
  `app.replay_dead_letter_job` require an active user with the immutable
  `jobs.manage` permission and append audit/review history.

A worker transaction must commit the claim before any provider call. The worker
uses the stable job ID/idempotency key as the provider idempotency scope,
heartbeats during long work, and never records success after its lease expires.
External adapters remain responsible for provider-supported idempotency and
reconciliation because a process can lose its lease after a provider accepts a
request but before local completion is recorded.

Retryable classifications are `transient`, `rate_limited`, and `unknown`;
lease expiry follows the same bounded-attempt behavior. Validation, permission,
provider-authentication, and permanent failures dead-letter immediately.
Retries use capped exponential equal jitter, honor a bounded provider
`Retry-After`, and never exceed the configured maximum of 32 attempts. Exhausted
or permanent work requires admin review. Replay creates a new job and outbox
event with a new idempotency key while preserving replay and causation lineage;
history is never rewritten.

## Shared TypeScript policy

The framework-neutral
[job policy](../../packages/jobs/src/job-policy.ts) mirrors the canonical states,
failure classification, bounded retry calculation, lease-owner decision, and
recursive credential-key check. Its
[unit suite](../../packages/jobs/src/job-policy.test.ts) covers normative and
forbidden transitions, retry classification, deterministic jitter and caps,
attempt exhaustion, permanent failure, invalid input, wrong/stale leases, the
exact lease-expiry boundary, and minimized payloads.

The package does not access Postgres or call a provider. Database functions are
the concurrency and persistence authority; the TypeScript policy gives worker
code a testable shared interpretation without duplicating tenant behavior.

## Acceptance mapping

| Acceptance ID | Criterion | Evidence | Status |
|---|---|---|---|
| `M1-JOB-AC-001` | An authoritative command, outbox event, durable job, and queue audit commit or roll back together. | `app.enqueue_outbox_job`; savepoint rollback and linked-row pgTAP cases. | Implemented; runtime pending. |
| `M1-JOB-AC-002` | Every outbox/job/history row preserves workspace context; browser reads are RLS-filtered and browser enqueue/actor spoofing is impossible. | Composite workspace FKs, forced RLS, column grants, active actor validation, negative pgTAP cases. | Implemented; runtime pending. |
| `M1-JOB-AC-003` | One logical workspace/job-type/idempotency key creates one job; exact normalized retries reuse it and changed input fails closed. | Unique key, canonical fingerprint, transaction advisory lock, idempotency pgTAP cases. | Implemented; independent-session stress pending. |
| `M1-JOB-AC-004` | Competing workers claim eligible work without waiting on already-claimed rows. | Priority/availability index and `FOR UPDATE SKIP LOCKED` claim query; SQL-shape assertion. | Implemented; multi-session runtime pending. |
| `M1-JOB-AC-005` | Heartbeat, expiry reclaim, and lease-token fencing prevent a stale worker from changing local terminal state. | Lease columns/checks, heartbeat/reclaim/complete functions, two-attempt reclaim pgTAP path, TS lease tests. | Implemented; runtime pending. |
| `M1-JOB-AC-006` | Retries are classified, bounded, exponentially backed off with jitter, and unavailable until due. | SQL and TypeScript retry policy; retry-wait, future-availability, exhaustion, permanent-failure cases. | Implemented; runtime pending. |
| `M1-JOB-AC-007` | Exhausted/permanent work dead-letters for authorized review; cancellation/replay is safe and history-preserving. | Dead-letter state, `jobs.manage` review/cancel/replay functions, append-only review rows, lineage tests. | Implemented; admin UI deferred. |
| `M1-JOB-AC-008` | Outbox, attempts, reviews, and audit evidence cannot be rewritten or deleted. | Immutable triggers, hard-delete guard, append-only mutation pgTAP cases, existing audit foundation. | Implemented; runtime pending. |
| `M1-JOB-AC-009` | Correlation, causation, attempt, worker, lease, provider-request, and safe failure fields make delivery observable without storing credentials. | Schema, lifecycle audit writes, secret-key checks, telemetry pgTAP and TS cases. | Implemented; live telemetry export deferred. |
| `M1-JOB-AC-010` | The exact migration and policy revision passes static, unit, type, lint, formatting, and database acceptance gates. | Validation record below and 71-assertion pgTAP suite. | Source gates pass; database runtime pending. |

This maps directly to stories `VYN-JOB-001` and the durable-job/attempt/admin
portion of `VYN-OPS-001`, while reusing `VYN-TEN-001`, `VYN-SEC-001`, and
`VYN-AUD-001`. The database suite covers `T-JOB-001`, `T-JOB-002`, and
`T-JOB-003`. It provides schema evidence toward `T-OPS-001`, but no dashboard or
alert-delivery acceptance is claimed.

## Test coverage

The
[pgTAP suite](../../supabase/tests/003_outbox_jobs.test.sql) declares 71
assertions covering:

- schema/function presence, service-only execution, and denial of direct worker
  or browser mutation;
- atomic rollback, linked outbox/job creation, normalized exact replay,
  changed-request conflict, workspace key isolation, and secret payload denial;
- same-workspace metadata read, cross-workspace non-disclosure, permission
  denial, and payload-column denial;
- `SKIP LOCKED`/advisory-lock query shape, claims, ownership fencing,
  heartbeat, expiry reclaim, new-token re-claim, and logical-job uniqueness;
- retry delay, attempt budget, permanent failure, dead letter,
  permission-checked acknowledgement/replay/cancel, and causation lineage;
- append-only outbox/attempt/review behavior, immutable workspace ownership,
  forced RLS, and correlated audit evidence without payload credentials.

The single-session suite proves invariants and SQL shape, not real two-session
lock scheduling. CI must add or run an independent-session claim/reclaim stress
test before production load is accepted.

## Operations and telemetry

Structured worker logs must include `workspace_id`, `job_id`, `job_type`,
`attempt_number`, `worker_id`, `lease_token` only where access-controlled,
`correlation_id`, `causation_id`, outcome, duration, error classification/code,
and provider request ID. Payloads, documents, customer fields, credentials, and
raw provider bodies do not belong in logs.

Initial metrics should include queue depth/age by job type, claim throughput,
attempt outcome and duration, retry schedule, heartbeat/reclaim counts,
dead-letter age, review/replay counts, and provider error classification. Alerts
and response steps should follow
[observability and incidents](../operations/OBSERVABILITY_BACKUP_INCIDENTS.md)
and the [runbook catalog](../operations/RUNBOOK_CATALOG.md): pause the affected
job type, preserve evidence, inspect provider drift/idempotency, correct input or
adapter behavior, then replay through the authorized command.

## Migration compatibility and rollback

The migration is additive after the tenancy/identity foundation and before
callers that enqueue work. It does not change an existing HTTP API, UI route, or
tenant seed. Once shared, do not edit the migration in place; corrections use a
later forward migration.

There is no destructive down migration. If behavior is defective:

1. feature-disable or pause the affected caller/job type;
2. stop claims while allowing in-flight leases to expire safely;
3. preserve all outbox, attempt, review, and audit history;
4. deploy a forward schema/function correction; and
5. resume or replay only after provider idempotency and drift are reconciled.

Dropping tables or deleting queue history is not a valid rollback.

## Verification record

Local source evidence recorded on 2026-07-16:

- `pnpm exec vitest run packages/jobs/src/job-policy.test.ts` passed 1 file and
  10 tests;
- `pnpm --filter @vynlo/jobs typecheck` passed;
- targeted ESLint passed (with the repository's non-blocking React-version
  detection warning for this non-React package);
- Prettier check and `git diff --check` passed for the owned files;
- `pglast` parsed the migration and 71-assertion pgTAP suite with PostgreSQL
  grammar; and
- the assertion counter matches the declared pgTAP plan.

Docker is not installed and no local Supabase daemon is available in this
environment. This evidence does not prove migration execution, constraints,
triggers, RLS evaluation, function privileges, pgTAP results, or real lock
contention. Acceptance still requires a clean `pnpm exec supabase db reset`,
`pnpm exec supabase test db`, and independent-session worker contention test on
the exact reviewed revision. A direct `pnpm exec supabase test db` attempt found
the CLI but failed to connect to a local Postgres service.

## Remaining follow-ups and residual risks

The transactional preview integration and worker lifecycle source follow-ups
from this foundation are implemented in the later preview/invitation delivery
records. Remaining work is:

1. Add provider-specific idempotency/external mapping and reconciliation. Lease
   fencing protects local state but cannot alone prevent a duplicated provider
   effect after an ambiguous timeout or process death.
2. Execute the 71 pgTAP assertions and multi-session claim/reclaim contention in
   Supabase CI; inspect claim/reclaim query plans at representative queue size.
3. Build phone-usable English/French admin review, retry, cancel, queue-health,
   empty/error, and accessible status flows; no UI acceptance is claimed here.
4. Export metrics/traces and validate alert thresholds, dead-letter response,
   recovery time, and replay runbooks. `VYN-OPS-001` remains incomplete until
   these observable operations are exercised.
5. Treat the recursive key denylist as defense in depth. Service callers still
   own payload minimization and safe-text redaction, and a compromised trusted
   service credential remains capable of misattribution within an active
   workspace even though browser actor spoofing is denied.
