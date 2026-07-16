# Milestone 1 end-to-end source integration

**Recorded:** 2026-07-16

**Status:** End-to-end source path integrated; database, Auth, SMTP, MFA,
Storage, worker-process, and provider runtime acceptance pending

## Outcome and boundary

Milestone 1 now has one tenant-neutral source path from an administrator-created
workspace invitation through authenticated membership, MFA-gated operations,
inventory/party/deal creation, a transactional document-preview job, worker
rendering, and a private artifact read. This document joins the individual
delivery records; it does not replace their detailed invariants or claim that
the path has run against a live Supabase environment.

The integrated path covers the source-level portions of `VYN-AUTH-001`,
`VYN-AUTH-002`, `VYN-TEN-001`, `VYN-SEC-001`, `VYN-AUD-001`, `VYN-INV-001`,
`VYN-INV-002`, `VYN-NUM-001`, `VYN-CRM-001`, `VYN-DEAL-001`, `VYN-DOC-001`,
`VYN-JOB-001`, `VYN-UX-001`, `VYN-I18N-001`, and `VYN-OPS-001`. Production
activation, official documents, payments, tenant formulas, real legal content,
and provider reconciliation beyond the documented invitation behavior remain
outside this source integration.

## Integrated sequence

| Step | Authoritative boundary and behavior | Source evidence | Acceptance/test IDs |
| --- | --- | --- | --- |
| 1. Invite | An authenticated administrator selects a server-verified workspace, completes recent AAL2, and submits email, expiry, locale, and explicit role IDs. Workspace, actor, provider token, and user authority are absent from the body. | `/api/v1/workspace-invitations`, OpenAPI command, operations invitation form, `create_workspace_invitation_job` | `M1-TEN-AC-002`, `M1-TEN-AC-004`, `M1-TEN-AC-005`, `M1-TEN-AC-008`, `T-TEN-002`, `T-RBAC-001`, `T-AUTH-002` |
| 2. Commit delivery intent | One transaction creates the pending invitation and immutable role snapshot, appends audit, and enqueues `auth.invitation.deliver` with only `invitation_id`. | Invite-only migration, outbox/job migration and pgTAP suites | `M1-JOB-AC-001` to `M1-JOB-AC-003`, `M1-AUTH-DELIVERY-AC-001`, `T-JOB-001`, `T-AUD-001` |
| 3. Deliver | The lease-fenced worker reloads authoritative invitation data. A new provider identity uses GoTrue `/invite`; an existing identity uses `/otp` with `create_user: false`. Both receive the same allowlisted callback, and provider tokens/response bodies are not persisted or logged. | Invitation worker handler, repository, provider adapter, runner, and tests | `M1-AUTH-DELIVERY-AC-001` to `M1-AUTH-DELIVERY-AC-008`, `T-AUTH-001`, `T-JOB-002`, `T-JOB-003` |
| 4. Login/callback | GoTrue establishes the invited identity/session and returns to `/login?invitation=<id>&workspace=<id>`. The IDs are routing context, not authorization. The browser Auth client detects the session at `/login`; there is no separate server callback route in this increment. | Invitation redirect builder, login page, `AuthAccess`, malformed-context and client tests | `M1-TEN-AC-005`, `M1-TEN-AC-008`, `T-AUTH-001`, `T-TEN-002` |
| 5. Accept | With the bearer session, the client posts only `invitationId`; workspace selection remains in `X-Workspace-Id`. SQL requires a confirmed authenticated email matching the pending, unexpired invitation, then atomically creates the membership and copied role assignments. | `/api/v1/workspace-invitations/accept`, application service, `accept_workspace_invitation` | `M1-TEN-AC-005`, `M1-TEN-AC-006`, `T-AUTH-001`, `T-TEN-001`, `T-RBAC-001`, `T-AUD-001` |
| 6. MFA gate | The operations view checks the current Auth assurance level. It exposes TOTP enrollment and challenge/verify controls and does not load workspace operations until AAL2. | `OperationsWorkbench`, Supabase MFA client calls, bilingual message catalogs | `M1-TEN-AC-004`, `M1-TEN-AC-008`, `M1-UX-AC-001`, `M1-I18N-AC-001`, `T-AUTH-002`, `T-UX-001`, `T-I18N-001` |
| 7. Workspace and grants | The client loads active memberships/workspaces and effective permission keys, then scopes reads and command headers to the selected verified workspace. Permission keys, not role labels, control visible/actions-enabled state. | Operations resource loader, auth/application policy packages, forced-RLS foundation | `M1-TEN-AC-001` to `M1-TEN-AC-003`, `M1-UX-AC-002`, `T-TEN-001`, `T-TEN-002`, `T-RBAC-001` |
| 8. Inventory | The mobile-usable form posts a typed/pasted VIN and integer minor-unit values. The command atomically creates vehicle/holding records and permanently allocates a workspace stock number. | `/api/v1/inventory-units`, application service, inventory package and SQL command | `M1-SLICE-AC-001` to `M1-SLICE-AC-003`, `T-INV-001`, `T-INV-002`, `T-NUM-001` to `T-NUM-003` |
| 9. Party | The next step creates a normalized workspace-owned person or organization through the same command boundary. | `/api/v1/parties`, CRM package and `create_party` | `M1-SLICE-AC-004`, `T-CRM-001` |
| 10. Deal | The deal draft links the selected party and inventory through composite workspace foreign keys while deriving owner membership from the authenticated identity. | `/api/v1/deals`, deals package and `create_deal_draft` | `M1-SLICE-AC-005`, `T-DEAL-001`, `T-TEN-001` |
| 11. Preview transaction | The preview command stores the immutable watermarked, unnumbered render snapshot and atomically creates the `documents.render_preview` outbox event/job and immutable mapping. | `/api/v1/documents/preview`, preview pipeline migration, OpenAPI, pgTAP | `M1-SLICE-AC-006` to `M1-SLICE-AC-009`, `M1-DOC-AC-006` to `M1-DOC-AC-010`, `T-DOC-001`, `T-DOC-JOB-001` to `T-DOC-JOB-006` |
| 12. Render/store | The durable worker claims with lease fencing, reloads and validates immutable source, escapes an allowlisted template, applies the non-production watermark, and uploads deterministic HTML to private Storage with create-only semantics. | Preview worker renderer, storage adapter, job runner, and tests | `M1-WORKER-AC-001` to `M1-WORKER-AC-006`, `T-JOB-002`, `T-JOB-003` |
| 13. Complete/read | The artifact RPC requires the matching current worker ID and lease token, then records checksum/media/bytes/path before generic job success. The browser sees only safe artifact identity; an audited user authorization plus service-only metadata load verifies exact bytes before a short URL is signed. | Preview artifact/authorization migrations, verified server grant adapter, operations action | `M1-DOC-AC-011` to `M1-DOC-AC-013`, `M1-WORKER-AC-007`, `M1-WORKER-AC-008`, `T-DOC-JOB-006` to `T-DOC-JOB-010`, `T-TEN-003` |

