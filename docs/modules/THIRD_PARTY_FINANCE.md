# Third-party finance tracking

Purpose: record financing arranged through an external lender while the lender remains the source of underwriting, terms, calculation, and repayment servicing.

Fields include lender, applicant/deal, requested amount, submitted date, lender reference, status, approved amount, returned rate/term, conditions, required documents, approval expiry, customer acceptance, funding status/date/reference, notes, and attachments.

Starter statuses:

```text
preparing
submitted
additional_information_required
conditionally_approved
approved
declined
customer_declined
funded
cancelled
expired
```

Excluded: credit-bureau pulls, lender-network submission, independent payment calculation presented as lender terms, repayment schedules, late fees, collections, and payoff servicing.
