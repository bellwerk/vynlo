# Observability, backup, recovery, and incidents

## Observability

Structured logs with request/correlation/job/workspace IDs and PII redaction. Error tracking for web/worker. Metrics for API latency/error, queue depth/age, job failure, provider error/rate limit, PDF/media duration, auth failures, storage use.

Alert on dead letters, failed backups, credential expiry, and sustained sync lag.

## Pilot service targets

- Core API p95 < 500 ms excluding queued provider work.
- Key mobile page usable within 2.5 s on reasonable 4G after authentication/cache warmup.
- Normal listing sync target < 60 s.
- Typical photo processing < 120 s.
- Typical PDF generation < 60 s.
- 99.5% monthly pilot availability excluding planned maintenance.

## Recovery

- Database RPO one hour or better.
- RTO four hours or better.
- Daily critical configuration/pack export.
- Restore test before launch and at least quarterly; monthly during pilot preferred.

Cross-workspace exposure is critical severity. Incidents record owner, containment, credential revocation, impact, evidence, communications, recovery, and postmortem.
