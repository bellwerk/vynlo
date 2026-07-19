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

`20260716160000_inventory_workflow_foundation.sql` is the forward-only Milestone
2 inventory/workflow expansion. It adds workspace locations, semantic-versioned
workflow configuration, workflow instances/events, permission-separated
internal inventory details, location events, and append-only command receipts.
It expands existing inventory rows compatibly and backfills any pre-migration M1
holding episodes into a neutral `m1.inventory_compat` workflow. The existing M1
create command remains callable and automatically attaches the active
`inventory.standard` workflow when one is configured.

The three M2 inventory commands use optimistic aggregate versions, deterministic
idempotency fingerprints, fixed search paths, immutable permission keys,
transactional audit/outbox writes, and workspace-composite foreign keys. Every
new exposed table has forced RLS; authenticated clients receive no direct DML.
Activated workflow content and child states/transitions are immutable. An
active version can only retire with all content/provenance unchanged, after
which corrections install a new bounded semantic version such as `1.1.0`.
Rollback is an application/configuration rollback followed by a reviewed
forward migration, never deletion of workflow, transfer, receipt, audit, or
outbox history.

`20260716170000_durable_vin_decode.sql` adds provider-neutral VIN requests,
immutable raw and mapped results, duplicate candidates/reviews, reference-only
outbox jobs, lease-fenced worker completion, bounded dead-letter retry, and
permissioned duplicate decisions with recent step-up for manager overrides.

`20260716180000_inventory_cost_search.sql` adds the append-only integer-minor
cost ledger, derived effective reversal status, cost/search projections, bounded
inventory search, and validated private/workspace saved views. Cost evidence is
fenced to a ready, undeleted preserved file owned by the same workspace and
inventory aggregate. Money values cross JSON audit/outbox boundaries as decimal
strings so values above the JavaScript safe-integer range remain exact.

`20260716190000_media_pipeline.sql` adds versioned image-processing profiles,
private upload and processing lineage, immutable managed-file provenance,
versioned inventory media collections, worker-lease-fenced legal originals,
audited exact-object download authorization, raw retention, and append-only
legal/incident holds. A raw deletion load establishes a database fence before
the provider mutation, so a hold acquired first blocks deletion and a hold
cannot race an already-authorized provider delete.

`20260716200000_inventory_intake_from_vin.sql` makes a confirmed successful VIN
decode the canonical inventory allocation boundary. It consumes one immutable
result/review, rechecks duplicate state under locks, allocates stock
transactionally, records confirmed facts, and revokes browser access to the
legacy direct-allocation primitive.

`20260716210000_media_upload_verification.sql` places every browser upload behind
an exact unexpired quarantine intent and a durable, lease-fenced verification
job. Only a checksum/size/MIME/signature/dimension match plus a clean malware
receipt can enqueue image processing; rejections remain visible and retryable.

`20260716220000_media_quarantine_cleanup.sql` adds service-only, bounded
quarantine cleanup scheduling and immutable cleanup provenance. It covers
expired abandoned upload intents, terminal verification rejection, and
successful uploads only after the same processing generation has a
checksum-matched deterministic raw copy and normalized master. Cleanup jobs and
worker RPCs fence workspace, upload session, generation, checksum, active lease,
and attempt. Legal/document originals are excluded. The migration does not
enable a provider delete primitive; runtime consumers remain disabled until an
atomic conditional-delete adapter is available.

`20260716230000_m2_sql_domain_hardening.sql` is the additive storage-policy
cutover. Authenticated uploads must match one live upload intent's exact object
key, byte size, and normalized MIME metadata. Authenticated roles have no
persistent `storage.objects` read policy or SELECT grant; application commands
authorize an exact managed file, audit the decision, and issue only a short-lived
server-side storage grant.

`20260716240000_legal_original_upload_verification.sql` adds document-owned
legal/signed-original intents, exact private Storage INSERT policy, recent
step-up enforcement for signed bytes, a lease-bound scan-first verification
path, and immutable preserved-original provenance. It also adds bounded durable
cleanup for expired or terminally rejected unaccepted objects. Cleanup records
exact generation/checksum/MIME/size and can never select a completed preserved
original; the physical consumer remains disabled until an atomic
checksum-conditional delete provider is available.

`20260716250000_m2_vehicle_media_management.sql` adds exact vehicle-photo read
projections and optimistic, actor-idempotent caption/archive/order/cover
commands. Authenticated direct reads of provider coordinates are revoked;
mutations preserve collection invariants and append audit/outbox evidence.

`20260716260000_m2_inventory_operations.sql` completes the non-media Milestone
2 operator read/lifecycle boundary. It adds permission-aware detail, active
location, exact cost-ledger/category, and complete saved-view projections;
owner-only saved-view archive; and recent-step-up full vehicle-fact replacement
with immutable before/after history, actor-scoped idempotency, audit evidence,
and a reference-only outbox event. New provenance tables use forced RLS and
deny browser DML. Rollback is a forward corrective change that retains fact,
receipt, audit, and outbox history.

