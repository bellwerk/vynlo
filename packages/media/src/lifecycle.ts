import { MediaPolicyError } from "./errors";
import type { VehiclePhotoProcessingSource } from "./job-contract";
import {
  deepFreeze,
  requirePositiveSafeInteger,
  requireUuid,
} from "./validation";

export const VEHICLE_MEDIA_STATUSES = [
  "awaiting_upload",
  "quarantined",
  "processing",
  "ready",
  "failed",
  "archived",
] as const;

export type VehicleMediaStatus = (typeof VEHICLE_MEDIA_STATUSES)[number];

const allowedTransitions: Readonly<
  Record<VehicleMediaStatus, ReadonlySet<VehicleMediaStatus>>
> = Object.freeze({
  awaiting_upload: new Set<VehicleMediaStatus>(["quarantined", "archived"]),
  quarantined: new Set<VehicleMediaStatus>([
    "processing",
    "failed",
    "archived",
  ]),
  processing: new Set<VehicleMediaStatus>(["ready", "failed", "archived"]),
  ready: new Set<VehicleMediaStatus>(["processing", "archived"]),
  failed: new Set<VehicleMediaStatus>(["processing", "archived"]),
  archived: new Set<VehicleMediaStatus>(),
});

export function canTransitionVehicleMediaStatus(
  from: VehicleMediaStatus,
  to: VehicleMediaStatus,
): boolean {
  return allowedTransitions[from].has(to);
}

export function assertVehicleMediaTransition(
  from: VehicleMediaStatus,
  to: VehicleMediaStatus,
): void {
  if (!canTransitionVehicleMediaStatus(from, to)) {
    throw new MediaPolicyError("invalid_media_transition");
  }
}

export type MediaProcessingFailureClassification =
  | "transient"
  | "rate_limited"
  | "unknown"
  | "lease_expired"
  | "validation"
  | "permission"
  | "provider_auth"
  | "permanent";

export type MediaProcessingFailurePlan =
  | Readonly<{
      disposition: "retry";
      mediaStatus: "processing";
      recordTerminalFailure: false;
    }>
  | Readonly<{
      disposition: "terminal_failure";
      mediaStatus: "failed";
      recordTerminalFailure: true;
    }>;

export function planMediaProcessingFailure(input: {
  readonly classification: MediaProcessingFailureClassification;
  readonly failedAttemptNumber: number;
  readonly maximumAttempts: number;
}): MediaProcessingFailurePlan {
  const maximumAttempts = requirePositiveSafeInteger(
    input.maximumAttempts,
    "retry_not_allowed",
  );
  const failedAttemptNumber = requirePositiveSafeInteger(
    input.failedAttemptNumber,
    "retry_not_allowed",
  );
  if (maximumAttempts > 32 || failedAttemptNumber > maximumAttempts) {
    throw new MediaPolicyError("retry_not_allowed");
  }

  const retryable = [
    "transient",
    "rate_limited",
    "unknown",
    "lease_expired",
  ].includes(input.classification);
  if (retryable && failedAttemptNumber < maximumAttempts) {
    return deepFreeze({
      disposition: "retry",
      mediaStatus: "processing",
      recordTerminalFailure: false,
    });
  }
  return deepFreeze({
    disposition: "terminal_failure",
    mediaStatus: "failed",
    recordTerminalFailure: true,
  });
}

export interface VehiclePhotoReprocessPlan {
  readonly nextGeneration: number;
  readonly nextMediaVersion: number;
  readonly nextStatus: "processing";
  readonly source: VehiclePhotoProcessingSource;
}

export function planVehiclePhotoReprocess(input: {
  readonly status: VehicleMediaStatus;
  readonly currentMediaVersion: number;
  readonly expectedMediaVersion: number;
  readonly currentGeneration: number;
  readonly source: VehiclePhotoProcessingSource;
}): VehiclePhotoReprocessPlan {
  if (input.status !== "failed" && input.status !== "ready") {
    throw new MediaPolicyError("reprocess_not_allowed");
  }
  const currentMediaVersion = requirePositiveSafeInteger(
    input.currentMediaVersion,
    "stale_media_version",
  );
  const expectedMediaVersion = requirePositiveSafeInteger(
    input.expectedMediaVersion,
    "stale_media_version",
  );
  if (currentMediaVersion !== expectedMediaVersion) {
    throw new MediaPolicyError("stale_media_version");
  }
  const currentGeneration = requirePositiveSafeInteger(
    input.currentGeneration,
    "reprocess_not_allowed",
  );
  if (input.status === "ready" && input.source.kind === "upload_session") {
    throw new MediaPolicyError("reprocess_not_allowed");
  }
  if (
    currentMediaVersion === Number.MAX_SAFE_INTEGER ||
    currentGeneration === Number.MAX_SAFE_INTEGER ||
    (input.source.kind !== "upload_session" &&
      input.source.kind !== "media_file")
  ) {
    throw new MediaPolicyError("reprocess_not_allowed");
  }

  return deepFreeze({
    nextGeneration: currentGeneration + 1,
    nextMediaVersion: currentMediaVersion + 1,
    nextStatus: "processing",
    source: {
      kind: input.source.kind,
      id: requireUuid(input.source.id, "reprocess_not_allowed"),
    },
  });
}
