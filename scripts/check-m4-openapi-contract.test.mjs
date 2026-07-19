import assert from "node:assert/strict";
import test from "node:test";

import {
  numberingVersionCommandSchemaErrors,
  operationParityErrors,
  requiredM4Operations,
  supersedeCommandSchemaErrors,
  trustedEvidenceSchemaErrors,
} from "./check-m4-openapi-contract.mjs";

test("M4 contract enumerates the 34 required route/method pairs", () => {
  assert.equal(requiredM4Operations.length, 34);
  assert.equal(new Set(requiredM4Operations).size, 34);
  assert.ok(requiredM4Operations.includes("post /documents/official"));
  assert.ok(requiredM4Operations.includes("get /reports/deals"));
});

test("M4 parity reports implemented and documented omissions independently", () => {
  const complete = new Map(
    requiredM4Operations.map((operation) => [operation, {}]),
  );
  const implemented = new Map(complete);
  const documented = new Map(complete);
  implemented.delete("post /documents/official");
  documented.delete("get /reports/deals");

  assert.deepEqual(operationParityErrors(implemented, documented), [
    "Missing implemented M4 operation: post /documents/official",
    "Missing documented M4 operation: get /reports/deals",
  ]);
});

test("M4 trusted runtime evidence must be closed and carry an opaque UUID", () => {
  const valid = [
    "M4CalculationEvidence",
    "M4TaxEvidence",
    "M4TaxPreviewEvidence",
  ]
    .map(
      (name) =>
        `    ${name}: {"type":"object","additionalProperties":false,"required":["evidenceId"],"properties":{"evidenceId":{"$ref":"#/components/schemas/M4Uuid"}}}`,
    )
    .join("\n");
  assert.deepEqual(trustedEvidenceSchemaErrors(valid), []);

  assert.deepEqual(
    trustedEvidenceSchemaErrors(
      valid.replace('"required":["evidenceId"]', '"required":[]'),
    ),
    [
      "Trusted-evidence schema does not require evidenceId: M4CalculationEvidence",
    ],
  );
});

test("M4 supersession requires a closed optimistic-concurrency command", () => {
  const valid =
    '    M4SupersedeDocumentCommand: {"type":"object","additionalProperties":false,"required":["expectedVersion"],"properties":{"expectedVersion":{"$ref":"#/components/schemas/M4ExpectedVersion"}}}';
  assert.deepEqual(supersedeCommandSchemaErrors(valid), []);
  assert.deepEqual(
    supersedeCommandSchemaErrors(
      valid.replace('"required":["expectedVersion"]', '"required":[]'),
    ),
    ["Supersede command schema does not require expectedVersion"],
  );
});

test("M4 numbering exposes only the supported trusted configuration", () => {
  const valid =
    '    M4NumberingVersionCommand: {"type":"object","additionalProperties":false,"required":["allocationEvent","timezoneName"],"properties":{"allocationEvent":{"type":"string","const":"official_document_created"},"timezoneName":{"type":"string","const":"UTC"}}}';
  assert.deepEqual(numberingVersionCommandSchemaErrors(valid), []);
  assert.deepEqual(
    numberingVersionCommandSchemaErrors(
      valid.replace(
        '"timezoneName":{"type":"string","const":"UTC"}',
        '"timezoneName":{"type":"string"},"fixtureEvidence":{}',
      ),
    ),
    [
      "Numbering command still accepts self-attested evidence",
      "Numbering command does not pin the supported timezone",
    ],
  );
});
