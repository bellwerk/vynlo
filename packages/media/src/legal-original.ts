import type { MalwareScanReceipt } from "./ports";
import { MediaPolicyError } from "./errors";
import type { LegalOriginalMimeType } from "./object-keys";
import { detectVehiclePhotoMimeType } from "./upload-policy";
import {
  deepFreeze,
  hasExactKeys,
  isRecord,
  requirePositiveSafeInteger,
  requireSha256,
  requireUuid,
} from "./validation";

export const LEGAL_ORIGINAL_MAX_BYTES = 50_000_000;
export const LEGAL_ORIGINAL_MIME_TYPES = [
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
] as const;

export type LegalOriginalMediaKind = "legal_document" | "signed_document";

const legalMimeTypes = new Set<string>(LEGAL_ORIGINAL_MIME_TYPES);

export interface LegalOriginalIntent {
  readonly byteSize: number;
  readonly checksumSha256: string;
  readonly filename: string;
  readonly mediaKind: LegalOriginalMediaKind;
  readonly mimeType: LegalOriginalMimeType;
}

export function normalizeLegalOriginalIntent(input: {
  readonly byteSize: number;
  readonly checksumSha256: string;
  readonly filename: string;
  readonly mediaKind: string;
  readonly mimeType: string;
}): LegalOriginalIntent {
  const filename = input.filename.trim();
  const mimeType = input.mimeType.trim().toLowerCase();
  const byteSize = requirePositiveSafeInteger(
    input.byteSize,
    "invalid_legal_original",
  );
  if (
    filename.length < 1 ||
    filename.length > 255 ||
    /[\u0000-\u001f\u007f]/u.test(filename) ||
    byteSize > LEGAL_ORIGINAL_MAX_BYTES ||
    !legalMimeTypes.has(mimeType) ||
    (input.mediaKind !== "legal_document" &&
      input.mediaKind !== "signed_document")
  ) {
    throw new MediaPolicyError("invalid_legal_original");
  }
  return deepFreeze({
    byteSize,
    checksumSha256: requireSha256(
      input.checksumSha256,
      "invalid_legal_original",
    ),
    filename,
    mediaKind: input.mediaKind,
    mimeType: mimeType as LegalOriginalMimeType,
  });
}

export function detectLegalOriginalMimeType(
  bytes: Uint8Array,
): LegalOriginalMimeType | null {
  if (
    bytes.length >= 5 &&
    bytes[0] === 0x25 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x44 &&
    bytes[3] === 0x46 &&
    bytes[4] === 0x2d
  ) {
    return "application/pdf";
  }
  return detectVehiclePhotoMimeType(bytes.slice(0, 128));
}

export interface LegalOriginalVerificationReceipt {
  readonly attempt: number;
  readonly jobId: string;
  readonly leaseId: string;
  readonly malwareScan: Readonly<{
    readonly scanner: string;
    readonly scannerVersion: string;
    readonly signatureVersion: string;
    readonly sourceChecksumSha256: string;
    readonly verdict: "clean";
  }>;
  readonly schemaVersion: 1;
  readonly storage: Readonly<{
    readonly bucket: "media-private";
    readonly byteSize: number;
    readonly checksumSha256: string;
    readonly generation: string;
    readonly mimeType: LegalOriginalMimeType;
    readonly objectKey: string;
  }>;
  readonly verifier: Readonly<{
    readonly name: "vynlo-legal-original-verifier";
    readonly version: "1";
  }>;
  readonly workerId: string;
}

