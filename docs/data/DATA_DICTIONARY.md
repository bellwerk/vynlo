# Data dictionary

This is the logical schema. SQL migrations may normalize further while preserving ownership, history, and invariants.

## Identity and tenancy

### `organizations`
Commercial account: name, status, billing metadata.

### `workspaces`
Operational isolation boundary: organization, name, slug, default locale, timezone, default currency, status.

### `user_profiles`
Primary key references the authentication-provider user ID; display name, preferred locale, status.

### `workspace_memberships`
Workspace, user, role assignments, membership status, invite/activation timestamps. Unique workspace/user.

### `roles`, `permissions`, `role_permissions`
Workspace or pack-defined RBAC. Application code checks permission keys, never hardcoded role names.

### `legal_entities`, `brands`, `locations`
Effective-dated seller/company information, operating brands, branches, addresses, contacts, timezone/locale overrides.

## Inventory

### `vehicles`
Physical identity: VIN, model year, make, model, trim, body, engine, transmission, fuel, drivetrain, colours, manufacturer data, decoder result. A normal rule blocks accidental duplicate active records; controlled override handles data quality or legitimate history.

### `inventory_units`
Workspace holding episode: vehicle, stock number, acquisition source/date, location, odometer value/unit, condition, workflow instance, prices/currency, availability/sale/closure dates, notes, concurrency version.

### `inventory_cost_entries`
Category, amount minor, currency, vendor party, tax snapshot, incurred date, notes, supporting file. Typical categories: acquisition, transport, repair, registration, detailing, other.

### `stock_number_definitions`, `stock_number_allocations`
Versioned strategy, prefix/padding/suffix behavior, sequence state, permanent allocation event, source relationship, import reservation.

### `vehicle_media`, `media_files`
Media item, file roles, provider references, dimensions, checksum, sort order, cover flag, scan/processing state, retention date.

### `channel_listings`
Inventory unit, provider connection, remote item ID, locale/channel, publication state, mapped snapshot, last sync, etag/version, drift/error.

## CRM and parties

### `parties`
Type `person` or `organization`; display name and workspace ownership.

### `party_contacts`, `party_addresses`, `party_identifiers`
Phones, emails, addresses, and regulated identifiers with type, validity, verification, and access sensitivity.

### `party_relationships`
Workspace-scoped relationship between two parties—authorized representative, employee/contact, household/reference, or tenant-defined role—with effective dates and privacy metadata. Deal-specific roles still use `deal_participants`.

### `leads`
Prospect party, source, interested inventory, assignee, workflow, next action, conversion/loss data.

### `activities`, `tasks`, `appointments`
Timeline entries and assigned work.

## Deals

### `deals`
Deal-type key, location, workflow, currency, owner, dates, line items/totals snapshot, notes, concurrency version.

### `deal_participants`
Deal/party/role such as buyer, seller, dealer buyer, lender, authorized representative, trade-in owner.

### `deal_inventory_units`
Deal/inventory-unit role such as sold unit, purchased unit, trade-in, wholesale unit.

### `trade_ins`
Vehicle facts, owner, allowance, lien/payoff, condition, tax-pack eligibility inputs, resulting inventory-unit link.

### `finance_applications`
External lender, requested/approved amounts, returned rate/term, status, conditions, expiry, reference, funding state; no servicing schedule.

### `payment_transactions`
One-time event: type, amount minor/currency, method, reference, dates, status, proof, actor/approver. Recurring servicing is optional.

## Documents, tax, calculations

### `document_types`
Workspace/pack-defined key, translated name, field schema, workflow, numbering, template, tax/calculation references, activation state.

### `document_template_versions`
Immutable source bundle, engine/renderer version, checksum, locale, field-schema version, approvals.

### `documents`
Preview or official record, number, status, deal/entity links, exact version references, input snapshot, checksum, void/supersede lineage.

### `document_files`
Generated original, signed scan, replacement scan, attachment; provider file, checksum, MIME, version, current flag.

### `calculation_definitions`, `calculation_versions`, `calculation_snapshots`
Declarative AST, schemas, fixtures, approval/activation; immutable run input/output/components/rounding/engine checksum.

### `tax_packs`, `tax_pack_versions`, `tax_calculation_snapshots`
Jurisdiction/effective version, rules/rate sources, approval, calculation inputs/outputs.

### `numbering_definitions`, `number_allocations`
Transactional permanent official-number history.

## Configuration and operations

### `workflow_definitions`, `workflow_versions`, `workflow_states`, `workflow_transitions`, `workflow_instances`, `workflow_events`
Versioned state machines with canonical categories, flags, guards, actor permissions, and event history.

### `custom_field_definitions`, `custom_field_values`
Typed workspace fields. Critical platform fields remain relational.

### `integration_connections`
Provider type, encrypted-credential reference, scopes, status, environment, config, health.

### `external_resources`
Links a Vynlo entity/file to a provider object using connection, remote ID, version/etag, metadata, and drift state.

### `jobs`, `job_attempts`
Durable asynchronous work and attempt/error history.

### `export_definitions`, `export_versions`, `export_runs`, `export_files`
Versioned columns/filters/calculations and generated files.

### `audit_events`, `approval_records`
Append-only history and explicit approval of sensitive actions/versions.

### `workspace_settings`, `workspace_feature_entitlements`, `feature_flags`
Versioned workspace defaults, product capability entitlements, and platform rollout flags. Entitlements and flags are separate concepts and never replace permission checks.

### `installed_packs`
Installed Vynlo starter and tax pack versions with schema/checksum/provenance and activation state.

### `workspace_configuration_versions`, `workspace_configuration_changes`, `workspace_configuration_activations`
Runtime source of truth for approved workspace configuration baselines, their artifact diffs, provenance, approvals, effective dates, and rollback lineage.

### `workspace_configuration_imports`, `workspace_configuration_exports`
Optional portable package operations for seeding, migration, backup, and controlled transfer. Credentials and customer data are excluded.

## Universal field rules

- UUID primary keys.
- Money: signed `bigint` minor units plus ISO currency.
- Rates: exact decimal or basis points, documented per field.
- Timestamps: UTC; render in workspace/location timezone.
- Legal dates: date-only.
- Mutable records: concurrency version and timestamps.
- Historical financial/document/audit records are never silently deleted.
