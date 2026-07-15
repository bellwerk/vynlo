# Contributing

## Branching and review

- Protect `main`.
- Use short-lived branches: `feat/`, `fix/`, `docs/`, `chore/`.
- Require pull-request review, green CI, and migration review.
- Squash merge unless preserving a migration sequence requires otherwise.

## Required pull-request information

- Requirement IDs addressed.
- Architecture decision affected, if any.
- Database/RLS impact.
- API compatibility impact.
- Workspace-configuration and reusable-pack compatibility impact.
- Security/privacy impact.
- Tests added.
- Screenshots at mobile and desktop widths for UI changes.
- Rollback or feature-flag plan.

## Database changes

- Never edit an applied migration.
- Add forward migrations and document rollback/recovery.
- Avoid destructive changes until all dependent workspace configuration versions and reusable packs are migrated.
- Add indexes based on query plans, not guesses.

## Configuration and pack compatibility

Breaking workspace-configuration or reusable-pack schema changes require a new major schema version, migration tooling or a documented path, compatibility tests, and coordinated activation of dependent runtime configuration. A tenant does not require a repository.

## Documentation

Normative requirements use `MUST`, `MUST NOT`, `SHOULD`, and `MAY`. Any unresolved business choice must be recorded as an activation gate, not hidden in a TODO comment.
