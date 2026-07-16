# Stage 0 verification and traceability

## Scope

Stage 0 establishes the repository and toolchain foundation only. It implements `VYN-E00-S01` through `VYN-E00-S05` and the shell-level foundations of `VYN-UX-001` and `VYN-I18N-001`. Product workflows, production database schema, RLS policies, and tenant business rules remain deferred to their approved milestones.

## Evidence mapping

| Story or requirement | Stage 0 evidence |
|---|---|
| `VYN-E00-S01` | Root pnpm workspace, `apps/web`, `apps/worker`, and approved package boundaries |
| `VYN-E00-S02` | Strict TypeScript, ESLint, Prettier, Vitest, Playwright/axe, Redocly, Markdown, secret, reusable-source boundary, and dependency checks |
| `VYN-E00-S03` | Pinned Supabase CLI, local config, two synthetic workspace fixtures, and a Docker-backed CI start/reset/query smoke test |
| `VYN-E00-S04` | Least-privilege GitHub Actions, pinned Action SHAs, verified web-build artifact upload, CODEOWNERS, and repository administration checklist |
| `VYN-E00-S05` | Root quick start and local-development troubleshooting |
| `VYN-UX-001`, `T-UX-001`, `T-UX-002` foundation | App Router shell exercised at 360 px and desktop, touch-safe navigation, no horizontal overflow, automated axe scan, and a monorepo-safe shadcn/ui source layout |
| `VYN-I18N-001`, `T-I18N-001` foundation | Parallel English/French message catalogs with key-alignment and accent-preservation tests |
| `VYN-UX-001`, `T-PWA-001` foundation | Web manifest route and browser smoke assertion; update/offline behavior remains a later shell increment |

## Database boundary

`supabase/seed.sql` creates a disposable `stage0.synthetic_workspaces` table only. It is not the production organization/workspace schema. PR 2 owns production migrations, RLS, authentication, memberships, permissions, and cross-workspace database denial tests.

The `quality / database-smoke` GitHub Actions job starts the pinned local Supabase stack, runs `pnpm db:reset`, and queries the running Postgres database. It fails unless the executed seed contains exactly two unique rows and every row is marked as a fixture. The static `pnpm test:db` check remains useful without Docker, but it is not a substitute for this runtime job.

## Tenant boundary

Reusable source and configuration under `apps/`, `packages/`, `scripts/`, and `supabase/` is scanned against tenant-owned reserved-term policies. Tenant packages and tests remain under `tenant-seeds/<workspace>/`; the shared validator discovers and runs them generically without embedding a workspace formula, tax rate, or schedule implementation.

## GitHub-hosted acceptance

Local success is supporting evidence only. PR #1 is mergeable only when the latest GitHub-hosted `quality / validate` and `quality / database-smoke` jobs are both green. The PR description records the reviewed run and commit after GitHub completes them.

## Validation commands

Use `pnpm validate` for the non-provider gate, `pnpm test:e2e` for responsive browser and accessibility checks, and `pnpm worker:health` for the worker process. With Docker running, use `pnpm supabase:start`, `pnpm db:reset`, and `pnpm check:supabase:runtime` to reproduce the database smoke assertion.
