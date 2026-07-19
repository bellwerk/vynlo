# Milestone 3 end-to-end delivery

**Status:** Complete at the repository boundary; live PostgreSQL/Supabase
acceptance remains a staging gate where the required local infrastructure is
unavailable.

Milestone 3 delivers versioned workflows, typed custom fields, CRM, configurable
deals, external-lender tracking, and an append-only one-time money ledger. It
stops before document/tax/calculation/export work from Milestone 4.

## Delivered surface

- `20260716350000_m3_workflow_hardening.sql` adds immutable workflow versions,
  compatibility-checked activation, pinned instances, guarded transitions,
  append-only events, optimistic concurrency, audit evidence, and inert outbox
  effects.
- `20260716360000_m3_typed_custom_fields.sql` adds versioned bilingual field
  definitions and typed, permissioned values for the supported party,
  inventory, lead, and deal entities.
- `20260716370000_m3_party_crm_foundation.sql` and
  `20260716390000_m3_lead_timeline_tasks_appointments.sql` add parties,
  normalized contacts, relationships, leads, activities, tasks, appointments,
  and configured actor-idempotent lead conversion.
- `20260716380000_m3_deal_foundation.sql` adds versioned deal types,
  checksum-bound bilingual option labels, participants, inventory roles, exact
  line items, and configuration-driven deal workflows. Pinned detail
  projections expose only the allowed localized participant, inventory, and
  one-time-event options.
- `20260716400000_m3_trade_ins_external_finance.sql` adds trade-ins with
  separately confirmed inventory creation plus external-lender applications,
  immutable condition replacement, and reported status history.
- `20260716410000_m3_one_time_payment_ledger.sql` adds exact-minor-unit one-time
  payment events, settlement, reasoned refund/reversal, actor-scoped
  idempotency, recent-AAL2 protection, audit, and outbox evidence.
- The application layer and strict `/api/v1` contract expose the same bounded
  services used by the mobile-first English/French operator pages under
  `/people` and `/deals`.
- `packs/starter-retail-dealer` supplies tenant-neutral workflow semantics,
  roles, permissions, and deal types without embedding tenant contract logic in
  reusable platform code.

## Requirement and acceptance matrix

