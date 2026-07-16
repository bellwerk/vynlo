import type { JobRunnerLogger } from "./job-runner";

export interface BatchJobRunner {
  runBatch(limit: number): Promise<number>;
}

type Sleep = (milliseconds: number, signal: AbortSignal) => Promise<void>;

export async function sleepUntil(
  milliseconds: number,
  signal: AbortSignal,
): Promise<void> {
  if (signal.aborted) {
    return;
  }
  await new Promise<void>((resolve) => {
    const timer = setTimeout(done, milliseconds);
    signal.addEventListener("abort", done, { once: true });
    function done() {
      clearTimeout(timer);
      signal.removeEventListener("abort", done);
      resolve();
    }
  });
}

export class WorkerService {
  readonly #batchSize: number;
  readonly #errorBackoffBaseMs: number;
  readonly #errorBackoffMaximumMs: number;
  readonly #logger: JobRunnerLogger;
  readonly #pollIntervalMs: number;
  readonly #random: () => number;
  readonly #runner: BatchJobRunner;
  readonly #sleep: Sleep;

  constructor(input: {
    readonly batchSize: number;
    readonly errorBackoffBaseMs: number;
    readonly errorBackoffMaximumMs: number;
    readonly logger: JobRunnerLogger;
    readonly pollIntervalMs: number;
    readonly random?: () => number;
    readonly runner: BatchJobRunner;
    readonly sleep?: Sleep;
  }) {
    this.#batchSize = input.batchSize;
    this.#errorBackoffBaseMs = input.errorBackoffBaseMs;
    this.#errorBackoffMaximumMs = input.errorBackoffMaximumMs;
    this.#logger = input.logger;
    this.#pollIntervalMs = input.pollIntervalMs;
    this.#random = input.random ?? Math.random;
    this.#runner = input.runner;
    this.#sleep = input.sleep ?? sleepUntil;
  }

  async run(signal: AbortSignal): Promise<void> {
    let consecutiveFailures = 0;
    this.#logger.info("worker polling started", {
      batchSize: this.#batchSize,
      pollIntervalMs: this.#pollIntervalMs,
    });

    while (!signal.aborted) {
      try {
        const claimedCount = await this.#runner.runBatch(this.#batchSize);
        consecutiveFailures = 0;
        this.#logger.info("worker poll completed", { claimedCount });
        if (claimedCount === 0 && !signal.aborted) {
          await this.#sleep(this.#pollIntervalMs, signal);
        }
      } catch {
        consecutiveFailures += 1;
        const cap = Math.min(
          this.#errorBackoffMaximumMs,
          this.#errorBackoffBaseMs * 2 ** Math.min(consecutiveFailures - 1, 20),
        );
        const random = this.#random();
        const retryDelayMs = Math.max(
          1,
          Math.floor(
            cap / 2 + (cap / 2) * Math.min(Math.max(random, 0), 0.999_999),
          ),
        );
        this.#logger.info("worker poll failed", {
          consecutiveFailures,
          retryDelayMs,
        });
        if (!signal.aborted) {
          await this.#sleep(retryDelayMs, signal);
        }
      }
    }

    this.#logger.info("worker polling stopped", { graceful: true });
  }
}