## HTTP authority and response contract

All write routes use `Authorization`, `X-Workspace-Id`, `Idempotency-Key`,
`X-Request-Id`, and `X-Correlation-Id`. The access token supplies identity;
`X-Workspace-Id` is a selection that SQL/application authorization must verify;
neither can be replaced by a body field.

Invitation creation accepts exactly:

```json
{
  "email": "invited.user@example.invalid",
  "expiresAt": "2026-07-23T18:00:00Z",
  "requestedLocale": "en-CA",
  "roleIds": ["00000000-0000-4000-8000-000000000001"]
}
```

It returns a camelCase `data` envelope with `invitationId`,
`invitationStatus`, `outboxEventId`, `jobId`, `jobStatus`, and `replayed` using
202 for a new queued invitation and 200 for replay. Acceptance accepts exactly
`{ "invitationId": "uuid" }` and returns `invitationId`, `membershipId`,
`invitationStatus`, and `replayed` using 201 for a new membership and 200 for
replay.

Strict schemas reject body `workspaceId`, user/actor IDs, membership IDs,
provider tokens, service credentials, and extra fields before PostgREST. Safe
command errors use 400, 401, 403, 409, 422, 429, or 503 envelopes without
database/provider detail.

## Permission, assurance, RLS, and audit evidence

