export const MAX_VEHICLE_PHOTO_BYTES = 20_000_000;

export const VEHICLE_PHOTO_ACCEPT =
  "image/jpeg,image/png,image/webp,image/heic,image/heif,.jpg,.jpeg,.png,.webp,.heic,.heif";

export type VehiclePhotoMimeType =
  "image/heic" | "image/heif" | "image/jpeg" | "image/png" | "image/webp";

export type VehiclePhotoValidationErrorCode =
  "file_empty" | "file_too_large" | "unsupported_file_type";

export interface VehiclePhotoFileDescriptor {
  readonly name: string;
  readonly size: number;
  readonly type: string;
}

export interface VehiclePhotoUploadIntent {
  readonly mediaId: string;
  readonly upload: Readonly<{
    readonly bucket: "media-private";
    readonly expiresAt: string;
    readonly objectKey: string;
    readonly requiresAuthenticatedSession: true;
  }>;
  readonly uploadSessionId: string;
}

export interface VehiclePhotoVerificationReceipt {
  readonly jobId: string;
  readonly jobStatus:
    | "cancelled"
    | "dead_letter"
    | "queued"
    | "retry_wait"
    | "running"
    | "succeeded";
  readonly mediaId: string;
  readonly uploadSessionId: string;
}

export type VehiclePhotoProjectedStatus =
  | "awaiting_upload"
  | "completed"
  | "dead_letter"
  | "queued"
  | "rejected"
  | "retry_wait"
  | "running";

export interface VehiclePhotoVerificationStatus {
  readonly completedAt: string | null;
  readonly job: Readonly<{
    readonly attemptCount: number;
    readonly id: string;
    readonly maximumAttempts: number;
    readonly retryAt: string | null;
  }> | null;
  readonly mediaId: string;
  readonly retryable: boolean;
  readonly status: VehiclePhotoProjectedStatus;
  readonly uploadSessionId: string;
}

export type VehiclePhotoStatusMessageKey =
  | "photoStatusCompleted"
  | "photoStatusDeadLetter"
  | "photoStatusQueued"
  | "photoStatusRejected"
  | "photoStatusRetryWait"
  | "photoStatusRunning";

export function vehiclePhotoCommandKey(
  cache: Map<string, string>,
  scope: string,
  payload: unknown,
  createKey: () => string = () => crypto.randomUUID(),
): string {
  const fingerprint = `${scope}:${JSON.stringify(payload)}`;
  const existing = cache.get(fingerprint);
  if (existing) return existing;
  const key = createKey();
  cache.set(fingerprint, key);
  return key;
}

export function clearVehiclePhotoCommandKey(
  cache: Map<string, string>,
  scope: string,
  payload: unknown,
): void {
  cache.delete(`${scope}:${JSON.stringify(payload)}`);
}

export function isVehiclePhotoUploadIntentExpired(
  intent: VehiclePhotoUploadIntent,
  now = Date.now(),
): boolean {
  return Date.parse(intent.upload.expiresAt) <= now;
}

