# Vynlo core MVP scope

## Foundation

- organizations, workspaces, legal entities, brands, locations;
- invite-only users, RBAC, MFA, sessions, and audit;
- feature entitlements and versioned workspace configuration;
- English/French localization architecture;
- mobile-first installable PWA.

## Inventory and merchandising

- physical vehicle and inventory-unit records;
- manual/pasted VIN entry, basic decoding, duplicate review;
- configurable stock-number allocation;
- location, condition, prices, cost ledger, internal/public notes;
- inventory aging and estimated gross;
- media upload, processing, ordering, cover selection, and derivatives;
- generic website/listing provider adapter and sync status;
- managed storage plus optional external storage.

## CRM and deals

- leads and sources, parties, activities, notes, tasks, appointments;
- lead-to-deal conversion;
- cash retail, third-party-financed retail, wholesale, vehicle purchase, and trade-in records;
- one-time deposits, payments, refunds, and lender proceeds.

## External finance tracking

- lender directory;
- application lifecycle, reference, requested/approved amounts, returned rate/term, conditions, expiry, and funding;
- no lender-network submission and no loan servicing.

## Documents and configuration

- generic document types, standard field library, custom fields;
- versioned HTML/CSS/Liquid templates;
- optional tenant calculation definitions;
- tax-pack invocation;
- preview, official numbering, PDF generation, signed-file upload, void/supersede lineage;
- workflow and custom-field engines;
- generic CSV/XLSX exports.

## Reliability and operations

- transactional outbox, worker, retries, dead-letter review;
- observability, backup/restore, staging/production separation;
- RLS and tenant isolation tests.

The Drivven pilot is installed from `tenant-seeds/drivven` into runtime workspace configuration. It uses the same application build and deployment as every other tenant.
