// Stable test IDs: T-JOB-002, T-JOB-003.
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  createInvitationDeliveryJobHandler,
  type InvitationDeliveryProvider,
  type InvitationDeliveryRepository,
} from "./invitation-delivery-handler";
import type { ClaimedJob, DurableJobStore } from "./job-store";
import {
  DurableJobRunner,
  JobExecutionError,
  type JobHandler,
} from "./job-runner";

function claimedJob(overrides: Partial<ClaimedJob> = {}): ClaimedJob {
  return {
    attemptNumber: 1,
    causationId: null,
    correlationId: "00000000-0000-4000-8000-000000000010",
    entityId: "00000000-0000-4000-8000-000000000020",
    entityType: "document_preview",
    idempotencyKey: "preview-job-request-1",
    jobId: "00000000-0000-4000-8000-000000000030",
    jobType: "documents.render_preview",
    leaseExpiresAt: "2026-07-16T12:01:00.000Z",
    leaseToken: "00000000-0000-4000-8000-000000000040",
    maximumAttempts: 8,
    outboxEventId: "00000000-0000-4000-8000-000000000050",
    payload: { previewRequestId: "preview-1" },
    payloadSchemaVersion: 1,
    workspaceId: "00000000-0000-4000-8000-000000000060",
    ...overrides,
  };
}

function jobStore(job: ClaimedJob): DurableJobStore {
  return {
    claimJobs: vi.fn(async () => [job]),
    completeJob: vi.fn(async () => undefined),
    failJob: vi.fn(async () => undefined),
    heartbeatJob: vi.fn(async () => "2026-07-16T12:02:00.000Z"),
    reclaimExpiredJobs: vi.fn(async () => 0),
  };
}

const logger = { info: vi.fn() };

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((promiseResolve, promiseReject) => {
    resolve = promiseResolve;
    reject = promiseReject;
  });
  return { promise, reject, resolve } as const;
}

afterEach(() => {
  vi.clearAllMocks();
  vi.useRealTimers();
});

