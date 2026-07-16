import {
  detectVehiclePhotoMimeType,
  type VehiclePhotoDerivativeVariant,
  type VehiclePhotoProcessorReceipt,
} from "@vynlo/media";
import sharp from "sharp";

import { JobExecutionError } from "./job-runner";
import { mediaSha256Hex } from "./managed-media-storage";
import type {
  ProcessedVehiclePhotoOutput,
  VehiclePhotoBinaryProcessor,
} from "./media-handler";

interface SharpFormatCapability {
  readonly input?: Readonly<{
    readonly buffer?: boolean;
    readonly fileSuffix?: readonly string[];
  }>;
  readonly output?: Readonly<{ readonly buffer?: boolean }>;
}

export interface SharpMediaReadiness {
  readonly heicInput: boolean;
  readonly jpegInput: boolean;
  readonly libvipsVersion: string;
  readonly pngInput: boolean;
  readonly sharpVersion: string;
  readonly webpInput: boolean;
  readonly webpOutput: boolean;
}

export interface InspectedVehiclePhoto {
  readonly exifOrientation: number | null;
  readonly height: number;
  readonly width: number;
}

function formatCapability(name: string): SharpFormatCapability {
  const formats = sharp.format as unknown as Readonly<Record<string, unknown>>;
  const value = formats[name];
  return typeof value === "object" && value !== null
    ? (value as SharpFormatCapability)
    : {};
}

function canRead(name: string): boolean {
  return formatCapability(name).input?.buffer === true;
}

function canWrite(name: string): boolean {
  return formatCapability(name).output?.buffer === true;
}

function canReadHeic(): boolean {
  const input = formatCapability("heif").input;
  if (input?.buffer !== true || !Array.isArray(input.fileSuffix)) return false;

  return input.fileSuffix.some((suffix) =>
    [".heic", ".heif"].includes(suffix.toLowerCase()),
  );
}

function assertHeicInputReady(
  mimeType: string | null,
  readiness: SharpMediaReadiness,
): void {
  if (
    mimeType !== null &&
    ["image/heic", "image/heif"].includes(mimeType) &&
    !readiness.heicInput
  ) {
    throw new JobExecutionError({
      classification: "permanent",
      code: "media.heic_codec_unavailable",
      safeDetail:
        "This deployment has not enabled a verified HEIC/HEIF decoder.",
    });
  }
}

export function readSharpMediaReadiness(): SharpMediaReadiness {
  return Object.freeze({
    // Sharp exposes AVIF through the libvips HEIF loader too. A working HEIF
    // buffer loader therefore does not prove that the patent-encumbered
    // HEIC/HEVC codec is installed. Only advertise HEIC when libvips exposes an
    // actual .heic or .heif input suffix; deployment acceptance still runs a
    // genuine HEIC golden probe.
    heicInput: canReadHeic(),
    jpegInput: canRead("jpeg"),
    libvipsVersion: sharp.versions.vips ?? "unknown",
    pngInput: canRead("png"),
    sharpVersion: sharp.versions.sharp ?? "unknown",
    webpInput: canRead("webp"),
    webpOutput: canWrite("webp"),
  });
}

export function assertSharpMediaRuntimeReady(): SharpMediaReadiness {
  const readiness = readSharpMediaReadiness();
  if (
    !readiness.jpegInput ||
    !readiness.pngInput ||
    !readiness.webpInput ||
    !readiness.webpOutput ||
    readiness.sharpVersion === "unknown" ||
    readiness.libvipsVersion === "unknown"
  ) {
    throw new TypeError(
      "The worker image runtime does not provide the required bounded Sharp codecs.",
    );
  }
  return readiness;
}

export async function inspectVehiclePhotoWithSharp(input: {
  readonly maximumPixels: number;
  readonly signal: AbortSignal;
  readonly source: Uint8Array;
}): Promise<InspectedVehiclePhoto> {
  input.signal.throwIfAborted();
  try {
    assertHeicInputReady(
      detectVehiclePhotoMimeType(input.source.subarray(0, 64)),
      readSharpMediaReadiness(),
    );
    const metadata = await sharp(input.source, {
      failOn: "warning",
      limitInputPixels: input.maximumPixels,
      pages: 1,
    }).metadata();
    input.signal.throwIfAborted();
    if (
      metadata.width === undefined ||
      metadata.height === undefined ||
      metadata.width < 1 ||
      metadata.height < 1 ||
      (metadata.pages ?? 1) !== 1
    ) {
      throw new TypeError("Invalid bounded image metadata.");
    }
    const exifOrientation = metadata.orientation ?? null;
    const swapsAxes =
      exifOrientation !== null && [5, 6, 7, 8].includes(exifOrientation);
    return Object.freeze({
      exifOrientation,
      height: swapsAxes ? metadata.width : metadata.height,
      width: swapsAxes ? metadata.height : metadata.width,
    });
  } catch (error) {
    if (error instanceof JobExecutionError) throw error;
    throw new JobExecutionError({
      classification: "validation",
      code: "media.image_metadata_invalid",
      safeDetail:
        "The uploaded vehicle photo does not contain safe bounded image metadata.",
    });
  }
}

