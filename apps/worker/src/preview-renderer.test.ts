// Stable test IDs: T-DOC-001, T-DOC-006.
import { describe, expect, it } from "vitest";

import { JobExecutionError } from "./job-runner";
import {
  parsePreviewJobPayload,
  PREVIEW_RENDERER_VERSION,
  PREVIEW_WATERMARK,
  previewStorageObjectPath,
  renderPreviewHtml,
  sha256Hex,
  type PreviewRenderSource,
} from "./preview-renderer";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const documentId = "10000000-0000-4000-8000-000000000002";
const templateVersionId = "10000000-0000-4000-8000-000000000003";
const renderInputChecksum = "a".repeat(64);

function payload() {
  return parsePreviewJobPayload({
    entityId: documentId,
    entityType: "document",
    jobType: "documents.render_preview",
    payload: {
      document_id: documentId,
      locale: "en-CA",
      render_input_checksum: renderInputChecksum,
      template_version_id: templateVersionId,
    },
    payloadSchemaVersion: 1,
  });
}

function source(
  overrides: Partial<PreviewRenderSource> = {},
): PreviewRenderSource {
  const sourceHtml =
    "<html><body><h1>{{ participants[0].display_name }}</h1><p>{{ deal.id }}</p></body></html>";
  return {
    documentId,
    documentMode: "preview",
    documentStatus: "queued",
    locale: "en-CA",
    officialNumber: null,
    productionApproved: false,
    renderInputChecksum,
    renderInputSnapshot: {
      deal: { id: "deal-1" },
      participants: [{ display_name: '<Alex & "Sam">' }],
    },
    rendererVersion: PREVIEW_RENDERER_VERSION,
    sourceChecksum: sha256Hex(sourceHtml),
    sourceHtml,
    templateClass: "synthetic_non_production",
    templateStatus: "active",
    templateVersionId,
    watermark: PREVIEW_WATERMARK,
    workspaceId,
    ...overrides,
  };
}

describe("preview payload", () => {
  it("accepts only the canonical version-one job contract", () => {
    expect(payload()).toEqual({
      documentId,
      locale: "en-CA",
      renderInputChecksum,
      templateVersionId,
    });
  });

  it("rejects extra fields, entity mismatches, and malformed checksums", () => {
    for (const input of [
      {
        entityId: documentId,
        entityType: "document",
        jobType: "documents.render_preview",
        payload: {
          document_id: documentId,
          locale: "en-CA",
          render_input_checksum: renderInputChecksum,
          template_version_id: templateVersionId,
          snapshot: {},
        },
        payloadSchemaVersion: 1,
      },
      {
        entityId: workspaceId,
        entityType: "document",
        jobType: "documents.render_preview",
        payload: {
          document_id: documentId,
          locale: "en-CA",
          render_input_checksum: renderInputChecksum,
          template_version_id: templateVersionId,
        },
        payloadSchemaVersion: 1,
      },
    ]) {
      expect(() => parsePreviewJobPayload(input)).toThrow(JobExecutionError);
    }
  });
});

describe("deterministic preview rendering", () => {
  it("escapes snapshot values and injects one fixed watermark", () => {
    const first = renderPreviewHtml({
      payload: payload(),
      source: source(),
      workspaceId,
    });
    const second = renderPreviewHtml({
      payload: payload(),
      source: source(),
      workspaceId,
    });

    expect(first).toEqual(second);
    expect(first.html).toContain("DRAFT / NON-PRODUCTION");
    expect(first.html.match(/data-vynlo-watermark/gu)).toHaveLength(1);
    expect(first.html).toContain("&lt;Alex &amp; &quot;Sam&quot;&gt;");
    expect(first.html).not.toContain('<Alex & "Sam">');
    expect(first.checksum).toMatch(/^[a-f0-9]{64}$/u);
    expect(first.byteSize).toBe(first.body.byteLength);
  });

  it("rejects executable, remote, unsupported, or altered template source", () => {
    const unsafeSources = [
      "<html><body><script>alert(1)</script></body></html>",
      '<html><body><img src="https://example.invalid/a.png"></body></html>',
      "<html><body>{% if deal %}x{% endif %}</body></html>",
    ];

    for (const sourceHtml of unsafeSources) {
      expect(() =>
        renderPreviewHtml({
          payload: payload(),
          source: source({
            sourceChecksum: sha256Hex(sourceHtml),
            sourceHtml,
          }),
          workspaceId,
        }),
      ).toThrow(JobExecutionError);
    }

    expect(() =>
      renderPreviewHtml({
        payload: payload(),
        source: source({ sourceChecksum: "b".repeat(64) }),
        workspaceId,
      }),
    ).toThrow(JobExecutionError);
  });

  it("permanently rejects placeholders outside the explicit preview allowlist", () => {
    const sourceHtml = "<html><body>{{ deal.status }}</body></html>";
    expect(() =>
      renderPreviewHtml({
        payload: payload(),
        source: source({
          sourceChecksum: sha256Hex(sourceHtml),
          sourceHtml,
        }),
        workspaceId,
      }),
    ).toThrow(
      expect.objectContaining({
        classification: "permanent",
        code: "preview.template_placeholder_not_allowed",
      }),
    );
  });

  it("supports only the fixed watermark and first deterministic list entries", () => {
    const sourceHtml =
      "<html><body>{{ watermark }} / {{ deal.id }} / {{ deal.deal_type_key }} / {{ deal.currency_code }} / {{ participants[0].display_name }} / {{ inventory_units[0].stock_number }} / {{ inventory_units[0].vin }}</body></html>";
    const rendered = renderPreviewHtml({
      payload: payload(),
      source: source({
        renderInputSnapshot: {
          deal: {
            currency_code: "CAD",
            deal_type_key: "retail",
            id: "deal-1",
          },
          inventory_units: [{ stock_number: "S-1", vin: '<VIN&"1">' }],
          participants: [{ display_name: "Alex" }],
        },
        sourceChecksum: sha256Hex(sourceHtml),
        sourceHtml,
      }),
      workspaceId,
    });
    expect(rendered.html).toContain(PREVIEW_WATERMARK);
    expect(rendered.html).toContain("retail / CAD / Alex / S-1");
    expect(rendered.html).toContain("&lt;VIN&amp;&quot;1&quot;&gt;");
  });

  it("requires preview-only, unnumbered, non-production source state", () => {
    expect(() =>
      renderPreviewHtml({
        payload: payload(),
        source: source({ officialNumber: "P001" as never }),
        workspaceId,
      }),
    ).toThrow(JobExecutionError);
    expect(() =>
      renderPreviewHtml({
        payload: payload(),
        source: source({ productionApproved: true as never }),
        workspaceId,
      }),
    ).toThrow(JobExecutionError);
  });

  it("derives a workspace-scoped deterministic private object path", () => {
    expect(
      previewStorageObjectPath({
        artifactChecksum: "f".repeat(64),
        documentId,
        workspaceId,
      }),
    ).toBe(
      `${workspaceId}/documents/${documentId}/preview/${"f".repeat(64)}.html`,
    );
  });
});
