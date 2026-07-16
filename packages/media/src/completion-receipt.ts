import { MediaPolicyError } from "./errors";
import {
  vehiclePhotoDerivativeObjectKey,
  vehiclePhotoRawObjectKey,
} from "./object-keys";
import type { ManagedObjectMetadata } from "./ports";
import type { VehiclePhotoProcessingProfileSnapshot } from "./processing-profile";
import {
  validateVehiclePhotoProcessorReceipt,
  type VehiclePhotoProcessorReceipt,
} from "./processor-receipt";
import type { ValidatedVehiclePhotoSource } from "./upload-policy";
import {
  deepFreeze,
  hasExactKeys,
  isRecord,
  requirePositiveSafeInteger,
  requireSha256,
  requireUuid,
} from "./validation";

export const VEHICLE_PHOTO_COMPLETION_RECEIPT_SCHEMA_VERSION = 1;

export interface VehiclePhotoCompletionReceipt {
  readonly schemaVersion: typeof VEHICLE_PHOTO_COMPLETION_RECEIPT_SCHEMA_VERSION;
  readonly workspaceId: string;
  readonly mediaId: string;
  readonly processingRunId: string;
  readonly jobId: string;
  readonly workerId: string;
  readonly leaseId: string;
  readonly attempt: number;
  readonly profileChecksumSha256: string;
  readonly sourceChecksumSha256: string;
  readonly rawObject: ManagedObjectMetadata;
  readonly processorReceipt: VehiclePhotoProcessorReceipt;
  readonly derivativeObjects: readonly ManagedObjectMetadata[];
}

export interface VehiclePhotoCompletionContext {
  readonly workspaceId: string;
  readonly mediaId: string;
  readonly processingRunId: string;
  readonly jobId: string;
  readonly workerId: string;
  readonly leaseId: string;
  readonly attempt: number;
  readonly bucket: string;
  readonly source: ValidatedVehiclePhotoSource;
  readonly profile: VehiclePhotoProcessingProfileSnapshot;
}

const bucketPattern = /^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$/u;
const workerIdPattern = /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/u;

function requireBucket(value: unknown): string {
  if (typeof value !== "string" || !bucketPattern.test(value)) {
    throw new MediaPolicyError("invalid_completion_receipt");
  }
  return value;
}

function parseStoredObject(value: unknown): ManagedObjectMetadata {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "bucket",
      "objectKey",
      "byteSize",
      "mimeType",
      "checksumSha256",
    ]) ||
    typeof value.objectKey !== "string" ||
    value.objectKey.length < 1 ||
    typeof value.mimeType !== "string" ||
    value.mimeType.length < 1
  ) {
    throw new MediaPolicyError("invalid_completion_receipt");
  }

  return {
    bucket: requireBucket(value.bucket),
    objectKey: value.objectKey,
    byteSize: requirePositiveSafeInteger(
      value.byteSize,
      "invalid_completion_receipt",
    ),
    mimeType: value.mimeType,
    checksumSha256: requireSha256(
      value.checksumSha256,
      "invalid_completion_receipt",
    ),
  };
}

function requireExpectedIdentity(
  actual: unknown,
  expected: string,
  leaseIdentity: boolean,
): string {
  const normalized = requireUuid(
    actual,
    leaseIdentity ? "lease_identity_mismatch" : "invalid_completion_receipt",
  );
  if (normalized !== expected) {
    throw new MediaPolicyError(
      leaseIdentity ? "lease_identity_mismatch" : "invalid_completion_receipt",
    );
  }
  return normalized;
}

function requireExpectedWorkerId(actual: unknown, expected: string): string {
  if (
    typeof actual !== "string" ||
    typeof expected !== "string" ||
    actual.length < 1 ||
    actual.length > 200 ||
    expected.length < 1 ||
    expected.length > 200 ||
    !workerIdPattern.test(actual) ||
    !workerIdPattern.test(expected) ||
    actual !== expected
  ) {
    throw new MediaPolicyError("lease_identity_mismatch");
  }
  return actual;
}

/**
 * Validates that a completion can only be applied by the worker holding the
 * expected lease and that every stored object matches the deterministic plan.
 */
