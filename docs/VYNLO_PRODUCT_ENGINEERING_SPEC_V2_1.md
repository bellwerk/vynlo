# Vynlo Product & Engineering Specification v2.1

**Version:** 2.1.0  
**Decision date:** 2026-07-15  
**Status:** Approved for implementation  
**Canonical repository:** `vynlo`  
**First workspace:** Drivven  
**Drivven bootstrap path:** `tenant-seeds/drivven`  
**Supersedes:** Vynlo/DEH MVP documentation pack v1 and the July 14 discovery audit  
**Normative language:** “must” and “shall” are requirements; “may” is optional behavior.

---

## 1. Executive decision

Vynlo shall be built as an independent, configurable, inventory-first dealership SaaS platform. Drivven, operated by Auto BS Inc., is the first tenant and uses private extensions that are not representative of Vynlo's normal customer.

The standard Vynlo customer is a small or medium vehicle dealership that:

- manages one or more locations;
- acquires, prepares, prices, photographs, and lists vehicles;
- primarily completes cash sales;
- sometimes arranges financing through a third-party lender;
- needs leads, customers, appointments, tasks, documents, and reports;
- has little or no internal engineering staff.

Vynlo core shall not contain preset rent-to-buy, lease, rental, in-house finance, recurring repayment, collection, repossession, brokerage, or late-fee logic. It shall provide generic engines through which an authorized tenant can install such behavior privately.

Drivven's RTB contracts, 70/30 split, GoCardless behavior, recurring payment rules, vehicle return/repossessed workflow, stock convention, Drive/Webflow mappings, daily-payment formula, and accounting exports belong exclusively to Drivven workspace configuration.

---

## 2. Specification hierarchy and ownership

Every requirement and artifact must be classified as one of five types.

### 2.1 Vynlo platform core

Reusable capabilities available to any tenant:

- organizations, workspaces, legal entities, brands, and locations;
- authentication, sessions, MFA, memberships, roles, and permissions;
- inventory, VIN decode, costs, pricing, media, and merchandising;
- leads, CRM, tasks, appointments, parties, and deals;
- third-party lender application tracking;
- one-time payment transactions;
- generic documents, workflows, custom fields, calculations, tax packs, and exports;
- provider adapters, background jobs, audit, security, and operations;
- responsive web/PWA interface.

### 2.2 Standard retail dealer starter pack

An editable initial configuration for a conventional dealership:

- typical inventory, lead, and deal workflows;
- common roles;
- cash sale, externally financed sale summary, vehicle purchase, trade-in, and generic invoice schemas;
- inventory summary export.

Starter templates are demonstrations until approved by a tenant. Defaults are data, never platform enums or identity checks.

### 2.3 Tax packs

Separately versioned jurisdiction logic maintained under explicit source and approval records. The first candidate is Québec. A tax pack is not a legal document and not a tenant contract formula.

### 2.4 Workspace configuration

A workspace's legal wording, formulas, custom statuses, numbering, provider mappings, exports, and activation decisions are stored as versioned runtime configuration. A portable package may bootstrap or export that configuration, but a tenant does not require a repository. The first configured workspace is Drivven.

### 2.5 Future optional modules

Capabilities outside the core MVP, including market intelligence, appraisal, sourcing, reconditioning, recurring payment servicing, advanced collections, digital signatures, marketplace automation, accounting integrations, service/parts operations, and native mobile applications.

No platform pull request may introduce behavior whose true owner is a workspace configuration.

---

## 3. Product scope

### 3.1 Vynlo core MVP

#### Foundation

- Multi-tenant organization and workspace model.
- Legal entities, operating brands, locations, currencies, locale, timezone, and units.
- Invite-only authentication.
- Role- and permission-based authorization.
- MFA and step-up authentication.
- Append-only audit trail.
- Versioned feature entitlements, workspace settings, and configuration activation.
- English/French localization architecture.
- Mobile-first installable PWA.

#### Inventory and merchandising

- Physical vehicle identity separate from inventory holding/acquisition episode.
- Manual/pasted VIN and basic decoder integration.
- Duplicate review, controlled correction, and audit.
- Configurable transactional stock-number allocation.
- Location, odometer, condition, public/internal notes, prices, and acquisition dates.
- Cost ledger for acquisition, transport, repairs, registration, detailing, and tenant categories.
- Days-in-stock and estimated gross.
- Vehicle media upload, normalization, derivatives, ordering, and cover selection.
- Managed storage by default; optional storage provider adapters.
- Website/listing channel adapter, publish/update/unpublish, sync state, drift, and retries.

