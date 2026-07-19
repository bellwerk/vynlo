import {
  createVehiclePhotoProcessingProfileSnapshot,
  normalizeVehiclePhotoUploadIntent,
  planVehiclePhotoDerivatives,
  validateVehiclePhotoProcessorReceipt,
  validateVehiclePhotoSource,
} from "@vynlo/media";
import sharp from "sharp";
import { describe, expect, it } from "vitest";

import { mediaSha256Hex } from "./managed-media-storage";
import {
  assertSharpMediaRuntimeReady,
  inspectVehiclePhotoWithSharp,
  readSharpMediaReadiness,
  SharpVehiclePhotoProcessor,
} from "./sharp-vehicle-photo-processor";

const SOURCE_WIDTH = 1_200;
const SOURCE_HEIGHT = 800;
const ORIENTED_WIDTH = SOURCE_HEIGHT;
const ORIENTED_HEIGHT = SOURCE_WIDTH;

const sourceFormats = [
  {
    extension: "jpg",
    format: "jpeg",
    mimeType: "image/jpeg",
  },
  {
    extension: "png",
    format: "png",
    mimeType: "image/png",
  },
  {
    extension: "webp",
    format: "webp",
    mimeType: "image/webp",
  },
] as const;

type SourceFormat = (typeof sourceFormats)[number];

function asymmetricSourcePixels(): Buffer {
  const pixels = Buffer.alloc(SOURCE_WIDTH * SOURCE_HEIGHT * 3);
  const colours = {
    bottomLeft: [20, 40, 230],
    bottomRight: [230, 210, 20],
    topLeft: [230, 30, 20],
    topRight: [30, 220, 40],
  } as const;

  for (let y = 0; y < SOURCE_HEIGHT; y += 1) {
    for (let x = 0; x < SOURCE_WIDTH; x += 1) {
      const colour =
        y < SOURCE_HEIGHT / 2
          ? x < SOURCE_WIDTH / 2
            ? colours.topLeft
            : colours.topRight
          : x < SOURCE_WIDTH / 2
            ? colours.bottomLeft
            : colours.bottomRight;
      const offset = (y * SOURCE_WIDTH + x) * 3;
      pixels[offset] = colour[0];
      pixels[offset + 1] = colour[1];
      pixels[offset + 2] = colour[2];
    }
  }

  return pixels;
}

async function orientedSource(format: SourceFormat) {
  let pipeline = sharp(asymmetricSourcePixels(), {
    raw: { channels: 3, height: SOURCE_HEIGHT, width: SOURCE_WIDTH },
  })
    .withMetadata({ orientation: 6 })
    .withExifMerge({
      IFD0: { Artist: "Vynlo synthetic media fixture" },
      IFD3: {
        GPSLatitude: "1/1 2/1 3/1",
        GPSLatitudeRef: "N",
        GPSLongitude: "4/1 5/1 6/1",
        GPSLongitudeRef: "E",
      },
    })
    .withXmp(
      '<?xpacket begin=""?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" /></x:xmpmeta><?xpacket end="w"?>',
    );

  if (format.format === "jpeg") {
    pipeline = pipeline.jpeg({ chromaSubsampling: "4:4:4", quality: 95 });
  } else if (format.format === "png") {
    pipeline = pipeline.png({ compressionLevel: 9 });
  } else {
    pipeline = pipeline.webp({ alphaQuality: 100, quality: 95 });
  }

  const source = await pipeline.toBuffer();
  const metadata = await sharp(source).metadata();
  expect(metadata).toMatchObject({
    format: format.format,
    height: SOURCE_HEIGHT,
    orientation: 6,
    width: SOURCE_WIDTH,
  });
  expect(metadata.exif).toBeDefined();
  expect(metadata.xmp).toBeDefined();

  const checksumSha256 = await mediaSha256Hex(source);
  const inspected = await inspectVehiclePhotoWithSharp({
    maximumPixels: 60_000_000,
    signal: new AbortController().signal,
    source,
  });
  expect(inspected).toEqual({
    exifOrientation: 6,
    height: ORIENTED_HEIGHT,
    width: ORIENTED_WIDTH,
  });
  const validatedSource = validateVehiclePhotoSource({
    checksumSha256,
    exifOrientation: inspected.exifOrientation,
    height: inspected.height,
    intent: normalizeVehiclePhotoUploadIntent({
      checksumSha256,
      declaredMimeType: format.mimeType,
      filename: `phone-photo.${format.extension}`,
      sizeBytes: source.byteLength,
    }),
    observedSizeBytes: source.byteLength,
    signatureBytes: source.subarray(0, 64),
    width: inspected.width,
  });
  return { source: new Uint8Array(source), validatedSource };
}

