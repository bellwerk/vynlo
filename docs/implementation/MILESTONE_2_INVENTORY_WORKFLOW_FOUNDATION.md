# Milestone 2 inventory and workflow database foundation

**Status:** Database implementation and static verification complete; local
Supabase runtime acceptance remains open

**Migration:**
`supabase/migrations/20260716160000_inventory_workflow_foundation.sql`

**Database test:**
`supabase/tests/007_inventory_workflow_foundation.test.sql`

## Scope and ownership boundary

This increment supplies the tenant-neutral database foundation needed for
Milestone 2 inventory operations. It adds workspace-configured locations,
versioned generic workflows, holding-episode detail updates, location transfers,
and workflow transitions without putting business rules in route handlers or
React components.

The database remains the operational source of truth. Each canonical command
updates authoritative state, audit evidence, an outbox event, and an immutable
idempotency receipt in one transaction. Provider work remains downstream of the
outbox. No provider call, tenant name, tenant contract formula, repository path,
or arbitrary tenant code is part of this migration.

This is a database-foundation increment, not the full Milestone 2 exit. VIN
provider decoding, controlled fact/duplicate override commands, cost ledger,
search/read models, saved views, media processing, API/UI wiring, and live
multi-connection acceptance are separate increments.

## Acceptance and traceability

| Acceptance ID | Requirements and tests | Implemented evidence | State |
|---|---|---|---|
| `M2-INV-AC-005` | `VYN-INV-001`, `T-INV-004` | `inventory_units` gains condition, location, exact money, acquisition/availability/sale/closure timestamps, expected sale price, and workflow projection fields. Internal notes live in a separately authorized relation. | Database foundation implemented |
| `M2-INV-AC-006` | `VYN-WF-001`, `T-INV-004` | Generic workflow definitions, bounded semantic versions, localized states, allowlisted transitions, pinned instances, and append-only events drive inventory lifecycle changes. | Database foundation implemented |
| `M2-INV-AC-010` | `VYN-SEC-001`, `T-RBAC-001` | Immutable override/internal permission keys, MFA-role grant invariants, forced RLS, composite workspace keys, hidden-note isolation, and no browser table DML fail closed. | Implemented for exposed database commands |
| `M2-INV-AC-011` | `VYN-API-001`, `VYN-AUD-001`, `VYN-JOB-001`, `T-AUD-001` | Detail, transfer, and transition commands require expected version and idempotency key. Exact replay returns original entity/version/event IDs; a changed fingerprint or stale version fails. Audit and outbox rows commit atomically. | Implemented; concurrent runtime acceptance pending |

The stable requirement/test catalogues remain authoritative. These local
acceptance IDs identify the evidence boundary of this increment.

## Database contract

### Workflow configuration and runtime

`workflow_definitions` owns a workspace/entity/purpose workflow identity.
`workflow_versions.version` is a 5-to-64-character semantic version matching
`MAJOR.MINOR.PATCH`, aligned with `schemas/workflow.schema.json` and portable
workflow artifacts. `schema_version` remains a separate positive integer.

States carry localized labels, a canonical category, and constrained behavior
flags. Transitions reference existing states and an active immutable permission
key. Guards and effects are closed allowlists:

- guards: `required_fields_complete`, `sale_completion_requirements_met`;
- effects: `listing.publish`, `listing.unpublish`, `listing.refresh`,
  `media.retention_review`.

Tenant JavaScript, SQL, shell, filesystem, module imports, and unrestricted
network behavior cannot be stored as executable workflow configuration. A draft
version is populated before activation. Once active or retired, its version
content, states, and transitions cannot be inserted, updated, or deleted. An
active version may move only to `retired` while every configuration and
provenance field remains unchanged; this releases the active-version slot for a
forward correction. Existing instances stay pinned to the exact version on
which they started.

`workflow_instances` stores current state, canonical status, lifecycle status,
and aggregate version for one entity/purpose. `workflow_events` records each
successful transition with actor, reason, request, correlation, and aggregate
version. Event rows are append-only.

### Inventory projection and restricted detail

`inventory_units` remains the holding episode rather than the physical vehicle.
The expansion is compatible with existing M1 rows and callers:

- open status now includes `draft`, `active`, and `pending`;
- terminal status remains `closed` or `archived`;
- `acquisition_date` remains the business date while nullable timestamps record
  acquisition, availability, sale, and closure events;
- advertised and expected sale money use integer minor units and the holding
  episode's ISO currency;
- `location_id` and workflow references are workspace-composite foreign keys;
- `available_at` is prohibited until a workspace-owned location is present;
- `version` is the optimistic-concurrency version shared with the workflow
  instance.

`inventory_unit_internal_details` stores restricted notes outside the broadly
readable inventory row. Reading requires `inventory.read_internal`; changing a
note requires the explicit presence flag plus `inventory.update_internal`.
When the flag is false, the detail command does not read, compare, authorize,
fingerprint, or rewrite the hidden value. Audit, outbox, and receipt results
never contain internal-note content. When the flag is true, the value is an
explicit set operation and is not compared with the prior hidden value, so a
caller with update-only authority cannot probe note equality.

`inventory_location_events` records every committed transfer. Both location and
inventory links preserve workspace ownership. Closed/archived inventory cannot
change details or location.

## Command surface

All commands derive and verify the actor through authenticated membership and
immutable permission keys. The workspace argument is supplied only by the
server-side route/application boundary after resolving authenticated context;
an arbitrary request-body workspace ID is never authoritative.

