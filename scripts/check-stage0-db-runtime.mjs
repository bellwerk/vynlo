import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

function run(command, args) {
  return execFileSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  }).trim();
}

const repositoryRoot = path.resolve(import.meta.dirname, "..");
const supabaseConfig = readFileSync(
  path.join(repositoryRoot, "supabase", "config.toml"),
  "utf8",
);
const projectId = /^project_id\s*=\s*"([^"]+)"/mu.exec(supabaseConfig)?.[1];

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
    [
      "select json_build_object(",
      "'workspace_count', count(*),",
      "'unique_slug_count', count(distinct slug),",
      "'all_fixture_only', bool_and(fixture_only)",
      ")",
      "from stage0.synthetic_workspaces;",
    ].join(" "),
  ]),
);

if (
  result.workspace_count !== 2 ||
  result.unique_slug_count !== 2 ||
  result.all_fixture_only !== true
) {
  throw new Error(
    `Unexpected Stage 0 database fixture state: ${JSON.stringify(result)}`,
  );
}

console.log("stage0_supabase_runtime: pass (2 synthetic workspaces)");
