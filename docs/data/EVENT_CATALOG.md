# Domain and audit event catalogue

Events use stable names and versioned payload schemas. Domain events drive internal behavior; audit events record human/system accountability. Do not publish raw PII unnecessarily.

## Identity/configuration

```text
workspace.created
auth.invitation.created
auth.invitation.accepted
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
vehicle.facts_overridden
inventory_unit.created
inventory_unit.intake_confirmed
inventory_unit.vin_link_confirmed
inventory_unit.manual_intake_confirmed
inventory_unit.manual_vin_link_confirmed
inventory_unit.updated
inventory_unit.location_transferred
inventory_unit.transitioned
inventory.vin_decode_requested
inventory.vin_decode_succeeded
inventory.vin_decode_retry_requested
inventory.vin_duplicate_reviewed
inventory_saved_view.created
inventory_saved_view.updated
inventory_saved_view.archived
stock_number.allocated
inventory_cost.posted
inventory_cost.reversed
media.upload_intent_created
media.upload_completed
media.upload_verification_queued
media.upload_verification_retry_requested
media.upload_rejected
media.processing_queued
media.processing_started
media.processing_succeeded
media.processing_failed
media.processing_retry_pending
media.reprocessing_queued
media.caption_updated
media.archived
media.legal_upload_intent_created
media.legal_original_verification_queued
media.legal_original_verification_retry_requested
media.legal_original_verification_rejected
media.legal_original_recorded
media.legal_original_quarantine_cleanup_queued
media.legal_original_quarantine_cleanup_completed
media.download_authorized
media.retention_held
media.retention_released
media.quarantine_cleanup_queued
media.quarantine_deleted
media.quarantine_not_found
media.raw_retention_queued
media.raw_deleted
media.cover_changed
media.collection_reordered
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
document.preview_job_queued
document.preview_generated
document.preview_failed
document.preview_artifact_recorded
document_preview.download_authorized
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
