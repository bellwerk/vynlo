# API endpoint catalogue

**Base:** `/api/v1`  
**Normative companion:** `contracts/openapi.v1.yaml`

All endpoints authenticate the user, resolve active membership/workspace on the server, apply permission and RLS checks, return a correlation/request ID, and use structured errors. UUIDs are opaque. Mutation clients send `Idempotency-Key` where noted and `If-Match`/expected version for mutable aggregates.

## Identity and workspace

| Method/path | Permission | Behavior |
|---|---|---|
| `GET /me` | authenticated | Profile, accessible workspaces, auth assurance |
| `GET /sessions` | authenticated | Active sessions/devices when provider supports |
| `DELETE /sessions/{id}` | authenticated | Revoke one session |
| `POST /sessions/revoke-all` | authenticated + step-up | Revoke other sessions |
| `GET /workspaces` | authenticated | Accessible workspaces |
| `GET /workspaces/{id}` | workspace member | Workspace summary/features |
| `PATCH /workspaces/{id}` | `workspace.manage` + version | Safe workspace settings |
| `GET/POST /workspaces/{id}/members` | `users.manage` | List/invite members |
| `PATCH /members/{id}` | `users.manage` + step-up | Roles/status |
| `GET /permissions` | member | Effective permission keys |

Auth enrollment/reset/MFA challenge use Supabase Auth routes; application callbacks enforce invitation and membership.

## Legal entities, brands, locations

```text
GET/POST/PATCH /legal-entities
GET/POST/PATCH /brands
GET/POST/PATCH /locations
```

Manage permission required. Sensitive identifiers use separate endpoints and permissions:

```text
GET/POST/PATCH /legal-entities/{id}/identifiers
```

Reads return masked values unless restricted permission is present.

## Inventory

| Method/path | Behavior |
|---|---|
| `GET /inventory-units` | Cursor list, filters, saved-view-compatible fields |
| `POST /inventory-units` | Confirm decoded facts and atomically create or safely link; response distinguishes allocation from existing-open-unit linkage |
| `GET /inventory-units/{id}` | Permission-aware operator detail; internal notes and cost/gross fields are masked independently |
| `PATCH /inventory-units/{id}` | Versioned editable fields |
| `POST /inventory-units/{id}/location-transfers` | Versioned transfer to an active workspace location with audit/outbox evidence |
| `POST /inventory-units/{id}/transition` | Execute configured workflow transition |
| `POST /inventory-units/{id}/archive` | Convenience command to configured archive transition |
| `GET/POST /inventory-units/{id}/costs` | Bounded exact cost ledger, active localized categories, metrics, and cost posting |
| `POST /inventory-costs/{id}/reversal` | Step-up reversal entry, never edit posted amount |
| `GET/POST /inventory-saved-views` | List complete visible configurations or save a versioned private/shared view |
| `POST /inventory-saved-views/{id}/archive` | Owner-only optimistic saved-view archive |
| `GET /locations` | Active workspace locations available to inventory search and transfer |
| `GET /vehicles/{id}` | Physical vehicle facts/history |
| `POST /vin/decode` | Decode suggestions; no stock allocation |
| `GET /vin/decode/{requestId}` | Safe request/job/result status without raw provider payload; consumed requests are terminal while job history remains intact |
| `POST /vin/decode/{requestId}/retry` | Reasoned retry of eligible durable decode work |
| `POST /vin/decode/{requestId}/duplicate-review` | Append a reasoned active/history duplicate decision |
| `POST /vin/decode/{requestId}/manual-intake` | Confirm manual facts only after authoritative dead-letter state; response distinguishes create from safe linkage without a second open holding episode |
| `POST /vehicles/{id}/facts-override` | Full-snapshot controlled correction with reason, expected facts version, immutable history, permission, and recent step-up |

Inventory creation requires idempotency. Transition and update require expected version.

## Media

