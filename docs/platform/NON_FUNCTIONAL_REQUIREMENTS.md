# Non-functional requirements

## Availability and recovery

### Pilot targets

- Core web/API monthly availability target: 99.5%, excluding announced maintenance and external provider outages.
- SaaS general-availability target after operational validation: 99.9%.
- Database recovery point objective: one hour or better.
- Service recovery time objective: four hours or better.
- Provider outage must degrade only the affected integration; authoritative Vynlo writes remain available where safe.

Targets are monitored and revised before a paid SLA is offered. No customer contract may promise a higher SLA than the measured architecture supports.

## Performance

Measured with production-like staging data:

| Operation | Target |
|---|---|
| Authenticated API read excluding file/provider calls | p95 ≤ 500 ms |
| Authoritative API mutation excluding async provider work | p95 ≤ 800 ms |
| Inventory search/list query | p95 ≤ 750 ms |
| Mobile initial useful content on mid-range device/4G | p75 ≤ 2.5 s |
| Route interaction response | p75 ≤ 200 ms when no server round trip is required |
| Background listing sync after queue | normally ≤ 60 s |
| Single image normalization after upload completes | p95 ≤ 30 s |
| PDF preview render | p95 ≤ 30 s |
| Official PDF render | p95 ≤ 60 s |
| Export ≤ 10,000 rows | p95 ≤ 60 s |

If a target cannot be met, the UI must show durable progress rather than time out or pretend completion.

## Scale design targets

The initial architecture shall support without tenant-specific redesign:

```text
50 locations per workspace
250 active users per workspace
10,000 active inventory units per workspace
100,000 historical inventory units per workspace
50 media items per inventory unit by default
1,000,000 audit events per workspace with partition/archive strategy
100 concurrent web sessions per workspace
```

These are engineering design/test targets, not plan entitlements.

## Browser/device support

- Current and previous major Chrome, Edge, Firefox, and Safari.
- Current and previous major iOS Safari and Android Chrome.
- Minimum supported layout width 360 CSS px.
- Tablet reference 768 px; desktop 1280 px and above.
- No Internet Explorer.

## Accessibility and localization

- WCAG 2.2 AA target.
- English and French UI keys from first release.
- Unicode throughout.
- Locale-aware dates, numbers, currencies, and addresses.
- Machine keys/IDs remain language-independent.
- No customer legal text is machine-translated without tenant approval.

## Upload and processing limits

Default limits, configurable by plan/workspace within security maximums:

```text
vehicle photo original: 20 MB
general/signed PDF: 50 MB
vehicle media items: 50
signed scan pages: 25
general attachment: 50 MB
bulk upload concurrency per user: 4
```

Reject unsupported MIME/signature, decompression/pixel bombs, encrypted PDFs that cannot be safely processed when a preview is required, and files exceeding policy. Preserve legal originals according to retention policy.

## API and jobs

- Cursor page default 50, maximum 100.
- Every duplicate-prone mutation supports idempotency.
- Default provider job attempts: eight with exponential backoff/jitter; adapter may lower for known permanent errors.
- Worker leases expire and jobs are reclaimable.
- All externally visible long work is asynchronous.
- Dead-letter and provider drift are visible to authorized operators.

## Consistency

Strong transaction consistency is required for:

- stock/document number allocation;
- official document and immutable snapshot creation;
- workflow transition plus audit/outbox;
- financial transaction settlement/reversal;
- configuration/pack/version activation;
- permission/membership changes.

Provider sync is eventual and exposes state.

## Security targets

- MFA and step-up policy enforced server-side.
- RLS negative tests for every exposed table.
- No known critical/high dependency or container vulnerabilities at release unless formally risk accepted.
- Secret scanning on every pull request.
- Security headers and CSP applied to web/PDF-preview surfaces.
- Rate limiting and abuse protection on auth, uploads, search, exports, and render/calculation APIs.
- Template/formula sandbox resource limits and adversarial tests.

## Maintainability

- Strict TypeScript; no untyped financial/domain boundary.
- Database and API changes include migration/compatibility tests.
- Platform modules do not import workspace seed directories or tenant-owned runtime assets.
- Public package contracts use semantic versions.
- Architectural exceptions require ADR.
- Operationally meaningful actions include structured logging/metrics/tracing.
