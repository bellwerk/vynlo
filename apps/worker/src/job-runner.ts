import {
  findProhibitedJobPayloadKey,
  type JobErrorClassification,
} from "@vynlo/jobs";
import type { ClaimedJob, DurableJobStore, FailJobInput } from "./job-store";

export interface JobResult {
  readonly providerRequestId?: string | undefined;
  readonly summary?: Readonly<Record<string, unknown>>;
}

export interface JobHandlerContext {
  /**
   * Handlers must pass this signal to every database, storage, and provider
   * operation so a lost lease stops new side effects.
   */
  readonly signal: AbortSignal;
}

export type JobHandler = (
  job: ClaimedJob,
  context: JobHandlerContext,
) => Promise<JobResult | void>;

export interface JobRunnerLogger {
  info(message: string, context?: Readonly<Record<string, unknown>>): void;
}

type PersistedFailureClassification = Exclude<
  JobErrorClassification,
  "lease_expired"
>;

const unsafeFailureDetail =
  /(authorization|bearer|cookie|credential|password|private.?key|secret|token)/iu;

class ManagedLeaseHeartbeat {
  readonly #abortController: AbortController;
  readonly #heartbeat: () => Promise<string>;
  readonly #intervalMs: number;
  #failure: JobExecutionError | undefined;
  readonly #failurePromise: Promise<never>;
  #inFlight: Promise<void> | undefined;
  #rejectFailure!: (reason: JobExecutionError) => void;
  #stopped = false;
  #timer: ReturnType<typeof setTimeout> | undefined;

  constructor(input: {
    readonly abortController: AbortController;
    readonly heartbeat: () => Promise<string>;
    readonly intervalMs: number;
  }) {
    this.#abortController = input.abortController;
    this.#heartbeat = input.heartbeat;
    this.#intervalMs = input.intervalMs;
    this.#failurePromise = new Promise<never>((_resolve, reject) => {
      this.#rejectFailure = reject;
    });
  }

  get failed(): Promise<never> {
    return this.#failurePromise;
  }

  start(): void {
    this.#schedule();
  }

  async stop(): Promise<void> {
    this.#stopped = true;
    if (this.#timer !== undefined) {
      clearTimeout(this.#timer);
      this.#timer = undefined;
    }
    await this.#inFlight;
    if (this.#failure !== undefined) {
      throw this.#failure;
    }
  }

  #schedule(): void {
    if (this.#stopped || this.#failure !== undefined) {
      return;
    }
    this.#timer = setTimeout(() => {
      this.#timer = undefined;
      this.#inFlight = this.#runOnce();
    }, this.#intervalMs);
  }

  async #runOnce(): Promise<void> {
    try {
      await this.#heartbeat();
    } catch {
      const failure = new JobExecutionError({
        classification: "transient",
        code: "worker.heartbeat_failed",
        safeDetail: "The worker could not renew its active job lease.",
      });
      this.#failure = failure;
      this.#abortController.abort(failure);
      this.#rejectFailure(failure);
    } finally {
      this.#inFlight = undefined;
      this.#schedule();
    }
  }
}

export class JobExecutionError extends Error {
  readonly classification: PersistedFailureClassification;
  readonly code: string;
  readonly providerRequestId: string | undefined;
  readonly retryAfterSeconds: number | undefined;
  readonly safeDetail: string;

  constructor(input: {
    readonly classification: PersistedFailureClassification;
    readonly code: string;
    readonly providerRequestId?: string | undefined;
    readonly retryAfterSeconds?: number | undefined;
    readonly safeDetail: string;
  }) {
    if (!/^[a-z][a-z0-9_.-]{0,119}$/u.test(input.code)) {
      throw new TypeError("Job failure code must be a safe machine key.");
    }
    if (
      input.safeDetail.trim().length === 0 ||
      input.safeDetail.length > 2_000 ||
      unsafeFailureDetail.test(input.safeDetail)
    ) {
      throw new TypeError("Job failure detail is not safe to persist.");
    }
    super(input.safeDetail);
    this.name = "JobExecutionError";
    this.classification = input.classification;
    this.code = input.code;
    this.providerRequestId = input.providerRequestId;
    this.retryAfterSeconds = input.retryAfterSeconds;
    this.safeDetail = input.safeDetail;
  }
}

export class DurableJobRunner {
  readonly #handlers: ReadonlyMap<string, JobHandler>;
  readonly #heartbeatIntervalMs: number;
  readonly #leaseSeconds: number;
  readonly #logger: JobRunnerLogger;
  readonly #store: DurableJobStore;
  readonly #workerId: string;

