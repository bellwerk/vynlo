# PostgreSQL schema specification

**Status:** Normative logical DDL for Release 1. Migrations may split supporting tables, but may not remove ownership, constraints, history, or invariants without an ADR.

## Conventions

- PostgreSQL `uuid` primary keys generated server-side.
- Every operational tenant row has non-null `workspace_id`.
- `created_at`, `updated_at` are `timestamptz`; legal/business dates use `date`.
- Mutable aggregates have `version bigint not null default 1`.
- Money is `bigint amount_minor` plus `char(3) currency_code`.
- Rates are `integer` basis points or exact `numeric`, identified in the column name.
- Soft lifecycle fields are explicit; no generic `deleted_at` on financial/document/audit records.
- Human sequence values allocate inside a transaction and are never inferred using `max()+1`.
- JSON configuration is schema-versioned and checksummed.
- All exposed tables have RLS.

## Identity, tenancy, and configuration

### `organizations`

| Column | Type | Rules |
|---|---|---|
| id | uuid | PK |
| name | text | required |
| status | text | `active`, `suspended`, `closed` |
| billing_metadata | jsonb | no payment secrets |
| created_at/updated_at | timestamptz | required |

Index: normalized name for support search.

### `workspaces`

| Column | Type | Rules |
|---|---|---|
| id | uuid | PK |
| organization_id | uuid | FK organizations |
| slug | citext | unique globally |
| name | text | required |
| status | text | `provisioning`, `active`, `suspended`, `closed` |
| default_locale | text | BCP-47 |
| timezone | text | IANA |
| default_currency | char(3) | ISO 4217 |
| odometer_unit | text | `km` or `mi` |
| settings_version | bigint | optimistic concurrency |
| created_at/updated_at | timestamptz | required |

### `user_profiles`

`user_id uuid` PK/FK `auth.users`; display name, preferred locale, status, last workspace, timestamps. Email remains owned by Auth and is not duplicated unless required for audit snapshot.

### `workspace_memberships`

Workspace/user unique pair, status, invitation/activation/deactivation timestamps, invited_by, created/updated. Inactive membership fails all RLS.

### `roles`, `permissions`, `role_permissions`, `membership_roles`

Roles may be system/pack/workspace defined. Permission key is immutable stable text. Unique workspace/key where workspace-defined. Membership-role unique. Platform code checks permissions, not labels or role names.

### `legal_entities`

Workspace, immutable key, legal/operating names, registered address reference, default currency/locale/timezone, effective dates, status, version.

### `legal_entity_identifiers`

Legal entity, identifier type, encrypted/masked value where sensitive, effective dates, verification state. Separate read permission.

### `brands`

Workspace, name, public contact/branding references, active state.

### `locations`

Workspace, legal entity/brand optional links, key, name, address, phone/email, locale/timezone, active state. Unique workspace/key.

### `workspace_settings`

Workspace one-to-one, schema version, settings JSON, version, updated_by/time. Contains safe operational defaults such as locale, media profile, UI preferences, and approved configuration references; never credentials.

### `workspace_feature_entitlements`

Workspace/feature key unique, enabled, source (`plan`, `admin`, `migration`, `support`), configuration JSON, effective dates, version, audit metadata. API and UI authorization must consult the same entitlement service.

### `feature_flags`

Platform rollout/experiment key with optional workspace targeting, enabled state, configuration, effective dates, and audit metadata. Feature flags are not billing entitlements and cannot bypass permissions or activation gates.

### `installed_packs`

Workspace, pack class (`starter`, `tax`), key/version/schema, source/checksum, installed/activated/retired timestamps, status. Unique workspace/class/key/version. Workspace-specific legal/business configuration is stored in dedicated versioned records rather than treated as a runtime Git pack.

### `workspace_configuration_versions`

Workspace, version label, schema version, status (`draft`, `validated`, `approved`, `active`, `retired`), source (`admin`, `seed`, `import`, `migration`), source/checksum/provenance, parent version, created/approved/activated/retired metadata, and immutable summary/diff references.

### `workspace_configuration_changes`

Configuration version, artifact type/key/version, change operation, before/after checksum, validation state, dependency/impact metadata. Provides the installation plan and traceability without duplicating every domain artifact body.