#### CRM and deals

- Person and organization parties.
- Leads, sources, assignments, notes, activities, tasks, and appointments.
- Lead conversion to deal.
- Cash retail, third-party-financed retail, wholesale, vehicle purchase, and trade-in records.
- Multiple deal participants with roles.
- One-time deposits, receipts, refunds, trade-in credits, and lender proceeds.

#### Third-party finance tracking

- Lender directory and applicant/deal association.
- Requested amount, submitted date, status, external reference, returned approval amount, rate, term, conditions, expiration, and funding.
- No electronic lender-network submission in MVP.
- No repayment schedule or loan servicing for the outside lender.

#### Document/configuration systems

- Tenant-defined document types and typed field schemas.
- Standard reusable field library and typed custom fields.
- Immutable HTML/CSS/Liquid-style template versions.
- Optional tenant calculation definitions.
- Approved tax-pack invocation.
- Preview, official numbering, PDF generation, signed-file upload, void, and supersede.
- Configurable workflows with neutral canonical categories.
- Versioned CSV/XLSX exports.

#### Reliability and SaaS operations

- Stable `/api/v1` contract.
- Transactional outbox and durable worker jobs.
- Idempotent provider calls, bounded retries, dead-letter review, and drift reconciliation.
- Local/development/staging/production separation.
- RLS and cross-workspace tests.
- Backup, restore, incident, and observability specifications.

### 3.2 Core non-goals

Not in Vynlo core MVP:

- internal loan servicing;
- RTB, leasing, or short-term-rental business logic;
- late fees, collections, or repossession;
- lender-network submissions;
- proprietary appraisal, competitive-market, sourcing, or price recommendation data;
- full accounting/general ledger;
- service-shop, parts, payroll, or DMS replacement;
- arbitrary-code formulas;
- visual low-code builders;
- offline writes;
- native App Store/Play Store application;
- autonomous marketplace posting or negotiation.

### 3.3 “Similar to vAuto” boundary

The comparison means a central system for inventory operations, merchandising, dealership workflows, and reporting. It does not promise vAuto-equivalent licensed market data, appraisal intelligence, sourcing, or price-to-market functionality in MVP.

---

## 4. Repository and package architecture

### 4.1 One canonical repository

Vynlo uses one private repository named `vynlo`. A dealership tenant is a workspace in Postgres with versioned configuration and secure assets; it is not a Git repository, branch, deployment, or code fork.

`tenant-seeds/drivven` contains non-secret bootstrap, migration, and test artifacts for the first complex workspace. It is not imported by reusable platform packages and is not a required pattern for future tenants.

No production credentials, customer records, signed contracts, unredacted identity documents, service-account files, or production exports belong in Git.

### 4.2 Modular-monolith monorepo

```text
apps/
  web/                 Next.js web application, API, and PWA
  worker/              background jobs, PDF rendering, media processing

packages/
  api-contracts/
  application/
  domain/
  database/
  validation/
  auth/
  inventory/
  media/
  crm/
  deals/
  documents/
  workflows/
  calculations/
  tax/
  exports/
  integrations/
  jobs/
  observability/
  design-tokens/
  ui-web/
  test-support/

packs/
  starter-retail-dealer/
  tax/ca-qc/

tenant-seeds/
  drivven/

schemas/
contracts/
supabase/
docs/
```

Use pnpm workspaces. These packages are ownership boundaries inside one application, not independently deployed microservices. A future `apps/mobile` may consume API/domain/validation/design-token packages but not web UI components.

### 4.3 Runtime configuration

Activated workspace behavior is stored in versioned database records and secure object storage. Portable configuration packages are optional import/export/bootstrap artifacts. Runtime code resolves behavior from the current approved workspace configuration, never a repository path or workspace name.

A normal future tenant is onboarded through the Vynlo administration flow and requires no Git changes. A separate tenant repository or deployment is exceptional and requires an ADR plus a contractual, regulatory, on-premises, customer-owned-code, or materially different access-control reason.

### 4.4 Dependency direction

```text
UI/API adapters
  -> application services
    -> domain and policy packages
      -> persistence/provider ports
        -> infrastructure adapters
```

React components and route handlers must not implement authorization, numbering, tax, workflow, or tenant formula behavior. Platform code must never contain a branch such as `if workspace === "drivven"` or import `tenant-seeds/drivven`.

