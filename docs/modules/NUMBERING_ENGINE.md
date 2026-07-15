# Numbering engine

Vynlo owns transactional allocation and history; a pack owns format and scope.

## Definition

A versioned numbering definition declares:

```text
key and labels
scope: workspace, legal entity, location, document type, or combination
prefix/suffix
numeric width
starting value
increment
reset: never, yearly, monthly, or configured period
timezone used for period boundary
format pattern
import/reservation rules
allocation event
reuse policy
```

MVP supports numeric sequences plus a tenant-defined deterministic suffix strategy validated by a pack. Arbitrary code is prohibited.

## Allocation

Allocation occurs inside the same database transaction that creates the authoritative entity/official document.

```text
lock sequence row
validate active definition/version/scope
select next unused value
insert permanent allocation
create/link entity
write audit and outbox
commit
```

Unique constraints protect `(workspace_id, definition_version_id, scope_key, period_key, sequence_value, suffix)` and final formatted value.

## Idempotency

The allocation command accepts an idempotency key. Repeating the same command returns the existing allocation/entity. Rendering or provider retries never allocate again.

## No reuse

When `reuse: never`:

- abandoned, void, cancelled, failed-render, or imported numbers remain consumed;
- administrators cannot delete or return a value to the pool;
- corrections receive a new value and lineage;
- gaps are acceptable and auditable.

## Imports

An authorized import may reserve an existing number after uniqueness and format validation. The sequence advances when required to avoid future collision. Every import records source, actor, batch, and reason.

## Concurrency tests

At least 100 parallel allocation attempts must produce 100 unique values with no gaps caused by transaction failure before allocation commit. Failures after commit preserve the number and retry subsequent side effects.
