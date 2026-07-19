#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const CODE_EXTENSIONS = new Set([
  ".cjs",
  ".css",
  ".js",
  ".jsx",
  ".mjs",
  ".ts",
  ".tsx",
]);
const JSX_EXTENSIONS = new Set([".jsx", ".tsx"]);
const IGNORED_DIRECTORIES = new Set([
  ".git",
  ".next",
  "coverage",
  "dist",
  "node_modules",
  "playwright-report",
  "test-results",
]);
const RAW_COLOR_METADATA_FILES = new Set([
  // Browser/PWA metadata must serialize concrete colors; CSS variables are invalid here.
  "apps/web/app/layout.tsx",
  "apps/web/app/manifest.ts",
]);

const RAW_CONTROL = /<\s*(button|input|select|textarea)\b/gu;
const DIRECT_RADIX_IMPORT =
  /(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s*)["'](?:@radix-ui\/[^"']+|radix-ui(?:\/[^"']*)?)["']/gu;
const RAW_COLOR =
  /#[\da-f]{3,8}\b|\b(?:color|hsl|hsla|lab|lch|oklab|oklch|rgb|rgba)\(\s*[^)]*\)|\b(?:bg|border|fill|outline|ring|shadow|stroke|text)-(?:amber|blue|cyan|emerald|fuchsia|gray|green|indigo|lime|neutral|orange|pink|purple|red|rose|sky|slate|stone|teal|violet|yellow|zinc)-\d{2,3}\b/giu;
const TRANSITION_ALL = /\btransition-all\b|\btransition\s*:\s*all\b/giu;
const DISALLOWED_TRANSITION =
  /\btransition-(?:colors|shadow)\b|\btransition-\[[^\]]*(?:background|border|color|filter|height|shadow|width)[^\]]*\]|\btransition(?:-property)?\s*:[^;]*(?:background|border|color|filter|height|shadow|width)[^;]*;/giu;
const THICK_SIDE_STRIPE =
  /\bborder-[lr]-[3-9]\b|\bborder-(?:left|right)(?:-width)?\s*:\s*(?:[3-9]|\d{2,})px\b/giu;
const MILESTONE_SHELL_DUPLICATION = /<\s*(?:aside|nav)\b/giu;

/**
 * UI-MIG-06 enforcement ceiling.
 *
 * The migration is complete, so every prohibited rule has a permanent zero
 * allowance. Keep the explicit rule map checked in: it documents the contract
 * and prevents CI from silently accepting a newly generated debt baseline.
 */
export const ENFORCEMENT_CEILING = Object.freeze({
  "disallowed-transition": Object.freeze({}),
  "direct-radix": Object.freeze({}),
  "milestone-shell-duplication": Object.freeze({}),
  "raw-color": Object.freeze({}),
  "raw-interactive": Object.freeze({}),
  "side-stripe": Object.freeze({}),
  "transition-all": Object.freeze({}),
});

function normalizeRelativePath(value) {
  return value.split(path.sep).join("/").replace(/^\.\//u, "");
}

function isWithin(relativePath, prefix) {
  return relativePath === prefix || relativePath.startsWith(`${prefix}/`);
}

function lineAndColumn(source, index) {
  const before = source.slice(0, index);
  const lines = before.split("\n");
  return { column: lines.at(-1).length + 1, line: lines.length };
}

/** Remove comments while preserving offsets and quoted strings. */
function maskComments(source) {
  const output = [...source];
  let quote = null;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];

    if (quote) {
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
      output[index] = " ";
      output[index + 1] = " ";
      index += 2;
      while (index < source.length && source[index] !== "\n") {
        output[index] = " ";
        index += 1;
      }
      index -= 1;
      continue;
    }

    if (character === "/" && next === "*") {
      output[index] = " ";
      output[index + 1] = " ";
      index += 2;
      while (
        index < source.length &&
        !(source[index] === "*" && source[index + 1] === "/")
      ) {
        if (source[index] !== "\n" && source[index] !== "\r") {
          output[index] = " ";
        }
        index += 1;
      }
      if (index < source.length) {
        output[index] = " ";
        output[index + 1] = " ";
        index += 1;
      }
    }
  }

  return output.join("");
}

