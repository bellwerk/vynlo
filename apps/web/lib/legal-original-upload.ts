export const MAX_LEGAL_ORIGINAL_BYTES = 50_000_000;

export const LEGAL_ORIGINAL_ACCEPT =
  "application/pdf,image/jpeg,image/png,image/webp,image/heic,image/heif,.pdf,.jpg,.jpeg,.png,.webp,.heic,.heif";

export type LegalOriginalMimeType =
  | "application/pdf"
  | "image/heic"
  | "image/heif"
  | "image/jpeg"
  | "image/png"
  | "image/webp";

export type LegalOriginalValidationErrorCode =
  "file_empty" | "file_too_large" | "unsupported_file_type";

export interface LegalOriginalUploadIntent {
  readonly documentId: string;
  readonly expiresAt: string;
  readonly mediaKind: "legal_document" | "signed_document";
  readonly upload: Readonly<{
    readonly bucket: "media-private";
    readonly objectKey: string;
  }>;
  readonly uploadSessionId: string;
}

export interface LegalOriginalVerificationReceipt {
  readonly documentId: string;
  readonly jobId: string;
  readonly jobStatus:
    | "cancelled"
    | "dead_letter"
    | "queued"
    | "retry_wait"
    | "running"
    | "succeeded";
  readonly uploadSessionId: string;
}

export type LegalOriginalProjectedStatus =
  | "awaiting_upload"
  | "completed"
  | "dead_letter"
  | "queued"
  | "rejected"
  | "retry_wait"
  | "running";

export interface LegalOriginalVerificationStatus {
  readonly completedAt: string | null;
  readonly documentId: string;
  readonly job: Readonly<{
    readonly attemptCount: number;
    readonly id: string;
    readonly maximumAttempts: number;
    readonly retryAt: string | null;
  }> | null;
  readonly mediaKind: "legal_document" | "signed_document";
  readonly retryable: boolean;
  readonly status: LegalOriginalProjectedStatus;
  readonly uploadSessionId: string;
}

export type LegalOriginalStatusMessageKey =
  | "statusCompleted"
  | "statusDeadLetter"
  | "statusQueued"
  | "statusRejected"
  | "statusRetryWait"
  | "statusRunning";