export function validateVehiclePhotoCompletionReceipt(input: {
  readonly receipt: unknown;
  readonly context: VehiclePhotoCompletionContext;
}): VehiclePhotoCompletionReceipt {
  const { receipt, context } = input;
  if (
    !isRecord(receipt) ||
    !hasExactKeys(receipt, [
      "schemaVersion",
      "workspaceId",
      "mediaId",
      "processingRunId",
      "jobId",
      "workerId",
      "leaseId",
      "attempt",
      "profileChecksumSha256",
      "sourceChecksumSha256",
      "rawObject",
      "processorReceipt",
      "derivativeObjects",
    ]) ||
    receipt.schemaVersion !== VEHICLE_PHOTO_COMPLETION_RECEIPT_SCHEMA_VERSION ||
    !Array.isArray(receipt.derivativeObjects)
  ) {
    throw new MediaPolicyError("invalid_completion_receipt");
  }

  const workspaceId = requireExpectedIdentity(
    receipt.workspaceId,
    requireUuid(context.workspaceId, "invalid_completion_receipt"),
    false,
  );
  const mediaId = requireExpectedIdentity(
    receipt.mediaId,
    requireUuid(context.mediaId, "invalid_completion_receipt"),
    false,
  );
  const processingRunId = requireExpectedIdentity(
    receipt.processingRunId,
    requireUuid(context.processingRunId, "invalid_completion_receipt"),
    false,
  );
  const jobId = requireExpectedIdentity(
    receipt.jobId,
    requireUuid(context.jobId, "invalid_completion_receipt"),
    false,
  );
  const workerId = requireExpectedWorkerId(receipt.workerId, context.workerId);
  const leaseId = requireExpectedIdentity(
    receipt.leaseId,
    requireUuid(context.leaseId, "lease_identity_mismatch"),
    true,
  );
  const attempt = requirePositiveSafeInteger(
    receipt.attempt,
    "lease_identity_mismatch",
  );
  if (attempt !== context.attempt) {
    throw new MediaPolicyError("lease_identity_mismatch");
  }

  const bucket = requireBucket(context.bucket);
  const profileChecksumSha256 = requireSha256(
    receipt.profileChecksumSha256,
    "invalid_completion_receipt",
  );
  const sourceChecksumSha256 = requireSha256(
    receipt.sourceChecksumSha256,
    "invalid_completion_receipt",
  );
  if (
    profileChecksumSha256 !== context.profile.checksumSha256 ||
    sourceChecksumSha256 !== context.source.checksumSha256
  ) {
    throw new MediaPolicyError("invalid_completion_receipt");
  }

  const rawObject = parseStoredObject(receipt.rawObject);
  const expectedRawKey = vehiclePhotoRawObjectKey({
    workspaceId,
    mediaId,
    checksumSha256: context.source.checksumSha256,
    mimeType: context.source.detectedMimeType,
  });
  if (
    rawObject.bucket !== bucket ||
    rawObject.objectKey !== expectedRawKey ||
    rawObject.byteSize !== context.source.sizeBytes ||
    rawObject.mimeType !== context.source.detectedMimeType ||
    rawObject.checksumSha256 !== context.source.checksumSha256
  ) {
    throw new MediaPolicyError("invalid_completion_receipt");
  }

  const processorReceipt = validateVehiclePhotoProcessorReceipt({
    receipt: receipt.processorReceipt,
    source: context.source,
    profile: context.profile,
  });
  if (receipt.derivativeObjects.length !== processorReceipt.outputs.length) {
    throw new MediaPolicyError("invalid_completion_receipt");
  }

  const objectsByKey = new Map<string, ManagedObjectMetadata>();
  for (const value of receipt.derivativeObjects) {
    const object = parseStoredObject(value);
    if (objectsByKey.has(object.objectKey)) {
      throw new MediaPolicyError("invalid_completion_receipt");
    }
    objectsByKey.set(object.objectKey, object);
  }

  const derivativeObjects = processorReceipt.outputs.map((output) => {
    const expectedKey = vehiclePhotoDerivativeObjectKey({
      workspaceId,
      mediaId,
      processingRunId,
      variant: output.variant,
      checksumSha256: output.checksumSha256,
    });
    const object = objectsByKey.get(expectedKey);
    if (
      object === undefined ||
      object.bucket !== bucket ||
      object.mimeType !== output.mimeType ||
      object.byteSize !== output.byteSize ||
      object.checksumSha256 !== output.checksumSha256
    ) {
      throw new MediaPolicyError("invalid_completion_receipt");
    }
    return object;
  });

  return deepFreeze({
    schemaVersion: VEHICLE_PHOTO_COMPLETION_RECEIPT_SCHEMA_VERSION,
    workspaceId,
    mediaId,
    processingRunId,
    jobId,
    workerId,
    leaseId,
    attempt,
    profileChecksumSha256,
    sourceChecksumSha256,
    rawObject,
    processorReceipt,
    derivativeObjects,
  });
}
