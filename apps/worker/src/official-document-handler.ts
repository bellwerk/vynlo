import type { ClaimedJob } from "./job-store";
import { JobExecutionError, type JobHandler } from "./job-runner";
import type { ImmutableArtifactStorage } from "./immutable-artifact-storage";
import {
  OFFICIAL_DOCUMENT_JOB_TYPE,
  officialDocumentStoragePath,
  type OfficialDocumentRenderer,
  type OfficialDocumentRenderSource,
} from "./official-document-renderer";
import {
  assertExactKeys,
  CHECKSUM_PATTERN,
  m4Failure,
  requireRecord,
  requireUuid,
  UUID_PATTERN,
} from "./m4-worker-validation";

export interface OfficialDocumentJobPayload {
  readonly documentId: string;
  readonly locale: string;
  readonly mode: "official";
  readonly renderInputChecksum: string;
  readonly templateVersionId: string;
  readonly versionSnapshotChecksum: string;
}

export interface OfficialDocumentCompletionReplay {
  readonly aggregateVersion: number;
  readonly artifactChecksum: string;
  readonly byteSize: number;
  readonly documentFileId: string;
}

export interface OfficialDocumentRepository {
  complete(input: {
    readonly artifactChecksum: string;
    readonly byteSize: number;
    readonly correlationId: string;
    readonly documentId: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly objectPath: string;
    readonly receipt: Readonly<Record<string, unknown>>;
    readonly rendererVersion: string;
    readonly requestId: string;
    readonly signal: AbortSignal;
    readonly storageBucket: string;
    readonly storageGeneration: string;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<{
    readonly aggregateVersion: number;
    readonly documentFileId: string;
    readonly replayed: boolean;
  }>;
  load(input: {
    readonly documentId: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly signal: AbortSignal;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<
    OfficialDocumentRenderSource &
      Readonly<{ readonly completion: OfficialDocumentCompletionReplay | null }>
  >;
  recordFailure(input: {
    readonly classification: JobExecutionError["classification"];
    readonly correlationId: string;
    readonly documentId: string;
    readonly errorCode: string;
    readonly errorDetailSafe: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly requestId: string;
    readonly retryAfterSeconds?: number | undefined;
    readonly signal: AbortSignal;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<void>;
}

function invalidPayload(): never {
  throw new JobExecutionError({
    classification: "permanent",
    code: "document.invalid_job_payload",
    safeDetail: "The official document job payload failed strict validation.",
  });
}

export function parseOfficialDocumentJobPayload(
  job: ClaimedJob,
): OfficialDocumentJobPayload {
  const payload = requireRecord(job.payload, "document", "job_payload");
  assertExactKeys(
    payload,
    [
      "document_id",
      "locale",
      "mode",
      "render_input_checksum",
      "template_version_id",
      "version_snapshot_checksum",
    ],
    "document",
    "job_payload_keys",
  );
  const locale = payload.locale;
  if (
    job.jobType !== OFFICIAL_DOCUMENT_JOB_TYPE ||
    job.entityType !== "document" ||
    job.payloadSchemaVersion !== 1 ||
    job.entityId === null ||
    payload.mode !== "official" ||
    typeof locale !== "string" ||
    !/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/u.test(locale) ||
    typeof payload.render_input_checksum !== "string" ||
    !CHECKSUM_PATTERN.test(payload.render_input_checksum) ||
    typeof payload.version_snapshot_checksum !== "string" ||
    !CHECKSUM_PATTERN.test(payload.version_snapshot_checksum)
  ) {
    invalidPayload();
  }
  const documentId = requireUuid(
    payload.document_id,
    "document",
    "job_document_id",
  );
  const templateVersionId = requireUuid(
    payload.template_version_id,
    "document",
    "job_template_version_id",
  );
  if (documentId !== job.entityId) invalidPayload();
  return Object.freeze({
    documentId,
    locale,
    mode: "official",
    renderInputChecksum: payload.render_input_checksum,
    templateVersionId,
    versionSnapshotChecksum: payload.version_snapshot_checksum,
  });
}

function assertSourceMatchesPayload(
  source: OfficialDocumentRenderSource,
  payload: OfficialDocumentJobPayload,
): void {
  if (
    source.documentId !== payload.documentId ||
    source.locale !== payload.locale ||
    source.renderInputChecksum !== payload.renderInputChecksum ||
    source.versionSnapshotChecksum !== payload.versionSnapshotChecksum ||
    source.versionSnapshot.templateVersionId !== payload.templateVersionId
  ) {
    throw new JobExecutionError({
      classification: "validation",
      code: "document.render_snapshot_mismatch",
      safeDetail:
        "The official document job differs from its immutable snapshot.",
    });
  }
}

export function createOfficialDocumentJobHandler(input: {
  readonly documents: OfficialDocumentRepository;
  readonly renderer: Pick<OfficialDocumentRenderer, "render">;
  readonly storage: ImmutableArtifactStorage;
  readonly workerId: string;
}): JobHandler {
  return async (job, context) => {
    const failureDocumentId =
      job.entityId !== null && UUID_PATTERN.test(job.entityId)
        ? job.entityId
        : undefined;
    try {
      const payload = parseOfficialDocumentJobPayload(job);
      const source = await input.documents.load({
        documentId: payload.documentId,
        jobId: job.jobId,
        leaseToken: job.leaseToken,
        signal: context.signal,
        workerId: input.workerId,
        workspaceId: job.workspaceId,
      });
      assertSourceMatchesPayload(source, payload);
      if (source.completion !== null) {
        return {
          summary: {
            aggregate_version: source.completion.aggregateVersion,
            artifact_checksum: source.completion.artifactChecksum,
            byte_size: source.completion.byteSize,
            document_file_id: source.completion.documentFileId,
            document_id: payload.documentId,
            renderer_version: source.rendererVersion,
            replayed: true,
          },
        };
      }
      const artifact = await input.renderer.render(source, context.signal);
      const objectPath = officialDocumentStoragePath({
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
        stored.byteSize !== artifact.byteSize ||
        stored.checksum !== artifact.checksum ||
        stored.contentType !== artifact.contentType ||
        stored.objectPath !== objectPath
      ) {
        throw new JobExecutionError({
          classification: "permanent",
          code: "document.storage_receipt_mismatch",
          safeDetail:
            "Private document storage returned inconsistent provenance.",
        });
      }
      const receipt = Object.freeze({
        officialNumber: source.officialNumber,
        renderInputChecksum: source.renderInputChecksum,
        renderer: Object.freeze({ version: artifact.rendererVersion }),
        sourceBundleChecksum: source.sourceBundleChecksum,
        storage: Object.freeze({
          bucket: stored.bucket,
          byteSize: stored.byteSize,
          checksumSha256: stored.checksum,
          generation: stored.generation,
          objectKey: stored.objectPath,
        }),
        versionSnapshotChecksum: source.versionSnapshotChecksum,
      });
      const completion = await input.documents.complete({
        artifactChecksum: artifact.checksum,
        byteSize: artifact.byteSize,
        correlationId: job.correlationId,
        documentId: payload.documentId,
        jobId: job.jobId,
        leaseToken: job.leaseToken,
        objectPath,
        receipt,
        rendererVersion: artifact.rendererVersion,
        requestId: `job:${job.jobId}:complete`,
        signal: context.signal,
        storageBucket: stored.bucket,
        storageGeneration: stored.generation,
        workerId: input.workerId,
        workspaceId: job.workspaceId,
      });
      return {
        summary: {
          aggregate_version: completion.aggregateVersion,
          artifact_checksum: artifact.checksum,
          byte_size: artifact.byteSize,
          document_file_id: completion.documentFileId,
          document_id: payload.documentId,
          renderer_version: artifact.rendererVersion,
          replayed: completion.replayed,
        },
      };
    } catch (error) {
      const failure = m4Failure("document", error);
      if (failureDocumentId !== undefined && !context.signal.aborted) {
        try {
          await input.documents.recordFailure({
            classification: failure.classification,
            correlationId: job.correlationId,
            documentId: failureDocumentId,
            errorCode: failure.code,
            errorDetailSafe: failure.safeDetail,
            jobId: job.jobId,
            leaseToken: job.leaseToken,
            requestId: `job:${job.jobId}:failure`,
            retryAfterSeconds: failure.retryAfterSeconds,
            signal: context.signal,
            workerId: input.workerId,
            workspaceId: job.workspaceId,
          });
        } catch {
          // The runner remains the only durable-job settler and must receive
          // the original safe classification even when domain telemetry fails.
        }
      }
      throw failure;
    }
  };
}
