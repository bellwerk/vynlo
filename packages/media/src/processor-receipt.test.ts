import { describe, expect, it } from "vitest";

import {
  validateVehiclePhotoCompletionReceipt,
  type VehiclePhotoCompletionContext,
} from "./completion-receipt";
import { MediaPolicyError } from "./errors";
import {
  vehiclePhotoDerivativeObjectKey,
  vehiclePhotoRawObjectKey,
} from "./object-keys";
import {
  createVehiclePhotoProcessingProfileSnapshot,
  planVehiclePhotoDerivatives,
} from "./processing-profile";
import {
  validateVehiclePhotoProcessorReceipt,
  type VehiclePhotoProcessorReceipt,
} from "./processor-receipt";
import type { ValidatedVehiclePhotoSource } from "./upload-policy";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const MEDIA_ID = "20000000-0000-4000-8000-000000000001";
const RUN_ID = "30000000-0000-4000-8000-000000000001";
const JOB_ID = "40000000-0000-4000-8000-000000000001";
const WORKER_ID = "local-worker-1";
const LEASE_ID = "60000000-0000-4000-8000-000000000001";
const SOURCE_CHECKSUM = "a".repeat(64);
const BUCKET = "managed-media";

function expectCode(operation: () => unknown, code: string): void {
  expect(operation).toThrowError(MediaPolicyError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

async function fixture() {
  const source: ValidatedVehiclePhotoSource = {
    detectedMimeType: "image/jpeg",
    sizeBytes: 1_000,
    width: 4_000,
    height: 3_000,
    pixelCount: 12_000_000,
    checksumSha256: SOURCE_CHECKSUM,
    exifOrientation: 6,
  };
  const profile = await createVehiclePhotoProcessingProfileSnapshot({
    profileKey: "vehicle-photo.standard",
    version: 1,
  });
  const plan = planVehiclePhotoDerivatives({
    sourceWidth: source.width,
    sourceHeight: source.height,
    profile,
  });
  const processorReceipt: VehiclePhotoProcessorReceipt = {
    processor: { name: "test-processor", version: "1.2.3" },
    profileChecksumSha256: profile.checksumSha256,
    sourceChecksumSha256: source.checksumSha256,
    outputs: plan.map((output, index) => ({
      variant: output.variant,
      role: output.role,
      mimeType: output.mimeType,
      width: output.width,
      height: output.height,
      byteSize: 500 + index,
      checksumSha256: (index + 2).toString(16).repeat(64),
      orientationPolicyApplied: true,
      normalizedOrientation: 1,
      outputColorSpace: "srgb",
      upscaled: false,
      metadata: {
        exifPresent: false,
        gpsPresent: false,
        iptcPresent: false,
        xmpPresent: false,
      },
    })),
  };
  const context: VehiclePhotoCompletionContext = {
    workspaceId: WORKSPACE_ID,
    mediaId: MEDIA_ID,
    processingRunId: RUN_ID,
    jobId: JOB_ID,
    workerId: WORKER_ID,
    leaseId: LEASE_ID,
    attempt: 2,
    bucket: BUCKET,
    source,
    profile,
  };
  const completionReceipt = {
    schemaVersion: 1,
    workspaceId: WORKSPACE_ID,
    mediaId: MEDIA_ID,
    processingRunId: RUN_ID,
    jobId: JOB_ID,
    workerId: WORKER_ID,
    leaseId: LEASE_ID,
    attempt: 2,
    profileChecksumSha256: profile.checksumSha256,
    sourceChecksumSha256: source.checksumSha256,
    rawObject: {
      bucket: BUCKET,
      objectKey: vehiclePhotoRawObjectKey({
        workspaceId: WORKSPACE_ID,
        mediaId: MEDIA_ID,
        checksumSha256: source.checksumSha256,
        mimeType: source.detectedMimeType,
      }),
      byteSize: source.sizeBytes,
      mimeType: source.detectedMimeType,
      checksumSha256: source.checksumSha256,
    },
    processorReceipt,
    derivativeObjects: processorReceipt.outputs
      .map((output) => ({
        bucket: BUCKET,
        objectKey: vehiclePhotoDerivativeObjectKey({
          workspaceId: WORKSPACE_ID,
          mediaId: MEDIA_ID,
          processingRunId: RUN_ID,
          variant: output.variant,
          checksumSha256: output.checksumSha256,
        }),
        byteSize: output.byteSize,
        mimeType: output.mimeType,
        checksumSha256: output.checksumSha256,
      }))
      .reverse(),
  };
  return { source, profile, processorReceipt, context, completionReceipt };
}

describe("M2-MEDIA processor safety receipts", () => {
  it("VYN-MEDIA-001 / T-MED-002 accepts proof of orientation and metadata policy", async () => {
    const { source, profile, processorReceipt } = await fixture();
    const validated = validateVehiclePhotoProcessorReceipt({
      receipt: {
        ...processorReceipt,
        outputs: [...processorReceipt.outputs].reverse(),
      },
      source,
      profile,
    });

    expect(validated.outputs.map(({ variant }) => variant)).toEqual([
      "normalized_master",
      "website_1080",
      "thumbnail_640",
      "thumbnail_320",
    ]);
    expect(
      validated.outputs.every(
        (output) =>
          output.orientationPolicyApplied &&
          output.normalizedOrientation === 1 &&
          !output.metadata.exifPresent &&
          !output.metadata.gpsPresent &&
          !output.metadata.iptcPresent &&
          !output.metadata.xmpPresent,
      ),
    ).toBe(true);
    expect(Object.isFrozen(validated.outputs[0]?.metadata)).toBe(true);
  });

  it("VYN-MEDIA-001 / T-MED-002 rejects GPS or metadata leakage", async () => {
    const { source, profile, processorReceipt } = await fixture();
    const receipt = {
      ...processorReceipt,
      outputs: processorReceipt.outputs.map((output, index) =>
        index === 0
          ? {
              ...output,
              metadata: { ...output.metadata, gpsPresent: true },
            }
          : output,
      ),
    };

    expectCode(
      () => validateVehiclePhotoProcessorReceipt({ receipt, source, profile }),
      "unsafe_processor_metadata",
    );
  });

  it("VYN-MEDIA-001 / T-MED-002 rejects missing, upscaled, or wrong-size derivatives", async () => {
    const { source, profile, processorReceipt } = await fixture();
    expectCode(
      () =>
        validateVehiclePhotoProcessorReceipt({
          receipt: {
            ...processorReceipt,
            outputs: processorReceipt.outputs.slice(1),
          },
          source,
          profile,
        }),
      "invalid_processor_receipt",
    );
    expectCode(
      () =>
        validateVehiclePhotoProcessorReceipt({
          receipt: {
            ...processorReceipt,
            outputs: processorReceipt.outputs.map((output, index) =>
              index === 0
                ? { ...output, width: output.width + 1, upscaled: true }
                : output,
            ),
          },
          source,
          profile,
        }),
      "invalid_processor_receipt",
    );
  });
});

describe("M2-MEDIA completion receipt and lease identity", () => {
  it("VYN-MEDIA-001 / T-MED-004 validates and canonically orders stored outputs", async () => {
    const { context, completionReceipt } = await fixture();
    const result = validateVehiclePhotoCompletionReceipt({
      receipt: completionReceipt,
      context,
    });

    expect(result.workerId).toBe(WORKER_ID);
    expect(result.leaseId).toBe(LEASE_ID);
    expect(result.derivativeObjects.map(({ objectKey }) => objectKey)).toEqual(
      result.processorReceipt.outputs.map((output) =>
        vehiclePhotoDerivativeObjectKey({
          workspaceId: WORKSPACE_ID,
          mediaId: MEDIA_ID,
          processingRunId: RUN_ID,
          variant: output.variant,
          checksumSha256: output.checksumSha256,
        }),
      ),
    );
    expect(Object.isFrozen(result)).toBe(true);
  });

  it("VYN-MEDIA-001 / T-MED-004 rejects stale worker, lease, and attempt receipts", async () => {
    const { context, completionReceipt } = await fixture();
    for (const receipt of [
      { ...completionReceipt, workerId: "local-worker-2" },
      { ...completionReceipt, workerId: "unsafe worker" },
      { ...completionReceipt, leaseId: JOB_ID },
      { ...completionReceipt, attempt: 1 },
    ]) {
      expectCode(
        () => validateVehiclePhotoCompletionReceipt({ receipt, context }),
        "lease_identity_mismatch",
      );
    }
  });

  it("VYN-MEDIA-001 / T-MED-004 rejects missing or conflicting object receipts", async () => {
    const { context, completionReceipt } = await fixture();
    expectCode(
      () =>
        validateVehiclePhotoCompletionReceipt({
          receipt: {
            ...completionReceipt,
            derivativeObjects: completionReceipt.derivativeObjects.slice(1),
          },
          context,
        }),
      "invalid_completion_receipt",
    );
    expectCode(
      () =>
        validateVehiclePhotoCompletionReceipt({
          receipt: {
            ...completionReceipt,
            rawObject: {
              ...completionReceipt.rawObject,
              objectKey: completionReceipt.rawObject.objectKey.replace(
                WORKSPACE_ID,
                JOB_ID,
              ),
            },
          },
          context,
        }),
      "invalid_completion_receipt",
    );
  });

  it("VYN-MEDIA-001 / T-MED-004 rejects unexpected receipt fields", async () => {
    const { context, completionReceipt } = await fixture();
    expectCode(
      () =>
        validateVehiclePhotoCompletionReceipt({
          receipt: { ...completionReceipt, providerToken: "must-not-pass" },
          context,
        }),
      "invalid_completion_receipt",
    );
  });
});
