export const JOB_STATUSES = [
  "queued",
  "running",
  "retry_wait",
  "succeeded",
  "dead_letter",
  "cancelled",
] as const;

export type JobStatus = (typeof JOB_STATUSES)[number];

export const JOB_ERROR_CLASSIFICATIONS = [
  "transient",
  "rate_limited",
  "permanent",
  "validation",
  "permission",
  "provider_auth",
  "unknown",
  "lease_expired",
] as const;

export type JobErrorClassification = (typeof JOB_ERROR_CLASSIFICATIONS)[number];

export const DEFAULT_MAX_JOB_ATTEMPTS = 8;
export const MAX_JOB_ATTEMPTS = 32;
export const DEFAULT_BACKOFF_BASE_SECONDS = 30;
export const DEFAULT_BACKOFF_MAX_SECONDS = 3_600;

const allowedTransitions: Readonly<Record<JobStatus, ReadonlySet<JobStatus>>> =
  Object.freeze({
    queued: new Set<JobStatus>(["running", "cancelled"]),
    running: new Set<JobStatus>(["succeeded", "retry_wait", "dead_letter"]),
    retry_wait: new Set<JobStatus>(["running", "dead_letter", "cancelled"]),
    succeeded: new Set<JobStatus>(),
    dead_letter: new Set<JobStatus>(),
    cancelled: new Set<JobStatus>(),
  });

export function canTransitionJobStatus(
  from: JobStatus,
  to: JobStatus,
): boolean {
  return allowedTransitions[from].has(to);
}

export function isRetryableJobError(
  classification: JobErrorClassification,
): boolean {
  return ["transient", "rate_limited", "unknown", "lease_expired"].includes(
    classification,
  );
}

function requireIntegerInRange(
  value: number,
  minimum: number,
  maximum: number,
  label: string,
): void {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(
      `${label} must be an integer from ${minimum} to ${maximum}`,
    );
  }
}

/**
 * Calculates capped exponential backoff with equal jitter.
 *
 * `jitterUnit` is injected so workers can use secure randomness while tests stay
 * deterministic. The result is always in `[cap / 2, cap)` and never exceeds
 * the configured maximum.
 */
export function calculateRetryDelaySeconds(input: {
  readonly failedAttemptNumber: number;
  readonly baseDelaySeconds: number;
  readonly maximumDelaySeconds: number;
  readonly jitterUnit: number;
}): number {
  requireIntegerInRange(
    input.failedAttemptNumber,
    1,
    MAX_JOB_ATTEMPTS,
    "failedAttemptNumber",
  );
  requireIntegerInRange(input.baseDelaySeconds, 1, 3_600, "baseDelaySeconds");
  requireIntegerInRange(
    input.maximumDelaySeconds,
    input.baseDelaySeconds,
    86_400,
    "maximumDelaySeconds",
  );
  if (
    !Number.isFinite(input.jitterUnit) ||
    input.jitterUnit < 0 ||
    input.jitterUnit >= 1
  ) {
    throw new RangeError("jitterUnit must be in [0, 1)");
  }

  const delayCap = Math.min(
    input.maximumDelaySeconds,
    input.baseDelaySeconds * 2 ** (input.failedAttemptNumber - 1),
  );

  return Math.max(
    1,
    Math.floor(delayCap / 2 + (delayCap / 2) * input.jitterUnit),
  );
}

export type FailureDisposition =
  | Readonly<{
      status: "retry_wait";
      retryDelaySeconds: number;
      reviewRequired: false;
    }>
  | Readonly<{
      status: "dead_letter";
      retryDelaySeconds: null;
      reviewRequired: true;
    }>;