`20260716270000_document_preview_download_authorization.sql` closes the preview
read boundary with append-only forced-RLS authorization receipts. The browser
can authorize one visible artifact but never receive bucket/object coordinates;
a service-only loader resolves the exact audited record for checksum, MIME, and
size verification before a short server grant is signed.

`20260716280000_m2_vin_intake_completion.sql` completes the VIN-to-inventory
boundary with active workspace location and condition configuration, exact
confirmed-result binding, and a dedicated audited manual path that is available
only after an authoritative VIN job reaches dead letter. Every decode request
receives one immutable intake/link receipt while independently reviewed requests
may safely reference the same open holding without allocating another stock
number. Both commands return an explicit create-versus-link flag; compatible
confirmed values fill only currently-null facts before an open-unit receipt is
recorded. A consumed request projects as terminal `consumed` with retry/review
disabled while its underlying durable job and dead-letter history remain
unchanged. Request consumption, actor idempotency, audit, outbox, and permanent
numbering history remain immutable; rollback is forward repair.

`20260716290000_managed_media_download_authorization.sql` applies the same
opaque boundary to managed media. Authenticated callers create an
actor-idempotent, short-lived authorization without receiving provider
coordinates. Only the service-role loader can resolve the exact workspace,
file, bucket, key, generation, checksum, MIME, and size tuple used for immutable
byte verification and URL signing. Authorization receipts use forced RLS and
are append-only; rollback is a forward corrective migration that preserves
audit history.

`20260716300000_m2_media_security_hardening.sql` removes direct API-role
execution from the vehicle-upload completion and legal-original preservation
implementation helpers. Their same-owner SECURITY DEFINER verification
wrappers remain the only service-role completion paths. It also revokes direct
authenticated and service reads of coordinate-bearing legal upload sessions;
the Storage INSERT policy now uses a boolean-only actor/intention predicate
with a fixed empty search path. No media or audit history is rewritten, and
rollback is a forward corrective privilege change.

`20260716310000_m2_actor_idempotency_hardening.sql` gives every early M2
inventory, cost, and media command an explicit workspace/actor/domain
idempotency namespace. Public command wrappers validate and preserve the raw
logical key; the private implementations include actor identity in advisory
locks and replay predicates, while composite unique indexes include actor and
command kind. Same-actor pre-migration receipts therefore retain replay
compatibility, while another permitted actor cannot receive or conflict-poison
that result, even with a key shaped like the retired `a1:` digest. The prior
workspace/domain-only unique constraints are removed. Trusted actorless media
worker receipts retain a separate partial workspace/domain/key uniqueness rule.
Owner-internal implementations and key adapters have no API-role grant. Saved-
view receipts and opaque managed-download authorizations were already actor-
scoped and remain unchanged.

`20260716320000_vehicle_upload_storage_policy_hardening.sql` restores the exact
vehicle-photo Storage INSERT boundary after authenticated reads of
`media_upload_sessions` were revoked. The Storage policy now calls a
boolean-only, fixed-search-path SECURITY DEFINER predicate that checks actor,
bucket, key, live intent status, exact size, normalized MIME, and permission
without exposing the underlying row. The stale authenticated SELECT policy is
removed while service/worker access remains unchanged. No media, object, job,
audit, outbox, or receipt history is rewritten; rollback is a forward policy
repair.

`20260716330000_legal_original_failure_visibility_retry.sql` adds the
authenticated owner-only status projection and manual dead-letter retry for
legal-original verification. Both SECURITY DEFINER RPCs derive the actor from
the session, verify workspace ownership and the media-kind permission, and
require recent strong authentication for signed originals. Status returns only
projected lifecycle and bounded safe failure fields. Retry stores the unchanged
external key in an actor-aware media receipt, requires an explicit audited
reason, copies the dead-letter source job's bounded policy and opaque payload,
and creates fresh causation/replay-linked outbox/job lineage. Direct browser
SELECT remains revoked; rollback is a forward privilege/command repair that
preserves jobs, receipts, audit, and outbox history.

`20260716340000_vehicle_upload_failure_visibility_retry.sql` adds the
authenticated owner-only status projection and reasoned manual dead-letter
retry for vehicle-photo upload verification. Status returns only lifecycle,
bounded attempts/retry time, and safe failure identifiers. Retry locks the
exact upload, media aggregate, and current dead-letter job; stores the raw key
in an actor-aware receipt; copies the reference-only payload and bounded job
policy; and preserves aggregate, causation, replay, audit, and outbox lineage.
Exact receipt replay remains deterministic after later terminal state, while a
fresh command cannot revive rejected bytes. The migration is additive and does
not alter legal/signed-original, retention, or provider-object behavior.
