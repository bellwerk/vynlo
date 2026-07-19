import { MediaPolicyError } from "./errors";
import { deepFreeze } from "./validation";

export const VEHICLE_RAW_RETENTION_DAYS = 7;

export const VEHICLE_RAW_RETENTION_POLICY = deepFreeze({
  kind: "delete_after_verified_master" as const,
  version: 1 as const,
  days: VEHICLE_RAW_RETENTION_DAYS,
});

export const LEGAL_ORIGINAL_RETENTION_POLICY = deepFreeze({
  kind: "preserve_original" as const,
  version: 1 as const,
});

export type OriginalFileClass = "vehicle_photo_raw" | "legal_document_original";

export type OriginalRetentionPlan =
  | Readonly<{
      fileClass: "vehicle_photo_raw";
      policy: typeof VEHICLE_RAW_RETENTION_POLICY;
      deleteAfter: string;
    }>
  | Readonly<{
      fileClass: "legal_document_original";
      policy: typeof LEGAL_ORIGINAL_RETENTION_POLICY;
      deleteAfter: null;
    }>;

function parseInstant(value: string | Date): Date {
  const date =
    value instanceof Date ? new Date(value.getTime()) : new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new MediaPolicyError("invalid_retention_time");
  }
  return date;
}

export function planOriginalRetention(input: {
  readonly fileClass: OriginalFileClass;
  readonly verifiedMasterAt?: string | Date;
}): OriginalRetentionPlan {
  if (input.fileClass === "legal_document_original") {
    return deepFreeze({
      fileClass: input.fileClass,
      policy: LEGAL_ORIGINAL_RETENTION_POLICY,
      deleteAfter: null,
    });
  }

  if (input.verifiedMasterAt === undefined) {
    throw new MediaPolicyError("invalid_retention_time");
  }
  const verifiedMasterAt = parseInstant(input.verifiedMasterAt);
  verifiedMasterAt.setUTCDate(
    verifiedMasterAt.getUTCDate() + VEHICLE_RAW_RETENTION_DAYS,
  );
  return deepFreeze({
    fileClass: input.fileClass,
    policy: VEHICLE_RAW_RETENTION_POLICY,
    deleteAfter: verifiedMasterAt.toISOString(),
  });
}

export function assertOriginalDeletionDue(input: {
  readonly plan: OriginalRetentionPlan;
  readonly now: string | Date;
  readonly verifiedMasterAvailable: boolean;
  readonly retentionHold: boolean;
}): void {
  if (
    input.plan.fileClass !== "vehicle_photo_raw" ||
    input.plan.deleteAfter === null ||
    !input.verifiedMasterAvailable ||
    input.retentionHold
  ) {
    throw new MediaPolicyError("retention_prohibited");
  }

  const now = parseInstant(input.now);
  const deleteAfter = parseInstant(input.plan.deleteAfter);
  if (now.getTime() < deleteAfter.getTime()) {
    throw new MediaPolicyError("retention_prohibited");
  }
}
