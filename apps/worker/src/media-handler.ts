import {
  buildVehiclePhotoProcessingJobPayload,
  MediaPolicyError,
  parseVehiclePhotoProcessingJob,
  planVehiclePhotoDerivatives,
  validateVehiclePhotoCompletionReceipt,
  validateVehiclePhotoProcessorReceipt,
  validateVehiclePhotoSource,
  vehiclePhotoDerivativeObjectKey,
  vehiclePhotoRawObjectKey,
  verifyVehiclePhotoProcessingProfileSnapshot,
  type ManagedObjectMetadata,
  type ManagedObjectStorage,
  type MediaMalwareScanner,
  type VehiclePhotoDerivativeVariant,
  type VehiclePhotoProcessingProfileSnapshot,
  type VehiclePhotoProcessorReceipt,
} from "@vynlo/media";
import type { ClaimedJob } from "./job-store";
import { JobExecutionError, type JobHandler } from "./job-runner";
import {
  materializeMediaSource,
  mediaSha256Hex,
} from "./managed-media-storage";

export const MEDIA_PROCESSING_JOB_TYPE = "media.process_vehicle_photo" as const;
export const MEDIA_RAW_RETENTION_JOB_TYPE =
  "media.delete_retained_raw" as const;

export interface MediaProcessingSource {
  readonly alreadySucceeded: boolean;
  readonly bucket: string;
  readonly byteSize: number;
  readonly checksumSha256: string;
  readonly exifOrientation: number | null;
  readonly generation: number;
  readonly height: number;
  readonly mediaStatus: "processing" | "ready";
  readonly mimeType:
    "image/jpeg" | "image/png" | "image/webp" | "image/heic" | "image/heif";
  readonly objectKey: string;
  readonly profile: VehiclePhotoProcessingProfileSnapshot;
  readonly width: number;
}

export interface MediaCompletionResult {
  readonly aggregateVersion: number;
  readonly mediaStatus: "ready";
  readonly normalizedMasterFileId: string;
  readonly rawDeleteAfter: string;
  readonly rawFileId: string;
  readonly replayed: boolean;
}