---

## 5. Reference technology stack

The required starting baseline is defined in `docs/implementation/TOOLCHAIN_BASELINE.md`. The first scaffold pull request pins exact patch versions, the package-manager version, lockfile, CLI versions, Action commit SHAs, and container image digest. The approved baseline is:

- Node.js 24 LTS.
- pnpm 11 workspaces with one committed root lockfile.
- Next.js 16 App Router, exact patch pinned at scaffold time.
- TypeScript strict mode.
- Tailwind CSS and shadcn/ui source components.
- Supabase Postgres, Auth, RLS, and managed storage reference provider.
- Zod/JSON Schema for validation.
- `/api/v1` route handlers and OpenAPI contract.
- Postgres transactional outbox and job queue.
- Container worker with Playwright/Chromium and Sharp/libvips.
- Vercel reference web deployment.
- Google Cloud Run reference worker deployment.
- GitHub Actions CI/CD.
- OpenTelemetry-compatible tracing and error monitoring.
- Exact decimal arithmetic for financial calculations.

Equivalent technology requires an architecture decision record.

---

## 6. Tenancy and data ownership

### 6.1 Boundaries

```text
organization:
commercial account/customer relationship

workspace:
operational data and RLS isolation boundary

legal entity:
company that owns/contracts/sells

brand:
operating/public identity

location:
physical or operational branch
```

A future organization may own multiple workspaces and legal entities.

### 6.2 Isolation key

All workspace-owned rows use `workspace_id`. Never rely on a client-supplied workspace ID without membership validation. Worker jobs, files, cache keys, logs, exports, provider links, search indexes, and analytics must preserve the same boundary.

### 6.3 Workspace configuration behavior

Workflows, fields, documents, templates, numbering, calculations, exports, entitlements, and provider mappings are stored as versioned runtime configuration. Active versions are immutable and record provenance, checksums, approvals, and effective dates.

Optional portable configuration packages import draft versions through a validated schema and impact plan. They are not the runtime source of truth. Credentials are encrypted runtime records and are never included in Git or portable packages.

---

## 7. Domain model

### 7.1 Vehicle and inventory separation

`vehicles` represents physical identity and manufacturer facts.  
`inventory_units` represents one workspace's acquisition/holding episode and owns stock, location, price, costs, state, listing, acquisition, and closure data.

This permits reacquisition, different stock policies, multiple holding episodes, and historical accuracy.

### 7.2 Inventory data

Key concepts:

```text
vehicles
inventory_units
stock_number_definitions
stock_number_allocations
inventory_cost_entries
vehicle_media
media_files
channel_listings
locations
workflow_instances/events
```

VIN duplicate handling warns against accidental duplicates but permits controlled historical cases. Stock number uniqueness applies per workspace/holding unit.

### 7.3 Parties, CRM, and deals

Use generalized people/organization parties and participant roles instead of a single fixed customer column.

```text
parties
party_contacts
party_addresses
party_identifiers
leads
activities
tasks
appointments
deals
deal_participants
deal_inventory_units
trade_ins
finance_applications
payment_transactions
```

Party roles may include buyer, seller, dealer buyer, trade-in owner, lender, vendor, or authorized representative.

### 7.4 Documents, calculations, tax, and exports

```text
document_types
document_template_versions
documents
document_files
numbering_definitions/allocations

calculation_definitions/versions/snapshots
tax_packs/versions/snapshots

export_definitions/versions/runs/files
approval_records
```

No platform table is named for RTB, brokerage, repossession, or Drivven.

### 7.5 Provider and operational records

```text
integration_connections
external_resources
jobs
job_attempts
audit_events
installed_packs
workspace_feature_entitlements
workspace_configuration_versions
workspace_configuration_imports
```

Remote IDs never live directly on the vehicle row.

### 7.6 Universal field rules

- UUID primary keys.
- Money is signed integer minor units plus ISO currency.
- Rates use exact decimal or basis points with documented semantics.
- Timestamps are UTC; display uses workspace/location timezone.
- Legal dates are date-only.
- Mutable aggregates use optimistic concurrency.
- Immutable financial/document/audit history is never silently deleted.
- Odometer stores value plus `km` or `mi`.

---

## 8. Workflow system

Vynlo owns the engine, not tenant labels.

Each workflow version defines:

- entity type;
- initial state;
- tenant labels/translations;
- neutral category (`draft`, `active`, `pending`, `closed`, `archived`);
- behavior flags such as publishable, terminal, inspection required, or blocks new deal;
- permitted transitions;
- permission, guard, reason, and side effects;
- immutable version and event history.

