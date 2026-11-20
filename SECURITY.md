# Security policy

Do not open public issues containing vulnerabilities, credentials, personal data, contract files, or provider identifiers.

- Secrets reside in the deployment secret store or encrypted integration-credential records.
- Local development uses synthetic data only.
- Production support access is time-limited, approved, and audited.
- Customer documents are private by default and never use permanent public URLs.
- File uploads are quarantined until validation and malware scanning complete.
- Security-sensitive changes require review from an authorized maintainer.

The operational incident runbook is in `docs/operations/OBSERVABILITY_BACKUP_INCIDENTS.md`.

## Web server and gateway images

`pnpm check:nginx` (part of `pnpm test:security` and `pnpm verify`) rejects nginx images older than the nginx2root fixes for CVE-2026-123007, CVE-2026-123633, CVE-2026-123634, CVE-2026-121810 and CVE-2026-113425: use nginx 1.30.7+ (stable) or 1.31.9+ (mainline) with an exact version tag. OpenResty and Kong images are rejected until a maintainer confirms a fixed release and records it in `scripts/check-nginx-versions.mjs`.

The local Supabase stack started by the pinned Supabase CLI includes a Kong gateway built on OpenResty. Use it only on a trusted development machine or CI runner, do not expose ports 54321–54323 beyond localhost, and upgrade the CLI once Supabase ships a Kong image with the nginx2root fixes.
