# Multi-tenancy

```text
organization
└── workspace (RLS/data boundary)
    ├── legal entities
    ├── brands
    ├── locations
    ├── members/roles
    ├── inventory/deals/documents
    ├── integrations
    ├── installed starter/tax pack versions
    └── workspace configuration versions
```

An organization may own several workspaces. A workspace may contain several legal entities, brands, locations, currencies, and languages. Drivven MVP uses one workspace, one legal entity, one brand, two locations, and CAD.

## Isolation rules

- Every workspace-owned row has `workspace_id` directly unless inherited through an immutable parent and explicitly justified.
- Composite uniqueness includes `workspace_id`.
- API handlers obtain workspace context from authenticated membership, never a trusted client-supplied ID alone.
- Background jobs validate `workspace_id` before every query/provider operation.
- Storage paths, cache keys, rate-limit keys, logs, and exports are workspace-scoped.
- Platform support access requires approval, reason, expiration, and audit.

## Provisioning

1. Create organization and workspace.
2. Create owner membership.
3. Apply starter pack and create/import validated workspace configuration.
4. Create legal entity, brand, locations, roles, workflows, entitlements, and settings.
5. Connect integrations through OAuth or encrypted credentials.
6. Activate approved tax/document/formula versions.

Workspace suspension disables sign-in and jobs without deleting data. Export, retention, legal hold, and controlled deletion are separate workflows.
