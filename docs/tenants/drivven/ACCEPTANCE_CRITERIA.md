# Drivven pilot acceptance criteria

## Inventory

- **DRV-INV-001:** Confirming vehicle creation allocates exactly one permanent stock number and queues exactly one folder-creation job.
- **DRV-INV-002:** Two simultaneous creations cannot receive the same number.
- **DRV-INV-003:** VIN decode failure does not prevent manual completion; duplicate VIN/holding warnings require review.
- **DRV-INV-004:** Changing location updates Drivven data immediately and queues the correct Webflow update.
- **DRV-INV-005:** Sales users can archive but cannot delete inventory records.

## Drive and media

- **DRV-DRV-001:** Folder creation/move is idempotent and Shared Drive-aware.
- **DRV-DRV-002:** A provider outage does not roll back the Vynlo inventory record; the job retries and exposes status.
- **DRV-MED-001:** JPEG/PNG/WebP/HEIC vehicle photos generate normalized master, 1080px WebP, 640px, and 320px derivatives.
- **DRV-MED-002:** The first photo is cover by default; order/cover changes synchronize without duplicate assets.
- **DRV-MED-003:** Original signed and regulated documents are preserved unchanged.

## Webflow

- **DRV-WEB-001:** Staging and production connections are separated.
- **DRV-WEB-002:** Price below 2,000 CAD maps Publishing Page to Under $2,000; otherwise it maps to current location while Location always remains explicit.
- **DRV-WEB-003:** Delivered/unavailable queues unpublish or Available=false according to configured mapping.
- **DRV-WEB-004:** Drift and permanent sync failures are visible and auditable.

## RTB

- **DRV-RTB-001:** A preview consumes no RTB number and is visibly non-production.
- **DRV-RTB-002:** Official generation is blocked until full initial payment is settled and required fields/approvals are present.
- **DRV-RTB-003:** An official generation consumes one permanent sequence number exactly once, even when rendering retries.
- **DRV-RTB-004:** Formula run stores exact inputs, outputs, component rows, tax/formula/template/renderer versions, and checksums.
- **DRV-RTB-005:** Brokerage plus capital down payment equals the initial payment to the cent.
- **DRV-RTB-006:** Weekly/biweekly original schedule reaches zero principal under approved golden cases.
- **DRV-RTB-007:** Changed official data creates a new document and supersedes, never overwrites, the old one.
- **DRV-RTB-008:** Only one active RTB deal may exist for one inventory unit.
- **DRV-RTB-009:** Marking signed activates the original schedule; signed scan is a separate immutable file.
- **DRV-RTB-010:** Delivered marks Webflow unavailable and queues the Sold folder move.

## Security

- **DRV-SEC-001:** All three users authenticate with MFA.
- **DRV-SEC-002:** Sales cannot change activated formula/tax/template versions, reverse/refund payment transactions, waive fees, or void signed documents.
- **DRV-SEC-003:** Sensitive admin actions require step-up authentication and an audit reason.
- **DRV-SEC-004:** No Drivven data is readable from another workspace in RLS, API, job, export, file, cache, or log tests.
