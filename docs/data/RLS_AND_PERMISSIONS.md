# Row-Level Security and permissions

Authorization is the intersection of authenticated identity, active workspace membership, granted permission, entity/business guard, and step-up authentication where required.

Stable permission keys are defined in `PERMISSION_CATALOG.md`. Representative keys include:

```text
inventory.read
inventory.create
inventory.update
inventory.archive
listings.publish
costs.read
costs.create
crm.read
crm.update
deals.create
deals.close
documents.preview
documents.generate_approved
documents.void
configuration.manage
integrations.manage
exports.run
users.manage
audit.read
```

## RLS principles

- Enable RLS on every exposed table.
- `SELECT`: active workspace membership and appropriate read permission.
- `INSERT`: creation permission; ownership/audit fields cannot be spoofed.
- `UPDATE`: permission plus immutable workspace ownership and `WITH CHECK`.
- `DELETE`: generally disallowed for financial/document/audit rows; use archive/void commands.
- Service role only in server/worker code after explicit workspace validation.

Sensitive identifiers and contract files require stronger permissions than basic customer read and should be omitted/masked in unauthorized responses.

For every table test same-workspace permission, cross-workspace denial, inactive membership, missing permission, ownership spoofing, service context, and audit immutability.
