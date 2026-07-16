# Milestone 2 inventory operations

**Status:** Source implementation and static verification complete; local
Postgres/pgTAP runtime acceptance remains open because this environment has no
database runtime

**Migration:**
`supabase/migrations/20260716260000_m2_inventory_operations.sql`

**Database test:**
`supabase/tests/016_m2_inventory_operations.test.sql`

## Scope and traceability

This increment closes the non-media operator surface for `VYN-INV-001`,
`VYN-COST-001`, `VYN-SEARCH-001`, `VYN-WF-001`, `VYN-TEN-001`,
`VYN-SEC-001`, `VYN-AUD-001`, `VYN-API-001`, `VYN-UX-001`, and
`VYN-I18N-001`. It supplies source evidence for `M2-INV-AC-005` through
`M2-INV-AC-011`; the media-specific acceptance boundary is documented
separately.

| Acceptance ID | Implemented evidence |
|---|---|
| `M2-INV-AC-005` | Permission-aware exact detail projection, versioned editable details, current location, masked internal notes, phone-usable operator form, and visible save/conflict/retry state. |
| `M2-INV-AC-006` | Current pinned workflow/version plus only currently authorized, guard-satisfied transitions; the UI posts the selected configured transition to the canonical application command. |
| `M2-INV-AC-007` | Exact cost metrics and bounded ledger with localized active category definitions, posting, step-up reversal, and permission masking. |
| `M2-INV-AC-008` | Active locations feed inventory search and transfer forms by opaque ID; saved-view filters round-trip location IDs. |
| `M2-INV-AC-009` | Owner/private and workspace-shared saved views can be listed, loaded, versioned, cloned, and owner-archived without exposing executable tenant input. |
| `M2-INV-AC-010` | Full-snapshot fact correction requires `inventory.facts_override`, recent strong authentication, expected fact version, a reason, immutable history, and workspace isolation. |
| `M2-INV-AC-011` | Read and command routes use strict application schemas, stable `/api/v1` contracts, expected versions, actor-scoped idempotency, audit assertions, and reference-only outbox evidence. |

## Read and authorization boundary

`app.get_inventory_unit_operations` requires `inventory.read` and returns one
workspace-scoped operator projection. It includes the holding episode, physical
vehicle facts, pinned workflow state/version, current location, optimistic
aggregate version, capability flags, and only allowed transitions whose
configured permission and declarative guard are currently satisfied.

Restricted data fails closed:

- internal notes are `null` without `inventory.read_internal`;
- posted cost and estimated gross are `null` without `costs.read`;
- cost ledger access independently requires both `inventory.read` and
  `costs.read`;
- cost create/reverse and fact override buttons follow server-returned
  capabilities, but the command boundary reauthorizes every request;
- an arbitrary workspace ID carried as a UI preference is never authoritative:
  the server derives the actor from the bearer session and verifies active
  membership and permission before reading or writing.

`app.list_active_inventory_locations` returns at most 200 active,
workspace-owned, versioned locations. `app.get_inventory_unit_costs` returns a
stable created-time/ID cursor, at most 200 immutable ledger entries, exact money
as decimal strings, current metrics, and active localized category definitions.
The category ID submitted by the UI remains opaque and is validated by the
existing canonical cost command.

`app.list_inventory_saved_views` returns complete allowlisted configurations
for the actor's views and active workspace-shared views. Archived views are
visible only to their owner when explicitly requested. No SQL, JavaScript, or
provider instruction can be stored in the view contract.

## Controlled fact correction and immutable history

`app.override_vehicle_facts` replaces the complete mutable fact snapshot; it
does not patch an ambiguous subset or change the VIN. The command:

1. requires `inventory.facts_override` with recent strong authentication;
2. validates normalized bounded values, expected fact version, reason,
   correlation, and actor-scoped idempotency;
3. locks the physical vehicle and rejects stale/no-op updates;
4. increments `facts_version` exactly once;
5. writes append-only before/after provenance and audit evidence;
6. commits a minimized `vehicle.facts_overridden` outbox event containing only
   vehicle ID, new fact version, and history ID;
