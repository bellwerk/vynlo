# Drivven RTB formula specification

**Formula key:** `drivven-rtb`  
**Version:** 1.0.0 candidate  
**Owner:** Drivven workspace configuration  
**Platform dependency:** Vynlo safe calculation runtime and active tax pack  
**Production status:** Disabled until approval records and golden fixtures are signed

This formula is not part of Vynlo's standard product and must never be copied into platform defaults.

## Preconditions

- Currency is CAD.
- Signature date is the official calculation/accrual date.
- The initial payment is fully settled.
- Payment frequency is weekly or biweekly.
- Duration is one of 12, 18, 24, 30, 36, or 48 months.
- Tax-dependent generation has an active approved Québec tax-pack version.
- Any trade-in credit used for tax purposes has explicit eligibility confirmation.
- Fee rows use admin-approved categories and tax/financing flags.

## Initial-payment split

All input money is integer minor units.

```text
brokerage_fee_base =
  round_half_up(initial_payment_total × 0.70)

capital_down_payment =
  initial_payment_total − brokerage_fee_base
```

The second expression uses the exact remainder so both portions always equal the received initial payment.

The brokerage base is considered paid from the initial payment. Its applicable tax is calculated through the active tax pack and added to financed capital under this tenant formula. No separate invoice is automatically generated.

## Financed-capital order

```text
vehicle_price_after_capital_and_trade_in =
  max(
    vehicle_cash_price
    − capital_down_payment
    − eligible_trade_in_credit,
    0
  )

taxable_financed_fees =
  sum(fee.amount where fee.taxable and fee.financed)

non_taxable_financed_fees =
  sum(fee.amount where not fee.taxable and fee.financed)

vehicle_taxable_consideration =
  vehicle_price_after_capital_and_trade_in
  + taxable_financed_fees

vehicle GST/QST =
  active Québec tax-pack result for vehicle_taxable_consideration

brokerage GST/QST =
  active Québec tax-pack result for brokerage_fee_base

net_capital_financed =
  vehicle_price_after_capital_and_trade_in
  + taxable_financed_fees
  + vehicle GST
  + vehicle QST
  + non_taxable_financed_fees
  + trade_in_lien_payoff
  + brokerage GST
  + brokerage QST
```

The trade-in allowance and lien payoff are distinct:
- eligible allowance may reduce the taxable consideration according to the approved tax pack;
- lien/payoff is added afterward as financed amount under the candidate Drivven rule;
- no rule infers tax eligibility merely because a trade-in exists.

This order is activation-gated by accountant/legal approval.

## Payment periods

```text
weekly:
  periods_per_year = 52
  period_days = 7

biweekly:
  periods_per_year = 26
  period_days = 14

number_of_payments =
  duration_months × periods_per_year ÷ 12

first_payment_date =
  signature_date + period_days
```

First payment is calculated and read-only in the pilot.

## Amortized payment

The annual nominal rate is stored in basis points:

```text
19.99% = 1999 bps
periodic_rate = annual_rate_bps ÷ 10,000 ÷ periods_per_year
```

For non-zero interest:

```text
regular_payment =
  P × r ÷ (1 − (1 + r)^(-n))
```

For zero interest:

```text
regular_payment = P ÷ n
```

Regular payment is rounded half-up to the nearest cent. Schedule rows apply each payment first to accrued interest and then to principal.

For each row:

```text
interest =
  round_half_up(opening_balance × periodic_rate)

principal =
  payment − interest

remaining_balance =
  opening_balance − principal
```

The final row is adjusted to exactly clear the remaining principal. The final payment may therefore differ slightly from the regular payment.

## Immutable original schedule

Official generation stores an immutable schedule with:

```text
payment number
due date
payment amount
principal portion
interest portion
remaining principal
```

Late fees, provider failures, partial payments, extra payments, and collections do not rewrite this schedule. Those become separate live servicing events in a future Drivven module.

## Signing-date rule

Preview PDFs have no official number and do not establish a schedule.

When finalizing:
1. Sales confirms intended signature date.
2. Vynlo generates the official number, formula snapshot, and PDF.
3. The customer must sign that date.
4. If signing occurs on a different date, the unsigned document is voided/superseded and a new official number and schedule are generated.

## Candidate fixtures

This seed directory contains five exact candidate cases:
- weekly, no trade-in;
- biweekly with eligible trade-in;
- zero interest and odd-cent initial payment;
- taxable/non-taxable fees plus lien exceeding allowance;
- final rounding adjustment.

They enable implementation and automated testing but remain non-production until the Drivven administrator and designated accounting reviewer approve the exact outputs.

## Prohibited behavior

- No native JavaScript or arbitrary code in the formula.
- No binary floating-point money calculations.
- No per-deal override of the 70/30 split.
- No sales override of tax rules, first payment date, or schedule rows.
- No mutation of an activated formula version.
- No official generation when tax/formula/template approvals are missing.
