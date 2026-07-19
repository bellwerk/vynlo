// Stable test IDs: T-UX-002.
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { Button, cn } from "./index";
import { Button as ButtonFromSubpath } from "@vynlo/ui-web/components/button";
import { cn as cnFromSubpath } from "@vynlo/ui-web/lib/utils";

interface ComponentsConfig {
  readonly aliases: Readonly<Record<string, string>>;
}

interface PackageConfig {
  readonly exports: Readonly<Record<string, string>>;
  readonly imports: Readonly<Record<string, string>>;
}

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../..");
const appRoot = resolve(repositoryRoot, "apps/web");

function readJson<T>(path: string): T {
  return JSON.parse(readFileSync(path, "utf8")) as T;
}

function resolvePackageExport(
  packageConfig: PackageConfig,
  specifier: string,
): string {
  const subpath = `.${specifier.replace("@vynlo/ui-web", "")}`;
  const exactTarget = packageConfig.exports[subpath];
  if (exactTarget) return resolve(packageRoot, exactTarget);

  for (const [exportPattern, targetPattern] of Object.entries(
    packageConfig.exports,
  )) {
    const wildcardIndex = exportPattern.indexOf("*");
    if (wildcardIndex === -1) continue;

    const prefix = exportPattern.slice(0, wildcardIndex);
    const suffix = exportPattern.slice(wildcardIndex + 1);
    if (!subpath.startsWith(prefix) || !subpath.endsWith(suffix)) continue;

    const wildcard = subpath.slice(
      prefix.length,
      subpath.length - suffix.length,
    );
    return resolve(packageRoot, targetPattern.replace("*", wildcard));
  }

  throw new Error(`No package export resolves ${specifier}`);
}

describe("shadcn monorepo structure", () => {
  const appConfig = readJson<ComponentsConfig>(
    resolve(appRoot, "components.json"),
  );
  const packageConfig = readJson<PackageConfig>(
    resolve(packageRoot, "package.json"),
  );
  const packageComponentsConfig = readJson<ComponentsConfig>(
    resolve(packageRoot, "components.json"),
  );

  it("routes app components, shared UI, and utilities to distinct targets", () => {
    expect(appConfig.aliases).toMatchObject({
      components: "@/components",
      ui: "@vynlo/ui-web/components",
      utils: "@vynlo/ui-web/lib/utils",
    });

    const componentTarget = resolve(
      appRoot,
      appConfig.aliases.components?.replace("@/", "") ?? "",
    );
    const uiTarget = resolvePackageExport(
      packageConfig,
      `${appConfig.aliases.ui}/button`,
    );
    const utilityTarget = resolvePackageExport(
      packageConfig,
      appConfig.aliases.utils ?? "",
    );

    expect(componentTarget).toBe(resolve(appRoot, "components"));
    expect(uiTarget).toBe(resolve(packageRoot, "src/components/button.tsx"));
    expect(utilityTarget).toBe(resolve(packageRoot, "src/lib/utils.ts"));
    expect(new Set([componentTarget, uiTarget, utilityTarget]).size).toBe(3);
    expect(existsSync(componentTarget)).toBe(true);
    expect(existsSync(uiTarget)).toBe(true);
    expect(existsSync(utilityTarget)).toBe(true);
  });

  it("keeps package-local generator aliases aligned with package imports", () => {
    expect(packageComponentsConfig.aliases).toMatchObject({
      components: "#components",
      hooks: "#hooks",
      lib: "#lib",
      ui: "#components",
      utils: "#lib/utils",
    });
    expect(packageConfig.imports).toMatchObject({
      "#components/*": "./src/components/*.tsx",
      "#hooks/*": "./src/hooks/*.ts",
      "#lib/*": "./src/lib/*.ts",
    });
  });

  it("exposes stable root and generated-style subpath imports", () => {
    expect(ButtonFromSubpath).toBe(Button);
    expect(cnFromSubpath).toBe(cn);
    expect(cn("px-2", false && "hidden", ["px-4", "font-bold"])).toBe(
      "px-4 font-bold",
    );
  });
});
