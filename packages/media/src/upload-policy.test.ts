import { describe, expect, it } from "vitest";

import { MediaPolicyError } from "./errors";
import {
  VEHICLE_PHOTO_MAX_BYTES,
  VEHICLE_PHOTO_MAX_PIXELS,
  detectVehiclePhotoMimeType,
  normalizeVehiclePhotoUploadIntent,
  validateVehiclePhotoSource,
  type VehiclePhotoMimeType,
} from "./upload-policy";

const CHECKSUM = "a".repeat(64);
const JPEG_SIGNATURE = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);

function ascii(value: string): number[] {
  return [...value].map((character) => character.charCodeAt(0));
}

function isoBaseMediaSignature(brand: string): Uint8Array {
  return new Uint8Array([
    0,
    0,
    0,
    20,
    ...ascii("ftyp"),
    ...ascii(brand),
    0,
    0,
    0,
    0,
    ...ascii(brand),
  ]);
}

const signatures: ReadonlyArray<readonly [VehiclePhotoMimeType, Uint8Array]> = [
  ["image/jpeg", JPEG_SIGNATURE],
  [
    "image/png",
    new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  ],
  [
    "image/webp",
    new Uint8Array([...ascii("RIFF"), 0, 0, 0, 0, ...ascii("WEBP")]),
  ],
  ["image/heic", isoBaseMediaSignature("heic")],
  ["image/heif", isoBaseMediaSignature("mif1")],
];

function expectCode(operation: () => unknown, code: string): void {
  expect(operation).toThrowError(MediaPolicyError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

function validIntent(mimeType: VehiclePhotoMimeType = "image/jpeg") {
  return normalizeVehiclePhotoUploadIntent({
    filename: "inventory-photo.jpg",
    declaredMimeType: mimeType,
    sizeBytes: 1_000,
    checksumSha256: CHECKSUM,
  });
}

describe("M2-MEDIA upload intent and source policy", () => {
  it("VYN-MEDIA-001 / T-MED-003 accepts only the five allowed signatures", () => {
    for (const [mimeType, signature] of signatures) {
      expect(detectVehiclePhotoMimeType(signature)).toBe(mimeType);
    }

    expect(
      detectVehiclePhotoMimeType(isoBaseMediaSignature("avif")),
    ).toBeNull();
    expect(
      detectVehiclePhotoMimeType(new Uint8Array([0x25, 0x50, 0x44])),
    ).toBeNull();
  });

  it("VYN-MEDIA-001 / T-MED-003 normalizes declared type and enforces the byte ceiling", () => {
    const intent = normalizeVehiclePhotoUploadIntent({
      filename: "  inventory image.PNG  ",
      declaredMimeType: " IMAGE/PNG ",
      sizeBytes: VEHICLE_PHOTO_MAX_BYTES,
    });

    expect(intent).toEqual({
      filename: "inventory image.PNG",
      declaredMimeType: "image/png",
      sizeBytes: VEHICLE_PHOTO_MAX_BYTES,
      checksumSha256: null,
      maximumPixels: VEHICLE_PHOTO_MAX_PIXELS,
    });
    expect(Object.isFrozen(intent)).toBe(true);

    expectCode(
      () =>
        normalizeVehiclePhotoUploadIntent({
          filename: "photo.gif",
          declaredMimeType: "image/gif",
          sizeBytes: 10,
        }),
      "unsupported_declared_mime_type",
    );
    expectCode(
      () =>
        normalizeVehiclePhotoUploadIntent({
          filename: "photo.jpg",
          declaredMimeType: "image/jpeg",
          sizeBytes: VEHICLE_PHOTO_MAX_BYTES + 1,
        }),
      "invalid_size_bytes",
    );
  });

  it("VYN-MEDIA-001 / T-MED-003 rejects unsafe filenames and malformed checksums", () => {
    for (const filename of ["", "bad\u0000name.jpg", "x".repeat(256)]) {
      expectCode(
        () =>
          normalizeVehiclePhotoUploadIntent({
            filename,
            declaredMimeType: "image/jpeg",
            sizeBytes: 10,
          }),
        "invalid_filename",
      );
    }
    expectCode(
      () =>
        normalizeVehiclePhotoUploadIntent({
          filename: "photo.jpg",
          declaredMimeType: "image/jpeg",
          sizeBytes: 10,
          checksumSha256: "not-a-checksum",
        }),
      "invalid_checksum",
    );
  });

  it("VYN-MEDIA-001 / T-MED-003 compares observed signature, size, and checksum", () => {
    const source = validateVehiclePhotoSource({
      intent: validIntent(),
      signatureBytes: JPEG_SIGNATURE,
      observedSizeBytes: 1_000,
      width: 8_000,
      height: 7_500,
      checksumSha256: CHECKSUM.toUpperCase(),
      exifOrientation: 6,
    });

    expect(source).toMatchObject({
      detectedMimeType: "image/jpeg",
      pixelCount: VEHICLE_PHOTO_MAX_PIXELS,
      checksumSha256: CHECKSUM,
      exifOrientation: 6,
    });
    expect(Object.isFrozen(source)).toBe(true);

    expectCode(
      () =>
        validateVehiclePhotoSource({
          intent: validIntent("image/png"),
          signatureBytes: JPEG_SIGNATURE,
          observedSizeBytes: 1_000,
          width: 1,
          height: 1,
          checksumSha256: CHECKSUM,
          exifOrientation: null,
        }),
      "declared_mime_type_mismatch",
    );
    expectCode(
      () =>
        validateVehiclePhotoSource({
          intent: validIntent(),
          signatureBytes: JPEG_SIGNATURE,
          observedSizeBytes: 999,
          width: 1,
          height: 1,
          checksumSha256: CHECKSUM,
          exifOrientation: null,
        }),
      "source_size_mismatch",
    );
  });

  it("VYN-MEDIA-001 / T-MED-003 rejects decompression bombs and invalid orientation", () => {
    expectCode(
      () =>
        validateVehiclePhotoSource({
          intent: validIntent(),
          signatureBytes: JPEG_SIGNATURE,
          observedSizeBytes: 1_000,
          width: 10_000,
          height: 6_001,
          checksumSha256: CHECKSUM,
          exifOrientation: 1,
        }),
      "pixel_limit_exceeded",
    );
    expectCode(
      () =>
        validateVehiclePhotoSource({
          intent: validIntent(),
          signatureBytes: JPEG_SIGNATURE,
          observedSizeBytes: 1_000,
          width: 10,
          height: 10,
          checksumSha256: CHECKSUM,
          exifOrientation: 9,
        }),
      "invalid_image_dimensions",
    );
  });
});
