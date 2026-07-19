import { describe, expect, it, vi } from "vitest";

import {
  MediaMaintenanceBatchRunner,
  PostgrestMediaMaintenanceProducer,
} from "./media-maintenance-scheduler";

const correlationId = "a9000000-0000-4000-8000-000000000001";
const serviceRoleKey = "service-role-key-that-is-server-only";

describe("T-MED-004 / T-JOB-003 media maintenance scheduler", () => {
  it("calls all bounded durable producers with one correlation ID", async () => {
    const request = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([{ job_id: "a9000000-0000-4000-8000-000000000002" }]),
      )
      .mockResolvedValueOnce(Response.json([]))
      .mockResolvedValueOnce(Response.json([]));
    const producer = new PostgrestMediaMaintenanceProducer({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://database.example.invalid",
    });

    await expect(
      producer.scheduleDue({ correlationId, limit: 25 }),
    ).resolves.toEqual({
      legalOriginalCleanupJobs: 1,
      quarantineCleanupJobs: 0,
      rawRetentionJobs: 0,
    });
    expect(request).toHaveBeenCalledTimes(3);
    expect(request.mock.calls.map(([url]) => String(url))).toEqual(
      expect.arrayContaining([
        expect.stringContaining("enqueue_due_media_quarantine_cleanup"),
        expect.stringContaining(
          "enqueue_due_legal_original_quarantine_cleanup",
        ),
        expect.stringContaining("enqueue_due_vehicle_raw_retention"),
      ]),
    );
    for (const [, init] of request.mock.calls) {
      expect(JSON.parse(String(init?.body))).toEqual({
        p_correlation_id: correlationId,
        p_limit: 25,
      });
    }
  });

  it("rate-limits scheduler ticks while normal job claims continue", async () => {
    let now = 1_000;
    const producer = {
      scheduleDue: vi.fn().mockResolvedValue({
        legalOriginalCleanupJobs: 1,
        quarantineCleanupJobs: 2,
        rawRetentionJobs: 3,
      }),
    };
    const runner = { runBatch: vi.fn().mockResolvedValue(4) };
    const logger = { info: vi.fn() };
    const scheduled = new MediaMaintenanceBatchRunner({
      correlationId: () => correlationId,
      intervalMs: 60_000,
      limit: 100,
      logger,
      now: () => now,
      producer,
      runner,
    });

    await expect(scheduled.runBatch(10)).resolves.toBe(4);
    now += 1_000;
    await expect(scheduled.runBatch(10)).resolves.toBe(4);
    now += 60_000;
    await expect(scheduled.runBatch(10)).resolves.toBe(4);

    expect(producer.scheduleDue).toHaveBeenCalledTimes(2);
    expect(runner.runBatch).toHaveBeenCalledTimes(3);
    expect(logger.info).toHaveBeenCalledWith(
      "media maintenance scheduling completed",
      expect.objectContaining({
        legalOriginalCleanupJobs: 1,
        quarantineCleanupJobs: 2,
        rawRetentionJobs: 3,
      }),
    );
  });

  it("reports a producer failure and still runs the durable job consumer", async () => {
    const producer = {
      scheduleDue: vi.fn().mockRejectedValue(new Error("database unavailable")),
    };
    const runner = { runBatch: vi.fn().mockResolvedValue(0) };
    const logger = { info: vi.fn() };
    const scheduled = new MediaMaintenanceBatchRunner({
      correlationId: () => correlationId,
      intervalMs: 60_000,
      limit: 100,
      logger,
      now: () => 1_000,
      producer,
      runner,
    });

    await expect(scheduled.runBatch(10)).resolves.toBe(0);
    expect(logger.info).toHaveBeenCalledWith(
      "media maintenance scheduling failed",
      { correlationId, retryAfterMs: 5_000 },
    );
    expect(runner.runBatch).toHaveBeenCalledTimes(1);
  });
});