function processingFailure(error: unknown): JobExecutionError {
  if (error instanceof JobExecutionError) return error;
  return new JobExecutionError({
    classification: "validation",
    code: "media.image_decode_or_transform_failed",
    safeDetail:
      "The uploaded vehicle photo could not be decoded and transformed safely.",
  });
}

/**
 * Bounded Sharp/libvips adapter. Sharp strips EXIF/IPTC/XMP metadata unless
 * withMetadata is requested; every output is decoded again to prove the
 * expected dimensions, sRGB colour space, and absence of those blocks.
 */
export class SharpVehiclePhotoProcessor implements VehiclePhotoBinaryProcessor {
  readonly #readiness: SharpMediaReadiness;

  constructor() {
    this.#readiness = assertSharpMediaRuntimeReady();
  }

  async process(
    input: Parameters<VehiclePhotoBinaryProcessor["process"]>[0],
  ): ReturnType<VehiclePhotoBinaryProcessor["process"]> {
    input.signal.throwIfAborted();
    assertHeicInputReady(
      input.validatedSource.detectedMimeType,
      this.#readiness,
    );

    try {
      const outputs: ProcessedVehiclePhotoOutput[] = [];
      const receiptOutputs: VehiclePhotoProcessorReceipt["outputs"][number][] =
        [];

      for (const derivative of input.derivativePlan) {
        input.signal.throwIfAborted();
        const transformed = await sharp(input.source, {
          failOn: "warning",
          limitInputPixels: input.profile.sourcePolicy.maximumPixels,
          pages: 1,
        })
          .autoOrient()
          .resize({
            fit: "fill",
            height: derivative.height,
            width: derivative.width,
            withoutEnlargement: true,
          })
          .toColourspace("srgb")
          .webp({
            alphaQuality: 100,
            effort: 4,
            quality: 84,
            smartSubsample: true,
          })
          .toBuffer({ resolveWithObject: true });
        input.signal.throwIfAborted();

        const body = new Uint8Array(transformed.data);
        const metadata = await sharp(body, {
          failOn: "warning",
          limitInputPixels: input.profile.sourcePolicy.maximumPixels,
        }).metadata();
        if (
          transformed.info.width !== derivative.width ||
          transformed.info.height !== derivative.height ||
          metadata.width !== derivative.width ||
          metadata.height !== derivative.height ||
          metadata.format !== "webp" ||
          metadata.space !== "srgb" ||
          metadata.exif !== undefined ||
          metadata.iptc !== undefined ||
          metadata.xmp !== undefined
        ) {
          throw new JobExecutionError({
            classification: "permanent",
            code: "media.image_output_policy_mismatch",
            safeDetail:
              "The image runtime produced output outside the immutable media profile.",
          });
        }
        const checksumSha256 = await mediaSha256Hex(body);
        outputs.push({
          body,
          variant: derivative.variant as VehiclePhotoDerivativeVariant,
        });
        receiptOutputs.push({
          byteSize: body.byteLength,
          checksumSha256,
          height: derivative.height,
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
          role: derivative.role,
          upscaled: false,
          variant: derivative.variant,
          width: derivative.width,
        });
      }

      return {
        outputs: Object.freeze(outputs),
        receipt: Object.freeze({
          outputs: Object.freeze(receiptOutputs),
          processor: Object.freeze({
            name: "sharp-libvips",
            version: `${this.#readiness.sharpVersion}+vips.${this.#readiness.libvipsVersion}`,
          }),
          profileChecksumSha256: input.profile.checksumSha256,
          sourceChecksumSha256: input.validatedSource.checksumSha256,
        }),
      };
    } catch (error) {
      throw processingFailure(error);
    }
  }
}
