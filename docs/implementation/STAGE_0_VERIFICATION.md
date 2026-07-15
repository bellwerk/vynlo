# Stage 0 verification and traceability

## Scope

Stage 0 establishes the repository and toolchain foundation only. It implements `VYN-E00-S01` through `VYN-E00-S05` and the shell-level foundations of `VYN-UX-001` and `VYN-I18N-001`. Product workflows, production database schema, RLS policies, and tenant business rules remain deferred to their approved milestones.

## Evidence mapping

| Story or requirement | Stage 0 evidence |
|---|---|
| `VYN-E00-S01` | Root pnpm workspace, `apps/web`, `apps/worker`, and approved package boundaries |
| `VYN-E00-S02` | Strict TypeScript, ESLint, Prettier, Vitest, Playwright/axe, Redocly, Markdown, secret, boundary, and dependency checks |
| `VYN-E00-S03` | Pinned Supabase CLI, local config, and two synthetic workspace fixtures |
| `VYN-E00-S04` | Least-privilege GitHub Actions, pinned Action SHAs, CODEOWNERS, build artifact, and repository administration checklist |
| `VYN-E00-S05` | Root quick start and local-development troubleshooting |
| `VYN-UX-001`, `T-UX-001`, `T-UX-002` foundation | App Router shell exercised at 360 px and desktop, touch-safe navigation, no horizontal overflow, and automated axe scan |
| `VYN-I18N-001`, `T-I18N-001` foundation | Parallel English/French message catalogs with key-alignment and accent-preservation tests |
| `VYN-UX-001`, `T-PWA-001` foundation | Web manifest route and browser smoke assertion; update/offline behavior remains a later shell increment |

## Database boundary

`supabase/seed.sql` creates a disposable `stage0.synthetic_workspaces` table only. It is not the production organization/workspace schema. PR 2 owns production migrations, RLS, authentication, memberships, permissions, and cross-workspace database denial tests.

## Validation commands

Use `pnpm validate` for the non-provider gate, `pnpm test:e2e` for responsive browser and accessibility checks, `pnpm worker:health` for the worker process, and `pnpm supabase:start` with Docker running for the local database stack.
