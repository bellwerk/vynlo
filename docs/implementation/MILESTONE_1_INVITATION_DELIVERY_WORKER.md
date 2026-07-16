# Milestone 1 invitation delivery worker

**Recorded:** 2026-07-16

**Status:** Worker source and local contract tests implemented; live Auth/SMTP
acceptance pending

**Scope:** Worker delivery half of `VYN-AUTH-001`, `M1-TEN-AC-005`, and
`VYN-JOB-001`

## Delivered behavior

The worker now consumes the canonical `auth.invitation.deliver` durable job
created by the
[invite-only auth migration](../../supabase/migrations/20260716150000_invite_only_auth.sql).
It never accepts an email address, redirect URL, provider credential, or
provider-generated secret from the queued payload. It never generates an auth
link itself.

The implementation adds:

- exact payload-schema validation for `{ "invitation_id": "<uuid>" }`;
- a lease-fenced service-role reload through
  `app.read_invitation_delivery_job` before any provider call;
- cross-checks between the claimed job, workspace, entity, payload, and
  authoritative invitation;
- GoTrue new-identity delivery through `/auth/v1/invite` and existing-identity
  passwordless delivery through `/auth/v1/otp` with `create_user: false`, never
  `/admin/generate_link`;
- an origin-validated, server-only application redirect to
  `/login?invitation=<invitation_id>&workspace=<workspace_id>`;
- a bounded provider timeout and safe transient, rate-limit, provider-auth,
  validation, and permanent failure classification;
- authoritative identity-aware provider selection so an existing user still
  receives the invitation/workspace callback;
- durable success/failure, attempt history, audit, retry, and dead-letter state
  through the existing `app.complete_job` and `app.fail_job` functions; and
- structured result and log fields that exclude invited email, response bodies,
  provider user records, and provider-generated secrets.

Public signup remains disabled in
[`supabase/config.toml`](../../supabase/config.toml). The service-role credential
exists only in the worker environment and is never exposed through browser
configuration or a public signup path.

## Acceptance mapping

| Acceptance ID | Criterion | Evidence | Status |
|---|---|---|---|
| `M1-AUTH-DELIVERY-AC-001` | The durable job has type `auth.invitation.deliver`, schema version 1, matching `workspace_invitation` entity, and exactly one invitation ID field. | Exact-key parser plus malformed, extra-field, entity, schema, and ID tests. | Implemented. |
| `M1-AUTH-DELIVERY-AC-002` | Email, workspace, locale, expiry, invitation state, active lease, and provider-identity state are reloaded authoritatively by a trusted command. | `app.read_invitation_delivery_job` adapter with service-role, `Content-Profile: app`, and lease-fence contract tests. | Implemented; live RPC pending. |
| `M1-AUTH-DELIVERY-AC-003` | Provider delivery uses server-only invite or non-creating passwordless email with only invited email and an allowlisted app redirect. | GoTrue adapter request-shape, origin, credential-header, both endpoint, non-creation, and redirect tests. | Implemented; live Auth redirect allowlist pending. |
| `M1-AUTH-DELIVERY-AC-004` | No generated provider secret or response body enters persistence, output, or logs. | Adapter never parses the success/error body; synthetic sensitive-body, result-summary, database-detail, and logger leakage tests. | Implemented. |
| `M1-AUTH-DELIVERY-AC-005` | A provider identity found on reload receives a passwordless callback without creating another user. | Identity-aware handler, ambiguous-outcome retry, canonical OTP request, and repository-flag tests. | Implemented. |
| `M1-AUTH-DELIVERY-AC-006` | Provider and database failures have bounded, safe retry or terminal classification. | Timeout, cancellation, transport, 401, 422, 429/Retry-After, 503, terminal invitation state, and database transport tests. | Implemented. |
| `M1-AUTH-DELIVERY-AC-007` | Terminal state is written only through lease-fenced durable-job functions with append-only attempts and audit. | Shared durable runner/store plus integrated invitation failure persistence test. | Implemented; live audit verification pending. |
| `M1-AUTH-DELIVERY-AC-008` | The worker registers both preview and invitation jobs, validates all server-only runtime settings, and produces a directly importable Node 24 artifact. | Entrypoint registration, runtime-configuration tests, bundled build, and import smoke assertion. | Implemented. |

## Worker contract

The claimed job must have:

- job type `auth.invitation.deliver`;
- entity type `workspace_invitation`;
- an entity ID equal to `payload.invitation_id`;
- payload schema version `1`; and
- exactly one payload key, `invitation_id`.

The worker then invokes the app-schema RPC with `Content-Profile: app`:

```text
app.read_invitation_delivery_job(job_id, worker_id, lease_token)
```

The function returns exactly one active, unexpired, pending invitation for the
currently running, unexpired lease. It also reports whether an `auth.users`
identity already exists for the case-insensitive invited email. An expired,
revoked, accepted, malformed, mismatched, or lease-lost job fails with a
deterministic non-retryable validation response before provider delivery.

When no identity exists, the provider request is:

```text
POST <supabase-origin>/auth/v1/invite?redirect_to=<encoded-app-login-url>
Content-Type: application/json;charset=UTF-8

{"email":"<authoritative-invited-email>"}
```