/** Remove quoted values while preserving offsets for structural JSX checks. */
function maskQuotedStrings(source) {
  const output = [...source];
  let quote = null;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (!quote) {
      if (character === '"' || character === "'" || character === "`") {
        quote = character;
        output[index] = " ";
      }
      continue;
    }

    if (character !== "\n" && character !== "\r") output[index] = " ";
    if (character === "\\") {
      index += 1;
      if (index < source.length && source[index] !== "\n") output[index] = " ";
      continue;
    }
    if (character === quote) quote = null;
  }

  return output.join("");
}

function collectMatches({ description, file, pattern, rule, source }) {
  const findings = [];
  pattern.lastIndex = 0;

  for (const match of source.matchAll(pattern)) {
    const location = lineAndColumn(source, match.index);
    findings.push({
      ...location,
      description,
      file,
      match: match[0].replace(/\s+/gu, " ").trim().slice(0, 100),
      rule,
    });
  }

  return findings;
}

/** Inspect one source file. Exported for checker unit tests. */
export function inspectSource(relativePath, source) {
  const file = normalizeRelativePath(relativePath);
  const extension = path.extname(file).toLowerCase();
  const uncommented = maskComments(source);
  const structuralSource = maskQuotedStrings(uncommented);
  const findings = [];
  const isSharedUiSource = isWithin(file, "packages/ui-web/src");
  const isDesignTokenSource = isWithin(file, "packages/design-tokens");
  const isWebUiSource = isWithin(file, "apps/web");
  const isMilestoneShell =
    isWebUiSource && /\/m\d+-operator-shell\.[cm]?[jt]sx?$/u.test(file);

  if (JSX_EXTENSIONS.has(extension) && isWebUiSource && !isSharedUiSource) {
    findings.push(
      ...collectMatches({
        description:
          "Use the matching @vynlo/ui-web primitive instead of a raw interactive element.",
        file,
        pattern: RAW_CONTROL,
        rule: "raw-interactive",
        source: structuralSource,
      }),
    );
  }

  if (!isSharedUiSource) {
    findings.push(
      ...collectMatches({
        description:
          "Radix primitives are owned by packages/ui-web; import the Vynlo wrapper instead.",
        file,
        pattern: DIRECT_RADIX_IMPORT,
        rule: "direct-radix",
        source: uncommented,
      }),
    );
  }

  if (isMilestoneShell) {
    findings.push(
      ...collectMatches({
        description:
          "Milestone shell adapters must delegate to the shared OperatorShell instead of recreating navigation chrome.",
        file,
        pattern: MILESTONE_SHELL_DUPLICATION,
        rule: "milestone-shell-duplication",
        source: structuralSource,
      }),
    );
  }

  if (
    (isWebUiSource || isSharedUiSource) &&
    !isDesignTokenSource &&
    !RAW_COLOR_METADATA_FILES.has(file)
  ) {
    findings.push(
      ...collectMatches({
        description:
          "Use a semantic design token instead of a raw or palette-specific color.",
        file,
        pattern: RAW_COLOR,
        rule: "raw-color",
        source: uncommented,
      }),
      ...collectMatches({
        description:
          "List transition properties explicitly; transition-all is not permitted.",
        file,
        pattern: TRANSITION_ALL,
        rule: "transition-all",
        source: uncommented,
      }),
      ...collectMatches({
        description:
          "Vynlo motion may animate only opacity and transform; color, geometry, filter, and shadow transitions are not permitted.",
        file,
        pattern: DISALLOWED_TRANSITION,
        rule: "disallowed-transition",
        source: uncommented,
      }),
      ...collectMatches({
        description:
          "Use a neutral one-pixel separator or a complete semantic border instead of a thick colored side stripe.",
        file,
        pattern: THICK_SIDE_STRIPE,
        rule: "side-stripe",
        source: uncommented,
      }),
    );
  }

  return findings.sort(
    (left, right) => left.line - right.line || left.column - right.column,
  );
}

