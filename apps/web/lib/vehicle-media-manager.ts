const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const SHA256_PATTERN = /^[a-f0-9]{64}$/u;

export type VehicleMediaStatus =
  "awaiting_upload" | "failed" | "processing" | "quarantined" | "ready";
export type VehicleMediaVariant =
  | "normalized_master"
  | "raw_original"
  | "thumbnail_320"
  | "thumbnail_640"
  | "website_1080";

export interface VehicleMediaFile {
  readonly byteSize: number;
  readonly checksumSha256: string;
  readonly createdAt: string;
  readonly fileClass: "vehicle_photo_derivative" | "vehicle_photo_raw";
  readonly height: number | null;
  readonly id: string;
  readonly metadataStripped: boolean;
  readonly mimeType: string;
  readonly processingRunId: string | null;
  readonly status: "available" | "retired";
  readonly variant: VehicleMediaVariant;
  readonly width: number | null;
}

export interface VehicleMediaAsset {
  readonly archivedAt: null;
  readonly caption: string | null;
  readonly collectionVersion: number;
  readonly createdAt: string;
  readonly files: readonly VehicleMediaFile[];
  readonly id: string;
  readonly inventoryUnitId: string;
  readonly isCover: boolean;
  readonly mediaVersion: number;
  readonly processingProfile: Readonly<{
    checksumSha256: string;
    id: string;
    version: number;
  }>;
  readonly sortOrder: number;
  readonly status: VehicleMediaStatus;
  readonly updatedAt: string;
}

export interface VehicleMediaCollection {
  readonly collectionVersion: number;
  readonly inventoryUnitId: string;
  readonly items: readonly VehicleMediaAsset[];
}

export class VehicleMediaResponseError extends Error {
  constructor() {
    super("The vehicle media response is invalid.");
    this.name = "VehicleMediaResponseError";
  }
}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new VehicleMediaResponseError();
  }
  return value as Record<string, unknown>;
}

function exactKeys(
  value: Record<string, unknown>,
  keys: readonly string[],
): void {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (
    actual.length !== expected.length ||
    actual.some((key, index) => key !== expected[index])
  ) {
    throw new VehicleMediaResponseError();
  }
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new VehicleMediaResponseError();
  }
  return value.toLowerCase();
}

function integer(
  value: unknown,
  minimum = 1,
  maximum = Number.MAX_SAFE_INTEGER,
) {
  if (
    !Number.isSafeInteger(value) ||
    Number(value) < minimum ||
    Number(value) > maximum
  ) {
    throw new VehicleMediaResponseError();
  }
  return Number(value);
}

function timestamp(value: unknown): string {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) {
    throw new VehicleMediaResponseError();
  }
  return value;
}

function nullableInteger(value: unknown): number | null {
  return value === null ? null : integer(value);
}

function parseFile(value: unknown): VehicleMediaFile {
  const file = record(value);
  exactKeys(file, [
    "byteSize",
    "checksumSha256",
    "createdAt",
    "fileClass",
    "height",
    "id",
    "metadataStripped",
    "mimeType",
    "processingRunId",
    "status",
    "variant",
    "width",
  ]);
  const variants: readonly VehicleMediaVariant[] = [
    "normalized_master",
    "raw_original",
    "thumbnail_320",
    "thumbnail_640",
    "website_1080",
  ];
  const fileClasses = [
    "vehicle_photo_derivative",
    "vehicle_photo_raw",
  ] as const;
  const statuses = ["available", "retired"] as const;
  if (
    typeof file.checksumSha256 !== "string" ||
    !SHA256_PATTERN.test(file.checksumSha256) ||
    typeof file.mimeType !== "string" ||
    file.mimeType.length < 3 ||
    file.mimeType.length > 120 ||
    typeof file.metadataStripped !== "boolean" ||
    !fileClasses.includes(file.fileClass as (typeof fileClasses)[number]) ||
    !statuses.includes(file.status as (typeof statuses)[number]) ||
    !variants.includes(file.variant as VehicleMediaVariant)
  ) {
    throw new VehicleMediaResponseError();
  }
  const width = nullableInteger(file.width);
  const height = nullableInteger(file.height);
  if (
    (width === null) !== (height === null) ||
    (file.fileClass === "vehicle_photo_raw") !==
      (file.variant === "raw_original")
  ) {
    throw new VehicleMediaResponseError();
  }
  return Object.freeze({
    byteSize: integer(file.byteSize),
    checksumSha256: file.checksumSha256,
    createdAt: timestamp(file.createdAt),
    fileClass: file.fileClass as VehicleMediaFile["fileClass"],
    height,
    id: uuid(file.id),
    metadataStripped: file.metadataStripped,
    mimeType: file.mimeType,
    processingRunId:
      file.processingRunId === null ? null : uuid(file.processingRunId),
    status: file.status as VehicleMediaFile["status"],
    variant: file.variant as VehicleMediaVariant,
    width,
  });
}

