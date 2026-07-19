# @vynlo/workflows

Workflow engine ownership boundary for immutable, versioned state machines and
deterministic transition planning.

This package is an ownership boundary inside the modular monolith, not an
independently deployed service. It performs no persistence, provider, network,
filesystem, clock, or random operation.

## Milestone 2 contracts

- `defineVersionedWorkflow` validates, copies, and freezes definitions, states,
  transitions, translated labels, flags, required fields, guards, and effects.
  Existing instances pin the exact definition key, semantic version, and
  SHA-256 checksum.
- Guards are finite declarative keys only:
  `required_fields_complete` and `sale_completion_requirements_met`. Trusted
  application services evaluate those facts; a missing or false result denies
  the transition.
- Effects are inert outbox declarations only: `listing.publish`,
  `listing.unpublish`, `listing.refresh`, and `media.retention_review`.
  JavaScript, SQL, shell, filesystem, module, URL, HTTP, and arbitrary network
  constructs are not accepted.
- A transition requires the immutable permission key, exact aggregate version,
  source state, target/transition fields, configured guard, and reason when
  declared. The caller supplies event IDs and time, so the next instance,
  append-only workflow event, and outbox event are deterministic.

## Compatibility notes

The module is additive to the prior package boundary. Persistence adapters map
`guard_key` and `effect_keys` directly to these catalogs and must commit the
instance/entity version, workflow event, audit event, and outbox row atomically.
Role labels and request-supplied workspace IDs are never transition authority.
A definition change requires a new immutable version/checksum; it is not an
in-place edit to an active or previously pinned artifact.