| Action | Required authorization | Correlated successful audit evidence |
| --- | --- | --- |
| Create invitation | `users.manage` and recent AAL2 in the selected workspace | `auth.invitation.created`, `job.queued` |
| Accept invitation | Confirmed authenticated email matching the pending invitation; no pre-existing membership authority is accepted | `auth.invitation.accepted` plus membership/role lifecycle evidence |
| Enter operations | Active user/profile/membership and AAL2 in the source UI; SQL independently applies role/workspace MFA policy | Auth provider evidence; no secret is copied into audit |
| Create inventory | `inventory.create` | `inventory_unit.created` |
| Create party | `crm.create` | `party.created` |
| Create deal | `deals.create`, `crm.read`, `inventory.read` | `deal.created` |
| Request preview | `documents.preview`, `deals.read`, `crm.read`, `inventory.read` | `document.preview_requested`, `job.queued`, `document.preview_job_queued` |
| Complete preview | Service role plus matching current worker ID and active job lease token | `document.preview_generated`, `document.preview_artifact_recorded`, `job.succeeded` |
| Read artifact | `documents.read`, or requester plus `documents.preview`; audited server authorization; bounded size/checksum/MIME verification | Browser receives no provider coordinates; immutable artifact/authorization/audit rows remain authoritative |

Every persisted domain/job/file row preserves `workspace_id`; cross-workspace
links use composite foreign keys where applicable. Browser roles receive
RLS-filtered reads and narrow command execution, not raw table mutation.
Service-role use is limited to worker adapters and never substitutes for the
lease, mapping, workspace, checksum, or state validations in trusted RPCs.

## Idempotency, failure, and retry behavior

- Invitation create is scoped by workspace, actor, and idempotency key. Exact
  replay returns the original invitation/outbox/job; changed input conflicts.
- Acceptance is scoped by workspace, authenticated actor, and idempotency key.
  Exact replay returns the original membership; a different invitation
  conflicts.
- Inventory, party, deal, and preview commands use canonical fingerprints.
  The UI retains the key for a failed/ambiguous identical submission and clears
  it only after success.
- Preview enqueue commits or rolls back with its document and audit. The queue
  contains only IDs, locale, and checksums, never customer snapshots or
  credentials.
- Workers use bounded claims, heartbeat, lease expiry/reclaim, classified
  retry, exponential jitter, dead-letter review, and fenced terminal commands.
- Deterministic Storage upload uses `x-upsert: false`; a conflict succeeds only
  when private readback proves identical bytes/checksum. Artifact completion is
  immutable and exactly replayable.
- GoTrue invitation/OTP delivery cannot participate in the database
  transaction and is at least once. After an ambiguous invite outcome, an
  existing identity switches the retry to `/otp` with `create_user: false`
  rather than another `/invite`; both the original and retry email can still
  arrive. Job success proves provider submission, not SMTP delivery. Operators
  must not generate or copy provider links as a recovery shortcut.

The UI exposes safe loading, working, queued, unavailable, permission-denied,
failed/retry, and invitation-acceptance states. Provider/database details,
emails, snapshots, rendered HTML, service credentials, and provider response
bodies are excluded from browser errors and structured worker logs.

## Mobile, accessibility, and localization evidence

The source UI is mobile-first from 360 CSS pixels, uses step-based inventory,
party, deal, and preview forms, retains 44 px targets and visible focus, and has
no hover-only command. Invitation, login, acceptance, MFA, workspace selection,
permission denial, queue state, and preview availability copy exists in
structure-matched English and French catalogs. Machine keys, API fields, job
types, and permission keys remain language-independent.

