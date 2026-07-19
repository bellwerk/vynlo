# Milestone 4 — Documents, numbering, calculations, tax, and exports

**Status:** Complete (verified 2026-07-17)

**Scope boundary:** Repository-complete Milestone 4; no provider adapter or
Drivven pilot implementation from Milestone 5.

Milestone 4 turns the preview-only document foundation into tenant-neutral,
versioned engines for documents, permanent numbering, exact calculations,
tax-pack execution, and exports. Tenant legal wording, contract formulas,
accounting layouts, provider mappings, and credentials remain runtime
configuration. The starter legal templates and the `tax-ca-qc` candidate stay
production-disabled until their documented approvals exist.

## Operator UI design brief

- **Visual thesis:** a calm paper-and-ledger operations desk using the existing
  warm paper, dark ink, signal, and rust palette; document pages, timelines, and
  ruled lists carry hierarchy without dashboard-card clutter.
- **Content plan:** document queue and availability first; short validation and
  preview steps second; exact versions, files, jobs, and lineage on detail;
  configuration and exports remain dedicated working surfaces.
- **Interaction thesis:** persistent render/export status, clear focus and
  keyboard disclosure, and restrained state transitions that are removed under
  reduced-motion preferences. Irreversible number allocation is never hidden
  behind autosave or a generic confirmation.

## Requirements and acceptance IDs

### Configuration and approval lifecycle

- `M4-CFG-AC-001` — Draft, validated, test-passed, approved, active, and
  retired states are explicit and checksum-bound.
- `M4-CFG-AC-002` — Activation requires the immutable permission key, recent
  step-up authentication, compatible schema, exact checksum, passed fixtures,
  required unexpired approvals, and a reason.
- `M4-CFG-AC-003` — Active versions cannot be updated or deleted; correction
  creates a new version or activates a previously approved compatible version.
- `M4-CFG-AC-004` — Missing gates return stable machine codes and an explicit
  gate list; runtime never falls back to a draft version.
- `M4-CFG-AC-005` — Approval records are append-only, exact-version records
  with actor, professional provenance, conditions, expiry, and audit evidence.

### Numbering

- `M4-NUM-AC-001` — A version defines scope, pattern, start, increment,
  reset/period/timezone, imports, and reuse policy without executable code;
  Milestone 4 supports UTC and allocates only on `official_document_created`.
- `M4-NUM-AC-002` — Official allocation and authoritative document creation
  commit atomically under workspace-scoped locking and uniqueness constraints.
- `M4-NUM-AC-003` — Idempotent replay returns the same allocation/document;
  renderer retry never allocates again.
- `M4-NUM-AC-004` — Committed, failed-render, voided, superseded, reserved, and
  imported numbers are never returned to a `reuse: never` sequence.
- `M4-NUM-AC-005` — Concurrent allocation produces unique formatted values;
  a transaction that fails before allocation commit consumes no value.

### Documents and files

- `M4-DOC-AC-001` — Field schemas, localized document types, HTML/CSS source,
  assets, fonts, renderer version, and checksums are versioned and immutable.
- `M4-DOC-AC-002` — The bounded Liquid-style renderer permits only declared
  values, conditions, loops, and formatting helpers; script, SQL, shell,
  filesystem, imports, SSRF/local-network access, and excessive resources fail
  closed.
- `M4-DOC-AC-003` — Preview is watermarked, unnumbered, freely regenerable,
  and cannot mutate an official snapshot.
- `M4-DOC-AC-004` — Official generation validates exact active approvals and
  dependencies, consumes deal-checksum-bound runtime evidence once, allocates
  once, pins an immutable snapshot, and queues one durable PDF job in the same
  transaction. Exact command replay resolves before receipt expiry checks.
- `M4-DOC-AC-005` — PDF completion verifies immutable source/input and storage
  receipts, records a checksummed generated-original file, and is idempotent.
- `M4-DOC-AC-006` — Render failure is retryable or reviewable without changing
  the document ID, number, input, or exact versions. An unrecoverable failed
  replacement can instead be voided with reason, permission, recent AAL2, and
  audit evidence; its failure and permanently consumed number remain intact.
