# Toolchain baseline

**Specification date:** 2026-07-15  
**Status:** Required starting baseline; exact patch versions are pinned by the first scaffold commit and lockfile.

## Runtime and package management

- Node.js 24 LTS.
- pnpm 11, pinned in the root `package.json#packageManager` field.
- Corepack updated and enabled for local/CI use.
- One `pnpm-lock.yaml` committed at the repository root.
- No npm/yarn lockfiles.

## Web and UI

- Next.js 16 App Router, exact patch pinned at scaffold time.
- React version required by the selected Next.js release.
- Strict TypeScript.
- Tailwind CSS.
- shadcn/ui source components stored under `packages/ui-web`; upstream components are reviewed like project code.
- Zod for runtime TypeScript validation; JSON Schema for portable configuration contracts.
- Playwright for browser/E2E and PDF rendering tests.

## Backend and data

- Supabase Postgres/Auth/RLS and managed storage as the reference platform.
- Supabase CLI pinned in development tooling and CI.
- SQL migrations under `supabase/migrations`; applied migrations are never edited.
- Postgres-backed transactional outbox/job queue; no external queue is required for Release 1.
- Exact decimal library selected in Milestone 0 and wrapped behind a Vynlo money/decimal package; binary floating point is prohibited for financial calculations.

## Worker and file processing

- Containerized Node worker.
- Playwright/Chromium for PDFs.
- Sharp/libvips for image normalization and derivatives.
- File-signature validation and malware-scanning adapter.
- Reference deployment: Google Cloud Run or equivalent container host approved by ADR.

## Testing and quality

- Unit/invariant tests: Vitest or the stable test runner selected by the team and recorded in the first scaffold ADR.
- Database/RLS tests: pgTAP plus integration tests through Supabase.
- API contract tests: OpenAPI validation plus generated-client compatibility tests.
- Accessibility: automated axe checks plus manual keyboard/screen-reader review.
- Security: secret scanning, dependency/container scanning, upload/template/formula adversarial suites.

## Pinning policy

The initial scaffold pull request shall record exact versions in:

```text
.nvmrc or .tool-versions
package.json engines
package.json packageManager
pnpm-lock.yaml
container base-image digest
GitHub Action commit SHAs
Supabase CLI version
```

Minor/major upgrades require green compatibility tests. Security patches may be expedited but may not bypass database, RLS, API, document, media, and workspace-isolation tests.