### `workspace_configuration_activations`

Workspace, configuration version, effective time, previous active version, actor, approval records, status, rollback reference, and audit correlation. Only one active configuration baseline per workspace, while domain artifact versions may have independent effective dates where documented.

### `workspace_configuration_imports` / `workspace_configuration_exports`

Workspace, source/destination, package schema/version/checksum, validation/impact report, status, requested/completed metadata, generated file reference, and redaction policy. Credentials and customer data are excluded from portable packages.

## Inventory

### `vehicles`

| Column | Type | Rules |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | required |
| vin | citext | normalized; nullable only during incomplete import |
| model_year | smallint | reasonable range validation |
| make/model/trim | text | trim nullable |
| body_type | text | nullable |
| engine_liters | numeric(5,2) | nullable |
| cylinders/horsepower | integer | nullable |
| transmission/fuel_type/drivetrain | text | normalized keys |
| exterior/interior_color | text | nullable |
| manufacturer_data | jsonb | provider snapshot/reference, not authoritative user edits |
| decoder_provider/result/version | text/jsonb | nullable |
| facts_version | bigint | required |
| created_at/updated_at | timestamptz | required |

Constraints:
- normalized VIN syntax check when present;
- no global uniqueness across holding history;
- application duplicate-review query by workspace/VIN;
- only controlled permission can override conflicting VIN facts.

Indexes: workspace/VIN, workspace/year/make/model.

### `inventory_units`

| Column | Type | Rules |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | required |
| vehicle_id | uuid | FK |
| stock_number | citext | unique per workspace |
| stock_allocation_id | uuid | FK |
| acquisition_date/source_party_id | date/uuid | nullable during incomplete state |
| location_id | uuid | required before available |
| odometer_value | bigint | nonnegative |
| odometer_unit | text | `km`/`mi` |
| condition_key/title_status | text | nullable/configurable |
| currency_code | char(3) | required |
| advertised_price_minor | bigint | nullable |
| expected_sale_price_minor | bigint | nullable |
| workflow_instance_id | uuid | required |
| public_notes/internal_notes | text | access separated |
| acquired_at/available_at/sold_at/closed_at | timestamptz | nullable |
| version | bigint | required |
| created_at/updated_at | timestamptz | required |

Constraints:
- unique `(workspace_id, lower(stock_number))`;
- vehicle/workspace match;
- money currency equals unit currency unless explicit conversion module exists;
- no hard delete after operational activity.

Indexes: workspace/state/location, stock, vehicle, acquired date, price.

### `inventory_cost_entries`

Workspace, inventory unit, category definition, amount/currency, tax snapshot optional, vendor party optional, incurred date, description, supporting file, reversal_of optional, status, created_by/time.

Settled/posted entry is never edited; correction creates reversal/replacement. Index by unit/date/category.

### `stock_number_definitions`

Workspace/key/version, strategy JSON, activation state, checksum, approval. Active definition immutable.

### `stock_number_allocations`

Workspace, definition version, allocated value, numeric sequence, suffix, entity ID, source relationship, allocation/import event, idempotency key, allocated_by/time.

Unique workspace/value and workspace/definition/sequence/suffix. No delete/reuse.

### `vehicle_media`

Workspace, inventory unit, type, caption, sort order, cover flag, status, retention policy/version, created_by/time.

Partial unique index: one current cover per inventory unit.

### `media_files`

Media, role (`raw`, `normalized_master`, `website`, `thumbnail`, `preview`), storage mapping, MIME, bytes, width/height, checksum, processing state, retention/delete time, created time.

Unique media/role/profile version. Checksum indexes support dedupe; cross-workspace bytes are never exposed by dedupe.

### `channel_listings`

Workspace, inventory unit, integration connection, channel/locale, remote resource link, publication status, mapped data checksum/snapshot, remote version/etag, last sync/attempt, drift state, error, version.

Unique inventory/connection/channel/locale.

## Parties and CRM

### `parties`

Workspace, type (`person`, `organization`), display name, status, version, timestamps.

### `person_profiles` / `organization_profiles`

One-to-one party detail. Person: legal/preferred names, DOB when required. Organization: legal/operating names and registration data references.

