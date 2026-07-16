export type MediaPolicyErrorCode =
  | "declared_mime_type_mismatch"
  | "invalid_checksum"
  | "invalid_collection"
  | "invalid_completion_receipt"
  | "invalid_cover"
  | "invalid_derivative_plan"
  | "invalid_filename"
  | "invalid_image_dimensions"
  | "invalid_job_contract"
  | "invalid_job_payload"
  | "invalid_legal_original"
  | "invalid_legal_original_receipt"
  | "invalid_media_order"
  | "invalid_media_transition"
  | "invalid_object_key_input"
  | "invalid_processing_profile"
  | "invalid_processor_receipt"
  | "invalid_retention_time"
  | "invalid_size_bytes"
  | "lease_identity_mismatch"
  | "pixel_limit_exceeded"
  | "reprocess_not_allowed"
  | "retention_prohibited"
  | "retry_not_allowed"
  | "source_size_mismatch"
  | "stale_collection_version"
  | "stale_media_version"
  | "unsafe_processor_metadata"
  | "unsupported_declared_mime_type"
  | "unsupported_file_signature";

/** Safe machine-readable domain failure without provider or customer detail. */
export class MediaPolicyError extends Error {
  readonly code: MediaPolicyErrorCode;

  constructor(code: MediaPolicyErrorCode) {
    super(code);
    this.name = "MediaPolicyError";
    this.code = code;
  }
}
