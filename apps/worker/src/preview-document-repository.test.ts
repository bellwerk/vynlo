// Stable test IDs: T-DOC-001, T-JOB-001.
import { describe, expect, it, vi } from "vitest";

import { PostgrestPreviewDocumentRepository } from "./preview-document-repository";
import { PREVIEW_WATERMARK, sha256Hex } from "./preview-renderer";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const documentId = "10000000-0000-4000-8000-000000000002";
const templateVersionId = "10000000-0000-4000-8000-000000000003";
const sourceHtml = "<html><body>{{ deal.id }}</body></html>";

function repository(fetchImplementation: typeof fetch) {
  return new PostgrestPreviewDocumentRepository({
    fetchImplementation,
    serviceRoleKey: "x".repeat(32),
    supabaseUrl: "http://127.0.0.1:54321",
  });
}

describe("PostgrestPreviewDocumentRepository", () => {
  it("loads the exact same-workspace preview and immutable template source", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          {
            id: documentId,
            locale: "en-CA",
            mode: "preview",
            official_number: null,
            render_input_checksum: "a".repeat(64),
            render_input_snapshot: { deal: { id: "deal-1" } },
            status: "queued",
            template_version_id: templateVersionId,
            watermark: PREVIEW_WATERMARK,
            workspace_id: workspaceId,
          },
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            id: templateVersionId,
            locale: "en-CA",
            production_approved: false,
            renderer_version: "synthetic-html-v1",
            source_checksum: sha256Hex(sourceHtml),
            source_html: sourceHtml,
            status: "active",
            template_class: "synthetic_non_production",
            watermark: PREVIEW_WATERMARK,
            workspace_id: workspaceId,
          },
        ]),
      );
    const signal = new AbortController().signal;

    const result = await repository(fetchImplementation).loadRenderSource({
      payload: {
        documentId,
        locale: "en-CA",
        renderInputChecksum: "a".repeat(64),
        templateVersionId,
      },
      signal,
      workspaceId,
    });

    expect(result).toMatchObject({
      documentId,
      documentMode: "preview",
      officialNumber: null,
      productionApproved: false,
      templateVersionId,
      workspaceId,
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(2);
    for (const [input, init] of fetchImplementation.mock.calls) {
      const url = new URL(String(input));
      expect(url.searchParams.get("workspace_id")).toBe(`eq.${workspaceId}`);
      expect(init?.signal).toBe(signal);
      expect(url.pathname).not.toContain("storage");
      expect(new Headers(init?.headers).get("content-profile")).toBeNull();
    }
  });

  it("calls the artifact completion RPC with the deterministic storage receipt", async () => {
    const fetchImplementation = vi.fn(
      async (
        _input: Parameters<typeof fetch>[0],
        _init?: Parameters<typeof fetch>[1],
      ) => {
        void _input;
        void _init;
        return Response.json([
          {
            document_file_id: "10000000-0000-4000-8000-000000000004",
            document_status: "generated",
            replayed: false,
          },
        ]);
      },
    );
    const signal = new AbortController().signal;
    const result = await repository(fetchImplementation).completeArtifact({
      artifactChecksum: "b".repeat(64),
      byteSize: 123,
      contentType: "text/html; charset=utf-8",
      correlationId: "10000000-0000-4000-8000-000000000005",
      documentId,
      filename: "preview.html",
      jobId: "10000000-0000-4000-8000-000000000006",
      leaseToken: "10000000-0000-4000-8000-000000000007",
      objectPath: `${workspaceId}/documents/${documentId}/preview/${"b".repeat(64)}.html`,
      rendererVersion: "synthetic-html-v1",
      requestId: "job:10000000-0000-4000-8000-000000000006",
      signal,
      storageBucket: "preview-artifacts",
      workerId: "preview-worker",
      workspaceId,
    });

    expect(result).toEqual({
      documentFileId: "10000000-0000-4000-8000-000000000004",
      documentStatus: "generated",
      replayed: false,
    });
    const [url, init] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/complete_document_preview_artifact",
    );
    expect(JSON.parse(String(init?.body))).toMatchObject({
      p_checksum: "b".repeat(64),
      p_document_id: documentId,
      p_job_id: "10000000-0000-4000-8000-000000000006",
      p_lease_token: "10000000-0000-4000-8000-000000000007",
      p_storage_bucket: "preview-artifacts",
      p_worker_id: "preview-worker",
      p_workspace_id: workspaceId,
    });
    expect(new Headers(init?.headers).get("content-profile")).toBe("app");
  });

  it("does not disclose database error response content", async () => {
    const fetchImplementation = vi.fn(
      async () => new Response("sensitive row detail", { status: 500 }),
    );

    const error = await repository(fetchImplementation)
      .completeArtifact({
        artifactChecksum: "b".repeat(64),
        byteSize: 123,
        contentType: "text/html; charset=utf-8",
        correlationId: "10000000-0000-4000-8000-000000000005",
        documentId,
        filename: "preview.html",
        jobId: "10000000-0000-4000-8000-000000000006",
        leaseToken: "10000000-0000-4000-8000-000000000007",
        objectPath: "safe/path.html",
        rendererVersion: "synthetic-html-v1",
        requestId: "job:10000000-0000-4000-8000-000000000006",
        signal: new AbortController().signal,
        storageBucket: "preview-artifacts",
        workerId: "preview-worker",
        workspaceId,
      })
      .catch((caught: unknown) => caught);

    expect(error).toMatchObject({ classification: "transient" });
    expect(JSON.stringify(error)).not.toContain("row detail");
  });
});