| Function | Permission behavior | Transaction result |
|---|---|---|
| `app.update_inventory_unit_details` | Requires `inventory.update`; an explicit internal-note update additionally requires `inventory.update_internal`. | New aggregate version, canonical status/state, audit ID, outbox ID, replay state. |
| `app.transfer_inventory_unit_location` | Requires `inventory.update`; destination must be active in the same workspace and a reason is mandatory. | New aggregate version, location-event ID, audit ID, outbox ID, replay state. |
| `app.transition_inventory_workflow` | Requires `inventory.transition` and the transition's configured permission; validates current state, reason, allowlisted guard, and pinned workflow version. | New aggregate version/state/status, workflow-event ID, audit ID, outbox ID, replay state. |

Each command validates a bounded idempotency key, fingerprints normalized
business input, takes an idempotency-scoped transaction advisory lock, locks the
aggregate row, and verifies the expected version. Exact replay returns the
original receipt. Reusing a key with different input produces a conflict, and a
stale expected version uses SQLSTATE `40001` so API callers can map it to the
standard version-conflict response.

`20260716310000_m2_actor_idempotency_hardening.sql` scopes the logical key by
workspace, authenticated actor, and command in the advisory lock, replay
predicate, and composite unique index. Two equally permitted users may therefore
use the same raw client-generated key without receiving or poisoning one
another's receipt. Same-actor receipts written before the cutover remain
replayable; the private implementation functions accept the validated raw key
and have no API-role grant.

## M1 compatibility and seed behavior

The migration runs forward without replacing the M1 create function or making
new workflow columns immediately non-null. Existing holding episodes are
backfilled into an immutable, tenant-neutral `m1.inventory_compat@1.0.0`
workflow whose states preserve the prior canonical status. This compatibility
workflow is database migration state, not tenant source configuration.

After the synthetic seed installs `inventory.standard@1.0.0`, the existing
`app.create_inventory_unit` command automatically creates a pinned instance and
maps its M1 `active` status to `in_preparation`. A workspace without an active
workflow can continue using the M1 contract during a rolling deployment; a
later contract migration may make the relationship mandatory after all
workspaces are provisioned.

The seed is bound to the exact
`packs/starter-retail-dealer/workflows/inventory.yaml` SHA-256 and its complete
state/transition graph. `scripts/validate_spec.py` compares the artifact key,
version, initial state, localized states, behavior flags, guards, reason gates,
effects, and checksum against both synthetic workspace fixtures, so a copied
runtime variant cannot drift silently from the shipped starter pack.

The seed installs only fictional deterministic runtime records: one location
and one nine-state/sixteen-transition workflow per synthetic workspace. It
creates the workflow version as a draft, installs states/transitions, and then
activates it. Reapplying the seed skips child insertion for already-active
versions, preserving immutability.

## RLS, authorization, and audit

- All ten new public tables have RLS enabled and forced.
- Authenticated users receive permission-scoped reads for locations, workflow
  configuration/runtime history, and internal detail; receipts have no browser
  read grant.
- Authenticated users receive no insert, update, or delete grant on any new
  table. The three fixed-search-path security-definer commands are the mutation
  boundary.
- Every workspace-owned foreign key preserves workspace context. Security-
  definer commands query by both workspace and opaque entity ID and return the
  same unavailable error for missing/cross-workspace targets.
- `inventory.duplicate_override` and `inventory.facts_override` can be granted
  only to roles that require MFA. Grant, role-MFA downgrade, and permission
  reactivation paths all recheck the invariant under row locks. This increment
  reserves those keys but does not expose an override command.
- Location events, workflow events, and command receipts reject update/delete
  even from trusted application roles.
- Audit and outbox payloads record only safe changed keys, state, locations,
  aggregate version, correlation, and allowlisted effects. No credentials,
  internal-note values, customer data, or tenant-specific values are seeded.

## API, UI, accessibility, and localization compatibility

The database returns a common command result shape so application/API adapters
can map it consistently. The migration itself adds no route, React component,
or desktop-only interaction. Phone-usable step forms, visible save/conflict
state, bilingual translation keys, desktop table/mobile cards, accessibility
coverage, and OpenAPI wiring belong to the coordinating Milestone 2 source
increment.

Workflow labels are seeded in English and French. No UI should expose raw state,
condition, permission, or effect keys directly; clients resolve translation
keys and localized configuration labels.

## Operations, rollback, and verification

The relevant operational event names are:

- `inventory_unit.updated`;
- `inventory_unit.location_transferred`;
- `inventory_unit.transitioned`.

They preserve aggregate version and correlation ID for log, audit, and job
linkage. Downstream workers must claim durable jobs idempotently and surface
retry/dead-letter state; no provider side effect occurs in these commands.

Rollback means disabling new callers or activating a compatible prior workflow
through a reviewed forward correction. Do not drop or rewrite inventory,
workflow, location, receipt, audit, or outbox history. Schema contraction is
deferred until every deployed caller and workspace is proven compatible.

Static verification parses the migration, seed, and 97-assertion pgTAP suite.
The suite covers schema, RLS, authorization, semantic versions, configuration
activation/retirement immutability, immediate aggregate projection invariants,
hidden-data non-disclosure, idempotency, concurrency conflicts, workspace
isolation, transition rules, terminal behavior, audit/outbox parity, and
append-only history. A local Supabase database run remains required to claim
runtime pgTAP acceptance; the current environment has no available Docker
runtime.

Before production activation, also run a genuine multi-connection contention
test for update/transfer/transition conflicts, verify API conflict mapping and
localized mobile/desktop behavior, exercise outbox retry/dead-letter telemetry,
and retain staging evidence for RLS and rollback behavior.
