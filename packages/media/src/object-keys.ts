import { MediaPolicyError } from "./errors";
import {
  VEHICLE_PHOTO_DERIVATIVE_VARIANTS,
  type VehiclePhotoDerivativeVariant,
} from "./processing-profile";
import type { VehiclePhotoMimeType } from "./upload-policy";
import { requireSha256, requireUuid } from "./validation";

export type LegalOriginalMimeType =
  | "application/pdf"
  | "image/jpeg"
  | "image/png"
  | "image/webp"
  | "image/heic"
  | "image/heif";

const extensions: Readonly<Record<LegalOriginalMimeType, string>> =
  Object.freeze({
    "application/pdf": "pdf",
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/heic": "heic",
    "image/heif": "heif",
  });
const derivativeVariants = new Set<string>(VEHICLE_PHOTO_DERIVATIVE_VARIANTS);

function extensionFor(mimeType: string, allowed: readonly string[]): string {
  if (!allowed.includes(mimeType)) {
    throw new MediaPolicyError("invalid_object_key_input");
  }
  const extension = extensions[mimeType as LegalOriginalMimeType];
  if (extension === undefined) {
    throw new MediaPolicyError("invalid_object_key_input");
  }
  return extension;
}

export function vehiclePhotoQuarantineObjectKey(input: {
  readonly workspaceId: string;
  readonly uploadSessionId: string;
}): string {
  const workspaceId = requireUuid(
    input.workspaceId,
    "invalid_object_key_input",
  );
  const uploadSessionId = requireUuid(
    input.uploadSessionId,
    "invalid_object_key_input",
  );
  return `workspaces/${workspaceId}/uploads/${uploadSessionId}/source`;
}

export function vehiclePhotoRawObjectKey(input: {
  readonly workspaceId: string;
  readonly mediaId: string;
  readonly checksumSha256: string;
  readonly mimeType: VehiclePhotoMimeType;
}): string {
  const workspaceId = requireUuid(
    input.workspaceId,
    "invalid_object_key_input",
  );
  const mediaId = requireUuid(input.mediaId, "invalid_object_key_input");
  const checksum = requireSha256(
    input.checksumSha256,
    "invalid_object_key_input",
  );
  const extension = extensionFor(input.mimeType, [
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
  ]);
  return `workspaces/${workspaceId}/media/${mediaId}/raw/${checksum}.${extension}`;
}

export function vehiclePhotoDerivativeObjectKey(input: {
  readonly workspaceId: string;
  readonly mediaId: string;
  readonly processingRunId: string;
  readonly variant: VehiclePhotoDerivativeVariant;
  readonly checksumSha256: string;
}): string {
  const workspaceId = requireUuid(
    input.workspaceId,
    "invalid_object_key_input",
  );
  const mediaId = requireUuid(input.mediaId, "invalid_object_key_input");
  const processingRunId = requireUuid(
    input.processingRunId,
    "invalid_object_key_input",
  );
  if (!derivativeVariants.has(input.variant)) {
    throw new MediaPolicyError("invalid_object_key_input");
  }
  const checksum = requireSha256(
    input.checksumSha256,
    "invalid_object_key_input",
  );
  return `workspaces/${workspaceId}/media/${mediaId}/runs/${processingRunId}/${input.variant}/${checksum}.webp`;
}

export function documentOriginalObjectKey(input: {
  readonly workspaceId: string;
  readonly documentId: string;
  readonly fileId: string;
  readonly checksumSha256: string;
  readonly mimeType: LegalOriginalMimeType;
}): string {
  const workspaceId = requireUuid(
    input.workspaceId,
    "invalid_object_key_input",
  );
  const documentId = requireUuid(input.documentId, "invalid_object_key_input");
  const fileId = requireUuid(input.fileId, "invalid_object_key_input");
  const checksum = requireSha256(
    input.checksumSha256,
    "invalid_object_key_input",
  );
  const extension = extensionFor(input.mimeType, Object.keys(extensions));
  return `workspaces/${workspaceId}/documents/${documentId}/files/${fileId}/${checksum}.${extension}`;
}