function heicSignatureFixture(): Uint8Array {
  return new Uint8Array([
    0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63,
    0x00, 0x00, 0x00, 0x00, 0x6d, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63,
  ]);
}

async function expectOrientedColourPattern(
  body: Uint8Array,
  width: number,
  height: number,
): Promise<void> {
  const decoded = await sharp(body)
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  expect(decoded.info).toMatchObject({ channels: 3, height, width });

  const pixel = (xRatio: number, yRatio: number) => {
    const x = Math.floor(width * xRatio);
    const y = Math.floor(height * yRatio);
    const offset = (y * width + x) * decoded.info.channels;
    return [
      decoded.data[offset] ?? 0,
      decoded.data[offset + 1] ?? 0,
      decoded.data[offset + 2] ?? 0,
    ] as const;
  };
  const expectNear = (
    actual: readonly number[],
    expected: readonly number[],
  ) => {
    expected.forEach((channel, index) => {
      expect(actual[index]).toBeGreaterThanOrEqual(channel - 35);
      expect(actual[index]).toBeLessThanOrEqual(channel + 35);
    });
  };

  // EXIF orientation 6 rotates the raw source 90 degrees clockwise.
  expectNear(pixel(0.2, 0.2), [20, 40, 230]);
  expectNear(pixel(0.8, 0.2), [230, 30, 20]);
  expectNear(pixel(0.2, 0.8), [230, 210, 20]);
  expectNear(pixel(0.8, 0.8), [30, 220, 40]);
}

