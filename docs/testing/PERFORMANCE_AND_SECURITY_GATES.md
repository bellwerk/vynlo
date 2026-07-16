# Performance and security release gates

## Performance

- NFR targets tested with production-like seeded data.
- Query plans reviewed for inventory/lead/deal/document lists.
- No unbounded list endpoint.
- Upload/render/export jobs tested under configured concurrency.
- Job backlog recovers after provider outage.
- `pnpm test:stock-concurrency` passes against local and staging with at least
  100 real connections; stock allocations remain unique and contiguous and a
  rollback burns no number. Document-number concurrency is repeated when the
  official numbering engine enters Milestone 4.
- Mobile pages meet agreed useful-content and interaction targets.
- PDF/media worker memory and timeout limits verified against maximum files.

## Security

- RLS test matrix passes for every exposed table.
- IDOR/cross-workspace attempts return inaccessible behavior.
- Role escalation and workspace-ID spoof attempts fail.
- Step-up actions reject stale/low-assurance sessions.
- Template injection, SSRF, local-file access, script execution, and resource-exhaustion tests fail closed.
- Formula cycles, depth/node/row/time limits and invalid money/rates fail closed.
- Malicious/invalid uploads, extension spoofing, pixel bombs, and oversized files are rejected.
- Secrets do not appear in source, build artifacts, logs, traces, errors, exports, or client bundles.
- Dependency/container/IaC scans meet release policy.
- CSP, cookies, CORS, CSRF strategy, security headers, and rate limits verified.
- Backup and incident exercises completed.

No release proceeds with an unaccepted critical or high vulnerability.
