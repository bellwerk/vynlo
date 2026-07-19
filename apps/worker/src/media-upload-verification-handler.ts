import {
  MediaPolicyError,
  normalizeVehiclePhotoUploadIntent,
  parseVehiclePhotoUploadVerificationJob,
  validateVehiclePhotoSource,
  type MalwareScanReceipt,
  type ManagedObjectStorage,
  type MediaMalwareScanner,
  type VehiclePhotoMimeType,
} from "@vynlo/media";

import { JobExecutionError, type JobHandler } from "./job-runner";
import {
  materializeMediaSource,
  mediaSha256Hex,
} from "./managed-media-storage";
import { inspectVehiclePhotoWithSharp } from "./sharp-vehicle-photo-processor";

export const MEDIA_UPLOAD_VERIFICATION_JOB_TYPE =
  "media.verify_vehicle_photo_upload" as const;

export interface MediaUploadVerificationSource {
  readonly actorUserId: string;
  readonly bucket: string;
  readonly expectedByteSize: number;
  readonly expectedChecksumSha256: string;
  readonly expectedMimeType: VehiclePhotoMimeType;
  readonly expiresAt: string;
  readonly objectKey: string;
}

interface VerificationLeaseInput {
  readonly attemptNumber: number;
  readonly correlationId: string;
  readonly jobId: string;
  readonly leaseToken: string;
  readonly mediaId: string;
  readonly requestId: string;
  readonly signal: AbortSignal;
  readonly uploadSessionId: string;
  readonly workerId: string;
  readonly workspaceId: string;
}

export interface MediaUploadVerificationRepository {
  complete(
    input: VerificationLeaseInput & {
      readonly exifOrientation: number | null;
      readonly height: number;
      readonly malwareScanReceipt: MalwareScanReceipt;
      readonly observedByteSize: number;
      readonly observedChecksumSha256: string;
      readonly observedMimeType: VehiclePhotoMimeType;
      readonly width: number;
    },
  ): Promise<{
    readonly aggregateVersion: number;
    readonly mediaStatus: "quarantined";
    readonly processingJobId: string;
    readonly processingRunId: string;
    readonly replayed: boolean;
  }>;
  load(input: VerificationLeaseInput): Promise<MediaUploadVerificationSource>;
  reject(
    input: VerificationLeaseInput & {
      readonly errorClassification:
        "permanent" | "permission" | "provider_auth" | "validation";
      readonly errorCode: string;
    },
  ): Promise<void>;
}

function filenameForMimeType(mimeType: VehiclePhotoMimeType): string {
  return `source.${
    {
      "image/heic": "heic",
      "image/heif": "heif",
      "image/jpeg": "jpg",
      "image/png": "png",
      "image/webp": "webp",
    }[mimeType]
  }`;
}

function safeFailure(error: unknown): JobExecutionError {
  if (error instanceof JobExecutionError) return error;
  if (error instanceof MediaPolicyError) {
    return new JobExecutionError({
      classification: "validation",
      code: `media.${error.code}`,
      safeDetail:
        "The uploaded vehicle photo failed a deterministic verification check.",
    });
  }
  return new JobExecutionError({
    classification: "unknown",
    code: "media.unhandled_upload_verification_failure",
    safeDetail:
      "Vehicle photo verification failed without a safe classified error.",
  });
}

function assertCleanReceipt(
  receipt: MalwareScanReceipt,
  checksumSha256: string,
): void {
  if (
    receipt.sourceChecksumSha256 !== checksumSha256 ||
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
      safeDetail: "The quarantined upload did not pass malware validation.",
    });
  }
}

function isTerminalVerificationFailure(
  classification: JobExecutionError["classification"],
): classification is
  "permanent" | "permission" | "provider_auth" | "validation" {
  return ["permanent", "permission", "provider_auth", "validation"].includes(
    classification,
  );
}

export function createMediaUploadVerificationJobHandler(input: {
  readonly inspect?: typeof inspectVehiclePhotoWithSharp;
  readonly repository: MediaUploadVerificationRepository;
  readonly scanner: MediaMalwareScanner;
  readonly storage: ManagedObjectStorage;
  readonly workerId: string;
}): JobHandler {
  return async (job, context) => {
    const parsed = parseVehiclePhotoUploadVerificationJob({
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
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      mediaId: parsed.mediaId,
      requestId: `job:${job.jobId}:verify-upload`,
      signal: context.signal,
      uploadSessionId: parsed.uploadSessionId,
      workerId: input.workerId,
      workspaceId: parsed.workspaceId,
    } as const;
    let source: MediaUploadVerificationSource | undefined;

    try {
      source = await input.repository.load(lease);
      const bytes = await materializeMediaSource(
        await input.storage.read({
          object: { bucket: source.bucket, objectKey: source.objectKey },
          signal: context.signal,
        }),
        20_000_000,
      );
      const checksumSha256 = await mediaSha256Hex(bytes);
      const scanReceipt = await input.scanner.scan({
        signal: context.signal,
        source: bytes,
        sourceChecksumSha256: checksumSha256,
      });
      assertCleanReceipt(scanReceipt, checksumSha256);
      const inspected = await (input.inspect ?? inspectVehiclePhotoWithSharp)({
        maximumPixels: 60_000_000,
        signal: context.signal,
        source: bytes,
      });
      const validated = validateVehiclePhotoSource({
        checksumSha256,
        exifOrientation: inspected.exifOrientation,
        height: inspected.height,
        intent: normalizeVehiclePhotoUploadIntent({
          checksumSha256: source.expectedChecksumSha256,
          declaredMimeType: source.expectedMimeType,
          filename: filenameForMimeType(source.expectedMimeType),
          sizeBytes: source.expectedByteSize,
        }),
        observedSizeBytes: bytes.byteLength,
        signatureBytes: bytes.slice(0, 64),
        width: inspected.width,
      });
      const completion = await input.repository.complete({
        ...lease,
        exifOrientation: validated.exifOrientation,
        height: validated.height,
        malwareScanReceipt: scanReceipt,
        observedByteSize: validated.sizeBytes,
        observedChecksumSha256: validated.checksumSha256,
        observedMimeType: validated.detectedMimeType,
        requestId: `job:${job.jobId}:complete-upload`,
        width: validated.width,
      });
      return {
        summary: {
          aggregate_version: completion.aggregateVersion,
          media_id: parsed.mediaId,
          media_status: completion.mediaStatus,
          processing_job_id: completion.processingJobId,
          processing_run_id: completion.processingRunId,
          replayed: completion.replayed,
          upload_session_id: parsed.uploadSessionId,
        },
      };
    } catch (error) {
      const failure = safeFailure(error);
      if (
        source !== undefined &&
        isTerminalVerificationFailure(failure.classification)
      ) {
        await input.repository.reject({
          ...lease,
          errorClassification: failure.classification,
          errorCode: failure.code,
          requestId: `job:${job.jobId}:reject-upload`,
        });
      }
      throw failure;
    }
  };
}
