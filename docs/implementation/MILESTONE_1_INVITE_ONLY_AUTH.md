# Milestone 1 invite-only authentication

## Outcome

This slice implements the persistence and authenticated API half of
`VYN-AUTH-001`. A recent-AAL2 workspace administrator with the immutable
`users.manage` permission can create one time-limited pending invitation for a
validated email and an explicit set of active workspace roles. The same
transaction appends command history and queues durable delivery work.

After GoTrue establishes an authenticated session, the matching confirmed email
can accept the invitation without already having a workspace membership. The
trusted command atomically provisions an active user profile, active membership,
active role assignments, terminal invitation acceptance, idempotency history,
and audit evidence.

Public registration remains disabled in `supabase/config.toml`. GoTrue owns all
provider invite tokens. Vynlo never persists or returns a raw provider token.

## Scope

Implemented in this slice:

- forward migration `20260716150000_invite_only_auth.sql`;
- append-only invitation create/accept command history;
- recent-AAL2 `users.manage` invitation creation;
- validated, normalized email, locale, expiry, and role input;
- atomic outbox/job enqueue with a non-PII payload;
- lease-bound worker reload of the authoritative invitation;
- matching-email acceptance before membership exists;
- atomic active profile, membership, role, invitation, and audit persistence;
- application contracts and strict RPC response validation;
- thin authenticated `/api/v1` command routes using the public PostgREST key;
- pgTAP and unit/route negative matrices.

Not implemented in this slice:

- live browser/provider end-to-end execution of `T-AUTH-001`;
- deployed Supabase Auth settings verification;
- invitation revoke/expire administrator commands or scheduled expiry sweeps;
- deployed MFA/session recovery flows and operational recovery evidence.

Subsequent source integration adds the strict OpenAPI operations and the
English/French administrator invitation, invited-user login/acceptance, and MFA
operations UI. See [the end-to-end record](MILESTONE_1_END_TO_END.md); those
source assets do not prove a live Auth/SMTP/database journey.

## Acceptance IDs

| Acceptance ID | Criterion | Evidence | Result |
|---|---|---|---|
| `M1-AUTH-AC-001` | Only an authenticated active `users.manage` member with AAL2 step-up no older than 15 minutes can create an invitation. | `app.create_workspace_invitation_job`, application body contract, pgTAP AAL1/stale/permission/workspace negatives. | Implemented; database runtime pending. |
| `M1-AUTH-AC-002` | Creation validates one email, one BCP 47 locale, expiry within 30 days, and one to 32 unique active role IDs owned by the selected workspace. | SQL validation, locked role scope, strict Zod input, cross-workspace/duplicate/invalid-input tests. | Implemented; database runtime pending. |
| `M1-AUTH-AC-003` | Invitation, role snapshot, append-only command mapping, audit event, outbox event, and delivery job commit atomically and replay idempotently. | One security-definer transaction, command fingerprint, advisory lock, pending-email unique index, exact replay tests. | Implemented; database runtime pending. |
| `M1-AUTH-AC-004` | The delivery job contains only `invitation_id`; email is reloaded only by the active lease owner and provider tokens never enter Vynlo state. | Exact JSON equality, forbidden-content assertions, service-only reload RPC, no authenticated table mutation grants. | Implemented; provider staging pending. |
| `M1-AUTH-AC-005` | A matching confirmed authenticated email can accept a pending unexpired invitation without prior membership and atomically receive the invited active roles. | `app.accept_workspace_invitation`, invitation row lock, Auth email checks, active-role locks, profile/membership/role/audit assertions. | Implemented; browser E2E pending. |
| `M1-AUTH-AC-006` | Mismatched email, workspace spoof, expired/revoked/terminal invitation, inactive role/profile, and idempotency conflict fail without partial provisioning. | Transactional command and pgTAP negative matrix. | Implemented; database runtime pending. |
| `M1-AUTH-AC-007` | Invitation and command state remain workspace-owned, forced-RLS protected, append-only where applicable, and auditable without job PII. | Composite foreign keys, forced RLS, narrow grants, immutable trigger, explicit audit actions. | Implemented; database runtime pending. |

## Authenticated API contract

Both routes require the existing command headers:

- `Authorization: Bearer <user access token>`;
- `X-Workspace-Id: <uuid>`;
- `Idempotency-Key: <8-200 printable characters>`;
- `X-Request-Id: <safe request identifier>`;
- `X-Correlation-Id: <uuid>`;
- `Content-Type: application/json`.

