import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import {
  documentedComponentParameters,
  documentedOperations,
  documentedQueryParameters,
  queryParameterParityErrors,
  routeOperationsFromSource,
} from "./check-m3-openapi-contract.mjs";

const root = process.cwd();
const routeRoot = path.join(root, "apps", "web", "app", "api", "v1");
const contractPath = path.join(root, "contracts", "openapi.v1.yaml");

/** M4-EXIT-AC-001 and T-API-001: the complete repository M4 contract. */
export const requiredM4Operations = Object.freeze([
  "get /document-types",
  "post /documents/validate",
  "post /documents/preview",
  "post /documents/official",
  "get /documents",
  "get /documents/{id}",
  "post /document-preview-artifacts/{id}/download-grants",
  "get /documents/{id}/files/{fileId}/download",
  "post /documents/{id}/signed-files",
  "post /documents/{id}/mark-signed",
  "post /documents/{id}/void",
  "post /documents/{id}/supersede",
  "post /documents/{id}/retry-render",
  "get /numbering-definitions",
  "post /numbering-definitions/{key}/versions",
  "post /numbering-versions/{id}/activate",
  "get /approval-records",
  "post /approval-records",
  "get /tax-packs",
  "post /tax/calculate-preview",
  "post /tax-pack-versions/{id}/activate",
  "get /calculation-definitions",
  "post /calculations/validate",
  "post /calculations/run-preview",
  "post /calculation-versions/{id}/approve",
  "post /calculation-versions/{id}/activate",
  "get /export-definitions",
  "post /exports/{definitionKey}/runs",
  "get /export-runs/{id}",
  "get /export-runs/{id}/download",
  "get /reports/inventory-aging",
  "get /reports/inventory-gross",
  "get /reports/leads",
  "get /reports/deals",
]);

const requiredSet = new Set(requiredM4Operations);
const trustedEvidenceSchemas = Object.freeze([
  "M4CalculationEvidence",
  "M4TaxEvidence",
  "M4TaxPreviewEvidence",
]);

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

async function implementedOperations() {
  const operations = new Map();
  for (const file of await routeFiles(routeRoot)) {
    const routePath = filesystemRoutePath(file);
    const source = await readFile(file, "utf8");
    for (const [operation, details] of routeOperationsFromSource(
      source,
      routePath,
      file,
    )) {
      if (requiredSet.has(operation)) operations.set(operation, details);
    }
  }
  return operations;
}

function sorted(values) {
  return [...values].sort((left, right) => left.localeCompare(right));
}

export function operationParityErrors(implemented, documented) {
  const errors = [];
  for (const operation of requiredM4Operations) {
    if (!implemented.has(operation)) {
      errors.push(`Missing implemented M4 operation: ${operation}`);
    }
    if (!documented.has(operation)) {
      errors.push(`Missing documented M4 operation: ${operation}`);
    }
  }
  return errors;
}

export function trustedEvidenceSchemaErrors(source) {
  const errors = [];
  for (const name of trustedEvidenceSchemas) {
    const match = new RegExp(`^    ${name}: (.+)$`, "mu").exec(source);
    if (match?.[1] === undefined) {
      errors.push(`Missing trusted-evidence schema: ${name}`);
      continue;
    }
    const declaration = match[1];
    const required = /"required":\[([^\]]*)\]/u.exec(declaration)?.[1] ?? "";
    if (!declaration.includes('"additionalProperties":false')) {
      errors.push(`Trusted-evidence schema is not closed: ${name}`);
    }
    if (!required.includes('"evidenceId"')) {
      errors.push(
        `Trusted-evidence schema does not require evidenceId: ${name}`,
      );
    }
    if (
      !declaration.includes(
        '"evidenceId":{"$ref":"#/components/schemas/M4Uuid"}',
      )
    ) {
      errors.push(`Trusted-evidence schema has no UUID evidenceId: ${name}`);
    }
  }
  return errors;
}

export function supersedeCommandSchemaErrors(source) {
  const errors = [];
  const match = /^    M4SupersedeDocumentCommand: (.+)$/mu.exec(source);
  if (match?.[1] === undefined) {
    return ["Missing supersede command schema: M4SupersedeDocumentCommand"];
  }
  const declaration = match[1];
  const required = /"required":\[([^\]]*)\]/u.exec(declaration)?.[1] ?? "";
  if (!declaration.includes('"additionalProperties":false')) {
    errors.push("Supersede command schema is not closed");
  }
  if (!required.includes('"expectedVersion"')) {
    errors.push("Supersede command schema does not require expectedVersion");
  }
  if (
    !declaration.includes(
      '"expectedVersion":{"$ref":"#/components/schemas/M4ExpectedVersion"}',
    )
  ) {
    errors.push("Supersede command schema has no bounded expectedVersion");
  }
  return errors;
}

