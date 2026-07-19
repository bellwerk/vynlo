import { parseVehiclePhotoProcessingProfileSnapshot } from "@vynlo/media";
import { JobExecutionError } from "./job-runner";
import type {
  MediaCompletionResult,
  MediaProcessingRepository,
  MediaProcessingSource,
  RawRetentionRepository,
} from "./media-handler";
import type { MediaUploadVerificationRepository } from "./media-upload-verification-handler";
import type { MediaQuarantineCleanupRepository } from "./media-quarantine-cleanup-handler";
import type { LegalOriginalUploadVerificationRepository } from "./legal-original-upload-verification-handler";
import type { LegalOriginalQuarantineCleanupRepository } from "./legal-original-quarantine-cleanup-handler";

function invalidContract(label: string): JobExecutionError {
  return new JobExecutionError({
    classification: "permanent",
    code: `media.invalid_${label}`,
    safeDetail: "The media database response failed contract validation.",
  });
}

function record(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidContract(label);
  }
  return value as Record<string, unknown>;
}

function string(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length < 1)
    throw invalidContract(label);
  return value;
}

function integer(value: unknown, label: string): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1)
    throw invalidContract(label);
  return value as number;
}

function nullableInteger(value: unknown, label: string): number | null {
  return value === null ? null : integer(value, label);
}

function boolean(value: unknown, label: string): boolean {
  if (typeof value !== "boolean") throw invalidContract(label);
  return value;
}

function nullableString(value: unknown, label: string): string | null {
  return value === null ? null : string(value, label);
}

function baseUrl(value: string): string {
  const parsed = new URL(value);
  const local = ["127.0.0.1", "localhost", "::1"].includes(parsed.hostname);
  if (
    (parsed.protocol !== "https:" && !(parsed.protocol === "http:" && local)) ||
    parsed.username !== "" ||
    parsed.password !== "" ||
    !["", "/"].includes(parsed.pathname) ||
    parsed.search !== "" ||
    parsed.hash !== ""
  ) {
    throw new TypeError("Supabase media repository URL must be a safe origin.");
  }
  return parsed.toString().replace(/\/$/u, "");
}

function responseFailure(response: Response): JobExecutionError {
  if (response.status === 401 || response.status === 403) {
    return new JobExecutionError({
      classification: "provider_auth",
      code: "media.database_access_denied",
      safeDetail: "The media database denied the worker request.",
    });
  }
  if (response.status === 409) {
    return new JobExecutionError({
      classification: "permanent",
      code: "media.database_state_conflict",
      safeDetail: "The media database rejected conflicting terminal state.",
    });
  }
  if (response.status === 429 || response.status >= 500) {
    return new JobExecutionError({
      classification: "transient",
      code: "media.database_temporarily_unavailable",
      safeDetail: "The media database is temporarily unavailable.",
    });
  }
  return new JobExecutionError({
    classification: "permanent",
    code: "media.database_request_rejected",
    safeDetail: "The media database rejected the validated worker request.",
  });
}

export class PostgrestMediaRepository implements MediaProcessingRepository {
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #headers: Readonly<Record<string, string>>;

