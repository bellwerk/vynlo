# @vynlo/tax

Tenant-neutral tax-pack compiler, selector, executor, and calculation-port
adapter for `M4-TAX-AC-001..005`. It runs inside the modular monolith and makes
no address, tenant, provider, or external-service decision.

## Selection and activation

`compileTaxPack` validates exact pack keys, version/effective dates, HTTPS source
metadata, source references, implemented taxable-base and per-tax rounding
semantics, trade-in policy, lifecycle state, approvals, and immutable checksum.

`selectTaxPack` requires explicit jurisdiction, transaction context, date,
currency, and usage. No address field exists, and extra selector fields fail
closed. Preview may use a non-retired candidate. Official selection requires an
exact active version with approval references; missing, expired, unsupported,
retired, unapproved, or ambiguous configuration is unavailable.

## Exact execution and evidence

`executeTaxCalculation` consumes integer minor units and uses Decimal.js for
rates and intermediate values. The current bounded rule vocabulary supports an
explicit eligible taxable-consideration base, per-tax rounding, and conditional
eligible-trade-in credit. Explicitly classified discounts are nonnegative
`taxable_discounts_minor` and `non_taxable_discounts_minor` buckets, separate
from positive fee buckets. The derived taxable base is
`max(vehicle + taxable fees - taxable discounts - eligible trade credit, 0)`;
non-taxable consideration is
`max(non-taxable fees - non-taxable discounts, 0)`. Existing callers may omit
both discount fields. A trade credit requires recorded eligibility or a dedicated
override decision with immutable `tax.override` permission, recent strong
authentication, reason, and review reference. Lien payoff, discount category,
and free-text inference are not runtime tax decisions.

Each result includes normalized input, all tax outputs, override evidence, the
exact compiled pack (including rates, sources, and rounding), pack and engine
versions, and deterministic checksums. `createCalculationTaxPort` preserves that
version evidence when tax is invoked from `@vynlo/calculations`.

`runTaxGoldenCases` executes complete expected-output assertions from parsed
golden JSON. `src/runtime.test.ts` implements `T-TAX-001` and `T-TAX-002` and
loads the committed CA-QC golden files rather than duplicating their expected
results in the runner. The taxable-discount candidate fixture proves the same
exact projection used by deal-bound runtime evidence without approving a tax
treatment.

## CA-QC candidate boundary

`packs/tax/ca-qc` remains a **draft candidate**. Its 5% GST/TPS and 9.975%
QST/TVQ fixtures, including explicit eligible trade-in treatment, are software
implementation evidence only. Passing fixtures does not create legal,
accounting, tax-professional, or production approval, and never activates the
pack.
