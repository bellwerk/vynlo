## Summary

Describe the user-visible and architectural change.

## Traceability

- Requirement IDs:
- Acceptance-criterion IDs:
- Test-case IDs:
- Related ADR/configuration version:

## Boundary review

- [ ] This change contains no workspace-name branch or hardcoded Drivven business rule in reusable platform code.
- [ ] Workspace-specific behavior is represented as validated, versioned configuration.
- [ ] No production secret, customer data, signed document, identity document, or unredacted fixture is included.

## Data, API, and compatibility

- [ ] Database/schema impact is documented and migrations are additive/reversible where possible.
- [ ] RLS `USING` and `WITH CHECK` behavior is covered by positive and cross-workspace negative tests.
- [ ] OpenAPI/contracts and generated clients are updated when applicable.
- [ ] Configuration/package compatibility and rollback behavior are documented.

## Security and privacy

- [ ] Permission and step-up-authentication requirements are tested.
- [ ] Audit events are emitted for privileged or financially significant actions.
- [ ] Logs, traces, and error details contain no prohibited sensitive data.
- [ ] Upload/template/formula/integration attack surfaces were considered.

## UX evidence

- [ ] Mobile evidence at 360–390 px is attached for user-interface changes.
- [ ] Desktop/tablet evidence is attached where applicable.
- [ ] Keyboard, focus, labels, validation, loading, empty, error, and retry states were tested.
- [ ] French and English keys are provided; user-facing text is not hardcoded.

## Reliability and operations

- [ ] External side effects use outbox/jobs, idempotency, retries, and observable failure states.
- [ ] Concurrency and duplicate-delivery behavior are tested.
- [ ] Metrics/logging/tracing and runbook impact are documented.
- [ ] Rollback, feature-disable, or recovery plan is described.

## Test evidence

List commands and results, including unit, database/RLS, contract, integration, E2E, accessibility, and security checks that apply.

## Activation gates

List any legal, tax, accounting, provider, template, or production-data inputs that remain gated. Do not mark a gated capability production-ready without an approval record.
