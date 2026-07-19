import { MediaPolicyError } from "./errors";
import {
  VEHICLE_PHOTO_MAX_BYTES,
  VEHICLE_PHOTO_MAX_PIXELS,
  VEHICLE_PHOTO_MIME_TYPES,
} from "./upload-policy";
import {
  deepFreeze,
  requirePositiveSafeInteger,
  requireSha256,
  sha256Hex,
} from "./validation";

export const VEHICLE_PHOTO_PROCESSING_PROFILE_SCHEMA_VERSION = 1;

export const VEHICLE_PHOTO_DERIVATIVE_VARIANTS = [
  "normalized_master",
  "website_1080",
  "thumbnail_640",
  "thumbnail_320",
] as const;

export type VehiclePhotoDerivativeVariant =
  (typeof VEHICLE_PHOTO_DERIVATIVE_VARIANTS)[number];

export type VehiclePhotoFileRole =
  "normalized_master" | "website" | "thumbnail";

export interface VehiclePhotoProcessingProfileIdentity {
  readonly profileKey: string;
  readonly version: number;
}

export interface VehiclePhotoDerivativeSpecification {
  readonly variant: VehiclePhotoDerivativeVariant;
  readonly role: VehiclePhotoFileRole;
  readonly mimeType: "image/webp";
  readonly resize:
    | Readonly<{
        mode: "max_edge";
        maximumEdgePixels: 2560;
        withoutEnlargement: true;
      }>
    | Readonly<{
        mode: "max_width";
        maximumWidthPixels: 1080 | 640 | 320;
        withoutEnlargement: true;
      }>;
}

export interface VehiclePhotoProcessingProfileSnapshot {
  readonly schemaVersion: typeof VEHICLE_PHOTO_PROCESSING_PROFILE_SCHEMA_VERSION;
  readonly profileKey: string;
  readonly version: number;
  readonly sourcePolicy: Readonly<{
    maximumBytes: typeof VEHICLE_PHOTO_MAX_BYTES;
    maximumPixels: typeof VEHICLE_PHOTO_MAX_PIXELS;
    acceptedMimeTypes: typeof VEHICLE_PHOTO_MIME_TYPES;
  }>;
  readonly transformationPolicy: Readonly<{
    orientation: "exif_auto";
    outputColorSpace: "srgb";
    metadata: Readonly<{
      exif: "strip";
      gps: "strip";
      iptc: "strip";
      xmp: "strip";
    }>;
  }>;
  readonly derivatives: readonly VehiclePhotoDerivativeSpecification[];
  readonly checksumSha256: string;
}

export interface PlannedVehiclePhotoDerivative {
  readonly variant: VehiclePhotoDerivativeVariant;
  readonly role: VehiclePhotoFileRole;
  readonly mimeType: "image/webp";
  readonly width: number;
  readonly height: number;
  readonly withoutEnlargement: true;
}

const profileKeyPattern = /^[a-z][a-z0-9_.-]{2,119}$/u;

function derivativeSpecifications(): readonly VehiclePhotoDerivativeSpecification[] {
  return [
    {
      variant: "normalized_master",
      role: "normalized_master",
      mimeType: "image/webp",
      resize: {
        mode: "max_edge",
        maximumEdgePixels: 2560,
        withoutEnlargement: true,
      },
    },
    {
      variant: "website_1080",
      role: "website",
      mimeType: "image/webp",
      resize: {
        mode: "max_width",
        maximumWidthPixels: 1080,
        withoutEnlargement: true,
      },
    },
    {
      variant: "thumbnail_640",
      role: "thumbnail",
      mimeType: "image/webp",
      resize: {
        mode: "max_width",
        maximumWidthPixels: 640,
        withoutEnlargement: true,
      },
    },
    {
      variant: "thumbnail_320",
      role: "thumbnail",
      mimeType: "image/webp",
      resize: {
        mode: "max_width",
        maximumWidthPixels: 320,
        withoutEnlargement: true,
      },
    },
  ];
}

type VehiclePhotoProcessingProfileBody = Omit<
  VehiclePhotoProcessingProfileSnapshot,
  "checksumSha256"