  constructor(input: {
    readonly handlers: ReadonlyMap<string, JobHandler>;
    readonly heartbeatIntervalMs?: number;
    readonly leaseSeconds?: number;
    readonly logger: JobRunnerLogger;
    readonly store: DurableJobStore;
    readonly workerId: string;
  }) {
    if (input.workerId.trim().length === 0 || input.workerId.length > 200) {
      throw new TypeError("workerId must be a non-empty stable identifier.");
    }
    const leaseSeconds = input.leaseSeconds ?? 60;
    if (
      !Number.isInteger(leaseSeconds) ||
      leaseSeconds < 5 ||
      leaseSeconds > 900
    ) {
      throw new RangeError("leaseSeconds must be an integer from 5 to 900.");
    }
    const heartbeatIntervalMs =
      input.heartbeatIntervalMs ?? Math.floor((leaseSeconds * 1_000) / 3);
    if (
      !Number.isInteger(heartbeatIntervalMs) ||
      heartbeatIntervalMs < 100 ||
      heartbeatIntervalMs > Math.floor((leaseSeconds * 1_000) / 2)
    ) {
      throw new RangeError(
        "heartbeatIntervalMs must be from 100ms through half of the lease.",
      );
    }
    this.#handlers = input.handlers;
    this.#heartbeatIntervalMs = heartbeatIntervalMs;
    this.#leaseSeconds = leaseSeconds;
    this.#logger = input.logger;
    this.#store = input.store;
    this.#workerId = input.workerId;
  }

  async runBatch(limit = 10): Promise<number> {
    const reclaimedCount = await this.#store.reclaimExpiredJobs(limit);
    if (reclaimedCount > 0) {
      this.#logger.info("expired job leases reclaimed", { reclaimedCount });
    }
    const jobs = await this.#store.claimJobs({
      jobTypes: [...this.#handlers.keys()],
      leaseSeconds: this.#leaseSeconds,
      limit,
      workerId: this.#workerId,
    });

    await Promise.all(jobs.map((job) => this.#runJob(job)));
    return jobs.length;
  }

  async #runJob(job: ClaimedJob): Promise<void> {
    const logContext = {
      attemptNumber: job.attemptNumber,
      correlationId: job.correlationId,
      jobId: job.jobId,
      jobType: job.jobType,
      workspaceId: job.workspaceId,
    } as const;
    const handler = this.#handlers.get(job.jobType);

    if (!handler) {
      await this.#fail(job, {
        classification: "permanent",
        errorCode: "worker.handler_not_registered",
        errorDetailSafe: "No verified handler is registered for this job type.",
      });
      return;
    }

    this.#logger.info("job execution started", logContext);

    const abortController = new AbortController();
    const heartbeat = new ManagedLeaseHeartbeat({
      abortController,
      heartbeat: () =>
        this.#store.heartbeatJob({
          extendSeconds: this.#leaseSeconds,
          jobId: job.jobId,
          leaseToken: job.leaseToken,
          workerId: this.#workerId,
        }),
      intervalMs: this.#heartbeatIntervalMs,
    });
    const handlerPromise = Promise.resolve().then(() =>
      handler(job, { signal: abortController.signal }),
    );
    heartbeat.start();

    try {
      const result = (await Promise.race([
        handlerPromise,
        heartbeat.failed,
      ])) ?? { summary: {} };
      await heartbeat.stop();
      const summary = result.summary ?? {};
      const prohibitedKey = findProhibitedJobPayloadKey(summary);
      if (prohibitedKey !== null) {
        throw new JobExecutionError({
          classification: "permanent",
          code: "worker.unsafe_result_summary",
          safeDetail:
            "The handler returned a result summary with a prohibited field.",
        });
      }

      await this.#store.completeJob({
        jobId: job.jobId,
        leaseToken: job.leaseToken,
        providerRequestId: result.providerRequestId,
        resultSummary: summary,
        workerId: this.#workerId,
      });
      this.#logger.info("job execution succeeded", logContext);
    } catch (error) {
      abortController.abort(error);
      let effectiveError = error;
      try {
        await heartbeat.stop();
      } catch (heartbeatError) {
        effectiveError = heartbeatError;
      }
      await handlerPromise.catch(() => undefined);

      const failure =
        effectiveError instanceof JobExecutionError
          ? effectiveError
          : new JobExecutionError({
              classification: "unknown",
              code: "worker.unhandled_failure",
              safeDetail: "The handler failed without a safe classified error.",
            });

      await this.#fail(job, {
        classification: failure.classification,
        errorCode: failure.code,
        errorDetailSafe: failure.safeDetail,
        providerRequestId: failure.providerRequestId,
        retryAfterSeconds: failure.retryAfterSeconds,
      });
      this.#logger.info("job execution failed", {
        ...logContext,
        classification: failure.classification,
        errorCode: failure.code,
      });
    }
  }

  async #fail(
    job: ClaimedJob,
    failure: Omit<FailJobInput, "jobId" | "leaseToken" | "workerId">,
  ) {
    await this.#store.failJob({
      ...failure,
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      workerId: this.#workerId,
    });
  }
}
