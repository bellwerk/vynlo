# RLS policy matrix

**Status:** Normative policy design. SQL migrations must implement equivalent behavior and tests.

## Trusted helper functions

Functions run with fixed search path and minimal `SECURITY DEFINER` only where necessary:

```text
app.current_user_id() -> uuid
app.has_active_membership(workspace_id uuid) -> boolean
app.has_permission(workspace_id uuid, permission_key text) -> boolean
app.auth_assurance_at_least(level text) -> boolean
app.entity_belongs_to_workspace(entity_table text, entity_id uuid, workspace_id uuid) -> boolean
```

Permission helpers derive user identity from `auth.uid()` and server-maintained membership/role rows. They never trust JWT custom claims as the sole current authorization source.

## Universal workspace policy

For a normal workspace table `t`:

```sql
ALTER TABLE t ENABLE ROW LEVEL SECURITY;
ALTER TABLE t FORCE ROW LEVEL SECURITY;

CREATE POLICY t_select ON t
FOR SELECT
USING (
  app.has_active_membership(workspace_id)
  AND app.has_permission(workspace_id, '<entity>.read')
);

CREATE POLICY t_insert ON t
FOR INSERT
WITH CHECK (
  app.has_active_membership(workspace_id)
  AND app.has_permission(workspace_id, '<entity>.create')
);

CREATE POLICY t_update ON t
FOR UPDATE
USING (
  app.has_active_membership(workspace_id)
  AND app.has_permission(workspace_id, '<entity>.update')
)
WITH CHECK (
  app.has_active_membership(workspace_id)
  AND app.has_permission(workspace_id, '<entity>.update')
);
```

Application commands additionally prevent workspace ID changes, enforce expected version, validate fields and state, and write audit.

## Table policy matrix

| Table group | Select | Insert | Update | Delete |
|---|---|---|---|---|
| organizations/workspaces | membership/support policy | provisioning service | admin/manage | prohibited; close command |
| memberships/roles | member can see safe roster; admin full | users.manage | users.manage + step-up | deactivate/unassign command |
| legal entities/locations/brands | member or configured permission | settings.manage | settings.manage | retire/deactivate |
| legal identifiers | restricted permission; masked view otherwise | settings.manage + step-up | version/replace + step-up | prohibited |
| workspace settings/entitlements | configuration read | configuration.manage | versioned update; entitlement source restrictions | prohibited |
| workspace configuration versions/changes | configuration read | import/admin configuration service | lifecycle command only | prohibited |
| configuration imports/exports/activations | configuration read | configuration/import/export service | system/lifecycle status only | prohibited |
| starter/tax pack installations | configuration read | pack service | lifecycle command | prohibited |
| vehicles/inventory units | inventory.read | inventory.create | inventory.update | prohibited; archive |
| costs | costs.read | costs.edit | draft only | posted entry prohibited; reverse |
| media | inventory/media read | media.create | metadata/order/cover permission | archive; file retention job |
| listings | listings.read | system/application command | application/provider job | disable/unpublish command |
| parties/CRM | crm.read | crm.create | crm.update | archive/anonymize policy |
| party identifiers | restricted permission | restricted permission | replace/version | prohibited |
| deals/trade-ins/finance | deals.read | deals.create | state/field permission | cancel/close, no hard delete after history |
| payment transactions | payments.read | payments.record | draft only | prohibited; reverse/refund |
| document definitions | config read | configuration.manage | new version only | retire |
| documents/files | documents.read | application command/upload permission | lifecycle command only | prohibited |
| calculations/tax snapshots | permitted owning entity read | application engine only | prohibited | prohibited |
| workflow events | owning entity read | transition service only | prohibited | prohibited |
| integrations | integrations.read; credentials never returned | integrations.manage + step-up | integrations.manage + step-up | disable |
| jobs | operations.read or own user-safe jobs | server only | worker/admin command | prohibited |
| exports | exports permission | exports.run | system status only | expire file |
| approvals | approval read | approver permission + step-up | prohibited | prohibited |
| audit events | audit.read | trusted audit function only | prohibited | prohibited |
| reusable starter/tax pack versions | configuration read | pack service | lifecycle command | prohibited |

## Append-only tables

No user UPDATE/DELETE policies:

```text
stock_number_allocations
number_allocations
workflow_events
calculation_snapshots
tax_calculation_snapshots
job_attempts
approval_records
audit_events
posted/reversal payment records
official document input/version snapshots
workspace_configuration_activations
workspace_configuration_changes after activation
```

Service routines may append only. Retention/partition operations run under dedicated audited maintenance identity.

## File access

File bytes are not directly public. API validates workspace, entity/file role, permission, and retention before issuing a short-lived signed URL or streaming. Restricted identity and signed-document files require dedicated permission. Public listing derivatives use a separate explicit public-publish path containing no customer metadata.

## Public listing read model

If Vynlo later hosts public listings, use a dedicated sanitized projection/table populated by a job. Do not expose operational inventory tables to anonymous RLS.

## Service and worker access

The service role is never in browser code. Each server/worker command:

1. authenticates caller or trusted job;
2. loads authoritative workspace/entity;
3. verifies membership/permission or job provenance;
4. scopes all queries explicitly;
5. writes correlation/audit;
6. uses least-privilege provider credential.

## Mandatory RLS tests per table

- allowed same-workspace select/write;
- denied different workspace;
- inactive membership;
- missing permission;
- attempted workspace reassignment;
- attempted foreign-key link to other workspace;
- restricted field/file;
- append-only update/delete;
- service command with wrong workspace/job provenance;
- absence/non-disclosure returns.

No table is considered complete until its negative matrix is automated.
