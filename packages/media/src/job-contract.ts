import { MediaPolicyError } from "./errors";
import {
  deepFreeze,
  hasExactKeys,
  isRecord,
  requirePositiveSafeInteger,
  requireSha256,
  requireUuid,
} from "./validation";

export const VEHICLE_PHOTO_PROCESSING_JOB_TYPE =
  "media.process_vehicle_photo" as const;
export const VEHICLE_PHOTO_PROCESSING_PAYLOAD_SCHEMA_VERSION = 1 as const;
export const VEHICLE_PHOTO_UPLOAD_VERIFICATION_JOB_TYPE =
  "media.verify_vehicle_photo_upload" as const;
export const VEHICLE_PHOTO_UPLOAD_VERIFICATION_PAYLOAD_SCHEMA_VERSION =
  1 as const;
export const MEDIA_QUARANTINE_CLEANUP_JOB_TYPE =
  "media.delete_quarantine_upload" as const;
export const MEDIA_QUARANTINE_CLEANUP_PAYLOAD_SCHEMA_VERSION = 1 as const;
export const LEGAL_ORIGINAL_UPLOAD_VERIFICATION_JOB_TYPE =
  "media.verify_legal_original" as const;
export const LEGAL_ORIGINAL_UPLOAD_VERIFICATION_PAYLOAD_SCHEMA_VERSION =
  1 as const;
export const LEGAL_ORIGINAL_QUARANTINE_CLEANUP_JOB_TYPE =
  "media.delete_legal_original_quarantine" as const;
export const LEGAL_ORIGINAL_QUARANTINE_CLEANUP_PAYLOAD_SCHEMA_VERSION =
  1 as const;

export type MediaQuarantineCleanupReason =
  "expired_intent" | "terminal_rejection" | "verified_raw_copy";
export type LegalOriginalQuarantineCleanupReason =
  "expired_intent" | "terminal_rejection";

export type VehiclePhotoProcessingSource = Readonly<{
  kind: "upload_session" | "media_file";
  id: string;
}>;

export interface VehiclePhotoProcessingJobPayload {
  readonly media_id: string;
  readonly processing_run_id: string;
  readonly profile_checksum: string;
  readonly source: VehiclePhotoProcessingSource;
}

export interface VehiclePhotoProcessingJobEnvelope {
  readonly workspaceId: string;
  readonly jobType: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly payloadSchemaVersion: number;
  readonly payload: unknown;
}

export interface ParsedVehiclePhotoProcessingJob {
  readonly workspaceId: string;
  readonly mediaId: string;
  readonly processingRunId: string;
  readonly profileChecksumSha256: string;
  readonly source: VehiclePhotoProcessingSource;
}

export interface VehiclePhotoUploadVerificationJobPayload {
  readonly media_id: string;
  readonly upload_session_id: string;
}

export interface ParsedVehiclePhotoUploadVerificationJob {
  readonly workspaceId: string;
  readonly mediaId: string;
  readonly uploadSessionId: string;
}

export interface LegalOriginalUploadVerificationJobPayload {
  readonly upload_session_id: string;
}

export interface ParsedLegalOriginalUploadVerificationJob {
  readonly documentId: string;
  readonly uploadSessionId: string;
  readonly workspaceId: string;
}

export interface LegalOriginalQuarantineCleanupJobPayload {
  readonly reason: LegalOriginalQuarantineCleanupReason;
  readonly upload_session_id: string;
}

export interface ParsedLegalOriginalQuarantineCleanupJob {
  readonly reason: LegalOriginalQuarantineCleanupReason;
  readonly uploadSessionId: string;
  readonly workspaceId: string;
}

export interface MediaQuarantineCleanupJobPayload {
  readonly checksum_sha256: string | null;
  readonly generation: number;
  readonly media_id: string;
  readonly reason: MediaQuarantineCleanupReason;
  readonly upload_session_id: string;
}

export interface ParsedMediaQuarantineCleanupJob {
  readonly checksumSha256: string | null;
  readonly generation: number;
  readonly mediaId: string;
  readonly reason: MediaQuarantineCleanupReason;
  readonly uploadSessionId: string;
  readonly workspaceId: string;
}

function normalizeSource(value: unknown): VehiclePhotoProcessingSource {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["kind", "id"]) ||
    (value.kind !== "upload_session" && value.kind !== "media_file")
  ) {
    throw new MediaPolicyError("invalid_job_payload");
  }
  return deepFreeze({
    kind: value.kind,
    id: requireUuid(value.id, "invalid_job_payload"),
  });
}

