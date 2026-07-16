# Domain and audit event catalogue

Events use stable names and versioned payload schemas. Domain events drive internal behavior; audit events record human/system accountability. Do not publish raw PII unnecessarily.

## Identity/configuration

```text
workspace.created
membership.invited
membership.activated
membership.deactivated
membership.roles_changed
integration.connected
integration.credentials_changed
pack.installed
artifact.approved
artifact.activated
artifact.retired
```

## Inventory/media/listings

```text
vehicle.created
vehicle.facts_corrected
inventory_unit.created
inventory_unit.updated
inventory_unit.transitioned
stock_number.allocated
cost_entry.posted
cost_entry.reversed
media.uploaded
media.processing_succeeded
media.processing_failed
media.cover_changed
media.reordered
listing.publish_requested
listing.synced
listing.sync_failed
listing.drift_detected
listing.conflict_resolved
```

## CRM/deals/finance/money

```text
lead.created
lead.assigned
lead.transitioned
lead.converted
activity.recorded
task.created
task.completed
appointment.created
deal.created
deal.transitioned
trade_in.recorded
finance_application.created
finance_application.transitioned
payment_transaction.recorded
payment_transaction.settled
payment_transaction.reversed
payment_transaction.refunded
```

## Documents/calculations/tax

```text
document.preview_requested
document.preview_generated
document.official_requested
document.number_allocated
document.generated
document.generation_failed
document.signed_file_uploaded
document.marked_signed
document.voided
document.superseded
calculation.executed
tax_calculation.executed
export.requested
export.generated
```

## Jobs/operations

```text
job.queued
job.started
job.retry_scheduled
job.succeeded
job.dead_lettered
job.cancelled
migration.batch_started
migration.row_reviewed
migration.batch_committed
migration.batch_failed
```

Every event schema specifies workspace, actor/system identity, aggregate, aggregate version, occurred time, correlation/causation IDs, payload version, and minimized payload. Consumers are idempotent by event ID.