The web adapter uses `NEXT_PUBLIC_SUPABASE_URL` and a publishable/legacy anon
key. It sends both `Accept-Profile: app` and `Content-Profile: app`. A Supabase
secret/service-role key is rejected by configuration validation and is never
available to these browser-facing routes.

### Create invitation

`POST /api/v1/workspace-invitations`

```json
{
  "email": "person@example.invalid",
  "roleIds": ["51000000-0000-4000-8000-000000000001"],
  "requestedLocale": "en-CA",
  "expiresAt": "2026-07-17T18:00:00.000Z"
}
```

New work returns HTTP `202`; an exact replay returns HTTP `200`.

```json
{
  "data": {
    "invitationId": "uuid",
    "invitationStatus": "pending",
    "outboxEventId": "uuid",
    "jobId": "uuid",
    "jobStatus": "queued",
    "replayed": false
  }
}
```

### Accept invitation

After GoTrue establishes a session, the browser callback carries identifiers,
not credentials:

```text
/login?invitation=<invitation_id>&workspace=<workspace_id>
```

The authenticated client then calls
`POST /api/v1/workspace-invitations/accept` with the selected workspace header.

```json
{
  "invitationId": "83000000-0000-4000-8000-000000000001"
}
```

New acceptance returns HTTP `201`; an exact or already-accepted matching-user
replay returns HTTP `200`.

```json
{
  "data": {
    "invitationId": "uuid",
    "membershipId": "uuid",
    "invitationStatus": "accepted",
    "replayed": false
  }
}
```

All errors use the existing stable envelope:

```json
{
  "error": {
    "code": "permission_denied",
    "message": "The command is not permitted."
  }
}
```

No response discloses whether another workspace contains a matching email.

## Database RPC contract

Authenticated create command:

```sql
app.create_workspace_invitation_job(
  uuid, text, text, uuid[], text, timestamptz, text, uuid
)
```

Arguments are workspace ID, idempotency key, email, role IDs, requested locale,
expiry, request ID, and correlation ID. It returns exactly one row:

```text
(invitation_id uuid, invitation_status text, outbox_event_id uuid,
 job_id uuid, job_status text, replayed boolean)
```

Authenticated acceptance command:

```sql
app.accept_workspace_invitation(uuid, text, uuid, text, uuid)
```

Arguments are workspace ID, idempotency key, invitation ID, request ID, and
correlation ID. It returns exactly one row:

```text
(invitation_id uuid, membership_id uuid,
 invitation_status text, replayed boolean)
```

Acceptance derives the user from `auth.uid()`, verifies the signed JWT email
against the confirmed `auth.users.email`, and then compares that identity with
the locked invitation. It deliberately does not call active-membership helpers
before provisioning because a valid invited user does not have membership yet.

Service-only authoritative worker read:

```sql
app.read_invitation_delivery_job(uuid, text, uuid)
```

Arguments are job ID, worker ID, and lease token. It returns exactly one row only
for the current unexpired running lease and an unexpired pending invitation:

```text
(invitation_id uuid, workspace_id uuid, email text, requested_locale text,
 expires_at timestamptz, provider_identity_exists boolean)
```

An ineligible lease or invitation raises SQLSTATE `22023`, allowing the worker to
classify the result as validation/permanent without parsing response details.
The RPC is executable only by `service_role`.

## Delivery worker contract

The creation transaction enqueues exactly:

```text
event_name: auth.invitation.delivery_requested
job_type: auth.invitation.deliver
aggregate_type/entity_type: workspace_invitation
aggregate_id/entity_id: invitation_id
payload_schema_version: 1
payload: {"invitation_id":"<uuid>"}
```

The job payload and outbox payload have one field. They never contain email,
locale, redirect URL, password, secret, provider token, cookie, credential, or
service key.

The worker uses the existing durable-job RPCs:

```sql
app.claim_jobs(text, integer, integer, text[])
app.heartbeat_job(uuid, text, uuid, integer)
app.complete_job(uuid, text, uuid, jsonb, text)
app.fail_job(uuid, text, uuid, text, text, text, text, integer)
```

Claim filters to `auth.invitation.deliver`. After the lease-bound reload:

1. If `provider_identity_exists` is `true`, the worker asks GoTrue for an
   existing-identity passwordless callback through `/auth/v1/otp` with
   `{email, create_user: false}` and the callback above.
2. If it is `false`, the worker calls the GoTrue administrator invite endpoint
   with `{email}` and the same callback. GoTrue creates and owns the invite token.
3. Either accepted provider submission completes with
   `delivery_outcome: submitted`. Vynlo does not infer delivery merely from
   identity existence.
4. The only allowed result summary is `invitation_id` plus that outcome. An
   optional non-secret provider request ID uses the dedicated job column.
