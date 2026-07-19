# Milestone 2 inventory cost and search slice

**Status:** Source implementation and static verification complete; local
Postgres/pgTAP runtime acceptance remains open because Docker is unavailable

**Migrations:** `supabase/migrations/20260716180000_inventory_cost_search.sql`,
`supabase/migrations/20260716310000_m2_actor_idempotency_hardening.sql`

**Database tests:** `supabase/tests/010_inventory_cost_search.test.sql`,
`supabase/tests/021_m2_actor_idempotency_hardening.test.sql`

## Scope and traceability

This increment implements `VYN-COST-001`, `VYN-SEARCH-001`, `VYN-INV-001`,
`VYN-TEN-001`, `VYN-AUD-001`, and `VYN-API-001` for inventory costs, exact
metrics, bounded search, and user saved views. The related acceptance coverage
is `M2-INV-AC-007`, `M2-INV-AC-008`, `M2-INV-AC-009`, and
`M2-INV-AC-011`.

## Authoritative cost model

- Cost categories are localized, workspace-owned, versioned configuration.
  Active and retired definitions are immutable; corrections use a new version.
- Cost entries are append-only integer minor units with an ISO currency code.
  A correction appends one linked reversal; it never rewrites the original.
- Posted/reversed state is derived from immutable reversal links in the
  RLS-invoker history view; no mutable status column can drift from the ledger.
- Optional cost evidence must be a ready, undeleted preserved file owned by the
  same workspace and inventory aggregate. Cross-workspace, wrong-owner,
  preview/raw, deleted, and unverified files fail closed.
- Posting locks the inventory aggregate, checks its expected version, and
  advances the inventory and pinned workflow versions together.
- Reversal additionally requires `costs.reverse` and recent strong
  authentication, and its effective date cannot precede the original cost.
  Both commands commit audit and outbox evidence atomically and replay the
  original evidence for a matching idempotency key.
- Cost post and reversal logical keys are scoped by workspace, actor, and
  command kind in the advisory lock, replay predicate, and composite unique
  index. The raw key is preserved, so same-actor pre-cutover entries remain
  compatible; a second permitted user cannot replay or conflict-poison the
  first user's result, including with a digest-shaped key.
- The metrics projection stores exact posted cost and estimated gross. API,
  audit, and outbox money values remain decimal strings so values beyond
  JavaScript's safe integer range do not lose precision.

## Search and saved views

`app.search_inventory_units` uses a workspace-scoped full-text/trigram document,
bounded filters, a deterministic rank/update/ID cursor, and a page limit of 100.
Inventory readers who lack `costs.read` receive `null` cost and gross fields,
even when they can see the inventory record.

Saved views accept only allowlisted filters, sort keys, columns, layout, density,
and share scope. They cannot contain SQL or executable tenant code. A private
view is owner-scoped; a workspace-shared view additionally requires
`inventory.update`. Writes use version checks, immutable receipts, and audit
evidence.

## Operations and rollback

Cost and saved-view writes have no direct provider side effects. Downstream work
starts from committed outbox records. Projection helpers are not browser
callable, all exposed tables use forced RLS, and browser DML is denied in favor
of fixed application commands.

Rollback is forward-only: stop new callers, retain the ledger and receipts, and
repair configuration or projections with reviewed forward changes. Never delete
or rewrite posted cost, reversal, audit, or outbox history.

The application/API suites, OpenAPI lint, SQL parsing, static Supabase gate, and
65-assertion cost/search plus 45-assertion actor-hardening pgTAP source suites
pass. A real local/staging database run remains required before claiming
runtime RLS, trigger, or contention acceptance.