```text
POST /inventory-units/{id}/media/upload-intents
GET /inventory-units/{id}/media
POST /media/{id}/complete-upload
GET /media/{id}/upload-sessions/{uploadSessionId}
POST /media/{id}/upload-sessions/{uploadSessionId}/retry
GET /media/{id}
PATCH /media/{id}
POST /inventory-units/{id}/media/reorder
POST /inventory-units/{id}/media/{mediaId}/set-cover
POST /media/{id}/reprocess
POST /media/{id}/archive
POST /media-files/{id}/download-grants
POST /documents/{id}/original-upload-intents
POST /documents/{id}/original-upload-completions
GET /documents/{id}/original-upload-sessions/{uploadSessionId}
POST /documents/{id}/original-upload-sessions/{uploadSessionId}/retry
```

Upload intent declares expected type/size. Completion queues processing. Responses expose raw/master/derivative states without leaking provider credentials. Download authorization returns an opaque grant; a service-only loader verifies exact immutable bytes before signing a short URL.

Legal-original status is owner/permission scoped and exposes only projected
lifecycle, bounded attempt/retry, and safe failure fields. Manual retry accepts
an explicit reason only while the active verification job is dead-letter;
terminal rejection requires a new upload intent. Signed-original status and
retry repeat recent strong authentication.

Vehicle upload status is separately owner/permission scoped and exposes only
projected lifecycle, bounded attempt/retry, and safe failure fields. Manual
retry requires an explicit reason and the exact current dead-letter job; a
terminally rejected vehicle photo must use a new upload intent. Neither route
returns quarantine coordinates, checksums, scan receipts, or raw worker/provider
errors.

## Listings and integrations

```text
GET /inventory-units/{id}/listings
POST /inventory-units/{id}/listings/{connectionId}/publish
POST /inventory-units/{id}/listings/{connectionId}/update
POST /inventory-units/{id}/listings/{connectionId}/unpublish
POST /listings/{id}/reconcile
GET /integration-connections
POST /integration-connections/{provider}/authorize
POST /integration-connections/{id}/callback
PATCH /integration-connections/{id}
POST /integration-connections/{id}/health-check
DELETE /integration-connections/{id}
GET /integration-conflicts
POST /integration-conflicts/{id}/resolve
```

Provider actions queue jobs and return `202` with job ID. Credential changes require step-up. Deletion disables the connection and preserves mappings/history.

## Parties and CRM

```text
GET/POST/PATCH /parties
GET/POST/PATCH /parties/{id}/contacts
GET/POST/PATCH /parties/{id}/addresses
GET/POST/PATCH /parties/{id}/identifiers
GET/POST/PATCH /leads
POST /leads/{id}/transition
POST /leads/{id}/convert
GET/POST /activities
GET/POST/PATCH /tasks
POST /tasks/{id}/complete
GET/POST/PATCH /appointments
```

Lead conversion is idempotent and creates/links one deal. Restricted identifiers use masked response and dedicated permission.

## Deals, trade-ins, and external finance

```text
GET/POST/PATCH /deals
POST /deals/{id}/transition
GET/POST/DELETE /deals/{id}/participants
GET/POST/DELETE /deals/{id}/inventory-units
GET/POST/PATCH /deals/{id}/line-items
GET/POST/PATCH /deals/{id}/trade-ins
GET/POST/PATCH /finance-applications
POST /finance-applications/{id}/transition
GET/POST /finance-applications/{id}/conditions
```

Deleting a draft relationship is allowed only before official document/financial history. Otherwise use close/cancel/reversal commands.

## One-time payment transactions

```text
GET/POST /deals/{id}/payment-transactions
GET /payment-transactions/{id}
POST /payment-transactions/{id}/settle
POST /payment-transactions/{id}/reverse
POST /payment-transactions/{id}/refund
```

Record/settle requires idempotency. Reverse/refund requires permission, reason, step-up where configured, and creates new linked transaction. A settled transaction is not patched.

## Documents