describe("T-MED-001 / T-MED-002 / T-MED-003 Sharp vehicle-photo processor", () => {
  it("reports the deployment codec surface and requires core codecs", () => {
    const readiness = assertSharpMediaRuntimeReady();
    expect(readiness).toMatchObject({
      heicInput: false,
      jpegInput: true,
      pngInput: true,
      webpInput: true,
      webpOutput: true,
    });
    expect(readSharpMediaReadiness()).toEqual(readiness);
  });

  it.each(sourceFormats)(
    "auto-orients a real generated $format input and proves every WebP derivative receipt",
    async (sourceFormat) => {
      const { source, validatedSource } = await orientedSource(sourceFormat);
      const profile = await createVehiclePhotoProcessingProfileSnapshot({
        profileKey: "vehicle_photo.default",
        version: 1,
      });
      const derivativePlan = planVehiclePhotoDerivatives({
        profile,
        sourceHeight: validatedSource.height,
        sourceWidth: validatedSource.width,
      });
      expect(derivativePlan).toEqual([
        expect.objectContaining({
          height: 1_200,
          variant: "normalized_master",
          width: 800,
          withoutEnlargement: true,
        }),
        expect.objectContaining({
          height: 1_200,
          variant: "website_1080",
          width: 800,
          withoutEnlargement: true,
        }),
        expect.objectContaining({
          height: 960,
          variant: "thumbnail_640",
          width: 640,
          withoutEnlargement: true,
        }),
        expect.objectContaining({
          height: 480,
          variant: "thumbnail_320",
          width: 320,
          withoutEnlargement: true,
        }),
      ]);

      const result = await new SharpVehiclePhotoProcessor().process({
        derivativePlan,
        profile,
        signal: new AbortController().signal,
        source,
        validatedSource,
      });
      const receipt = validateVehiclePhotoProcessorReceipt({
        profile,
        receipt: result.receipt,
        source: validatedSource,
      });

      expect(result.outputs).toHaveLength(4);
      expect(receipt.outputs).toHaveLength(4);
      for (const output of result.outputs) {
        const planned = derivativePlan.find(
          ({ variant }) => variant === output.variant,
        );
        const outputReceipt = receipt.outputs.find(
          ({ variant }) => variant === output.variant,
        );
        expect(planned).toBeDefined();
        expect(outputReceipt).toBeDefined();
        if (planned === undefined || outputReceipt === undefined) continue;

        const metadata = await sharp(output.body).metadata();
        expect(metadata).toMatchObject({
          format: "webp",
          height: planned.height,
          space: "srgb",
          width: planned.width,
        });
        expect(metadata.orientation).toBeUndefined();
        expect(metadata.exif).toBeUndefined();
        expect(metadata.iptc).toBeUndefined();
        expect(metadata.xmp).toBeUndefined();
        expect(output.body.byteLength).toBe(outputReceipt.byteSize);
        expect(await mediaSha256Hex(output.body)).toBe(
          outputReceipt.checksumSha256,
        );
        expect(outputReceipt).toMatchObject({
          height: planned.height,
          metadata: {
            exifPresent: false,
            gpsPresent: false,
            iptcPresent: false,
            xmpPresent: false,
          },
          mimeType: "image/webp",
          normalizedOrientation: 1,
          orientationPolicyApplied: true,
          outputColorSpace: "srgb",
          upscaled: false,
          variant: planned.variant,
          width: planned.width,
        });
        await expectOrientedColourPattern(
          output.body,
          planned.width,
          planned.height,
        );
      }
    },
  );

  it("fails a signature-valid HEIC input before decoder I/O when HEVC is unavailable", async () => {
    const source = heicSignatureFixture();
    const checksumSha256 = await mediaSha256Hex(source);
    await expect(
      inspectVehiclePhotoWithSharp({
        maximumPixels: 60_000_000,
        signal: new AbortController().signal,
        source,
      }),
    ).rejects.toMatchObject({
      classification: "permanent",
      code: "media.heic_codec_unavailable",
    });
    const validatedSource = validateVehiclePhotoSource({
      checksumSha256,
      exifOrientation: 6,
      height: 6,
      intent: normalizeVehiclePhotoUploadIntent({
        checksumSha256,
        declaredMimeType: "image/heic",
        filename: "phone-photo.heic",
        sizeBytes: source.byteLength,
      }),
      observedSizeBytes: source.byteLength,
      signatureBytes: source,
      width: 4,
    });
    const profile = await createVehiclePhotoProcessingProfileSnapshot({
      profileKey: "vehicle_photo.default",
      version: 1,
    });
    const derivativePlan = planVehiclePhotoDerivatives({
      profile,
      sourceHeight: validatedSource.height,
      sourceWidth: validatedSource.width,
    });
    await expect(
      new SharpVehiclePhotoProcessor().process({
        derivativePlan,
        profile,
        signal: new AbortController().signal,
        source,
        validatedSource,
      }),
    ).rejects.toMatchObject({
      classification: "permanent",
      code: "media.heic_codec_unavailable",
    });
  });

  it("classifies deterministic decoder failures without leaking codec details", async () => {
    const profile = await createVehiclePhotoProcessingProfileSnapshot({
      profileKey: "vehicle_photo.default",
      version: 1,
    });
    const { validatedSource } = await orientedSource(sourceFormats[1]);
    await expect(
      new SharpVehiclePhotoProcessor().process({
        derivativePlan: planVehiclePhotoDerivatives({
          profile,
          sourceHeight: validatedSource.height,
          sourceWidth: validatedSource.width,
        }),
        profile,
        signal: new AbortController().signal,
        source: new Uint8Array([0x89, 0x50, 0x4e, 0x47]),
        validatedSource,
      }),
    ).rejects.toMatchObject({
      classification: "validation",
      code: "media.image_decode_or_transform_failed",
    });
  });
});
