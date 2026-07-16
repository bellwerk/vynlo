# System architecture

```text
Browser / installed PWA
        |
        v
Next.js web application
- UI and server rendering
- /api/v1 route handlers
- application services
        |
        +------------------+
        |                  |
        v                  v
Supabase Postgres      Supabase Auth
- RLS                  - identities
- domain data          - sessions/MFA
- outbox/jobs
        |
        v
Container worker
- job claims
- PDF rendering
- media processing
- provider synchronization
- scheduled reconciliation
        |
        +--> managed/external storage
        +--> website/listing providers
        +--> VIN providers
        +--> transactional email
        +--> future finance/marketplace providers
```

## Source of truth

- Postgres is the operational source of truth for entities, state, mappings, versions, and audit.
- Storage providers are the source of file bytes under a recorded provider policy.
- External websites are publication destinations, never authoritative inventory databases.
- Provider drift is represented as a conflict/reconciliation state.

## Application layers

```text
UI / API adapters
Application services / commands / queries
Domain models and policies
Persistence and provider ports
Infrastructure adapters
```

React components must not implement tax, formula, numbering, workflow, or authorization logic.

## Data ownership

- Platform configuration defines engines and schemas.
- Starter packs define editable defaults.
- Tax packs define approved jurisdiction rules.
- Versioned runtime workspace configuration defines private tenant behavior.
- Credentials are encrypted runtime records, never Git seed or portable package files.

## Reference deployment

- Web/API: Vercel or equivalent Next.js hosting.
- Database/Auth/managed storage: separate Supabase project per environment.
- Worker: container deployment capable of Playwright, Sharp/libvips, and file scanning; Google Cloud Run is the reference target.
- Environments: local, development, staging, production.
