# Database tests

`001_tenancy_identity_rls.test.sql` is the 83-assertion pgTAP suite for
T-AUTH-002, T-AUTH-003, T-AUTH-004, T-TEN-001, T-RBAC-001, and T-AUD-001. It
verifies inactive user/membership denial, missing permissions, AAL2 and
15-minute step-up behavior, cross-workspace reads/writes/links, protected actor
fields, workspace settings versions, invitation lifecycle/token controls,
permission-key/MFA invariants, lifecycle-only deletion, scoped audit attribution,
service-only audit append, non-disclosure, and audit immutability.

Run against a local Supabase stack:

```sh
pnpm supabase:start
pnpm supabase:reset
pnpm exec supabase test db
```

The seed contains two fictional, deterministic workspace boundaries:

- `10000000-0000-4000-8000-000000000001` — Northstar Motors Test
- `20000000-0000-4000-8000-000000000002` — Harbour Auto Lab

Fixture Auth users have no provider identity row, and every password hash is
generated from a random unknown value. Tests authenticate them by setting
transaction-local Supabase JWT claims; they cannot be used for interactive login
with a known credential. The runtime checker reapplies the seed once to prove
idempotent fixture setup before validating counts.
