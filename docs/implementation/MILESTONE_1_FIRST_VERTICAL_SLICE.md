# Milestone 1 first vertical slice

**Status:** Data/domain foundation plus subsequent API, UI, preview-pipeline, and
worker source integration implemented; runtime acceptance remains open

**Migration:** `supabase/migrations/20260716120000_first_vertical_slice.sql`

**Database test:** `supabase/tests/004_first_vertical_slice_rls.test.sql`

## Scope and boundary

This increment implements the smallest tenant-neutral data path from a physical
vehicle and inventory holding episode through a party and linked deal draft to
an unnumbered synthetic document preview request. It follows the
[Milestone 1 delivery sequence](IMPLEMENTATION_PLAN.md), the
[logical PostgreSQL model](../data/POSTGRES_SCHEMA_SPEC.md), and the
[RLS policy matrix](../data/RLS_POLICY_MATRIX.md).

This migration increment deliberately did not complete the whole Milestone 1
exit criterion. Subsequent source increments now provide the web routes,
mobile-first bilingual operations UI, transactional preview enqueue, worker
renderer, and private artifact mapping described in
[the end-to-end record](MILESTONE_1_END_TO_END.md). Official documents,
payments, tenant formulas, tenant legal wording, and production-provider
acceptance remain outside this slice. The synthetic template is test-only and
is structurally prohibited from being production-approved.

## Acceptance and traceability

The local acceptance IDs below apply to this implementation increment. Stable
Release 1 test IDs remain authoritative in the
[test-case catalogue](../testing/TEST_CASE_CATALOG.md).

| Acceptance ID | Requirement and test IDs | Implemented evidence | State |
|---|---|---|---|
| `M1-SLICE-AC-001` | `VYN-INV-001`, `T-INV-001` | `vehicles` stores physical identity separately from `inventory_units`; a later closed holding episode can reuse the vehicle without reusing the stock allocation. | Foundation implemented |
| `M1-SLICE-AC-002` | `VYN-INV-002`, `T-INV-002` | TypeScript and SQL normalize typed/pasted VINs to uppercase and accept exactly 17 valid characters; camera scanning is absent. Conflicting stored facts require controlled review. | Minimal create validation implemented; provider decode and duplicate-review UI deferred |
| `M1-SLICE-AC-003` | `VYN-NUM-001`, `T-NUM-001`, `T-NUM-002`, `T-NUM-003` | A locked per-definition counter, append-only allocation, composite uniqueness, request fingerprint, and idempotency key allocate the stock number in the inventory transaction. Validation failures roll back before allocation; committed numbers cannot be deleted or changed. | Core invariant implemented; true multi-connection load test pending |
| `M1-SLICE-AC-004` | `VYN-CRM-001`, `T-CRM-001` | `app.create_party` creates an idempotent workspace-owned person or organization with normalized display name and audit. | Party foundation only; contacts, leads, consent, tasks, and timeline deferred |
| `M1-SLICE-AC-005` | `VYN-DEAL-001`, `T-DEAL-001` | `app.create_deal_draft` derives the owner membership and atomically creates the draft, primary party role, and inventory role. Composite foreign keys reject cross-workspace links. | Minimal draft implemented; workflow, line items, totals, trade-ins, and close/cancel commands deferred |
| `M1-SLICE-AC-006` | `VYN-DOC-001`, `T-DOC-001` | `app.request_document_preview` stores a server-built snapshot as `queued`, fixes the watermark to `DRAFT / NON-PRODUCTION`, and requires `official_number IS NULL`. The later preview wrapper, artifact transaction, and worker integrate enqueue/render/private persistence. | Source path integrated; database/Storage runtime pending |
| `M1-SLICE-AC-007` | `VYN-TEN-001`, `T-TEN-001`, `T-TEN-002` | Every new table has forced RLS. Workspace ownership is direct and composite foreign keys protect links. Strict route DTOs omit authoritative workspace and owner fields; SQL permissions reject another workspace. | Database/application/API boundary implemented; database runtime pending |
| `M1-SLICE-AC-008` | `VYN-SEC-001`, `VYN-AUTH-002`, `T-RBAC-001`, `T-AUTH-002` | Browser roles receive read plus command execution, not table mutation. Commands use immutable permission keys through `app.has_permission`; existing membership policy makes an MFA-required role fail at AAL1. | Implemented for exposed commands |
| `M1-SLICE-AC-009` | `VYN-AUD-001`, `T-AUD-001` | Inventory, party, deal, preview request, preview success, and preview failure actions append correlated audit events in the same transaction as their state change. | Implemented for this slice |
| `M1-SLICE-AC-010` | `VYN-UX-001`, `VYN-I18N-001`, `T-UX-001`, `T-I18N-001` | Flat serializable command DTOs use integer minor units, locale keys, and small step-sized payloads without workspace authority or camera input. Subsequent forms are step-based, bilingual, permission-aware, and mobile-first. | Source UI and mocked E2E evidence implemented; live journey pending |

