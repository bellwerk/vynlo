# Tax-pack engine

Vynlo owns the tax-pack runtime and may maintain approved jurisdiction packs. Tax rules are not embedded in templates or tenant formulas.

A pack declares jurisdiction, transaction contexts, effective dates, currencies, rates/source metadata, taxable-base rules, classifications, trade-in eligibility/treatment, exemptions, rounding, output schema, golden tests, and approvals.

Runtime input includes workspace/legal jurisdiction, date/context, party tax status, vehicle facts, line items, trade-in facts, and approved overrides. Output includes subtotals, tax amounts, adjustments, warnings, exact versions, and immutable snapshot.

A pack cannot infer jurisdiction from free-text address. Missing/expired pack blocks tax-dependent official documents. Overrides require permission/reason and are snapshotted. Tenant formulas may consume but not redefine active tax outputs.

`tax-ca-qc` is the first candidate pack and remains activation-gated by professional approval and golden cases.
