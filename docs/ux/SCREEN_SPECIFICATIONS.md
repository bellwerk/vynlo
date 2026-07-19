# Screen specifications

All screens use translated labels, stable machine routes, permission-based actions, skeleton/loading, empty, validation, permission-denied, provider-failure, and offline states. Core screens work at 360 px without horizontal page scrolling.

## Global shell

### Mobile

- Top bar: workspace/brand, page title, job/attention indicator, profile.
- Bottom navigation: Inventory, Leads, Deals, Tasks, More.
- “More”: parties, documents, reports, settings, operations according to permission.
- Global search opened from header/command action.
- Safe-area padding and no controls hidden behind browser/home indicator.

### Desktop

- Collapsible sidebar with same information architecture.
- Header: workspace switcher, global search/command, jobs/notifications, locale, user/session.
- Main content max-width rules by screen; dense tables only on desktop.
- Workspace context is always visible and cannot be changed by a hidden form field.

## Authentication

### Sign in

- Google sign-in and invite-only email/password.
- No public registration.
- Localized errors without revealing whether an uninvited email exists.
- Link to password reset and privacy/support information.

### Invitation

- Show inviting workspace and role.
- Expired/used/revoked states.
- Accept, establish account, enroll MFA when policy requires.

### MFA

Enrollment, challenge, recovery-code acknowledgement, and step-up challenge. Sensitive command resumes only after successful assurance.

### Sessions

List device/browser, last activity, current marker; revoke one or all others. No raw token data.

## Dashboard

Role-sensitive cards:

```text
inventory counts/aging
listing/sync action required
new/overdue leads and tasks
appointments
deals by state
recent documents/activity
```

Cards navigate to filtered lists. Mobile stacks; desktop grid. Empty dashboard points to first permitted task.

## Inventory list

### Content

Cover thumbnail/placeholder, stock, year/make/model/trim, price/currency, location, workspace state, days in stock, media readiness, listing status, warnings.

### Mobile

- Search field.
- Filter/sort sheet with active-filter chips.
- Card/list; no spreadsheet dependency.
- Quick actions limited to safe common actions.
- Long-press is not required.
- Infinite/cursor “load more” with preserved scroll.

### Desktop

- Table with selectable columns, deterministic sorting, filters, saved views.
- Bulk actions only when every selected row is eligible.
- Inline edit only for explicitly safe fields; financial/transition changes open a focused form.
- Sticky stock/vehicle column where needed.

### States

No inventory, no matching results, partial data/incomplete, sync failure, access denied.

## Create inventory

Step wizard:

1. **VIN/specification** — type/paste VIN; validate; decode; compare existing records; manual facts.
2. **Acquisition/stock** — source, acquisition date, currency, stock preview; number is not allocated yet.
3. **Condition/location/odometer** — unit-aware input and required disclosures.
4. **Pricing/costs** — advertised/expected price and initial cost entries.
5. **Media** — optional initial uploads; may continue while processing.
6. **Review** — exact values, configured initial state, provider jobs to be queued.
7. **Confirm create** — allocates stock and creates record atomically.

Draft saves do not consume stock. Duplicate review cannot be bypassed without permission/reason.

## Inventory detail

Header: cover, stock, vehicle, state, location, price, primary actions and warnings.

Tabs/sections:

```text
Overview
Costs
Media
Listings
Leads/deals
Documents
Timeline/history
```

Mobile uses stacked summary and sticky action bar. Changes show saved/version state. Transition dialog explains effects such as unpublish or required inspection.

## Costs

Ledger list with category, vendor, date, amount/currency, attachment, status/reversal. Add form uses approved categories. Posted entry cannot be edited; reverse command explains effect.

## Media manager

- Drag/drop and device file picker; mobile camera/photo-library for vehicle photos/doc uploads, not VIN scanning.
- Queue with upload and processing progress.
- Preview master/derivative state.
- Accessible move earlier/later controls plus desktop drag reorder.
- Set cover, caption, archive, retry.
- Duplicate warning.
- Raw-retention date where permitted.
- Errors identify file and actionable retry/replacement.

## Listing detail

Per channel/locale:

```text
connection
publication state
mapped preview
last sync/attempt
remote link
asset state
drift/error
```

Publish/update/unpublish queues a job. Confirmation lists external effects. Conflict resolution shows Vynlo value and observed remote value with permitted adopt/overwrite choice.

## Leads

### List/board

Desktop offers Board and List modes. Board columns derive from the selected
workspace pipeline's active immutable workflow version; application code never
hard-codes stage names or order. Non-terminal states are columns. Converted and
Lost are outcome targets and filters. Cards show prospect/lead, interested
vehicle, assignee, source, next action, and overdue/age attention without
decorative badges or dense nested cards.