`T-NUM-002` is only partially closed: invalid input and failed transactions do
not persist an allocation, but a persisted multi-step inventory draft does not
exist yet. `T-TEN-002`, `T-UX-001`, and `T-I18N-001` now have API/UI source and
mocked-browser evidence; live database/provider execution remains open.

## Database contract

### Tables

| Group | Tables | Invariants |
|---|---|---|
| Inventory and numbering | `stock_number_definitions`, `stock_number_counters`, `stock_number_allocations`, `vehicles`, `inventory_units` | Permanent values are unique by workspace and definition, idempotency is workspace-scoped, the allocation and inventory references are transactionally deferred as one cycle, active duplicate holding episodes are blocked, and a physical vehicle is separate from its holding episode. |
| CRM and deals | `parties`, `deals`, `deal_participants`, `deal_inventory_units` | The deal owner is an active membership derived from the authenticated user. Party and inventory links use composite workspace foreign keys. One active `sold` link per inventory unit prevents conflicting drafts. |
| Preview documents | `document_types`, `document_template_versions`, `documents` | Only synthetic non-production template versions are allowed. Template source and render input are immutable. The document mode is always `preview`, the official number is always null, and the only lifecycle is `queued -> generated | failed`. |

All money in this slice uses integer minor units plus a three-letter currency
code. No binary floating-point financial value is stored.

### SQL command surface

The API/application layer should call these functions after resolving the
selected workspace from a validated route or header. A body field must never
become the authoritative workspace source.

| Function | Result | Authorization |
|---|---|---|
| `app.create_inventory_unit(uuid, uuid, text, text, integer, text, text, date, bigint, text, text, bigint, text, text, uuid)` | `(inventory_unit_id uuid, vehicle_id uuid, stock_number text, replayed boolean)` | Active membership plus `inventory.create`; existing role/workspace MFA policy applies. |
| `app.create_party(uuid, text, text, text, text, uuid)` | `(party_id uuid, replayed boolean)` | Active membership plus `crm.create`. |
| `app.create_deal_draft(uuid, text, text, text, uuid, text, uuid, text, text, text, uuid)` | `(deal_id uuid, participant_id uuid, inventory_link_id uuid, replayed boolean)` | `deals.create`, `crm.read`, and `inventory.read`; owner membership is derived. |
| `app.request_document_preview_job(uuid, text, uuid, uuid, text, text, uuid)` | Document/preview state plus immutable outbox/job IDs and replay state | `documents.preview`, `deals.read`, `crm.read`, and `inventory.read`; document and job commit together. |
| `app.complete_document_preview_artifact(uuid, uuid, uuid, text, uuid, text, text, text, text, bigint, text, text, text, uuid)` | `(document_file_id uuid, document_status text, replayed boolean)` | `service_role` only; requires the matching worker ID/current lease token and validates the deterministic private artifact contract. |

The original `request_document_preview` and `complete_document_preview`
functions remain internal transaction primitives; direct authenticated/service
execution was revoked by the forward preview-pipeline migration.

Each authenticated command has an idempotency key, a canonical request
fingerprint, a request ID, and a required correlation UUID. Exact replay returns
the existing result. Reusing the key for a different request fails with a
conflict.

## TypeScript contract surface

Each package exports its new contract from `src/index.ts`:

- `@vynlo/inventory`: VIN normalization, phone-usable inventory create DTO,
  integer-money checks, and deterministic stock formatting;
- `@vynlo/crm`: person/organization party command normalization;
- `@vynlo/deals`: linked party/inventory draft DTO without workspace or owner
  authority;
- `@vynlo/documents`: fixed preview watermark, synthetic non-production
  template contract, preview request normalization, and terminal-state guards.

The contracts are framework-neutral. Business invariants remain outside React
components and route handlers.

## RLS, authorization, MFA, and audit

- All 12 new public tables have both RLS and forced RLS.
- Authenticated users have select access only when the matching immutable
  permission key resolves in the row's workspace.
- Authenticated users have no direct insert, update, or delete grants. The four
  user commands are fixed-search-path `SECURITY DEFINER` functions that validate
  membership, permission, workspace ownership, and request invariants.