- `M4-DOC-AC-007` — Signed scans append immutable file versions; selecting the
  current authorized scan does not delete history.
- `M4-DOC-AC-008` — Mark-signed, void, and supersede require eligible state,
  permission, expected version, reason/step-up where required, audit, and
  permanent lineage.
- `M4-DOC-AC-009` — Changed official data creates a new numbered document with
  independent permission and expected-version checks. The original remains
  usable through replacement failure and is superseded only after verified
  replacement output; original files and snapshots remain unchanged. Voiding a
  failed replacement releases only its active successor claim, allowing one
  fresh successor against the prior document's current aggregate version.
- `M4-DOC-AC-010` — Downloads verify exact provider bytes/checksum and return a
  short-lived opaque authorization without exposing storage coordinates.

### Calculations

- `M4-CALC-AC-001` — A typed JSON AST supports exact constants/fields,
  arithmetic, percentages, min/max/absolute, comparisons, conditions,
  coalesce, row totals, rounding, dates, approved tax outputs, and the optional
  generic amortized-payment primitive.
- `M4-CALC-AC-002` — Decimal/money operations declare currency and rounding;
  binary floating-point is not used for financial results.
- `M4-CALC-AC-003` — Cycles, missing/type-invalid references, division by zero,
  overflow, and depth/node/row/execution limits fail with stable safe codes.
- `M4-CALC-AC-004` — Every official run appends the exact definition, engine,
  input, output, components, rounding, and checksum snapshot.
- `M4-CALC-AC-005` — Activation requires exact passed fixtures and approvals;
  active calculation versions are immutable.

### Tax

- `M4-TAX-AC-001` — Selection uses explicit jurisdiction, context, currency,
  and effective date; free-text address inference is prohibited.
- `M4-TAX-AC-002` — Exact pack/rate/source/rounding/input/output versions are
  snapshotted; approved overrides require a dedicated permission and reason.
  Canonical deal inputs keep positive fees and nonnegative, explicitly
  classified discounts in separate taxable/non-taxable minor-unit buckets;
  the runtime performs no jurisdiction or tenant inference.
- `M4-TAX-AC-003` — Missing, expired, unapproved, unsupported, or ambiguous tax
  configuration blocks a dependent official operation.
- `M4-TAX-AC-004` — Candidate `tax-ca-qc` fixtures deterministically validate
  5% GST/TPS and 9.975% QST/TVQ on the price excluding GST, including explicit
  eligible-trade-in treatment, an explicitly classified taxable discount, and
  per-tax rounding.
- `M4-TAX-AC-005` — Candidate fixture success is implementation evidence only;
  it never creates professional approval or production activation.

### Exports and reports

- `M4-EXP-AC-001` — Versioned definitions declare tenant-neutral source,
  localized columns, safe mappings/calculations, filters/sort, sensitivity,
  permission, CSV/XLSX formatting, and expiry; submitted filters satisfy the
  approved bounded JSON Schema rather than only a property-name allowlist.
- `M4-EXP-AC-002` — CSV and XLSX contain the same authorized rows, labels,
  units, exact money/currency values, filters, and deterministic ordering from
  one append-only first-execution source snapshot. PostgreSQL bigint money is
  transported to the worker as canonical decimal text.
- `M4-EXP-AC-003` — Runs record exact definition version, filters, actor, row
  count, checksum, expiry, source-manifest fingerprint, audit, outbox, and
  durable job state. Exact command replay precedes mutable activation/approval
  lookup while conflicting reuse fails closed.
- `M4-EXP-AC-004` — Sensitive columns/runs require their immutable permission
  key and recent step-up; downloads are short-lived, workspace-bound, and
  reauthorize every permission captured in the generated column plan.
- `M4-EXP-AC-005` — Core inventory aging/gross, leads, and deals reports remain
  phone-usable and do not hardcode tenant bookkeeping columns.

### Integrated exit

- `M4-EXIT-AC-001` — `T-DOC-001..006`, `T-NUM-001..003`,
  `T-CALC-001..002`, `T-TAX-001..002`, `T-EXP-001..002`, applicable
  configuration/auth/job/storage/tenancy/audit IDs, and English/French
  phone/tablet/desktop journeys all pass.
