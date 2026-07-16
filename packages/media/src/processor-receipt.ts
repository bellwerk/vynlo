import { MediaPolicyError } from "./errors";
import {
  planVehiclePhotoDerivatives,
  type VehiclePhotoDerivativeVariant,
  type VehiclePhotoFileRole,
  type VehiclePhotoProcessingProfileSnapshot,
} from "./processing-profile";
import type { ValidatedVehiclePhotoSource } from "./upload-policy";
import {
  deepFreeze,
  hasExactKeys,
  isRecord,
  requirePositiveSafeInteger,
  requireSha256,
} from "./validation";

export interface VehiclePhotoDerivativeReceipt {
  readonly variant: VehiclePhotoDerivativeVariant;
  readonly role: VehiclePhotoFileRole;
  readonly mimeType: "image/webp";
  readonly width: number;
  readonly height: number;
  readonly byteSize: number;
  readonly checksumSha256: string;
  readonly orientationPolicyApplied: true;
  readonly normalizedOrientation: 1;
  readonly outputColorSpace: "srgb";
  readonly upscaled: false;
  readonly metadata: Readonly<{
    exifPresent: false;
    gpsPresent: false;
    iptcPresent: false;
    xmpPresent: false;
  }>;
}

export interface VehiclePhotoProcessorReceipt {
  readonly processor: Readonly<{
    name: string;
    version: string;
  }>;
  readonly profileChecksumSha256: string;
  readonly sourceChecksumSha256: string;
  readonly outputs: readonly VehiclePhotoDerivativeReceipt[];
}

const processorIdentifierPattern = /^[A-Za-z0-9][A-Za-z0-9_.+-]{0,119}$/u;

function requireProcessorIdentifier(value: unknown): string {
  if (typeof value !== "string" || !processorIdentifierPattern.test(value)) {
    throw new MediaPolicyError("invalid_processor_receipt");
  }
  return value;
}

export function validateVehiclePhotoProcessorReceipt(input: {
  readonly receipt: unknown;
  readonly source: ValidatedVehiclePhotoSource;
  readonly profile: VehiclePhotoProcessingProfileSnapshot;
}): VehiclePhotoProcessorReceipt {
  if (
    !isRecord(input.receipt) ||
    !hasExactKeys(input.receipt, [
      "processor",
      "profileChecksumSha256",
      "sourceChecksumSha256",
      "outputs",
    ]) ||
    !isRecord(input.receipt.processor) ||
    !hasExactKeys(input.receipt.processor, ["name", "version"]) ||
    !Array.isArray(input.receipt.outputs)
  ) {
    throw new MediaPolicyError("invalid_processor_receipt");
  }

  const profileChecksumSha256 = requireSha256(
    input.receipt.profileChecksumSha256,
    "invalid_processor_receipt",
  );
  const sourceChecksumSha256 = requireSha256(
    input.receipt.sourceChecksumSha256,
    "invalid_processor_receipt",
  );
  if (
    profileChecksumSha256 !== input.profile.checksumSha256 ||
    sourceChecksumSha256 !== input.source.checksumSha256
  ) {
    throw new MediaPolicyError("invalid_processor_receipt");
  }

  const plan = planVehiclePhotoDerivatives({
    sourceWidth: input.source.width,
    sourceHeight: input.source.height,
    profile: input.profile,
  });
  if (input.receipt.outputs.length !== plan.length) {
    throw new MediaPolicyError("invalid_processor_receipt");
  }

  const receiptsByVariant = new Map<string, Record<string, unknown>>();
  for (const output of input.receipt.outputs) {
    if (
      !isRecord(output) ||
      !hasExactKeys(output, [
        "variant",
        "role",
        "mimeType",
        "width",
        "height",
        "byteSize",
        "checksumSha256",
        "orientationPolicyApplied",
        "normalizedOrientation",
        "outputColorSpace",
        "upscaled",
        "metadata",
      ]) ||
      typeof output.variant !== "string" ||
      receiptsByVariant.has(output.variant)
    ) {
      throw new MediaPolicyError("invalid_processor_receipt");
    }
    receiptsByVariant.set(output.variant, output);
  }

  const normalizedOutputs = plan.map((expected) => {
    const output = receiptsByVariant.get(expected.variant);
    if (
      output === undefined ||
      output.variant !== expected.variant ||
      output.role !== expected.role ||
      output.mimeType !== expected.mimeType ||
      output.width !== expected.width ||
      output.height !== expected.height ||
      output.orientationPolicyApplied !== true ||
      output.normalizedOrientation !== 1 ||
      output.outputColorSpace !== "srgb" ||
      output.upscaled !== false
    ) {
      throw new MediaPolicyError("invalid_processor_receipt");
    }
    if (
      !isRecord(output.metadata) ||
      !hasExactKeys(output.metadata, [
        "exifPresent",
        "gpsPresent",
        "iptcPresent",
        "xmpPresent",
      ]) ||
      output.metadata.exifPresent !== false ||
      output.metadata.gpsPresent !== false ||
      output.metadata.iptcPresent !== false ||
      output.metadata.xmpPresent !== false
    ) {
      throw new MediaPolicyError("unsafe_processor_metadata");
    }

    return {
      variant: expected.variant,
      role: expected.role,
      mimeType: expected.mimeType,
      width: expected.width,
      height: expected.height,
      byteSize: requirePositiveSafeInteger(
        output.byteSize,
        "invalid_processor_receipt",
      ),
      checksumSha256: requireSha256(
        output.checksumSha256,
        "invalid_processor_receipt",
      ),
      orientationPolicyApplied: true as const,
      normalizedOrientation: 1 as const,
      outputColorSpace: "srgb" as const,
      upscaled: false as const,
      metadata: {
        exifPresent: false as const,
        gpsPresent: false as const,
        iptcPresent: false as const,
        xmpPresent: false as const,
      },
    };
  });

  return deepFreeze({
    processor: {
      name: requireProcessorIdentifier(input.receipt.processor.name),
      version: requireProcessorIdentifier(input.receipt.processor.version),
    },
    profileChecksumSha256,
    sourceChecksumSha256,
    outputs: normalizedOutputs,
  });
}
