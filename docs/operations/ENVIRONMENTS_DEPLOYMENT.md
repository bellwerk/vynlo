# Environments and deployment

```text
local: synthetic data and mocks
development: shared engineering, no production data/credentials
staging: production-like, separate Supabase/storage/provider staging
production: protected approvals, secrets, backups
```

Reference deployment:

- Web/API: Vercel.
- Database/Auth/managed storage: Supabase.
- Worker: Google Cloud Run container.
- CI/CD: GitHub Actions.

Equivalent providers require an ADR.

## Release

1. Merge with green CI.
2. Apply development migration/tests.
3. Deploy staging and candidate packs.
4. Run migration dry run, provider smoke, UAT, security, backup.
5. Approve release/versions.
6. Deploy with flags off where needed.
7. Apply migrations, deploy worker/web, activate.
8. Verify dashboards/jobs/critical flows/rollback.

Migrations are forward-only. Destructive changes use expand/migrate/contract and maintain pack compatibility.
