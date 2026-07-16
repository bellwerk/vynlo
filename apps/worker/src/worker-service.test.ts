import { describe, expect, it, vi } from "vitest";

import { WorkerService } from "./worker-service";

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((promiseResolve) => {
    resolve = promiseResolve;
  });
  return { promise, resolve } as const;
}

const logger = { info: vi.fn() };

describe("WorkerService", () => {
  it("polls with a bounded idle delay and stops without another claim", async () => {
    const controller = new AbortController();
    const runner = { runBatch: vi.fn(async () => 0) };
    const sleep = vi.fn(async (_milliseconds: number) => {
      void _milliseconds;
      controller.abort();
    });
    const service = new WorkerService({
      batchSize: 10,
      errorBackoffBaseMs: 1_000,
      errorBackoffMaximumMs: 30_000,
      logger,
      pollIntervalMs: 500,
      runner,
      sleep,
    });

    await service.run(controller.signal);

    expect(runner.runBatch).toHaveBeenCalledOnce();
    expect(sleep).toHaveBeenCalledWith(500, controller.signal);
  });

  it("uses capped jittered backoff and never logs an untrusted failure", async () => {
    const controller = new AbortController();
    const runner = {
      runBatch: vi.fn(async () => {
        throw new Error("sensitive database response");
      }),
    };
    const sleep = vi.fn(async () => {
      controller.abort();
    });
    const isolatedLogger = { info: vi.fn() };
    const service = new WorkerService({
      batchSize: 10,
      errorBackoffBaseMs: 1_000,
      errorBackoffMaximumMs: 30_000,
      logger: isolatedLogger,
      pollIntervalMs: 500,
      random: () => 0,
      runner,
      sleep,
    });

    await service.run(controller.signal);

    expect(sleep).toHaveBeenCalledWith(500, controller.signal);
    expect(JSON.stringify(isolatedLogger.info.mock.calls)).not.toContain(
      "database response",
    );
  });

  it("drains an in-flight batch before graceful shutdown", async () => {
    const controller = new AbortController();
    const batch = deferred<number>();
    const runner = { runBatch: vi.fn(() => batch.promise) };
    const service = new WorkerService({
      batchSize: 10,
      errorBackoffBaseMs: 1_000,
      errorBackoffMaximumMs: 30_000,
      logger,
      pollIntervalMs: 500,
      runner,
    });

    const running = service.run(controller.signal);
    await Promise.resolve();
    controller.abort();
    let settled = false;
    void running.then(() => {
      settled = true;
    });
    await Promise.resolve();
    expect(settled).toBe(false);

    batch.resolve(1);
    await running;
    expect(runner.runBatch).toHaveBeenCalledOnce();
  });
});
