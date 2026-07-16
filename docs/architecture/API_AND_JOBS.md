# API and background jobs

## API rules

- Base path: `/api/v1`.
- Stable machine keys; translated labels are UI concerns.
- Mutations support `Idempotency-Key` where duplicate submission is plausible.
- Errors use `code`, `message`, `field_errors`, `request_id`, and retry guidance.
- Optimistic concurrency uses row version or timestamp preconditions.
- Pagination is cursor-based for large lists.
- `contracts/openapi.v1.yaml` is normative and grows with implementation.

## Command transaction

```text
BEGIN
- validate membership/permission
- validate expected version
- change business rows
- write audit event
- write outbox/job
COMMIT
```

Provider work occurs after commit.

## Job lifecycle

```text
queued -> running -> succeeded
                 -> retry_wait -> running
                 -> dead_letter
                 -> cancelled
```

Required fields include workspace, job type, entity, idempotency key, payload version, priority, attempts, availability/locks, errors, correlation ID, and timestamps.

## Retry and reconciliation

- Exponential backoff with jitter.
- Provider-specific permanent/transient classification.
- No retry for validation/permission errors without correction.
- Idempotency prevents duplicate folders, listings, assets, and documents.
- Dead letters are visible to authorized admins.
- Reconciliation compares provider state with mappings and reports drift without silent adoption.
