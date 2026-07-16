import type { ClaimedJob } from "./job-store";
import { JobExecutionError, type JobHandler } from "./job-runner";
import type { PrivateArtifactStorage } from "./private-artifact-storage";
import {
  parsePreviewJobPayload,
  PREVIEW_RENDERER_VERSION,
  previewStorageObjectPath,
  renderPreviewHtml,
  type PreviewJobPayload,
  type PreviewRenderSource,
} from "./preview-renderer";

export interface PreviewArtifactCompletion {
  readonly documentFileId: string;
  readonly documentStatus: "generated";
  readonly replayed: boolean;
}

export interface PreviewDocumentRepository {
  completeArtifact(input: {
    readonly artifactChecksum: string;
    readonly byteSize: number;
    readonly contentType: string;
    readonly correlationId: string;
    readonly documentId: string;
    readonly filename: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly objectPath: string;
    readonly rendererVersion: string;
    readonly requestId: string;
    readonly signal: AbortSignal;
    readonly storageBucket: string;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<PreviewArtifactCompletion>;
  loadRenderSource(input: {
    readonly payload: PreviewJobPayload;
    readonly signal: AbortSignal;
    readonly workspaceId: string;
  }): Promise<PreviewRenderSource>;
}

export function createPreviewJobHandler(input: {
  readonly documents: PreviewDocumentRepository;
  readonly storage: PrivateArtifactStorage;
  readonly workerId: string;
}): JobHandler {
  return async (job: ClaimedJob, context) => {
    const payload = parsePreviewJobPayload(job);
    const source = await input.documents.loadRenderSource({
      payload,
      signal: context.signal,
      workspaceId: job.workspaceId,
    });
    const artifact = renderPreviewHtml({
      payload,
      source,
      workspaceId: job.workspaceId,
    });
    const objectPath = previewStorageObjectPath({
      artifactChecksum: artifact.checksum,
      documentId: payload.documentId,
      workspaceId: job.workspaceId,
    });
    const stored = await input.storage.put({
      body: artifact.body,
      checksum: artifact.checksum,
      contentType: artifact.contentType,
      objectPath,
      signal: context.signal,
    });
    if (
      stored.checksum !== artifact.checksum ||
      stored.byteSize !== artifact.byteSize ||
      stored.objectPath !== objectPath
    ) {
      throw new JobExecutionError({
        classification: "permanent",
        code: "preview.storage_receipt_mismatch",
        safeDetail:
          "Private storage returned an inconsistent artifact receipt.",
      });
    }

    const completion = await input.documents.completeArtifact({
      artifactChecksum: artifact.checksum,
      byteSize: artifact.byteSize,
      contentType: artifact.contentType,
      correlationId: job.correlationId,
      documentId: payload.documentId,
      filename: artifact.filename,
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      objectPath,
      rendererVersion: PREVIEW_RENDERER_VERSION,
      requestId: `job:${job.jobId}`,
      signal: context.signal,
      storageBucket: stored.bucket,
      workerId: input.workerId,
      workspaceId: job.workspaceId,
    });

    return {
      summary: {
        artifact_checksum: artifact.checksum,
        byte_size: artifact.byteSize,
        document_file_id: completion.documentFileId,
        document_status: completion.documentStatus,
        renderer_version: PREVIEW_RENDERER_VERSION,
        replayed: completion.replayed,
      },
    };
  };
}
