# Milestone 1 tenancy and identity foundation

**Recorded:** 2026-07-16

**Status:** Foundation code present; database runtime acceptance pending

**Scope:** Tenancy, identity, authorization, assurance, and audit foundations only

## Scope boundary

This document records the first foundation slice of
[Milestone 1](./IMPLEMENTATION_PLAN.md). It does not claim that Milestone 1 is
complete. Feature entitlements and full immutable configuration-version
records, the PWA/localization shell, outbox/jobs, inventory, parties/deals,
document preview, and invite delivery were implemented as separate Milestone 1
source deliveries and are joined in
[the end-to-end record](MILESTONE_1_END_TO_END.md).

The normative requirement and test IDs come from
[requirements traceability](../03_REQUIREMENTS_TRACEABILITY.md) and the
[test case catalog](../testing/TEST_CASE_CATALOG.md). Authentication behavior is
also constrained by [Authentication, sessions, users, and roles](../modules/AUTH_AND_USERS.md),
while database authorization follows
[Row-Level Security and permissions](../data/RLS_AND_PERMISSIONS.md) and the
[permission catalog](../data/PERMISSION_CATALOG.md).

Status terms in this document mean:

- **Implemented:** source and local non-Docker checks exist for this slice.
- **Runtime pending:** the implementation requires an executed Supabase reset
  and pgTAP result before acceptance.
- **Partial:** only part of the stated requirement or test case is implemented.
- **Deferred:** no completion claim is made in this slice.

## Implemented scope

### Database and local authentication configuration

The additive
[tenancy identity migration](../../supabase/migrations/20260715120000_tenancy_identity_foundation.sql)
introduces:

- `organizations` as the commercial boundary and `workspaces` as the operational
  and RLS boundary;
- user profiles, workspace memberships, roles, platform/workspace permissions,
  role grants, membership-role assignments, invitations, invitation-role
  assignments, and audit events;
- composite workspace foreign keys and immutable ownership columns that reject
  cross-workspace links or workspace reassignment;
- narrow browser column grants and database-derived actor/lifecycle fields that
  prevent ownership, grant, and timestamp spoofing;
- lifecycle state in place of hard deletion for all eleven exposed foundation
  tables;
- 75 immutable platform permission keys, with workspace-private keys retained as
  namespaced runtime records that cannot shadow platform keys;
- fixed-search-path authorization helpers for current identity, active
  membership, effective permission, AAL, recent strong authentication,
  organization access, profile visibility, permission visibility, and trusted
  audit append;
- forced RLS and explicit grants for all eleven exposed tables, with invitation
  token hashes excluded from browser reads and invitation writes restricted to
  trusted commands;
- serialized MFA invariants for administrative grants and permission
  reactivation, plus guarded membership/invitation lifecycle transitions;
- automatic, non-writable `settings_version` advancement for workspace setting
  changes;
- audit triggers for workspace, membership, role/grant, workspace-scoped
  permission, and invitation mutations, with invitation token hashes removed
  from audit snapshots and stale pooled JWT claims ignored for service writes;
  and
- a service-role-only append function plus update/delete rejection for audit
  rows.

[Supabase configuration](../../supabase/config.toml) disables public signup and
sets the local normal-session timebox to 336 hours (14 days). Production Supabase
settings are external state and are not proven by this repository value.

The [synthetic seed](../../supabase/seed.sql) retains the Stage 0 compatibility
projection and adds two fictional organization/workspace boundaries, generated
unknown password hashes, deterministic lifecycle timestamps that support an
idempotent second seed execution, active/limited/deactivated memberships,
MFA-marked administrator roles, and explicit grants. It contains no provider
identity that permits interactive login and no tenant production data.

### Application and authentication policy contracts

The framework-neutral `@vynlo/auth` package now provides:

- shared membership and user-profile status contracts; authorization requires
  both records to be active;
- the stable platform permission-key union;
- effective-permission resolution from active membership and explicit
  workspace-scoped role grants, without accepting role labels or client/JWT
  permission claims;
- a maximum 14-day normal-session decision;
- MFA-required workspace access for administrators or workspaces configured to
  require MFA for every member; and
