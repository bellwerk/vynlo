# ADR-0004: Transactional outbox and worker

**Status:** Accepted

Provider, PDF, and media work is represented by durable jobs created with the business transaction. A container worker claims with Postgres locking and applies retries.
