# Database tests

`001_tenancy_identity_rls.test.sql` is the 83-assertion pgTAP suite for
T-AUTH-002, T-AUTH-003, T-AUTH-004, T-TEN-001, T-RBAC-001, and T-AUD-001. It
verifies inactive user/membership denial, missing permissions, AAL2 and
15-minute step-up behavior, cross-workspace reads/writes/links, protected actor
fields, workspace settings versions, invitation lifecycle/token controls,
permission-key/MFA invariants, lifecycle-only deletion, scoped audit attribution,
service-only audit append, non-disclosure, and audit immutability.

Run against a local Supabase stack:

```sh
pnpm supabase:start
pnpm supabase:reset
pnpm exec supabase test db
```

The seed contains two fictional, deterministic workspace boundaries:

- `10000000-0000-4000-8000-000000000001` — Northstar Motors Test
- `20000000-0000-4000-8000-000000000002` — Harbour Auto Lab

Fixture Auth users have no provider identity row, and every password hash is
generated from a random unknown value. Tests authenticate them by setting
transaction-local Supabase JWT claims; they cannot be used for interactive login
with a known credential. The runtime checker reapplies the seed once to prove
idempotent fixture setup before validating counts.

`006_invite_only_auth.test.sql` adds 55 assertions for `T-AUTH-001`,
`T-AUTH-002`, `T-AUTH-004`, `T-TEN-001`, `T-RBAC-001`, `T-AUD-001`, and
`T-JOB-001`. It covers recent-AAL2 invitation authorization, role scope,
workspace isolation, exact non-PII delivery payloads, leased worker reads,
provider endpoint selection state, matching-email activation, failure/terminal
states, idempotency, atomic audit evidence, and append-only command history.

`007_inventory_workflow_foundation.test.sql` adds 97 assertions for
`VYN-INV-001`, `VYN-WF-001`, `T-INV-004`, `T-TEN-001`, `T-RBAC-001`,
`T-AUD-001`, and the local `M2-INV-AC-*` acceptance IDs. It covers forced RLS,
browser DML denial, semantic workflow versions, activation/retirement
immutability, allowlisted declarative effects, complete MFA grant/downgrade/
reactivation invariants, compatible M1 creation, immediate aggregate projection
checks, hidden-note isolation, cross-workspace denial, exact idempotent replay,
optimistic concurrency, location history, workflow transition guards and
reasons, terminal-state immutability, audit/outbox parity, composite ownership,
and append-only history under trusted roles.

`008_durable_vin_decode.test.sql` adds 58 assertions for normalized VIN enqueue,
immutable provider provenance, minimized jobs, lease fencing, duplicate
snapshots and decisions, manager step-up, retry/dead-letter behavior,
idempotency, audit/outbox parity, forced RLS, and workspace isolation.

`009_media_pipeline.test.sql` adds 79 assertions for immutable profile
lifecycle/roll-forward, exact upload and processing leases, deterministic
derivatives, collection aggregate versions, preserved legal-original receipts,
audited download authorization, direct object-read denial, legal/incident hold
lifecycle, and raw-deletion/hold race fencing.

`010_inventory_cost_search.test.sql` adds 65 assertions for exact integer-minor
cost posting above the JavaScript safe-integer boundary, append-only reversals,
derived effective status, supporting-file workspace/owner/class/readiness
fences, bounded search and cursors, cost-field masking, and validated private
saved views.

`011_inventory_intake_from_vin.test.sql` adds 40 assertions for canonical
confirmed-result consumption, duplicate-state rechecks, permanent concurrent
stock allocation, idempotent replay/conflict handling, immutable intake
lineage, audit/outbox evidence, browser denial of legacy allocation, and
cross-workspace rejection. It also verifies explicit create-versus-link results,
open-unit authoritative-fact conflict rejection, compatible null-fact fill with
optimistic-version advancement, and fail-closed rejection of inventory details
that an existing-unit link cannot apply.

`012_media_upload_verification.test.sql` adds 36 assertions for mandatory
expected checksums, exact upload size/MIME storage policy enforcement, durable
verification jobs, lease and generation fencing, clean/rejected malware paths,
idempotent completion, and audit/outbox evidence.

`013_media_quarantine_cleanup.test.sql` adds 47 assertions for durable bounded
cleanup scheduling, expired and terminal-rejection eligibility, exact minimized
job payloads, workspace/session/generation/checksum fencing, lease isolation,
idempotent checksum and completion replay, audit/outbox/job-attempt telemetry,
forced RLS, browser denial, append-only provenance, and legal-original
exclusion. Provider replacement-race behavior is covered by worker Vitest
because pgTAP does not operate the external object store.

