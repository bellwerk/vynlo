# Workspace configuration architecture

## Purpose

Workspace configuration allows each dealership to customize Vynlo without creating a repository, branch, deployment, or code fork.

## Runtime source of truth

The authoritative configuration is stored in Postgres and secure object storage. It is grouped into immutable versions and activated through audited commands.

Core records:

```text
workspace_settings
workspace_feature_entitlements
workspace_configuration_versions
workspace_configuration_changes
workspace_configuration_activations
workspace_configuration_imports
workspace_configuration_exports
approval_records
```

Domain-specific versioned records remain in their own tables:

```text
workflow_definitions / workflow_versions
document_types / document_template_versions
calculation_definitions / calculation_versions
numbering_definitions
export_definitions / export_definition_versions
custom_field_definitions / custom_field_versions
integration_connections / integration_mappings
tax_pack_assignments
```

## Configuration lifecycle

```text
draft
-> schema validation
-> dependency validation
-> automated fixture/tests
-> review
-> approved
-> scheduled/active
-> retired
```

An active version is immutable. Editing creates a new draft version. Rollback reactivates an earlier compatible version while historical records continue to reference the version originally used.

## Workspace entitlements

Entitlements determine which product capabilities a workspace may access. They are not tenant-specific source-code modules.

Initial entitlement keys:

```text
inventory
media
crm
deals
one_time_payments
documents
website_publishing
third_party_finance
exports
custom_workflows
tenant_calculations
```

Future keys may include marketplace, payment servicing, collections, digital signatures, and accounting integrations.

UI navigation, API authorization, jobs, and billing checks must use the same entitlement service. A disabled capability may not be invoked by manually calling an API.

## Safe admin configuration in Release 1

Workspace administrators may manage:

- branding, locale, timezone, currency, and units;
- legal entities and locations;
- users, roles, and permitted role assignments;
- active approved workflows/statuses;
- basic field visibility and requiredness;
- numbering starting values before first allocation;
- integration connections and website field mappings;
- activation of approved templates, formulas, exports, and tax assignments.

They may not:

- run arbitrary code;
- bypass RLS, audit, or immutable history;
- alter an already generated official document;
- change an activated version in place;
- enable an artifact whose required approval or compatibility check is missing.

## Portable configuration packages

A portable workspace configuration package is optional and used for:

- development/demo workspaces;
- repeatable first-tenant provisioning;
- complex migrations;
- staging-to-production promotion;
- disaster recovery of configuration;
- source-reviewed enterprise onboarding.

It is not required for normal SaaS onboarding.

A package may include:

- non-secret legal entity/location seed data;
- roles and field definitions;
- workflows;
- numbering definitions;
- document and template source bundles;
- tenant calculations and synthetic fixtures;
- export definitions;
- symbolic integration mappings;
- migration metadata.

A package must not include:

- credentials, tokens, private keys, or service-account files;
- customer/lead/deal records;
- signed documents;
- identity documents;
- production exports;
- unrestricted executable code.

Import process:

1. Parse and validate against `schemas/workspace-config-package.schema.json`.
2. Verify checksums and supported platform/schema versions.
3. Resolve dependencies and symbolic references.
4. Produce a human-readable diff and impact plan.
5. Run fixtures and compatibility tests in staging.
6. Require appropriate approval.
7. Install draft versions.
8. Activate explicitly; never auto-activate legal/financial artifacts.
9. Record provenance and audit events.

## Drivven seed

`tenant-seeds/drivven` is the initial portable configuration package for the first workspace. It exists for reproducible development, migration, and UAT. Vynlo runtime code reads only installed database versions, not files from this directory.

## New-tenant rule

Creating a new dealership normally requires only:

```text
organization/workspace creation
starter-pack selection
jurisdiction/tax assignment
legal entity and locations
users and roles
branding and field settings
workflow and document activation
integration connections
inventory import
UAT and activation
```

It does not require a repository, branch, application deployment, or code modification.