- Existing `app.has_permission` behavior denies inactive users, inactive
  memberships, suspended boundaries, cross-workspace grants, and MFA-required
  roles without AAL2.
- This slice exposes no sensitive official-generation, refund, credential,
  role-change, or configuration-activation command. Therefore the 15-minute
  step-up guard is not added to ordinary inventory, party, draft, or preview
  creation. Later sensitive commands must call the existing recent-assurance
  guard.
- `stock_number_allocations`, template source, relationship ownership, preview
  input, and document mode/number fields are immutable. Hard delete is blocked
  for every new table.
- Audit payloads preserve workspace, actor, assurance, request/correlation IDs,
  action, entity, safe state data, and idempotency metadata. No secrets or real
  customer data are present in fixtures.

## Migration compatibility and rollback

The migration is additive and forward-only. It depends on the tenancy helpers,
permission catalogue, and audit function introduced by
`20260715120000_tenancy_identity_foundation.sql`. It sorts after the generic
configuration and outbox migrations but does not alter their tables or
functions.

No existing application row is backfilled. A workspace cannot create inventory
until a trusted provisioning path installs one active stock definition/counter;
it cannot request a preview until it has an active synthetic non-production
document type/template. The pgTAP fixtures create those records inside a rolled
back test transaction only.

Production rollback must roll back callers or disable the feature while
preserving created rows. Do not drop allocations, audit history, templates,
documents, deals, or parties after use. Corrections require forward migrations
using expand/migrate/contract. A destructive down migration is acceptable only
for a disposable local database through `supabase db reset`.

## Subsequent API and UI integration

This migration itself added no route or screen. The later application increment
now implements the intended call path:

```text
responsive form -> API/application service -> SQL command/RLS -> audit
                                        -> outbox/job -> worker preview/file
```

`/api/v1/inventory-units`, `/api/v1/parties`, `/api/v1/deals`, and
`/api/v1/documents/preview` share strict application services and command
headers. The operations screen uses English/French translation keys, works from
360 px, exposes save/queue/unavailable states, and reads artifacts through a
short-lived signed URL. Route, application, and mocked browser tests do not
replace live database/worker acceptance; see
[the end-to-end record](MILESTONE_1_END_TO_END.md).

## Operations and telemetry

- Command audit events carry request and correlation identifiers for later log,
  trace, and job linkage.
- Workspace/status/list indexes and immutable history support operational
  review. The allocation counter uses a row lock, so contention is bounded to
  one workspace/definition.
- Preview records remain durably `queued` if no worker is connected; they are
  not silently marked generated.
- This migration performs no provider, file, or network side effect. The later
  worker performs private Storage I/O only after a durable lease-bound claim.
- The lower-level request audit retains `outbox_enqueue_deferred: true` for
  historical compatibility. The public wrapper now enqueues in the same
  transaction and appends `document.preview_job_queued` as authoritative
  completion evidence.

## Verification

The package tests cover normalization, invalid VINs, integer money, deterministic
stock formatting, DTO authority boundaries, preview watermark/number safety,
and terminal preview state. The pgTAP suite contains 72 assertions covering
schema presence, forced RLS, raw-write denial, permissions/MFA, cross-workspace
denial, composite ownership, idempotency, uniqueness, append-only history,
audit, preview safety, and a 100-allocation contention probe.

The pgTAP contention probe exercises the locked allocator 100 times in one
database session. `scripts/check-stock-allocation-concurrency.mjs` is the
separate `T-NUM-001` runtime gate: it opens at least 100 real connections,
commits simultaneous allocations, checks persisted uniqueness/contiguity, and
proves rollback does not burn a number. It must be run against disposable local
and staging databases because the successful allocations are permanent.

## Explicit follow-ups

The preview enqueue, worker, API, and bilingual operations source follow-ups
from this original slice are implemented by later Milestone 1 increments. The
remaining work is:

1. Execute the complete invitation-to-artifact path against live
   Supabase/Auth/Storage and retain exact-head runtime evidence.
2. Add a real persisted draft-before-confirmation flow if product UX needs one;
   verify abandoned drafts consume no number (`T-NUM-002`).
3. Run the committed `pnpm test:stock-concurrency` gate against local and
   staging Postgres and retain its JSON evidence (`T-NUM-001`).
4. Add controlled VIN duplicate/reacquisition review, provider decode snapshot,
   manual override permission/reason/audit, inventory lifecycle commands, and
   optimistic concurrency.
5. Add lead/timeline, deal workflow/line items/totals, official document files,
   broader renderer
   sandbox tests, and official generation only in their approved milestones.
