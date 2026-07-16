import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const POLICY_FILE_NAME = "platform-boundary-policy.json";
const REUSABLE_ROOTS = ["apps", "packages", "scripts", "supabase"];
const SOURCE_EXTENSIONS = new Set([
  ".bash",
  ".cjs",
  ".css",
  ".cts",
  ".js",
  ".jsx",
  ".json",
  ".less",
  ".mjs",
  ".mts",
  ".ps1",
  ".py",
  ".sass",
  ".scss",
  ".sh",
  ".sql",
  ".toml",
  ".ts",
  ".tsx",
  ".yaml",
  ".yml",
]);
const GENERATED_DIRECTORIES = new Set([
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
const HASH_COMMENT_EXTENSIONS = new Set([
  ".bash",
  ".ps1",
  ".py",
  ".sh",
  ".toml",
  ".yaml",
  ".yml",
]);
const SLASH_COMMENT_EXTENSIONS = new Set([
  ".cjs",
  ".css",
  ".cts",
  ".js",
  ".jsx",
  ".less",
  ".mjs",
  ".mts",
  ".sass",
  ".scss",
  ".ts",
  ".tsx",
]);

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function readDirectory(directory) {
  try {
    return await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error?.code === "ENOENT") return [];
    throw error;
  }
}

async function walkFiles(directory, visit) {
  for (const entry of await readDirectory(directory)) {
    if (entry.isSymbolicLink() || GENERATED_DIRECTORIES.has(entry.name))
      continue;

    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) await walkFiles(fullPath, visit);
    else if (entry.isFile()) await visit(fullPath);
  }
}

function maskCharacter(character) {
  return character === "\n" || character === "\r" ? character : " ";
}

function stripSlashComments(source) {
  const result = source.split("");
  let quote = null;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];

    if (quote !== null) {
      if (character === "\\") {
        index += 1;
        continue;
      }
      if (character === quote) quote = null;
      continue;
    }

    if (character === '"' || character === "'" || character === "`") {
      quote = character;
      continue;
    }

    if (character === "/" && next === "/") {
      while (index < source.length && source[index] !== "\n") {
        result[index] = maskCharacter(source[index]);
        index += 1;
      }
      index -= 1;
      continue;
    }

    if (character === "/" && next === "*") {
      result[index] = " ";
      result[index + 1] = " ";
      index += 2;
      while (
        index < source.length &&
        !(source[index] === "*" && source[index + 1] === "/")
      ) {
        result[index] = maskCharacter(source[index]);
        index += 1;
      }
      if (index < source.length) {
        result[index] = " ";
        result[index + 1] = " ";
        index += 1;
      }
    }
  }

  return result.join("");
}

function stripHashComments(source, stripDocstrings) {
  const result = source.split("");
  let quote = null;
  let tripleQuote = null;
  let tripleQuoteIsDocumentation = false;
  let lineHasCode = false;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];

    if (tripleQuote !== null) {
      if (source.startsWith(tripleQuote, index)) {
        if (tripleQuoteIsDocumentation) {
          for (let offset = 0; offset < 3; offset += 1)
            result[index + offset] = " ";
        }
        index += 2;
        tripleQuote = null;
        tripleQuoteIsDocumentation = false;
      } else if (tripleQuoteIsDocumentation) {
        result[index] = maskCharacter(character);
      }
      if (character === "\n") lineHasCode = false;
      continue;
    }

    if (quote !== null) {
      if (character === "\\") {
        index += 1;
        continue;
      }
      if (character === quote) quote = null;
      if (character === "\n") lineHasCode = false;
      continue;
    }

    if (
      stripDocstrings &&
      (source.startsWith('"""', index) || source.startsWith("'''", index))
    ) {
      tripleQuote = source.slice(index, index + 3);
      tripleQuoteIsDocumentation = !lineHasCode;
      if (tripleQuoteIsDocumentation) {
        result[index] = " ";
        result[index + 1] = " ";
        result[index + 2] = " ";
      }
      index += 2;
      continue;
    }

    if (character === '"' || character === "'") {
      quote = character;
      lineHasCode = true;
      continue;
    }

    if (character === "#") {
      while (index < source.length && source[index] !== "\n") {
        result[index] = maskCharacter(source[index]);
        index += 1;
      }
      index -= 1;
      continue;
    }

    if (character === "\n") lineHasCode = false;
    else if (!/\s/u.test(character)) lineHasCode = true;
  }

  return result.join("");
}

