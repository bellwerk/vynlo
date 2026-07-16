# Vynlo v1 discovery pack to v2 specification

## Product correction

- Replaced a Drivven/RTB-centered product with an independent inventory-first dealer SaaS.
- Defined the normal customer as a cash-sale dealership with occasional external financing.
- Narrowed the vAuto comparison to inventory operations/merchandising/workflow, excluding market intelligence in MVP.

## Ownership correction

- Split Vynlo platform and Drivven tenant into two private repositories.
- Removed RTB, 70/30, recurring payment, collections, Drivven statuses, stock, Drive, Webflow, and accounting rules from platform ownership.
- Added starter-pack, tax-pack, tenant-pack, and future-module classifications.

## Architecture correction

- Added pnpm monorepo, web/PWA, worker, stable API, outbox/jobs, provider adapters, and staging/production boundaries.
- Added workspace RLS boundary and organization/legal-entity/brand/location separation.
- Added pack schemas, activation gates, checksums, and approval lifecycle.

## Data correction

- Separated physical vehicle from inventory holding episode.
- Replaced fixed costs with cost ledger.
- Added generalized parties/participants, leads/CRM, trade-ins, external finance, one-time transactions, media, listings, jobs, approvals, and exports.
- Replaced provider IDs on vehicle with external mappings.
- Replaced CAD cents/km assumptions with currency minor units and odometer unit.

## UI/operations correction

- Added mobile-first PWA, shadcn/ui, bilingual architecture, accessibility, form/error behavior, and no offline writes.
- Removed camera VIN scanning.
- Added image resizing/HEIC/derivatives from day one.
- Added 14-day session, MFA, step-up authentication.
- Added NFRs, security, RLS matrix, testing, backup, incident, and runbooks.

## Drivven correction

- Preserved all confirmed Drivven requirements in a private pack.
- Resolved stock allocation and suffix policy.
- Specified Drive/Webflow mappings and migration.
- Specified candidate RTB formula, exact candidate fixtures, immutable schedule, signing-date rule, numbering, and activation gates.
- Disabled non-approved document templates and future servicing modules.