  constructor(input: {
    readonly fetchImplementation?: typeof fetch;
    readonly serviceRoleKey: string;
    readonly supabaseUrl: string;
  }) {
    if (input.serviceRoleKey.trim().length < 20) {
      throw new TypeError("A server-only service role key is required.");
    }
    this.#baseUrl = baseUrl(input.supabaseUrl);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#headers = Object.freeze({
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
      "Content-Profile": "app",
      "Content-Type": "application/json",
    });
  }

  async start(
    input: Parameters<MediaProcessingRepository["start"]>[0],
  ): Promise<MediaProcessingSource> {
    const row = await this.#single(
      "start_vehicle_photo_processing",
      {
        p_attempt_number: input.attemptNumber,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_media_id: input.mediaId,
        p_processing_run_id: input.processingRunId,
        p_request_id: input.requestId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const profileValue = record(row.profile_snapshot, "profile_snapshot");
    let profile;
    try {
      profile = await parseVehiclePhotoProcessingProfileSnapshot(profileValue);
    } catch {
      throw invalidContract("profile_snapshot");
    }
    const mimeType = string(row.source_mime_type, "source_mime_type");
    if (
      ![
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif",
      ].includes(mimeType)
    ) {
      throw invalidContract("source_mime_type");
    }
    const mediaStatus = string(row.media_status, "media_status");
    if (mediaStatus !== "processing" && mediaStatus !== "ready") {
      throw invalidContract("media_status");
    }
    return {
      alreadySucceeded: boolean(row.already_succeeded, "already_succeeded"),
      bucket: string(row.source_bucket, "source_bucket"),
      byteSize: integer(row.source_byte_size, "source_byte_size"),
      checksumSha256: string(row.source_checksum_sha256, "source_checksum"),
      exifOrientation: nullableInteger(
        row.source_exif_orientation,
        "source_orientation",
      ),
      generation: integer(row.generation, "generation"),
      height: integer(row.source_height, "source_height"),
      mediaStatus,
      mimeType: mimeType as MediaProcessingSource["mimeType"],
      objectKey: string(row.source_object_key, "source_object_key"),
      profile,
      width: integer(row.source_width, "source_width"),
    };
  }

  async complete(
    input: Parameters<MediaProcessingRepository["complete"]>[0],
  ): Promise<MediaCompletionResult> {
    const row = await this.#single(
      "complete_vehicle_photo_processing",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_media_id: input.mediaId,
        p_processing_run_id: input.processingRunId,
        p_receipt: input.receipt,
        p_request_id: input.requestId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    if (row.media_status !== "ready")
      throw invalidContract("completion_status");
    return {
      aggregateVersion: integer(row.aggregate_version, "aggregate_version"),
      mediaStatus: "ready",
      normalizedMasterFileId: string(
        row.normalized_master_file_id,
        "normalized_master_file_id",
      ),
      rawDeleteAfter: string(row.raw_delete_after, "raw_delete_after"),
      rawFileId: string(row.raw_file_id, "raw_file_id"),
      replayed: boolean(row.replayed, "replayed"),
    };
  }

  async recordFailure(
    input: Parameters<MediaProcessingRepository["recordFailure"]>[0],
  ): Promise<void> {
    await this.#single(
      "record_vehicle_photo_processing_failure",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_error_classification: input.classification,
        p_error_code: input.errorCode,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_media_id: input.mediaId,
        p_processing_run_id: input.processingRunId,
        p_request_id: input.requestId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
  }

  async load(
    input: Parameters<RawRetentionRepository["load"]>[0],
  ): ReturnType<RawRetentionRepository["load"]> {
    const row = await this.#single(
      "load_vehicle_raw_retention",
      {
        p_attempt_number: input.attemptNumber,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_media_file_id: input.mediaFileId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    return {
      alreadyDeleted: boolean(row.already_deleted, "already_deleted"),
      checksumSha256: string(row.checksum_sha256, "retention_checksum"),
      mediaId: string(row.media_id, "retention_media_id"),
      storageBucket: string(row.storage_bucket, "retention_bucket"),
      storageObjectKey: string(row.storage_object_key, "retention_object_key"),
    };
  }

  async completeRawRetention(
    input: Parameters<RawRetentionRepository["complete"]>[0],
  ): ReturnType<RawRetentionRepository["complete"]> {
    const row = await this.#single(
      "complete_vehicle_raw_retention",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_media_file_id: input.mediaFileId,
        p_request_id: input.requestId,
        p_storage_result: input.storageResult,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    return {
      deletedAt: string(row.deleted_at, "deleted_at"),
      mediaId: string(row.media_id, "retention_media_id"),
      replayed: boolean(row.replayed, "retention_replayed"),
    };
  }

  // The interface method name collides with processing completion. Expose a
  // small adapter for the retention handler rather than weakening either type.
  rawRetentionRepository(): RawRetentionRepository {
    return {
      complete: (input) => this.completeRawRetention(input),
      load: (input) => this.load(input),
    };
  }

  async loadUploadVerification(
    input: Parameters<MediaUploadVerificationRepository["load"]>[0],
  ): ReturnType<MediaUploadVerificationRepository["load"]> {
    const row = await this.#single(
      "load_vehicle_photo_upload_verification",
      {
        p_attempt_number: input.attemptNumber,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_media_id: input.mediaId,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const expectedMimeType = string(
      row.expected_mime_type,
      "verification_mime_type",
    );
    if (
      ![
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif",
      ].includes(expectedMimeType)
    ) {
      throw invalidContract("verification_mime_type");
    }
    return {
      actorUserId: string(row.actor_user_id, "verification_actor_user_id"),
      bucket: string(row.upload_bucket, "verification_bucket"),
      expectedByteSize: integer(
        row.expected_byte_size,
        "verification_byte_size",
      ),
      expectedChecksumSha256: string(
        row.expected_checksum_sha256,
        "verification_checksum",
      ),
      expectedMimeType: expectedMimeType as Awaited<
        ReturnType<MediaUploadVerificationRepository["load"]>
      >["expectedMimeType"],
      expiresAt: string(row.expires_at, "verification_expires_at"),
      objectKey: string(row.upload_object_key, "verification_object_key"),
    };
  }

  async completeUploadVerification(
    input: Parameters<MediaUploadVerificationRepository["complete"]>[0],
  ): ReturnType<MediaUploadVerificationRepository["complete"]> {
    const row = await this.#single(
      "complete_vehicle_photo_upload_verification",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_exif_orientation: input.exifOrientation,
        p_height: input.height,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_malware_scan_receipt: input.malwareScanReceipt,
        p_media_id: input.mediaId,
        p_observed_byte_size: input.observedByteSize,
        p_observed_checksum_sha256: input.observedChecksumSha256,
        p_observed_mime_type: input.observedMimeType,
        p_request_id: input.requestId,
        p_upload_session_id: input.uploadSessionId,
        p_width: input.width,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    if (row.media_status !== "quarantined") {
      throw invalidContract("verification_completion_status");
    }
    return {
      aggregateVersion: integer(
        row.aggregate_version,
        "verification_aggregate_version",
      ),
      mediaStatus: "quarantined",
      processingJobId: string(row.job_id, "verification_processing_job_id"),
      processingRunId: string(
        row.processing_run_id,
        "verification_processing_run_id",
      ),
      replayed: boolean(row.replayed, "verification_replayed"),
    };
  }

  async rejectUploadVerification(
    input: Parameters<MediaUploadVerificationRepository["reject"]>[0],
  ): ReturnType<MediaUploadVerificationRepository["reject"]> {
    await this.#single(
      "reject_vehicle_photo_upload_verification",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_error_classification: input.errorClassification,
        p_error_code: input.errorCode,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_media_id: input.mediaId,
        p_request_id: input.requestId,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
  }

  mediaUploadVerificationRepository(): MediaUploadVerificationRepository {
    return {
      complete: (input) => this.completeUploadVerification(input),
      load: (input) => this.loadUploadVerification(input),
      reject: (input) => this.rejectUploadVerification(input),
    };
  }

  async loadLegalOriginalUploadVerification(
    input: Parameters<LegalOriginalUploadVerificationRepository["load"]>[0],
  ): ReturnType<LegalOriginalUploadVerificationRepository["load"]> {
    const row = await this.#single(
      "load_legal_original_upload_verification",
      {
        p_attempt_number: input.attemptNumber,
        p_document_id: input.documentId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const expectedMimeType = string(
      row.expected_mime_type,
      "legal_original_expected_mime_type",
    );
    if (
      ![
        "application/pdf",
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif",
      ].includes(expectedMimeType)
    ) {
      throw invalidContract("legal_original_expected_mime_type");
    }
    const mediaKind = string(row.media_kind, "legal_original_media_kind");
    if (mediaKind !== "legal_document" && mediaKind !== "signed_document") {
      throw invalidContract("legal_original_media_kind");
    }
    if (row.upload_bucket !== "media-private") {
      throw invalidContract("legal_original_bucket");
    }
    return {
      actorUserId: string(row.actor_user_id, "legal_original_actor_user_id"),
      bucket: "media-private",
      expectedByteSize: integer(
        row.expected_byte_size,
        "legal_original_expected_byte_size",
      ),
      expectedChecksumSha256: string(
        row.expected_checksum_sha256,
        "legal_original_expected_checksum",
      ),
      expectedMimeType: expectedMimeType as Awaited<
        ReturnType<LegalOriginalUploadVerificationRepository["load"]>
      >["expectedMimeType"],
      mediaKind,
      objectKey: string(row.upload_object_key, "legal_original_object_key"),
    };
  }

  async completeLegalOriginalUploadVerification(
    input: Parameters<LegalOriginalUploadVerificationRepository["complete"]>[0],
  ): ReturnType<LegalOriginalUploadVerificationRepository["complete"]> {
    const row = await this.#single(
      "complete_legal_original_upload_verification",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_document_id: input.documentId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_observed_byte_size: input.observedByteSize,
        p_observed_checksum_sha256: input.observedChecksumSha256,
        p_observed_mime_type: input.observedMimeType,
        p_request_id: input.requestId,
        p_storage_generation: input.storageGeneration,
        p_upload_session_id: input.uploadSessionId,
        p_verification_receipt: input.verificationReceipt,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    return {
      mediaFileId: string(row.media_file_id, "legal_original_media_file_id"),
      mediaId: string(row.media_id, "legal_original_media_id"),
      replayed: boolean(row.replayed, "legal_original_replayed"),
    };
  }

  async rejectLegalOriginalUploadVerification(
    input: Parameters<LegalOriginalUploadVerificationRepository["reject"]>[0],
  ): ReturnType<LegalOriginalUploadVerificationRepository["reject"]> {
    await this.#single(
      "reject_legal_original_upload_verification",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_document_id: input.documentId,
        p_error_classification: input.errorClassification,
        p_error_code: input.errorCode,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_request_id: input.requestId,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
  }

  legalOriginalUploadVerificationRepository(): LegalOriginalUploadVerificationRepository {
    return {
      complete: (input) => this.completeLegalOriginalUploadVerification(input),
      load: (input) => this.loadLegalOriginalUploadVerification(input),
      reject: (input) => this.rejectLegalOriginalUploadVerification(input),
    };
  }

  async loadLegalOriginalQuarantineCleanup(
    input: Parameters<LegalOriginalQuarantineCleanupRepository["load"]>[0],
  ): ReturnType<LegalOriginalQuarantineCleanupRepository["load"]> {
    const row = await this.#single(
      "load_legal_original_quarantine_cleanup",
      {
        p_attempt_number: input.attemptNumber,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const reason = string(row.cleanup_reason, "legal_cleanup_reason");
    if (reason !== "expired_intent" && reason !== "terminal_rejection") {
      throw invalidContract("legal_cleanup_reason");
    }
    if (row.storage_bucket !== "media-private") {
      throw invalidContract("legal_cleanup_bucket");
    }
    return {
      alreadyDeleted: boolean(row.already_deleted, "legal_cleanup_deleted"),
      bucket: "media-private",
      cleanupId: string(row.cleanup_id, "legal_cleanup_id"),
      objectKey: string(row.storage_object_key, "legal_cleanup_object_key"),
      reason,
    };
  }

  async fenceLegalOriginalQuarantineCleanup(
    input: Parameters<LegalOriginalQuarantineCleanupRepository["fence"]>[0],
  ): ReturnType<LegalOriginalQuarantineCleanupRepository["fence"]> {
    const row = await this.#single(
      "fence_legal_original_quarantine_cleanup",
      {
        p_attempt_number: input.attemptNumber,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_observed_byte_size: input.observedByteSize,
        p_observed_checksum_sha256: input.observedChecksumSha256,
        p_observed_mime_type: input.observedMimeType,
        p_storage_generation: input.storageGeneration,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    return {
      cleanupId: string(row.cleanup_id, "legal_cleanup_id"),
      replayed: boolean(row.replayed, "legal_cleanup_replayed"),
    };
  }

  async completeLegalOriginalQuarantineCleanup(
    input: Parameters<LegalOriginalQuarantineCleanupRepository["complete"]>[0],
  ): ReturnType<LegalOriginalQuarantineCleanupRepository["complete"]> {
    const row = await this.#single(
      "complete_legal_original_quarantine_cleanup",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_observed_checksum_sha256: input.observedChecksumSha256,
        p_request_id: input.requestId,
        p_storage_result: input.storageResult,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const cleanupStatus = string(row.cleanup_status, "legal_cleanup_status");
    if (cleanupStatus !== "deleted" && cleanupStatus !== "not_found") {
      throw invalidContract("legal_cleanup_status");
    }
    return {
      cleanupId: string(row.cleanup_id, "legal_cleanup_id"),
      cleanupStatus,
      replayed: boolean(row.replayed, "legal_cleanup_replayed"),
    };
  }

  legalOriginalQuarantineCleanupRepository(): LegalOriginalQuarantineCleanupRepository {
    return {
      complete: (input) => this.completeLegalOriginalQuarantineCleanup(input),
      fence: (input) => this.fenceLegalOriginalQuarantineCleanup(input),
      load: (input) => this.loadLegalOriginalQuarantineCleanup(input),
    };
  }

  async loadQuarantineCleanup(
    input: Parameters<MediaQuarantineCleanupRepository["load"]>[0],
  ): ReturnType<MediaQuarantineCleanupRepository["load"]> {
    const row = await this.#single(
      "load_media_quarantine_cleanup",
      {
        p_attempt_number: input.attemptNumber,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const reason = string(row.cleanup_reason, "quarantine_cleanup_reason");
    if (
      reason !== "expired_intent" &&
      reason !== "terminal_rejection" &&
      reason !== "verified_raw_copy"
    ) {
      throw invalidContract("quarantine_cleanup_reason");
    }
    return {
      alreadyDeleted: boolean(
        row.already_deleted,
        "quarantine_cleanup_already_deleted",
      ),
      bucket: string(row.storage_bucket, "quarantine_cleanup_bucket"),
      cleanupId: string(row.cleanup_id, "quarantine_cleanup_id"),
      expectedChecksumSha256: nullableString(
        row.expected_checksum_sha256,
        "quarantine_cleanup_expected_checksum",
      ),
      generation: integer(row.generation, "quarantine_cleanup_generation"),
      mediaId: string(row.media_id, "quarantine_cleanup_media_id"),
      objectKey: string(
        row.storage_object_key,
        "quarantine_cleanup_object_key",
      ),
      reason,
    };
  }

  async fenceQuarantineCleanupChecksum(
    input: Parameters<MediaQuarantineCleanupRepository["fenceChecksum"]>[0],
  ): ReturnType<MediaQuarantineCleanupRepository["fenceChecksum"]> {
    const row = await this.#single(
      "fence_media_quarantine_cleanup_checksum",
      {
        p_attempt_number: input.attemptNumber,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_observed_byte_size: input.observedByteSize,
        p_observed_checksum_sha256: input.observedChecksumSha256,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    return {
      checksumSha256: string(
        row.checksum_sha256,
        "quarantine_cleanup_fenced_checksum",
      ),
      cleanupId: string(row.cleanup_id, "quarantine_cleanup_id"),
      replayed: boolean(row.replayed, "quarantine_cleanup_fence_replayed"),
    };
  }

  async completeQuarantineCleanup(
    input: Parameters<MediaQuarantineCleanupRepository["complete"]>[0],
  ): ReturnType<MediaQuarantineCleanupRepository["complete"]> {
    const row = await this.#single(
      "complete_media_quarantine_cleanup",
      {
        p_attempt_number: input.attemptNumber,
        p_correlation_id: input.correlationId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_object_checksum_sha256: input.objectChecksumSha256,
        p_request_id: input.requestId,
        p_storage_result: input.storageResult,
        p_upload_session_id: input.uploadSessionId,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const cleanupStatus = string(
      row.cleanup_status,
      "quarantine_cleanup_status",
    );
    if (cleanupStatus !== "deleted" && cleanupStatus !== "not_found") {
      throw invalidContract("quarantine_cleanup_status");
    }
    return {
      cleanupId: string(row.cleanup_id, "quarantine_cleanup_id"),
      cleanupStatus,
      completedAt: string(row.completed_at, "quarantine_cleanup_completed_at"),
      mediaId: string(row.media_id, "quarantine_cleanup_media_id"),
      replayed: boolean(row.replayed, "quarantine_cleanup_replayed"),
    };
  }

  mediaQuarantineCleanupRepository(): MediaQuarantineCleanupRepository {
    return {
      complete: (input) => this.completeQuarantineCleanup(input),
      fenceChecksum: (input) => this.fenceQuarantineCleanupChecksum(input),
      load: (input) => this.loadQuarantineCleanup(input),
    };
  }

  async #single(
    functionName: string,
    parameters: Readonly<Record<string, unknown>>,
    signal: AbortSignal,
  ): Promise<Record<string, unknown>> {
    let response: Response;
    try {
      response = await this.#fetch(
        `${this.#baseUrl}/rest/v1/rpc/${functionName}`,
        {
          body: JSON.stringify(parameters),
          headers: this.#headers,
          method: "POST",
          signal,
        },
      );
    } catch {
      throw new JobExecutionError({
        classification: "transient",
        code: "media.database_transport_failed",
        safeDetail: "The media database request did not complete.",
      });
    }
    if (!response.ok) throw responseFailure(response);
    let value: unknown;
    try {
      value = await response.json();
    } catch {
      throw invalidContract("json_response");
    }
    if (!Array.isArray(value) || value.length !== 1) {
      throw invalidContract(`${functionName}_count`);
    }
    return record(value[0], functionName);
  }
}
