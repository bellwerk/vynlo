# Future private module — Drivven payment servicing and collections

**Status:** Deferred and disabled  
**Ownership:** Drivven private configuration on an optional Vynlo servicing module

This module must not define Vynlo's standard dealership product.

## Provider and matching

- Read existing GoCardless customers, mandates, and payment events.
- Use webhooks plus a daily reconciliation.
- Candidate matching keys: stock number and customer name.
- Ambiguous matches require human confirmation.
- Retries are manually initiated in GoCardless, not by Vynlo.
- Provider event IDs and idempotency prevent duplicate processing.

## Live schedule

The immutable original RTB schedule remains unchanged. A separate live servicing view records:

```text
scheduled installment
provider attempts/events
paid/failed status
manual credits
e-transfer matches
late-fee events
waivers
notes and tasks
```

## Late-fee rule

Candidate Drivven policy:

- 50 CAD flat fee.
- One fee per scheduled installment, never one per retry attempt.
- Created on a confirmed GoCardless failure.
- No grace period.
- No tax and no additional interest under the candidate rule.
- Due with the final contract settlement.
- Admin may waive with reason; the original event remains.
- Production use requires final legal/accounting approval and approved wording.

## Partial and extra payments

- A partial/manual payment is a separate credit and does not rewrite the signed schedule.
- Extra principal and early payoff require admin-approved calculations.
- The first servicing release does not automatically modify GoCardless.

## Gmail/e-transfer matching

Mailbox: `info@autobs.ca`.

- Read-only least-privilege access.
- Extract sender, amount, date, message/reference.
- Suggest potential matches.
- Sales/office or admin confirms.
- Store a provider link, not unnecessary full message content.
- Never silently apply money.

## Daily report

At 10:00 America/Toronto, send an English report to:

```text
info@autobs.ca
info@drivven.ca
```

Include yesterday's failures and all unresolved overdue items, grouped by date and client, with secure Vynlo links and suggested actions.

## Collection workflow

Candidate task escalation:

```text
1 missed installment:
reminder and warning task

2:
legal-warning document/task

3:
manager/legal repossession review
```

Vynlo never automatically repossesses a vehicle. Every notice, contact, decision, and approval is audited. Legal wording and process remain activation-gated.

## Data and security

- Payment and mailbox credentials are encrypted per workspace.
- Webhook signatures are verified.
- Sensitive provider data is minimized in logs.
- Financial changes require reason and audit.
- Cross-workspace matching or event visibility is prohibited.