Transition commands validate current state, version, permission, guards, and concurrency in one database transaction. Side effects create outbox jobs after the state transaction commits.

The standard starter pack provides conventional retail states. Drivven workspace configuration provides active RTB, returned, and repossessed states.

---

## 9. Customization model

### 9.1 Release 1 configuration lifecycle

Versioned database records configure workflows, document types, formulas, tax dependencies, numbering, exports, integration mappings, entitlements, and roles. Draft versions are validated, reviewed, approved, and explicitly activated. Optional files under `packs/` or `tenant-seeds/` only seed or export those records.

### 9.2 Release 1 admin UI

Safe runtime settings:

- branding and locations;
- users/roles;
- active approved statuses;
- numbering start values;
- basic field visibility/requiredness;
- integration connection and website field mapping;
- document activation;
- approved export selection.

### 9.3 Later builders

Deferred:

- visual document builder;
- visual formula editor;
- visual workflow editor;
- arbitrary form/report builder.

Customization cannot weaken tenancy, security, audit, immutable history, or required core fields.

---

## 10. Document engine

### 10.1 Ownership

Vynlo owns renderer, schemas, validation, numbering, versioning, files, approvals, and lineage. A tenant owns legal wording, branding, document types, optional formulas, and activation.

### 10.2 Template technology

- Versioned HTML/CSS source bundle.
- Sandboxed Liquid-style values, loops, and conditions.
- Allowlisted formatting helpers.
- No JavaScript, SQL, shell, filesystem access, server imports, or unrestricted network access.
- Playwright/Chromium worker PDF rendering.
- Fonts/assets stored and checksummed with the template version.

### 10.3 Lifecycle

```text
draft data
-> preview PDF: unnumbered, watermarked, non-production
-> official-generation validation
-> transactional permanent number allocation
-> immutable input/version snapshot
-> asynchronous render
-> generated file and checksum
-> optional physical/digital signature workflow
-> signed file versions
-> void/supersede lineage
```

A rendering retry reuses the same document and number. Changed official data creates a new document/number and supersedes the prior record.

### 10.4 Production activation

A customer-facing version requires:

- exact field schema;
- final tenant-approved wording/layout;
- template source and assets;
- required tax/formula versions;
- approval records;
- visual regression;
- permissions and numbering;
- feature activation.

Development templates are watermarked and do not consume production numbering.

### 10.5 Retention

Do not retain an editable generated PDF. Do retain immutable source bundle, assets, schema, renderer version, input snapshot, version/checksum records, generated original, and signed files.

---

## 11. Calculation runtime

Vynlo ships no preset contract business formula.

The safe declarative runtime supports typed:

- constants and field references;
- add/subtract/multiply/divide;
- percentages, min/max/absolute, sum, and rounding;
- comparisons, conditions, and coalesce;
- repeating-row totals;
- date operations;
- approved tax-pack invocation;
- generic amortized-payment and schedule primitives when a tenant definition requires them.

It prohibits arbitrary code. Definitions have depth, node, row, and execution limits; circular or missing references fail safely.

Use exact decimal arithmetic. Definitions progress:

```text
draft -> test passed -> approved -> active -> retired
```

Active versions are immutable. Every run stores exact definition/engine versions, input, output, component rows, rounding, and checksum. Tenant formula activation requires exact approved fixtures.

---

## 12. Tax engine and packs

Tax logic is separate from templates and tenant formulas.

A tax-pack version defines:

- jurisdiction and transaction context;
- effective dates and currencies;
- rates and source metadata;
- taxable-base and classification rules;
- trade-in/exemption inputs;
- rounding;
- outputs;
- exact golden tests and approval records.

The runtime must not infer jurisdiction from an address string. A tax-dependent official document is blocked when the appropriate pack is missing, expired, unapproved, or cannot handle the transaction.

The candidate `tax-ca-qc` pack models 5% GST/TPS and 9.975% QST/TVQ, with QST calculated on price excluding GST, and includes a conditional eligible dealer trade-in rule. It remains activation-gated by professional review and signed fixtures.

Tenant formulas may consume tax outputs but may not redefine active tax rules.

---

## 13. Inventory and stock workflows

### 13.1 Create inventory