>;

function profileRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new MediaPolicyError("invalid_processing_profile");
  }
  return value as Record<string, unknown>;
}

function requireExactKeys(
  value: Record<string, unknown>,
  expectedKeys: readonly string[],
): void {
  if (
    Object.keys(value).sort().join(",") !== [...expectedKeys].sort().join(",")
  ) {
    throw new MediaPolicyError("invalid_processing_profile");
  }
}

function suppliedProfileBody(value: unknown): Readonly<{
  body: Record<string, unknown>;
  checksumSha256: string;
  profileKey: string;
  version: number;
}> {
  const root = profileRecord(value);
  requireExactKeys(root, [
    "checksumSha256",
    "derivatives",
    "profileKey",
    "schemaVersion",
    "sourcePolicy",
    "transformationPolicy",
    "version",
  ]);
  const sourcePolicy = profileRecord(root.sourcePolicy);
  requireExactKeys(sourcePolicy, [
    "acceptedMimeTypes",
    "maximumBytes",
    "maximumPixels",
  ]);
  const transformationPolicy = profileRecord(root.transformationPolicy);
  requireExactKeys(transformationPolicy, [
    "metadata",
    "orientation",
    "outputColorSpace",
  ]);
  const metadata = profileRecord(transformationPolicy.metadata);
  requireExactKeys(metadata, ["exif", "gps", "iptc", "xmp"]);
  if (!Array.isArray(root.derivatives)) {
    throw new MediaPolicyError("invalid_processing_profile");
  }
  const derivatives = root.derivatives.map((value) => {
    const derivative = profileRecord(value);
    requireExactKeys(derivative, ["mimeType", "resize", "role", "variant"]);
    const resize = profileRecord(derivative.resize);
    if (resize.mode === "max_edge") {
      requireExactKeys(resize, [
        "maximumEdgePixels",
        "mode",
        "withoutEnlargement",
      ]);
    } else if (resize.mode === "max_width") {
      requireExactKeys(resize, [
        "maximumWidthPixels",
        "mode",
        "withoutEnlargement",
      ]);
    } else {
      throw new MediaPolicyError("invalid_processing_profile");
    }
    return {
      variant: derivative.variant,
      role: derivative.role,
      mimeType: derivative.mimeType,
      resize:
        resize.mode === "max_edge"
          ? {
              mode: resize.mode,
              maximumEdgePixels: resize.maximumEdgePixels,
              withoutEnlargement: resize.withoutEnlargement,
            }
          : {
              mode: resize.mode,
              maximumWidthPixels: resize.maximumWidthPixels,
              withoutEnlargement: resize.withoutEnlargement,
            },
    };
  });
  if (
    typeof root.profileKey !== "string" ||
    !Number.isSafeInteger(root.version)
  ) {
    throw new MediaPolicyError("invalid_processing_profile");
  }
  return {
    body: {
      schemaVersion: root.schemaVersion,
      profileKey: root.profileKey,
      version: root.version,
      sourcePolicy: {
        maximumBytes: sourcePolicy.maximumBytes,
        maximumPixels: sourcePolicy.maximumPixels,
        acceptedMimeTypes: sourcePolicy.acceptedMimeTypes,
      },
      transformationPolicy: {
        orientation: transformationPolicy.orientation,
        outputColorSpace: transformationPolicy.outputColorSpace,
        metadata: {
          exif: metadata.exif,
          gps: metadata.gps,
          iptc: metadata.iptc,
          xmp: metadata.xmp,
        },
      },
      derivatives,
    },
    checksumSha256: requireSha256(
      root.checksumSha256,
      "invalid_processing_profile",
    ),
    profileKey: root.profileKey,
    version: root.version as number,
  };
}

