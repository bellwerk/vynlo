# Vynlo implementation plan

**Status:** Normative delivery sequence  
**Goal:** Build one reusable Vynlo platform and prove it through the Drivven pilot without hardcoding Drivven behavior.

## Delivery strategy

Use vertical slices. Each milestone must include schema, RLS, API, responsive UI, audit, jobs, tests, and operations—not only backend tables or visual screens.

Development occurs in one repository and one release stream. Drivven configuration is installed into a workspace from `tenant-seeds/drivven`; normal tenants are configured through the runtime onboarding system.

## Milestone 0 — repository, tooling, and environments

Deliver:

- pnpm workspace and package boundaries;
- Next.js web app and worker skeleton;
- strict TypeScript, linting, formatting, unit/integration/E2E test runners;
- GitHub Actions for type/lint/test/schema/secret/dependency checks;
- local Supabase and synthetic seed data;
- development, staging, and production environment definitions;
- structured logging, correlation IDs, feature flags, and error monitoring skeleton;
- configuration/schema validation command;
- protected `main` branch and pull-request template.

Exit criteria:

- a clean clone boots locally using documented commands;
- CI validates Markdown links, OpenAPI, JSON/YAML schemas, migrations, and no-secret policy;
- no tenant production credentials exist in the repository.

## Milestone 1 — foundation and first vertical slice

Deliver:

- organizations, workspaces, profiles, memberships, roles, permissions;
- invite-only authentication, MFA enrollment, 14-day session policy, step-up guard;
- RLS helpers and negative isolation tests;
- append-only audit events;
- feature entitlements and workspace configuration versions;
- PWA shell, shadcn/ui design tokens, English/French translation infrastructure;
- transactional outbox/job primitives;
- minimal inventory create/view;
- minimal party/deal draft;
- document preview pipeline using a synthetic non-production template.

Purpose:

Validate the complete web -> API/application -> database/RLS -> worker -> file path before adding breadth.

Exit criteria:

- two synthetic workspaces cannot access each other's data;
- an invited user can create an inventory record and render a watermarked preview on phone and desktop;
- every sensitive command has permission and audit behavior.

## Milestone 2 — inventory, stock, search, and media

Deliver:

- vehicle versus inventory-unit model;
- manual/pasted VIN, decoder adapter, raw response, duplicate review, override reason;
- transactional stock allocation and concurrency tests;
- locations, odometer, notes, prices, workflow instance;
- cost ledger, days-in-stock, and estimated gross;
- search, filters, saved views, mobile cards, desktop table;
- media upload, quarantine, validation, HEIC conversion, orientation, derivatives, cover/order, retention;
- managed-storage provider.

Exit criteria:

- simultaneous creation never duplicates stock;
- provider/processing failures are visible and retryable;
- vehicle photos meet derivative and metadata rules;
- original legal/document files remain preserved.

## Milestone 3 — workflows, CRM, deals, and one-time money

Deliver:

- workflow definitions/versions/states/transitions/instances/events;
- typed custom fields;
- parties, contacts, addresses, identifiers, leads, activities, tasks, appointments;
- lead conversion;
- deals, participants, inventory links, line items, trade-ins;
- third-party finance application tracking;
- one-time deposits, receipts, refunds, and lender proceeds with reversal model;
- starter retail workflow and deal configurations.

Exit criteria:

- a lead can become a cash or third-party-financed deal;
- no recurring loan servicing is introduced into core;
- settled transaction corrections use reversal/refund events;
- all workflow transitions enforce permission, guards, concurrency, and audit.

## Milestone 4 — documents, numbering, calculations, tax, and exports

Deliver:

- document types, field schemas, template source bundles, renderer sandbox;
- preview versus official generation, transactional numbering, immutable snapshots;
- file versions, signed scans, void/supersede lineage;
- safe expression runtime and activation lifecycle;
- tax-pack runtime and `tax-ca-qc` candidate pack validation;
- generic export definitions and CSV/XLSX generation;
- approval records and activation gates.

Exit criteria:

- preview never consumes a number;
- rendering retry cannot allocate a second number;
- arbitrary template/formula code cannot execute;
- activated definitions are immutable;
- tax/formula/legal artifacts remain disabled without approvals.

## Milestone 5 — providers and Drivven pilot

Deliver:

- generic StorageProvider and WebsitePublishingProvider interfaces;
- Google Drive Shared Drive adapter with idempotent create/move/list/reconcile;
- Webflow adapter with staging/production mappings, locale/field handling, assets, publish/unpublish, drift;
- install Drivven seed: roles, locations, stock rules, workflows, fields, formula candidates, export candidate;
- Drivven inventory folder and Webflow behavior;
- Drivven RTB development flow using watermarked/synthetic template until final approval;
- existing Drive/Webflow migration tool and dry run.

Exit criteria:

- platform packages contain no Drivven branch/import;
- provider outage never loses the business transaction;
- Drivven configuration is stored as runtime versions after import;
- the Drivven end-to-end pilot passes staging UAT at phone and desktop widths.

## Milestone 6 — hardening and production activation

Deliver:

- security review, performance/load tests, accessibility review;
- backup/restore and incident exercises;
- production provider connections and least-privilege scopes;
- migration reconciliation and sign-off;
- final branding;
- approved tax pack and Drivven legal/formula/template fixtures;
- launch dashboards, runbooks, support process, rollback and feature flags.

Exit criteria:

- every production activation gate has an approval record;
- no non-production template can generate an official document;
- launch checklist and UAT are signed;
- restore and provider-failure procedures are demonstrated.

## Parallel workstreams

The following may run in parallel after Milestone 1 contracts stabilize:

```text
A. inventory/media/search
B. CRM/deals/finance tracking
C. document/configuration engines
D. provider adapters and migration research
E. security/RLS/testing/operations
F. Drivven field catalogue and external approvals
```

Cross-workstream schema/API changes require review from the owning domain and the architecture owner.

## Explicit deferrals

Do not add to Release 1 without a new approved decision:

- native mobile app;
- offline writes;
- full visual template/formula/workflow builders;
- public self-service signup/billing;
- lender network submission;
- recurring payment servicing as a standard module;
- autonomous marketplace posting/negotiation;
- market appraisal/price-to-market data;
- service-shop/parts/payroll/general ledger.