7. stores an immutable receipt and returns the original evidence on exact
   replay.

Both fact-history tables use workspace-composite foreign keys, forced RLS, and
append-only triggers. Authenticated clients receive no direct DML. History
reads require inventory read plus fact-override permission; receipt reads are
limited to the original actor with that permission.

## API and application contract

The exact source routes are:

| Method/path | Contract |
|---|---|
| `GET /api/v1/inventory-units/{id}` | Permission-aware operator projection. |
| `PATCH /api/v1/inventory-units/{id}` | Canonical versioned detail update. |
| `GET/POST /api/v1/inventory-units/{id}/costs` | Bounded ledger/categories/metrics and canonical cost posting. |
| `GET /api/v1/locations` | Active inventory locations. |
| `GET/POST /api/v1/inventory-saved-views` | List complete visible configurations or save a versioned view. |
| `POST /api/v1/inventory-saved-views/{id}/archive` | Owner-only optimistic archive with exact replay. |
| `POST /api/v1/vehicles/{id}/facts-override` | Recent-step-up full fact replacement. |

The application layer validates IDs, bodies, query cursors, exact response
shapes, and all database RPC results. Money reads stay strings across the JSON
boundary. Command routes map stale versions and idempotency reuse to conflict,
missing assurance or permission to forbidden, inaccessible entities to not
found, and invalid business state to unprocessable input. OpenAPI documents
the same strict camel-case envelopes and command bodies.

## Mobile, desktop, localization, and accessibility

`/inventory` now loads active locations and full saved-view configurations.
The selected location survives search and saved-view load/save. Owner views can
be updated or archived; a shared view is cloned into a new private view rather
than mutating another actor's configuration.

`/inventory/{id}` is a mobile-first operator dossier rather than a desktop-only
table. It provides detail, transfer, workflow, cost, reversal, fact-correction,
and media navigation with preserved drafts, visible save state, inline conflict
reload, retry, and step-up guidance. At desktop widths, operational forms and
the fact dossier use a restrained two-column layout. All controls have labels,
keyboard focus styles, phone-sized targets, semantic status/alert regions, and
no hover-only action. English and French text comes from translation keys;
workflow and cost category labels come from versioned localized configuration.

The media manager at `/inventory/{id}/media` uses an active-membership resolver
for direct navigation. A requested workspace query value is treated only as a
preference, validated against active memberships, and otherwise falls back to
the first authorized workspace.

## Compatibility, operations, and rollback

The migration is additive. It does not rewrite inventory, cost, workflow,
saved-view, audit, or outbox history and does not change an existing command
signature. The two new tables are provenance/receipt relations; read RPCs add
bounded projections over existing authoritative data.

No read or saved-view archive performs a provider side effect. Fact correction
commits the authoritative database change and reference-only outbox record in
one transaction; downstream consumers must remain idempotent by event ID and
surface retry/dead-letter telemetry through the shared durable-job platform.

Rollback is forward-only: stop the new callers, retain immutable history and
receipts, and correct schemas/configuration through a reviewed forward
migration. Never delete or rewrite fact, ledger, workflow, audit, outbox, or
saved-view lifecycle evidence.

## Verification state

Focused application and route suites cover successful reads/writes, malformed
IDs/bodies/cursors, permission and assurance failures, conflict mapping,
strict database response validation, idempotent replay, and workspace context.
The 64-assertion pgTAP source suite covers forced RLS, browser grants,
same/cross-workspace behavior, cost masking/categories/cursors, saved-view
owner/share/archive semantics, AAL and permission failure, fact version/no-op
conflicts, audit/outbox/history evidence, replay/reuse, and append-only tables.

TypeScript, focused Vitest suites, OpenAPI lint, and the static Supabase
foundation checker are expected gates for this increment. A real local or
staging Postgres run of migration plus pgTAP remains required before claiming
runtime RLS, trigger, advisory-lock, or contention acceptance.
