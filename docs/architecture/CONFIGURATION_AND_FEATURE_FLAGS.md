# Configuration, entitlements, and feature flags

Vynlo separates commercial capability, versioned workspace behavior, controlled rollout, and approval-gated production use. These mechanisms are related but not interchangeable.

## 1. Platform constraints

Platform code defines security minimums, supported field types, API/provider contracts, renderer and calculation limits, schema compatibility, and system invariants. A workspace cannot configure around these controls.

## 2. Workspace entitlements

`workspace_feature_entitlements` answers whether a workspace is commercially and operationally allowed to use a capability, for example:

```text
inventory
media
crm
deals
documents
website_publishing
third_party_finance
exports
payment_servicing (future)
collections (future)
```

The UI, API, jobs, and billing/plan checks use one entitlement service. Hiding navigation alone is never authorization.

## 3. Versioned workspace configuration

Workspace configuration defines tenant-owned behavior, including legal entities, locations, roles, custom fields, workflow versions, numbering, document types/templates, calculation definitions, export definitions, and provider mappings. Runtime records in Postgres/object storage are the source of truth.

Configuration can be created through the admin UI, installed from a Vynlo starter/tax pack, or imported from an optional workspace configuration package. Import never activates customer-facing behavior automatically.

## 4. Feature flags

Feature flags control engineering rollout and experiments. They are environment- and optionally workspace-scoped. A flag may disable or gradually expose code, but cannot:

- grant an entitlement;
- bypass permissions or RLS;
- activate a draft document, tax pack, formula, or workflow;
- override an approval gate.

## 5. Activation gates

Legal documents, tax packs, calculation definitions, sensitive exports, and customer-facing provider mappings require exact-version approval and activation records. Availability states are:

```text
not entitled
entitled but not configured
configured draft
validation failed
approval/input missing
preview only
active for production
retired for new use
```

Direct API calls must enforce the same state as the UI.

## 6. MVP admin configuration

Workspace administrators may manage, within permission and schema limits:

- branding, locale, timezone, currency, and media defaults;
- legal entities and locations;
- users, roles, and permissions;
- supported stock-number strategies;
- workflow labels and allowed configuration values;
- typed custom fields;
- document activation and approved template versions;
- provider connections and mappings;
- approved tax-pack selection;
- export definitions and report access.

Full visual document, calculation, workflow, and report builders are later work. Release 1 imports complex configuration through validated definitions and exposes controlled settings rather than arbitrary code.
