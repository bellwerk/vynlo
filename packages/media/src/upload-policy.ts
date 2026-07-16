import { MediaPolicyError } from "./errors";
import {
  deepFreeze,
  requirePositiveSafeInteger,
  requireSha256,
} from "./validation";

export const VEHICLE_PHOTO_MAX_BYTES = 20_000_000;
export const VEHICLE_PHOTO_MAX_PIXELS = 60_000_000;

export const VEHICLE_PHOTO_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
] as const;

export type VehiclePhotoMimeType = (typeof VEHICLE_PHOTO_MIME_TYPES)[number];

const mimeTypes = new Set<string>(VEHICLE_PHOTO_MIME_TYPES);
const jpegSignature = [0xff, 0xd8, 0xff] as const;
const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] as const;
const heicBrands = new Set(["heic", "heix", "hevc", "hevx"]);
const heifBrands = new Set(["heif", "mif1", "msf1"]);

export interface VehiclePhotoUploadIntentInput {
  readonly filename: string;
  readonly declaredMimeType: string;
  readonly sizeBytes: number;
  readonly checksumSha256?: string | null;
}

export interface VehiclePhotoUploadIntent {
  readonly filename: string;
  readonly declaredMimeType: VehiclePhotoMimeType;
  readonly sizeBytes: number;
  readonly checksumSha256: string | null;
  readonly maximumPixels: typeof VEHICLE_PHOTO_MAX_PIXELS;
}

export interface VehiclePhotoSourceValidationInput {
  readonly intent: VehiclePhotoUploadIntent;
  readonly signatureBytes: Uint8Array;
  readonly observedSizeBytes: number;
  readonly width: number;
  readonly height: number;
  readonly checksumSha256: string;
  readonly exifOrientation: number | null;
}

export interface ValidatedVehiclePhotoSource {
  readonly detectedMimeType: VehiclePhotoMimeType;
  readonly sizeBytes: number;
  readonly width: number;
  readonly height: number;
  readonly pixelCount: number;
  readonly checksumSha256: string;
  readonly exifOrientation: number | null;
}

function matches(bytes: Uint8Array, expected: readonly number[]): boolean {
  return expected.every((byte, index) => bytes[index] === byte);
}

function ascii(bytes: Uint8Array, start: number, length: number): string {
  return String.fromCharCode(...bytes.slice(start, start + length));
}

function readUnsigned32BigEndian(bytes: Uint8Array): number {
  return (
    ((bytes[0] ?? 0) * 0x1000000 +
      (bytes[1] ?? 0) * 0x10000 +
      (bytes[2] ?? 0) * 0x100 +
      (bytes[3] ?? 0)) >>>
    0
  );
}

function detectHeif(bytes: Uint8Array): VehiclePhotoMimeType | null {
  if (bytes.length < 16 || ascii(bytes, 4, 4) !== "ftyp") {
    return null;
  }

  const declaredBoxSize = readUnsigned32BigEndian(bytes.slice(0, 4));
  const availableBoxSize = Math.min(
    bytes.length,
    declaredBoxSize === 0 ? bytes.length : declaredBoxSize,
  );
  if (availableBoxSize < 16) {
    return null;
  }

  const brands = [ascii(bytes, 8, 4)];
  for (let offset = 16; offset + 4 <= availableBoxSize; offset += 4) {
    brands.push(ascii(bytes, offset, 4));
  }

  if (brands.some((brand) => heicBrands.has(brand))) {
    return "image/heic";
  }
  if (brands.some((brand) => heifBrands.has(brand))) {
    return "image/heif";
  }
  return null;
}

export function detectVehiclePhotoMimeType(
  signatureBytes: Uint8Array,
): VehiclePhotoMimeType | null {
  if (signatureBytes.length >= 3 && matches(signatureBytes, jpegSignature)) {
    return "image/jpeg";
  }
  if (signatureBytes.length >= 8 && matches(signatureBytes, pngSignature)) {
    return "image/png";
  }
  if (
    signatureBytes.length >= 12 &&
    ascii(signatureBytes, 0, 4) === "RIFF" &&
    ascii(signatureBytes, 8, 4) === "WEBP"
  ) {
    return "image/webp";
  }
  return detectHeif(signatureBytes);
}

export function normalizeVehiclePhotoUploadIntent(
  input: VehiclePhotoUploadIntentInput,
): VehiclePhotoUploadIntent {
  const filename = input.filename.trim();
  if (
    filename.length < 1 ||
    filename.length > 255 ||
    /[\u0000-\u001f\u007f]/u.test(filename)
  ) {
    throw new MediaPolicyError("invalid_filename");
  }

  const normalizedMimeType = input.declaredMimeType.trim().toLowerCase();
  if (!mimeTypes.has(normalizedMimeType)) {
    throw new MediaPolicyError("unsupported_declared_mime_type");
  }

  const sizeBytes = requirePositiveSafeInteger(
    input.sizeBytes,
    "invalid_size_bytes",
  );
  if (sizeBytes > VEHICLE_PHOTO_MAX_BYTES) {
    throw new MediaPolicyError("invalid_size_bytes");
  }

  const checksumSha256 =
    input.checksumSha256 === undefined || input.checksumSha256 === null
      ? null
      : requireSha256(input.checksumSha256, "invalid_checksum");

  return deepFreeze({
    filename,
    declaredMimeType: normalizedMimeType as VehiclePhotoMimeType,
    sizeBytes,
    checksumSha256,
    maximumPixels: VEHICLE_PHOTO_MAX_PIXELS,
  });
}

export function validateVehiclePhotoSource(
  input: VehiclePhotoSourceValidationInput,
): ValidatedVehiclePhotoSource {
  const observedSizeBytes = requirePositiveSafeInteger(
    input.observedSizeBytes,
    "invalid_size_bytes",
  );
  if (
    observedSizeBytes > VEHICLE_PHOTO_MAX_BYTES ||
    observedSizeBytes !== input.intent.sizeBytes
  ) {
    throw new MediaPolicyError("source_size_mismatch");
  }

  const detectedMimeType = detectVehiclePhotoMimeType(input.signatureBytes);
  if (detectedMimeType === null) {
    throw new MediaPolicyError("unsupported_file_signature");
  }
  if (detectedMimeType !== input.intent.declaredMimeType) {
    throw new MediaPolicyError("declared_mime_type_mismatch");
  }

  const width = requirePositiveSafeInteger(
    input.width,
    "invalid_image_dimensions",
  );
  const height = requirePositiveSafeInteger(
    input.height,
    "invalid_image_dimensions",
  );
  const pixelCount = width * height;
  if (!Number.isSafeInteger(pixelCount)) {
    throw new MediaPolicyError("invalid_image_dimensions");
  }
  if (pixelCount > VEHICLE_PHOTO_MAX_PIXELS) {
    throw new MediaPolicyError("pixel_limit_exceeded");
  }

  const checksumSha256 = requireSha256(
    input.checksumSha256,
    "invalid_checksum",
  );
  if (
    input.intent.checksumSha256 !== null &&
    input.intent.checksumSha256 !== checksumSha256
  ) {
    throw new MediaPolicyError("invalid_checksum");
  }

  if (
    input.exifOrientation !== null &&
    (!Number.isInteger(input.exifOrientation) ||
      input.exifOrientation < 1 ||
      input.exifOrientation > 8)
  ) {
    throw new MediaPolicyError("invalid_image_dimensions");
  }

  return deepFreeze({
    detectedMimeType,
    sizeBytes: observedSizeBytes,
    width,
    height,
    pixelCount,
    checksumSha256,
    exifOrientation: input.exifOrientation,
  });
}