function stripComments(source, extension) {
  if (SLASH_COMMENT_EXTENSIONS.has(extension))
    return stripSlashComments(source);
  if (HASH_COMMENT_EXTENSIONS.has(extension))
    return stripHashComments(source, extension === ".py");
  return source;
}

function escapeRegularExpression(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}

function normalizedParts(value) {
  return value
    .normalize("NFKC")
    .toLocaleLowerCase("en")
    .split(/[\s_./\\:-]+/u)
    .filter(Boolean);
}

function splitIdentifier(identifier) {
  return identifier
    .replace(/([\p{Ll}\p{N}])(\p{Lu})/gu, "$1 $2")
    .replace(/(\p{Lu}+)(\p{Lu}\p{Ll})/gu, "$1 $2")
    .split(/[$_\s]+/u)
    .filter(Boolean)
    .map((part) => part.normalize("NFKC").toLocaleLowerCase("en"));
}

function findReservedTerm(source, value) {
  const parts = normalizedParts(value);
  if (parts.length === 0) return -1;

  const separatedSource = parts
    .map(escapeRegularExpression)
    .join("[\\s_./\\\\:-]+");
  const separatedMatch = new RegExp(
    `(?<![\\p{L}\\p{N}])${separatedSource}(?![\\p{L}\\p{N}])`,
    "iu",
  ).exec(source);
  if (separatedMatch) return separatedMatch.index;

  const identifierExpression = /[$_\p{L}][$_\p{L}\p{N}]*/gu;
  for (const match of source.matchAll(identifierExpression)) {
    const identifierParts = splitIdentifier(match[0]);
    for (
      let start = 0;
      start <= identifierParts.length - parts.length;
      start += 1
    ) {
      if (
        parts.every((part, offset) => identifierParts[start + offset] === part)
      )
        return match.index;
    }
  }

  return -1;
}

function decimalPattern(part) {
  const decimal = (part / 100).toString();
  const [, fraction = ""] = decimal.split(".");
  return `(?<![\\d.])(?:0)?\\.${escapeRegularExpression(fraction)}0*(?!\\d)`;
}

function findReservedRatio(source, parts) {
  const [first, second] = parts;
  const explicitPair = new RegExp(
    `(?<!\\d)${first}\\s*%?\\s*(?:[/:-]|to)\\s*${second}\\s*%?(?!\\d)`,
    "iu",
  ).exec(source);
  if (explicitPair) return explicitPair.index;

  const firstDecimal = decimalPattern(first);
  const secondDecimal = decimalPattern(second);
  const firstMatch = new RegExp(firstDecimal, "u").exec(source);
  const secondMatch = new RegExp(secondDecimal, "u").exec(source);
  if (firstMatch && secondMatch)
    return Math.min(firstMatch.index, secondMatch.index);

  const numericWrapper = `(?:(?:new\\s+)?[A-Za-z_$][\\w$]*\\s*\\(\\s*[\"']?${firstDecimal}[\"']?\\s*\\)|${firstDecimal})`;
  const arithmeticShare = new RegExp(
    `(?:[*/]\\s*${numericWrapper}|${numericWrapper}\\s*[*/])`,
    "u",
  ).exec(source);
  return arithmeticShare?.index ?? -1;
}

function locationFor(source, index) {
  const before = source.slice(0, index);
  const lines = before.split(/\r?\n/u);
  return {
    line: lines.length,
    column: (lines.at(-1)?.length ?? 0) + 1,
  };
}

function validatePolicy(document, policyPath) {
  if (!isRecord(document) || document.schema_version !== 1)
    throw new Error(`${policyPath}: schema_version must be 1`);

  const terms = document.reserved_terms ?? [];
  const ratios = document.reserved_ratios ?? [];
  if (!Array.isArray(terms) || !Array.isArray(ratios))
    throw new Error(`${policyPath}: reserved terms and ratios must be arrays`);

  for (const entry of terms) {
    if (
      !isRecord(entry) ||
      typeof entry.value !== "string" ||
      entry.value.trim().length < 2 ||
      typeof entry.reason !== "string" ||
      entry.reason.trim().length === 0
    )
      throw new Error(`${policyPath}: invalid reserved term`);
  }

  for (const entry of ratios) {
    if (
      !isRecord(entry) ||
      !Array.isArray(entry.parts) ||
      entry.parts.length !== 2 ||
      !entry.parts.every((part) => Number.isInteger(part) && part > 0) ||
      entry.parts[0] + entry.parts[1] !== 100 ||
      typeof entry.reason !== "string" ||
      entry.reason.trim().length === 0
    )
      throw new Error(`${policyPath}: invalid reserved ratio`);
  }

  return { terms, ratios };
}