- a recent-step-up decision that requires AAL2 and strong authentication no more
  than 15 minutes old.

The `@vynlo/application` package exposes an authoritative workspace-context
resolver. It requires an authenticated user, a server-validated route/header
workspace selection, and exactly one active matching membership whose user
profile is also active. A request-body workspace may be checked for consistency
but cannot become the authority.

### Test assets

The TypeScript suites in
[auth policy tests](../../packages/auth/src/auth-policy.test.ts) and
[workspace-context tests](../../packages/application/src/workspace-context.test.ts)
cover policy boundaries, denial reasons, invalid timestamps, inactive user and
membership states, cross-workspace grants, spoofed body workspace IDs, and
duplicate membership invariants.

The [pgTAP RLS suite](../../supabase/tests/001_tenancy_identity_rls.test.sql)
declares 83 assertions covering schema/helper presence, same-workspace access,
cross-workspace read/write/link denial, inactive user/membership states, missing
permission, platform-key shadow rejection, serialized MFA invariants, derived
ownership fields, workspace setting-version advancement, stale and future
step-up denial, invitation token/lifecycle restrictions, trusted pooled audit
attribution, profile/organization lifecycle audit, service-only audit append,
audit non-disclosure, and audit immutability. The suite is authored but has not
been executed in this local environment.

## Acceptance IDs

| Acceptance ID | Criterion | Current evidence | Result |
|---|---|---|---|
| `M1-TEN-AC-001` | Organization and workspace identity records preserve the organization boundary, and every workspace-owned identity/RBAC relationship is constrained to one `workspace_id`. | Additive migration, composite foreign keys, immutable ownership triggers, and two-workspace seed. | Implemented; runtime pending. |
| `M1-TEN-AC-002` | Authoritative workspace context is derived from authenticated identity plus one active server-loaded membership and active user profile; body/header spoofing, inactive state, and ambiguous membership fail closed. | Application resolver, strict API command routes, body/header spoof tests, RLS helpers, and pgTAP cases. | Source integrated; database runtime pending. |
| `M1-TEN-AC-003` | Every exposed foundation table has forced RLS; effective permissions use immutable keys and active role grants; missing, shadowed, or cross-workspace grants never authorize. | Eleven forced-RLS tables, platform-key shadow guard, locking invariant guards, explicit grants, auth unit tests, and pgTAP cases. | Implemented; runtime pending. |
| `M1-TEN-AC-004` | Public signup is disabled, normal sessions cannot exceed 14 days, administrator/workspace MFA rules are enforced, and sensitive changes require strong authentication no older than 15 minutes. | Supabase local config, TypeScript policy contracts/tests, MFA role invariants, RLS assurance helpers, and pgTAP cases. | Partial: provider adapters, deployed settings, enrollment, revocation, and E2E proof remain. |
| `M1-TEN-AC-005` | A time-limited invitation can be created for workspace role assignments, accepted only by its matching identity/membership, and activated with an audit event; non-invited registration is rejected. | Trusted invitation create/accept RPCs and API, GoTrue-managed delivery job/worker, matching-email provisioning, invitation login context, public-signup-off local config, and [invite-only auth traceability](MILESTONE_1_INVITE_ONLY_AUTH.md). | Source integrated; live Auth/SMTP/callback/database acceptance pending. |
| `M1-TEN-AC-006` | Authorized privileged mutations and policy rejections produce workspace-scoped, append-only audit events that browser callers cannot forge or mutate. | Audit schema, mutation triggers, pooled-role attribution guard, trusted append function, RLS, grants, and pgTAP event-shape/immutability cases. | Partial: durable audit of application/policy rejections and assertions for each sensitive command remain. |
| `M1-TEN-AC-007` | A clean database reset applies the migration and seed, then all tenancy/RLS pgTAP assertions pass against the exact revision under review. | Migration, compatible seed, 83-assertion pgTAP suite, and GitHub database job definition. | Runtime pending; no local Docker execution. |
| `M1-TEN-AC-008` | `/api/v1`, Server Actions, and responsive English/French UI flows call the same application/auth policies and expose localized, accessible denial and recovery states. | Strict invitation/vertical-slice routes and application services; invitation/login/MFA/operations UI; catalog, route, and mocked Playwright tests. | Source integrated; live end-to-end runtime pending. |

