# Test strategy

## Layers

### Unit/domain
Numbering, decimal helpers, workflows, custom fields, document lineage, listing mapping, retention, permissions.

### Invariants
Numbers never reused; official snapshots immutable; cross-workspace access denied; settled transaction not mutated; cost total equals ledger; formula deterministic; tax snapshot references approved version.

### Database/RLS
Migrations, constraints, concurrent allocation, RLS per table, audit immutability, job locking, starter/tax pack installation, workspace-configuration import/activation.

`pnpm test:stock-concurrency` is the `T-NUM-001` runtime gate. Against a
disposable, migrated, synthetically seeded database it opens at least 100 real
connections, commits simultaneous allocations, verifies unique contiguous
persisted numbers, and proves a rolled-back transaction burns no number. It
requires `SUPABASE_TEST_DATABASE_URL`; the workspace, actor, definition,
currency, and connection count can be overridden with the documented
`VYNLO_TEST_*` variables in the script. This destructive-to-test-data gate is
never pointed at production.

### API
OpenAPI request/response/error/idempotency and compatibility.

### Integrations
Mock suites and staging smoke tests for storage, website, VIN, email/future providers; rate limits, expiry, timeout, duplicate callback, drift.

### Media
Orientation, HEIC, pixel bombs, duplicates, metadata stripping, dimensions/quality, retry, retention.

### Documents
Validation, preview watermark, numbering, sandbox, page breaks, localization, fonts, checksums, visual snapshots, signed versions, void/supersede.

### E2E
Core path at 360 px, 768 px, and desktop; provider outage and permission denial.

### Security
Isolation, IDOR, escalation, uploads, template injection, expression abuse, credential leak, rate limiting, step-up.

Platform tests contain no Drivven-specific terms or fixtures. Starter packs, tax packs, and workspace configuration seeds have separate suites.

## Stable test IDs

The required Release 1 test IDs and requirement mappings are in [`TEST_CASE_CATALOG.md`](TEST_CASE_CATALOG.md). CI reports these IDs so traceability survives test-file reorganization. `scripts/validate_spec.py` rejects an automated test suite that omits stable test-ID metadata or cites an ID absent from the catalogue.
