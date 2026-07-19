// Stable test IDs: T-DOC-004, T-DOC-005, T-DOC-006, T-JOB-003.
import { describe, expect, it, vi } from "vitest";

import type { ImmutableArtifactStorage } from "./immutable-artifact-storage";
import type { ClaimedJob } from "./job-store";
import { JobExecutionError } from "./job-runner";
import {
  createOfficialDocumentJobHandler,
  type OfficialDocumentRepository,
} from "./official-document-handler";
import type {
  OfficialDocumentRenderer,
  OfficialDocumentRenderSource,
} from "./official-document-renderer";

const ids = {
  correlation: "10000000-0000-4000-8000-000000000001",
  document: "10000000-0000-4000-8000-000000000002",
  file: "10000000-0000-4000-8000-000000000003",
  job: "10000000-0000-4000-8000-000000000004",
  lease: "10000000-0000-4000-8000-000000000005",
  outbox: "10000000-0000-4000-8000-000000000006",
  template: "10000000-0000-4000-8000-000000000007",
  workspace: "10000000-0000-4000-8000-000000000008",
} as const;

function job(): ClaimedJob {
  return {
    attemptNumber: 1,
    causationId: null,
    correlationId: ids.correlation,
    entityId: ids.document,
    entityType: "document",
    idempotencyKey: "render:official-1",
    jobId: ids.job,
    jobType: "documents.render_pdf",
    leaseExpiresAt: "2026-07-16T18:00:00.000Z",
    leaseToken: ids.lease,
    maximumAttempts: 5,
    outboxEventId: ids.outbox,
    payload: {
      document_id: ids.document,
      locale: "en-CA",
      mode: "official",
      render_input_checksum: "a".repeat(64),
      template_version_id: ids.template,
      version_snapshot_checksum: "b".repeat(64),
    },
    payloadSchemaVersion: 1,
    workspaceId: ids.workspace,
  };
}

const source: OfficialDocumentRenderSource & { readonly completion: null } = {
  assetManifest: {},
  documentId: ids.document,
  fontManifest: {},
  locale: "en-CA",
  officialNumber: "DOC-0001",
  renderInputChecksum: "a".repeat(64),
  renderInputSnapshot: { document: { fields: {} } },
  rendererVersion: "playwright-pdf-v1",
  sourceBundleChecksum: "c".repeat(64),
  sourceCss: "",
  sourceHtml: "<p>Official</p>",
  versionSnapshot: { templateVersionId: ids.template },
  versionSnapshotChecksum: "b".repeat(64),
  completion: null,
};

function dependencies() {
  const documents: OfficialDocumentRepository = {
    complete: vi.fn().mockResolvedValue({
      aggregateVersion: 2,
      documentFileId: ids.file,
      replayed: false,
    }),
    load: vi.fn().mockResolvedValue(source),
    recordFailure: vi.fn().mockResolvedValue(undefined),
  };
  const body = new TextEncoder().encode(
    "%PDF-1.7\n" + "x".repeat(120) + "\n%%EOF",
  );
  const renderer: Pick<OfficialDocumentRenderer, "render"> = {
    render: vi.fn().mockResolvedValue({
      body,
      byteSize: body.byteLength,
      checksum: "d".repeat(64),
      contentType: "application/pdf",
      filename: "DOC-0001.pdf",
      rendererVersion: "playwright-pdf-v1",
    }),
  };
  const storage: ImmutableArtifactStorage = {
    put: vi.fn().mockResolvedValue({
      bucket: "documents-private",
      byteSize: body.byteLength,
      checksum: "d".repeat(64),
      contentType: "application/pdf",
      generation: '"generation-1"',
      objectPath: `${ids.workspace}/documents/${ids.document}/generated_original/v1/${"d".repeat(64)}.pdf`,
    }),
  };
  return { documents, renderer, storage };
}

describe("M4 documents.render_pdf handler", () => {
  it("persists a snapshot-bound private receipt and leaves job success to the runner", async () => {
    const { documents, renderer, storage } = dependencies();
    const handler = createOfficialDocumentJobHandler({
      documents,
      renderer,
      storage,
      workerId: "worker-m4-1",
    });
    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).resolves.toMatchObject({
      summary: {
        document_file_id: ids.file,
        document_id: ids.document,
        replayed: false,
      },
    });
    expect(documents.complete).toHaveBeenCalledWith(
      expect.objectContaining({
        artifactChecksum: "d".repeat(64),
        receipt: {
          officialNumber: "DOC-0001",
          renderInputChecksum: "a".repeat(64),
          renderer: { version: "playwright-pdf-v1" },
          sourceBundleChecksum: "c".repeat(64),
          storage: expect.objectContaining({
            bucket: "documents-private",
            generation: '"generation-1"',
          }),
          versionSnapshotChecksum: "b".repeat(64),
        },
      }),
    );
    expect(documents.recordFailure).not.toHaveBeenCalled();
  });

  it("records domain failure evidence then rethrows for canonical runner retry", async () => {
    const { documents, renderer, storage } = dependencies();
    const failure = new JobExecutionError({
      classification: "transient",
      code: "document.pdf_render_timeout",
      retryAfterSeconds: 5,
      safeDetail: "The bounded official PDF render timed out.",
    });
    vi.mocked(renderer.render).mockRejectedValueOnce(failure);
    const handler = createOfficialDocumentJobHandler({
      documents,
      renderer,
      storage,
      workerId: "worker-m4-1",
    });
    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).rejects.toBe(failure);
    expect(documents.recordFailure).toHaveBeenCalledWith(
      expect.objectContaining({
        classification: "transient",
        documentId: ids.document,
        errorCode: "document.pdf_render_timeout",
        retryAfterSeconds: 5,
      }),
    );
    expect(documents.complete).not.toHaveBeenCalled();
  });

  it("replays committed domain completion without rendering or storing again", async () => {
    const { documents, renderer, storage } = dependencies();
    vi.mocked(documents.load).mockResolvedValueOnce({
      ...source,
      completion: {
        aggregateVersion: 4,
        artifactChecksum: "d".repeat(64),
        byteSize: 256,
        documentFileId: ids.file,
      },
    });
    const handler = createOfficialDocumentJobHandler({
      documents,
      renderer,
      storage,
      workerId: "worker-m4-1",
    });

    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).resolves.toMatchObject({
      summary: {
        aggregate_version: 4,
        document_file_id: ids.file,
        replayed: true,
      },
    });
    expect(renderer.render).not.toHaveBeenCalled();
    expect(storage.put).not.toHaveBeenCalled();
    expect(documents.complete).not.toHaveBeenCalled();
  });

  it("fails closed before rendering when the job snapshot is changed", async () => {
    const { documents, renderer, storage } = dependencies();
    const handler = createOfficialDocumentJobHandler({
      documents,
      renderer,
      storage,
      workerId: "worker-m4-1",
    });
    await expect(
      handler(
        { ...job(), payload: { ...job().payload, mode: "preview" } },
        { signal: new AbortController().signal },
      ),
    ).rejects.toMatchObject({ code: "document.invalid_job_payload" });
    expect(renderer.render).not.toHaveBeenCalled();
  });
});
