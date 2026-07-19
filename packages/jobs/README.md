# @vynlo/jobs

Tenant-neutral policy contracts for the Postgres transactional outbox and durable
worker jobs.

The package owns the canonical job states, failure classification, bounded retry
planning, capped exponential backoff with equal jitter, active-lease decisions,
and recursive rejection of credential-bearing payload keys. It has no provider
adapter and contains no tenant behavior.

Database persistence and service-only lifecycle functions are defined by
`supabase/migrations/20260716110000_outbox_jobs.sql`. A business command must
write its authoritative rows and call `app.enqueue_outbox_job` in the same
transaction. Provider work starts only after commit.
