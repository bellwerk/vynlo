import { describe, expect, it, vi } from "vitest";

import type { ClaimedJob } from "./job-store";
import type { PrivateArtifactStorage } from "./private-artifact-storage";
import {
  createPreviewJobHandler,
  type PreviewDocumentRepository,
} from "./preview-handler";
import {
  PREVIEW_RENDERER_VERSION,
  PREVIEW_WATERMARK,
  sha256Hex,
  type PreviewRenderSource,
} from "./preview-renderer";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const documentId = "10000000-0000-4000-8000-000000000002";
const templateVersionId = "10000000-0000-4000-8000-000000000003";
const renderInputChecksum = "a".repeat(64);
const sourceHtml = "<html><body>{{ deal.id }}</body></html>";
const workerId = "preview-worker";

function job(overrides: Partial<ClaimedJob> = {}): ClaimedJob {
  return {
    attemptNumber: 1,
    causationId: null,
    correlationId: "10000000-0000-4000-8000-000000000004",
    entityId: documentId,
    entityType: "document",
    idempotencyKey: "preview-job-request-1",
    jobId: "10000000-0000-4000-8000-000000000005",
    jobType: "documents.render_preview",
    leaseExpiresAt: "2026-07-16T12:01:00.000Z",
    leaseToken: "10000000-0000-4000-8000-000000000006",
    maximumAttempts: 8,
    outboxEventId: "10000000-0000-4000-8000-000000000007",
    payload: {
      document_id: documentId,
      locale: "en-CA",
      render_input_checksum: renderInputChecksum,
      template_version_id: templateVersionId,
    },
    payloadSchemaVersion: 1,
    workspaceId,
    ...overrides,
  };
}

function source(
  overrides: Partial<PreviewRenderSource> = {},
): PreviewRenderSource {
  return {
    documentId,
    documentMode: "preview",
    documentStatus: "queued",
    locale: "en-CA",
    officialNumber: null,
    productionApproved: false,
    renderInputChecksum,
    renderInputSnapshot: { deal: { id: "deal-1" } },
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

function dependencies() {
  const documents: PreviewDocumentRepository = {
    completeArtifact: vi.fn(async () => ({
      documentFileId: "10000000-0000-4000-8000-000000000008",
      documentStatus: "generated" as const,
      replayed: false,
    })),
    loadRenderSource: vi.fn(async () => source()),
  };
  const storage: PrivateArtifactStorage = {
    put: vi.fn(async (write) => ({
      bucket: "preview-artifacts",
      byteSize: write.body.byteLength,
      checksum: write.checksum,
      objectPath: write.objectPath,
    })),
  };
  return { documents, storage };
}

describe("documents.render_preview handler", () => {
  it("loads, renders, privately stores, and transactionally records an artifact", async () => {
    const { documents, storage } = dependencies();
    const handler = createPreviewJobHandler({ documents, storage, workerId });
    const signal = new AbortController().signal;

    const result = await handler(job(), { signal });

    expect(documents.loadRenderSource).toHaveBeenCalledWith({
      payload: {
        documentId,
        locale: "en-CA",
        renderInputChecksum,
        templateVersionId,
      },
      signal,
      workspaceId,
    });
    expect(storage.put).toHaveBeenCalledWith(
      expect.objectContaining({
        contentType: "text/html; charset=utf-8",
        objectPath: expect.stringMatching(
          new RegExp(
            `^${workspaceId}/documents/${documentId}/preview/[a-f0-9]{64}\\.html$`,
            "u",
          ),
        ),
      }),
    );
    expect(documents.completeArtifact).toHaveBeenCalledWith(
      expect.objectContaining({
        correlationId: job().correlationId,
        documentId,
        filename: "preview.html",
        jobId: job().jobId,
        leaseToken: job().leaseToken,
        requestId: `job:${job().jobId}`,
        storageBucket: "preview-artifacts",
        workerId,
        workspaceId,
      }),
    );
    expect(result).toMatchObject({
      summary: {
        document_file_id: "10000000-0000-4000-8000-000000000008",
        document_status: "generated",
        renderer_version: PREVIEW_RENDERER_VERSION,
      },
    });
  });

  it("rejects malformed payload before reading authoritative document data", async () => {
    const { documents, storage } = dependencies();
    const handler = createPreviewJobHandler({ documents, storage, workerId });

    await expect(
      handler(job({ payload: { document_id: documentId } }), {
        signal: new AbortController().signal,
      }),
    ).rejects.toMatchObject({
      classification: "validation",
      code: "preview.invalid_job_payload",
    });
    expect(documents.loadRenderSource).not.toHaveBeenCalled();
    expect(storage.put).not.toHaveBeenCalled();
  });

  it("is replay-safe when storage and document completion already exist", async () => {
    const { documents, storage } = dependencies();
    vi.mocked(documents.loadRenderSource).mockResolvedValueOnce(
      source({ documentStatus: "generated" }),
    );
    vi.mocked(documents.completeArtifact).mockResolvedValueOnce({
      documentFileId: "10000000-0000-4000-8000-000000000008",
      documentStatus: "generated",
      replayed: true,
    });
    const handler = createPreviewJobHandler({ documents, storage, workerId });

    await expect(
      handler(job({ attemptNumber: 2 }), {
        signal: new AbortController().signal,
      }),
    ).resolves.toMatchObject({ summary: { replayed: true } });
    expect(storage.put).toHaveBeenCalledOnce();
    expect(documents.completeArtifact).toHaveBeenCalledOnce();
  });

  it("fails closed on an inconsistent private-storage receipt", async () => {
    const { documents, storage } = dependencies();
    vi.mocked(storage.put).mockResolvedValueOnce({
      bucket: "preview-artifacts",
      byteSize: 1,
      checksum: "f".repeat(64),
      objectPath: "wrong/path.html",
    });
    const handler = createPreviewJobHandler({ documents, storage, workerId });

    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "permanent",
      code: "preview.storage_receipt_mismatch",
    });
    expect(documents.completeArtifact).not.toHaveBeenCalled();
  });
});
