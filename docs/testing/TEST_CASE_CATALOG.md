# Release 1 test-case catalogue

This catalogue gives stable test IDs for traceability. Test files may contain several parameterized cases, but CI reports these IDs. Provider staging tests remain skipped only when the relevant staging connection is not part of the tested environment; production activation requires them to pass.

## Identity, tenancy, and permissions

| Test ID | Requirement | Test |
|---|---|---|
| T-AUTH-001 | VYN-AUTH-001 | Invited user activates account; non-invited public registration is rejected. |
| T-AUTH-002 | VYN-AUTH-002 | Administrator without MFA cannot access an MFA-required workspace. |
| T-AUTH-003 | VYN-AUTH-002 | Session expires at configured 14-day maximum. |
| T-AUTH-004 | VYN-AUTH-002 | Sensitive action rejects stale assurance and succeeds after step-up. |
| T-TEN-001 | VYN-TEN-001 | User in workspace A cannot select, insert, update, or link workspace B records. |
| T-TEN-002 | VYN-TEN-001 | API body/header workspace spoof does not change authoritative workspace context. |
| T-TEN-003 | VYN-TEN-001 | Job, file, export, search, cache, and log context retain workspace ownership. |
| T-RBAC-001 | VYN-SEC-001 | Effective permissions derive from active membership/roles, not labels or client claims. |
| T-AUD-001 | VYN-AUD-001 | Privileged mutation and rejection create the specified append-only audit event. |

## Configuration and activation

| Test ID | Requirement | Test |
|---|---|---|
| T-CFG-001 | VYN-CFG-001 | Workspace configuration package validates and imports as draft without automatic activation. |
| T-CFG-002 | VYN-CFG-001 | Invalid dependency/checksum/schema produces deterministic impact errors. |
| T-CFG-003 | VYN-CFG-001 | Activation requires permission, step-up, exact checksum, approvals, fixtures, and compatible version; imported document types/templates use the same exact gates and production-disabled placeholders are rejected. |
| T-CFG-004 | VYN-CFG-001 | Activated version is immutable; correction creates a new version, while retirement and append-only revocation invalidate the exact approval. |
| T-CFG-005 | VYN-CFG-001 | Disabled entitlement hides UI and rejects direct API use. |
| T-CFG-006 | VYN-CFG-001 | Feature flag cannot grant entitlement or bypass an activation gate. |

## Workflows and typed custom fields

| Test ID | Requirement | Test |
|---|---|---|
| T-WF-001 | VYN-WF-001 | Workflow graph/version validation rejects unsafe guards, effects, execution keys, invalid references, and mutation of an activated version. |
| T-WF-002 | VYN-WF-001 | Transition enforces entity permission, source state, required fields, declarative guard, reason, and expected version atomically. |
| T-WF-003 | VYN-WF-001 | Concurrent or replayed transition produces exactly one entity update, workflow event, audit event, and outbox event. |
| T-WF-004 | VYN-WF-001 | Workflow definitions, instances, events, and transition reasons remain isolated by workspace and domain permission. |
| T-FIELD-001 | VYN-FIELD-001 | Every supported custom-field type validates and round-trips through a pinned immutable definition version without binary floating point. |
| T-FIELD-002 | VYN-FIELD-001 | Field visibility/edit permission, sensitivity masking, and same-workspace reference checks are enforced at API and database layers. |
| T-FIELD-003 | VYN-FIELD-001 | Custom fields cannot shadow critical core fields, execute code, or weaken workflow requirements and tenant isolation. |

## Inventory, numbering, and costs

| Test ID | Requirement | Test |
|---|---|---|
| T-INV-001 | VYN-INV-001 | Physical vehicle and holding episode remain separate across reacquisition. |
| T-INV-002 | VYN-INV-002 | VIN normalizes, decodes, stores provider snapshot, and permits audited manual completion on failure. |
| T-INV-003 | VYN-INV-002 | Duplicate/reacquisition candidates require review and do not silently merge. |
| T-NUM-001 | VYN-NUM-001 | 100 concurrent allocations are unique and monotonically follow the active definition. |
| T-NUM-002 | VYN-NUM-001 | Abandoned pre-confirmation draft consumes no stock number. |
| T-NUM-003 | VYN-NUM-001 | Allocated/imported number is never reused after archive, void, or failure. |
| T-COST-001 | VYN-COST-001 | Posted cost cannot be edited; reversal/replacement preserves ledger total and audit. |
| T-COST-002 | VYN-COST-001 | Cost, price, and estimated-gross values preserve exact PostgreSQL bigint minor units and the workspace ISO currency without binary floating point. |
| T-INV-004 | VYN-INV-001 | Location transfer, state transition, price update, and archive enforce version/permission/workflow. |
| T-SEARCH-001 | VYN-SEARCH-001 | Workspace-scoped inventory search, bounded filters, pagination, and saved views round-trip safely across phone cards and desktop tables. |

## Media and storage

