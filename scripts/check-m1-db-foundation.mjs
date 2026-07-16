import { readFile, readdir } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const migrationsDirectory = path.join(root, "supabase", "migrations");
const migrationNames = (await readdir(migrationsDirectory)).filter((name) =>
  /^\d{14}_[a-z0-9_]+\.sql$/u.test(name),
);

if (migrationNames.length === 0) {
  throw new Error("At least one timestamped production migration is required.");
}

const migrations = await Promise.all(
  migrationNames.map((name) =>
    readFile(path.join(migrationsDirectory, name), "utf8"),
  ),
);
const migrationSql = migrations.join("\n");
const seedSql = await readFile(path.join(root, "supabase", "seed.sql"), "utf8");
const databaseTestsDirectory = path.join(root, "supabase", "tests");
const databaseTestNames = (await readdir(databaseTestsDirectory))
  .filter((name) => /^\d{3}_[a-z0-9_]+\.test\.sql$/u.test(name))
  .sort();
const databaseTestSuites = await Promise.all(
  databaseTestNames.map(async (name) => ({
    name,
    sql: await readFile(path.join(databaseTestsDirectory, name), "utf8"),
  })),
);
const databaseTests = databaseTestSuites.map(({ sql }) => sql).join("\n");
const permissionCatalog = await readFile(
  path.join(root, "docs", "data", "PERMISSION_CATALOG.md"),
  "utf8",
);
const permissionContracts = await readFile(
  path.join(root, "packages", "auth", "src", "permissions.ts"),
  "utf8",
);
const supabaseConfig = await readFile(
  path.join(root, "supabase", "config.toml"),
  "utf8",
);
const authenticatedRpcAdapter = await readFile(
  path.join(root, "apps", "web", "lib", "api", "postgrest.ts"),
  "utf8",
);
const workerJobStore = await readFile(
  path.join(root, "apps", "worker", "src", "job-store.ts"),
  "utf8",
);
const previewRepository = await readFile(
  path.join(root, "apps", "worker", "src", "preview-document-repository.ts"),
  "utf8",
);

const foundationTables = [
  "organizations",
  "workspaces",
  "user_profiles",
  "workspace_memberships",
  "roles",
  "permissions",
  "role_permissions",
  "membership_roles",
  "workspace_invitations",
  "workspace_invitation_roles",
  "audit_events",
];

const exposedTables = [
  ...new Set(
    [
      ...migrationSql.matchAll(/create\s+table\s+public\.([a-z][a-z0-9_]*)/giu),
    ].map(([, table]) => table),
  ),
].sort();

for (const table of foundationTables) {
  if (!exposedTables.includes(table)) {
    throw new Error(
      `Production migration is missing foundation table ${table}.`,
    );
  }
}

for (const table of exposedTables) {
  for (const requiredPattern of [
    new RegExp(`create\\s+table\\s+public\\.${table}\\s*\\(`, "iu"),
    new RegExp(
      `alter\\s+table\\s+public\\.${table}\\s+enable\\s+row\\s+level\\s+security`,
      "iu",
    ),
    new RegExp(
      `alter\\s+table\\s+public\\.${table}\\s+force\\s+row\\s+level\\s+security`,
      "iu",
    ),
  ]) {
    if (!requiredPattern.test(migrationSql)) {
      throw new Error(
        `Production migration is missing the required ${table} schema/RLS contract.`,
      );
    }
  }
}

for (const helper of [
  "current_user_id",
  "auth_assurance_at_least",
  "has_recent_strong_auth",
  "has_active_membership",
  "has_permission",
  "validate_membership_activation",
  "assert_permission_mfa_requirement",
  "derive_browser_identity_fields",
  "bump_workspace_settings_version",
  "record_boundary_status_audit",
  "guard_workspace_permission_key",
  "write_audit_event",
]) {
  const declaration = new RegExp(
    `create\\s+function\\s+app\\.${helper}\\s*\\(`,
    "iu",
  );
  if (!declaration.test(migrationSql)) {
    throw new Error(`Missing trusted database helper: app.${helper}.`);
  }
}

for (const command of [
  "create_inventory_unit",
  "create_party",
  "create_deal_draft",
  "request_document_preview_job",
  "complete_document_preview_artifact",
  "claim_jobs",
  "complete_job",
  "fail_job",
  "heartbeat_job",
  "create_workspace_invitation_job",
  "accept_workspace_invitation",
  "read_invitation_delivery_job",
]) {
  if (
    !new RegExp(`create\\s+function\\s+app\\.${command}\\s*\\(`, "iu").test(
      migrationSql,
    )
  ) {
    throw new Error(`Missing Milestone 1 command contract: app.${command}.`);
  }
}