export function numberingVersionCommandSchemaErrors(source) {
  const match = /^    M4NumberingVersionCommand: (.+)$/mu.exec(source);
  if (match?.[1] === undefined) {
    return ["Missing numbering command schema: M4NumberingVersionCommand"];
  }
  const declaration = match[1];
  const errors = [];
  if (!declaration.includes('"additionalProperties":false')) {
    errors.push("Numbering command schema is not closed");
  }
  if (
    declaration.includes('"fixtureEvidence"') ||
    declaration.includes('"validationEvidence"')
  ) {
    errors.push("Numbering command still accepts self-attested evidence");
  }
  if (
    !declaration.includes(
      '"allocationEvent":{"type":"string","const":"official_document_created"}',
    )
  ) {
    errors.push(
      "Numbering command does not pin the supported allocation event",
    );
  }
  if (!declaration.includes('"timezoneName":{"type":"string","const":"UTC"}')) {
    errors.push("Numbering command does not pin the supported timezone");
  }
  return errors;
}

async function checkContract() {
  const source = await readFile(contractPath, "utf8");
  const implemented = await implementedOperations();
  const documented = documentedOperations(source);
  const componentParameters = documentedComponentParameters(source);
  const errors = operationParityErrors(implemented, documented.operations);
  errors.push(...trustedEvidenceSchemaErrors(source));
  errors.push(...supersedeCommandSchemaErrors(source));
  errors.push(...numberingVersionCommandSchemaErrors(source));

  for (const [routePath, count] of documented.pathCounts) {
    if (
      count > 1 &&
      requiredM4Operations.some((entry) => entry.endsWith(` ${routePath}`))
    ) {
      errors.push(
        `Duplicate M4 path key (${count} declarations): ${routePath}`,
      );
    }
  }

  for (const operation of requiredM4Operations) {
    const specification = documented.operations.get(operation);
    if (specification === undefined) continue;
    const body = specification.body.join("\n");
    if (specification.operationId === null) {
      errors.push(`M4 operation has no operationId: ${operation}`);
    }
    const generic = body.match(
      /#\/components\/schemas\/(GenericResource|GenericList|CommandRequest)\b/gu,
    );
    if (generic) {
      errors.push(
        `${operation} uses forbidden generic schema(s): ${[...new Set(generic)].join(", ")}`,
      );
    }
    if (
      operation !== "post /document-preview-artifacts/{id}/download-grants" &&
      !body.includes("x-vynlo-acceptance:")
    ) {
      errors.push(`M4 operation has no acceptance traceability: ${operation}`);
    }
    if (
      operation.startsWith("post ") &&
      !body.includes("IdempotencyKey") &&
      !body.includes("*id003")
    ) {
      errors.push(`M4 command omits Idempotency-Key: ${operation}`);
    }
    if (
      operation === "post /documents/{id}/supersede" &&
      !body.includes("M4SupersedeDocumentCommand")
    ) {
      errors.push(
        "Supersede operation omits its strict expected-version schema",
      );
    }
    if (
      operation === "post /documents/official" &&
      !body.includes("M4OfficialDocumentCommand")
    ) {
      errors.push(
        "Official document creation no longer uses its create schema",
      );
    }

    const implementation = implemented.get(operation);
    if (implementation !== undefined) {
      errors.push(
        ...queryParameterParityErrors(
          operation,
          implementation.queryParameters,
          documentedQueryParameters(specification, componentParameters),
        ),
      );
    }
  }

  return { errors: sorted(errors), implementedCount: implemented.size };
}

async function main() {
  const result = await checkContract();
  if (result.errors.length > 0) {
    console.error("Milestone 4 OpenAPI parity check failed:");
    for (const error of result.errors) console.error(`- ${error}`);
    process.exitCode = 1;
    return;
  }
  console.log(
    `Milestone 4 OpenAPI parity check passed (${result.implementedCount} route/method pairs).`,
  );
}

if (
  process.argv[1] !== undefined &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  await main();
}