1. Staff enters/pastes VIN or begins from manual vehicle facts.
2. Decoder returns suggestions and raw provider result.
3. Vynlo displays conflicts/duplicate review.
4. Staff completes required acquisition/location/price data.
5. On confirmed creation, allocate stock transactionally and create inventory unit.
6. Queue storage-folder/media/listing jobs.
7. A provider failure does not recycle the number or roll back the business record.

Camera VIN scanning is excluded. Future document extraction may suggest VIN/cost from uploaded documents.

### 13.2 Costs and gross

Costs are immutable/reversible ledger entries with category, vendor, amount/currency, date, tax context, notes, and file. Totals and estimated gross are derived; no fixed repair/transport columns constrain future categories.

### 13.3 Reacquisition

A returned or reacquired physical vehicle may create a new inventory unit according to workspace policy. The Drivven private workflow may reuse the original holding/stock under its specific RTB rule.

---

## 14. Media pipeline

### 14.1 Vehicle photos

Accepted: JPEG, PNG, WebP, HEIC/HEIF where worker support is available.

Processing:

1. quarantine;
2. actual signature/MIME, size, pixel, and safety validation;
3. malware scan where applicable;
4. orientation correction and HEIC conversion;
5. GPS stripping from public derivatives;
6. normalized master and derivative generation;
7. checksums/deduplication;
8. order/cover persistence;
9. asynchronous provider publication.

Default profile:

```text
normalized master: maximum long edge 2560 px
website derivative: maximum width 1080 px WebP
thumbnails: 640 px and 320 px WebP
```

Raw marketing-photo original defaults to deletion seven days after verified normalization, configurable per workspace.

### 14.2 Documents

Registration, purchase, identity, and signed/legal documents preserve the original. Previews are separately derived. The only legal copy is never destructively resized or recompressed.

---

## 15. CRM, deals, and external finance

### 15.1 Lead flow

```text
capture/import
-> assign
-> contact/activity/task
-> appointment/qualification
-> convert or close lost
```

Every timeline item has actor, timestamp, channel/type, subject/body, and entity links.

### 15.2 Deal flow

The starter pack supports cash retail, third-party-financed retail, wholesale, purchase, and trade-in. Deal types are configuration, not enums.

Deals link participants and inventory units by roles, record currency/line items and snapshots, and execute workspace workflows.

### 15.3 External lender

Vynlo records the application and lender-returned terms. It does not calculate, submit, collect, or service the lender's loan in MVP.

### 15.4 One-time payments

Core types include deposit, sale receipt, refund, lender proceeds, and other one-time event. Records store amount/currency, method, reference, status, proof, actor, and approval. Settled events are reversed through new events, never edited away.

Recurring installment servicing is optional and not a standard platform workflow.

---

## 16. Listing and provider integrations

### 16.1 Provider contracts

Platform defines generic storage, website/listing, VIN, email, finance, accounting, and marketplace ports. Provider adapters return normalized IDs, state, errors, rate-limit hints, and versions.

### 16.2 Transactional outbox

No external provider call occurs inside the authoritative business transaction.

```text
commit domain change + outbox
-> worker claims job
-> provider call with idempotency
-> result/mapping recorded
-> transient retry with jitter
-> permanent failure/dead letter/admin review
```

UI statuses:

```text
not configured
pending
processing
synced
retrying
action required
disabled
```

### 16.3 Drift

External manual changes are detected where providers permit. Workspace policy decides whether Vynlo overwrites, adopts, or requests manual resolution. No silent destructive reconciliation.

---

## 17. API contract

- Base path `/api/v1`.
- OpenAPI is normative for external/mobile clients.
- Authenticated requests derive user/workspace context from membership.
- Mutating endpoints support idempotency keys where duplicate submission is possible.
- Errors use structured code, user-safe message, field details, correlation ID, and retryability.
- Cursor pagination, filtering, sorting, and locale/timezone are explicit.
- Optimistic-concurrency version required for mutable aggregate updates.
- Server Actions may improve the web UX but must call the same application services.

A future native client can be introduced without bypassing application rules.

---

## 18. Mobile/PWA and UI

### 18.1 Technology

- Next.js App Router and strict TypeScript.
- Tailwind CSS.
- shadcn/ui source components in `packages/ui-web`.
- shared design tokens;
- installable PWA manifest and standalone display;
- localization keys for English/French.

### 18.2 Responsive rules