if (
  !/p_job_type\s*=>\s*'auth\.invitation\.deliver'[\s\S]*?p_payload\s*=>\s*pg_catalog\.jsonb_build_object\(\s*'invitation_id'\s*,\s*new_invitation_id\s*\)/iu.test(
    migrationSql,
  ) ||
  /p_job_type\s*=>\s*'auth\.invitation\.deliver'[\s\S]{0,800}\b(?:token|email)\b\s*,/iu.test(
    migrationSql,
  )
) {
  throw new Error(
    "Invitation delivery jobs must contain only the authoritative invitation identifier.",
  );
}

if (!/^schemas\s*=\s*\[[^\]]*"app"[^\]]*\]/imu.test(supabaseConfig)) {
  throw new Error(
    "Supabase Data API must expose the app schema used by authenticated RPC commands.",
  );
}

for (const [label, source] of [
  ["Authenticated web RPC adapter", authenticatedRpcAdapter],
  ["Worker job RPC adapter", workerJobStore],
]) {
  if (!/["']Content-Profile["']\s*:\s*["']app["']/u.test(source)) {
    throw new Error(`${label} must select the app PostgREST schema.`);
  }
}
if (
  !/["']Content-Profile["']\s*:\s*contentProfile/u.test(previewRepository) ||
  !/complete_document_preview_artifact[\s\S]*?["']app["']/u.test(
    previewRepository,
  )
) {
  throw new Error(
    "Preview completion RPC adapter must select the app PostgREST schema.",
  );
}

const previewCompletionContract =
  /create\s+function\s+app\.complete_document_preview_artifact\s*\([\s\S]*?\$\$;/iu.exec(
    migrationSql,
  )?.[0] ?? "";
if (
  !/p_job_id\s+uuid\s*,\s*p_worker_id\s+text\s*,\s*p_lease_token\s+uuid/iu.test(
    previewCompletionContract,
  ) ||
  !/render_job\.lease_owner\s+is\s+distinct\s+from\s+p_worker_id/iu.test(
    previewCompletionContract,
  ) ||
  !/render_job\.lease_token\s+is\s+distinct\s+from\s+p_lease_token/iu.test(
    previewCompletionContract,
  )
) {
  throw new Error(
    "Preview artifact completion must match the current worker ID and lease token.",
  );
}

if (
  !/create\s+function\s+app\.guard_workspace_permission_key\(\)[\s\S]*?platform_permission\.workspace_id\s+is\s+null[\s\S]*?platform_permission\.key\s*=\s*new\.key/iu.test(
    migrationSql,
  ) ||
  !/create\s+trigger\s+permissions_workspace_key_guard\b/iu.test(migrationSql)
) {
  throw new Error(
    "Workspace-private permission keys must be namespaced runtime records that cannot shadow platform keys.",
  );
}

const rolePermissionInvariant =
  /create\s+function\s+app\.assert_role_permission_scope\(\)[\s\S]*?\$\$;/iu.exec(
    migrationSql,
  )?.[0] ?? "";
if (
  !/from\s+public\.permissions[\s\S]*?for\s+share/iu.test(
    rolePermissionInvariant,
  ) ||
  !/from\s+public\.roles[\s\S]*?for\s+update/iu.test(rolePermissionInvariant)
) {
  throw new Error(
    "Role-permission MFA invariants must lock permission and role rows to serialize concurrent changes.",
  );
}

if (
  !/create\s+trigger\s+permissions_mfa_guard\s+before\s+update\s+of\s+status\s+on\s+public\.permissions/iu.test(
    migrationSql,
  )
) {
  throw new Error(
    "Permission reactivation must re-check the administrative-role MFA invariant.",
  );
}

const invitationBrowserSelect =
  /grant\s+select\s*\(([\s\S]*?)\)\s+on\s+public\.workspace_invitations\s+to\s+authenticated\s*;/iu.exec(
    migrationSql,
  )?.[1];
if (
  !invitationBrowserSelect ||
  /\btoken_hash\b/iu.test(invitationBrowserSelect)
) {
  throw new Error(
    "Authenticated invitation reads must use an explicit column grant that excludes token_hash.",
  );
}

const organizationBrowserSelect =
  /grant\s+select\s*\(([\s\S]*?)\)\s+on\s+public\.organizations\s+to\s+authenticated\s*;/iu.exec(
    migrationSql,
  )?.[1];
if (
  !organizationBrowserSelect ||
  /\bbilling_metadata\b/iu.test(organizationBrowserSelect)
) {
  throw new Error(
    "Authenticated organization reads must exclude internal billing metadata.",
  );
}
if (
  /create\s+policy\s+invitations_(?:insert|update)\b/iu.test(migrationSql) ||
  /grant\s+[^;]*\b(?:insert|update)\b[^;]*on\s+public\.workspace_invitations\s+to\s+authenticated\s*;/iu.test(
    migrationSql,
  )
) {
  throw new Error(
    "Invitation creation and lifecycle mutation must remain trusted-command-only.",
  );
}

if (
  !/create\s+function\s+app\.has_active_membership[\s\S]*?join\s+public\.user_profiles[\s\S]*?up\.status\s*=\s*'active'/iu.test(
    migrationSql,
  ) ||
  /create\s+policy\s+user_profiles_insert\b/iu.test(migrationSql) ||
  /grant\s+[^;]*\binsert\b[^;]*on\s+public\.user_profiles\s+to\s+authenticated\s*;/iu.test(
    migrationSql,
  )
) {
  throw new Error(
    "Deactivated user profiles must fail closed and profile provisioning must remain trusted-command-only.",
  );
}

for (const trigger of [
  "organizations_status_audit",
  "user_profiles_status_audit",
  "workspace_memberships_actor_fields",
  "roles_actor_fields",
  "role_permissions_actor_fields",
  "membership_roles_actor_fields",
  "workspaces_settings_version",
]) {
  if (
    !new RegExp(`create\\s+trigger\\s+${trigger}\\b`, "iu").test(migrationSql)
  ) {
    throw new Error(
      `Missing required boundary lifecycle audit trigger: ${trigger}.`,
    );
  }
}

const authenticatedInsertGrants = [
  ...migrationSql.matchAll(
    /grant\s+insert\s*\(([^)]*)\)[\s\S]*?to\s+authenticated\s*;/giu,
  ),
].map(([, columns]) => columns);
for (const protectedColumn of [
  "invited_at",
  "activated_at",
  "deactivated_at",
  "invited_by",
  "created_by",
  "granted_by",
  "granted_at",
  "revoked_by",
  "revoked_at",
  "assigned_by",
  "assigned_at",
]) {
  if (
    authenticatedInsertGrants.some((columns) =>
      new RegExp(`\\b${protectedColumn}\\b`, "iu").test(columns),
    )
  ) {
    throw new Error(
      `Authenticated insert grants must not expose derived ownership/lifecycle column ${protectedColumn}.`,
    );
  }
}

const workspaceUpdateGrant =
  /grant\s+update\s*\(([^)]*)\)\s+on\s+public\.workspaces\s+to\s+authenticated\s*;/iu.exec(
    migrationSql,
  )?.[1];
if (
  !workspaceUpdateGrant ||
  /\b(?:id|organization_id|slug|settings_version|created_at|updated_at)\b/iu.test(
    workspaceUpdateGrant,
  )
) {
  throw new Error(
    "Workspace browser updates must use safe column grants and derive settings_version.",
  );
}

const securityDefinerBlocks =
  migrationSql.match(/create\s+function\s+app\.[\s\S]*?\$\$;/giu) ?? [];
for (const block of securityDefinerBlocks.filter((candidate) =>
  /security\s+definer/iu.test(candidate),
)) {
  if (!/set\s+search_path\s*=\s*''/iu.test(block)) {
    throw new Error(
      "Every SECURITY DEFINER app helper must use an empty fixed search_path.",
    );
  }
}

if (
  !/grant\s+execute\s+on\s+function\s+app\.write_audit_event\([^;]*\)\s+to\s+service_role\s*;/iu.test(
    migrationSql,
  ) ||
  /grant\s+execute\s+on\s+function\s+app\.write_audit_event\([^;]*\)\s+to\s+(?:anon|authenticated)\s*;/iu.test(
    migrationSql,
  )
) {
  throw new Error(
    "app.write_audit_event must be executable by service_role only.",
  );
}

const catalogKeys = new Set(
  [...permissionCatalog.matchAll(/^([a-z][a-z0-9_]*\.[a-z0-9_.]+)$/gmu)].map(
    ([, key]) => key,
  ),
);
const migrationKeys = new Set(
  [
    ...migrationSql.matchAll(
      /\('([a-z][a-z0-9_]*\.[a-z0-9_.]+)',\s*'platform'\)/gu,
    ),
  ].map(([, key]) => key),
);
const contractKeys = new Set(
  [
    ...permissionContracts.matchAll(
      /^\s+"([a-z][a-z0-9_]*\.[a-z0-9_.]+)",$/gmu,
    ),
  ].map(([, key]) => key),
);

function assertSameKeys(label, actual) {
  const missing = [...catalogKeys].filter((key) => !actual.has(key));
  const unexpected = [...actual].filter((key) => !catalogKeys.has(key));
  if (missing.length > 0 || unexpected.length > 0) {
    throw new Error(
      `${label} permission mismatch; missing=${missing.join(",") || "none"}; unexpected=${unexpected.join(",") || "none"}.`,
    );
  }
}

if (catalogKeys.size !== 75) {
  throw new Error(
    `Expected 75 stable platform permission keys, found ${catalogKeys.size}.`,
  );
}
assertSameKeys("Migration", migrationKeys);
assertSameKeys("TypeScript", contractKeys);

const fixtureWorkspaceIds = new Set(
  seedSql.match(/[12]0000000-0000-4000-8000-00000000000[12]/gu) ?? [],
);
if (fixtureWorkspaceIds.size !== 2) {
  throw new Error(
    "Synthetic seed must contain exactly two stable workspace boundaries.",
  );
}
if (
  !/extensions\.crypt\([\s\S]*(?:extensions|pg_catalog)\.gen_random_uuid/iu.test(
    seedSql,
  )
) {
  throw new Error(
    "Synthetic Auth users must use randomized, non-interactive credentials.",
  );
}

if (
  !/insert\s+into\s+public\.stock_number_definitions[\s\S]*?'10000000-0000-4000-8000-000000000001'[\s\S]*?'active'[\s\S]*?'20000000-0000-4000-8000-000000000002'[\s\S]*?'active'/iu.test(
    seedSql,
  )
) {
  throw new Error(
    "Both synthetic workspaces need active stock-number definitions for the first vertical slice.",
  );
}

if (
  !/insert\s+into\s+public\.document_template_versions[\s\S]*?false[\s\S]*?true[\s\S]*?'active'/iu.test(
    seedSql,
  )
) {
  throw new Error(
    "Synthetic document templates must remain watermarked, non-production, and active.",
  );
}

if (
  !/insert\s+into\s+storage\.buckets[\s\S]*?values\s*\(\s*'document-previews'\s*,\s*'document-previews'\s*,\s*false\b/iu.test(
    seedSql,
  )
) {
  throw new Error(
    "The local preview artifact bucket must be present and private.",
  );
}

for (const testId of [
  "T-AUTH-002",
  "T-AUTH-003",
  "T-AUTH-004",
  "T-TEN-001",
  "T-RBAC-001",
  "T-AUD-001",
]) {
  if (!databaseTests.includes(testId)) {
    throw new Error(`Database negative matrix is missing ${testId}.`);
  }
}

let databaseAssertionCount = 0;
for (const suite of databaseTestSuites) {
  if (!/extensions\.finish\(\)/u.test(suite.sql)) {
    throw new Error(`${suite.name} must finish its declared pgTAP plan.`);
  }

  const declaredAssertions = Number(
    /select\s+extensions\.plan\((\d+)\)/iu.exec(suite.sql)?.[1],
  );
  const assertionCount = [
    ...suite.sql.matchAll(
      /^\s*select\s+extensions\.(?:has_[a-z_]+|ok|results_eq|is|throws_ok|lives_ok)\s*\(/gimu,
    ),
  ].length;

  if (
    !Number.isSafeInteger(declaredAssertions) ||
    declaredAssertions !== assertionCount
  ) {
    throw new Error(
      `${suite.name} pgTAP plan mismatch: declared=${declaredAssertions || "missing"}, assertions=${assertionCount}.`,
    );
  }
  databaseAssertionCount += assertionCount;
}

console.log(
  `milestone1_supabase_foundation: pass (${exposedTables.length} forced-RLS tables, ${catalogKeys.size} permission keys, 2 synthetic workspaces, ${databaseAssertionCount} pgTAP assertions)`,
);
