import {
  LEGAL_ORIGINAL_QUARANTINE_CLEANUP_JOB_TYPE,
  LEGAL_ORIGINAL_MAX_BYTES,
  parseLegalOriginalQuarantineCleanupJob,
  type LegalOriginalObjectStorage,
  type LegalOriginalQuarantineCleanupReason,
  type ManagedObjectStorage,
} from "@vynlo/media";

import { JobExecutionError, type JobHandler } from "./job-runner";
import {
  materializeMediaSource,
  mediaSha256Hex,
} from "./managed-media-storage";

export { LEGAL_ORIGINAL_QUARANTINE_CLEANUP_JOB_TYPE };

interface Lease {
  readonly attemptNumber: number;
  readonly jobId: string;
  readonly leaseToken: string;
  readonly signal: AbortSignal;
  readonly uploadSessionId: string;
  readonly workerId: string;
  readonly workspaceId: string;
}

export interface LegalOriginalQuarantineCleanupSource {
  readonly alreadyDeleted: boolean;
  readonly bucket: "media-private";
  readonly cleanupId: string;
  readonly objectKey: string;
  readonly reason: LegalOriginalQuarantineCleanupReason;
}

export interface LegalOriginalQuarantineCleanupRepository {
  complete(
    input: Lease & {
      readonly correlationId: string;
      readonly observedChecksumSha256: string | null;
      readonly requestId: string;
      readonly storageResult: "deleted" | "not_found";
    },
  ): Promise<{
    readonly cleanupId: string;
    readonly cleanupStatus: "deleted" | "not_found";
    readonly replayed: boolean;
  }>;
  fence(
    input: Lease & {
      readonly observedByteSize: number;
      readonly observedChecksumSha256: string;
      readonly observedMimeType: string;
      readonly storageGeneration: string;
    },
  ): Promise<{ readonly cleanupId: string; readonly replayed: boolean }>;
  load(input: Lease): Promise<LegalOriginalQuarantineCleanupSource>;
}

function permanent(code: string, safeDetail: string): JobExecutionError {
  return new JobExecutionError({
    classification: "permanent",
    code,
    safeDetail,
  });
}

export function createLegalOriginalQuarantineCleanupJobHandler(input: {
  readonly repository: LegalOriginalQuarantineCleanupRepository;
  readonly storage: LegalOriginalObjectStorage & ManagedObjectStorage;
  readonly workerId: string;
}): JobHandler {
  if (
    input.workerId.trim().length === 0 ||
    input.workerId.length > 200 ||
    !/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/u.test(input.workerId)
  ) {
    throw new TypeError("Legal cleanup worker ID must be a stable identifier.");
  }
  return async (job, context) => {
    const parsed = parseLegalOriginalQuarantineCleanupJob({
      entityId: job.entityId ?? "",
      entityType: job.entityType,
      jobType: job.jobType,
      payload: job.payload,
      payloadSchemaVersion: job.payloadSchemaVersion,
      workspaceId: job.workspaceId,
    });
    const lease = {
      attemptNumber: job.attemptNumber,
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      signal: context.signal,
      uploadSessionId: parsed.uploadSessionId,
      workerId: input.workerId,
      workspaceId: parsed.workspaceId,
    } as const;
    const source = await input.repository.load(lease);
    if (source.reason !== parsed.reason) {
      throw permanent(
        "media.legal_cleanup_reason_mismatch",
        "The legal upload cleanup fence differs from its durable job.",
      );
    }
    if (source.alreadyDeleted) {
      return {
        summary: {
          cleanup_id: source.cleanupId,
          replayed: true,
          upload_session_id: parsed.uploadSessionId,
        },
      };
    }
    const object = { bucket: source.bucket, objectKey: source.objectKey };
    const metadata = await input.storage.head({
      object,
      signal: context.signal,
    });
    if (metadata === null) {
      const completion = await input.repository.complete({
        ...lease,
        correlationId: job.correlationId,
        observedChecksumSha256: null,
        requestId: `job:${job.jobId}:legal-quarantine-not-found`,
        storageResult: "not_found",
      });
      return {
        summary: {
          cleanup_id: completion.cleanupId,
          cleanup_status: completion.cleanupStatus,
          replayed: completion.replayed,
          upload_session_id: parsed.uploadSessionId,
        },
      };
    }
    const provider = await input.storage.readLegalOriginal({
      object,
      signal: context.signal,
    });
    const bytes = await materializeMediaSource(
      provider.source,
      LEGAL_ORIGINAL_MAX_BYTES,
    );
    const checksumSha256 = await mediaSha256Hex(bytes);
    if (
      metadata.byteSize !== bytes.byteLength ||
      metadata.checksumSha256 !== checksumSha256 ||
      metadata.mimeType !== provider.providerMimeType
    ) {
      throw permanent(
        "media.legal_cleanup_provider_drift",
        "The legal upload quarantine object changed during verification.",
      );
    }
    const fence = await input.repository.fence({
      ...lease,
      observedByteSize: bytes.byteLength,
      observedChecksumSha256: checksumSha256,
      observedMimeType: provider.providerMimeType,
      storageGeneration: provider.generation,
    });
    if (fence.cleanupId !== source.cleanupId) {
      throw permanent(
        "media.legal_cleanup_fence_mismatch",
        "The legal upload cleanup database returned an inconsistent fence.",
      );
    }
    const storageResult = await input.storage.delete({
      ifChecksumSha256: checksumSha256,
      object,
      signal: context.signal,
    });
    if (storageResult === "precondition_failed") {
      throw permanent(
        "media.legal_cleanup_atomic_precondition_failed",
        "The legal upload object was replaced before atomic deletion.",
      );
    }
    const completion = await input.repository.complete({
      ...lease,
      correlationId: job.correlationId,
      observedChecksumSha256: checksumSha256,
      requestId: `job:${job.jobId}:legal-quarantine-cleanup`,
      storageResult,
    });
    return {
      summary: {
        cleanup_id: completion.cleanupId,
        cleanup_status: completion.cleanupStatus,
        replayed: completion.replayed,
        upload_session_id: parsed.uploadSessionId,
      },
    };
  };
}