## Requirement and test traceability

| Requirement or test | Current implementation evidence | Completion statement |
|---|---|---|
| `VYN-AUTH-001` | Public signup is disabled locally; atomic invitation/delivery persistence, authenticated create/accept APIs, matching-email membership activation, audit evidence, and invitation/login UI source exist. | Traced in [Milestone 1 invite-only authentication](MILESTONE_1_INVITE_ONLY_AUTH.md); deployed provider verification and a live journey remain. |
| `T-AUTH-001` | Database/application/worker tests cover invite creation, delivery state, mismatch/expiry/terminal denial, and matching-user activation; mocked browser tests cover invitation routing and commands. | Partial; provider staging and live invite callback/public-signup E2E are still required before closing the test. |
| `VYN-AUTH-002` | The auth package, local 336-hour session timebox, SQL AAL/recent-auth helpers, MFA role invariants, and sensitive RLS policies implement the policy foundation. | Partial through `M1-TEN-AC-004`; deployed provider enforcement and end-to-end assurance remain. |
| `T-AUTH-002` | Auth unit tests cover administrator/workspace-wide MFA; pgTAP covers AAL1 denial for an administrator and non-MFA admin-role rejection. | Unit evidence passes; database runtime pending. |
| `T-AUTH-003` | Auth unit tests cover the exact 14-day boundary, overlong windows, revocation, not-yet-valid sessions, and inactive user profiles; pgTAP denies a deactivated profile despite an active membership. | Unit evidence passes; provider/runtime session revocation remains. |
| `T-AUTH-004` | Auth unit tests cover missing, stale, exact-boundary, future-dated, and fresh step-up; pgTAP applies the same boundary to role management. | Unit evidence passes; database runtime and E2E re-authentication remain. |
| `VYN-TEN-001` | Workspace-composite constraints, forced RLS, two-workspace seed, SQL helpers, and authoritative application context exist. | Partial through `M1-TEN-AC-001` to `M1-TEN-AC-003`; this slice covers identity/RBAC rows only. |
| `T-TEN-001` | Application tests deny inactive/other-user memberships; pgTAP covers cross-workspace reads, inserts, links, audit reads, and ownership spoofing. | Unit evidence passes; database runtime pending. |
| `T-TEN-002` | Application and route tests reject body workspace authority, missing/invalid workspace headers, and extra identity/provider fields. | Source evidence passes; database runtime remains. |
| `T-TEN-003` | Later outbox/job and preview-artifact rows preserve workspace context; Storage reads require an exact visible artifact bucket/path match; worker logs preserve validated workspace IDs without payloads. | Source integrated for jobs and preview files; live RLS/Storage/log proof remains. |
| `VYN-SEC-001` | Stable permission keys, active membership/role/grant evaluation, fixed-search-path SQL helpers, forced RLS, and explicit grants exist. | Partial through `M1-TEN-AC-003`; runtime RLS proof remains. |
| `T-RBAC-001` | Auth unit tests reject labels/client claims and cross-workspace grants; pgTAP covers explicit/missing grants, private-key shadow denial, key immutability, and permission-reactivation MFA enforcement. | Unit evidence passes; database runtime pending. |
| `VYN-AUD-001` | Workspace-scoped audit rows, mutation triggers, service-only append, RLS reads, and update/delete prevention exist. | Partial through `M1-TEN-AC-006`; approvals and comprehensive rejection events remain. |
| `T-AUD-001` | pgTAP asserts browser/service actor shape, stale pooled-claim rejection, trusted append, browser-forgery denial, scoped read, and update/delete rejection. | Partial and runtime pending; rejected-command persistence still needs dedicated assertions. |

## RLS, permission, and audit behavior

### RLS and grants

RLS is enabled and forced on `organizations`, `workspaces`, `user_profiles`,
`workspace_memberships`, `roles`, `permissions`, `role_permissions`,
`membership_roles`, `workspace_invitations`, `workspace_invitation_roles`, and
`audit_events`.

The policies have these intended properties:

- anonymous access is revoked;
- organization and workspace reads derive from active membership and effective
  permission;
