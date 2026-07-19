# Candidate tax pack: Canada / Québec

**Pack key:** `tax-ca-qc`  
**Version:** 1.0.0
**Activation status:** Draft; production activation requires accountant/legal approval and signed golden tests.

This pack models a conventional Québec vehicle-sale context. It is not a
universal contract formula and must not contain tenant-specific revenue splits,
brokerage, repayment, or collection logic.

## Candidate defaults

- GST/TPS rate: 5%.
- QST/TVQ rate: 9.975%.
- QST is calculated on the price excluding GST.
- In a qualifying dealer trade-in transaction, an eligible trade-in credit may reduce the taxable consideration according to the active trade-in rule and recorded eligibility inputs.
- A discount affects a tax bucket only when the deal line explicitly classifies it; the runtime does not infer classification from its label, source, or tenant.
- Taxes are rounded to the nearest cent using half-up rounding on the tax base defined by the active rule.

## Activation requirements

1. Confirm transaction contexts and inputs with a Québec accountant/legal reviewer.
2. Confirm eligible trade-in conditions and the treatment of liens/payoffs.
3. Confirm rounding against the dealership's accounting records.
4. Approve every golden case.
5. Record source and approval references in Vynlo.
6. Activate a specific immutable version; never silently change an active version.

See `SOURCE_NOTES.md`. 