Filters cover state, assignee, source, inventory interest, next-action window,
created date, and search. Location is offered only when the lead or interested
inventory has authoritative location context. Filters, selected pipeline, and
Board/List mode persist as safe URL state. Every column is independently bounded
and cursor-paginated.

Pointer drag, touch, keyboard, and a `Move to…` menu are equivalent ways to call
the existing permissioned transition command. Only allowed destinations are
presented. Stale or concurrent moves roll back visually, announce the conflict,
and refresh affected columns. Lost requires its configured reason; Converted
opens the existing deal-conversion flow rather than silently changing state.

At 320–414 px, use a stage picker/tabs and one vertical card list; never compress
the desktop board or introduce horizontal page scrolling. Empty, no-match,
loading, partial failure, offline, stale, permission-denied, success, and retry
states are explicit. See `implementation/LEAD_PIPELINE_BOARD_SCOPE.md`.

### Detail

Prospect/contact, interested units, assignment/state, next task, timeline, appointments, notes, source. Actions: call/email link where safe, add activity, task, appointment, convert, close lost with reason.

## Parties

Search people/organizations. Detail:

```text
profile
contacts/addresses
masked identifiers
communication preferences
timeline
leads/deals
documents
```

Restricted identifiers require permission and may require explicit reveal audit. Duplicate party suggestions require review, not silent merge.

## Tasks and appointments

Personal/team list/calendar, due/start time, priority/status, entity links. Complete/reschedule/reassign according to permission. Timezone always explicit in storage and clear in display.

## Deal wizard

1. Deal type and location/legal entity.
2. Participants and roles.
3. Inventory units and trade-ins.
4. Price, line items, taxes, and one-time transactions.
5. External finance, when applicable.
6. Documents and requirements.
7. Review and configured transition.

Tenant deal type schema controls steps/fields. Review lists missing requirements and exact activation gates. Draft autosave does not close inventory or generate official documents.

## Trade-in

Capture owner, VIN/vehicle facts, odometer, condition, allowance, lien/payoff/lender, supporting files, and tax eligibility inputs. Clearly distinguish allowance from payoff. Creating the resulting inventory unit follows workspace stock policy and separate confirmation.

## Third-party finance

List/detail with lender, applicant, deal/vehicle, requested/approved amount, external reference, state, returned rate/term, conditions, expiration, funding. Vynlo labels values as lender-reported and does not calculate a repayment schedule.

## One-time transactions

Deal ledger shows type, amount, method, reference, state, proof, actor/date, reversal/refund links. Record form supports multiple transactions. Settle, reverse, and refund use separate commands and permissions; settled row is read-only.

## Documents

### Type selection

Show installed/available types with states:

```text
available
preview only
missing required data
missing approval
disabled
retired
```

### Document wizard

Tenant schema groups fields into short steps, prefills authoritative data, distinguishes editable and calculated fields, and shows source/override provenance.

### Preview

Queue/render status, visible watermark, no official number. Allow data correction and new preview.

### Official confirmation

Show irreversible number allocation, exact document date, legal entity, template/tax/formula versions, and unresolved warnings. Requires permission and step-up where configured.

### Detail

Status/timeline, exact versions/checksums, preview/generated/signed files, job state, lineage, secure download, signed upload, mark signed, void/supersede according to policy.

## Reports and exports

Report filters, definitions, sensitivity, currency/unit labels, generated time. Export command shows row scope and expiry; job progress and secure expiring download. Empty/large-result guidance.

## Settings

Grouped by permission:

```text
Workspace and branding
Legal entities/identifiers
Locations
Members/roles
Features/packs
Workflows
Custom fields
Numbering
Tax packs
Document types/templates
Export definitions
Integrations
Retention/security
Audit
```

Draft/version/approval/activation status is always visible. Activation dialog shows checksums, gates, impact, effective date, and rollback path.

## Operations

Jobs, dead letters, provider health, drift/conflicts, migration batches, recent incidents. Raw secret payloads never shown. Retry/cancel/resolve requires eligible status, permission, and reason when sensitive.

## Audit

Filter by time, actor, action, entity, category, assurance, correlation ID. Read-only. Diffs mask restricted fields unless separately authorized. Link to entity/version where retained.

## System states

- **Offline:** persistent banner; writes/finalization disabled; safe local form state explained.
- **Maintenance/degraded provider:** affected capability warning, authoritative records remain accessible where safe.
- **403:** explains missing permission without exposing hidden data.
- **404:** same for absent/inaccessible resource.
- **409 conflict:** preserves input and offers refresh/compare.
- **500/503:** correlation ID and safe retry/support action.