`014_legal_original_upload_verification.test.sql` adds 44 assertions for exact
legal/signed intents, size/MIME Storage fencing, recent strong authentication,
workspace and actor isolation, minimized durable jobs, active-lease worker
loads, scan/provenance receipt completion, rejection, forced RLS, and a separate
expired/rejected quarantine cleanup lineage. It proves completed preserved
originals are cleanup-ineligible and that cleanup generation/checksum/MIME/size
fences, audit, and outbox state are immutable. External provider deletion stays
covered by worker adversarial tests and remains runtime-disabled without an
atomic conditional-delete primitive.

`015_m2_vehicle_media_management.test.sql` adds 32 assertions for exact safe
media projections, legal-original non-disclosure, caption/archive concurrency
and idempotency, order compaction, cover promotion, forced RLS, direct-provider
coordinate denial, and matching audit/outbox versions.

`016_m2_inventory_operations.test.sql` adds 64 assertions for exact inventory
operator reads, internal/cost masking, active localized locations and cost
categories, bounded cost cursors, owner/shared saved-view list/load/archive,
workspace isolation, recent-AAL and permission denial, full-snapshot vehicle
fact correction, optimistic/idempotency conflicts, immutable before/after
history, minimized outbox payloads, audit parity, forced RLS, browser DML
denial, and append-only provenance.

`017_document_preview_download_authorization.test.sql` adds 20 assertions for
artifact visibility, browser-safe columns, audited actor-idempotent
authorization, conflicting replay, expiry/TTL bounds, workspace isolation,
service-only coordinate loading, and append-only forced-RLS receipts.

`018_m2_vin_intake_completion.test.sql` adds 44 assertions for active location
and condition enforcement, exact decode-result confirmation, terminal-job-only
manual facts, request consumption, actor idempotency, immutable receipts,
workspace and permission isolation, recent-AAL enforcement, audit/outbox
linkage, and permanent stock allocation. It also proves conflicting manual facts
cannot link an open unit, terminal consumption preserves visible dead-letter
history without retry/review eligibility, rejects silently discarded details
on manual open-unit links, and proves two independently reviewed
requests can link to the same open unit with distinct request receipts while
returning one stock number and consuming one allocation.
Consumed manual requests reject both replayed and fresh decode-retry commands
before any new job, audit, or outbox side effect.

`019_managed_media_download_authorization.test.sql` adds 27 assertions for the
opaque managed-media authorization contract, actor-scoped idempotency and
conflict behavior, expiry bounds, workspace/file visibility, browser coordinate
non-disclosure, service-only exact-coordinate loading, and append-only
forced-RLS authorization receipts.
Signed originals additionally require the restricted-file permission and
recent AAL2. Stale vehicle-photo generations are denied both before
authorization and when resolving an earlier grant.

`020_m2_media_security_hardening.test.sql` adds 22 assertions for revoked
vehicle/legal implementation helpers, service-only lease-fenced wrappers,
same-owner wrapper composition, fixed search paths, legal upload-session
coordinate non-disclosure, the boolean-only Storage policy predicate, exact
metadata acceptance, mismatch rejection, and direct browser/service table and
helper denial.

`021_m2_actor_idempotency_hardening.test.sql` adds 45 assertions for explicit
actor-key indexes, removal of the shared physical key constraints, strict
wrapper/search-path and private-helper grants, same-actor legacy replay
compatibility, and digest-shaped cross-user poisoning regressions across
inventory detail, transfer, workflow transition, exact cost post/reversal,
vehicle upload intent/verification, reorder, cover, caption, and archive
commands. It also checks receipt-to-audit/outbox actor parity without claiming
live provider or database integration outside the pgTAP environment.

`022_vehicle_upload_storage_policy_hardening.test.sql` adds 16 assertions for
the boolean-only vehicle Storage predicate, fixed search path and narrow grants,
authenticated upload-session non-disclosure, removal of the stale SELECT
policy, exact owner/key/size/MIME acceptance, metadata mismatch and cross-actor
denial, and preservation of the restricted media completion helpers.

`023_legal_original_failure_visibility_retry.test.sql` adds 39 assertions for
the browser-safe status projection, continued upload-session non-disclosure,
workspace/permission/owner and signed-step-up enforcement, bounded safe
dead-letter visibility, actor-scoped raw-key replay and conflict behavior,
cross-actor key isolation, stale/rejected-state denial, copied scheduling
policy, causation/replay lineage, and reason/audit/outbox parity.
It also proves inaccessible IDs share absent-ID semantics, generic cancellation
remains a safe parseable terminal state, and retry through terminal rejection
and quarantine cleanup allocates one monotonic aggregate event lineage.

`024_vehicle_upload_failure_visibility_retry.test.sql` adds 34 assertions for
the owner-safe vehicle upload projection, narrow RPC grants and return shape,
workspace/owner indistinguishability, bounded dead-letter visibility, separate
terminal rejection, explicit retry reason, exact source-job and aggregate
locking, copied scheduling policy, causation/replay lineage, actor-aware raw-key
namespaces, audit/outbox parity, stale active-job denial, and deterministic
receipt replay/conflict behavior after a later terminal transition.
