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

`025_m3_workflow_hardening.test.sql` adds 48 assertions for immutable workflow
definitions and versions, checksum and compatibility activation, pinned
instances, declarative guards, required fields, permissions, recent-AAL2
administration, optimistic concurrency, reasoned transitions, actor-scoped
idempotency, forced RLS, audit, and inert outbox evidence.

`026_m3_typed_custom_fields.test.sql` adds 69 assertions for versioned bilingual
definitions, supported typed values, exact decimals and money, active option
sets, same-workspace party, location, user, and inventory references,
sensitivity masking, visibility/edit and inventory-read permissions, core-field
shadow rejection, optimistic concurrency, immutable definition provenance,
forced RLS, and audit evidence.

`027_m3_starter_configuration.test.sql` adds 40 assertions for tenant-neutral
starter role permissions, localized workflow/deal-type configuration,
checksum-bound bilingual role/event option labels, configuration-driven lead
conversion/loss and deal cancellation semantics, valid immutable references,
and the absence of tenant-specific runtime logic.

`028_m3_party_crm_foundation.test.sql` adds 67 assertions for person and
organization parties, normalized contacts, structured addresses, masked
identifiers, communication preferences, same-workspace relationships, bounded
safe projections, deterministic legacy profile materialization, optimistic
concurrency, archive behavior, RLS, authorization, audit, and idempotency.

`029_m3_deal_foundation.test.sql` adds 75 assertions for immutable deal-type
versions, exact bilingual configured participant/inventory/payment options,
configured-role projections, exact line items, authorized active custom-field
workflow checks, cash and external-finance policies, active-sale conflict
prevention, workspace isolation, optimistic concurrency, RLS, audit, and outbox
parity.

`030_m3_lead_timeline_tasks_appointments.test.sql` adds 78 assertions for leads,
inventory interest, configured transitions, append-only activities, versioned
tasks, timezone-explicit appointments, participant and inventory reservations,
reasoned outcomes, authorized active custom-field transition requirements,
actor-idempotent conversion, concurrency, authorization, forced RLS, audit, and
outbox evidence.

`031_m3_trade_ins_external_finance.test.sql` adds 79 assertions for distinct
trade-in facts and separately confirmed inventory creation, lender-reported
amounts and exact rates, finance status history, immutable condition replacement
lineage, satisfaction, expiry, permissions, recent authentication where
required, workspace isolation, forced RLS, concurrency, audit, and outbox
evidence.

`032_m3_one_time_payment_ledger.test.sql` adds 58 assertions for exact
minor-unit one-time events, settlement, dedicated refund/reversal permissions,
recent-AAL2 protection, immutable originals, same-deal correction lineage,
actor-scoped idempotency, row-lock concurrency defenses, workspace isolation,
forced RLS, proof masking, strict operator-ledger evidence, receipt generation,
audit, and outbox parity.

`033_m3_end_to_end_exit.test.sql` adds 32 assertions for the milestone exit
criteria. It carries a lead through conversion into one cash deal and one
third-party-financed deal, including valid parties, inventory roles, exact line
items, one-time money settlement, reasoned correction, and the absence of
recurring-servicing artifacts.

`034_m4_configuration_numbering_runtime_evidence.test.sql` adds 64 assertions
for checksum-bound configuration lifecycle commands, exact append-only
approvals, optimistic numbering-version creation, permanent monotonic
allocation and replay, UTC/official-document allocation semantics, forced RLS,
historical/future tax-assignment cutover, and service-only
actor/workspace/version-bound calculation evidence. All configuration and
execution fixtures are tenant-neutral and rolled back.

`035_m4_documents_numbering_lifecycle.test.sql` adds 82 assertions for preview
permission, watermarking, regeneration and idempotency; exact approved official
issuance; bounded fail-closed field-schema validation; deal-checksum-bound,
single-consumption runtime receipts and replay after receipt expiry; atomic
number/outbox/job/attempt creation; immutable render receipts and files; opaque
download grants; permission- and expected-version-guarded supersession;
replacement failure/success behavior; durable dead-letter status
synchronization; reasoned retry; failure-preserving, actor-idempotent void
recovery; fresh-successor and concurrent-claim serialization; audit evidence;
and workspace/RLS isolation. The official fixture approvals exist only inside
the rolled-back test transaction.

`036_m4_exports_reports_jobs.test.sql` adds 53 assertions for exact approved
CSV/XLSX plans, sensitive step-up, actor idempotency, durable worker leases,
crash-window replay, append-only paged source snapshots, exact bigint text
transport, bounded filter schemas, verified storage receipts, per-column
download reauthorization, opaque downloads, guarded run lifecycle/dead-letter
synchronization, forced RLS, report
pagination/date/workspace guards, and exact fractional minor-unit line rounding
before summation. Together, the Milestone 4 database suites contain 199 pgTAP
assertions.