### `party_contacts`

Party, contact type/value, normalized value, primary/preferred/verified flags, consent/preferences, effective dates. Sensitive read rules apply.

### `party_addresses`

Party, type, structured address, primary flag, effective dates.

### `party_identifiers`

Party, type, encrypted value, masked suffix, jurisdiction, effective dates, verification. Restricted permission and audit on read where configured.

### `party_relationships`

Workspace, source party, target party, relationship key, effective dates, notes/privacy metadata, version. Both parties must belong to the same workspace. Use for durable relationships; deal-specific roles remain in `deal_participants`.

### `leads`

Workspace, prospect party optional, source key, interested inventory optional, assignee membership, workflow instance, summary, next action, converted deal/lost reason, version, timestamps.

Indexes: workspace/state/assignee/next action/source.

### `activities`

Workspace, party/lead/deal optional links, type/channel, subject/body, direction, occurred_at, actor, provider reference. Append-only except controlled redaction.

### `tasks`

Workspace, entity links, assignee, due time, priority, status, title/description, completion metadata, version.

### `appointments`

Workspace, related entities, start/end/timezone/location, status, participants, notes, version.

## Deals and money

### `deal_type_definitions`

Workspace/key/version, labels, schema, workflow/version, allowed participant/inventory roles, activation.

### `deals`

Workspace, deal type/version, legal entity/location, currency, workflow instance, owner membership, primary dates, subtotal/tax/total snapshot references, notes, version, timestamps.

### `deal_participants`

Deal, party, role key, primary flag, snapshot JSON for official documents. Unique deal/party/role where appropriate.

### `deal_inventory_units`

Deal, inventory unit, role (`sold`, `purchased`, `trade_in`, `wholesale`, tenant key), amount/metadata. Guards prevent conflicting active sale deals.

### `deal_line_items`

Deal, key/type/label, quantity exact numeric, unit amount minor, currency, tax classification, payment timing, sort order, source/reference, version.

### `trade_ins`

Workspace/deal, owner party, physical vehicle or entered facts, allowance amount, lien/payoff, lender reference, condition, tax eligibility inputs, resulting inventory unit optional, status, version.

### `finance_applications`

Workspace/deal, applicant/lender parties, requested/approved amounts, currency, external reference, submitted/decision/expiry/funded dates, returned annual rate/term, status, conditions, provider mapping, version.

### `finance_application_conditions`

Application, text/key, required/satisfied status, due date, supporting file, timestamps.

### `payment_transactions`

Workspace/deal, type (`deposit`, `receipt`, `refund`, `lender_proceeds`, `trade_in_credit`, `other`), amount/currency, method, reference, occurred/settled dates, status, proof file, reversal/refund relationship, recorded/approved by, reason, version.

Rules:
- no mutation of a settled amount/status except through commands that create reversal/refund records;
- positive/negative sign convention is documented per type;
- idempotency prevents duplicate provider/import records.

## Documents, numbering, tax, and formulas

### `document_types`

Workspace/key/version, labels, field schema/checksum, numbering/workflow/template/tax/calculation references, production flag, activation status, approvals. Unique workspace/key/version.

### `document_template_versions`

Workspace/document type, version, locale, immutable source-bundle storage ref/checksum, asset/font manifest, renderer version, field schema/checksum, status, approvals, timestamps.

### `documents`

Workspace, document type/version, deal/entity references, preview/official mode, official number/allocation, status, intended signature date, exact template/tax/calculation/workflow/renderer references, immutable input snapshot/checksum, generated checksum, supersedes/superseded_by, created_by/time.

Unique workspace/document type/official number when official. Preview has no official number.

### `document_files`

Workspace/document, role (`preview`, `generated_original`, `signed_scan`, `attachment`, `void_notice`), version number, storage mapping, filename, MIME/bytes/checksum, current flag, uploaded/generated by/time.

Unique document/role/version. Partial unique one current signed scan if required, while all versions remain.

### `numbering_definitions` / `number_allocations`

Same immutable allocation model as stock; scope may be workspace, legal entity, location, document type, and optional period. Reset behavior explicit. Allocation and official-document creation occur in one transaction.

### `calculation_definitions` / `calculation_versions`