const mimeTypes = new Set<VehiclePhotoMimeType>([
  "image/heic",
  "image/heif",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const emptyTypeByExtension: Readonly<Record<string, VehiclePhotoMimeType>> =
  Object.freeze({
    heic: "image/heic",
    heif: "image/heif",
    jpeg: "image/jpeg",
    jpg: "image/jpeg",
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
  if (!data) throw new TypeError("invalid_command_response");
  return data;
}

export function validateVehiclePhotoFile(file: VehiclePhotoFileDescriptor):
  | Readonly<{ readonly mimeType: VehiclePhotoMimeType; readonly valid: true }>
  | Readonly<{
      readonly code: VehiclePhotoValidationErrorCode;
      readonly valid: false;
    }> {
  if (!Number.isSafeInteger(file.size) || file.size < 1) {
    return { code: "file_empty", valid: false };
  }
  if (file.size > MAX_VEHICLE_PHOTO_BYTES) {
    return { code: "file_too_large", valid: false };
  }

  const declaredType = file.type.trim().toLowerCase();
  if (mimeTypes.has(declaredType as VehiclePhotoMimeType)) {
    return {
      mimeType: declaredType as VehiclePhotoMimeType,
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

export async function sha256Hex(blob: Blob): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    await blob.arrayBuffer(),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function parseVehiclePhotoUploadIntent(
  value: unknown,
): VehiclePhotoUploadIntent {
  const data = commandData(value);
  const upload = record(data.upload);
  if (
    typeof data.mediaId !== "string" ||
    !uuidPattern.test(data.mediaId) ||
    typeof data.uploadSessionId !== "string" ||
    !uuidPattern.test(data.uploadSessionId) ||
    !upload ||
    upload.bucket !== "media-private" ||
    typeof upload.expiresAt !== "string" ||
    !Number.isFinite(Date.parse(upload.expiresAt)) ||
    typeof upload.objectKey !== "string" ||
    upload.objectKey.length < 1 ||
    upload.objectKey.length > 1_000 ||
    upload.requiresAuthenticatedSession !== true
  ) {
    throw new TypeError("invalid_media_upload_intent_response");
  }
  return {
    mediaId: data.mediaId.toLowerCase(),
    upload: {
      bucket: "media-private",
      expiresAt: upload.expiresAt,
      objectKey: upload.objectKey,
      requiresAuthenticatedSession: true,
    },
    uploadSessionId: data.uploadSessionId.toLowerCase(),
  };
}

export function parseVehiclePhotoVerificationReceipt(
  value: unknown,
): VehiclePhotoVerificationReceipt {
  const data = commandData(value);
  const statuses = [
    "cancelled",
    "dead_letter",
    "queued",
    "retry_wait",
    "running",
    "succeeded",
  ] as const;
  if (
    typeof data.jobId !== "string" ||
    !uuidPattern.test(data.jobId) ||
    !statuses.includes(data.jobStatus as (typeof statuses)[number]) ||
    typeof data.mediaId !== "string" ||
    !uuidPattern.test(data.mediaId) ||
    typeof data.uploadSessionId !== "string" ||
    !uuidPattern.test(data.uploadSessionId)
  ) {
    throw new TypeError("invalid_media_verification_response");
  }
  return {
    jobId: data.jobId.toLowerCase(),
    jobStatus: data.jobStatus as VehiclePhotoVerificationReceipt["jobStatus"],
    mediaId: data.mediaId.toLowerCase(),
    uploadSessionId: data.uploadSessionId.toLowerCase(),
  };
}

export function parseVehiclePhotoVerificationStatus(
  value: unknown,
): VehiclePhotoVerificationStatus {
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
  const status = data.status as VehiclePhotoProjectedStatus;
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
  const exactData = Object.keys(data).every((key) =>
    [
      "completedAt",
      "failure",
      "job",
      "mediaId",
      "retryable",
      "status",
      "uploadSessionId",
    ].includes(key),
  );
  const exactFailure =
    failure === null ||
    Object.keys(failure).every((key) =>
      ["classification", "code"].includes(key),
    );
  const exactJob =
    job === null ||
    Object.keys(job).every((key) =>
      ["attemptCount", "id", "maximumAttempts", "retryAt"].includes(key),
    );
  if (
    !exactData ||
    !exactFailure ||
    !exactJob ||
    !Object.hasOwn(data, "failure") ||
    !Object.hasOwn(data, "job") ||
    typeof data.mediaId !== "string" ||
    !uuidPattern.test(data.mediaId) ||
    typeof data.uploadSessionId !== "string" ||
    !uuidPattern.test(data.uploadSessionId) ||
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
    throw new TypeError("invalid_media_verification_status_response");
  }
  return {
    completedAt: data.completedAt as string | null,
    job:
      job === null
        ? null
        : {
            attemptCount: Number(job.attemptCount),
            id: String(job.id).toLowerCase(),
            maximumAttempts: Number(job.maximumAttempts),
            retryAt: job.retryAt as string | null,
          },
    mediaId: data.mediaId.toLowerCase(),
    retryable: data.retryable,
    status,
    uploadSessionId: data.uploadSessionId.toLowerCase(),
  };
}

export function vehiclePhotoStatusMessageKey(
  status: VehiclePhotoProjectedStatus,
): VehiclePhotoStatusMessageKey {
  switch (status) {
    case "awaiting_upload":
    case "queued":
      return "photoStatusQueued";
    case "running":
      return "photoStatusRunning";
    case "retry_wait":
      return "photoStatusRetryWait";
    case "dead_letter":
      return "photoStatusDeadLetter";
    case "rejected":
      return "photoStatusRejected";
    case "completed":
      return "photoStatusCompleted";
  }
}

export function vehiclePhotoStatusShouldPoll(
  status: VehiclePhotoProjectedStatus,
): boolean {
  return ["awaiting_upload", "queued", "running", "retry_wait"].includes(
    status,
  );
}

export function vehiclePhotoStatusPollDelay(attempt: number): number {
  const boundedAttempt = Number.isSafeInteger(attempt)
    ? Math.min(Math.max(attempt, 0), 4)
    : 0;
  return 500 * 2 ** boundedAttempt;
}

export function vehiclePhotoReceiptStatus(
  status: VehiclePhotoVerificationReceipt["jobStatus"],
): VehiclePhotoProjectedStatus {
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

export function vehiclePhotoProjectedJobStatus(
  status: VehiclePhotoProjectedStatus,
): VehiclePhotoVerificationReceipt["jobStatus"] {
  switch (status) {
    case "awaiting_upload":
    case "queued":
      return "queued";
    case "running":
      return "running";
    case "retry_wait":
      return "retry_wait";
    case "dead_letter":
      return "dead_letter";
    case "completed":
      return "succeeded";
    case "rejected":
      return "cancelled";
  }
}

export function vehiclePhotoStorageUrl(
  supabaseUrl: string,
  intent: VehiclePhotoUploadIntent,
): string {
  const segments = intent.upload.objectKey.split("/");
  if (
    segments.some(
      (segment) => segment.length === 0 || segment === "." || segment === "..",
    )
  ) {
    throw new TypeError("invalid_media_upload_object_key");
  }
  const encodedPath = [intent.upload.bucket, ...segments]
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  return `${supabaseUrl.replace(/\/$/u, "")}/storage/v1/object/${encodedPath}`;
}