export function buildVehiclePhotoProcessingJobPayload(input: {
  readonly mediaId: string;
  readonly processingRunId: string;
  readonly profileChecksumSha256: string;
  readonly source: VehiclePhotoProcessingSource;
}): VehiclePhotoProcessingJobPayload {
  return deepFreeze({
    media_id: requireUuid(input.mediaId, "invalid_job_payload"),
    processing_run_id: requireUuid(
      input.processingRunId,
      "invalid_job_payload",
    ),
    profile_checksum: requireSha256(
      input.profileChecksumSha256,
      "invalid_job_payload",
    ),
    source: normalizeSource(input.source),
  });
}

export function parseVehiclePhotoProcessingJob(
  envelope: VehiclePhotoProcessingJobEnvelope,
): ParsedVehiclePhotoProcessingJob {
  if (
    envelope.jobType !== VEHICLE_PHOTO_PROCESSING_JOB_TYPE ||
    envelope.entityType !== "vehicle_media" ||
    envelope.payloadSchemaVersion !==
      VEHICLE_PHOTO_PROCESSING_PAYLOAD_SCHEMA_VERSION ||
    !isRecord(envelope.payload) ||
    !hasExactKeys(envelope.payload, [
      "media_id",
      "processing_run_id",
      "profile_checksum",
      "source",
    ])
  ) {
    throw new MediaPolicyError("invalid_job_contract");
  }

  const workspaceId = requireUuid(envelope.workspaceId, "invalid_job_contract");
  const entityId = requireUuid(envelope.entityId, "invalid_job_contract");
  const mediaId = requireUuid(envelope.payload.media_id, "invalid_job_payload");
  if (entityId !== mediaId) {
    throw new MediaPolicyError("invalid_job_contract");
  }

  return deepFreeze({
    workspaceId,
    mediaId,
    processingRunId: requireUuid(
      envelope.payload.processing_run_id,
      "invalid_job_payload",
    ),
    profileChecksumSha256: requireSha256(
      envelope.payload.profile_checksum,
      "invalid_job_payload",
    ),
    source: normalizeSource(envelope.payload.source),
  });
}

export function buildVehiclePhotoUploadVerificationJobPayload(input: {
  readonly mediaId: string;
  readonly uploadSessionId: string;
}): VehiclePhotoUploadVerificationJobPayload {
  return deepFreeze({
    media_id: requireUuid(input.mediaId, "invalid_job_payload"),
    upload_session_id: requireUuid(
      input.uploadSessionId,
      "invalid_job_payload",
    ),
  });
}

export function parseVehiclePhotoUploadVerificationJob(
  envelope: VehiclePhotoProcessingJobEnvelope,
): ParsedVehiclePhotoUploadVerificationJob {
  if (
    envelope.jobType !== VEHICLE_PHOTO_UPLOAD_VERIFICATION_JOB_TYPE ||
    envelope.entityType !== "media_upload_session" ||
    envelope.payloadSchemaVersion !==
      VEHICLE_PHOTO_UPLOAD_VERIFICATION_PAYLOAD_SCHEMA_VERSION ||
    !isRecord(envelope.payload) ||
    !hasExactKeys(envelope.payload, ["media_id", "upload_session_id"])
  ) {
    throw new MediaPolicyError("invalid_job_contract");
  }

  const workspaceId = requireUuid(envelope.workspaceId, "invalid_job_contract");
  const entityId = requireUuid(envelope.entityId, "invalid_job_contract");
  const uploadSessionId = requireUuid(
    envelope.payload.upload_session_id,
    "invalid_job_payload",
  );
  if (entityId !== uploadSessionId) {
    throw new MediaPolicyError("invalid_job_contract");
  }
  return deepFreeze({
    workspaceId,
    mediaId: requireUuid(envelope.payload.media_id, "invalid_job_payload"),
    uploadSessionId,
  });
}

export function buildLegalOriginalUploadVerificationJobPayload(input: {
  readonly uploadSessionId: string;
}): LegalOriginalUploadVerificationJobPayload {
  return deepFreeze({
    upload_session_id: requireUuid(
      input.uploadSessionId,
      "invalid_job_payload",
    ),
  });
}

export function parseLegalOriginalUploadVerificationJob(
  envelope: VehiclePhotoProcessingJobEnvelope,
): ParsedLegalOriginalUploadVerificationJob {
  if (
    envelope.jobType !== LEGAL_ORIGINAL_UPLOAD_VERIFICATION_JOB_TYPE ||
    envelope.entityType !== "document" ||
    envelope.payloadSchemaVersion !==
      LEGAL_ORIGINAL_UPLOAD_VERIFICATION_PAYLOAD_SCHEMA_VERSION ||
    !isRecord(envelope.payload) ||
    !hasExactKeys(envelope.payload, ["upload_session_id"])
  ) {
    throw new MediaPolicyError("invalid_job_contract");
  }
  return deepFreeze({
    documentId: requireUuid(envelope.entityId, "invalid_job_contract"),
    uploadSessionId: requireUuid(
      envelope.payload.upload_session_id,
      "invalid_job_payload",
    ),
    workspaceId: requireUuid(envelope.workspaceId, "invalid_job_contract"),
  });
}

