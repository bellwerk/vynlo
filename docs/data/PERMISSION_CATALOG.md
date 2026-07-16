# Permission catalogue

Permission keys are stable machine contracts. Labels are localized. A pack may use `namespace.*` shorthand only during installation; the installer expands it to the exact compatible keys and stores explicit grants.

## Workspace/configuration

```text
workspace.read
workspace.manage
users.read
users.manage
roles.manage
configuration.read
configuration.manage
approvals.read
approvals.create
integrations.read
integrations.manage
jobs.read
jobs.manage
audit.read
```

## Inventory/media/listings

```text
inventory.read
inventory.create
inventory.update
inventory.transition
inventory.archive
inventory.duplicate_override
inventory.facts_override
inventory.read_internal
inventory.update_internal

costs.read
costs.create
costs.reverse

media.read
media.create
media.update
media.archive

listings.read
listings.publish
listings.unpublish
listings.reconcile
```

## CRM and deals

```text
crm.read
crm.create
crm.update
crm.assign

deals.read
deals.create
deals.update
deals.transition
deals.cancel
deals.close

finance_applications.read
finance_applications.create
finance_applications.update
```

## Money

```text
payments.read
payments.record
payments.settle
payments.reverse
payments.refund
```

## Documents/configuration

```text
documents.read
documents.preview
documents.generate_approved
documents.print
documents.upload_signed
documents.mark_signed
documents.void
documents.void_signed
documents.supersede

formula.read
formula.activate
tax.read
tax.activate
template.read
template.activate
workflow.read
workflow.activate
numbering.read
numbering.activate
```

## Reports/exports

```text
reports.read
exports.read
exports.run
exports.run_sensitive
```

## Restricted data

```text
identifiers.read_restricted
identifiers.manage
files.read_restricted
support.access
```

A workspace may add namespaced private keys such as
`<tenant-namespace>.collections.review`. Private keys do not become platform
permissions.

## Action rules

- Read permission never implies update.
- `configuration.manage` does not automatically grant activation; specific activation key plus step-up/approval is required.
- `documents.generate_approved` can use only production-enabled exact versions.
- `payments.record` cannot reverse/refund.
- `inventory.archive` is not hard delete.
- Restricted identifiers/files require the dedicated permission even when the parent party/document is readable.
- `media.create` may create, poll, and reason-retry an owned legal-original upload intent. Signed originals require the narrower `documents.upload_signed` key and recent strong authentication at intent, Storage INSERT, verification request, status poll, and manual dead-letter retry. Neither key grants direct upload-session SELECT or retry of a rejected/other-owner upload.
