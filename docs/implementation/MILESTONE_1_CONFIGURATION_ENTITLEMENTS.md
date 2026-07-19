# Milestone 1 configuration and entitlement foundation

**Recorded:** 2026-07-16

**Status:** Foundation source implemented; PostgreSQL runtime acceptance pending

**Scope:** EPIC `VYN-E02` feature entitlements, workspace configuration versions,
approval records, activation history, and shared application policy only

## Scope boundary

This is an additive foundation slice of
[Milestone 1](./IMPLEMENTATION_PLAN.md). It implements the runtime records and
commands required by
[ADR 0006](../architecture/adr/0006-runtime-workspace-configuration.md),
[workspace configuration](../architecture/WORKSPACE_CONFIGURATION.md), and
[approvals and activation](../modules/APPROVALS_AND_ACTIVATION.md). It does not
claim the whole epic or milestone is complete. Import/export package processing,
domain-specific workflow/template/formula/tax/numbering versions, the admin UI,
jobs, and reconciliation remain separate deliveries.

Domain-specific versions must remain in their owning tables and require their
specific activation permission. The generic configuration record in this slice
is deliberately restricted to `workspace.*` keys and requires both
`configuration.manage` and `workspace.manage` for activation. This prevents it
from becoming a bypass for `workflow.activate`, `template.activate`,
`formula.activate`, `tax.activate`, or `numbering.activate`.

## Implemented records and commands

The additive
[configuration migration](../../supabase/migrations/20260716100000_configuration_entitlements.sql)
adds four workspace-scoped tables:

- `workspace_feature_entitlements` stores immutable, versioned capability
  decisions with enabled state, limits, provenance, canonical SHA-256 checksum,
  effective interval, and `draft`/`active`/`superseded`/`retired` history;
- `workspace_configuration_versions` stores immutable `workspace.*` JSON
  payloads, checksums, provenance, compatibility bounds, effective dates,
  predecessor lineage, validation/review evidence, exact approval linkage, and
  the `draft -> validated -> reviewed -> approved -> active -> superseded` or
  `retired` lifecycle;
- `approval_records` stores append-only exact artifact/version/checksum
  decisions, human identity, professional provenance, conditions, references,
  expiry/review dates, revocation lineage, reason, and idempotency key; and
- `workspace_configuration_activations` stores append-only activation and
  rollback records, including the previous version, exact checksum, effective
  time, actor, reason, and idempotency key.

All four tables carry `workspace_id`, enable and force RLS, prohibit hard
deletion, and expose read access only through active membership plus
`configuration.read` or `approvals.read` as appropriate. Browser roles have no
direct insert/update privilege. Actor and lifecycle fields are derived inside
fixed-search-path security-definer commands, so a request cannot spoof creator,
approver, activator, timestamps, version numbers, or state.

Configuration commands require immutable platform permission keys and recent
AAL2 step-up through the existing `app.has_permission` and
`app.has_recent_strong_auth` helpers. Version allocation and activation use
transaction-scoped advisory locks; lifecycle commands lock the exact row and
require an expected status and checksum. A stale predecessor or state returns a
serialization conflict instead of creating forked history. Same-input command
retries return the original record, while reuse of an idempotency key with
changed input fails closed.

Entitlement creation, activation, and retirement are service-controlled because
workspace administrators cannot grant themselves commercial capability.
`app.is_feature_entitled` is the shared, effective-date-aware decision for UI,
API, and jobs; it returns false for a foreign workspace, absent entitlement,
disabled version, non-active version, or an expired interval.

Every successful insert or lifecycle update appends a workspace-scoped event to
the existing immutable `audit_events` table in the same transaction. Audit
attribution accepts a browser actor only when the active database role, signed
JWT role, user, membership, workspace, and assurance are valid. Trusted service
writes ignore stale pooled JWT claims and record a service/system actor.

## Application policy

The framework-neutral
[application policy](../../packages/application/src/configuration-entitlements.ts)
defines the initial tenant-neutral entitlement-key contract, the configuration
and entitlement lifecycle types, the shared entitlement decision, and an
optimistic exact-version transition assertion. Its
[unit suite](../../packages/application/src/configuration-entitlements.test.ts)
covers availability boundaries, malformed dates, cross-workspace input,
duplicate-active history, stale expected state, checksum mismatch, invalid
transition, missing/rejected/expired approval, platform incompatibility,
effective intervals, and input immutability.

The file is intentionally not integrated into route handlers or worker jobs in
this slice. Those adapters must first derive authoritative workspace context and
then call this policy; a request-body workspace remains untrusted.

## Acceptance mapping

