import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = process.cwd();
const routeRoot = path.join(root, "apps", "web", "app", "api", "v1");
const contractPath = path.join(root, "contracts", "openapi.v1.yaml");
const httpMethods = new Set([
  "delete",
  "get",
  "head",
  "options",
  "patch",
  "post",
  "put",
]);
const m3Prefixes = [
  "/activities",
  "/appointments",
  "/custom-field-definitions",
  "/deal-line-items",
  "/deals",
  "/finance-applications",
  "/leads",
  "/parties",
  "/payment-transactions",
  "/tasks",
  "/trade-ins",
  "/workflow-definitions",
  "/workflow-versions",
];

function isM3Path(value) {
  return m3Prefixes.some(
    (prefix) => value === prefix || value.startsWith(`${prefix}/`),
  );
}

function isQueryParityPath(value) {
  return isM3Path(value) || value === "/inventory-units";
}

async function routeFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) return routeFiles(target);
      return entry.isFile() && entry.name === "route.ts" ? [target] : [];
    }),
  );
  return nested.flat();
}

function filesystemRoutePath(file) {
  const relative = path.relative(routeRoot, path.dirname(file));
  const segments = relative
    .split(path.sep)
    .filter(Boolean)
    .map((segment) =>
      segment.startsWith("[") && segment.endsWith("]")
        ? `{${segment.slice(1, -1)}}`
        : segment,
    );
  return `/${segments.join("/")}`;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}