- Design at 360 px first.
- No hover-only control.
- Target 44×44 CSS-pixel touch areas.
- Sticky actions must not obscure content.
- Inventory uses cards/lists on mobile and data table on desktop.
- Contract/deal forms use steps and autosaved server drafts.
- Correct mobile input modes for money, number, phone, email, and date.
- Visible upload/job/sync progress and retry.
- No offline writes; show connectivity and server save confirmation.

### 18.3 Accessibility

WCAG 2.2 AA target, semantic landmarks/headings, keyboard operation, focus management, labels/errors/instructions, non-colour status, contrast, reduced motion, and assistive-tech testing.

A future native app shares API/domain/validation/tax/calculation/design tokens, not shadcn web components.

---

## 19. Authentication, sessions, and authorization

### 19.1 Login

Invite-only Google OAuth and email/password fallback through Supabase Auth. Public signup and shared accounts are prohibited.

### 19.2 Session

- Maximum normal session: 14 days.
- Short-lived access token with refresh.
- Password change, deactivation, admin revocation, or security event ends sessions.
- No global short idle timeout in MVP.
- Future optional local screen lock for shared terminals.

### 19.3 MFA and step-up

MFA mandatory for workspace administrators; workspace may require all users. Drivven requires all.

Step-up authentication is required when strong auth is older than 15 minutes for role/credential changes, tax/formula/template activation, signed-document void, refunds/reversals, sensitive exports, and privileged support access.

### 19.4 Permissions

Application checks permission keys, not role names. RLS enforces workspace isolation; application services enforce field/action policy. Restricted identifiers and documents require dedicated permission.

---

## 20. Security, privacy, audit, and retention

### 20.1 Classification

```text
public: published listing data
internal: inventory costs and internal notes
confidential: customer/deal/lender data
restricted: government identifiers, auth factors, credentials, signed legal files
```

### 20.2 Controls

- RLS and negative isolation tests on every exposed table.
- Encrypted credentials with key rotation.
- TLS and provider storage encryption.
- Short-lived secure file access.
- Upload quarantine, type/pixel/size validation, and safe previews.
- Rate limits for auth, search, upload, export, and expensive jobs.
- PII scrubbing in logs, errors, traces, analytics, and fixtures.
- No production data/credentials in local or development.
- Least-privilege provider scopes.
- Sensitive-field masking.

### 20.3 Audit

Append-only event includes workspace, actor/type, action, entity, before/after or structured diff, reason, correlation/request ID, IP, user agent, timestamp, and auth assurance.

No normal application role can edit/delete audit history.

### 20.4 Retention

MVP does not automatically delete signed documents, financial snapshots, or audit records until approved jurisdiction/tenant policies exist. Temporary previews and exports expire. Raw vehicle-photo retention follows media profile.

Before public SaaS launch, implement tenant export, legal hold, configurable retention, controlled deletion/anonymization, privacy requests, support access, and breach response.

---

## 21. Environments, deployment, and operations

```text
local: synthetic fixtures/mocks
development: engineering, no production data/credentials
staging: production-like, separate providers and test data
production: protected approvals, secrets, backups
```

Migrations use expand/migrate/contract. Destructive compatibility changes are not in-place.

Operations require:

- structured logs, metrics, traces, correlation IDs;
- provider/job dashboards and alerts;
- database and configuration backups;
- restore tests;
- incident severity and ownership;
- runbooks for provider outage, failed document, media queue, migration, and credential rotation;
- rollback/feature-flag strategy.

Reference recovery targets are one-hour-or-better database recovery point and four-hour-or-better service recovery time, subject to provider plan validation.

---

## 22. Testing and quality gates

### 22.1 Platform suite

- unit/domain;
- invariants and property tests;
- database/constraints/concurrency;
- RLS and cross-workspace denial;
- API/OpenAPI contracts;
- integration mocks/staging smoke;
- media golden files and adversarial inputs;
- document sandbox/visual snapshots;
- workflow/configuration/package schemas;
- mobile and desktop E2E;
- security abuse cases;
- performance/load for key paths;
- backup/restore and migration dry runs.

Platform tests must contain no Drivven business terms or fixtures.

### 22.2 Pack suites

Starter packs, tax packs, and workspace configuration seeds have separate schema, fixture, workflow, mapping, document, and acceptance tests.

Tax and financial calculation activation requires exact approved golden cases.

### 22.3 Core E2E

An ordinary configured workspace must be able to:

1. invite users;
2. create inventory from manual VIN;
3. decode and confirm data;
4. allocate stock;
5. add costs and images;
6. publish a listing;
7. capture and convert a lead;
8. create cash or external-finance deal;
9. record one-time payments;
10. preview/generate approved document;
11. upload signed file;
12. close inventory;
13. export/report;
14. preserve full audit.