const mimeTypes = new Set<LegalOriginalMimeType>([
  "application/pdf",
  "image/heic",
  "image/heif",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const emptyTypeByExtension: Readonly<Record<string, LegalOriginalMimeType>> =
  Object.freeze({
    heic: "image/heic",
    heif: "image/heif",
    jpeg: "image/jpeg",
    jpg: "image/jpeg",
    pdf: "application/pdf",
    png: "image/png",
    webp: "image/webp",
  });

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function commandData(value: unknown): Record<string, unknown> {
  const data = record(record(value)?.data);
  if (!data) throw new TypeError("invalid_legal_original_command_response");
  return data;
}

export function validateLegalOriginalFile(file: {
  readonly name: string;
  readonly size: number;
  readonly type: string;
}):
  | Readonly<{ readonly mimeType: LegalOriginalMimeType; readonly valid: true }>
  | Readonly<{
      readonly code: LegalOriginalValidationErrorCode;
      readonly valid: false;
    }> {
  if (!Number.isSafeInteger(file.size) || file.size < 1) {
    return { code: "file_empty", valid: false };
  }
  if (file.size > MAX_LEGAL_ORIGINAL_BYTES) {
    return { code: "file_too_large", valid: false };
  }
  const declaredType = file.type.trim().toLowerCase();
  if (mimeTypes.has(declaredType as LegalOriginalMimeType)) {
    return {
      mimeType: declaredType as LegalOriginalMimeType,
      valid: true,
    };
  }
  if (declaredType === "") {
    const extension = file.name.toLowerCase().split(".").pop() ?? "";
    const inferredType = emptyTypeByExtension[extension];
    if (inferredType) return { mimeType: inferredType, valid: true };
  }
  return { code: "unsupported_file_type", valid: false };
}

export async function legalOriginalSha256Hex(blob: Blob): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    await blob.arrayBuffer(),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function parseLegalOriginalUploadIntent(
  value: unknown,
): LegalOriginalUploadIntent {
  const data = commandData(value);
  const upload = record(data.upload);
  if (
    typeof data.documentId !== "string" ||
    !uuidPattern.test(data.documentId) ||
    typeof data.expiresAt !== "string" ||
    !Number.isFinite(Date.parse(data.expiresAt)) ||
    (data.mediaKind !== "legal_document" &&
      data.mediaKind !== "signed_document") ||
    typeof data.uploadSessionId !== "string" ||
    !uuidPattern.test(data.uploadSessionId) ||
    !upload ||
    upload.bucket !== "media-private" ||
    typeof upload.objectKey !== "string" ||
    upload.objectKey.length < 1 ||
    upload.objectKey.length > 1_000
  ) {
    throw new TypeError("invalid_legal_original_intent_response");
  }
  return {
    documentId: data.documentId.toLowerCase(),
    expiresAt: data.expiresAt,
    mediaKind: data.mediaKind,
    upload: { bucket: "media-private", objectKey: upload.objectKey },
    uploadSessionId: data.uploadSessionId.toLowerCase(),
  };
}

export function parseLegalOriginalVerificationReceipt(
  value: unknown,
): LegalOriginalVerificationReceipt {
  const data = commandData(value);
  const job = record(data.job);
  const statuses = [
    "cancelled",
    "dead_letter",
    "queued",
    "retry_wait",
    "running",
    "succeeded",
  ] as const;
  if (
    typeof data.documentId !== "string" ||
    !uuidPattern.test(data.documentId) ||
    typeof data.uploadSessionId !== "string" ||
    !uuidPattern.test(data.uploadSessionId) ||
    !job ||
    typeof job.id !== "string" ||
    !uuidPattern.test(job.id) ||
    !statuses.includes(job.status as (typeof statuses)[number])
  ) {
    throw new TypeError("invalid_legal_original_verification_response");
  }
  return {
    documentId: data.documentId.toLowerCase(),
    jobId: job.id.toLowerCase(),
    jobStatus: job.status as LegalOriginalVerificationReceipt["jobStatus"],
    uploadSessionId: data.uploadSessionId.toLowerCase(),
  };
}

export function parseLegalOriginalVerificationStatus(
  value: unknown,
): LegalOriginalVerificationStatus {
  const data = commandData(value);
  const job = data.job === null ? null : record(data.job);
  const failure = data.failure === null ? null : record(data.failure);
  const statuses = [
    "awaiting_upload",
    "completed",
    "dead_letter",
    "queued",
    "rejected",
    "retry_wait",
    "running",
  ] as const;
  const classifications = [
    "transient",
    "rate_limited",
    "permanent",
    "validation",
    "permission",
    "provider_auth",
    "unknown",
    "lease_expired",
  ] as const;
  const status = data.status as LegalOriginalProjectedStatus;
  const validCompletedAt =
    data.completedAt === null ||
    (typeof data.completedAt === "string" &&
      Number.isFinite(Date.parse(data.completedAt)));
  const validFailure =
    failure === null ||
    ((failure.classification === null ||
      classifications.includes(
        failure.classification as (typeof classifications)[number],
      )) &&
      (failure.code === null ||
        (typeof failure.code === "string" &&
          /^[a-z][a-z0-9_.-]{0,119}$/u.test(failure.code))));
  const validJob =
    job === null ||
    (typeof job.id === "string" &&
      uuidPattern.test(job.id) &&
      Number.isSafeInteger(job.attemptCount) &&
      Number(job.attemptCount) >= 0 &&
      Number.isSafeInteger(job.maximumAttempts) &&
      Number(job.maximumAttempts) >= 1 &&
      Number(job.maximumAttempts) <= 32 &&
      (job.retryAt === null ||
        (typeof job.retryAt === "string" &&
          Number.isFinite(Date.parse(job.retryAt)))));
  if (
    !Object.hasOwn(data, "failure") ||
    !Object.hasOwn(data, "job") ||
    typeof data.documentId !== "string" ||
    !uuidPattern.test(data.documentId) ||
    typeof data.uploadSessionId !== "string" ||
    !uuidPattern.test(data.uploadSessionId) ||
    (data.mediaKind !== "legal_document" &&
      data.mediaKind !== "signed_document") ||
    !statuses.includes(status) ||
    typeof data.retryable !== "boolean" ||
    data.retryable !== (status === "dead_letter") ||
    !validCompletedAt ||
    !validFailure ||
    !validJob ||
    (["queued", "running", "retry_wait", "dead_letter", "completed"].includes(
      status,
    ) &&
      job === null) ||
    (["dead_letter", "rejected"].includes(status) &&
      (failure === null ||
        (failure.classification === null && failure.code === null))) ||
    (status === "retry_wait" && job?.retryAt == null) ||
    (status !== "retry_wait" && job?.retryAt != null)
  ) {
    throw new TypeError("invalid_legal_original_status_response");
  }
  return {
    completedAt: data.completedAt as string | null,
    documentId: data.documentId.toLowerCase(),
    job:
      job === null
        ? null
        : {
            attemptCount: Number(job.attemptCount),
            id: String(job.id).toLowerCase(),
            maximumAttempts: Number(job.maximumAttempts),
            retryAt: job.retryAt as string | null,
          },
    mediaKind: data.mediaKind,
    retryable: data.retryable,
    status,
    uploadSessionId: data.uploadSessionId.toLowerCase(),
  };
}

export function legalOriginalStatusMessageKey(
  status: LegalOriginalProjectedStatus,
): LegalOriginalStatusMessageKey {
  switch (status) {
    case "awaiting_upload":
    case "queued":
      return "statusQueued";
    case "running":
      return "statusRunning";
    case "retry_wait":
      return "statusRetryWait";
    case "dead_letter":
      return "statusDeadLetter";
    case "rejected":
      return "statusRejected";
    case "completed":
      return "statusCompleted";
  }
}

export function legalOriginalStatusShouldPoll(
  status: LegalOriginalProjectedStatus,
): boolean {
  return ["awaiting_upload", "queued", "running", "retry_wait"].includes(
    status,
  );
}

export function legalOriginalReceiptStatus(
  status: LegalOriginalVerificationReceipt["jobStatus"],
): LegalOriginalProjectedStatus {
  switch (status) {
    case "queued":
      return "queued";
    case "running":
      return "running";
    case "retry_wait":
      return "retry_wait";
    case "dead_letter":
      return "dead_letter";
    case "succeeded":
      return "completed";
    case "cancelled":
      return "rejected";
  }
}

export function legalOriginalStorageUrl(
  supabaseUrl: string,
  intent: LegalOriginalUploadIntent,
): string {
  const segments = intent.upload.objectKey.split("/");
  if (
    segments.some(
      (segment) => segment.length === 0 || segment === "." || segment === "..",
    )
  ) {
    throw new TypeError("invalid_legal_original_object_key");
  }
  const encodedPath = [intent.upload.bucket, ...segments]
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  return `${supabaseUrl.replace(/\/$/u, "")}/storage/v1/object/${encodedPath}`;
}
