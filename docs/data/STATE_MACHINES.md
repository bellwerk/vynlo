# State machines

Vynlo stores workspace-defined state keys and maps them to neutral canonical categories:

```text
draft | active | pending | closed | archived
```

A state also declares flags such as publishable, sellable, requires review, terminal, or blocks another deal. The workflow-version file is the authoritative transition graph.

## Standard retail starter inventory

```text
draft -> incomplete
draft/incomplete -> in_preparation
in_preparation -> ready
ready -> listed
listed -> ready
ready/listed -> pending_sale
pending_sale -> ready
pending_sale -> sold
ready/listed -> wholesale
draft/incomplete/in_preparation/ready -> archived
```

`sold`, `wholesale`, and `archived` are terminal in starter version 1.0. A tenant needing return/reacquisition installs another workflow or opens a new inventory holding episode. Drivven's special return/repossessed behavior is private.

## Standard lead

```text
new -> contacted
contacted -> appointment
contacted/appointment -> qualified
qualified -> converted
any open state -> lost with reason
```

`converted` and `lost` are terminal in starter version 1.0.

## Standard retail deal

```text
draft -> preparing
preparing -> awaiting_customer
preparing -> awaiting_lender
awaiting_customer -> approved
awaiting_lender -> approved when lender approval is recorded
approved -> ready_for_delivery when documents are ready
ready_for_delivery -> completed when completion requirements pass
any eligible non-completed state -> cancelled with reason
```

## Document lifecycle

```text
draft
-> preview_requested
-> preview_generated / preview_failed

ready_for_official
-> generating
-> generated / generation_failed
-> signed_received when configured
-> completed/active when configured

generated or signed_received
-> void

new official document
-> supersedes prior document
```

Preview is unnumbered. Official number allocation and official document record occur transactionally before asynchronous render. Failed render keeps the allocation and retries.

## One-time payment transaction

```text
draft -> recorded -> settled
recorded -> cancelled
settled -> reversed by linked reversal
settled -> partially_refunded/refunded by linked refund transactions
```

A settled record is not edited.

## External finance application

```text
preparing
-> submitted
-> additional_information_required
-> conditionally_approved / approved / declined
approved/conditionally_approved
-> funded / customer_declined / expired / cancelled
```

Exact starter transitions are versioned configuration.

## Job

```text
queued -> running -> succeeded
running -> retry_wait -> running
running/retry_wait -> dead_letter
queued/retry_wait -> cancelled when safe
```

## Configuration artifact

```text
draft -> validated -> test_passed -> approved -> active -> retired
```

Activation is a privileged command. Active versions are immutable.

## Transition command rules

Every transition command:

1. resolves the entity and exact workflow version;
2. checks workspace/member/permission and step-up;
3. checks expected aggregate version;
4. verifies source state, required fields, guards, and reason;
5. updates instance/entity;
6. appends workflow/audit event;
7. appends outbox effects;
8. commits atomically.

Side-effect failure never reverses the committed state; it appears as a job/sync problem and follows declared compensation or review behavior.