Run at 360 px, tablet, and desktop.

### 22.4 Definition of done

A feature is done only when:

- requirement and acceptance IDs exist;
- platform/pack ownership is correct;
- API/data/permission/state behavior is documented;
- migrations, RLS, audit, jobs, errors, localization, accessibility, and responsive UI are handled;
- automated tests and operational telemetry exist;
- no activation gate is bypassed;
- documentation and traceability are updated.

---

## 23. Drivven first-tenant specification

### 23.1 Identity and locations

```text
Platform: Vynlo
Workspace/operating brand: Drivven
Legal entity: Auto BS Inc. (exact corporate identifiers activation-gated)

Montreal:
9110 Bd Saint-Michel
Montréal, QC H3X 2T8
+1 438 449-6777

Sherbrooke:
2258 Rue King Ouest
Sherbrooke, QC J1J 2E8
+1 819 300-0777
```

Three users: admin, sales, and sales/office. Both sales roles access both locations. All use MFA.

### 23.2 Stock

- Global `P` numeric sequence, not location-specific.
- Allocate on confirmed vehicle creation.
- Never reuse.
- Direct trade-ins from a source deal receive `a`, `b`, `c` suffixes.
- No nested suffixes; later trade-in against a suffixed unit receives next regular number.
- Imports may preserve existing admin-approved number and advance the sequence.

### 23.3 Google Drive

Drivven uses a company Shared Drive. OAuth uses a dedicated company-controlled account. IDs are encrypted runtime configuration.

Folder:

```text
P166 - 2018 TOYOTA COROLLA/
  01 PHOTOS/
  02 PURCHASE DOCUMENTS/
  03 CONTRACTS/
  04 REPAIRS AND INVOICES/
  05 REGISTRATION AND OTHER/
```

Delivered path:

```text
SOLD INVENTORY/
  2026/
    Q3/
      08 - AUGUST/
        P166 - 2018 TOYOTA COROLLA/
```

Archived and returned/repossessed paths are separate. Direct Drive edits are allowed but reconciled and flagged on conflict.

### 23.4 Webflow

Drivven's website provider is Webflow CMS `Inventory`.

Mapped data includes title, Available, Publishing Page, kilometres, transmission, engine litres/cylinders/horsepower, fuel, drivetrain, location, cash price, marketing payment, cover, and photos.

Rules:

- price below 2,000 CAD -> Under $2,000 publishing page;
- otherwise current location page;
- location remains explicit;
- delivered sets Available=false and does not delete the CMS item;
- Drive/normalized media remains master; Webflow receives 1080px WebP copies;
- sync is queued immediately and normally expected within 60 seconds;
- staging and production mappings are separate;
- exact IDs/options/locales are activation inputs.

The daily marketing formula is private:

```text
((cash price × 1.15) ÷ 1.30 × 1.15 ÷ 24 ÷ 30)
```

For 10,000 CAD, the approved example displays 14.13 CAD/day. It is not a contractual payment.

### 23.5 Drivven RTB

RTB is a private tenant document/formula/workflow.

- Global `RTB-000001` format, start chosen at activation.
- Never resets/reuses.
- Preview unnumbered/watermarked.
- Official number on PDF generation.
- Filename `P123_RTB-000257.pdf`.
- First signed scan `P123_RTB-000257_SIGNED.pdf`.
- Later scan `_SIGNED_02`, etc.
- Physical signatures in pilot.
- Contract marked signed manually and signed scan required before delivery.
- Only one active RTB per inventory unit.

Initial payment:

```text
brokerage base = round half-up(initial payment × 70%)
capital down payment = exact remainder
```

Brokerage base is paid upfront; applicable brokerage tax is financed under the private candidate formula. Capital down payment and eligible trade-in credit reduce the private formula's vehicle base before tax; lien/payoff is added as financed amount. This exact treatment is activation-gated by accountant/legal approval.

Payment:

- annual nominal rate in basis points;
- weekly 52/year or biweekly 26/year;
- 12/18/24/30/36/48 months;
- first due exactly 7/14 days after signature;
- amortized regular payment;
- final cent adjustment;
- original schedule immutable;
- no full schedule printed in RTB PDF.

No late fee, provider event, partial payment, or collection event modifies the signed schedule.

### 23.6 Other Drivven documents

