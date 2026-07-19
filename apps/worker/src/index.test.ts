// Stable test IDs: T-JOB-003, T-OPS-001.
import { pathToFileURL } from "node:url";

import { describe, expect, it } from "vitest";

import {
  ATOMIC_DELETE_BLOCKED_JOB_TYPES,
  enabledWorkerJobTypes,
  isDirectWorkerEntrypoint,
  workerExecutionLanes,
  WORKER_JOB_TYPES,
} from "./index";

describe("worker entrypoint", () => {
  it("declares core and gated media job types", () => {
    expect(WORKER_JOB_TYPES).toEqual([
      "documents.render_preview",
      "documents.render_pdf",
      "exports.generate",
      "auth.invitation.deliver",
      "inventory.vin_decode",
      "media.verify_vehicle_photo_upload",
      "media.verify_legal_original",
      "media.process_vehicle_photo",
      "media.delete_retained_raw",
      "media.delete_quarantine_upload",
      "media.delete_legal_original_quarantine",
    ]);
    expect(ATOMIC_DELETE_BLOCKED_JOB_TYPES).toEqual([
      "media.delete_retained_raw",
      "media.delete_quarantine_upload",
      "media.delete_legal_original_quarantine",
    ]);
    expect(
      enabledWorkerJobTypes({
        mediaProcessing: { enabled: false },
      } as never),
    ).toEqual([
      "documents.render_preview",
      "documents.render_pdf",
      "exports.generate",
      "auth.invitation.deliver",
      "inventory.vin_decode",
    ]);
    expect(
      enabledWorkerJobTypes({
        mediaProcessing: {
          clamdConnectTimeoutMs: 1_000,
          clamdHost: "clamd.internal",
          clamdPort: 3_310,
          clamdScanTimeoutMs: 30_000,
          enabled: true,
        },
      } as never),
    ).toEqual([
      "documents.render_preview",
      "documents.render_pdf",
      "exports.generate",
      "auth.invitation.deliver",
      "inventory.vin_decode",
      "media.verify_vehicle_photo_upload",
      "media.verify_legal_original",
      "media.process_vehicle_photo",
    ]);
  });

  it("starts only when the module is the direct process entry", () => {
    const entry = "C:\\workspace\\apps\\worker\\dist\\index.js";
    expect(isDirectWorkerEntrypoint(pathToFileURL(entry).href, entry)).toBe(
      true,
    );
    expect(
      isDirectWorkerEntrypoint(
        "file:///workspace/apps/worker/dist/index.js",
        "C:\\workspace\\vitest.js",
      ),
    ).toBe(false);
    expect(
      isDirectWorkerEntrypoint(
        "file:///workspace/apps/worker/dist/index.js",
        undefined,
      ),
    ).toBe(false);
  });

  it("reserves a bounded heavy-media lane inside the total claim budget", () => {
    expect(
      workerExecutionLanes(
        {
          exportGeneration: { maximumConcurrentJobs: 2 },
          mediaProcessing: {
            enabled: true,
            maximumConcurrentMediaJobs: 1,
          },
          pdfRendering: { maximumConcurrentJobs: 2 },
        } as never,
        [
          "documents.render_preview",
          "documents.render_pdf",
          "exports.generate",
          "inventory.vin_decode",
          "media.verify_vehicle_photo_upload",
          "media.verify_legal_original",
          "media.process_vehicle_photo",
        ],
      ),
    ).toEqual([
      {
        jobTypes: [
          "media.verify_vehicle_photo_upload",
          "media.verify_legal_original",
          "media.process_vehicle_photo",
        ],
        maximumConcurrency: 1,
      },
      {
        jobTypes: ["documents.render_pdf"],
        maximumConcurrency: 2,
      },
      {
        jobTypes: ["exports.generate"],
        maximumConcurrency: 2,
      },
      {
        jobTypes: ["documents.render_preview", "inventory.vin_decode"],
        maximumConcurrency: 100,
      },
    ]);
  });
});
