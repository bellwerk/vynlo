# Vynlo development handoff

**Specification:** Vynlo Product & Engineering Specification v2.1.0  
**Decision date:** 2026-07-15  
**Repository:** one private repository named `vynlo`  
**Status:** Authorized for engineering development; production activation remains gated where listed.

## Product statement

Vynlo is an independent, inventory-first SaaS for small and medium vehicle dealerships. Its normal customer manages inventory, media, leads, customers, cash sales, occasional third-party financing, documents, website publishing, and reporting.

Drivven is the first configured workspace. Its RTB contract, 70/30 split, recurring-payment behavior, workflow labels, `P###` numbering, Drive/Webflow mappings, and accounting export are private workspace configuration. They are not Vynlo defaults and must never appear as workspace-name branches in platform code.

## Non-negotiable architecture

1. One modular-monolith repository; no repository per tenant.
2. `workspace_id` is the operational/RLS boundary.
3. A future tenant is provisioned through runtime workspace configuration; Git changes are not normal onboarding.
4. Next.js mobile-first PWA plus a container worker.
5. Postgres is the operational source of truth.
6. Provider work uses the transactional outbox and durable jobs.
7. Financial calculation uses exact decimal arithmetic and immutable snapshots.
8. Official documents and activated configuration versions are immutable.
9. Every exposed table has RLS and automated negative tests.
10. Drivven seed artifacts may be imported through the configuration interface but may not be imported by reusable platform packages.

## Governing reading order

1. `AGENTS.md`
2. `docs/architecture/PRINCIPLES.md`
3. `docs/02_DECISION_REGISTER.md`
4. `docs/VYNLO_PRODUCT_ENGINEERING_SPEC_V2_1.md`
5. `docs/architecture/REPOSITORY_STRUCTURE.md`
6. `docs/data/POSTGRES_SCHEMA_SPEC.md`
7. `docs/data/RLS_POLICY_MATRIX.md`
8. `contracts/openapi.v1.yaml`
9. `docs/implementation/IMPLEMENTATION_PLAN.md`
10. `docs/implementation/EPICS_AND_STORIES.md`
11. `docs/tenants/drivven/DRIVVEN_PILOT_SCOPE.md`
12. `docs/testing/TEST_STRATEGY.md`

When documents conflict, the decision register and ADRs take precedence, followed by the consolidated specification, module/data/API documents, workspace-specific documents, and finally examples.

## First pull requests

### PR 1 — repository and toolchain

- Scaffold pnpm workspace using the pinned toolchain baseline.
- Add `apps/web`, `apps/worker`, shared package folders, root scripts, lockfile, CI, CODEOWNERS, pull-request template, and synthetic two-workspace seed.
- Add no feature implementation beyond health checks and the application shell.

### PR 2 — tenancy, auth, and RLS foundation

- Implement organizations, workspaces, profiles, memberships, roles, permissions, legal entities, brands, and locations.
- Add invite-only authentication, MFA policy, 14-day session maximum, step-up helper, RLS helpers, and cross-workspace negative tests.
- Add audit/outbox transaction primitives.

### PR 3 — first vertical slice

- Create a minimal inventory unit from manually entered VIN data.
- Allocate a stock number only on confirmed creation.
- Queue and process one worker job.
- Render one watermarked synthetic document preview.
- Verify the complete browser -> API/application -> Postgres/RLS -> outbox -> worker -> storage path at 360 px and desktop widths.

Subsequent work follows `docs/implementation/IMPLEMENTATION_PLAN.md`.

## Rules for unresolved external inputs

Engineering may use synthetic IDs, watermarked templates, mock providers, and candidate calculation fixtures. Engineering must not invent:

- legal wording;
- tax or accounting conclusions;
- corporate/permit identifiers;
- production OAuth credentials or provider IDs;
- Drivven production numbering start values;
- final customer-facing template approval.

The related feature remains disabled or preview-only and returns explicit activation-gate errors.

## Required PR evidence

Every PR includes:

```text
Requirement and acceptance IDs
Architecture/data/API impact
Workspace/RLS and permission impact
Security/privacy impact
Migration and compatibility notes
Mobile and desktop evidence for UI
Tests and failure/concurrency/idempotency coverage
Observability and rollback/disable plan
```

## Handoff completion criteria

The development lead acknowledges:

- the one-repository/workspace-configuration model;
- the platform-versus-Drivven boundary;
- the production activation gates;
- the implementation sequence;
- the security and test requirements;
- that this v2.1 package supersedes all v1/v2 planning files.
