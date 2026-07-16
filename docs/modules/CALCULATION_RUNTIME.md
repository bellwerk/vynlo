# Safe calculation runtime

Vynlo ships a deterministic runtime, not preset contract formulas. Definitions belong to a tenant or approved pack.

MVP operations:

```text
constant, field reference
add/subtract/multiply/divide
percentage, min/max/absolute
round/floor/ceiling
conditional/comparison/coalesce
sum repeating rows
date add/difference
approved tax-pack invocation
optional generic amortized-payment primitive
```

Definitions are typed JSON ASTs validated against `schemas/calculation.schema.json`. Arbitrary code is prohibited.

Use exact decimal arithmetic. Money declares currency/rounding. Division by zero, missing fields, overflow, cycle, unsupported operation, excessive depth/nodes/rows/time fail safely.

Lifecycle: `draft -> test_passed -> approved -> active -> retired`. Activated versions are immutable. Every run stores version, input, output, components, rounding, engine version, checksum. Activation requires approved exact fixtures.