When the authoritative reload finds an existing identity, the worker sends the
same callback through the installed `@supabase/auth-js` passwordless REST
contract without allowing user creation:

```text
POST <supabase-origin>/auth/v1/otp?redirect_to=<encoded-app-login-url>
Content-Type: application/json;charset=UTF-8

{
  "email": "<authoritative-invited-email>",
  "data": {},
  "create_user": false,
  "gotrue_meta_security": {},
  "code_challenge": null,
  "code_challenge_method": null
}
```

No custom user metadata is sent. The complete redirect for both paths is built
only from the validated `VYNLO_APP_URL` origin and authoritative UUIDs. Response
bodies are not parsed, returned, persisted, or logged. A safe `x-request-id`
header may be stored as provider correlation evidence after strict character
and length validation.

Successful summaries are limited to:

```json
{
  "invitation_id": "<uuid>",
  "delivery_outcome": "submitted"
}
```

Email, locale, expiry, redirects, provider records, credentials, and
provider-generated values are absent.

## Runtime configuration

Required server-only environment:

| Variable | Purpose |
|---|---|
| `VYNLO_APP_URL` | Application origin used to build the invitation login redirect. HTTPS is mandatory outside loopback development; credentials, paths, queries, and fragments are rejected. |
| `VYNLO_SUPABASE_URL` | Supabase project origin for app RPCs and the Auth admin endpoint. |
| `VYNLO_SUPABASE_SERVICE_ROLE_KEY` | Worker-only service credential for trusted RPC and GoTrue server-side invite/passwordless calls. Never expose or log it. |
| `VYNLO_WORKER_ID` | Stable non-secret worker instance identifier used by the job lease. |
| `VYNLO_PREVIEW_BUCKET` | Existing private preview bucket, still required because the same worker also handles preview jobs. |

Optional bounded setting:

| Variable | Default | Bounds |
|---|---:|---:|
| `VYNLO_AUTH_INVITE_TIMEOUT_MS` | `10000` | `1000..30000` |

The Supabase Auth configuration must allow the application `/login` invitation
redirects for the deployed origin. Verify the exact redirect including query
parameters in each environment; GoTrue may silently fall back to its Site URL
when a redirect is not allowlisted.

## Failure, retry, and operational behavior

Transport errors, timeouts, HTTP 408/425/5xx, and database unavailability are
transient. HTTP 429 is rate-limited and preserves only a bounded numeric
`Retry-After` hint. HTTP 401/403 is a provider-auth operational defect. Provider
identity conflict (409/422) is retried so the next authoritative reload can
select non-creating passwordless delivery. Malformed authoritative state,
invalid job state, and other rejected validated requests are terminal. The
durable job policy retries only retryable classifications with bounded
exponential jitter and creates admin review state when attempts are exhausted
or a non-retryable failure occurs.

Logs contain job/workspace/correlation IDs, attempt number, classification, and
safe machine codes. They do not contain invitation payloads, invited email,
provider response bodies, redirects, auth user records, or service credentials.
Operators should diagnose with the durable job attempt, audit event, and safe
provider request ID. Do not edit invitation, job, attempt, outbox, or audit
history directly.

### Provider idempotency limitation

Neither the GoTrue invite endpoint nor the passwordless endpoint accepts
Vynlo's durable idempotency key, and no atomic transaction spans provider email
delivery and `app.complete_job`. Delivery is therefore at least once, not
exactly once.

The worker reloads provider-identity state before every attempt. If an invite
timed out after GoTrue created the user, the retry switches to the non-creating
passwordless path so the existing identity still receives a callback carrying
the invitation/workspace route. This prevents the previous silent
identity-side reconciliation gap, but the original invite email and retry email
may both arrive. An ambiguous timeout after the passwordless provider accepted
the request can likewise resend another passwordless email on retry. Provider
rate limits reduce but do not eliminate duplicates.

Neither a successful provider response nor job completion proves downstream
mail delivery. Operators must treat `submitted` as provider acceptance, not a
delivery receipt, and use an approved explicit re-invitation/recovery workflow
when the recipient reports missing mail. Never recover by generating or copying
provider links.

## Verification and remaining runtime acceptance

Local worker verification covers payload minimization, service RPC shape,
authoritative-state rejection, provider request minimization, redirect
construction, timeout, failure classification, Retry-After, replay
new/existing identity provider selection, durable failure persistence, and
log/result leakage.

Still required against a disposable Supabase environment with outbound email:

1. reset through migration `20260716150000` and verify public signup remains
   disabled;
2. configure an exact allowed redirect for the deployed app `/login` flow;
3. create an invitation through the authenticated application command and run
   the worker through job success;
4. verify the email link establishes the matching identity before the
   acceptance RPC activates membership;
5. stop the worker after GoTrue invite acceptance but before `complete_job`,
   reclaim the lease, and verify the retry uses non-creating passwordless
   delivery while recording the expected at-least-once duplicate-email risk;
6. exercise expiry, revocation, rate-limit, provider-auth, and SMTP/provider
   outage paths; and
7. inspect worker logs, job summaries, attempts, audits, and browser responses
   for absence of email, service credentials, provider response bodies, and
   provider-generated secrets.