function requireCleanupReason(value: unknown): MediaQuarantineCleanupReason {
  if (
    value !== "expired_intent" &&
    value !== "terminal_rejection" &&
    value !== "verified_raw_copy"
  ) {
    throw new MediaPolicyError("invalid_job_payload");
  }
  return value;
}

export function buildMediaQuarantineCleanupJobPayload(input: {
  readonly checksumSha256: string | null;
  readonly generation: number;
  readonly mediaId: string;
  readonly reason: MediaQuarantineCleanupReason;
  readonly uploadSessionId: string;
}): MediaQuarantineCleanupJobPayload {
  return deepFreeze({
    checksum_sha256:
      input.checksumSha256 === null
        ? null
        : requireSha256(input.checksumSha256, "invalid_job_payload"),
    generation: requirePositiveSafeInteger(
      input.generation,
      "invalid_job_payload",
    ),
    media_id: requireUuid(input.mediaId, "invalid_job_payload"),
    reason: requireCleanupReason(input.reason),
    upload_session_id: requireUuid(
      input.uploadSessionId,
      "invalid_job_payload",
    ),
  });
}

export function parseMediaQuarantineCleanupJob(
  envelope: VehiclePhotoProcessingJobEnvelope,
): ParsedMediaQuarantineCleanupJob {
  if (
    envelope.jobType !== MEDIA_QUARANTINE_CLEANUP_JOB_TYPE ||
    envelope.entityType !== "media_upload_session" ||
    envelope.payloadSchemaVersion !==
      MEDIA_QUARANTINE_CLEANUP_PAYLOAD_SCHEMA_VERSION ||
    !isRecord(envelope.payload) ||
    !hasExactKeys(envelope.payload, [
      "checksum_sha256",
      "generation",
      "media_id",
      "reason",
      "upload_session_id",
    ])
  ) {
    throw new MediaPolicyError("invalid_job_contract");
  }

  const workspaceId = requireUuid(envelope.workspaceId, "invalid_job_contract");
  const entityId = requireUuid(envelope.entityId, "invalid_job_contract");
  const uploadSessionId = requireUuid(
    envelope.payload.upload_session_id,
    "invalid_job_payload",
  );
  if (entityId !== uploadSessionId) {
    throw new MediaPolicyError("invalid_job_contract");
  }

  return deepFreeze({
    checksumSha256:
      envelope.payload.checksum_sha256 === null
        ? null
        : requireSha256(
            envelope.payload.checksum_sha256,
            "invalid_job_payload",
          ),
    generation: requirePositiveSafeInteger(
      envelope.payload.generation,
      "invalid_job_payload",
    ),
    mediaId: requireUuid(envelope.payload.media_id, "invalid_job_payload"),
    reason: requireCleanupReason(envelope.payload.reason),
    uploadSessionId,
    workspaceId,
  });
}

function requireLegalCleanupReason(
  value: unknown,
): LegalOriginalQuarantineCleanupReason {
  if (value !== "expired_intent" && value !== "terminal_rejection") {
    throw new MediaPolicyError("invalid_job_payload");
  }
  return value;
}

export function buildLegalOriginalQuarantineCleanupJobPayload(input: {
  readonly reason: LegalOriginalQuarantineCleanupReason;
  readonly uploadSessionId: string;
}): LegalOriginalQuarantineCleanupJobPayload {
  return deepFreeze({
    reason: requireLegalCleanupReason(input.reason),
    upload_session_id: requireUuid(
      input.uploadSessionId,
      "invalid_job_payload",
    ),
  });
}

export function parseLegalOriginalQuarantineCleanupJob(
  envelope: VehiclePhotoProcessingJobEnvelope,
): ParsedLegalOriginalQuarantineCleanupJob {
  if (
    envelope.jobType !== LEGAL_ORIGINAL_QUARANTINE_CLEANUP_JOB_TYPE ||
    envelope.entityType !== "legal_original_upload_session" ||
    envelope.payloadSchemaVersion !==
      LEGAL_ORIGINAL_QUARANTINE_CLEANUP_PAYLOAD_SCHEMA_VERSION ||
    !isRecord(envelope.payload) ||
    !hasExactKeys(envelope.payload, ["reason", "upload_session_id"])
  ) {
    throw new MediaPolicyError("invalid_job_contract");
  }
  const uploadSessionId = requireUuid(
    envelope.payload.upload_session_id,
    "invalid_job_payload",
  );
  if (
    requireUuid(envelope.entityId, "invalid_job_contract") !== uploadSessionId
  ) {
    throw new MediaPolicyError("invalid_job_contract");
  }
  return deepFreeze({
    reason: requireLegalCleanupReason(envelope.payload.reason),
    uploadSessionId,
    workspaceId: requireUuid(envelope.workspaceId, "invalid_job_contract"),
  });
}
