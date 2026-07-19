// Stable test IDs: T-DOC-001, T-EXP-001, T-JOB-003.
import { DocumentDomainError } from "@vynlo/documents";
import { ExportDefinitionError } from "@vynlo/exports";
import { describe, expect, it } from "vitest";

import { m4Failure } from "./m4-worker-validation";

describe("M4 worker failure normalization", () => {
  it("preserves safe document domain codes without leaking detail", () => {
    expect(
      m4Failure(
        "document",
        new DocumentDomainError("template_value_invalid", "customer.secret"),
      ),
    ).toMatchObject({
      classification: "validation",
      code: "document.template_value_invalid",
      safeDetail:
        "The document artifact failed deterministic domain validation.",
    });
  });

  it("preserves safe export domain codes without leaking paths", () => {
    expect(
      m4Failure(
        "export",
        new ExportDefinitionError(
          "EXPORT_SOURCE_NOT_ALLOWED",
          "$.export.columns[0].source",
          "internal detail",
        ),
      ),
    ).toMatchObject({
      classification: "validation",
      code: "export.export_source_not_allowed",
      safeDetail: "The export artifact failed deterministic domain validation.",
    });
  });
});