5. Safe failure codes/details never contain email, response bodies, provider
   tokens, URLs with query credentials, or authorization material.

A provider identity conflict during the new-identity invite call is transient:
the next lease-fenced attempt reloads authoritative state and, once the identity
exists, selects non-creating OTP delivery. This handles the race without storing
provider response bodies or tokens.

Worker-only environment:

- `VYNLO_SUPABASE_URL`;
- `VYNLO_SUPABASE_SERVICE_ROLE_KEY`;
- `VYNLO_APP_URL`, validated as an origin before building the redirect;
- `VYNLO_WORKER_ID`, a stable non-secret lease-owner identifier;
- `VYNLO_PREVIEW_BUCKET`, required by the shared preview/invitation worker;
- optional bounded `VYNLO_AUTH_INVITE_TIMEOUT_MS`.

These variables must not be prefixed `NEXT_PUBLIC_`, returned by health checks,
or logged. The web application does not use the service-role key.

## Lifecycle and retry behavior

```text
invitation: pending --matching acceptance--> accepted
                  \--administrator command--> revoked (future slice)
                  \--expiry sweep-----------> expired (future slice)

delivery job: queued -> running -> succeeded
                       \-> retry_wait -> running
                       \-> dead_letter -> admin review/replay
```

Delivery success does not accept an invitation. The invitation remains pending
until a matching authenticated user runs the acceptance command. Expired,
revoked, or accepted records cannot be delivered or accepted again, except that
an already-accepted invitation replays safely for the same accepted user.

Creation idempotency is scoped by workspace, command kind, actor, and client key.
The fingerprint covers normalized email, sorted role IDs, canonical locale, and
exact expiry. The delivery job uses an internal key derived from the generated
invitation UUID, so client keys cannot collide in the shared job namespace.

Acceptance idempotency is scoped the same way and fingerprints the invitation
ID. Advisory locks serialize equal keys; the invitation row lock serializes
competing acceptance; active role row locks prevent a role from changing during
validation; unique and composite constraints preserve tenant ownership under
concurrency.

## RLS, authorization, and audit

- `workspace_invitations` and `workspace_invitation_roles` retain forced RLS and
  no authenticated insert/update grants.
- `workspace_invitation_commands` enables and forces RLS, has no authenticated
  table grant, and rejects update/delete through an append-only trigger.
- Only `authenticated` can execute create and accept.
- Only `service_role` can execute the lease-bound delivery read.
- The create command requires active `users.manage` and recent AAL2.
- Acceptance requires a confirmed matching authenticated email, not a
  pre-existing membership or role claim.
- Explicit audit actions are `auth.invitation.created` and
  `auth.invitation.accepted`; job lifecycle actions remain owned by the durable
  job subsystem.
- Explicit audit payloads omit the invitation email and all provider material.

## Test evidence

`006_invite_only_auth.test.sql` contains 55 assertions covering:

- schema, function, nullable legacy-token, and forced-RLS contracts;
- AAL1, stale AAL2, missing permission, and cross-workspace denial;
- invalid email, bounded expiry, duplicate/cross-workspace roles, and direct
  table-write rejection;
- atomic invitation/outbox/job persistence and exact one-field payload;
- create replay, changed-request conflict, and pending-email uniqueness;
- service lease ownership, provider endpoint selection, and safe completion;
- mismatch, wrong workspace, expiry, revocation, and terminal denial;
- no-prior-membership matching acceptance;
- profile, membership, role, invitation, MFA, audit, and replay invariants;
- append-only command history.

Application and route tests additionally cover strict bodies, authority-field
rejection, response contracts, RPC parameter mapping, bearer/workspace metadata,
public-key PostgREST, stable envelopes, and replay HTTP status.

`T-AUTH-001` is implemented at database/application/API and mocked-browser
source level but is not closed until provider staging and live browser E2E prove
the invite callback and public-registration rejection. `T-API-001`, responsive
UI, accessibility, and localization now have source evidence in the integrated
web increment; runtime provider/database acceptance remains open.

## Compatibility and rollback

The migration is additive except that legacy `workspace_invitations.token_hash`
becomes nullable. Existing non-null hashes remain readable only through trusted
database/service access and stay immutable; new commands always write `NULL`.
No raw token migration is attempted.

Rollback is an application rollback plus a reviewed forward corrective
migration. To stop new invitations safely, revoke authenticated execute on the
create RPC and pause `auth.invitation.deliver` claims. Do not drop invitation,
membership, command, outbox, job, or audit history. Pending records can later be
revoked through a reviewed lifecycle command.
