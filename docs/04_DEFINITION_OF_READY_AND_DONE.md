# Definition of Ready and Definition of Done

## Ready for implementation

A feature is ready when:

- requirement and classification are identified;
- platform-versus-workspace ownership is explicit;
- roles and permission checks are specified;
- state transitions and failure paths are defined;
- schema/API changes are known;
- acceptance criteria are testable;
- legal/tax activation gates are separated from engineering work;
- no unresolved alternative is hidden in the requirement.

## Done

A feature is done only when:

- implementation, migrations, and API contract are merged;
- RLS/authorization is implemented and tested;
- mobile and desktop behavior is tested;
- accessibility checks pass;
- audit events are verified;
- idempotency/retry behavior is tested for external work;
- observability and user-visible error states exist;
- documentation and traceability are updated;
- starter/tax/workspace-configuration compatibility tests pass;
- rollback or feature-disable procedure is documented.

## Release readiness

A release additionally requires staging UAT approval, backup and restore test, migration dry run, security review, provider validation, approved configuration and pack versions, and a recorded launch/rollback owner.
