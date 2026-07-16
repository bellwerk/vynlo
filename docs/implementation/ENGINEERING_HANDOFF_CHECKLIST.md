# Engineering handoff checklist

The development lead should complete this checklist before opening feature implementation pull requests.

## Repository

- [ ] Create private GitHub repository `vynlo`.
- [ ] Commit this specification package at the repository root.
- [ ] Protect `main`; require pull request, reviews, and green CI.
- [ ] Configure secret scanning and dependency alerts.
- [ ] Create CODEOWNERS for architecture, database/RLS, security, and Drivven tenant configuration.

## Environment ownership

- [ ] Assign owners for local, development, staging, and production.
- [ ] Create separate Supabase projects/databases for non-production and production.
- [ ] Define secret manager and key-rotation responsibility.
- [ ] Create synthetic test workspaces; do not import production data into development.

## Product and architecture

- [ ] Read `AGENTS.md` and `docs/architecture/PRINCIPLES.md`.
- [ ] Confirm one-repository and runtime-workspace-configuration decisions.
- [ ] Confirm modular-monolith package owners.
- [ ] Confirm API, outbox/worker, RLS, document sandbox, and media-processing approaches.
- [ ] Record any technology substitution as an ADR before implementation.

## Drivven

- [ ] Treat `tenant-seeds/drivven` as bootstrap/test configuration only.
- [ ] Keep RTB, 70/30, payments, collections, statuses, folders, Webflow, and export rules outside platform source.
- [ ] Identify business/admin, accounting, and legal approvers.
- [ ] Obtain a redacted field catalogue and final template plan before production activation.
- [ ] Inventory existing Drive folders and Webflow items for migration sizing.

## Definition of ready for each epic

- [ ] Requirement IDs and acceptance criteria exist.
- [ ] Data ownership and workspace boundary are explicit.
- [ ] API/commands/queries and failure codes are specified.
- [ ] Permissions, RLS, audit, and step-up needs are specified.
- [ ] State transitions and concurrency behavior are specified.
- [ ] Mobile and desktop screen behavior is specified.
- [ ] Background jobs/provider failure behavior is specified.
- [ ] Test IDs and operational telemetry are identified.

## Production activation remains blocked until

- [ ] Final corporate identifiers are verified.
- [ ] Provider credentials/IDs are connected in staging and production.
- [ ] Relevant tax pack is professionally approved.
- [ ] Customer-facing legal templates are approved.
- [ ] Tenant formulas have approved exact fixtures.
- [ ] Migration reconciliation and UAT are signed.
- [ ] Backup/restore and incident runbooks are exercised.
