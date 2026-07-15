# Repository structure

**Decision:** One canonical private repository named `vynlo`.

```text
vynlo/
├── apps/
│   ├── web/                         # Next.js web app, API routes, PWA shell
│   └── worker/                      # PDF, media, integration, reconciliation jobs
├── packages/
│   ├── api-contracts/               # OpenAPI-generated/shared request types
│   ├── application/                 # commands, queries, use cases, transactions
│   ├── domain/                      # tenant-neutral entities and invariants
│   ├── database/                    # typed repositories and migration helpers
│   ├── validation/                  # Zod/JSON Schema validation
│   ├── auth/                        # membership, permissions, assurance helpers
│   ├── inventory/
│   ├── media/
│   ├── crm/
│   ├── deals/
│   ├── documents/
│   ├── workflows/
│   ├── calculations/
│   ├── tax/
│   ├── exports/
│   ├── integrations/
│   ├── jobs/
│   ├── observability/
│   ├── design-tokens/
│   ├── ui-web/                      # shadcn/ui source components
│   └── test-support/
├── packs/
│   ├── starter-retail-dealer/       # editable Vynlo defaults/demonstrations
│   └── tax/ca-qc/                   # candidate jurisdiction pack
├── tenant-seeds/
│   └── drivven/                     # bootstrap/migration/test configuration only
├── contracts/
│   └── openapi.v1.yaml
├── schemas/
│   ├── calculation.schema.json
│   ├── document-type.schema.json
│   ├── export-definition.schema.json
│   ├── tax-pack.schema.json
│   ├── workflow.schema.json
│   └── workspace-config-package.schema.json
├── supabase/
│   ├── migrations/
│   ├── seed/
│   └── tests/
├── docs/
├── package.json
├── pnpm-workspace.yaml
└── turbo.json                         # optional only if adopted by ADR
```

## Tenant-seed rule

`tenant-seeds/drivven` is not a second application and is not imported by platform packages. It may contain:

- synthetic or redacted seed definitions;
- schemas, templates, formulas, workflows, exports, and mappings;
- migration instructions;
- Drivven-specific acceptance tests.

It must not contain credentials, real customers, signed documents, production exports, service-account files, or unredacted identity documents.

A future tenant does not automatically receive a folder. Normal onboarding creates versioned runtime configuration through Vynlo. A seed folder is justified only for repeatable migration, complex enterprise provisioning, demo/test workspaces, or contractual source-review requirements.

## Dependency direction

```text
apps/web and apps/worker
  -> packages/application
    -> domain packages and policy interfaces
      -> persistence/provider ports
        -> infrastructure adapters
```

Forbidden dependencies:

- platform package -> `tenant-seeds/drivven`;
- domain package -> Next.js/React/provider SDK;
- UI component -> direct database/service-role client;
- template -> arbitrary executable code;
- migration -> external provider call.

## Package policy

Packages are code-ownership boundaries, not separately deployed services. A new package requires a clear domain owner and public interface. Do not create a package for every small feature.

## Branch and release policy

- `main` is protected and deployable.
- Short-lived feature branches and pull requests are required.
- Schema/config compatibility validation runs in CI.
- Production configuration activation is a runtime approval, not necessarily a code deployment.
