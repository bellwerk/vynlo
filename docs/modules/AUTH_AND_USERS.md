# Authentication, sessions, users, and roles

## Authentication methods

MVP supports invite-only email/password and Google OAuth through Supabase Auth. Public registration is disabled. A workspace may restrict allowed email domains or providers.

## Session policy

- Maximum normal session: 14 days.
- Access tokens are short-lived and refreshed automatically.
- Password change, user deactivation, or administrator revocation terminates sessions.
- Users can view/revoke active sessions when supported.
- No forced short idle logout in platform MVP. A future tenant-configurable local screen lock may protect shared terminals.

## MFA and step-up

- MFA mandatory for workspace admins.
- Workspace setting may require MFA for all roles.
- Step-up required when strong authentication is older than 15 minutes for role/permission changes, credential changes, tax/formula/template activation, document voiding, refunds, sensitive exports, and support access.

## Invite flow

1. Admin enters email, workspace, and role(s).
2. Vynlo creates a time-limited invitation.
3. User authenticates and enrolls MFA when required.
4. Membership activates and an audit event is written.

Shared accounts are prohibited.