| Test ID | Requirement | Test |
|---|---|---|
| T-MED-001 | VYN-MEDIA-001 | JPEG, PNG, WebP, and HEIC inputs normalize orientation and produce configured derivatives. |
| T-MED-002 | VYN-MEDIA-001 | Public derivatives strip GPS metadata; regulated originals remain byte-preserved. |
| T-MED-003 | VYN-MEDIA-001 | Extension spoof, malware, pixel/decompression bomb, and size violation fail in quarantine. |
| T-MED-004 | VYN-MEDIA-001 | Replayed completion/reprocess job does not duplicate derivatives or mappings. |
| T-MED-005 | VYN-MEDIA-001 | Cover uniqueness and order persist under concurrent edits. |
| T-MED-006 | VYN-MEDIA-001 | Vehicle upload status is owner-safe and bounded; only the exact active dead-letter verification job accepts a reasoned actor-scoped retry, while terminal rejection requires a new upload. |
| T-STOR-001 | VYN-STOR-001 | Managed storage authorizes short-lived download only for eligible workspace/role/file. |

`T-MED-001` runs deterministic oriented JPEG, PNG, and WebP golden transforms
in the standard worker suite. Genuine HEIC transformation is a required
deployment gate for a custom libvips/libheif build with an HEVC decoder; the
prebuilt Sharp runtime must report the missing codec and fail before decode.

## CRM, deals, external finance, and one-time money

| Test ID | Requirement | Test |
|---|---|---|
| T-CRM-001 | VYN-CRM-001 | Lead activity/task/appointment timeline is workspace-isolated and permissioned. |
| T-CRM-002 | VYN-CRM-001 | Lead conversion is idempotent and creates/links one deal. |
| T-CRM-003 | VYN-CRM-001 | Phone-usable party profiles, contacts, addresses, relationships, consent preferences, and protected identifiers remain typed, translated, permissioned, and privacy-safe. |
| T-CRM-004 | VYN-CRM-002 | Pipeline metadata and state-filtered cursor pages derive from the authorized active workflow and never expose another workspace, pipeline, or permission domain. |
| T-CRM-005 | VYN-CRM-002 | Pointer, touch, keyboard, and menu stage moves use one transition command; invalid, unauthorized, stale, and concurrent moves restore truthful card state and preserve audit/outbox parity. |
| T-CRM-006 | VYN-CRM-002 | Lost requires the configured reason and Converted completes actor-idempotent lead-to-deal conversion without duplicate deals. |
| T-CRM-007 | VYN-CRM-002 | Workspace/pipeline switches discard stale column loads while locale, safe filters, focus, and permitted preview context remain correct. |
| T-CRM-008 | VYN-CRM-002 | English/French board/list behavior passes 320–1280 px, coarse-pointer, keyboard, reduced-motion, light/dark, offline/error/retry, axe, overflow, target-size, and deterministic visual checks. |
| T-DEAL-001 | VYN-DEAL-001 | Cash deal validates participants, inventory, line items, and workflow guards. |
| T-DEAL-002 | VYN-DEAL-001 | Trade-in distinguishes allowance, lien/payoff, ownership, and resulting inventory creation. |
| T-FIN-001 | VYN-FIN-001 | External lender lifecycle records lender-returned terms without creating a serviced loan schedule. |
| T-PAY-001 | VYN-PAY-001 | Settled transaction cannot be patched or deleted. |
| T-PAY-002 | VYN-PAY-001 | Reverse/refund creates a linked transaction, requires reason/permission, and preserves original. |
| T-PAY-003 | VYN-PAY-001 | Replayed record/settle/refund command is idempotent. |

## Documents, calculations, tax, and exports

| Test ID | Requirement | Test |
|---|---|---|
| T-DOC-001 | VYN-DOC-001 | Preview is watermarked, unnumbered, and freely regenerable. |
| T-DOC-002 | VYN-DOC-001 | Official generation requires exact type, template, numbering, workflow, calculation, and tax readiness, then atomically allocates one permanent number and immutable snapshot; validation exposes stable gate codes. |
| T-DOC-003 | VYN-DOC-001 | Render retry reuses document/number and cannot duplicate official files; reasoned AAL2 void is the terminal alternative and preserves permanent failure evidence. |
| T-DOC-004 | VYN-DOC-001 | Changed official data creates a superseding document while original files/snapshots remain; a voided failed replacement releases its claim so one fresh successor can use the current prior version and a new number. |
| T-DOC-005 | VYN-DOC-001 | Signed upload creates a separate immutable file version with authorized current selection. |
| T-DOC-006 | VYN-DOC-001 | Template script, SSRF, filesystem, local-network, and excessive-resource attempts fail closed. |
| T-CALC-001 | VYN-CALC-001 | Typed AST returns deterministic exact-decimal result and versioned snapshot. |
| T-CALC-002 | VYN-CALC-001 | Cycles, excessive nodes/depth/rows/time, division by zero, overflow, and type mismatch fail safely. |
| T-TAX-001 | VYN-TAX-001 | Pack selects by explicit jurisdiction/context/effective date, stores the exact version, and computes exact-money fee/discount buckets from explicit classifications. |
| T-TAX-002 | VYN-TAX-001 | Unsupported/expired/missing pack blocks tax-dependent official operation. |
| T-EXP-001 | VYN-EXP-001 | CSV/XLSX rows come from one append-only paged source snapshot; approved filter/sort rules, labels, units, currency, and exact bigint-minor text remain deterministic. |
| T-EXP-002 | VYN-EXP-001 | Sensitive export requires permission/step-up, and each expiring download reauthorizes every permission captured in the immutable column plan. |

