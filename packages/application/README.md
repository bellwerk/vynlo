# @vynlo/application

Tenant-neutral commands, queries, use cases, and transaction coordination.

`resolveWorkspaceContext` derives command ownership from the authenticated user,
an explicit validated route/header workspace selection, and a server-loaded
active membership and active user profile. A request-body workspace is checked
only for consistency and can never become the authoritative workspace context.

This package is an ownership boundary inside the modular monolith, not an independently deployed service. Stage 0 exposes only compile-safe foundations.
