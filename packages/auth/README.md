# @vynlo/auth

Framework-neutral membership, permission, session, and authentication-assurance policy contracts for the modular monolith.

## Contracts

- `PLATFORM_PERMISSION_KEYS` and `PlatformPermissionKey` are the stable machine keys from `docs/data/PERMISSION_CATALOG.md`.
- `WorkspaceMembership` distinguishes invited, active, suspended, and deactivated memberships and carries the authoritative user-profile status. Effective permissions require both an active membership and an active user profile.
- `resolveEffectivePermissionKeys`, `evaluatePermission`, and `hasEffectivePermission` accept only explicit, workspace-scoped role grants. Role labels and client/JWT claims are not policy inputs; denial results distinguish inactive membership from a missing grant.
- `evaluateNormalSession` enforces the 14-day maximum normal session window.
- `evaluateWorkspaceMfaAccess` requires MFA for administrators and when the workspace requires MFA for every member.
- `evaluateRecentStepUp` requires MFA/AAL2 and treats strong assurance as fresh for 15 minutes, inclusive of the exact boundary.

Authentication timestamps, user-profile status, membership status, and the
administrator designation must be loaded from trusted server-side records or
provider assurance, never an arbitrary request body.

## Traceability

The package unit tests cover `VYN-AUTH-002` through `T-AUTH-002`, `T-AUTH-003`, and `T-AUTH-004`, plus `VYN-SEC-001` through `T-RBAC-001`.

## Compatibility and deferred adapters

This package adds no database migration or API contract. Supabase session/AAL translation, membership/role queries, RLS helpers, route integration, audit events, and UI flows remain adapter/application work. Tenant-private permission namespaces remain database/runtime configuration and are not added to the platform permission union.
