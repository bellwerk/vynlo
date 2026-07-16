# Workspace onboarding and provisioning

## Standard onboarding

A normal dealership is onboarded without code changes or a new repository.

### Phase 1 — account and workspace

1. Create organization and workspace.
2. Set default locale, timezone, currency, odometer unit, and country/region.
3. Select the retail-dealer starter pack or a blank configuration.
4. Assign feature entitlements.
5. Create the first workspace administrator and require MFA enrollment.

### Phase 2 — dealership identity

1. Create legal entity and operating brand.
2. Add locations and public contact information.
3. Add approved identifiers with masked/restricted access.
4. Upload branding assets.

### Phase 3 — operating configuration

1. Configure stock numbering.
2. Activate an inventory workflow.
3. Configure roles and invite users.
4. Configure field visibility/requiredness.
5. Assign approved tax pack(s) for applicable contexts.
6. Select or upload document templates and keep them disabled until approved.
7. Configure exports.

### Phase 4 — integrations

1. Connect storage provider.
2. Connect website/listing provider if used.
3. Validate scopes and staging environment.
4. Map external fields/options/locales.
5. Run create/update/unpublish and media smoke tests.

### Phase 5 — migration

1. Inventory source assessment.
2. Dry-run import into staging.
3. Resolve duplicates and missing fields.
4. Reconcile counts, stock values, media, and external listing links.
5. Obtain admin sign-off.
6. Execute production import with a rollback/reconciliation plan.

### Phase 6 — UAT and activation

1. Run role-based UAT on phone, tablet, and desktop.
2. Validate RLS and cross-workspace isolation.
3. Validate document, numbering, tax, export, and provider behavior.
4. Confirm backup/restore and incident contacts.
5. Activate approved features.

## Drivven onboarding

Drivven uses the same process, with `tenant-seeds/drivven` as a bootstrap and migration source. The seed imports draft versions. Production activation still requires runtime approvals and encrypted provider connections.

## Provisioning invariants

- No default legal document is activated automatically.
- No tax pack is activated without jurisdiction/context selection and approval state.
- No production provider ID or credential is read from Git.
- No tenant can be created without an isolated workspace.
- No user can access a workspace before active membership and permission assignment.
- Every import and activation produces an audit event and a reversible plan where possible.

## Offboarding/export

Before public SaaS launch, implement an authorized workspace export that includes configuration, business data, metadata, and file manifests while excluding platform secrets and other workspaces. Suspension must revoke interactive and provider access without destroying retained records.
