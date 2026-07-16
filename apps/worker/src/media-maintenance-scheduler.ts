import type { JobRunnerLogger } from "./job-runner";
import { JobExecutionError } from "./job-runner";
import type { BatchJobRunner } from "./worker-service";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

export interface MediaMaintenanceScheduleResult {
  readonly legalOriginalCleanupJobs: number;
  readonly quarantineCleanupJobs: number;
  readonly rawRetentionJobs: number;
}

export interface MediaMaintenanceProducer {
  scheduleDue(input: {
    readonly correlationId: string;
    readonly limit: number;
  }): Promise<MediaMaintenanceScheduleResult>;
}

function safeOrigin(value: string): string {
  const url = new URL(value);
  const local = ["127.0.0.1", "localhost", "::1"].includes(url.hostname);
  if (
    (url.protocol !== "https:" && !(url.protocol === "http:" && local)) ||
    url.username !== "" ||
    url.password !== "" ||
    !["", "/"].includes(url.pathname) ||
    url.search !== "" ||
    url.hash !== ""
  ) {
    throw new TypeError("Supabase media scheduler URL must be a safe origin.");
  }
  return url.toString().replace(/\/$/u, "");
}

function schedulerFailure(
  code: string,
  safeDetail: string,
  classification: "permanent" | "provider_auth" | "transient",
): JobExecutionError {
  return new JobExecutionError({ classification, code, safeDetail });
}

function responseFailure(response: Response): JobExecutionError {
  if (response.status === 401 || response.status === 403) {
    return schedulerFailure(
      "media.scheduler_access_denied",
      "The media maintenance scheduler was denied by the database.",
      "provider_auth",
    );
  }
  if (response.status === 429 || response.status >= 500) {
    return schedulerFailure(
      "media.scheduler_temporarily_unavailable",
      "The media maintenance scheduler database is temporarily unavailable.",
      "transient",
    );
  }
  return schedulerFailure(
    "media.scheduler_request_rejected",
    "The database rejected a bounded media maintenance schedule request.",
    "permanent",
  );
}

function validateRows(value: unknown, limit: number, label: string): number {
  if (!Array.isArray(value) || value.length > limit) {
    throw schedulerFailure(
      `media.scheduler_invalid_${label}_response`,
      "The media maintenance scheduler returned an invalid bounded response.",
      "permanent",
    );
  }
  for (const row of value) {
    if (
      typeof row !== "object" ||
      row === null ||
      Array.isArray(row) ||
      !("job_id" in row) ||
      typeof row.job_id !== "string" ||
      !UUID_PATTERN.test(row.job_id)
    ) {
      throw schedulerFailure(
        `media.scheduler_invalid_${label}_response`,
        "The media maintenance scheduler returned an invalid bounded response.",
        "permanent",
      );
    }
  }
  return value.length;
}

export class PostgrestMediaMaintenanceProducer implements MediaMaintenanceProducer {
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
    this.#baseUrl = safeOrigin(input.supabaseUrl);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#headers = Object.freeze({
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
      "Content-Profile": "app",
      "Content-Type": "application/json",
    });
  }

  async scheduleDue(input: {
    readonly correlationId: string;
    readonly limit: number;
  }): Promise<MediaMaintenanceScheduleResult> {
    if (
      !Number.isInteger(input.limit) ||
      input.limit < 1 ||
      input.limit > 500 ||
      !UUID_PATTERN.test(input.correlationId)
    ) {
      throw new TypeError(
        "Invalid bounded media maintenance schedule request.",
      );
    }
    const body = {
      p_correlation_id: input.correlationId,
      p_limit: input.limit,
    };
    const [legalOriginalCleanupJobs, quarantineCleanupJobs, rawRetentionJobs] =
      await Promise.all([
        this.#schedule(
          "enqueue_due_legal_original_quarantine_cleanup",
          body,
          input.limit,
          "legal_original_cleanup",
        ),
        this.#schedule(
          "enqueue_due_media_quarantine_cleanup",
          body,
          input.limit,
          "quarantine_cleanup",
        ),
        this.#schedule(
          "enqueue_due_vehicle_raw_retention",
          body,
          input.limit,
          "raw_retention",
        ),
      ]);
    return {
      legalOriginalCleanupJobs,
      quarantineCleanupJobs,
      rawRetentionJobs,
    };
  }

  async #schedule(
    functionName: string,
    body: Readonly<Record<string, unknown>>,
    limit: number,
    label: string,
  ): Promise<number> {
    let response: Response;
    try {
      response = await this.#fetch(
        `${this.#baseUrl}/rest/v1/rpc/${functionName}`,
        {
          body: JSON.stringify(body),
          headers: this.#headers,
          method: "POST",
        },
      );
    } catch {
      throw schedulerFailure(
        "media.scheduler_transport_failed",
        "The media maintenance scheduler database request did not complete.",
        "transient",
      );
    }
    if (!response.ok) throw responseFailure(response);
    let value: unknown;
    try {
      value = await response.json();
    } catch {
      throw schedulerFailure(
        `media.scheduler_invalid_${label}_response`,
        "The media maintenance scheduler returned invalid JSON.",
        "permanent",
      );
    }
    return validateRows(value, limit, label);
  }
}

/** Runs bounded DB producers before normal claims without blocking claims on failure. */
export class MediaMaintenanceBatchRunner implements BatchJobRunner {
  readonly #correlationId: () => string;
  readonly #intervalMs: number;
  readonly #limit: number;
  readonly #logger: JobRunnerLogger;
  readonly #now: () => number;
  readonly #producer: MediaMaintenanceProducer;
  readonly #runner: BatchJobRunner;
  #nextScheduleAt = 0;

  constructor(input: {
    readonly correlationId?: () => string;
    readonly intervalMs: number;
    readonly limit: number;
    readonly logger: JobRunnerLogger;
    readonly now?: () => number;
    readonly producer: MediaMaintenanceProducer;
    readonly runner: BatchJobRunner;
  }) {
    if (
      !Number.isInteger(input.intervalMs) ||
      input.intervalMs < 5_000 ||
      input.intervalMs > 3_600_000 ||
      !Number.isInteger(input.limit) ||
      input.limit < 1 ||
      input.limit > 500
    ) {
      throw new RangeError("Invalid media maintenance scheduler bounds.");
    }
    this.#correlationId = input.correlationId ?? (() => crypto.randomUUID());
    this.#intervalMs = input.intervalMs;
    this.#limit = input.limit;
    this.#logger = input.logger;
    this.#now = input.now ?? Date.now;
    this.#producer = input.producer;
    this.#runner = input.runner;
  }

  async runBatch(limit: number): Promise<number> {
    const now = this.#now();
    if (now >= this.#nextScheduleAt) {
      const correlationId = this.#correlationId();
      try {
        const result = await this.#producer.scheduleDue({
          correlationId,
          limit: this.#limit,
        });
        this.#nextScheduleAt = now + this.#intervalMs;
        this.#logger.info("media maintenance scheduling completed", {
          correlationId,
          legalOriginalCleanupJobs: result.legalOriginalCleanupJobs,
          limit: this.#limit,
          quarantineCleanupJobs: result.quarantineCleanupJobs,
          rawRetentionJobs: result.rawRetentionJobs,
        });
      } catch {
        this.#nextScheduleAt = now + Math.min(this.#intervalMs, 5_000);
        this.#logger.info("media maintenance scheduling failed", {
          correlationId,
          retryAfterMs: Math.min(this.#intervalMs, 5_000),
        });
      }
    }
    return this.#runner.runBatch(limit);
  }
}