export function planJobFailure(input: {
  readonly classification: JobErrorClassification;
  readonly failedAttemptNumber: number;
  readonly maximumAttempts?: number;
  readonly baseDelaySeconds?: number;
  readonly maximumDelaySeconds?: number;
  readonly jitterUnit: number;
  readonly providerRetryAfterSeconds?: number;
}): FailureDisposition {
  const maximumAttempts = input.maximumAttempts ?? DEFAULT_MAX_JOB_ATTEMPTS;
  requireIntegerInRange(
    maximumAttempts,
    1,
    MAX_JOB_ATTEMPTS,
    "maximumAttempts",
  );
  requireIntegerInRange(
    input.failedAttemptNumber,
    1,
    maximumAttempts,
    "failedAttemptNumber",
  );

  if (
    !isRetryableJobError(input.classification) ||
    input.failedAttemptNumber >= maximumAttempts
  ) {
    return {
      status: "dead_letter",
      retryDelaySeconds: null,
      reviewRequired: true,
    };
  }

  let retryDelaySeconds = calculateRetryDelaySeconds({
    failedAttemptNumber: input.failedAttemptNumber,
    baseDelaySeconds: input.baseDelaySeconds ?? DEFAULT_BACKOFF_BASE_SECONDS,
    maximumDelaySeconds:
      input.maximumDelaySeconds ?? DEFAULT_BACKOFF_MAX_SECONDS,
    jitterUnit: input.jitterUnit,
  });

  if (input.providerRetryAfterSeconds !== undefined) {
    requireIntegerInRange(
      input.providerRetryAfterSeconds,
      1,
      86_400,
      "providerRetryAfterSeconds",
    );
    retryDelaySeconds = Math.max(
      retryDelaySeconds,
      input.providerRetryAfterSeconds,
    );
  }

  return {
    status: "retry_wait",
    retryDelaySeconds,
    reviewRequired: false,
  };
}

export interface JobLease {
  readonly workerId: string;
  readonly leaseToken: string;
  readonly heartbeatAtMs: number;
  readonly expiresAtMs: number;
}

export type LeaseDecision =
  | Readonly<{ allowed: true; reason: "active_lease" }>
  | Readonly<{
      allowed: false;
      reason:
        | "invalid_lease"
        | "wrong_worker"
        | "wrong_lease_token"
        | "expired_lease";
    }>;

export function evaluateJobLease(
  lease: JobLease,
  workerId: string,
  leaseToken: string,
  nowMs: number,
): LeaseDecision {
  if (
    !lease.workerId ||
    !lease.leaseToken ||
    !Number.isFinite(lease.heartbeatAtMs) ||
    !Number.isFinite(lease.expiresAtMs) ||
    !Number.isFinite(nowMs) ||
    lease.heartbeatAtMs < 0 ||
    lease.expiresAtMs <= lease.heartbeatAtMs
  ) {
    return { allowed: false, reason: "invalid_lease" };
  }

  if (lease.workerId !== workerId) {
    return { allowed: false, reason: "wrong_worker" };
  }

  if (lease.leaseToken !== leaseToken) {
    return { allowed: false, reason: "wrong_lease_token" };
  }

  if (nowMs >= lease.expiresAtMs) {
    return { allowed: false, reason: "expired_lease" };
  }

  return { allowed: true, reason: "active_lease" };
}

const prohibitedPayloadKey =
  /(password|secret|token|apikey|credential|authorization|cookie|privatekey)/u;

function normalizedPayloadKey(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/gu, "");
}

/** Returns the first prohibited credential-bearing key, including nested keys. */
export function findProhibitedJobPayloadKey(value: unknown): string | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const prohibited = findProhibitedJobPayloadKey(item);
      if (prohibited !== null) {
        return prohibited;
      }
    }
    return null;
  }

  if (typeof value !== "object" || value === null) {
    return null;
  }

  for (const [key, item] of Object.entries(value)) {
    if (prohibitedPayloadKey.test(normalizedPayloadKey(key))) {
      return key;
    }
    const nested = findProhibitedJobPayloadKey(item);
    if (nested !== null) {
      return nested;
    }
  }

  return null;
}