| Acceptance ID | Requirements | Acceptance condition |
|---|---|---|
| `M3-WF-AC-001` | `VYN-WF-001`, `VYN-CFG-001` | Definitions, immutable versions/checksums, translated states, declarative transitions, pinned instances, and append-only events round-trip without arbitrary execution. |
| `M3-WF-AC-002` | `VYN-WF-001`, `VYN-APP-001` | Activation requires exact checksum, compatibility, permission, recent strong authentication, approval provenance, audit, and optimistic concurrency. |
| `M3-WF-AC-003` | `VYN-WF-001`, `VYN-AUD-001`, `VYN-JOB-001` | Every transition atomically enforces permission, source, required fields, guard, reason, and version, then writes the entity, workflow event, audit event, and inert outbox effect exactly once. |
| `M3-WF-AC-004` | `VYN-WF-001`, `VYN-TEN-001`, `VYN-SEC-001` | Workflow definitions, instances, events, snapshots, and reasons are isolated by workspace and entity-domain permission. |
| `M3-FIELD-AC-001` | `VYN-FIELD-001` | Bilingual definitions are validated, immutable by version, and deeply stable after normalization. |
| `M3-FIELD-AC-002` | `VYN-FIELD-001`, `VYN-SEC-001` | Critical-core-field shadowing, executable configuration, and unsupported field contracts fail closed. |
| `M3-FIELD-AC-003` | `VYN-FIELD-001` | Short/long text, integer, exact decimal, integer-minor-unit money, boolean, date, and datetime values use typed storage without binary floating point. |
| `M3-FIELD-AC-004` | `VYN-FIELD-001` | Select values are accepted only from the pinned active version's declared option set. |
| `M3-FIELD-AC-005` | `VYN-FIELD-001`, `VYN-TEN-001` | Party, inventory, user, and other supported references are typed and constrained to authorized same-workspace targets. |
| `M3-FIELD-AC-006` | `VYN-FIELD-001`, `VYN-SEC-001` | Visibility/edit permissions and sensitivity masking fail closed without disclosing configured values. |
| `M3-FIELD-AC-007` | `VYN-FIELD-001`, `VYN-AUD-001` | Values preserve their definition version/checksum and append-only audit provenance. |
| `M3-FIELD-AC-008` | `VYN-FIELD-001`, `VYN-TEN-001` | Writes enforce workspace, entity type, immutable permission keys, and optimistic expected versions. |
| `M3-FIELD-AC-009` | `VYN-FIELD-001`, `VYN-WF-001` | Draft or retired definitions reject runtime writes; lead/deal projections and workflow checks consume only authorized active configured values. |
| `M3-CRM-AC-001` | `VYN-CRM-001` | Person and organization parties support profiles, normalized contacts, structured addresses, masked identifiers, preferences, and same-workspace relationships without unsafe hard delete. |
| `M3-CRM-AC-002` | `VYN-CRM-001`, `VYN-WF-001` | Leads support assignment, inventory interest, next action, configured workflow transitions, reasoned loss, and optimistic concurrency. |
| `M3-CRM-AC-003` | `VYN-CRM-001` | Append-only activities plus versioned tasks and timezone-explicit appointments produce a permissioned customer timeline. |
| `M3-CRM-AC-004` | `VYN-CRM-001`, `VYN-DEAL-001` | Lead conversion atomically and actor-idempotently creates or links exactly one configured deal while preserving the party and timeline. |
| `M3-DEAL-AC-001` | `VYN-DEAL-001`, `STD-DEAL-001` | Versioned deal types configure allowed participants, inventory roles, fields, workflow version, and cash/external-finance behavior without code branching. |
| `M3-DEAL-AC-002` | `VYN-DEAL-001` | Deal participants, inventory links, and exact line items enforce workspace, role, currency, version, and active-sale conflict invariants. |
| `M3-DEAL-AC-003` | `VYN-DEAL-001`, `VYN-INV-001` | Trade-ins keep allowance, lien/payoff, ownership, entered facts, tax-eligibility inputs, and optional separately confirmed inventory creation distinct. |
| `M3-DEAL-AC-004` | `VYN-DEAL-001`, `VYN-WF-001` | Cash and financed deal transitions enforce configured permissions, guards, reasons, concurrency, audit, and outbox evidence. |
| `M3-FIN-AC-001` | `VYN-FIN-001` | External finance applications preserve lender-reported amounts, exact rate/term, conditions, expiry, acceptance, and funding lifecycle without submission or servicing artifacts. |
| `M3-PAY-AC-001` | `VYN-PAY-001` | One-time deposit, receipt, balance, trade-in-credit, lender-proceeds, and tenant-configured events record and settle idempotently in exact minor units. |
| `M3-PAY-AC-002` | `VYN-PAY-001`, `VYN-AUTH-002` | Settled events are immutable; reasoned reversal/refund creates a linked event, requires its dedicated permission and recent strong authentication, and preserves the original. |
| `M3-PAY-AC-003` | `VYN-PAY-001`, `VYN-AUD-001` | Actor-scoped receipts plus row locks prevent duplicate settlement and concurrent over-refund/reversal while preserving exact audit/outbox parity. |
| `M3-API-AC-001` | `VYN-API-001`, `VYN-TEN-001` | The normative `/api/v1` CRM/deal/finance/payment/workflow/field surface derives workspace context from authentication and returns strict bounded contracts and safe errors. |
| `M3-UX-AC-001` | `VYN-UX-001` | Lead, party, task, appointment, deal, finance, and payment workflows are fully operable at 360 px and equivalent on tablet/desktop without hover-only actions or overflow. |
| `M3-I18N-AC-001` | `VYN-I18N-001` | English and French catalogues, configured-label fallback, dates, exact money, workflow states, validation, and recovery states remain complete and machine-key neutral. |
| `M3-EXIT-AC-001` | all Milestone 3 requirements | A lead becomes a cash deal and a third-party-financed deal; each path records valid participants/inventory/line items and one-time money, and demonstrates reasoned correction without recurring servicing. |

