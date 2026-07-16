import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

function run(command, args, input) {
  return execFileSync(command, args, {
    encoding: "utf8",
    input,
    stdio: [input === undefined ? "ignore" : "pipe", "pipe", "inherit"],
  }).trim();
}

const repositoryRoot = path.resolve(import.meta.dirname, "..");
const supabaseConfig = readFileSync(
  path.join(repositoryRoot, "supabase", "config.toml"),
  "utf8",
);
const projectId = /^project_id\s*=\s*"([^"]+)"/mu.exec(supabaseConfig)?.[1];
const seedSql = readFileSync(
  path.join(repositoryRoot, "supabase", "seed.sql"),
  "utf8",
);

if (!projectId) {
  throw new Error("supabase/config.toml must declare project_id.");
}

const containers = run("docker", [
  "ps",
  "--filter",
  `name=supabase_db_${projectId}`,
  "--format",
  "{{.ID}}",
])
  .split(/\r?\n/u)
  .filter(Boolean);

if (containers.length !== 1) {
  throw new Error(
    `Expected one running database container for ${projectId}, found ${containers.length}.`,
  );
}

run(
  "docker",
  [
    "exec",
    "--interactive",
    containers[0],
    "psql",
    "--username",
    "postgres",
    "--dbname",
    "postgres",
    "--set",
    "ON_ERROR_STOP=1",
  ],
  seedSql,
);

const query = `
select json_build_object(
  'organization_count', (select count(*) from public.organizations),
  'workspace_count', (select count(*) from public.workspaces),
  'profile_count', (select count(*) from public.user_profiles),
  'membership_count', (select count(*) from public.workspace_memberships),
  'active_membership_count', (
    select count(*) from public.workspace_memberships where status = 'active'
  ),
  'platform_permission_count', (
    select count(*) from public.permissions
    where source = 'platform' and workspace_id is null and status = 'active'
  ),
  'forced_rls_table_count', (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'organizations', 'workspaces', 'user_profiles', 'workspace_memberships',
        'roles', 'permissions', 'role_permissions', 'membership_roles',
        'workspace_invitations', 'workspace_invitation_roles', 'audit_events'
      )
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  )
);
`;

const result = JSON.parse(
  run("docker", [
    "exec",
    containers[0],
    "psql",
    "--username",
    "postgres",
    "--dbname",
    "postgres",
    "--tuples-only",
    "--no-align",
    "--command",
    query,
  ]),
);

const expected = {
  organization_count: 2,
  workspace_count: 2,
  profile_count: 4,
  membership_count: 4,
  active_membership_count: 3,
  platform_permission_count: 75,
  forced_rls_table_count: 11,
};

for (const [key, expectedValue] of Object.entries(expected)) {
  if (result[key] !== expectedValue) {
    throw new Error(
      `Unexpected Milestone 1 database state for ${key}: expected ${expectedValue}, received ${JSON.stringify(result[key])}.`,
    );
  }
}

console.log(
  "milestone1_supabase_runtime: pass (idempotent reseed, 2 isolated workspaces, 75 permissions, 11 forced-RLS tables)",
);
