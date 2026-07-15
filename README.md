# Vynlo — Product & Engineering Specification v2.1

**Specification version:** 2.1.0  
**Decision date:** 2026-07-15  
**Status:** Approved for development  
**Canonical repository:** `vynlo`  
**First workspace:** Drivven, operated by Auto BS Inc.

Vynlo is a configurable, inventory-first dealership operations and merchandising SaaS for small and medium vehicle dealerships. Drivven is the first configured workspace and has private operating rules, document templates, formulas, workflows, integrations, and exports. Those settings must never become hardcoded Vynlo behavior.

## Repository rule

Vynlo uses **one application repository**. A dealership tenant is a workspace in the database, not a Git repository or a code fork.

```text
vynlo/
├── apps/                     # web/PWA and background worker
├── packages/                 # reusable platform domains and infrastructure
├── packs/                    # Vynlo starter and tax packs
├── tenant-seeds/drivven/     # first-workspace bootstrap, migration, and test data
├── contracts/                # OpenAPI
├── schemas/                  # portable configuration schemas
├── supabase/                 # migrations, seeds, and database tests when development begins
└── docs/                     # normative product and engineering specifications
```

`tenant-seeds/drivven` exists because Drivven is the first pilot and has a complex migration. It is not a required pattern for every future tenant. Normal tenants are provisioned through Vynlo onboarding and stored as versioned database configuration plus secure object storage.

## Product boundary

Vynlo owns reusable capabilities:

- tenancy, identity, permissions, security, and audit;
- inventory, media, CRM, deals, documents, workflows, tax packs, exports, and integrations;
- a safe expression/calculation runtime;
- mobile-first PWA infrastructure;
- provider adapters, durable jobs, retries, and observability.

Vynlo does **not** own Drivven's RTB wording, 70/30 split, recurring payment rules, GoCardless matching, repossession process, `P###` stock convention, Webflow mapping, Google Drive folder scheme, marketing-payment formula, or accounting export layout.

## Development readiness

The architecture, domain boundaries, data model, APIs, security rules, responsive UX, implementation sequence, and Drivven pilot configuration are ready for development.

The following are production activation inputs, not architecture blockers:

- exact corporate, tax, permit, and provider identifiers;
- final customer-facing legal templates and approved legal wording;
- accountant/legal approval of tax and tenant calculation rules;
- production OAuth credentials and external system IDs;
- approved Drivven calculation fixtures and migration mappings.

An affected feature remains disabled until its activation gate is satisfied. Engineering must not invent legal or accounting content.

## Read first

1. [`DEVELOPMENT_HANDOFF.md`](DEVELOPMENT_HANDOFF.md)
2. [`AGENTS.md`](AGENTS.md)
3. [`docs/00_INDEX.md`](docs/00_INDEX.md)
4. [`docs/architecture/PRINCIPLES.md`](docs/architecture/PRINCIPLES.md)
5. [`docs/VYNLO_PRODUCT_ENGINEERING_SPEC_V2_1.md`](docs/VYNLO_PRODUCT_ENGINEERING_SPEC_V2_1.md)
6. [`docs/implementation/TOOLCHAIN_BASELINE.md`](docs/implementation/TOOLCHAIN_BASELINE.md)
7. [`docs/implementation/IMPLEMENTATION_PLAN.md`](docs/implementation/IMPLEMENTATION_PLAN.md)
8. [`docs/data/ERD.md`](docs/data/ERD.md)
9. [`docs/data/POSTGRES_SCHEMA_SPEC.md`](docs/data/POSTGRES_SCHEMA_SPEC.md)
10. [`contracts/openapi.v1.yaml`](contracts/openapi.v1.yaml)
11. [`docs/tenants/drivven/DRIVVEN_PILOT_SCOPE.md`](docs/tenants/drivven/DRIVVEN_PILOT_SCOPE.md)
12. [`docs/testing/TEST_STRATEGY.md`](docs/testing/TEST_STRATEGY.md)

## Source-control boundaries

Allowed in Git:

- platform source and specifications;
- starter/tax packs;
- non-secret Drivven seed definitions;
- synthetic/redacted test fixtures;
- template source approved for the development team.

Never allowed in Git:

- production credentials or OAuth refresh tokens;
- real customer records or signed contracts;
- unredacted identity documents;
- production exports;
- private keys or service-account files;
- production provider IDs when access policy requires them to remain secret.