| Method/path | Behavior |
|---|---|
| `GET /document-types` | Active/available types and requirements |
| `POST /documents/validate` | Validate data and activation gates |
| `POST /documents/preview` | Queue watermarked, unnumbered preview |
| `POST /documents/official` | Allocate permanent number and queue official render |
| `GET /documents` | Search/filter |
| `GET /documents/{id}` | Version/lineage/files/job |
| `POST /document-preview-artifacts/{id}/download-grants` | Audit visibility, verify immutable provider bytes server-side, and issue a short grant without exposing provider coordinates |
| `GET /documents/{id}/files/{fileId}/download` | Time-limited authorized download |
| `POST /documents/{id}/signed-files` | Register signed scan version |
| `POST /documents/{id}/mark-signed` | Transition with required data |
| `POST /documents/{id}/void` | Authorized reason/step-up |
| `POST /documents/{id}/supersede` | Create replacement relationship |
| `POST /documents/{id}/retry-render` | Retry same number/idempotent job |

Official generation requires idempotency and returns `202`. Preview never accepts/returns an official number.

## Workflow, fields, numbering, reusable packs, workspace configuration, and approvals

Administrative:

```text
GET /workflow-definitions
POST /workflow-definitions/{key}/versions
POST /workflow-versions/{id}/approve
POST /workflow-versions/{id}/activate

GET/POST /custom-field-definitions
POST /custom-field-definitions/{id}/retire

GET /numbering-definitions
POST /numbering-definitions/{key}/versions
POST /numbering-versions/{id}/activate

GET /installed-packs
POST /packs/validate
POST /packs/install
POST /packs/{key}/{version}/activate
POST /packs/{key}/{version}/retire

GET /workspace-configuration/versions
POST /workspace-configuration/imports
POST /workspace-configuration/exports
POST /workspace-configuration/versions/{id}/activate

GET /workspace-feature-entitlements
PATCH /workspace-feature-entitlements/{featureKey}

GET/POST /approval-records
```

Reusable pack endpoints apply only to starter and tax packs. Workspace-owned legal/business behavior is imported or edited as versioned runtime configuration. Activation commands require configuration permission, step-up, compatibility validation, passed fixtures, approval gates, and audit.

## Tax and calculations

```text
GET /tax-packs
POST /tax/calculate-preview
POST /tax-pack-versions/{id}/activate
GET /calculation-definitions
POST /calculations/validate
POST /calculations/run-preview
POST /calculation-versions/{id}/approve
POST /calculation-versions/{id}/activate
```

Preview cannot mutate official records. Tax/calculation official snapshots are created through the owning document/deal command.

## Exports and reporting

```text
GET /export-definitions
POST /exports/{definitionKey}/runs
GET /export-runs/{id}
GET /export-runs/{id}/download
GET /reports/inventory-aging
GET /reports/inventory-gross
GET /reports/leads
GET /reports/deals
```

Sensitive runs may require step-up. Generated links expire.

## Jobs, audit, and operations

```text
GET /jobs
GET /jobs/{id}
POST /jobs/{id}/retry
POST /jobs/{id}/cancel
GET /integration-conflicts
GET /audit-events
GET /health/ready
GET /health/live
```

Users see only jobs/audit allowed for their workspace/permission. Raw secret/provider payloads are never returned.

## Standard response rules

- `200/201`: completed authoritative operation.
- `202`: accepted asynchronous operation with job/document ID.
- `204`: completed with no body.
- `400`: malformed request.
- `401`: unauthenticated.
- `403`: authenticated but prohibited/insufficient assurance.
- `404`: absent or inaccessible; do not reveal cross-workspace existence.
- `409`: version/idempotency/duplicate/state conflict.
- `422`: valid shape but business/activation validation failed.
- `429`: rate limit with retry metadata.
- `503`: temporary dependency/service unavailability.

Error shape:

```json
{
  "code": "DOCUMENT_ACTIVATION_GATE_FAILED",
  "message": "This document version is not available for official generation.",
  "field_errors": {},
  "request_id": "…",
  "retryable": false,
  "details": {
    "gate_keys": ["legal_approval_missing"]
  }
}
```

User-visible text is localized from stable error codes; APIs do not localize machine keys.
