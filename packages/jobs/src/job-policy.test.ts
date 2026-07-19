import { describe, expect, it } from "vitest";

import {
  DEFAULT_MAX_JOB_ATTEMPTS,
  calculateRetryDelaySeconds,
  canTransitionJobStatus,
  evaluateJobLease,
  findProhibitedJobPayloadKey,
  isRetryableJobError,
  planJobFailure,
} from "./job-policy";

describe("VYN-JOB-001 job lifecycle", () => {
  it("T-JOB-003 permits only the normative state transitions", () => {
    expect(canTransitionJobStatus("queued", "running")).toBe(true);
    expect(canTransitionJobStatus("queued", "cancelled")).toBe(true);
    expect(canTransitionJobStatus("running", "retry_wait")).toBe(true);
    expect(canTransitionJobStatus("running", "succeeded")).toBe(true);
    expect(canTransitionJobStatus("running", "dead_letter")).toBe(true);
    expect(canTransitionJobStatus("retry_wait", "running")).toBe(true);
    expect(canTransitionJobStatus("retry_wait", "cancelled")).toBe(true);
    expect(canTransitionJobStatus("succeeded", "running")).toBe(false);
    expect(canTransitionJobStatus("dead_letter", "running")).toBe(false);
  });

  it("T-JOB-003 classifies retryable and permanent failures", () => {
    expect(isRetryableJobError("transient")).toBe(true);
    expect(isRetryableJobError("rate_limited")).toBe(true);
    expect(isRetryableJobError("unknown")).toBe(true);
    expect(isRetryableJobError("lease_expired")).toBe(true);
    expect(isRetryableJobError("validation")).toBe(false);
    expect(isRetryableJobError("permission")).toBe(false);
    expect(isRetryableJobError("provider_auth")).toBe(false);
    expect(isRetryableJobError("permanent")).toBe(false);
  });
});

describe("VYN-JOB-001 retry policy", () => {
  it("T-JOB-003 applies capped exponential backoff with equal jitter", () => {
    expect(
      calculateRetryDelaySeconds({
        failedAttemptNumber: 1,
        baseDelaySeconds: 30,
        maximumDelaySeconds: 3_600,
        jitterUnit: 0,
      }),
    ).toBe(15);
    expect(
      calculateRetryDelaySeconds({
        failedAttemptNumber: 3,
        baseDelaySeconds: 30,
        maximumDelaySeconds: 3_600,
        jitterUnit: 0.5,
      }),
    ).toBe(90);
    expect(
      calculateRetryDelaySeconds({
        failedAttemptNumber: 32,
        baseDelaySeconds: 30,
        maximumDelaySeconds: 3_600,
        jitterUnit: 0.999,
      }),
    ).toBeLessThanOrEqual(3_600);
  });

  it("T-JOB-003 honors provider retry-after without exceeding the attempt budget", () => {
    expect(
      planJobFailure({
        classification: "rate_limited",
        failedAttemptNumber: 2,
        jitterUnit: 0,
        providerRetryAfterSeconds: 600,
      }),
    ).toEqual({
      status: "retry_wait",
      retryDelaySeconds: 600,
      reviewRequired: false,
    });

    expect(
      planJobFailure({
        classification: "transient",
        failedAttemptNumber: DEFAULT_MAX_JOB_ATTEMPTS,
        jitterUnit: 0,
      }),
    ).toEqual({
      status: "dead_letter",
      retryDelaySeconds: null,
      reviewRequired: true,
    });
  });

  it("T-JOB-003 dead-letters non-retryable failures immediately", () => {
    for (const classification of [
      "validation",
      "permission",
      "provider_auth",
      "permanent",
    ] as const) {
      expect(
        planJobFailure({
          classification,
          failedAttemptNumber: 1,
          jitterUnit: 0.25,
        }),
      ).toEqual({
        status: "dead_letter",
        retryDelaySeconds: null,
        reviewRequired: true,
      });
    }
  });

  it("T-JOB-003 rejects invalid retry inputs", () => {
    expect(() =>
      calculateRetryDelaySeconds({
        failedAttemptNumber: 0,
        baseDelaySeconds: 30,
        maximumDelaySeconds: 3_600,
        jitterUnit: 0,
      }),
    ).toThrow(RangeError);
    expect(() =>
      calculateRetryDelaySeconds({
        failedAttemptNumber: 1,
        baseDelaySeconds: 30,
        maximumDelaySeconds: 3_600,
        jitterUnit: 1,
      }),
    ).toThrow(RangeError);
  });
});

describe("VYN-JOB-001 worker lease", () => {
  const lease = {
    workerId: "worker-a",
    leaseToken: "lease-a",
    heartbeatAtMs: 1_000,
    expiresAtMs: 61_000,
  } as const;

  it("T-JOB-002 authorizes only the live lease owner", () => {
    expect(evaluateJobLease(lease, "worker-a", "lease-a", 60_999)).toEqual({
      allowed: true,
      reason: "active_lease",
    });
    expect(evaluateJobLease(lease, "worker-b", "lease-a", 2_000)).toEqual({
      allowed: false,
      reason: "wrong_worker",
    });
    expect(evaluateJobLease(lease, "worker-a", "lease-b", 2_000)).toEqual({
      allowed: false,
      reason: "wrong_lease_token",
    });
  });

  it("T-JOB-002 expires the lease at the exact boundary", () => {
    expect(evaluateJobLease(lease, "worker-a", "lease-a", 61_000)).toEqual({
      allowed: false,
      reason: "expired_lease",
    });
  });
});

describe("VYN-JOB-001 payload safety", () => {
  it("T-JOB-001 rejects nested credential-bearing payload keys", () => {
    expect(
      findProhibitedJobPayloadKey({
        entityId: "entity-1",
        adapter: { access_token: "not-a-real-secret" },
      }),
    ).toBe("access_token");
    expect(findProhibitedJobPayloadKey([{ privateKey: "fixture" }])).toBe(
      "privateKey",
    );
  });

  it("T-JOB-001 accepts minimized tenant-neutral payloads", () => {
    expect(
      findProhibitedJobPayloadKey({
        entityId: "entity-1",
        payloadVersion: 1,
        locale: "fr-CA",
        fields: ["title", "status"],
      }),
    ).toBeNull();
  });
});