describe("DurableJobRunner", () => {
  it("completes a claimed job with a safe bounded result summary", async () => {
    const job = claimedJob();
    const store = jobStore(job);
    const handler: JobHandler = vi.fn(async () => ({
      summary: { checksum: "abc123", pageCount: 1 },
    }));
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, handler]]),
      logger,
      store,
      workerId: "worker-a",
    });

    await expect(runner.runBatch()).resolves.toBe(1);
    expect(store.heartbeatJob).not.toHaveBeenCalled();
    expect(store.completeJob).toHaveBeenCalledWith(
      expect.objectContaining({
        jobId: job.jobId,
        resultSummary: { checksum: "abc123", pageCount: 1 },
      }),
    );
    expect(store.failJob).not.toHaveBeenCalled();
  });

  it("renews the lease while a long handler is still running", async () => {
    vi.useFakeTimers();
    const job = claimedJob();
    const store = jobStore(job);
    const handlerResult = deferred<void>();
    const handler: JobHandler = vi.fn(() => handlerResult.promise);
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, handler]]),
      heartbeatIntervalMs: 100,
      logger,
      store,
      workerId: "worker-a",
    });

    const run = runner.runBatch();
    await vi.advanceTimersByTimeAsync(100);

    expect(store.heartbeatJob).toHaveBeenCalledOnce();
    expect(store.completeJob).not.toHaveBeenCalled();

    handlerResult.resolve();
    await expect(run).resolves.toBe(1);
    expect(store.completeJob).toHaveBeenCalledOnce();

    await vi.advanceTimersByTimeAsync(1_000);
    expect(store.heartbeatJob).toHaveBeenCalledOnce();
  });

  it("aborts the handler and schedules a safe retry when heartbeat fails", async () => {
    vi.useFakeTimers();
    const job = claimedJob();
    const store = jobStore(job);
    vi.mocked(store.heartbeatJob).mockRejectedValueOnce(
      new Error("untrusted transport response"),
    );
    let receivedSignal: AbortSignal | undefined;
    const handler: JobHandler = vi.fn(
      (_job, context) =>
        new Promise<void>((_resolve, reject) => {
          receivedSignal = context.signal;
          context.signal.addEventListener(
            "abort",
            () => reject(context.signal.reason),
            { once: true },
          );
        }),
    );
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, handler]]),
      heartbeatIntervalMs: 100,
      logger,
      store,
      workerId: "worker-a",
    });

    const run = runner.runBatch();
    await vi.advanceTimersByTimeAsync(100);
    await expect(run).resolves.toBe(1);

    expect(receivedSignal?.aborted).toBe(true);
    expect(store.completeJob).not.toHaveBeenCalled();
    expect(store.failJob).toHaveBeenCalledWith(
      expect.objectContaining({
        classification: "transient",
        errorCode: "worker.heartbeat_failed",
        errorDetailSafe: "The worker could not renew its active job lease.",
      }),
    );
    expect(JSON.stringify(vi.mocked(store.failJob).mock.calls)).not.toContain(
      "transport response",
    );
  });

  it("records heartbeat failure after a bounded grace period when a handler ignores cancellation", async () => {
    vi.useFakeTimers();
    const job = claimedJob();
    const store = jobStore(job);
    vi.mocked(store.heartbeatJob).mockRejectedValueOnce(
      new Error("untrusted heartbeat response"),
    );
    const handler: JobHandler = vi.fn(() => new Promise<void>(() => undefined));
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, handler]]),
      handlerSettlementGraceMs: 100,
      heartbeatIntervalMs: 100,
      logger,
      store,
      workerId: "worker-a",
    });

    const run = runner.runBatch();
    await vi.advanceTimersByTimeAsync(200);
    await expect(run).resolves.toBe(1);
    expect(store.failJob).toHaveBeenCalledWith(
      expect.objectContaining({
        errorCode: "worker.heartbeat_failed",
      }),
    );
    expect(logger.info).toHaveBeenCalledWith(
      "job handler ignored cancellation grace period",
      expect.objectContaining({ gracePeriodMs: 100 }),
    );
  });

  it("aborts a stalled heartbeat before the lease can expire", async () => {
    vi.useFakeTimers();
    const job = claimedJob();
    const store = jobStore(job);
    let heartbeatSignal: AbortSignal | undefined;
    vi.mocked(store.heartbeatJob).mockImplementationOnce(
      (input) =>
        new Promise<string>(() => {
          heartbeatSignal = input.signal;
        }),
    );
    const handler: JobHandler = vi.fn(
      (_job, context) =>
        new Promise<void>((_resolve, reject) => {
          context.signal.addEventListener(
            "abort",
            () => reject(context.signal.reason),
            { once: true },
          );
        }),
    );
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, handler]]),
      handlerSettlementGraceMs: 100,
      heartbeatIntervalMs: 100,
      heartbeatTimeoutMs: 100,
      leaseSeconds: 5,
      logger,
      store,
      workerId: "worker-a",
    });

    const run = runner.runBatch();
    await vi.advanceTimersByTimeAsync(200);
    await expect(run).resolves.toBe(1);

    expect(heartbeatSignal?.aborted).toBe(true);
    expect(store.completeJob).not.toHaveBeenCalled();
    expect(store.failJob).toHaveBeenCalledWith(
      expect.objectContaining({
        classification: "transient",
        errorCode: "worker.heartbeat_failed",
      }),
    );
  });

  it("never overlaps heartbeats and drains an in-flight renewal before completion", async () => {
    vi.useFakeTimers();
    const job = claimedJob();
    const store = jobStore(job);
    const handlerResult = deferred<void>();
    const heartbeatResult = deferred<string>();
    let inFlight = 0;
    let maximumInFlight = 0;
    vi.mocked(store.heartbeatJob).mockImplementationOnce(async () => {
      inFlight += 1;
      maximumInFlight = Math.max(maximumInFlight, inFlight);
      const value = await heartbeatResult.promise;
      inFlight -= 1;
      return value;
    });
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, () => handlerResult.promise]]),
      heartbeatIntervalMs: 100,
      heartbeatTimeoutMs: 1_000,
      logger,
      store,
      workerId: "worker-a",
    });

    const run = runner.runBatch();
    await vi.advanceTimersByTimeAsync(500);

    expect(store.heartbeatJob).toHaveBeenCalledOnce();
    expect(maximumInFlight).toBe(1);

    handlerResult.resolve();
    await Promise.resolve();
    expect(store.completeJob).not.toHaveBeenCalled();

    heartbeatResult.resolve("2026-07-16T12:02:00.000Z");
    await expect(run).resolves.toBe(1);
    expect(store.completeJob).toHaveBeenCalledOnce();
    expect(maximumInFlight).toBe(1);
  });

  it("persists a classified safe failure without leaking the thrown error", async () => {
    const job = claimedJob();
    const store = jobStore(job);
    const handler: JobHandler = vi.fn(async () => {
      throw new Error("untrusted provider response");
    });
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, handler]]),
      logger,
      store,
      workerId: "worker-a",
    });

    await runner.runBatch();

    expect(store.failJob).toHaveBeenCalledWith(
      expect.objectContaining({
        classification: "unknown",
        errorCode: "worker.unhandled_failure",
        errorDetailSafe: "The handler failed without a safe classified error.",
      }),
    );
    expect(JSON.stringify(vi.mocked(store.failJob).mock.calls)).not.toContain(
      "provider response",
    );
  });

  it("persists invitation provider failure without logging invited identity", async () => {
    const invitationId = "00000000-0000-4000-8000-000000000070";
    const workspaceId = "00000000-0000-4000-8000-000000000060";
    const job = claimedJob({
      entityId: invitationId,
      entityType: "workspace_invitation",
      jobType: "auth.invitation.deliver",
      payload: { invitation_id: invitationId },
      workspaceId,
    });
    const store = jobStore(job);
    const repository: InvitationDeliveryRepository = {
      readDeliveryJob: vi.fn(async () => ({
        email: "private-invitee@example.test",
        expiresAt: "2026-07-17T12:00:00.000Z",
        invitationId,
        providerIdentityExists: false,
        requestedLocale: "en-CA",
        workspaceId,
      })),
    };
    const provider: InvitationDeliveryProvider = {
      deliver: vi.fn(async () => {
        throw new JobExecutionError({
          classification: "transient",
          code: "auth.invitation_provider_temporarily_unavailable",
          safeDetail: "The identity provider is temporarily unavailable.",
        });
      }),
    };
    const invitationLogger = { info: vi.fn() };
    const handler = createInvitationDeliveryJobHandler({
      provider,
      repository,
      workerId: "worker-a",
    });
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, handler]]),
      logger: invitationLogger,
      store,
      workerId: "worker-a",
    });

    await runner.runBatch();

    expect(store.failJob).toHaveBeenCalledWith(
      expect.objectContaining({
        classification: "transient",
        errorCode: "auth.invitation_provider_temporarily_unavailable",
      }),
    );
    expect(JSON.stringify(invitationLogger.info.mock.calls)).not.toContain(
      "private-invitee@example.test",
    );
    expect(JSON.stringify(invitationLogger.info.mock.calls)).not.toContain(
      "invitation_id",
    );
  });

  it("completes an invitation job with only the safe delivery receipt", async () => {
    const invitationId = "00000000-0000-4000-8000-000000000071";
    const workspaceId = "00000000-0000-4000-8000-000000000060";
    const job = claimedJob({
      entityId: invitationId,
      entityType: "workspace_invitation",
      jobType: "auth.invitation.deliver",
      payload: { invitation_id: invitationId },
      workspaceId,
    });
    const store = jobStore(job);
    const repository: InvitationDeliveryRepository = {
      readDeliveryJob: vi.fn(async () => ({
        email: "private-invitee@example.test",
        expiresAt: "2026-07-17T12:00:00.000Z",
        invitationId,
        providerIdentityExists: false,
        requestedLocale: "fr-CA",
        workspaceId,
      })),
    };
    const provider: InvitationDeliveryProvider = {
      deliver: vi.fn(async () => ({
        providerRequestId: "provider-request-safe-1",
      })),
    };
    const invitationLogger = { info: vi.fn() };
    const handler = createInvitationDeliveryJobHandler({
      provider,
      repository,
      workerId: "worker-a",
    });
    const runner = new DurableJobRunner({
      handlers: new Map([[job.jobType, handler]]),
      logger: invitationLogger,
      store,
      workerId: "worker-a",
    });

    await runner.runBatch();

    expect(store.completeJob).toHaveBeenCalledWith({
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      providerRequestId: "provider-request-safe-1",
      resultSummary: {
        delivery_outcome: "submitted",
        invitation_id: invitationId,
      },
      workerId: "worker-a",
    });
    expect(store.failJob).not.toHaveBeenCalled();
    expect(
      JSON.stringify([
        invitationLogger.info.mock.calls,
        vi.mocked(store.completeJob).mock.calls,
      ]),
    ).not.toContain("private-invitee@example.test");
  });

  it("rejects credential-like persisted failure detail", () => {
    expect(
      () =>
        new JobExecutionError({
          classification: "permanent",
          code: "provider.invalid_response",
          safeDetail: "Authorization data was rejected.",
        }),
    ).toThrow(/not safe/u);
  });

  it("dead-letters a missing handler as a permanent operational defect", async () => {
    const job = claimedJob();
    const store = jobStore(job);
    const runner = new DurableJobRunner({
      handlers: new Map(),
      logger,
      store,
      workerId: "worker-a",
    });

    await runner.runBatch();

    expect(store.failJob).toHaveBeenCalledWith(
      expect.objectContaining({
        classification: "permanent",
        errorCode: "worker.handler_not_registered",
      }),
    );
  });

  it("claims heavy media work in a bounded lane without blocking lightweight jobs", async () => {
    const mediaJobs = Array.from({ length: 5 }, (_, index) =>
      claimedJob({
        jobId: `00000000-0000-4000-8000-${String(index + 100).padStart(12, "0")}`,
        jobType: "media.process_vehicle_photo",
      }),
    );
    const lightweightJobs = Array.from({ length: 4 }, (_, index) =>
      claimedJob({
        jobId: `00000000-0000-4000-8000-${String(index + 200).padStart(12, "0")}`,
        jobType: "documents.render_preview",
      }),
    );
    const releaseMedia = deferred<void>();
    let activeMedia = 0;
    let maximumActiveMedia = 0;
    const mediaHandler: JobHandler = vi.fn(async () => {
      activeMedia += 1;
      maximumActiveMedia = Math.max(maximumActiveMedia, activeMedia);
      await releaseMedia.promise;
      activeMedia -= 1;
    });
    const lightweightHandler: JobHandler = vi.fn(async () => undefined);
    const store: DurableJobStore = {
      claimJobs: vi.fn(async (input) =>
        (input.jobTypes.includes("media.process_vehicle_photo")
          ? mediaJobs
          : lightweightJobs
        ).slice(0, input.limit),
      ),
      completeJob: vi.fn(async () => undefined),
      failJob: vi.fn(async () => undefined),
      heartbeatJob: vi.fn(async () => "2026-07-16T12:02:00.000Z"),
      reclaimExpiredJobs: vi.fn(async () => 0),
    };
    const runner = new DurableJobRunner({
      executionLanes: [
        {
          jobTypes: ["documents.render_preview"],
          maximumConcurrency: 10,
        },
        {
          jobTypes: ["media.process_vehicle_photo"],
          maximumConcurrency: 2,
        },
      ],
      handlers: new Map([
        ["documents.render_preview", lightweightHandler],
        ["media.process_vehicle_photo", mediaHandler],
      ]),
      logger,
      store,
      workerId: "worker-a",
    });

    const run = runner.runBatch(10);
    await vi.waitFor(() => {
      expect(mediaHandler).toHaveBeenCalledTimes(2);
      expect(lightweightHandler).toHaveBeenCalledTimes(4);
    });
    expect(maximumActiveMedia).toBe(2);
    expect(store.claimJobs).toHaveBeenCalledWith(
      expect.objectContaining({
        jobTypes: ["media.process_vehicle_photo"],
        limit: 2,
      }),
    );

    releaseMedia.resolve();
    await expect(run).resolves.toBe(6);
    expect(vi.mocked(store.claimJobs).mock.results).toHaveLength(2);
  });

  it("rejects lane definitions that omit or duplicate handlers", () => {
    const handler: JobHandler = vi.fn();
    expect(
      () =>
        new DurableJobRunner({
          executionLanes: [
            { jobTypes: ["documents.render_preview"], maximumConcurrency: 1 },
          ],
          handlers: new Map([
            ["documents.render_preview", handler],
            ["media.process_vehicle_photo", handler],
          ]),
          logger,
          store: jobStore(claimedJob()),
          workerId: "worker-a",
        }),
    ).toThrow(/cover each registered job type exactly once/u);
  });
});