Milestone 4 PostgreSQL evidence is grouped in `supabase/tests/034` through
`036`: `034` covers `T-CFG-003..004`, imported
document-type/template exact approval and lifecycle gates, placeholder
rejection, `T-NUM-001..003`, exact approval replay evidence, UTC numbering
semantics, trusted runtime receipts, canonical fee/discount tax projection,
and historical/future tax cutover; `035`
covers `T-DOC-001..005`, exact validation/issuance gate parity and revocation
codes, bounded field schemas, deal-bound one-time receipts, official numbering,
supersession concurrency/permission, failure/retry, and file/download lineage;
`036` covers `T-EXP-001..002`, guarded durable export
jobs, crash-window replay, immutable source paging, bigint-safe transport,
filter-schema validation, per-column download reauthorization, and bounded
exact-money reports. Declarative
calculation/tax and renderer sandbox failure matrices remain in their
domain/worker suites under `T-CALC-001..002`, `T-TAX-001..002`, and
`T-DOC-006`.

## Integrations and jobs

| Test ID | Requirement | Test |
|---|---|---|
| T-JOB-001 | VYN-JOB-001 | Business transaction and outbox commit atomically; provider outage cannot erase the business record. |
| T-JOB-002 | VYN-JOB-001 | Worker lease expiry permits safe reclaim without duplicate external side effect. |
| T-JOB-003 | VYN-JOB-001 | Retry classification/backoff/dead-letter and admin review are observable. |
| T-LIST-001 | VYN-LIST-001 | Publish/update/unpublish creates one remote mapping per connection/channel/locale. |
| T-LIST-002 | VYN-LIST-001 | Remote/internal drift is surfaced and resolved through an audited choice. |
| T-API-001 | VYN-API-001 | Every OpenAPI operation enforces authentication/workspace/permission and stable error shape. |
| T-API-002 | VYN-API-001 | Pagination is bounded and stale aggregate update returns conflict without data loss. |

## UX, accessibility, performance, and operations

| Test ID | Requirement | Test |
|---|---|---|
| T-UX-001 | VYN-UX-001 | Core flow passes at 360 px, 768 px, and desktop without horizontal-table dependency. |
| T-UX-002 | VYN-UX-001 | Keyboard, focus, labels, errors, contrast, touch targets, and screen-reader checks meet target. |
| T-I18N-001 | VYN-I18N-001 | English/French UI changes without changing machine keys or corrupting accents/formats. |
| T-PWA-001 | VYN-UX-001 | Manifest/install/update/offline banner work; restricted data is not indiscriminately cached. |
| T-PERF-001 | VYN-OPS-001 | Production-like data meets documented list/mutation/job/render targets or shows durable progress. |
| T-OPS-001 | VYN-OPS-001 | Backup restore, provider outage, job backlog recovery, and rollback/disable runbooks pass. |

## Drivven pilot

| Test ID | Requirement | Test |
|---|---|---|
| T-DRV-001 | DRV-STOCK-001/2 | `P###` and direct `a/b/c` suffixes allocate concurrently; nested suffix is prohibited. |
| T-DRV-002 | DRV-DRV-001 | Shared Drive create/move/reconcile is idempotent and uses Shared Drive-aware requests. |
| T-DRV-003 | DRV-WEB-001 | Webflow staging mapping, locale, assets, price/location rule, publish and unavailable sync pass. |
| T-DRV-004 | DRV-RTB-001 | RTB preview/official/signed/delivery lifecycle enforces all guards and lineage. |
| T-DRV-005 | DRV-RTB-002 | All candidate golden fixtures reproduce every cent/date and invariant. |
| T-DRV-006 | DRV-PAY-001 | RTB official generation remains blocked until full initial payment is settled. |
| T-DRV-007 | DRV-MIG-001 | Migration dry run reconciles source folders/CMS items and creates no duplicate mappings. |
| T-DRV-008 | DRV-SEC-001/2/3/4 | Drivven MFA, permissions, step-up, and isolation rules pass. |

## Traceability rule

Every automated test implementation includes the stable test ID in its title or metadata. `scripts/validate_spec.py` enforces that each suite cites at least one ID from this catalogue. A pull request cannot close a requirement without linking the applicable acceptance and test IDs. Candidate tax/legal/calculation tests prove implementation consistency only; production activation still requires the documented professional/business approvals.
