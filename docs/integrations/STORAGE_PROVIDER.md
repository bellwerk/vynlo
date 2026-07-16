# Storage provider

Vynlo managed storage uses Supabase Storage or equivalent private object storage. Workspaces may connect external providers such as Google Drive.

Interface:

```text
createContainerOrFolder
listChildren
putFile/getFile
move/rename/copy
softDelete/restore when supported
getMetadata/checksum/version
createTimeLimitedDownload
watchOrReconcileChanges
```

Rules:

- No permanent public customer/contract links.
- Paths and metadata are workspace-scoped.
- Uploads enter quarantine before validation/scan.
- Failure is a job state, not a lost side effect.
- Manual external changes are reconciled according to policy.
- Signed/legal originals are immutable from Vynlo; provider-side replacement creates a conflict.
