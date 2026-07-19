import { describe, expect, it } from "vitest";

import {
  DocumentPreviewCommandError,
  PREVIEW_WATERMARK,
  SYNTHETIC_NON_PRODUCTION_TEMPLATE,
  assertSafePreviewRecord,
  completePreviewState,
  normalizeRequestDocumentPreviewCommand,
} from "./first-vertical-slice";

describe("first document-preview vertical-slice contracts", () => {
  it("ships only a synthetic, explicitly non-production template contract", () => {
    expect(SYNTHETIC_NON_PRODUCTION_TEMPLATE).toMatchObject({
      productionApproved: false,
      officialGenerationEnabled: false,
      watermark: PREVIEW_WATERMARK,
    });
    expect(
      SYNTHETIC_NON_PRODUCTION_TEMPLATE.sourceHtml.toLowerCase(),
    ).not.toContain("<script");
  });

  it("normalizes a preview request without accepting workspace or official-number input", () => {
    const normalized = normalizeRequestDocumentPreviewCommand({
      idempotencyKey: "preview-command-001",
      dealId: "91000000-0000-4000-8000-000000000001",
      templateVersionId: "93000000-0000-4000-8000-000000000001",
      locale: " fr-CA ",
    });
    expect(normalized.locale).toBe("fr-CA");
    expect(normalized).not.toHaveProperty("workspaceId");
    expect(normalized).not.toHaveProperty("officialNumber");
  });

  it("T-DOC-001 requires preview mode, no official number, and the fixed watermark", () => {
    expect(
      assertSafePreviewRecord({
        mode: "preview",
        officialNumber: null,
        watermark: PREVIEW_WATERMARK,
        state: {
          status: "queued",
          generatedChecksum: null,
          failureCode: null,
        },
      }).officialNumber,
    ).toBeNull();
  });

  it("permits one valid queued-to-generated transition", () => {
    expect(
      completePreviewState(
        { status: "queued", generatedChecksum: null, failureCode: null },
        { status: "generated", generatedChecksum: "a".repeat(64) },
      ),
    ).toEqual({
      status: "generated",
      generatedChecksum: "a".repeat(64),
      failureCode: null,
    });
  });

  it("rejects terminal-state replay and malformed checksums", () => {
    expect(() =>
      completePreviewState(
        {
          status: "generated",
          generatedChecksum: "a".repeat(64),
          failureCode: null,
        },
        { status: "failed", failureCode: "RENDER_FAILED" },
      ),
    ).toThrowError(DocumentPreviewCommandError);
    expect(() =>
      completePreviewState(
        { status: "queued", generatedChecksum: null, failureCode: null },
        { status: "generated", generatedChecksum: "not-a-checksum" },
      ),
    ).toThrowError("invalid_preview_transition");
  });
});