- `M4-EXIT-AC-002` — Formatting, lint, strict TypeScript, unit, PostgreSQL/RLS,
  concurrency, worker/PDF, OpenAPI, specification, Markdown, boundary, secret,
  dependency, accessibility, browser, and production-build gates pass.
- `M4-EXIT-AC-003` — Reusable source contains no Drivven, RTB, provider, or
  tenant-specific numbering/formula/export behavior; Milestone 5 remains
  untouched.

## API surface

The Milestone 4 contract implements the repository endpoint catalogue for:

- document type availability, validation, preview, official generation,
  list/detail, secure file download, signed files, mark-signed, void,
  supersede, and render retry;
- exact imported document-type and template approval through approval records,
  plus explicit activation endpoints for each immutable source version;
- numbering definition list/version creation/activation and approval records;
- tax pack list/preview/activation and calculation
  list/validate/preview/approve/activate;
- export definition list, run/status/download, and inventory aging/gross,
  leads, and deals reports.

Durable document and export execution, private-storage receipts, bounded PDF
rendering, source allowlists, retry ownership, runtime configuration, and
operator response are documented in
[Milestone 4 worker execution](MILESTONE_4_WORKER_EXECUTION.md).

Official commands derive workspace context from authenticated membership,
require idempotency, and use stable errors. Preview endpoints never accept or
return an official number.

## Compatibility and activation boundary

The migrations are forward-only and preserve Milestone 1 preview documents and
artifacts. Existing preview rows remain watermarked and unnumbered. Starter
document templates and `tax-ca-qc` remain preview/test candidates and cannot
produce official customer-facing output without exact external approval
records. Synthetic placeholder document types and templates cannot enter the
production approval or activation lifecycle.

Workspace or pack import is the creation boundary for document types and
template versions. Import persists immutable source checksums together with
validation and fixture evidence as draft/test-passed rows; the append-only
approval-record command and the dedicated activation endpoints then advance
the exact imported version. There is no parallel authenticated create command.
Document validation mirrors official issuance by checking the exact type,
template, numbering, workflow, calculation, and tax gates and returning stable
machine codes. Synthetic preview remains available without treating its
non-production status as an approval failure.

Approval mutation and revocation take an exclusive transaction lock derived
from the workspace, `configuration_artifact`, artifact type, and artifact ID.
Activation and official issuance take the shared side of the same key before
their locked re-read and exact approval checks; issuance acquires dependencies
in fixed order. An approval therefore cannot be revoked between validation and
an activated version or committed official snapshot.

Synthetic tenant-neutral fixtures may prove the generic official path inside
rolled-back tests; they are not seeded as production configuration.

## Exit verification

The completed exit run applied all 41 migrations to a fresh PostgreSQL 17.10
database, seeded it twice, and passed all 36 pgTAP suites serially: 1,976 of
1,976 assertions. The Milestone 4 suites contributed 199 assertions (`034`:
64, `035`: 82, `036`: 53). The portable runtime foundation gate also passed
against that database with 129 forced-RLS tables, 80 permission keys, and two
synthetic workspaces.

Dedicated concurrency evidence produced 100 unique contiguous committed stock
allocations and proved rollback reuse of the uncommitted next value. The
configuration-artifact shared/exclusive advisory-lock proof blocked mutation
while issuance held the shared lock, then succeeded after release. The
Milestone 4 numbering contention proof likewise passed against the fresh
database.

Repository verification passed formatting, lint, strict TypeScript across 23
workspaces, 118 Vitest files with 846 tests, specification validation, 34-pair
Milestone 4 OpenAPI parity, Markdown links, package boundaries, secret scans,
all 78 SQL files through PostgreSQL grammar parsing, worker build, and the
53-page Next.js production build. The browser matrix passed 174 journeys across
phone, tablet, and desktop, including English/French, keyboard, touch, overflow,
and axe accessibility checks. A real Chromium smoke test produced valid PDF
bytes twice with the same canonical SHA-256 digest. The dependency audit found
no known vulnerabilities.

Milestone 4 stops before Shared Drive, Webflow, Drivven seed installation,
Drivven RTB flow, or migration tooling from Milestone 5.
