import { describe, expect, it } from "vitest";

import {
  clearVehiclePhotoCommandKey,
  isVehiclePhotoUploadIntentExpired,
  MAX_VEHICLE_PHOTO_BYTES,
  parseVehiclePhotoUploadIntent,
  parseVehiclePhotoVerificationReceipt,
  parseVehiclePhotoVerificationStatus,
  sha256Hex,
  validateVehiclePhotoFile,
  vehiclePhotoCommandKey,
  vehiclePhotoProjectedJobStatus,
  vehiclePhotoReceiptStatus,
  vehiclePhotoStatusMessageKey,
  vehiclePhotoStatusPollDelay,
  vehiclePhotoStatusShouldPoll,
  vehiclePhotoStorageUrl,
} from "./vehicle-photo-upload";

const mediaId = "15000000-0000-4000-8000-000000000001";
const sessionId = "15000000-0000-4000-8000-000000000002";

describe("T-MED-003 / T-MED-004 vehicle photo upload browser contract", () => {
  it("accepts the five image MIME policies and infers an empty HEIC type", () => {
    for (const type of [
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/heic",
      "image/heif",
    ]) {
      expect(
        validateVehiclePhotoFile({ name: "photo.bin", size: 1, type }),
      ).toMatchObject({ mimeType: type, valid: true });
    }
    expect(
      validateVehiclePhotoFile({ name: "vehicle.HEIC", size: 1, type: "" }),
    ).toEqual({ mimeType: "image/heic", valid: true });
  });

  it("rejects empty, oversized, and mismatched files", () => {
    expect(
      validateVehiclePhotoFile({
        name: "photo.jpg",
        size: 0,
        type: "image/jpeg",
      }),
    ).toEqual({ code: "file_empty", valid: false });
    expect(
      validateVehiclePhotoFile({
        name: "photo.jpg",
        size: MAX_VEHICLE_PHOTO_BYTES + 1,
        type: "image/jpeg",
      }),
    ).toEqual({ code: "file_too_large", valid: false });
    expect(
      validateVehiclePhotoFile({
        name: "photo.jpg",
        size: 1,
        type: "text/plain",
      }),
    ).toEqual({ code: "unsupported_file_type", valid: false });
  });

  it("computes a lower-case browser SHA-256 digest", async () => {
    await expect(sha256Hex(new Blob(["vynlo"]))).resolves.toBe(
      "d28b7da36626cba66ee087d8b41da1243c137e342aaacafa9232b338dbf00922",
    );
  });

  it("parses exact upload and verification receipts", () => {
    expect(
      parseVehiclePhotoUploadIntent({
        data: {
          mediaId,
          upload: {
            bucket: "media-private",
            expiresAt: "2026-07-16T18:00:00.000Z",
            objectKey: "workspaces/one/quarantine/photo.jpg",
            requiresAuthenticatedSession: true,
          },
          uploadSessionId: sessionId,
        },
      }),
    ).toMatchObject({ mediaId, uploadSessionId: sessionId });
    expect(
      parseVehiclePhotoVerificationReceipt({
        data: {
          jobId: "15000000-0000-4000-8000-000000000003",
          jobStatus: "queued",
          mediaId,
          uploadSessionId: sessionId,
        },
      }),
    ).toMatchObject({ jobStatus: "queued", mediaId });
  });

  it("parses bounded status while keeping failure codes out of the UI model", () => {
    const status = parseVehiclePhotoVerificationStatus({
      data: {
        completedAt: null,
        failure: {
          classification: "transient",
          code: "media.storage_unavailable",
        },
        job: {
          attemptCount: 6,
          id: "15000000-0000-4000-8000-000000000003",
          maximumAttempts: 6,
          retryAt: null,
        },
        mediaId,
        retryable: true,
        status: "dead_letter",
        uploadSessionId: sessionId,
      },
    });
    expect(status).toMatchObject({
      job: { attemptCount: 6, maximumAttempts: 6 },
      retryable: true,
      status: "dead_letter",
    });
    expect(status).not.toHaveProperty("failure");
    expect(vehiclePhotoStatusMessageKey(status.status)).toBe(
      "photoStatusDeadLetter",
    );
    expect(vehiclePhotoStatusShouldPoll(status.status)).toBe(false);
    expect(vehiclePhotoStatusShouldPoll("retry_wait")).toBe(true);
    expect(vehiclePhotoReceiptStatus("succeeded")).toBe("completed");
    expect(vehiclePhotoProjectedJobStatus("completed")).toBe("succeeded");
    expect(vehiclePhotoProjectedJobStatus("rejected")).toBe("cancelled");
    expect([0, 1, 2, 3, 4, 9].map(vehiclePhotoStatusPollDelay)).toEqual([
      500, 1_000, 2_000, 4_000, 8_000, 8_000,
    ]);
  });

  it("rejects leaked coordinates and inconsistent retry state", () => {
    const base = {
      completedAt: null,
      failure: {
        classification: "transient",
        code: "media.storage_unavailable",
      },
      job: {
        attemptCount: 6,
        id: "15000000-0000-4000-8000-000000000003",
        maximumAttempts: 6,
        retryAt: null,
      },
      mediaId,
      retryable: true,
      status: "dead_letter",
      uploadSessionId: sessionId,
    } as const;
    expect(() =>
      parseVehiclePhotoVerificationStatus({
        data: { ...base, retryable: false },
      }),
    ).toThrow("invalid_media_verification_status_response");
    expect(() =>
      parseVehiclePhotoVerificationStatus({
        data: { ...base, storageObjectKey: "private/leak" },
      }),
    ).toThrow("invalid_media_verification_status_response");
  });

  it("expires intents at the exact deadline and rotates their command key", () => {
    const intent = parseVehiclePhotoUploadIntent({
      data: {
        mediaId,
        upload: {
          bucket: "media-private",
          expiresAt: "2026-07-16T18:00:00.000Z",
          objectKey: "workspaces/one/quarantine/photo.jpg",
          requiresAuthenticatedSession: true,
        },
        uploadSessionId: sessionId,
      },
    });
    expect(
      isVehiclePhotoUploadIntentExpired(
        intent,
        Date.parse("2026-07-16T17:59:59.999Z"),
      ),
    ).toBe(false);
    expect(
      isVehiclePhotoUploadIntentExpired(
        intent,
        Date.parse("2026-07-16T18:00:00.000Z"),
      ),
    ).toBe(true);

    const cache = new Map<string, string>();
    const payload = { checksumSha256: "a".repeat(64), filename: "photo.jpg" };
    expect(
      vehiclePhotoCommandKey(
        cache,
        "photo-intent:unit",
        payload,
        () => "first-key",
      ),
    ).toBe("first-key");
    expect(
      vehiclePhotoCommandKey(
        cache,
        "photo-intent:unit",
        payload,
        () => "unused-key",
      ),
    ).toBe("first-key");
    clearVehiclePhotoCommandKey(cache, "photo-intent:unit", payload);
    expect(
      vehiclePhotoCommandKey(
        cache,
        "photo-intent:unit",
        payload,
        () => "fresh-key",
      ),
    ).toBe("fresh-key");
  });

  it("encodes every storage key segment and rejects path traversal", () => {
    const intent = parseVehiclePhotoUploadIntent({
      data: {
        mediaId,
        upload: {
          bucket: "media-private",
          expiresAt: "2026-07-16T18:00:00.000Z",
          objectKey: "workspaces/one/photo #1.jpg",
          requiresAuthenticatedSession: true,
        },
        uploadSessionId: sessionId,
      },
    });
    expect(vehiclePhotoStorageUrl("https://example.supabase.co/", intent)).toBe(
      "https://example.supabase.co/storage/v1/object/media-private/workspaces/one/photo%20%231.jpg",
    );
    expect(() =>
      vehiclePhotoStorageUrl("https://example.supabase.co", {
        ...intent,
        upload: { ...intent.upload, objectKey: "workspaces/../secret" },
      }),
    ).toThrow("invalid_media_upload_object_key");
  });
});
