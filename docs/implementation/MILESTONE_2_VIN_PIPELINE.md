# Milestone 2 durable VIN pipeline

**Status:** Source implementation and static verification complete; local
Postgres/pgTAP runtime acceptance remains open because Docker is unavailable

**Migration:** `supabase/migrations/20260716170000_durable_vin_decode.sql`

**Database test:** `supabase/tests/008_durable_vin_decode.test.sql`

## Scope and traceability

This increment implements `VYN-INV-001`, `VYN-JOB-001`, `VYN-TEN-001`,
`VYN-SEC-001`, `VYN-AUD-001`, and `VYN-API-001` for typed or pasted VIN intake.
It covers the Milestone 2 requirements for provider decoding, immutable raw
results, mapped suggestions, visible retry state, duplicate discovery,
reasoned review, workspace isolation, audit, and outbox delivery.

The canonical VIN acceptance identifiers are:

| Acceptance ID | Verifiable outcome |
| --- | --- |
| `M2-INV-AC-001` | Typed or pasted VIN input is normalized, validated, and enqueued once through the durable workspace-scoped decode command. |
| `M2-INV-AC-002` | Provider raw results remain immutable and private while mapped suggestions or explicitly confirmed manual facts bind to a versioned intake receipt. |
| `M2-INV-AC-003` | Duplicate discovery and reasoned manager review are append-only, workspace-scoped, step-up protected where required, and never create a second open holding episode. |
| `M2-INV-AC-004` | Classified failures use bounded retry/dead-letter state; only an authoritative dead letter enables the audited manual-facts fallback. |

The provider adapter uses the public
[NHTSA vPIC API](https://vpic.nhtsa.dot.gov/api/Home/Index). It validates the
17-character VIN, enforces HTTPS outside local development, rejects redirects,
bounds time and response size, classifies provider failures, and never exposes
the raw response through the browser API.

## Durable flow

1. `POST /api/v1/vin/decode` validates and normalizes the VIN, then commits a
   decode request, durable job, audit event, outbox event, and idempotency
   receipt. It does not allocate stock or create inventory.
2. The worker claims `inventory.vin_decode` with a lease token and calls the
   NHTSA adapter.
3. `app.complete_vin_decode_request` verifies the current worker and lease,
   then stores the immutable raw response and bounded mapped suggestions in the
   same transaction as duplicate candidates, audit, and outbox evidence.
4. `GET /api/v1/vin/decode/{requestId}` exposes safe suggestions, provider
   provenance, an opaque raw-result reference, retry telemetry, and duplicate
   review state. After inventory consumption the request status is terminal
   `consumed` with retry and review disabled, while the nested job retains its
   actual `succeeded` or `dead_letter` state and safe failure history. The route
   never returns the raw provider payload.
5. A visible dead-letter request can be retried with an operator reason. A
   duplicate decision is append-only, reasoned, audited, idempotent, and
   workspace-scoped. Overriding open inventory additionally requires
   `inventory.duplicate_override` and strong authentication within 15 minutes.
6. The dedicated terminal manual-facts route requires the authoritative
   dead-letter job, displayed request version, explicit paperwork confirmation,
   active location/condition/stock configuration, and an operator reason. Its
   immutable receipt remains linked to the failed request and job; see
   [confirmed and manual inventory intake](MILESTONE_2_VIN_INVENTORY_INTAKE.md).

## Safety and compatibility

- The physical `vehicles` record remains separate from each inventory holding
  episode. Provider suggestions do not silently overwrite authoritative facts.
- Vehicle facts use tenant-neutral columns including `trim_name`; reserved or
  tenant-specific names are not introduced.
- Raw results, duplicate candidates, and reviews are append-only. Exposed tables
  use forced RLS and workspace-composite references.
- Provider and database failures are classified for bounded durable retry and
  visible dead-letter review. Credentials stay in server-only runtime
  configuration.
- API commands derive workspace context from authenticated headers; a request
  body cannot supply workspace authority.

Rollback is forward-only: disable new decode requests or switch the configured
adapter after review, allow claimed jobs to settle, and preserve request,
result, review, audit, outbox, and job history.

## Verification

The focused application, provider-adapter, worker-handler, repository, and API
route suites pass. The SQL migration and 58-assertion pgTAP suite parse, and the
central static Supabase gate validates forced RLS, command presence, permission
keys, and test structure. A real local/staging database run remains required
before claiming runtime migration, lease, RLS, or concurrency acceptance.