- administrative inserts/updates require the relevant immutable permission key
  and recent strong authentication, and narrow column grants exclude ownership,
  actor, lifecycle timestamp, and version fields;
- profile and membership visibility is limited to self or an authorized shared
  workspace;
- organization browser reads exclude internal billing metadata;
- workspace-private permissions cannot be attached across workspaces;
- role and membership relationships use composite workspace foreign keys;
- browser roles cannot append audit events; and
- direct hard deletion is prohibited, with lifecycle status used for correction
  and deactivation.

Every security-definer helper fixes `search_path` and is explicitly granted only
to the roles that need it. Application and worker adapters must still validate
workspace context before using any service-role capability; service-role access
is not a substitute for authorization.

### Permission behavior

Authorization depends on active organization, workspace, user profile,
membership, role, role-grant, and permission state. Role names and labels have
no authorization meaning. Administrator permissions require an MFA-marked role.
Permission and role rows are locked in a consistent order so concurrent grant,
role, and permission-status changes cannot bypass that invariant.

The TypeScript contracts are policy inputs, not trusted data loaders. Adapters
must load membership, role, grant, provider assurance, and timestamps from
server-side records and must not deserialize them from an arbitrary request
body.

### Audit behavior and limit

The migration automatically records successful inserts/updates for workspace,
membership, role/grant, and invitation records, plus per-workspace organization
and user-profile lifecycle events. Pooled service writes ignore stale JWT actor
and assurance claims. It also exposes a trusted append function for
application/worker events and prevents updates/deletes even for a database-owner
test context. `audit.read` remains workspace-scoped.

A failed SQL statement rolls back its own transaction, so the current database
triggers cannot provide durable evidence of every denied command. The
application boundary must emit the specified rejection event through a reviewed
trusted path after a policy denial, including request/correlation ID, actor,
workspace, action, assurance, and safe reason metadata. Tests must prove the
rejection event without storing invitation tokens, credentials, or sensitive
request payloads.

## Migration, compatibility, and rollback

### Forward migration

The timestamped migration is forward-only. It creates `citext` and `pgcrypto`
when absent, then adds new schemas, tables, indexes, constraints, functions,
triggers, policies, grants, comments, and platform permission rows. It does not
alter or consume existing application-domain rows because Stage 0 had no
production tenant schema.

Before merge, a clean Supabase reset must prove that the migration, seed, and
test suite run in order. An already-applied migration must never be edited;
corrections require a later timestamped migration.

### Compatibility

- The migration is additive relative to Stage 0.
- The seed retains `stage0.synthetic_workspaces` with the same two stable IDs so
  legacy Stage 0 consumers remain compatible while they migrate to
  `public.workspaces`.
- No `/api/v1` schema is changed, so there is no client contract break in this
  slice.
- Application deployment may roll back independently because no existing route
  depends on the new tables yet. The added database objects must remain in place
  for history and forward compatibility.
- Future schema consumers must deploy only after the target environment reports
  this migration applied.

### Rollback and recovery

Do not add a destructive down migration for identity or audit history. If a
defect is found before shared deployment, repair the branch and recreate the
local database. If it is found after deployment:

1. stop or feature-disable the affected write path;
2. roll back the application if that safely removes the caller;
3. ship a reviewed forward corrective migration that preserves workspace,
   membership, invitation, grant, and audit history;
4. re-run cross-workspace, permission, assurance, and audit tests; and
5. use database restore/PITR only under the environment recovery runbook when a
   forward repair cannot preserve integrity.

## API and UI applicability

This foundation migration changed no route or screen, but later source
increments now integrate it through strict `/api/v1` commands and the
English/French invitation, login, MFA, workspace, operations, denial, and retry
states. Identity comes from the bearer session, workspace selection comes from
the validated header, and strict bodies reject workspace/user/provider-token
authority. Route/application tests cover safe error mapping and spoofing;
Playwright covers mobile/desktop/accessibility behavior and a mocked invitation
operations flow.

