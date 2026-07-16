# @vynlo/inventory

Inventory domain ownership boundary for physical vehicles, inventory holding
episodes, prices, aging, and derived gross.

This package is an ownership boundary inside the modular monolith, not an
independently deployed service. Its domain functions are pure; application and
database commands derive the authoritative workspace and repeat concurrency,
authorization, audit, and tenant-isolation checks transactionally.

## Milestone 2 contracts

- Manual keyboard/paste VIN normalization excludes `I`, `O`, and `Q`; camera
  VIN scanning remains out of scope.
- A physical vehicle is distinct from each inventory holding episode. Canonical
  `draft`, `active`, and `pending` episodes are open; a closed or archived
  episode may be followed by a new holding for the same vehicle.
- Prices parse as non-negative Postgres-bigint minor units plus uppercase ISO
  currency. Domain calculations use `bigint`, never binary floating point.
- Public condition, location, price, and note updates require the exact current
  version. Location changes also require a reason. Internal notes use separate
  read/update permissions and are omitted from ordinary projections.
- Days in stock are elapsed calendar days from the workspace-local acquisition
  date and stop at the workspace-local closure date.
- Estimated gross uses expected sale price, falling back to advertised price,
  minus effective posted costs after posted reversals. With neither price it is
  `null`; it is not realized gross, tax, financing, or a tenant contract formula.

## Compatibility notes

The Milestone 2 module is additive and preserves the existing first vertical
slice exports. Transport adapters must encode `bigint` minor units as canonical
decimal strings (or proven safe JSON integers) and must not place a workspace ID
or internal notes into the ordinary public update contract. Persistence remains
authoritative for row locks, unique open holdings, expected versions, RLS,
immutable cost entries, audit records, and outbox writes.