export interface MediaProcessingRepository {
  complete(input: {
    readonly attemptNumber: number;
    readonly correlationId: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly mediaId: string;
    readonly processingRunId: string;
    readonly receipt: unknown;
    readonly requestId: string;
    readonly signal: AbortSignal;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<MediaCompletionResult>;
  recordFailure(input: {
    readonly attemptNumber: number;
    readonly classification: JobExecutionError["classification"];
    readonly correlationId: string;
    readonly errorCode: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly mediaId: string;
    readonly processingRunId: string;
    readonly requestId: string;
    readonly signal: AbortSignal;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<void>;
  start(input: {
    readonly attemptNumber: number;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly mediaId: string;
    readonly processingRunId: string;
    readonly requestId: string;
    readonly signal: AbortSignal;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<MediaProcessingSource>;
}

export interface ProcessedVehiclePhotoOutput {
  readonly body: Uint8Array;
  readonly variant: VehiclePhotoDerivativeVariant;
}

/**
 * Worker codec boundary. A production adapter may use Sharp/libvips only after
 * deployment probes prove the required input codecs, including HEIC/HEIF.
 */
export interface VehiclePhotoBinaryProcessor {
  process(input: {
    readonly derivativePlan: ReturnType<typeof planVehiclePhotoDerivatives>;
    readonly profile: VehiclePhotoProcessingProfileSnapshot;
    readonly signal: AbortSignal;
    readonly source: Uint8Array;
    readonly validatedSource: ReturnType<typeof validateVehiclePhotoSource>;
  }): Promise<{
    readonly outputs: readonly ProcessedVehiclePhotoOutput[];
    readonly receipt: VehiclePhotoProcessorReceipt;
  }>;
}

function extensionFilename(
  mimeType: MediaProcessingSource["mimeType"],
): string {
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

function policyFailure(error: unknown): JobExecutionError {
  if (error instanceof JobExecutionError) return error;
  if (error instanceof MediaPolicyError) {
    return new JobExecutionError({
      classification: "validation",
      code: `media.${error.code}`,
      safeDetail:
        "The vehicle photo failed a deterministic media policy check.",
    });
  }
  return new JobExecutionError({
    classification: "unknown",
    code: "media.unhandled_processing_failure",
    safeDetail:
      "Vehicle photo processing failed without a safe classified error.",
  });
}

function assertScanReceipt(
  receipt: Awaited<ReturnType<MediaMalwareScanner["scan"]>>,
  checksumSha256: string,
): void {
  if (
    receipt.sourceChecksumSha256 !== checksumSha256 ||
    receipt.verdict !== "clean" ||
    receipt.scanner.name.trim() === "" ||
    receipt.scanner.version.trim() === "" ||
    receipt.signatureVersion.trim() === ""
  ) {
    throw new JobExecutionError({
      classification: "validation",
      code:
        receipt.verdict === "infected"
          ? "media.malware_detected"
          : "media.invalid_scan_receipt",
      safeDetail:
        "The quarantined vehicle photo did not pass malware validation.",
    });
  }
}

export function createVehiclePhotoJobHandler(input: {
  readonly processor: VehiclePhotoBinaryProcessor;
  readonly repository: MediaProcessingRepository;
  readonly scanner: MediaMalwareScanner;
  readonly storage: ManagedObjectStorage;
  readonly workerId: string;
}): JobHandler {
  return async (job: ClaimedJob, context) => {
    const parsed = parseVehiclePhotoProcessingJob({
      ...job,
      entityId: job.entityId ?? "",
    });
    let source: MediaProcessingSource | undefined;
    try {
      source = await input.repository.start({
        attemptNumber: job.attemptNumber,
        jobId: job.jobId,
        leaseToken: job.leaseToken,
        mediaId: parsed.mediaId,
        processingRunId: parsed.processingRunId,
        requestId: `job:${job.jobId}:start`,
        signal: context.signal,
        workerId: input.workerId,
        workspaceId: parsed.workspaceId,
      });
      if (source.alreadySucceeded) {
        return {
          summary: {
            media_id: parsed.mediaId,
            media_status: "ready",
            replayed: true,
          },
        };
      }
      if (
        source.profile.checksumSha256 !== parsed.profileChecksumSha256 ||
        !(await verifyVehiclePhotoProcessingProfileSnapshot(source.profile))
      ) {
        throw new JobExecutionError({
          classification: "permanent",
          code: "media.profile_snapshot_mismatch",
          safeDetail:
            "The immutable media profile snapshot failed checksum validation.",
        });
      }

      const sourceBytes = await materializeMediaSource(
        await input.storage.read({
          object: { bucket: source.bucket, objectKey: source.objectKey },
          signal: context.signal,
        }),
        20_000_000,
      );
      const observedChecksum = await mediaSha256Hex(sourceBytes);
      const validatedSource = validateVehiclePhotoSource({
        checksumSha256: observedChecksum,
        exifOrientation: source.exifOrientation,
        height: source.height,
        intent: {
          checksumSha256: source.checksumSha256,
          declaredMimeType: source.mimeType,
          filename: extensionFilename(source.mimeType),
          maximumPixels: 60_000_000,
          sizeBytes: source.byteSize,
        },
        observedSizeBytes: sourceBytes.byteLength,
        signatureBytes: sourceBytes.slice(0, 64),
        width: source.width,
      });
      const scanReceipt = await input.scanner.scan({
        signal: context.signal,
        source: sourceBytes,
        sourceChecksumSha256: observedChecksum,
      });
      assertScanReceipt(scanReceipt, observedChecksum);

      const derivativePlan = planVehiclePhotoDerivatives({
        profile: source.profile,
        sourceHeight: source.height,
        sourceWidth: source.width,
      });
      const processed = await input.processor.process({
        derivativePlan,
        profile: source.profile,
        signal: context.signal,
        source: sourceBytes,
        validatedSource,
      });
      const processorReceipt = validateVehiclePhotoProcessorReceipt({
        profile: source.profile,
        receipt: processed.receipt,
        source: validatedSource,
      });
      const bodies = new Map(
        processed.outputs.map((output) => [output.variant, output.body]),
      );
      if (bodies.size !== processorReceipt.outputs.length) {
        throw new MediaPolicyError("invalid_processor_receipt");
      }

      const rawObject = await input.storage.putIfAbsent({
        body: sourceBytes,
        byteSize: sourceBytes.byteLength,
        checksumSha256: observedChecksum,
        mimeType: source.mimeType,
        object: {
          bucket: "media-private",
          objectKey: vehiclePhotoRawObjectKey({
            checksumSha256: observedChecksum,
            mediaId: parsed.mediaId,
            mimeType: source.mimeType,
            workspaceId: parsed.workspaceId,
          }),
        },
        signal: context.signal,
      });
      const derivativeObjects: ManagedObjectMetadata[] = [];
      for (const output of processorReceipt.outputs) {
        const body = bodies.get(output.variant);
        if (body === undefined)
          throw new MediaPolicyError("invalid_processor_receipt");
        derivativeObjects.push(
          await input.storage.putIfAbsent({
            body,
            byteSize: output.byteSize,
            checksumSha256: output.checksumSha256,
            mimeType: output.mimeType,
            object: {
              bucket: "media-private",
              objectKey: vehiclePhotoDerivativeObjectKey({
                checksumSha256: output.checksumSha256,
                mediaId: parsed.mediaId,
                processingRunId: parsed.processingRunId,
                variant: output.variant,
                workspaceId: parsed.workspaceId,
              }),
            },
            signal: context.signal,
          }),
        );
      }

      const receipt = validateVehiclePhotoCompletionReceipt({
        context: {
          attempt: job.attemptNumber,
          bucket: "media-private",
          jobId: job.jobId,
          leaseId: job.leaseToken,
          mediaId: parsed.mediaId,
          processingRunId: parsed.processingRunId,
          profile: source.profile,
          source: validatedSource,
          workerId: input.workerId,
          workspaceId: parsed.workspaceId,
        },
        receipt: {
          attempt: job.attemptNumber,
          derivativeObjects,
          jobId: job.jobId,
          leaseId: job.leaseToken,
          mediaId: parsed.mediaId,
          processingRunId: parsed.processingRunId,
          processorReceipt,
          profileChecksumSha256: source.profile.checksumSha256,
          rawObject,
          schemaVersion: 1,
          sourceChecksumSha256: observedChecksum,
          workerId: input.workerId,
          workspaceId: parsed.workspaceId,
        },
      });
      const completion = await input.repository.complete({
        attemptNumber: job.attemptNumber,
        correlationId: job.correlationId,
        jobId: job.jobId,
        leaseToken: job.leaseToken,
        mediaId: parsed.mediaId,
        processingRunId: parsed.processingRunId,
        receipt,
        requestId: `job:${job.jobId}:complete`,
        signal: context.signal,
        workerId: input.workerId,
        workspaceId: parsed.workspaceId,
      });
      return {
        summary: {
          aggregate_version: completion.aggregateVersion,
          media_id: parsed.mediaId,
          media_status: completion.mediaStatus,
          normalized_master_file_id: completion.normalizedMasterFileId,
          raw_delete_after: completion.rawDeleteAfter,
          raw_file_id: completion.rawFileId,
          replayed: completion.replayed,
        },
      };
    } catch (error) {
      const failure = policyFailure(error);
      if (source !== undefined) {
        await input.repository.recordFailure({
          attemptNumber: job.attemptNumber,
          classification: failure.classification,
          correlationId: job.correlationId,
          errorCode: failure.code,
          jobId: job.jobId,
          leaseToken: job.leaseToken,
          mediaId: parsed.mediaId,
          processingRunId: parsed.processingRunId,
          requestId: `job:${job.jobId}:failure`,
          signal: context.signal,
          workerId: input.workerId,
          workspaceId: parsed.workspaceId,
        });
      }
      throw failure;
    }
  };
}

export interface RawRetentionRepository {
  complete(input: {
    readonly attemptNumber: number;
    readonly correlationId: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly mediaFileId: string;
    readonly requestId: string;
    readonly signal: AbortSignal;
    readonly storageResult: "deleted" | "not_found";
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<{
    readonly deletedAt: string;
    readonly mediaId: string;
    readonly replayed: boolean;
  }>;
  load(input: {
    readonly attemptNumber: number;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly mediaFileId: string;
    readonly signal: AbortSignal;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<{
    readonly alreadyDeleted: boolean;
    readonly checksumSha256: string;
    readonly mediaId: string;
    readonly storageBucket: string;
    readonly storageObjectKey: string;
  }>;
}

export function createRawRetentionJobHandler(input: {
  readonly repository: RawRetentionRepository;
  readonly storage: ManagedObjectStorage;
  readonly workerId: string;
}): JobHandler {
  return async (job, context) => {
    if (
      job.jobType !== MEDIA_RAW_RETENTION_JOB_TYPE ||
      job.entityType !== "media_file" ||
      job.payloadSchemaVersion !== 1 ||
      typeof job.payload.media_file_id !== "string" ||
      job.payload.media_file_id !== job.entityId
    ) {
      throw new JobExecutionError({
        classification: "permanent",
        code: "media.invalid_retention_job",
        safeDetail: "The raw-retention job contract is invalid.",
      });
    }
    const source = await input.repository.load({
      attemptNumber: job.attemptNumber,
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      mediaFileId: job.payload.media_file_id,
      signal: context.signal,
      workerId: input.workerId,
      workspaceId: job.workspaceId,
    });
    if (source.alreadyDeleted) {
      return { summary: { media_file_id: job.entityId, replayed: true } };
    }
    const storageResult = await input.storage.delete({
      ifChecksumSha256: source.checksumSha256,
      object: {
        bucket: source.storageBucket,
        objectKey: source.storageObjectKey,
      },
      signal: context.signal,
    });
    if (storageResult === "precondition_failed") {
      throw new JobExecutionError({
        classification: "permanent",
        code: "media.retention_checksum_conflict",
        safeDetail: "The retained raw object checksum changed unexpectedly.",
      });
    }
    const completion = await input.repository.complete({
      attemptNumber: job.attemptNumber,
      correlationId: job.correlationId,
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      mediaFileId: job.payload.media_file_id,
      requestId: `job:${job.jobId}:retention`,
      signal: context.signal,
      storageResult,
      workerId: input.workerId,
      workspaceId: job.workspaceId,
    });
    return {
      summary: {
        deleted_at: completion.deletedAt,
        media_file_id: job.entityId,
        media_id: completion.mediaId,
        replayed: completion.replayed,
      },
    };
  };
}

export { buildVehiclePhotoProcessingJobPayload };
