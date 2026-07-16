# Local development and first clone

This document defines the expected developer experience for the application repository after Milestone 0 scaffolding. Commands are normative targets; the scaffold PR shall implement them without requiring hidden local steps.

## Prerequisites

```text
Git
Node.js 24 LTS
pnpm 11 through Corepack
Docker Desktop or compatible container runtime
Supabase CLI
```

Optional provider CLIs are not required for normal local work. Google Drive and Webflow use mocks in local development and dedicated staging connections in staging.

## First clone target

```bash
git clone <private-vynlo-repository-url>
cd vynlo
corepack enable
corepack prepare pnpm@11.13.0 --activate
pnpm install --frozen-lockfile
cp .env.example .env.local
pnpm supabase:start
pnpm db:reset
pnpm dev
```

Expected services:

```text
web/PWA: http://localhost:3000
local Supabase Studio: printed by Supabase CLI
worker: started by pnpm dev; health check available through pnpm worker:health
```

## Required root scripts

The first scaffold must provide:

```text
pnpm dev                 web + worker + local dependencies
pnpm build               production builds for web and worker
pnpm typecheck
pnpm lint
pnpm format:check
pnpm test                unit/invariant suites
pnpm test:db             migrations, constraints, RLS, invariants
pnpm test:api            OpenAPI and API contract tests
pnpm test:e2e            Playwright responsive E2E
pnpm test:security
pnpm test:config         JSON/YAML/schema/package validation
pnpm test:docs           Markdown links and specification lint
pnpm validate            all non-provider CI gates
pnpm supabase:start
pnpm supabase:stop
pnpm db:reset
pnpm db:migrate
pnpm seed:synthetic
```

`pnpm check:supabase` validates the migration/RLS/helper structure, permission-catalog parity, and two-workspace synthetic seed without Docker. With the local Supabase stack running, `pnpm test:db` adds the pgTAP tenancy, permission, MFA/step-up, ownership-spoofing, and append-only audit matrix. `pnpm check:supabase:runtime` reapplies the seed to prove idempotency before checking executed fixture counts.

The GitHub-hosted `quality / database-smoke` job additionally starts Supabase, resets and seeds the local Postgres database, and queries the executed rows. Reproduce that runtime assertion on a Docker-capable machine with:

```bash
pnpm supabase:start
pnpm db:reset
pnpm test:db
pnpm check:supabase:runtime
pnpm exec supabase stop --no-backup
```

## Common setup failures

- **Wrong Node or pnpm version:** use Node 24.18.0 and run `corepack prepare pnpm@11.13.0 --activate`.
- **Frozen lockfile failure:** do not regenerate with npm or yarn; use the pinned pnpm version and commit intentional dependency changes with `pnpm-lock.yaml`.
- **Supabase will not start:** confirm Docker is running and ports 54320-54323 are available, then run `pnpm supabase:stop` before retrying.
- **Playwright browser missing:** run `pnpm exec playwright install chromium`.
- **Python validation import error:** install `python -m pip install -r scripts/requirements.txt`.
- **Windows Corepack permission error:** open an elevated shell only for `corepack enable`; normal project commands should run without elevation.

## Local data rules

- Use synthetic workspaces, users, customers, vehicles, files, and calculations only.
- Do not download production backups, signed documents, identity files, or customer exports into local development.
- Drivven seed import uses synthetic/redacted artifacts from `tenant-seeds/drivven`.
- Local provider adapters default to deterministic mocks.
- Local email is captured by a development mailbox; no real customer message is sent.

## Environment files

- `.env.example` contains names and non-secret defaults only.
- `.env.local` is ignored by Git.
- Tenant/provider credentials are runtime encrypted records, not global environment variables.
- Service-role credentials are server/worker-only and never exposed through `NEXT_PUBLIC_*`.

## Database workflow

1. Add a new forward migration; never edit an applied migration.
2. Add/modify schema documentation and data dictionary.
3. Add RLS policies and negative tests.
4. Reset local database and run all migration tests.
5. Generate/update database types.
6. Include compatibility and rollout notes in the pull request.

## Definition of a working clone

A clean clone is accepted only when one documented command starts the local stack, synthetic users can sign in, two workspaces are isolated, the worker processes a sample job, and the test suite does not depend on developer-specific files or production services.
