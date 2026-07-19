// Stable test IDs: T-DOC-001, T-DOC-002, T-DOC-004, T-DOC-005.
import {
  computeTemplateSourceBundleChecksum,
  type DocumentTemplateAsset,
} from "@vynlo/documents";
import { describe, expect, it, vi } from "vitest";

import {
  canonicalizePdfBytes,
  OfficialDocumentRenderer,
  officialDocumentStoragePath,
  type OfficialDocumentRenderSource,
  type PdfEngine,
} from "./official-document-renderer";

function pdf(creation = "20260716123456"): Uint8Array {
  const padding = "x".repeat(120);
  return new TextEncoder().encode(
    `%PDF-1.7\n1 0 obj<</CreationDate (D:${creation}+00'00')>>endobj\n${padding}\n%%EOF`,
  );
}

function source(asset?: DocumentTemplateAsset): OfficialDocumentRenderSource {
  const assets = asset === undefined ? [] : [asset];
  const sourceCss = "body { color: #111; }";
  const sourceHtml =
    "<html><head></head><body><h1>{{ document.official_number }}</h1><p>{{ document.fields.customer_name }}</p></body></html>";
  return {
    assetManifest: assets.length === 0 ? {} : { assets },
    documentId: "10000000-0000-4000-8000-000000000001",
    fontManifest: {},
    locale: "en-CA",
    officialNumber: "INV-2026-0001",
    renderInputChecksum: "b".repeat(64),
    renderInputSnapshot: {
      document: { fields: { customer_name: "<Example>" } },
    },
    rendererVersion: "playwright-pdf-v1",
    sourceBundleChecksum: computeTemplateSourceBundleChecksum({
      assets,
      sourceCss,
      sourceHtml,
    }),
    sourceCss,
    sourceHtml,
    versionSnapshot: { schemaVersion: 2 },
    versionSnapshotChecksum: "c".repeat(64),
  };
}

describe("M4 official document PDF renderer", () => {
  it("renders escaped immutable input with the authoritative official number", async () => {
    const engine: PdfEngine = { render: vi.fn().mockResolvedValue(pdf()) };
    const renderer = new OfficialDocumentRenderer({ engine, timeoutMs: 5_000 });
    const result = await renderer.render(
      source(),
      new AbortController().signal,
    );
    expect(result.contentType).toBe("application/pdf");
    expect(result.filename).toBe("INV-2026-0001.pdf");
    expect(result.body.slice(0, 5)).toEqual(new TextEncoder().encode("%PDF-"));
    expect(engine.render).toHaveBeenCalledWith(
      expect.objectContaining({
        html: expect.stringContaining("INV-2026-0001"),
        locale: "en-CA",
      }),
    );
    const html = vi.mocked(engine.render).mock.calls[0]?.[0].html ?? "";
    expect(html).toContain("&lt;Example&gt;");
    expect(html).toContain("Content-Security-Policy");
    expect(html).not.toContain("<script");
  });

  it("keeps the legal number in content but derives a portable collision-safe filename", async () => {
    const engine: PdfEngine = { render: vi.fn().mockResolvedValue(pdf()) };
    const result = await new OfficialDocumentRenderer({
      engine,
      timeoutMs: 5_000,
    }).render(
      { ...source(), officialNumber: "LEGAL/2026/échange" },
      new AbortController().signal,
    );
    expect(result.filename).toBe("LEGAL-2026-change-4e8ca26ffeeec1ee.pdf");
    const html = vi.mocked(engine.render).mock.calls[0]?.[0].html ?? "";
    expect(html).toContain("LEGAL/2026/échange");
    expect(result.filename).not.toContain("/");
  });

  it("inlines only checksum-validated manifest assets as data URLs", async () => {
    const content = "89504e470d0a1a0a";
    const asset: DocumentTemplateAsset = {
      byteSize: 8,
      checksum:
        "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6",
      content,
      filename: "mark.png",
      key: "mark",
      mimeType: "image/png",
    };
    const base = source(asset);
    const sourceHtml = '<html><body><img src="vynlo-asset:mark"></body></html>';
    const checksum = computeTemplateSourceBundleChecksum({
      assets: [asset],
      sourceCss: base.sourceCss,
      sourceHtml,
    });
    const withAsset = {
      ...base,
      sourceBundleChecksum: checksum,
      sourceHtml,
    };
    const engine: PdfEngine = { render: vi.fn().mockResolvedValue(pdf()) };
    await new OfficialDocumentRenderer({ engine, timeoutMs: 5_000 }).render(
      withAsset,
      new AbortController().signal,
    );
    const html = vi.mocked(engine.render).mock.calls[0]?.[0].html ?? "";
    expect(html).toContain("data:image/png;base64,");
    expect(html).not.toContain("vynlo-asset:");
  });

  it("rejects template bytes that differ from the immutable bundle checksum", async () => {
    const engine: PdfEngine = { render: vi.fn().mockResolvedValue(pdf()) };
    const renderer = new OfficialDocumentRenderer({ engine, timeoutMs: 5_000 });

    await expect(
      renderer.render(
        { ...source(), sourceHtml: "<p>Changed after approval</p>" },
        new AbortController().signal,
      ),
    ).rejects.toMatchObject({
      code: "document.source_bundle_checksum_mismatch",
    });
    expect(engine.render).not.toHaveBeenCalled();
  });

  it("rejects unsafe integer transport before a PDF can be produced", async () => {
    const engine: PdfEngine = { render: vi.fn().mockResolvedValue(pdf()) };
    const renderer = new OfficialDocumentRenderer({ engine, timeoutMs: 5_000 });

    await expect(
      renderer.render(
        {
          ...source(),
          renderInputSnapshot: {
            document: { fields: { amount_minor: 9_007_199_254_740_992 } },
          },
        },
        new AbortController().signal,
      ),
    ).rejects.toMatchObject({ code: "document.render_input_number_unsafe" });
    expect(engine.render).not.toHaveBeenCalled();
  });

  it("normalizes volatile PDF metadata without changing byte length", () => {
    const first = canonicalizePdfBytes(pdf("20260716123456"));
    const second = canonicalizePdfBytes(pdf("20270102030405"));
    expect(first).toEqual(second);
    expect(first.byteLength).toBe(pdf().byteLength);
  });

  it("uses the database-compatible immutable generated-original path", () => {
    expect(
      officialDocumentStoragePath({
        artifactChecksum: "d".repeat(64),
        documentId: "10000000-0000-4000-8000-000000000001",
        workspaceId: "10000000-0000-4000-8000-000000000002",
      }),
    ).toBe(
      `10000000-0000-4000-8000-000000000002/documents/10000000-0000-4000-8000-000000000001/generated_original/v1/${"d".repeat(64)}.pdf`,
    );
  });
});