export function extractQueryParameters(source) {
  const parameters = new Set();
  const directSearchParameter =
    /\bsearchParams\s*\.\s*(?:get|getAll|has)\s*\(\s*(["'\x60])([^"'\x60]+)\1/gu;
  for (const match of source.matchAll(directSearchParameter)) {
    parameters.add(match[2]);
  }

  const aliases = new Set();
  const searchParameterAlias =
    /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*[^;\r\n]*\bsearchParams\s*;/gu;
  for (const match of source.matchAll(searchParameterAlias)) {
    aliases.add(match[1]);
  }
  for (const alias of aliases) {
    const aliasSearchParameter = new RegExp(
      `\\b${escapeRegExp(alias)}\\s*\\.\\s*(?:get|getAll|has)\\s*\\(\\s*(["'\\x60])([^"'\\x60]+)\\1`,
      "gu",
    );
    for (const match of source.matchAll(aliasSearchParameter)) {
      parameters.add(match[2]);
    }
  }
  return parameters;
}

function matchingDelimiter(source, start, opening, closing) {
  let depth = 0;
  let state = "code";
  for (let index = start; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];

    if (state === "line-comment") {
      if (character === "\n") state = "code";
      continue;
    }
    if (state === "block-comment") {
      if (character === "*" && next === "/") {
        state = "code";
        index += 1;
      }
      continue;
    }
    if (state !== "code") {
      if (character === "\\") {
        index += 1;
      } else if (
        (state === "single-quote" && character === "'") ||
        (state === "double-quote" && character === '"') ||
        (state === "template" && character === "`")
      ) {
        state = "code";
      }
      continue;
    }

    if (character === "/" && next === "/") {
      state = "line-comment";
      index += 1;
      continue;
    }
    if (character === "/" && next === "*") {
      state = "block-comment";
      index += 1;
      continue;
    }
    if (character === "'") {
      state = "single-quote";
      continue;
    }
    if (character === '"') {
      state = "double-quote";
      continue;
    }
    if (character === "`") {
      state = "template";
      continue;
    }
    if (character === opening) depth += 1;
    if (character === closing) {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}

function routeFunctionSource(source, declaration) {
  const parameterStart = declaration.index + declaration[0].lastIndexOf("(");
  const parameterEnd = matchingDelimiter(source, parameterStart, "(", ")");
  const bodyStart = source.indexOf("{", parameterEnd + 1);
  const bodyEnd = matchingDelimiter(source, bodyStart, "{", "}");
  if (parameterEnd < 0 || bodyStart < 0 || bodyEnd < 0) {
    throw new Error(`Unable to isolate route method ${declaration[1]}`);
  }
  return source.slice(declaration.index, bodyEnd + 1);
}

export function routeOperationsFromSource(source, routePath, file = null) {
  const operations = new Map();
  const exports = [
    ...source.matchAll(
      /export\s+(?:async\s+)?function\s+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*\(/gu,
    ),
  ];
  for (const current of exports) {
    const method = current[1].toLowerCase();
    const methodSource = routeFunctionSource(source, current);
    operations.set(`${method} ${routePath}`, {
      file,
      method,
      path: routePath,
      queryParameters: extractQueryParameters(methodSource),
    });
  }
  return operations;
}

async function implementedOperations() {
  const operations = new Map();
  for (const file of await routeFiles(routeRoot)) {
    const routePath = filesystemRoutePath(file);
    if (!isQueryParityPath(routePath)) continue;
    const source = await readFile(file, "utf8");
    for (const [operation, details] of routeOperationsFromSource(
      source,
      routePath,
      file,
    )) {
      operations.set(operation, details);
    }
  }
  return operations;
}

export function documentedOperations(source) {
  const lines = source.split(/\r?\n/u);
  const operations = new Map();
  const pathCounts = new Map();
  let currentPath = null;
  let currentMethod = null;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const pathMatch = /^ {2}(\/[^:]+):\s*$/u.exec(line);
    if (pathMatch) {
      currentPath = pathMatch[1];
      currentMethod = null;
      pathCounts.set(currentPath, (pathCounts.get(currentPath) ?? 0) + 1);
      continue;
    }
    if (/^components:\s*$/u.test(line)) {
      currentPath = null;
      currentMethod = null;
      continue;
    }
    if (currentPath === null) continue;

    const methodMatch = /^ {4}([a-z]+):\s*$/u.exec(line);
    if (methodMatch && httpMethods.has(methodMatch[1])) {
      currentMethod = methodMatch[1];
      const key = `${currentMethod} ${currentPath}`;
      operations.set(key, {
        body: [],
        line: index + 1,
        operationId: null,
        path: currentPath,
      });
      continue;
    }
    if (currentMethod === null) continue;

    const key = `${currentMethod} ${currentPath}`;
    const operation = operations.get(key);
    operation.body.push(line);
    const operationId = /^ {6}operationId:\s*([^\s#]+)\s*$/u.exec(line);
    if (operationId) operation.operationId = operationId[1];
  }

  return { operations, pathCounts };
}

function yamlScalar(value) {
  const trimmed = value.trim();
  if (
    trimmed.length >= 2 &&
    ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
      (trimmed.startsWith('"') && trimmed.endsWith('"')))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

export function documentedComponentParameters(source) {
  const parameters = new Map();
  const lines = source.split(/\r?\n/u);
  let inParameters = false;
  let current = null;

  for (const line of lines) {
    if (/^ {2}parameters:\s*$/u.test(line)) {
      inParameters = true;
      current = null;
      continue;
    }
    if (!inParameters) continue;
    if (/^ {2}\S/u.test(line)) break;

    const keyMatch = /^ {4}([^\s:]+):\s*$/u.exec(line);
    if (keyMatch) {
      current = { key: keyMatch[1], location: null, name: null };
      parameters.set(current.key, current);
      continue;
    }
    if (current === null) continue;
    const nameMatch = /^ {6}name:\s*(.+?)\s*$/u.exec(line);
    if (nameMatch) current.name = yamlScalar(nameMatch[1]);
    const locationMatch = /^ {6}in:\s*([^\s#]+)\s*$/u.exec(line);
    if (locationMatch) current.location = locationMatch[1];
  }
  return parameters;
}

export function documentedQueryParameters(
  operation,
  componentParameters = new Map(),
) {
  const parameters = new Set();
  let inParameters = false;
  let currentName = null;

  for (const line of operation.body) {
    if (/^ {6}parameters:\s*$/u.test(line)) {
      inParameters = true;
      currentName = null;
      continue;
    }
    if (!inParameters) continue;
    if (/^ {6}(?!-\s)\S/u.test(line)) {
      inParameters = false;
      currentName = null;
      continue;
    }

    const nameMatch = /^ {6}- name:\s*(.+?)\s*$/u.exec(line);
    if (nameMatch) {
      currentName = yamlScalar(nameMatch[1]);
      continue;
    }
    const referenceMatch =
      /^ {6}- \$ref:\s*['"]?#\/components\/parameters\/([^'"\s]+)['"]?\s*$/u.exec(
        line,
      );
    if (referenceMatch) {
      const referenced = componentParameters.get(referenceMatch[1]);
      if (referenced?.location === "query" && referenced.name !== null) {
        parameters.add(referenced.name);
      }
      currentName = null;
      continue;
    }
    if (/^ {6}- /u.test(line)) currentName = null;

    const locationMatch = /^ {8}in:\s*([^\s#]+)\s*$/u.exec(line);
    if (locationMatch?.[1] === "query" && currentName !== null) {
      parameters.add(currentName);
    }
  }
  return parameters;
}

export function queryParameterParityErrors(
  operation,
  implementedParameters,
  documentedParameters,
) {
  const errors = [];
  for (const parameter of sorted(implementedParameters)) {
    if (!documentedParameters.has(parameter)) {
      errors.push(
        `${operation} reads undocumented query parameter: ${parameter}`,
      );
    }
  }
  for (const parameter of sorted(documentedParameters)) {
    if (!implementedParameters.has(parameter)) {
      errors.push(
        `${operation} documents ignored query parameter: ${parameter}`,
      );
    }
  }
  return errors;
}

function sorted(values) {
  return [...values].sort((left, right) => left.localeCompare(right));
}

async function checkContract() {
  const source = await readFile(contractPath, "utf8");
  const implemented = await implementedOperations();
  const implementedM3 = new Set(
    [...implemented.keys()].filter((entry) =>
      isM3Path(entry.slice(entry.indexOf(" ") + 1)),
    ),
  );
  const documented = documentedOperations(source);
  const documentedM3 = new Set(
    [...documented.operations.keys()].filter((entry) =>
      isM3Path(entry.slice(entry.indexOf(" ") + 1)),
    ),
  );
  const componentParameters = documentedComponentParameters(source);
  const errors = [];

  for (const operation of sorted(implementedM3)) {
    if (!documentedM3.has(operation)) {
      errors.push(`Missing implemented M3 operation: ${operation}`);
    }
  }
  for (const operation of sorted(documentedM3)) {
    if (!implementedM3.has(operation)) {
      errors.push(`Stale or aspirational M3 operation: ${operation}`);
    }
  }
  for (const [routePath, count] of documented.pathCounts) {
    if (isM3Path(routePath) && count > 1) {
      errors.push(
        `Duplicate M3 path key (${count} declarations): ${routePath}`,
      );
    }
  }

  for (const [operation, details] of documented.operations) {
    if (details.operationId === null) {
      if (isM3Path(details.path)) {
        errors.push(`M3 operation has no operationId: ${operation}`);
      }
    }
  }

  const operationIds = new Map();
  for (const match of source.matchAll(/^\s+operationId:\s*([^\s#]+)\s*$/gmu)) {
    const operationId = match[1];
    const line = source.slice(0, match.index).split(/\r?\n/u).length;
    const prior = operationIds.get(operationId);
    if (prior !== undefined) {
      errors.push(
        `Duplicate operationId ${operationId}: lines ${prior} and ${line}`,
      );
    } else {
      operationIds.set(operationId, line);
    }
  }

  for (const operation of sorted(documentedM3)) {
    const details = documented.operations.get(operation);
    const body = details.body.join("\n");
    const generic = body.match(
      /#\/components\/schemas\/(GenericResource|GenericList|CommandRequest)\b/gu,
    );
    if (generic) {
      errors.push(
        `${operation} uses forbidden generic schema(s): ${[...new Set(generic)].join(", ")}`,
      );
    }
  }

  for (const [operation, details] of implemented) {
    if (!isQueryParityPath(details.path)) continue;
    const documentedDetails = documented.operations.get(operation);
    if (documentedDetails === undefined) continue;
    errors.push(
      ...queryParameterParityErrors(
        operation,
        details.queryParameters,
        documentedQueryParameters(documentedDetails, componentParameters),
      ),
    );
  }

  return { errors, implementedCount: implementedM3.size };
}

async function main() {
  const result = await checkContract();
  if (result.errors.length > 0) {
    console.error("Milestone 3 OpenAPI parity check failed:");
    for (const error of result.errors) console.error(`- ${error}`);
    process.exitCode = 1;
    return;
  }
  console.log(
    `Milestone 3 OpenAPI parity check passed (${result.implementedCount} route/method pairs).`,
  );
}

if (
  process.argv[1] !== undefined &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  await main();
}