async function loadBoundaryPolicy(root) {
  const tenantRoot = path.join(root, "tenant-seeds");
  const terms = [];
  const ratios = [];
  const policyFiles = [];

  for (const entry of await readDirectory(tenantRoot)) {
    if (!entry.isDirectory() || entry.isSymbolicLink()) continue;

    terms.push({ value: entry.name, reason: "tenant workspace key" });
    await walkFiles(path.join(tenantRoot, entry.name), async (filePath) => {
      if (path.basename(filePath) !== POLICY_FILE_NAME) return;
      const document = JSON.parse(await readFile(filePath, "utf8"));
      const policy = validatePolicy(document, path.relative(root, filePath));
      terms.push(...policy.terms);
      ratios.push(...policy.ratios);
      policyFiles.push(filePath);
    });
  }

  const uniqueTerms = [
    ...new Map(
      terms.map((entry) => [
        entry.value.normalize("NFKC").toLocaleLowerCase("en"),
        entry,
      ]),
    ).values(),
  ];
  const uniqueRatios = [
    ...new Map(ratios.map((entry) => [entry.parts.join(":"), entry])).values(),
  ];

  return { terms: uniqueTerms, ratios: uniqueRatios, policyFiles };
}

export async function scanTenantBoundaries(repositoryRoot) {
  const root = path.resolve(repositoryRoot);
  const policy = await loadBoundaryPolicy(root);
  const violations = [];
  let filesScanned = 0;

  for (const reusableRoot of REUSABLE_ROOTS) {
    await walkFiles(path.join(root, reusableRoot), async (filePath) => {
      const extension = path.extname(filePath).toLocaleLowerCase("en");
      if (!SOURCE_EXTENSIONS.has(extension)) return;

      filesScanned += 1;
      const source = stripComments(await readFile(filePath, "utf8"), extension);

      for (const entry of policy.terms) {
        const index = findReservedTerm(source, entry.value);
        if (index < 0) continue;
        violations.push({
          file: path.relative(root, filePath).split(path.sep).join("/"),
          ...locationFor(source, index),
          rule: "reserved-tenant-term",
          reason: entry.reason,
        });
      }

      for (const entry of policy.ratios) {
        const index = findReservedRatio(source, entry.parts);
        if (index < 0) continue;
        violations.push({
          file: path.relative(root, filePath).split(path.sep).join("/"),
          ...locationFor(source, index),
          rule: "reserved-tenant-ratio",
          reason: entry.reason,
        });
      }
    });
  }

  return {
    filesScanned,
    policyFiles: policy.policyFiles.length,
    violations: violations.sort((left, right) =>
      `${left.file}:${left.line}:${left.rule}`.localeCompare(
        `${right.file}:${right.line}:${right.rule}`,
      ),
    ),
  };
}

function rootFromArguments(arguments_) {
  if (arguments_.length === 0) return path.resolve(import.meta.dirname, "..");
  if (arguments_.length === 2 && arguments_[0] === "--root")
    return path.resolve(arguments_[1]);
  throw new Error(
    "usage: node scripts/check-package-boundaries.mjs [--root PATH]",
  );
}

async function main() {
  const result = await scanTenantBoundaries(
    rootFromArguments(process.argv.slice(2)),
  );
  if (result.violations.length > 0) {
    console.error("package_boundaries: fail");
    for (const violation of result.violations)
      console.error(
        `${violation.file}:${violation.line}:${violation.column} [${violation.rule}] ${violation.reason}`,
      );
    process.exitCode = 1;
    return;
  }

  console.log(
    `package_boundaries: pass (${result.filesScanned} reusable files, ${result.policyFiles} tenant policies)`,
  );
}

const invokedPath = process.argv[1]
  ? pathToFileURL(path.resolve(process.argv[1])).href
  : null;
if (invokedPath === import.meta.url)
  main().catch((error) => {
    console.error(`package_boundaries: error\n${error.message}`);
    process.exitCode = 1;
  });
