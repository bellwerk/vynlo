// Stable test IDs: T-TEN-001.
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

import { afterEach, describe, expect, it } from "vitest";

const checkerPath = fileURLToPath(
  new URL("../../../scripts/check-package-boundaries.mjs", import.meta.url),
);
const fixtureRoots = new Set<string>();
const tenantMarker = ["dri", "vven"].join("");
const formulaMarker = ["r", "tb"].join("");
const stockMarker = ["P", "###"].join("");
const ratioParts = [70, 30] as const;

async function createFixture(files: Record<string, string>) {
  const root = await mkdtemp(path.join(tmpdir(), "vynlo-boundaries-"));
  fixtureRoots.add(root);

  const policyPath = path.join(
    root,
    "tenant-seeds",
    tenantMarker,
    "tests",
    "platform-boundary-policy.json",
  );
  await mkdir(path.dirname(policyPath), { recursive: true });
  await writeFile(
    policyPath,
    JSON.stringify({
      schema_version: 1,
      reserved_terms: [
        { value: formulaMarker, reason: "tenant-owned formula identifier" },
        { value: stockMarker, reason: "tenant-owned stock convention" },
      ],
      reserved_ratios: [
        { parts: ratioParts, reason: "tenant-owned contract allocation" },
      ],
    }),
  );

  for (const [relativePath, contents] of Object.entries(files)) {
    const filePath = path.join(root, ...relativePath.split("/"));
    await mkdir(path.dirname(filePath), { recursive: true });
    await writeFile(filePath, contents);
  }

  return root;
}

function runChecker(root: string) {
  const result = spawnSync(process.execPath, [checkerPath, "--root", root], {
    encoding: "utf8",
  });
  return {
    status: result.status,
    output: `${result.stdout}${result.stderr}`,
  };
}

afterEach(async () => {
  await Promise.all(
    [...fixtureRoots].map((root) => rm(root, { recursive: true, force: true })),
  );
  fixtureRoots.clear();
});

describe("tenant boundary guard", () => {
  it("scans reusable roots without flagging comments or documentation", async () => {
    const ratioLabel = ratioParts.join("/");
    const root = await createFixture({
      "apps/web/src/page.tsx": `// ${tenantMarker}\n/* ${formulaMarker} ${ratioLabel} */\nexport const opacity = 0.7;\nexport const startButton = true;`,
      "apps/web/README.md": `${tenantMarker} ${formulaMarker} ${ratioLabel}`,
      "packages/domain/src/index.ts": "export const workspaceKind = 'tenant';",
      "scripts/check.py": `\"\"\"${tenantMarker} ${formulaMarker} ${ratioLabel}\"\"\"\nVALUE = \"neutral\" # ${tenantMarker}`,
      [`tenant-seeds/${tenantMarker}/tests/owned.py`]: `VALUE = \"${tenantMarker} ${formulaMarker} ${ratioLabel}\"`,
    });

    const result = runChecker(root);

    expect(result.status).toBe(0);
    expect(result.output).toContain("package_boundaries: pass");
  });

  it("rejects a tenant identity condition in the web application", async () => {
    const root = await createFixture({
      "apps/web/src/runtime.ts": `export const select = (workspace: { slug: string }) => workspace.slug === \"${tenantMarker}\";`,
    });

    const result = runChecker(root);

    expect(result.status).toBe(1);
    expect(result.output).toContain("apps/web/src/runtime.ts");
    expect(result.output).toContain("reserved-tenant-term");
  });

  it("rejects a tenant formula identifier in the worker", async () => {
    const root = await createFixture({
      "apps/worker/src/task.ts": `export const ${formulaMarker}Schedule = [];`,
    });

    const result = runChecker(root);

    expect(result.status).toBe(1);
    expect(result.output).toContain("apps/worker/src/task.ts");
    expect(result.output).toContain("reserved-tenant-term");
  });

  it("rejects a tenant-owned stock convention in the worker", async () => {
    const root = await createFixture({
      "apps/worker/src/task.ts": `export const stockPattern = "${stockMarker}";`,
    });

    const result = runChecker(root);

    expect(result.status).toBe(1);
    expect(result.output).toContain("apps/worker/src/task.ts");
    expect(result.output).toContain("reserved-tenant-term");
  });

  it.each([
    ["ratio notation", `export const allocation = "${ratioParts.join("/")}";`],
    [
      "arithmetic share",
      `export const allocate = (amount: number) => amount * ${ratioParts[0] / 100};`,
    ],
  ])(
    "rejects tenant-owned %s in a platform package",
    async (_label, source) => {
      const root = await createFixture({
        "packages/calculations/src/index.ts": source,
      });

      const result = runChecker(root);

      expect(result.status).toBe(1);
      expect(result.output).toContain("packages/calculations/src/index.ts");
      expect(result.output).toContain("reserved-tenant-ratio");
    },
  );

  it("rejects a tenant-owned import from an ordinary shared script", async () => {
    const root = await createFixture({
      "scripts/tenant_loader.py": `from tenant_seeds.${tenantMarker}.fees import catalog`,
    });

    const result = runChecker(root);

    expect(result.status).toBe(1);
    expect(result.output).toContain("scripts/tenant_loader.py");
    expect(result.output).toContain("reserved-tenant-term");
  });

  it("rejects tenant identity data in reusable database fixtures", async () => {
    const root = await createFixture({
      "supabase/seed.sql": `insert into workspaces (slug) values ('${tenantMarker}');`,
    });

    const result = runChecker(root);

    expect(result.status).toBe(1);
    expect(result.output).toContain("supabase/seed.sql");
    expect(result.output).toContain("reserved-tenant-term");
  });
});