function profileWithoutChecksum(
  identity: VehiclePhotoProcessingProfileIdentity,
): VehiclePhotoProcessingProfileBody {
  const profileKey = identity.profileKey.trim().toLowerCase();
  if (!profileKeyPattern.test(profileKey)) {
    throw new MediaPolicyError("invalid_processing_profile");
  }
  const version = requirePositiveSafeInteger(
    identity.version,
    "invalid_processing_profile",
  );

  return {
    schemaVersion: VEHICLE_PHOTO_PROCESSING_PROFILE_SCHEMA_VERSION,
    profileKey,
    version,
    sourcePolicy: {
      maximumBytes: VEHICLE_PHOTO_MAX_BYTES,
      maximumPixels: VEHICLE_PHOTO_MAX_PIXELS,
      acceptedMimeTypes: VEHICLE_PHOTO_MIME_TYPES,
    },
    transformationPolicy: {
      orientation: "exif_auto" as const,
      outputColorSpace: "srgb" as const,
      metadata: {
        exif: "strip" as const,
        gps: "strip" as const,
        iptc: "strip" as const,
        xmp: "strip" as const,
      },
    },
    derivatives: derivativeSpecifications(),
  };
}

export function serializeVehiclePhotoProcessingProfile(
  identity: VehiclePhotoProcessingProfileIdentity,
): string {
  return JSON.stringify(profileWithoutChecksum(identity));
}

export async function createVehiclePhotoProcessingProfileSnapshot(
  identity: VehiclePhotoProcessingProfileIdentity,
): Promise<VehiclePhotoProcessingProfileSnapshot> {
  const profile = profileWithoutChecksum(identity);
  const checksumSha256 = await sha256Hex(JSON.stringify(profile));
  return deepFreeze({ ...profile, checksumSha256 });
}

export async function parseVehiclePhotoProcessingProfileSnapshot(
  value: unknown,
): Promise<VehiclePhotoProcessingProfileSnapshot> {
  const supplied = suppliedProfileBody(value);
  const serialized = JSON.stringify(supplied.body);
  if ((await sha256Hex(serialized)) !== supplied.checksumSha256) {
    throw new MediaPolicyError("invalid_processing_profile");
  }
  const expected = profileWithoutChecksum({
    profileKey: supplied.profileKey,
    version: supplied.version,
  });
  if (serialized !== JSON.stringify(expected)) {
    throw new MediaPolicyError("invalid_processing_profile");
  }
  return deepFreeze({ ...expected, checksumSha256: supplied.checksumSha256 });
}

export async function verifyVehiclePhotoProcessingProfileSnapshot(
  snapshot: unknown,
): Promise<boolean> {
  try {
    await parseVehiclePhotoProcessingProfileSnapshot(snapshot);
    return true;
  } catch {
    return false;
  }
}

function scaledDimensions(
  sourceWidth: number,
  sourceHeight: number,
  scale: number,
): Readonly<{ width: number; height: number }> {
  return {
    width: Math.max(1, Math.round(sourceWidth * scale)),
    height: Math.max(1, Math.round(sourceHeight * scale)),
  };
}

export function planVehiclePhotoDerivatives(input: {
  readonly sourceWidth: number;
  readonly sourceHeight: number;
  readonly profile: VehiclePhotoProcessingProfileSnapshot;
}): readonly PlannedVehiclePhotoDerivative[] {
  const sourceWidth = requirePositiveSafeInteger(
    input.sourceWidth,
    "invalid_derivative_plan",
  );
  const sourceHeight = requirePositiveSafeInteger(
    input.sourceHeight,
    "invalid_derivative_plan",
  );
  requireSha256(input.profile.checksumSha256, "invalid_processing_profile");

  return deepFreeze(
    input.profile.derivatives.map((specification) => {
      const scale =
        specification.resize.mode === "max_edge"
          ? Math.min(
              1,
              specification.resize.maximumEdgePixels /
                Math.max(sourceWidth, sourceHeight),
            )
          : Math.min(1, specification.resize.maximumWidthPixels / sourceWidth);
      const dimensions = scaledDimensions(sourceWidth, sourceHeight, scale);
      return {
        variant: specification.variant,
        role: specification.role,
        mimeType: specification.mimeType,
        width: dimensions.width,
        height: dimensions.height,
        withoutEnlargement: true as const,
      };
    }),
  );
}
