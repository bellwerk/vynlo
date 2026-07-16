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
| T-CFG-003 | VYN-CFG-001 | Activation requires permission, step-up, exact checksum, approvals, fixtures, and compatible version. |
| T-CFG-004 | VYN-CFG-001 | Activated version is immutable; correction creates a new version. |
| T-CFG-005 | VYN-CFG-001 | Disabled entitlement hides UI and rejects direct API use. |
| T-CFG-006 | VYN-CFG-001 | Feature flag cannot grant entitlement or bypass an activation gate. |

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
| T-INV-004 | VYN-INV-001 | Location transfer, state transition, price update, and archive enforce version/permission/workflow. |

## Media and storage

| Test ID | Requirement | Test |
|---|---|---|
| T-MED-001 | VYN-MEDIA-001 | JPEG, PNG, WebP, and HEIC inputs normalize orientation and produce configured derivatives. |
| T-MED-002 | VYN-MEDIA-001 | Public derivatives strip GPS metadata; regulated originals remain byte-preserved. |
| T-MED-003 | VYN-MEDIA-001 | Extension spoof, malware, pixel/decompression bomb, and size violation fail in quarantine. |
| T-MED-004 | VYN-MEDIA-001 | Replayed completion/reprocess job does not duplicate derivatives or mappings. |
| T-MED-005 | VYN-MEDIA-001 | Cover uniqueness and order persist under concurrent edits. |
| T-STOR-001 | VYN-STOR-001 | Managed storage authorizes short-lived download only for eligible workspace/role/file. |

## CRM, deals, external finance, and one-time money

| Test ID | Requirement | Test |
|---|---|---|
| T-CRM-001 | VYN-CRM-001 | Lead activity/task/appointment timeline is workspace-isolated and permissioned. |
| T-CRM-002 | VYN-CRM-001 | Lead conversion is idempotent and creates/links one deal. |
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
| T-DOC-002 | VYN-DOC-001 | Official generation atomically allocates one permanent number and immutable snapshot. |
| T-DOC-003 | VYN-DOC-001 | Render retry reuses document/number and cannot duplicate official files. |
| T-DOC-004 | VYN-DOC-001 | Changed official data creates superseding document; original files/snapshots remain. |
| T-DOC-005 | VYN-DOC-001 | Signed upload creates a separate immutable file version with authorized current selection. |
| T-DOC-006 | VYN-DOC-001 | Template script, SSRF, filesystem, local-network, and excessive-resource attempts fail closed. |
| T-CALC-001 | VYN-CALC-001 | Typed AST returns deterministic exact-decimal result and versioned snapshot. |
| T-CALC-002 | VYN-CALC-001 | Cycles, excessive nodes/depth/rows/time, division by zero, overflow, and type mismatch fail safely. |
| T-TAX-001 | VYN-TAX-001 | Pack selects by explicit jurisdiction/context/effective date and stores exact version. |
| T-TAX-002 | VYN-TAX-001 | Unsupported/expired/missing pack blocks tax-dependent official operation. |
| T-EXP-001 | VYN-EXP-001 | CSV/XLSX rows, labels, units, currency, sensitivity, and filters match active export definition. |
| T-EXP-002 | VYN-EXP-001 | Sensitive export requires permission/step-up and returns expiring authorized download. |

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

Every automated test implementation includes the stable test ID in its title or metadata. A pull request cannot close a requirement without linking the applicable acceptance and test IDs. Candidate tax/legal/calculation tests prove implementation consistency only; production activation still requires the documented professional/business approvals.