Playwright covers shell/access layouts and accessibility checks, an AAL2
administrator invitation, an invited AAL1 user's MFA verification followed by
the required membership/resource reload, and the complete mocked operations
flow at phone and desktop widths. These tests prove browser source behavior and
body/header boundaries, not a live provider, database, worker, or Storage round
trip.

## Compatibility, rollback, and operations

All database changes are forward-only and history-preserving. If a defect is
found, disable the affected route/job type, stop new worker claims, allow or
reclaim leases safely, preserve invitation/membership/stock/job/artifact/audit
history, and ship a corrective migration. Do not drop or rewrite an applied
migration, reuse a stock/document number, overwrite an artifact, or delete job
attempt/audit evidence. UI/API deployment can roll back only when its callers
remain compatible with the applied database functions.

Required runtime configuration includes:

- public signup disabled and the normal-session maximum enforced in deployed
  Supabase Auth;
- exact allowlisting for the application `/login` invitation redirect;
- working Auth email/SMTP delivery and an approved recovery process;
- `VYNLO_APP_URL`, `VYNLO_SUPABASE_URL`, worker-only service-role credential,
  stable worker ID, and bounded worker timing;
- an existing private `VYNLO_PREVIEW_BUCKET` with the reviewed Storage/RLS
  policy; and
- queue age/depth, attempt/retry/dead-letter, provider classification, worker
  heartbeat/reclaim, and signed-artifact-access observability with runbooks.

## Runtime acceptance pending

Docker and a local Supabase/PostgreSQL stack are unavailable in the current
environment. Static parsing, unit/route tests, mocked Playwright flows, builds,
and contract linting do **not** establish runtime acceptance. No claim is made
that a live database migration, RLS decision, Auth invitation, SMTP message,
callback/session exchange, MFA challenge, worker lease, private upload, signed
URL, provider reconciliation, or complete user journey succeeded.

Before Milestone 1 runtime acceptance, evidence tied to the exact reviewed
revision must show:

1. a clean Supabase reset through all timestamped migrations and an idempotent
   seed rerun;
2. all pgTAP suites passing, including forced-RLS, cross-workspace, invitation,
   outbox, preview pipeline, immutable history, and Storage-policy assertions;
3. real multi-session stock allocation and worker claim/reclaim/heartbeat
   contention without duplicates or stale terminal writes;
4. public signup rejection plus a real administrator AAL2 invitation command;
5. GoTrue/SMTP delivery to an allowlisted `/login` redirect, matching confirmed
   identity acceptance, membership/role creation, and MFA enrollment/verify;
6. the authenticated inventory -> party -> deal -> preview sequence against the
   live database;
7. worker rendering into a verified private bucket, artifact/job success,
   exact replay, and a short-lived signed read that cannot disclose another
   workspace's object; and
8. secret/PII-safe browser responses, audits, logs, metrics, failure recovery,
   dead-letter review, and rollback/runbook evidence.

## Detailed delivery records

- [Tenancy and identity foundation](MILESTONE_1_TENANCY_FOUNDATION.md)
- [Configuration and entitlement foundation](MILESTONE_1_CONFIGURATION_ENTITLEMENTS.md)
- [Transactional outbox and durable jobs](MILESTONE_1_OUTBOX_JOBS.md)
- [First vertical slice](MILESTONE_1_FIRST_VERTICAL_SLICE.md)
- [Invite-only authentication](MILESTONE_1_INVITE_ONLY_AUTH.md)
- [Document-preview pipeline](MILESTONE_1_DOCUMENT_PREVIEW_PIPELINE.md)
- [Document-preview worker](MILESTONE_1_PREVIEW_WORKER.md)
- [Invitation-delivery worker](MILESTONE_1_INVITATION_DELIVERY_WORKER.md)
- [PWA and localization shell](MILESTONE_1_PWA_SHELL.md)
