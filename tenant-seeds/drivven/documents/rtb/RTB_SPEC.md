# Drivven RTB document specification

## Ownership and boundary

This document type is exclusive Drivven tenant configuration. Vynlo owns only the generic document, formula-runtime, tax-pack, storage, workflow, and audit machinery.

## Rendering lifecycle

```text
Draft deal
→ watermarked preview (no number)
→ full initial payment settled
→ finalization validation
→ permanent RTB number allocated
→ official PDF rendered
→ printed and physically signed
→ user marks signed
→ signed scan uploaded
→ delivery permitted
```

Rendering retries use the same document/number through an idempotency key. Changed official data creates a new number and superseding record.

## Page/section field catalogue

The final legal page layout remains an activation input, but engineering must support every field group below.

| Section | Required field groups | Source |
|---|---|---|
| Header | RTB number, contract/delivery/signature dates, template/formula/tax versions | document/version records |
| Seller | exact legal entity, operating brand, registered address, tax/permit identifiers | legal entity |
| Branch | Montreal or Sherbrooke address and phone | location |
| Customer | name, address, phone, email, date of birth, driver licence | party/identifiers |
| References | up to two names, relationships, phones, emails | customer references |
| Vehicle | stock, VIN, year, make, model, trim, colour, odometer, plate, accessories | vehicle/inventory |
| Disclosures | condition, rebuilt/VGA, statutory warranty category | inventory/deal |
| Price and fees | vehicle cash price and repeating approved fee rows | deal line items |
| Initial payment | total, 70% brokerage base, exact capital remainder | private formula snapshot |
| Trade-in | eligible credit, lien/payoff, eligibility confirmation | trade-in/tax snapshot |
| Taxes | vehicle TPS/TVQ and brokerage TPS/TVQ | tax snapshot |
| Financing | net capital, nominal annual rate, duration, frequency, count, regular/final payment, first date, total interest/obligation | formula snapshot |
| Insurance | responsibility, proof, coverage/deductible if used | deal custom fields |
| Consents | tracking, privacy, insurance, warranty, rebuilt-title acknowledgements | deal/document data |
| Legal clauses | final approved French wording and required statutory notices | immutable template source |
| Signatures | customer/seller signature and page/section initials | printed document |
| Footer | page count, template/formula/tax versions, document number | version metadata |

## Formula display

The main financial table must visibly show:

```text
Versement initial total
Frais de courtage
Acompte appliqué au capital
TPS/TVQ applicables aux frais de courtage
Montant net financé
```

The final approved brokerage annex is a dedicated page in the same PDF. No full amortization schedule is printed; it remains available in Vynlo.

## Security and immutability

- Driver-licence and personal fields are restricted by permission and masked where appropriate.
- Official PDF, signed scans, source template, field schema, calculations, versions, and checksums are immutable.
- Signed scans are separate versions; they never replace generated originals.
- Drive links are never public.
- A signed document may be voided/superseded only by authorized admin with step-up authentication and reason.

## Activation rule

The included HTML file is a rendering scaffold and remains watermarked. Engineering may use it for field coverage and visual testing. Customer-facing activation is forbidden until final approved French source is installed as a new immutable template version.
