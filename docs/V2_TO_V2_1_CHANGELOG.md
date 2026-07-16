# Vynlo specification v2.0 to v2.1 changelog

**Decision date:** 2026-07-15

## Repository and tenancy correction

- Replaced the two-repository recommendation with one canonical private repository: `vynlo`.
- Defined a tenant as a runtime workspace, not a repository, branch, deployment, or code fork.
- Moved Drivven bootstrap/configuration artifacts to `tenant-seeds/drivven` inside the one repository.
- Clarified that future tenants normally require no Git folder or code change.
- Added an exception process for rare dedicated/on-premises/customer-owned deployments.

## Runtime configuration

- Made versioned database configuration and secure object storage the authoritative source of workspace behavior.
- Reframed portable workspace packages as optional import/export/bootstrap artifacts.
- Added configuration lifecycle, impact planning, approval, activation, rollback, and provenance requirements.
- Added feature entitlements as runtime configuration rather than separate deployments.

## Architecture governance

- Added a concise normative engineering-principles document.
- Replaced ADR 0001 with the single-repository modular-monolith decision.
- Added an ADR for runtime workspace configuration.
- Updated dependency rules so reusable platform packages may not import Drivven seed files.

## Development handoff

- Added a milestone-based implementation plan.
- Added actionable platform and Drivven epics/stories.
- Added a pre-development engineering handoff checklist.
- Reordered delivery to prove an end-to-end vertical slice early while preserving the generic platform boundary.

## Product clarifications retained

- Vynlo remains inventory-first and targeted at conventional cash/third-party-financed dealerships.
- Drivven RTB, 70/30, recurring payments, collections, statuses, integrations, and exports remain workspace-specific.
- Camera VIN scanning remains excluded.
- Image normalization remains in Release 1.
- Session maximum remains 14 days with sensitive-action step-up authentication.
- Mobile-first PWA, shadcn/ui, French/English architecture, RLS, outbox/jobs, and immutable document/configuration versions remain required.

## Superseded artifacts

The v2 recommendation to create `vynlo-platform` and `vynlo-tenant-drivven` repositories is superseded. The v2 machine-readable definitions remain valid where not changed by v2.1, but their paths and runtime-installation interpretation now follow the single-repository model.
## Final development-authority additions

- Added a consolidated development handoff and explicit first-pull-request sequence.
- Added a pinned toolchain baseline: Node.js 24 LTS, pnpm 11, Next.js 16 App Router, strict TypeScript, Tailwind CSS, and shadcn/ui source components; exact patches are pinned by the scaffold commit and lockfile.
- Expanded the OpenAPI contract and endpoint catalogue to cover the Release 1 domain surface rather than only illustrative endpoints.
- Added local-development, test-case-catalogue, validation-script, machine-readable validation-result, and SHA-256 manifest artifacts.
- Added portable workspace configuration package schema and clarified that imported packages create draft database configuration; activated database versions remain authoritative.
- Added an explicit Drivven workspace documentation landing page and retained Drivven only as a private first-workspace configuration.
- Confirmed image normalization in Release 1, removal of camera VIN scanning, and 14-day maximum sessions with step-up authentication for sensitive actions.