export function buildLegalOriginalVerificationReceipt(input: {
  readonly attempt: number;
  readonly bucket: string;
  readonly byteSize: number;
  readonly checksumSha256: string;
  readonly generation: string;
  readonly jobId: string;
  readonly leaseId: string;
  readonly malwareScan: MalwareScanReceipt;
  readonly mimeType: LegalOriginalMimeType;
  readonly objectKey: string;
  readonly workerId: string;
}): LegalOriginalVerificationReceipt {
  const checksumSha256 = requireSha256(
    input.checksumSha256,
    "invalid_legal_original_receipt",
  );
  const generation = input.generation.trim();
  const objectKey = input.objectKey.trim();
  const workerId = input.workerId.trim();
  if (
    input.bucket !== "media-private" ||
    generation.length < 1 ||
    generation.length > 200 ||
    objectKey.length < 1 ||
    objectKey.length > 1_000 ||
    workerId.length < 1 ||
    workerId.length > 200 ||
    input.malwareScan.verdict !== "clean" ||
    input.malwareScan.sourceChecksumSha256 !== checksumSha256 ||
    input.malwareScan.scanner.name.trim() === "" ||
    input.malwareScan.scanner.version.trim() === "" ||
    input.malwareScan.signatureVersion.trim() === ""
  ) {
    throw new MediaPolicyError("invalid_legal_original_receipt");
  }
  return deepFreeze({
    attempt: requirePositiveSafeInteger(
      input.attempt,
      "invalid_legal_original_receipt",
    ),
    jobId: requireUuid(input.jobId, "invalid_legal_original_receipt"),
    leaseId: requireUuid(input.leaseId, "invalid_legal_original_receipt"),
    malwareScan: {
      scanner: input.malwareScan.scanner.name,
      scannerVersion: input.malwareScan.scanner.version,
      signatureVersion: input.malwareScan.signatureVersion,
      sourceChecksumSha256: checksumSha256,
      verdict: "clean",
    },
    schemaVersion: 1,
    storage: {
      bucket: "media-private",
      byteSize: requirePositiveSafeInteger(
        input.byteSize,
        "invalid_legal_original_receipt",
      ),
      checksumSha256,
      generation,
      mimeType: input.mimeType,
      objectKey,
    },
    verifier: { name: "vynlo-legal-original-verifier", version: "1" },
    workerId,
  });
}

export function parseLegalOriginalVerificationReceipt(
  value: unknown,
): LegalOriginalVerificationReceipt {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "attempt",
      "jobId",
      "leaseId",
      "malwareScan",
      "schemaVersion",
      "storage",
      "verifier",
      "workerId",
    ]) ||
    !isRecord(value.malwareScan) ||
    !isRecord(value.storage) ||
    !isRecord(value.verifier) ||
    !hasExactKeys(value.malwareScan, [
      "scanner",
      "scannerVersion",
      "signatureVersion",
      "sourceChecksumSha256",
      "verdict",
    ]) ||
    !hasExactKeys(value.storage, [
      "bucket",
      "byteSize",
      "checksumSha256",
      "generation",
      "mimeType",
      "objectKey",
    ]) ||
    !hasExactKeys(value.verifier, ["name", "version"]) ||
    value.schemaVersion !== 1 ||
    value.verifier.name !== "vynlo-legal-original-verifier" ||
    value.verifier.version !== "1" ||
    typeof value.malwareScan.scanner !== "string" ||
    typeof value.malwareScan.scannerVersion !== "string" ||
    typeof value.malwareScan.signatureVersion !== "string"
  ) {
    throw new MediaPolicyError("invalid_legal_original_receipt");
  }
  return buildLegalOriginalVerificationReceipt({
    attempt: value.attempt as number,
    bucket: value.storage.bucket as string,
    byteSize: value.storage.byteSize as number,
    checksumSha256: value.storage.checksumSha256 as string,
    generation: value.storage.generation as string,
    jobId: value.jobId as string,
    leaseId: value.leaseId as string,
    malwareScan: {
      scanner: {
        name: value.malwareScan.scanner,
        version: value.malwareScan.scannerVersion,
      },
      signatureVersion: value.malwareScan.signatureVersion,
      sourceChecksumSha256: value.malwareScan.sourceChecksumSha256 as string,
      verdict: value.malwareScan.verdict as "clean",
    },
    mimeType: value.storage.mimeType as LegalOriginalMimeType,
    objectKey: value.storage.objectKey as string,
    workerId: value.workerId as string,
  });
}