function parseAsset(
  value: unknown,
  expectedInventoryUnitId: string,
): VehicleMediaAsset {
  const asset = record(value);
  exactKeys(asset, [
    "archivedAt",
    "caption",
    "collectionVersion",
    "createdAt",
    "files",
    "id",
    "inventoryUnitId",
    "isCover",
    "mediaVersion",
    "processingProfile",
    "sortOrder",
    "status",
    "updatedAt",
  ]);
  const statuses: readonly VehicleMediaStatus[] = [
    "awaiting_upload",
    "failed",
    "processing",
    "quarantined",
    "ready",
  ];
  if (
    asset.archivedAt !== null ||
    (asset.caption !== null &&
      (typeof asset.caption !== "string" ||
        asset.caption.length < 1 ||
        asset.caption.length > 500)) ||
    !Array.isArray(asset.files) ||
    asset.files.length > 5 ||
    typeof asset.isCover !== "boolean" ||
    !statuses.includes(asset.status as VehicleMediaStatus)
  ) {
    throw new VehicleMediaResponseError();
  }
  const inventoryUnitId = uuid(asset.inventoryUnitId);
  if (inventoryUnitId !== expectedInventoryUnitId) {
    throw new VehicleMediaResponseError();
  }
  const profile = record(asset.processingProfile);
  exactKeys(profile, ["checksumSha256", "id", "version"]);
  if (
    typeof profile.checksumSha256 !== "string" ||
    !SHA256_PATTERN.test(profile.checksumSha256)
  ) {
    throw new VehicleMediaResponseError();
  }
  const files = asset.files.map(parseFile);
  if (new Set(files.map((file) => file.id)).size !== files.length) {
    throw new VehicleMediaResponseError();
  }
  return Object.freeze({
    archivedAt: null,
    caption: asset.caption as string | null,
    collectionVersion: integer(asset.collectionVersion),
    createdAt: timestamp(asset.createdAt),
    files: Object.freeze(files),
    id: uuid(asset.id),
    inventoryUnitId,
    isCover: asset.isCover,
    mediaVersion: integer(asset.mediaVersion),
    processingProfile: Object.freeze({
      checksumSha256: profile.checksumSha256,
      id: uuid(profile.id),
      version: integer(profile.version),
    }),
    sortOrder: integer(asset.sortOrder, 0, 49),
    status: asset.status as VehicleMediaStatus,
    updatedAt: timestamp(asset.updatedAt),
  });
}

export function parseVehicleMediaCollection(
  value: unknown,
): VehicleMediaCollection {
  const envelope = record(value);
  exactKeys(envelope, ["data"]);
  const data = record(envelope.data);
  exactKeys(data, ["collectionVersion", "inventoryUnitId", "items"]);
  const inventoryUnitId = uuid(data.inventoryUnitId);
  const collectionVersion = integer(data.collectionVersion);
  if (!Array.isArray(data.items) || data.items.length > 50) {
    throw new VehicleMediaResponseError();
  }
  const items = data.items.map((item) => parseAsset(item, inventoryUnitId));
  if (
    new Set(items.map((item) => item.id)).size !== items.length ||
    items.some(
      (item, index) =>
        item.collectionVersion !== collectionVersion ||
        item.sortOrder !== index,
    ) ||
    items.filter((item) => item.isCover).length > 1
  ) {
    throw new VehicleMediaResponseError();
  }
  return Object.freeze({
    collectionVersion,
    inventoryUnitId,
    items: Object.freeze(items),
  });
}

export function parseThumbnailGrant(
  value: unknown,
  expectedFileId: string,
): Readonly<{ expiresAt: string; url: string }> {
  const envelope = record(value);
  exactKeys(envelope, ["data"]);
  const data = record(envelope.data);
  exactKeys(data, [
    "auditEventId",
    "byteSize",
    "checksumSha256",
    "download",
    "mediaFileId",
    "mediaKind",
    "mimeType",
    "replayed",
  ]);
  const download = record(data.download);
  exactKeys(download, ["expiresAt", "url"]);
  let url: URL;
  try {
    url = new URL(String(download.url));
  } catch {
    throw new VehicleMediaResponseError();
  }
  const safeProtocol =
    url.protocol === "https:" ||
    (url.protocol === "http:" &&
      ["127.0.0.1", "localhost", "::1"].includes(url.hostname));
  if (
    uuid(data.auditEventId) === "" ||
    integer(data.byteSize) < 1 ||
    typeof data.checksumSha256 !== "string" ||
    !SHA256_PATTERN.test(data.checksumSha256) ||
    uuid(data.mediaFileId) !== expectedFileId ||
    data.mediaKind !== "vehicle_photo" ||
    data.mimeType !== "image/webp" ||
    typeof data.replayed !== "boolean" ||
    !safeProtocol ||
    url.username !== "" ||
    url.password !== ""
  ) {
    throw new VehicleMediaResponseError();
  }
  return Object.freeze({
    expiresAt: timestamp(download.expiresAt),
    url: url.toString(),
  });
}

export function selectVehicleThumbnail(
  media: VehicleMediaAsset,
): VehicleMediaFile | null {
  for (const variant of ["thumbnail_320", "thumbnail_640"] as const) {
    const file = media.files.find(
      (candidate) =>
        candidate.variant === variant && candidate.status === "available",
    );
    if (file) return file;
  }
  return null;
}

export function moveVehicleMediaIds(
  items: readonly VehicleMediaAsset[],
  mediaId: string,
  direction: -1 | 1,
): readonly string[] {
  const index = items.findIndex((item) => item.id === mediaId);
  const destination = index + direction;
  if (index < 0 || destination < 0 || destination >= items.length) {
    return items.map((item) => item.id);
  }
  const ids = items.map((item) => item.id);
  [ids[index], ids[destination]] = [ids[destination]!, ids[index]!];
  return ids;
}

export function vehicleMediaIsTransient(status: VehicleMediaStatus): boolean {
  return ["awaiting_upload", "quarantined", "processing"].includes(status);
}