This is source evidence only. A real invited-user callback, provider assurance,
membership/RLS evaluation, MFA enrollment, session revocation, and complete
cross-workspace browser run remain in
[runtime acceptance](MILESTONE_1_END_TO_END.md#runtime-acceptance-pending).

## Telemetry and operations

This foundation migration introduced no durable job or provider call. Later
invitation and preview increments now use the outbox/worker lifecycle and its
safe retry/dead-letter telemetry. Database audit rows remain compliance
evidence, not a substitute for operational telemetry.

Adapters must add structured, secret-safe telemetry for workspace-context
denials, inactive membership, missing permission, MFA/step-up requirements,
invitation lifecycle failures, session revocation, trusted-audit failures, and
database policy errors. Logs and metrics must preserve `workspace_id` only after
membership validation and include request/correlation IDs. Alert thresholds and
runbook links are still required before production activation.

Operational checks for this slice are:

```sh
pnpm exec vitest run packages/auth/src packages/application/src
pnpm check:supabase
pnpm supabase:start
pnpm db:reset
pnpm test:db
pnpm check:supabase:runtime
```

## Verification record and remaining evidence

### Local evidence recorded on 2026-07-16

- Node.js `24.18.0` and pnpm `11.13.0` were active.
- The targeted Vitest command passed 2 files and 15 tests.
- `pnpm check:supabase` passed the structural gate for 11 forced-RLS tables, 75
  platform permission keys, two synthetic workspaces, and the declared
  83-assertion pgTAP plan.
- `pglast` 8.2 parsed the migration, seed, and pgTAP files with PostgreSQL 17
  grammar.
- `pnpm validate` passed formatting, lint, typecheck, 6 unit-test files/29 tests,
  specification, OpenAPI, Markdown, package-boundary, secret, Supabase
  structural, build, and dependency-audit gates.
- `docker version` failed because the Docker command is unavailable in this
  environment.

Consequently, local evidence does **not** prove that Postgres accepts the
migration, that the seed executes, that RLS evaluates correctly, or that the 83
pgTAP assertions pass. Static parsing and unit tests are not substitutes for
database execution.

### GitHub runtime evidence required before acceptance

Acceptance requires evidence tied to the exact reviewed commit:

1. `quality / validate` passes formatting, lint, TypeScript, unit, spec, OpenAPI,
   Markdown, boundary, secret, static database, dependency, build, and browser
   gates.
2. `quality / database-smoke` starts Supabase and completes `pnpm db:reset`,
   proving that the timestamped migration and seed execute on a clean database.
3. The GitHub database job executes `pnpm test:db`, including
   `pnpm exec supabase test db`, and records all 83 pgTAP assertions passing.
   Merely starting or resetting Supabase is insufficient for
   `M1-TEN-AC-003`, `M1-TEN-AC-006`, or `M1-TEN-AC-007`.
4. The runtime log confirms two isolated synthetic workspaces and no test uses a
   known credential or production tenant data; the runtime checker also applies
   the seed a second time and must remain green.
5. The PR records the exact commit SHA and links the successful run. A rerun on
   another revision does not satisfy acceptance.

Production readiness additionally requires live verification that public signup
is disabled, the 14-day session maximum is configured, MFA/provider settings are
correct, migrations are applied, service credentials remain server-only, and
alerts/runbooks exist. Those environment checks are not satisfied by local or
GitHub source validation.

## Explicit follow-ups

1. Obtain a green exact-head `quality / database-smoke` run and capture the
   83-assertion pgTAP result in the PR evidence.
2. Complete provider-staging and browser E2E for invite/OTP callback,
   matching-user activation, and public-signup rejection, then close
   `T-AUTH-001`.
3. Verify the implemented Supabase session/AAL and MFA enrollment/challenge UI
   against the deployed provider; add password/deactivation revocation, recent
   re-authentication UX, and session management.
4. Define and test durable rejection-audit behavior and exact event shapes for
   every sensitive command so `T-AUD-001` is complete.
5. Add aggregate row-version columns and expected-version/`If-Match` command
   paths before exposing mutable identity/RBAC APIs; `settings_version` covers
   only workspace setting changes in this slice.
6. Extend the workspace ownership/isolation already implemented for jobs and
   preview files to exports, search, caches, and future external mappings, then
   complete `T-TEN-003` with live evidence.
7. Add structured telemetry, alerts, operational runbooks, and deployed
   Supabase configuration checks before production activation.
