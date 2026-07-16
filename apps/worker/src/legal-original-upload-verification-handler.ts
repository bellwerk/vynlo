import {
  buildLegalOriginalVerificationReceipt,
  detectLegalOriginalMimeType,
  LEGAL_ORIGINAL_MAX_BYTES,
  normalizeLegalOriginalIntent,
  parseLegalOriginalUploadVerificationJob,
  type LegalOriginalMediaKind,
  type LegalOriginalMimeType,
  type LegalOriginalObjectStorage,
  type LegalOriginalVerificationReceipt,
  type MalwareScanReceipt,
  type MediaMalwareScanner,
  MediaPolicyError,
} from "@vynlo/media";

import { JobExecutionError, type JobHandler } from "./job-runner";
import {
  materializeMediaSource,
  mediaSha256Hex,
} from "./managed-media-storage";

export const LEGAL_ORIGINAL_UPLOAD_VERIFICATION_JOB_TYPE =
  "media.verify_legal_original" as const;

interface LegalOriginalLeaseInput {
  readonly attemptNumber: number;
  readonly correlationId: string;
  readonly documentId: string;
  readonly jobId: string;
  readonly leaseToken: string;
  readonly requestId: string;
  readonly signal: AbortSignal;
  readonly uploadSessionId: string;
  readonly workerId: string;
  readonly workspaceId: string;
}

export interface LegalOriginalUploadSource {
  readonly actorUserId: string;
  readonly bucket: "media-private";
  readonly expectedByteSize: number;
  readonly expectedChecksumSha256: string;
  readonly expectedMimeType: LegalOriginalMimeType;
  readonly mediaKind: LegalOriginalMediaKind;
  readonly objectKey: string;
}

export interface LegalOriginalUploadVerificationRepository {
  complete(
    input: LegalOriginalLeaseInput & {
      readonly observedByteSize: number;
      readonly observedChecksumSha256: string;
      readonly observedMimeType: LegalOriginalMimeType;
      readonly storageGeneration: string;
      readonly verificationReceipt: LegalOriginalVerificationReceipt;
    },
  ): Promise<{
    readonly mediaFileId: string;
    readonly mediaId: string;
    readonly replayed: boolean;
  }>;
  load(input: LegalOriginalLeaseInput): Promise<LegalOriginalUploadSource>;
  reject(
    input: LegalOriginalLeaseInput & {
      readonly errorClassification: "permanent" | "permission" | "validation";
      readonly errorCode: string;
    },
  ): Promise<void>;
}

function failure(error: unknown): JobExecutionError {
  if (error instanceof JobExecutionError) return error;
  if (error instanceof MediaPolicyError) {
    return new JobExecutionError({
      classification: "validation",
      code: `media.${error.code}`,
      safeDetail: "The preserved original failed deterministic verification.",
    });
  }
  return new JobExecutionError({
    classification: "unknown",
    code: "media.unhandled_legal_original_verification_failure",
    safeDetail: "The preserved original verification failed unexpectedly.",
  });
}

function assertClean(receipt: MalwareScanReceipt, checksum: string): void {
  if (
    receipt.sourceChecksumSha256 !== checksum ||
    receipt.scanner.name.trim() === "" ||
    receipt.scanner.version.trim() === "" ||
    receipt.signatureVersion.trim() === ""
  ) {
    throw new JobExecutionError({
      classification: "validation",
      code: "media.invalid_scan_receipt",
      safeDetail: "The private malware scanner returned an invalid receipt.",
    });
  }
  if (receipt.verdict !== "clean") {
    throw new JobExecutionError({
      classification: "validation",
      code: "media.malware_detected",
      safeDetail: "The preserved original did not pass malware validation.",
    });
  }
}

export function createLegalOriginalUploadVerificationJobHandler(input: {
  readonly repository: LegalOriginalUploadVerificationRepository;
  readonly scanner: MediaMalwareScanner;
  readonly storage: LegalOriginalObjectStorage;
  readonly workerId: string;
}): JobHandler {
  return async (job, context) => {
    const parsed = parseLegalOriginalUploadVerificationJob({
      entityId: job.entityId ?? "",
      entityType: job.entityType,
      jobType: job.jobType,
      payload: job.payload,
      payloadSchemaVersion: job.payloadSchemaVersion,
      workspaceId: job.workspaceId,
    });
    const lease = {
      attemptNumber: job.attemptNumber,
      correlationId: job.correlationId,
      documentId: parsed.documentId,
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      requestId: `job:${job.jobId}:verify-legal-original`,
      signal: context.signal,
      uploadSessionId: parsed.uploadSessionId,
      workerId: input.workerId,
      workspaceId: parsed.workspaceId,
    } as const;
    let loaded = false;
    try {
      const source = await input.repository.load(lease);
      loaded = true;
      const providerObject = await input.storage.readLegalOriginal({
        object: { bucket: source.bucket, objectKey: source.objectKey },
        signal: context.signal,
      });
      const bytes = await materializeMediaSource(
        providerObject.source,
        LEGAL_ORIGINAL_MAX_BYTES,
      );
      const checksumSha256 = await mediaSha256Hex(bytes);

      // No file parser or signature interpretation runs before this scan.
      const malwareScan = await input.scanner.scan({
        signal: context.signal,
        source: bytes,
        sourceChecksumSha256: checksumSha256,
      });
      assertClean(malwareScan, checksumSha256);

      const mimeType = detectLegalOriginalMimeType(bytes);
      normalizeLegalOriginalIntent({
        byteSize: bytes.byteLength,
        checksumSha256,
        filename: `original.${mimeType === "application/pdf" ? "pdf" : "image"}`,
        mediaKind: source.mediaKind,
        mimeType: mimeType ?? "application/octet-stream",
      });
      if (
        mimeType === null ||
        mimeType !== source.expectedMimeType ||
        providerObject.providerMimeType !== mimeType ||
        bytes.byteLength !== source.expectedByteSize ||
        checksumSha256 !== source.expectedChecksumSha256
      ) {
        throw new MediaPolicyError("invalid_legal_original");
      }
      const receipt = buildLegalOriginalVerificationReceipt({
        attempt: job.attemptNumber,
        bucket: source.bucket,
        byteSize: bytes.byteLength,
        checksumSha256,
        generation: providerObject.generation,
        jobId: job.jobId,
        leaseId: job.leaseToken,
        malwareScan,
        mimeType,
        objectKey: source.objectKey,
        workerId: input.workerId,
      });
      const completed = await input.repository.complete({
        ...lease,
        observedByteSize: bytes.byteLength,
        observedChecksumSha256: checksumSha256,
        observedMimeType: mimeType,
        requestId: `job:${job.jobId}:complete-legal-original`,
        storageGeneration: providerObject.generation,
        verificationReceipt: receipt,
      });
      return {
        summary: {
          media_file_id: completed.mediaFileId,
          media_id: completed.mediaId,
          replayed: completed.replayed,
          upload_session_id: parsed.uploadSessionId,
        },
      };
    } catch (error) {
      const safe = failure(error);
      if (
        loaded &&
        (safe.classification === "validation" ||
          safe.classification === "permanent" ||
          safe.classification === "permission")
      ) {
        await input.repository.reject({
          ...lease,
          errorClassification: safe.classification,
          errorCode: safe.code,
          requestId: `job:${job.jobId}:reject-legal-original`,
        });
      }
      throw safe;
    }
  };
}