## Milestone 4 boundary

Milestone 3 does not implement official document numbering/generation,
calculation or tax execution/snapshots, export generation, lender-network
submission, credit pulls, repayment schedules, principal/interest allocation,
recurring servicing, late fees, collections, repossession, arbitrary tenant
code, or a visual low-code workflow builder.

## Required verification

- `T-WF-001..004`, `T-FIELD-001..003`, `T-CRM-001..003`,
  `T-DEAL-001..002`, `T-FIN-001`, and `T-PAY-001..003`;
- full table-level forced-RLS negative matrices and composite workspace links;
- stale and concurrent transition/conversion/payment tests;
- domain, application, route-contract, OpenAPI, and starter-pack parity tests;
- 360 px, tablet, and desktop English/French browser flows with keyboard,
  touch-target, overflow, reduced-motion, and accessibility checks;
- formatting, lint, TypeScript, unit, specification, OpenAPI, boundary, secret,
  dependency, SQL parser/static, build, and end-to-end repository gates.

Live PostgreSQL concurrency, Supabase Auth/RLS, and any provider-dependent
acceptance remain staging gates when their required infrastructure is absent.

## Verification record

- `supabase/tests/025_m3_workflow_hardening.test.sql` through
  `supabase/tests/033_m3_end_to_end_exit.test.sql` provide 546 pgTAP assertions
  covering the acceptance matrix, including both cash and external-finance exit
  journeys.
- Every Milestone 3 migration and pgTAP file parses with PostgreSQL `pglast`;
  the repository Supabase static checker validates forced RLS, immutable
  permission keys, test plans, and migration/test traceability.
- All 98 workspace test files and 661 unit/integration tests pass across the
  domain, application, route, localization, exact-money, and UI layers. All 159
  browser tests pass; the 39 Milestone 3 cases exercise the operator journeys
  at phone, tablet, and desktop viewports.
- The strict OpenAPI checker proves exact parity between the 64 implemented
  Milestone 3 route/method pairs and `contracts/openapi.v1.yaml`, then Redocly
  validates the resulting contract.
- Formatting, lint, strict TypeScript, specification, Markdown link, package
  boundary, secret, dependency, production build, and browser gates pass at the
  repository boundary.

The local environment used for this record did not provide Docker or the
Supabase CLI. Consequently, the pgTAP suite is parser/static-verified here and
must also run against the release PostgreSQL/Supabase environment before
promotion. This is an explicit deployment acceptance gate, not a substitute for
the committed RLS, authorization, concurrency, and idempotency coverage.

## Compatibility, rollback, and operations

The migrations are additive and preserve the compatible Milestone 1 and 2
workspace, membership, inventory, audit, outbox, file, and job contracts.
Legacy starter records are backfilled only through deterministic versioned
configuration. Active workflow, deal-type, custom-field, finance-condition,
payment, audit, and outbox history remains immutable.

After Milestone 3 data exists, rollback means disabling the affected
entitlements and `/api/v1` operator routes while retaining records for recovery;
it does not mean deleting or down-migrating financial, workflow, audit, or
idempotency history. A corrective release must use a forward migration and, for
business corrections, a new version or reversal event.

The outbox remains durable and inert until an explicitly configured worker
claims an allowlisted effect. Milestone 3 does not submit to lenders or provide
recurring payment servicing. Operators must monitor failed/dead-letter jobs,
audit/outbox parity, workflow/configuration activation failures, conversion
conflicts, inventory-role conflicts, and payment correction attempts. Live RLS,
concurrency, recovery, and deployment-secret checks remain required in staging.

Milestone 3 is the stopping point for this delivery. No Milestone 4 document,
calculation, tax, numbering, or export implementation is included.