Workspace or approved-pack scope, key/version, input/output schemas, typed AST/checksum, engine version range, status, fixtures, approvals.

### `calculation_snapshots`

Workspace, definition/version, document/deal, immutable input/output/component/rounding JSON, engine version/checksum, run time. No update/delete.

### `tax_packs` / `tax_pack_versions`

Jurisdiction/context/effective dates, schema/rules/source/checksum, golden tests, approvals, state. Platform-managed packs are not automatically active in a workspace.

### `tax_calculation_snapshots`

Workspace, pack/version, transaction context, immutable input/output, override/reason, engine version/checksum, created time. No update/delete.

## Workflow and custom fields

### `workflow_definitions` / `workflow_versions`

Workspace or pack scope, key/entity type/version, schema/checksum, status, approvals.

### `workflow_states` / `workflow_transitions`

Version-owned state/transition rows with labels, canonical category, flags, guards, permissions, reason/field requirements, effects, order.

### `workflow_instances`

Workspace, definition/version, entity type/id, current state, version, started/closed times.

### `workflow_events`

Instance, transition, from/to, actor, reason, input/effect snapshot, correlation ID, occurred time. Append-only.

### `custom_field_definitions`

Workspace/entity/key/version, translated label/help, type, validation/default/options, sensitivity, required/visibility/edit permissions, status. Critical core fields cannot be shadowed.

### `custom_field_values`

Workspace, definition/version, entity type/id, typed value columns/JSON, version. Unique entity/definition.

## Integrations, jobs, exports, and audit

### `integration_connections`

Workspace/provider/type/environment, encrypted credential reference, scopes, configuration, status/health, token expiry, last check, version. Credentials never returned through normal API.

### `external_resources`

Workspace/connection, Vynlo entity/file type/id, remote ID, remote parent/path/URL metadata, etag/version/checksum, drift state, last observed. Unique connection/remote ID and entity/connection/role.

### `jobs`

Workspace, type, entity, payload schema/version, idempotency key, status, priority, available/lock times, attempt limits, correlation ID, result/error summary, timestamps.

Unique workspace/job type/idempotency key. Worker claim uses `FOR UPDATE SKIP LOCKED`.

### `job_attempts`

Job, attempt number, start/end, worker, outcome, error classification/code/detail-safe, provider request ID, retry time. Append-only.

### `export_definitions` / `export_versions`

Workspace or pack scope, key/version, entity, filters/columns/calculations/formats, schema/checksum, status, approvals.

### `export_runs` / `export_files`

Workspace, definition/version, parameters, requester, status, row count, expiry, output file/checksum. Sensitive exports require step-up and audit.

### `approval_records`

Workspace, artifact type/id/version/checksum, approval type, approver identity/role/organization, decision, conditions, attachment/reference, time. A rejected/superseded approval cannot activate an artifact.

### `audit_events`

Append-only, partitionable by time: workspace, actor/type, action, entity, before/after or diff, reason, request/correlation ID, IP, user agent, auth assurance, timestamp, hash-chain fields where enabled.

## Required database invariants

1. Cross-workspace foreign keys are prevented through composite ownership checks or transaction validation plus RLS.
2. Stock and official document numbers never duplicate or re-enter available pools.
3. Only one active workflow instance per entity/workflow purpose.
4. One cover media per inventory unit.
5. Official document snapshots and activated versions are immutable.
6. Settled financial transactions are reversed, not overwritten.
7. One provider remote object cannot map to unrelated entities in one connection.
8. Jobs with the same idempotency key cannot produce duplicate side effects.
9. Every privileged command writes audit in the same transaction.
10. Every activated pack/template/formula/tax/export/workflow has approval/checksum provenance.

## Required indexes

At minimum:

- workspace and primary list filters on every high-volume table;
- normalized stock and VIN;
- inventory workflow/location/age/price;
- leads/tasks by assignee/state/due;
- deals by state/type/date/owner;
- documents by number/type/status/entity;
- jobs by status/available/priority and idempotency;
- audit by workspace/time/entity/actor;
- external resources by connection/remote ID;
- GIN only on JSON fields with proven query use.

Index plans must be verified with realistic staging data before launch.
