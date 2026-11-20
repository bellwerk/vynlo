import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

// nginx2root (disclosed 2026-11-18): CVE-2026-123007, CVE-2026-123633,
// CVE-2026-123634, CVE-2026-121810 and CVE-2026-113425 are fixed in nginx
// 1.30.7 (stable) and 1.31.9 (mainline). Every older release in the affected
// ranges is rejected. OpenResty and Kong embed their own nginx builds and had
// no confirmed fixed release when this check was added, so they are rejected
// until a maintainer reviews a fixed version and adds it to FIXED_EMBEDDERS.
export const MINIMUM_FIXED_NGINX = Object.freeze({
  "1.30": [1, 30, 7],
  1.31: [1, 31, 9],
});
export const FIXED_EMBEDDERS = Object.freeze({
  openresty: null,
  kong: null,
});

const SKIPPED_DIRECTORIES = new Set([
  ".cache",
  ".git",
  ".next",
  ".turbo",
  "build",
  "coverage",
  "dist",
  "node_modules",
  "playwright-report",
  "test-results",
]);
const SCANNED_EXTENSIONS = new Set([
  ".conf",
  ".dockerfile",
  ".hcl",
  ".json",
  ".sh",
  ".tf",
  ".toml",
  ".yaml",
  ".yml",
]);

// Matches image references such as nginx:1.30.7-alpine,
// docker.io/library/nginx:1.31.9, nginxinc/nginx-unprivileged:1.30.7,
// openresty/openresty:1.27.1.2-alpine and kong/kong:3.9.1.
const IMAGE_PATTERN =
  /(?<![\w.-])(?:[\w.-]+(?::\d+)?\/)*(?<name>nginx|nginx-unprivileged|openresty|kong)(?::(?<tag>[\w.-]+))?(?:@sha256:[a-f0-9]{64})?(?![\w./-])/giu;

function isScannedFile(fileName) {
  const lower = fileName.toLocaleLowerCase("en");
  if (lower === "dockerfile" || lower.startsWith("dockerfile.")) return true;
  if (lower.startsWith("containerfile")) return true;
  return SCANNED_EXTENSIONS.has(path.extname(lower));
}

async function walkFiles(directory, visit) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return;
    throw error;
  }
  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (!SKIPPED_DIRECTORIES.has(entry.name))
        await walkFiles(path.join(directory, entry.name), visit);
    } else if (entry.isFile() && isScannedFile(entry.name)) {
      await visit(path.join(directory, entry.name));
    }
  }
}

function compareVersions(left, right) {
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference !== 0) return difference;
  }
  return 0;
}

export function assessNginxTag(tag) {
  if (!tag) return "unpinned nginx image; pin an exact patched version";
  const match = /^(\d+)\.(\d+)\.(\d+)(?:[-.].*)?$/u.exec(tag);
  if (!match)
    return `nginx tag "${tag}" is not an exact version; pin 1.30.7+ or 1.31.9+`;
  const version = match.slice(1, 4).map(Number);
  if (compareVersions(version, [1, 31, 9]) >= 0) return null;
  const branchMinimum = MINIMUM_FIXED_NGINX[`${version[0]}.${version[1]}`];
  if (branchMinimum && compareVersions(version, branchMinimum) >= 0)
    return null;
  return `nginx ${match.slice(1, 4).join(".")} is vulnerable to nginx2root; use 1.30.7+ (stable) or 1.31.9+ (mainline)`;
}

export function assessEmbedderTag(name, tag) {
  const fixed = FIXED_EMBEDDERS[name];
  if (!fixed)
    return `${name} embeds nginx and has no reviewed nginx2root-fixed release; review before use`;
  const match = /^(\d+(?:\.\d+)*)/u.exec(tag ?? "");
  if (!match) return `unpinned ${name} image; pin an exact patched version`;
  const version = match[1].split(".").map(Number);
  return compareVersions(version, fixed) >= 0
    ? null
    : `${name} ${match[1]} predates the reviewed nginx2root fix ${fixed.join(".")}`;
}

function locationFor(source, index) {
  const before = source.slice(0, index);
  const line = before.split("\n").length;
  return { line, column: index - before.lastIndexOf("\n") };
}

export function findViolations(source) {
  const violations = [];
  for (const match of source.matchAll(IMAGE_PATTERN)) {
    const name = match.groups.name.toLocaleLowerCase("en");
    const tag = match.groups.tag;
    // Ignore bare words (for example prose or package names) that carry no tag
    // and are not part of an image path or FROM/image: line.
    const lineStart = source.lastIndexOf("\n", match.index) + 1;
    const lineText = source.slice(lineStart, source.indexOf("\n", match.index));
    const looksLikeImage =
      Boolean(tag) ||
      match[0].includes("/") ||
      /^\s*(?:FROM\s|-?\s*image\s*[:=])/iu.test(lineText);
    if (!looksLikeImage) continue;

    const reason =
      name === "openresty" || name === "kong"
        ? assessEmbedderTag(name, tag)
        : assessNginxTag(tag);
    if (reason)
      violations.push({
        ...locationFor(source, match.index),
        image: match[0],
        reason,
      });
  }
  return violations;
}

export async function scanNginxVersions(repositoryRoot) {
  const root = path.resolve(repositoryRoot);
  const violations = [];
  let filesScanned = 0;

  await walkFiles(root, async (filePath) => {
    const relative = path.relative(root, filePath).split(path.sep).join("/");
    if (relative === "package.json" || relative.endsWith("/package.json"))
      return;
    if (relative.endsWith("lock.json") || relative.endsWith("lock.yaml"))
      return;
    filesScanned += 1;
    const source = await readFile(filePath, "utf8");
    for (const violation of findViolations(source))
      violations.push({ file: relative, ...violation });
  });

  return {
    filesScanned,
    violations: violations.sort((left, right) =>
      `${left.file}:${left.line}`.localeCompare(`${right.file}:${right.line}`),
    ),
  };
}

function rootFromArguments(arguments_) {
  if (arguments_.length === 0) return path.resolve(import.meta.dirname, "..");
  if (arguments_.length === 2 && arguments_[0] === "--root")
    return path.resolve(arguments_[1]);
  throw new Error("usage: node scripts/check-nginx-versions.mjs [--root PATH]");
}

async function main() {
  const result = await scanNginxVersions(
    rootFromArguments(process.argv.slice(2)),
  );
  if (result.violations.length > 0) {
    console.error("nginx_versions: fail");
    for (const violation of result.violations)
      console.error(
        `${violation.file}:${violation.line}:${violation.column} ${violation.image} — ${violation.reason}`,
      );
    process.exitCode = 1;
    return;
  }
  console.log(`nginx_versions: pass (${result.filesScanned} files scanned)`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) await main();