Scaffolds exist for private cash sale, dealer cash sale, vehicle purchase, service invoice, and short-term rental. Each remains feature-disabled and watermarked until its exact legal template/field mapping is approved.

### 23.7 Future private servicing

GoCardless, e-transfer Gmail matching, late-fee rules, morning reports, and collection workflow remain private/deferred.

Candidate future rule: one 50 CAD fee per failed scheduled installment, not per retry, no grace, flat/non-interest-bearing, due at final settlement, admin waiver with audit. Production requires legal/accounting approval.

### 23.8 Drivven pilot activation

Development may proceed against synthetic candidate fixtures. Production RTB activation requires final template, legal wording, exact seller identifiers, tax/accounting approval, approved golden cases, numbering start, PDF visual set, integration staging, migration dry run, backup/incident tests, and UAT.

---

## 24. Implementation sequence

### Milestone 0 — repository, tooling, and environments

- Create the single private `vynlo` repository and commit this specification.
- Scaffold pnpm workspace, web/PWA, worker, shared packages, and local Supabase.
- Add lint/type/test/schema/link/secret/dependency CI gates.
- Establish local, development, staging, and production environments and secret management.

### Milestone 1 — foundation and first vertical slice

- tenancy, auth, sessions, MFA, memberships, permissions, RLS, and audit;
- feature entitlements and runtime workspace configuration versions;
- base API, errors, idempotency, optimistic concurrency, outbox, worker, and observability;
- PWA shell, localization, shadcn tokens/layout;
- minimal inventory, party/deal draft, and watermarked document preview.

This milestone proves the full browser-to-database-to-worker path before breadth is added.

### Milestone 2 — inventory, media, search, and stock

- vehicles/inventory units, stock engine, VIN adapter, duplicate review;
- cost ledger, aging, and estimated gross;
- media pipeline and managed storage;
- mobile cards, desktop table, filters, saved views;
- starter inventory workflow.

### Milestone 3 — CRM, deals, finance tracking, and one-time money

- parties, leads, activities, tasks, appointments;
- deal participants, trade-ins, line items;
- third-party finance application tracking;
- one-time transactions and reversals;
- workflow/custom-field support.

### Milestone 4 — documents, numbering, calculations, tax, and exports

- document sandbox/render/files/lineage;
- transactional numbering;
- safe expression runtime and calculation snapshots;
- tax-pack runtime and approvals;
- versioned exports and activation records.

### Milestone 5 — Drivven provider configuration and pilot

- import `tenant-seeds/drivven` into a staging workspace;
- roles, locations, stock rule, workflows, and feature gates;
- Google Shared Drive and Webflow adapters/mappings;
- inventory migration dry run;
- Drivven RTB development flow with watermarked template and synthetic fixtures.

### Milestone 6 — hardening and production activation

- security, performance, accessibility, backup/restore, incident, and provider-failure exercises;
- final branding, external IDs, credentials, migration reconciliation, and UAT;
- approved tax/legal/accounting/template/calculation activation records;
- monitored launch with rollback and feature flags.

The detailed epic catalogue and exit criteria are in `docs/implementation/`.

---

## 25. Readiness and remaining inputs

This v2.1 specification makes final architecture and product decisions. Development may start.

The following are production activation inputs rather than unanswered product architecture:

- exact Auto BS Inc. registration/tax/permit identifiers;
- production Shared Drive, Webflow field/option/locale IDs and secrets;
- existing inventory/CMS item counts and mappings;
- final French RTB wording/layout and brokerage annex;
- accountant/legal approvals;
- signed Drivven and Québec golden fixtures;
- RTB and other document sequence start values;
- final branding assets;
- legally approved retention schedule.

A feature whose activation input is missing remains disabled. Missing external approval must not cause engineering to invent business/legal content or block unrelated platform work.

---

## 26. Canonical artifacts

The complete normative set is contained in one repository:

```text
vynlo/
  docs/
  schemas/
  contracts/
  packs/starter-retail-dealer/
  packs/tax/ca-qc/
  tenant-seeds/drivven/
```

`tenant-seeds/drivven` is a bootstrap/migration/test package, not a second application or runtime source of truth. After import, Drivven behavior is resolved from versioned workspace configuration records.

Machine-readable schemas, OpenAPI, starter/tax packs, Drivven seed fixtures, validation results, and checksums are part of this specification. The previous v2 two-repository recommendation and the earlier `vynlo_mvp_saas_docs` discovery pack are superseded and must not be used as implementation authority.
