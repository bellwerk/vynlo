import { describe, expect, it } from "vitest";

import {
  createVehiclePhotoProcessingProfileSnapshot,
  parseVehiclePhotoProcessingProfileSnapshot,
  planVehiclePhotoDerivatives,
  serializeVehiclePhotoProcessingProfile,
  verifyVehiclePhotoProcessingProfileSnapshot,
} from "./processing-profile";

describe("M2-MEDIA immutable vehicle-photo processing profile", () => {
  it("VYN-MEDIA-001 / T-MED-001 produces a deterministic immutable snapshot", async () => {
    const identity = { profileKey: "vehicle-photo.standard", version: 1 };
    const first = await createVehiclePhotoProcessingProfileSnapshot(identity);
    const second = await createVehiclePhotoProcessingProfileSnapshot(identity);

    expect(first).toEqual(second);
    expect(first.checksumSha256).toMatch(/^[a-f0-9]{64}$/u);
    expect(first.transformationPolicy).toEqual({
      orientation: "exif_auto",
      outputColorSpace: "srgb",
      metadata: {
        exif: "strip",
        gps: "strip",
        iptc: "strip",
        xmp: "strip",
      },
    });
    expect(Object.isFrozen(first)).toBe(true);
    expect(Object.isFrozen(first.derivatives)).toBe(true);
    expect(Object.isFrozen(first.transformationPolicy.metadata)).toBe(true);
    await expect(
      verifyVehiclePhotoProcessingProfileSnapshot(first),
    ).resolves.toBe(true);
  });

  it("VYN-MEDIA-001 / T-MED-001 binds checksum to profile identity and version", async () => {
    const first = await createVehiclePhotoProcessingProfileSnapshot({
      profileKey: "vehicle-photo.standard",
      version: 1,
    });
    const next = await createVehiclePhotoProcessingProfileSnapshot({
      profileKey: "vehicle-photo.standard",
      version: 2,
    });

    expect(first.checksumSha256).not.toBe(next.checksumSha256);
    expect(serializeVehiclePhotoProcessingProfile(first)).not.toContain(
      "checksumSha256",
    );
    await expect(
      verifyVehiclePhotoProcessingProfileSnapshot({
        ...first,
        checksumSha256: next.checksumSha256,
      }),
    ).resolves.toBe(false);
  });

  it("VYN-MEDIA-001 / T-MED-001 rejects tampered policy and derivative bodies", async () => {
    const profile = await createVehiclePhotoProcessingProfileSnapshot({
      profileKey: "vehicle-photo.standard",
      version: 1,
    });
    const tamperedPolicy = {
      ...profile,
      sourcePolicy: { ...profile.sourcePolicy, maximumBytes: 50_000_000 },
    };
    const tamperedDerivatives = {
      ...profile,
      derivatives: profile.derivatives.map((derivative, index) =>
        index === 1
          ? {
              ...derivative,
              resize: { ...derivative.resize, maximumWidthPixels: 2_000 },
            }
          : derivative,
      ),
    };

    await expect(
      verifyVehiclePhotoProcessingProfileSnapshot(tamperedPolicy),
    ).resolves.toBe(false);
    await expect(
      verifyVehiclePhotoProcessingProfileSnapshot(tamperedDerivatives),
    ).resolves.toBe(false);
    await expect(
      parseVehiclePhotoProcessingProfileSnapshot({
        ...profile,
        arbitraryNetworkPolicy: "allowed",
      }),
    ).rejects.toMatchObject({ code: "invalid_processing_profile" });
  });

  it("VYN-MEDIA-001 / T-MED-001 emits the exact landscape derivative plan", async () => {
    const profile = await createVehiclePhotoProcessingProfileSnapshot({
      profileKey: "vehicle-photo.standard",
      version: 1,
    });

    expect(
      planVehiclePhotoDerivatives({
        sourceWidth: 4_000,
        sourceHeight: 3_000,
        profile,
      }),
    ).toEqual([
      {
        variant: "normalized_master",
        role: "normalized_master",
        mimeType: "image/webp",
        width: 2_560,
        height: 1_920,
        withoutEnlargement: true,
      },
      {
        variant: "website_1080",
        role: "website",
        mimeType: "image/webp",
        width: 1_080,
        height: 810,
        withoutEnlargement: true,
      },
      {
        variant: "thumbnail_640",
        role: "thumbnail",
        mimeType: "image/webp",
        width: 640,
        height: 480,
        withoutEnlargement: true,
      },
      {
        variant: "thumbnail_320",
        role: "thumbnail",
        mimeType: "image/webp",
        width: 320,
        height: 240,
        withoutEnlargement: true,
      },
    ]);
  });

  it("VYN-MEDIA-001 / T-MED-001 preserves portrait ratio and never upscales", async () => {
    const profile = await createVehiclePhotoProcessingProfileSnapshot({
      profileKey: "vehicle-photo.standard",
      version: 1,
    });
    const portrait = planVehiclePhotoDerivatives({
      sourceWidth: 3_000,
      sourceHeight: 4_000,
      profile,
    });
    const small = planVehiclePhotoDerivatives({
      sourceWidth: 200,
      sourceHeight: 150,
      profile,
    });

    expect(portrait.map(({ width, height }) => [width, height])).toEqual([
      [1_920, 2_560],
      [1_080, 1_440],
      [640, 853],
      [320, 427],
    ]);
    expect(
      small.every(({ width, height }) => width === 200 && height === 150),
    ).toBe(true);
  });
});
