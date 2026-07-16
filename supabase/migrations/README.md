# Database migrations

Migrations are forward-only and timestamped. `20260715120000_tenancy_identity_foundation.sql`
implements the database portion of VYN-AUTH-001, VYN-AUTH-002, VYN-TEN-001,
VYN-SEC-001, and VYN-AUD-001.

The migration creates production identity/RBAC tables, fixed-search-path
authorization helpers, forced RLS policies, cross-workspace composite foreign
keys, lifecycle-only records, narrow browser column grants, derived actor fields,
automatic workspace settings versions, and the append-only audit primitive.
`app.write_audit_event` is executable only by `service_role`; browser roles can
only read audit rows when `audit.read` is effective. Global platform permission
keys are migration-owned, while workspace-private permissions remain namespaced
runtime records that cannot shadow platform keys and are audited on change.

This is an additive migration from Stage 0. It does not consume or transform the
disposable `stage0.synthetic_workspaces` projection. Rollback is application
rollback plus a reviewed forward corrective migration; do not drop identity or
audit history in a down migration.

`20260716150000_invite_only_auth.sql` completes the invitation persistence/API
command path: recent-AAL2 `users.manage` creation, immutable role snapshots,
atomic `auth.invitation.deliver` enqueue, matching confirmed-email acceptance,
active profile/membership/role provisioning, append-only idempotency history,
and a lease-bound service delivery read. GoTrue remains the only owner of invite
tokens; new invitation rows store no token hash and job payloads contain only the
invitation UUID.