async function walk(directory, rootDirectory) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error?.code === "ENOENT") return [];
    throw error;
  }

  const files = [];
  for (const entry of entries.sort((left, right) =>
    left.name.localeCompare(right.name),
  )) {
    if (entry.isDirectory() && IGNORED_DIRECTORIES.has(entry.name)) continue;
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walk(absolutePath, rootDirectory)));
    } else if (
      entry.isFile() &&
      CODE_EXTENSIONS.has(path.extname(entry.name))
    ) {
      files.push(
        normalizeRelativePath(path.relative(rootDirectory, absolutePath)),
      );
    }
  }
  return files;
}

export function countsByRuleAndFile(findings) {
  const counts = {};
  for (const finding of findings) {
    counts[finding.rule] ??= {};
    counts[finding.rule][finding.file] =
      (counts[finding.rule][finding.file] ?? 0) + 1;
  }

  return Object.fromEntries(
    Object.entries(counts)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([rule, files]) => [
        rule,
        Object.fromEntries(
          Object.entries(files).sort(([left], [right]) =>
            left.localeCompare(right),
          ),
        ),
      ]),
  );
}

/** Compare findings to the checked-in per-rule, per-file debt ceiling. */
export function evaluateFindings(findings, baseline = ENFORCEMENT_CEILING) {
  const grouped = new Map();
  for (const finding of findings) {
    const key = `${finding.rule}\u0000${finding.file}`;
    const group = grouped.get(key) ?? [];
    group.push(finding);
    grouped.set(key, group);
  }

  const regressions = [];
  const improvements = [];
  const actual = countsByRuleAndFile(findings);
  const ruleNames = new Set([...Object.keys(baseline), ...Object.keys(actual)]);

  for (const rule of [...ruleNames].sort()) {
    const fileNames = new Set([
      ...Object.keys(baseline[rule] ?? {}),
      ...Object.keys(actual[rule] ?? {}),
    ]);
    for (const file of [...fileNames].sort()) {
      const allowed = baseline[rule]?.[file] ?? 0;
      const count = actual[rule]?.[file] ?? 0;
      if (count > allowed) {
        const group = grouped.get(`${rule}\u0000${file}`) ?? [];
        regressions.push({
          actual: count,
          allowed,
          file,
          findings: group.slice(allowed),
          rule,
        });
      } else if (count < allowed) {
        improvements.push({ actual: count, allowed, file, rule });
      }
    }
  }

  return { actual, findings, improvements, regressions };
}

/** Scan UI-bearing workspace source without following generated output. */
export async function scanUiSystem({
  baseline = ENFORCEMENT_CEILING,
  rootDirectory = process.cwd(),
} = {}) {
  const roots = ["apps", "packages"];
  const files = (
    await Promise.all(
      roots.map((relativeRoot) =>
        walk(path.join(rootDirectory, relativeRoot), rootDirectory),
      ),
    )
  )
    .flat()
    .sort();

  const findings = [];
  for (const file of files) {
    const source = await readFile(path.join(rootDirectory, file), "utf8");
    findings.push(...inspectSource(file, source));
  }

  return evaluateFindings(findings, baseline);
}

export function formatReport(report) {
  const totalFindings = report.findings.length;
  if (report.regressions.length === 0) {
    return `UI system check passed (${totalFindings} prohibited findings; permanent zero-debt policy enforced).`;
  }

  const lines = [
    `UI system check failed with ${report.regressions.length} regression group(s).`,
  ];
  for (const regression of report.regressions) {
    lines.push(
      `\n${regression.rule} ${regression.file}: ${regression.actual} found, ${regression.allowed} allowed`,
    );
    for (const finding of regression.findings) {
      lines.push(
        `  ${finding.file}:${finding.line}:${finding.column} ${finding.match} — ${finding.description}`,
      );
    }
  }
  lines.push(
    "\nReplace the regression with Vynlo UI primitives/tokens. Do not raise the baseline to make CI green.",
  );
  return lines.join("\n");
}

async function main() {
  const argumentsList = new Set(process.argv.slice(2));
  const report = await scanUiSystem();

  if (argumentsList.has("--print-baseline")) {
    console.log(JSON.stringify(report.actual, null, 2));
    return;
  }
  if (argumentsList.has("--json")) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log(formatReport(report));
  }
  if (report.regressions.length > 0) process.exitCode = 1;
}

const isEntrypoint =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;

if (isEntrypoint) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
