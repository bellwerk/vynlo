# Operational runbook catalogue

Before production, each runbook must include trigger, owner, access required, diagnosis, safe actions, communication, verification, rollback, and post-incident tasks.

Required runbooks:

1. Web/API unavailable.
2. Database degraded or migration failed.
3. Worker queue backlog.
4. Job repeatedly dead-lettered.
5. PDF rendering failure or corrupted output.
6. Media processing backlog/codec failure.
7. Storage provider outage or permission loss.
8. Website/listing provider outage or drift.
9. VIN provider unavailable.
10. OAuth token expired/revoked.
11. Credential rotation.
12. Suspected credential or customer-data exposure.
13. User lost device/session revocation.
14. Cross-workspace access alarm.
15. Backup restore.
16. Accidental configuration activation.
17. Pack rollback/retirement.
18. Number allocation conflict.
19. Migration batch failure.
20. Tenant export/account closure when implemented.

Runbooks must never instruct staff to bypass RLS, edit immutable financial/document rows, reuse a number, expose a Drive link publicly, or paste credentials into logs/issues/chat.