| Acceptance ID | Criterion | Evidence | Status |
|---|---|---|---|
| `M1-CFG-AC-001` | Every entitlement/configuration/approval/activation row preserves one workspace boundary, with forced RLS and negative cross-workspace behavior. | Four forced-RLS tables, composite workspace foreign keys, read policies, no browser DML grants, pgTAP isolation cases. | Implemented; runtime pending. |
| `M1-CFG-AC-002` | Entitlements have immutable version/history semantics and one active version per workspace/key; a disabled, missing, expired, or foreign capability cannot be invoked. | Partial unique index, trusted install/activate/retire commands, `app.is_feature_entitled`, TypeScript and pgTAP cases. | Implemented; runtime pending. |
| `M1-CFG-AC-003` | Workspace configuration progresses through validated, reviewed, approved, active, superseded, retired states without in-place payload mutation or skipped gates. | Lifecycle constraints/triggers, canonical checksum, immutable payload trigger, expected-state command, validation/review evidence tests. | Implemented; runtime pending. |
| `M1-CFG-AC-004` | Activation requires exact checksum, compatible platform schema, effective dates, current exact approval, `configuration.manage`, `workspace.manage`, and recent AAL2. | Activation command, approval lookup, permission/step-up helper calls, negative pgTAP cases. | Implemented for `workspace.*`; domain activation commands deferred. |
| `M1-CFG-AC-005` | Concurrent creation/activation cannot fork version history or leave two active versions, and same-input retries are idempotent. | Advisory/row locks, unique indexes, latest-predecessor and expected-state checks, idempotency keys, version/supersession/rollback pgTAP cases. | Implemented; multi-session runtime stress remains. |
| `M1-CFG-AC-006` | Approval, configuration, activation, rollback, and entitlement changes append workspace-scoped audit evidence whose actor/lifecycle fields cannot be forged. | Triggered audit writes, append-only approval/activation tables, browser privilege denial, browser/service attribution cases. | Implemented; runtime pending. |
| `M1-CFG-AC-007` | Database migration and all configuration pgTAP assertions execute against the exact reviewed revision. | Migration and 86-assertion pgTAP suite. | Runtime pending because local Docker/Postgres is unavailable. |

## Test coverage

The
[pgTAP suite](../../supabase/tests/002_configuration_entitlements_rls.test.sql)
declares 86 assertions covering:

- table/function presence and forced RLS;
- missing permission, stale step-up, direct DML/actor spoofing, checksum mismatch,
  and cross-workspace command denial;
- passing validation evidence, mandatory review, exact approvals, incompatible
  platform schema, and effective activation;
- optimistic concurrency conflicts, serialized gap-free version allocation,
  stale predecessor rejection, unique active state, supersession, and rollback;
- draft, approval, activation, retirement, and entitlement retry idempotency;
- service-only entitlement changes and fail-closed shared availability;
- browser versus pooled-service audit attribution and audit isolation; and
- payload, approval, activation, entitlement, and deletion immutability.

The TypeScript suite contains 20 unit/invariant/failure tests. It is
framework-neutral and does not substitute for database execution.

## Migration compatibility and rollback

The migration is additive after the tenancy/identity foundation. It does not
change an existing API, application row, or tenant seed. Consumers must deploy
only after this migration is applied. Once shared, do not edit it in place;
corrections require a later forward migration.

There is intentionally no destructive down migration. Rollback means:

1. feature-disable the affected caller;
2. reactivate an earlier compatible, still-approved exact configuration version
   through the activation command, which appends a `rollback` record;
3. install a new corrective entitlement version rather than changing history;
4. ship a forward schema correction if database behavior is defective; and
5. preserve approval, activation, audit, and superseded version history.

Approval revocation cannot occur while its configuration is active. The active
version must first be superseded or retired, preventing a production version
from silently remaining active without its recorded gate.

## API, UI, accessibility, localization, and jobs

No OpenAPI operation, Server Action, route, web screen, job, file, or provider
call changes in this foundation slice. Mobile/desktop, WCAG, English/French, job
retry, outbox, and telemetry tests are therefore not claimed here.

The integrating vertical slice must:

- use one application service for Server Actions and `/api/v1`;
- derive workspace context from authenticated membership before calling any
  command or entitlement check;
- expose stable localized gate/error codes without disclosing foreign rows;
- use phone-usable approval, validation, activation, rollback, and retry flows;
- queue reconciliation through the transactional outbox after activation; and
- add structured logs/metrics with request and correlation IDs while keeping
  configuration payloads and approval attachments out of logs.

## Verification record

Local source evidence recorded on 2026-07-16:

- `pnpm --filter @vynlo/application typecheck` passed;
- the targeted Vitest run passed 1 file and 20 tests;
- `pglast` parsed the migration and 86-assertion pgTAP suite with PostgreSQL 17
  grammar; and
- the assertion counter matches the declared pgTAP plan.

Docker/Supabase is unavailable in this environment, so this evidence does not
prove PostgreSQL execution, trigger behavior, RLS evaluation, multi-session
locking, or the pgTAP result. Acceptance requires a clean database reset and
`pnpm exec supabase test db` on the exact reviewed commit. A later concurrency
test should also use two independent database sessions to stress simultaneous
draft creation and activation; the current pgTAP suite proves the locking and
optimistic-conflict contracts in a single session.

## Deferred follow-ups

1. Execute the migration and all 86 pgTAP assertions in CI against local
   Supabase, including a clean reset and repeat seed.
2. Add independent-session contention tests for version allocation, approval
   replay, and activation.
3. Build validated configuration package import/export and impact-diff records;
   imports must create drafts and never auto-activate.
4. Add domain-owned version tables and exact activation permissions for
   workflows, fields, templates, documents, formulas, taxes, numbering, exports,
   and provider mappings.
5. Integrate outbox/reconciliation jobs, stable API contracts, accessible
   English/French admin flows, and operational telemetry.
