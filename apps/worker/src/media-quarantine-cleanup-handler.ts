import {
  MEDIA_QUARANTINE_CLEANUP_JOB_TYPE,
  parseMediaQuarantineCleanupJob,
  type ManagedObjectStorage,
  type MediaQuarantineCleanupReason,
} from "@vynlo/media";

import type { ClaimedJob } from "./job-store";
import { JobExecutionError, type JobHandler } from "./job-runner";

export { MEDIA_QUARANTINE_CLEANUP_JOB_TYPE };

interface QuarantineCleanupLease {
  readonly attemptNumber: number;
  readonly jobId: string;
  readonly leaseToken: string;
  readonly signal: AbortSignal;
  readonly uploadSessionId: string;
  readonly workerId: string;
  readonly workspaceId: string;
}

export interface MediaQuarantineCleanupSource {
  readonly alreadyDeleted: boolean;
  readonly bucket: string;
  readonly cleanupId: string;
  readonly expectedChecksumSha256: string | null;
  readonly generation: number;
  readonly mediaId: string;
  readonly objectKey: string;
  readonly reason: MediaQuarantineCleanupReason;
}

export interface MediaQuarantineCleanupRepository {
  complete(
    input: QuarantineCleanupLease & {
      readonly correlationId: string;
      readonly objectChecksumSha256: string | null;
      readonly requestId: string;
      readonly storageResult: "deleted" | "not_found";
    },
  ): Promise<{
    readonly cleanupId: string;
    readonly cleanupStatus: "deleted" | "not_found";
    readonly completedAt: string;
    readonly mediaId: string;
    readonly replayed: boolean;
  }>;
  fenceChecksum(
    input: QuarantineCleanupLease & {
      readonly observedByteSize: number;
      readonly observedChecksumSha256: string;
    },
  ): Promise<{
    readonly checksumSha256: string;
    readonly cleanupId: string;
    readonly replayed: boolean;
  }>;
  load(input: QuarantineCleanupLease): Promise<MediaQuarantineCleanupSource>;
}

function permanent(code: string, safeDetail: string): JobExecutionError {
  return new JobExecutionError({
    classification: "permanent",
    code,
    safeDetail,
  });
}

export function createMediaQuarantineCleanupJobHandler(input: {
  readonly repository: MediaQuarantineCleanupRepository;
  readonly storage: ManagedObjectStorage;
  readonly workerId: string;
}): JobHandler {
  if (
    input.workerId.trim().length === 0 ||
    input.workerId.length > 200 ||
    !/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/u.test(input.workerId)
  ) {
    throw new TypeError(
      "Media cleanup worker ID must be a stable non-secret identifier.",
    );
  }
  return async (job: ClaimedJob, context) => {
    const parsed = parseMediaQuarantineCleanupJob({
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
    if (
      source.mediaId !== parsed.mediaId ||
      source.generation !== parsed.generation ||
      source.reason !== parsed.reason ||
      source.expectedChecksumSha256 !== parsed.checksumSha256
    ) {
      throw permanent(
        "media.quarantine_cleanup_fence_mismatch",
        "The quarantine cleanup database fence differs from its durable job.",
      );
    }
    if (source.alreadyDeleted) {
      return {
        summary: {
          cleanup_id: source.cleanupId,
          media_id: source.mediaId,
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
        objectChecksumSha256: null,
        requestId: `job:${job.jobId}:quarantine-not-found`,
        storageResult: "not_found",
      });
      return {
        summary: {
          cleanup_id: completion.cleanupId,
          cleanup_status: completion.cleanupStatus,
          completed_at: completion.completedAt,
          media_id: completion.mediaId,
          replayed: completion.replayed,
          upload_session_id: parsed.uploadSessionId,
        },
      };
    }
    if (
      source.expectedChecksumSha256 !== null &&
      metadata.checksumSha256 !== source.expectedChecksumSha256
    ) {
      throw permanent(
        "media.quarantine_cleanup_checksum_conflict",
        "The quarantine object differs from its persisted source checksum.",
      );
    }

    const fence = await input.repository.fenceChecksum({
      ...lease,
      observedByteSize: metadata.byteSize,
      observedChecksumSha256: metadata.checksumSha256,
    });
    if (
      fence.cleanupId !== source.cleanupId ||
      fence.checksumSha256 !== metadata.checksumSha256
    ) {
      throw permanent(
        "media.quarantine_cleanup_checksum_fence_failed",
        "The quarantine checksum fence returned inconsistent state.",
      );
    }

    const storageResult = await input.storage.delete({
      ifChecksumSha256: metadata.checksumSha256,
      object,
      signal: context.signal,
    });
    if (storageResult === "precondition_failed") {
      throw permanent(
        "media.quarantine_cleanup_atomic_precondition_failed",
        "The quarantine object was replaced before atomic deletion.",
      );
    }

    const completion = await input.repository.complete({
      ...lease,
      correlationId: job.correlationId,
      objectChecksumSha256: metadata.checksumSha256,
      requestId: `job:${job.jobId}:quarantine-cleanup`,
      storageResult,
    });
    return {
      summary: {
        cleanup_id: completion.cleanupId,
        cleanup_status: completion.cleanupStatus,
        completed_at: completion.completedAt,
        media_id: completion.mediaId,
        replayed: completion.replayed,
        upload_session_id: parsed.uploadSessionId,
      },
    };
  };
}
