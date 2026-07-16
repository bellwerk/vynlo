# Milestone 2 confirmed VIN inventory intake

**Status:** Source implementation and static verification complete; local
Postgres/pgTAP runtime acceptance remains open because Docker is unavailable

**Migrations:**
`supabase/migrations/20260716200000_inventory_intake_from_vin.sql` and
`supabase/migrations/20260716280000_m2_vin_intake_completion.sql`

**Database tests:**
`supabase/tests/011_inventory_intake_from_vin.test.sql` and
`supabase/tests/018_m2_vin_intake_completion.test.sql`

## Scope and traceability

This increment closes the gap between a successful VIN decode and authoritative
inventory creation for `VYN-INV-001`, `VYN-INV-002`, `VYN-NUM-001`,
`VYN-TEN-001`, `VYN-SEC-001`, `VYN-AUD-001`, and `VYN-API-001`.

`app.create_inventory_unit_from_vin_decode` is now the only inventory-create
RPC executable by an authenticated API caller. The earlier
`app.create_inventory_unit` function remains an owner-only transactional
allocation primitive so its proven counter locking can be reused internally;
all API-role execution grants are revoked. Historical pgTAP suites temporarily
grant the primitive only inside their rolled-back test transactions to preserve
pre-cutover fixture coverage.

## Commit-time invariants

The canonical command:

1. derives the actor and verifies `inventory.create` in the authenticated
   workspace;
2. requires the exact successful decode request, immutable result identifier,
   current aggregate version, and an explicit `accepted: true` fact
   confirmation;
3. serializes the idempotency key, decode request, and workspace VIN with
   transaction advisory locks;
4. rechecks the current physical vehicle and holding episodes instead of
   trusting an earlier duplicate snapshot;
5. requires a matching append-only review for vehicle-only or historical VINs;
6. permits a historical reacquisition only after
   `reacquire_existing_vehicle`; a stepped-up, reasoned
   `override_open_duplicate` review links the request to the current open
   holding only when its active location and condition are reconfirmed, without
   creating a second holding or stock number; acquisition, odometer, price, or
   notes on a link request are rejected because that branch cannot apply them;
7. rejects confirmed or manual facts that conflict with non-null authoritative
   vehicle facts, including the open-unit linkage branch, avoiding a silent
   facts override;
8. creates the holding episode and permanent stock allocation in the same
   transaction, or links the existing open holding; both branches fill only
   previously-null vehicle facts from the user's confirmed values before the
   receipt and audit return and advance the fact version whenever they fill a
   value; and
9. records forced-RLS, append-only request and link receipts plus audit and
   transactional outbox evidence before marking the decode request consumed.

One decode request has one immutable intake/link receipt and can be consumed
once. Independently reviewed requests may reference the same current open
holding, but they receive distinct request receipts and return its original
stock number; no second allocation occurs. Exact retries return the original
identifiers. A changed payload, second idempotency key, stale version,
cross-workspace result, late duplicate review, or mutation of consumed history
fails closed.

The completion migration also adds a separate manual-facts command. It requires
an authoritative terminal VIN job in `dead_letter`, the displayed request
version, explicit fact confirmation, model year/make/model, an operator reason,
active location/condition/stock configuration, and the same duplicate decision
rules. It preserves the terminal provider failure and links the manual receipt
to that exact job and decode request.

Both intake results expose `linkedExistingOpenUnit`. `false` means the command
allocated a new holding and stock number; `true` means it linked the already-open
holding and returned its permanent stock number. After either path consumes the
decode request, the safe status projection reports terminal `consumed` and
disables retry/review without rewriting the nested durable job status or failure
evidence.

## API integration contract

The application service is implemented in
`packages/application/src/vin-inventory-intake-api.ts`. The web PostgREST
contract exposes the confirmed and failed-decode RPCs, constructs
`VinInventoryIntakeApplicationService`, and routes confirmed submission through
`createFromConfirmedDecode` and terminal manual submission through
`createFromDeadLetterManualFacts`. The inventory-create route no longer calls
the revoked `create_inventory_unit` primitive.

The request body is strict and tenant-neutral:

- `confirmation.accepted` must be literal `true`;
- `confirmation.vinDecodeResultId` and `expectedRequestVersion` bind the UI
  confirmation to the state it displayed;
- `vinDecodeRequestId` identifies the workspace-verified decode aggregate being
  consumed by `POST /api/v1/inventory-units`;
- `vehicleFacts` contains the user's edited, normalized values; and
- `locationId` and `conditionKey` identify active workspace configuration;
- `inventory` contains acquisition date, odometer, exact minor-unit price,
  ISO currency, and public notes for a newly allocated holding; every mutable
  inventory detail must be null when an open-unit review links existing stock;
  and
- `POST /api/v1/vin/decode/{requestId}/manual-intake` is the only manual-facts
  path and remains unavailable until the authoritative job is dead-lettered.

Workspace authority, actor identity, duplicate decisions, VIN, stock value, and
consumption state are never accepted from arbitrary body fields.

## Compatibility and rollback

These are additive schema migrations with a deliberate API privilege cutover.
Deploy the route/application integration in the same release as the migrations;
an older web build will receive `permission denied for function
create_inventory_unit` after migration. Rollback is forward-only: keep intake,
decode, review, link, manual-facts, allocation, audit, and outbox history;
deploy a corrective migration and compatible route rather than deleting or
rewriting receipts.

The 40-assertion base suite covers the privilege cutover, explicit
confirmation, stale state, result binding, replay, second-key consumption,
workspace isolation, fact application, audit/outbox linkage, immutable history,
historical reacquisition, open-link conflict/detail rejection, compatible
null-fact fill with version fencing, and no-burn stock behavior. The
44-assertion completion
suite adds required location/condition configuration, dead-letter-only manual
facts, workspace/permission/AAL denial, terminal consumed projection, manual
fact-conflict rejection, immutable link receipts, and the independently reviewed
two-request/one-open-unit/one-stock invariant. SQL parsing, static gates,
TypeScript, focused unit tests, and phone/desktop E2E can run locally. A real
local or staging Postgres run remains required before claiming runtime RLS,
trigger, locking, and concurrency acceptance.
