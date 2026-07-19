// Stable test IDs: T-JOB-003, T-OPS-001.
import { describe, expect, it } from "vitest";

import { readWorkerRuntimeConfig } from "./runtime-config";

const validEnvironment = {
  PDF_RENDERER: "playwright",
  VYNLO_APP_URL: "http://localhost:3000",
  VYNLO_DOCUMENT_BUCKET: "documents-private",
  VYNLO_EXPORT_BUCKET: "exports-private",
  VYNLO_PREVIEW_BUCKET: "preview-artifacts",
  VYNLO_SUPABASE_SERVICE_ROLE_KEY: "x".repeat(32),
  VYNLO_SUPABASE_URL: "http://127.0.0.1:54321",
  VYNLO_WORKER_ID: "preview-worker-1",
} as const;

describe("worker runtime configuration", () => {
  it("applies bounded operational defaults to explicit server-only settings", () => {
    expect(readWorkerRuntimeConfig(validEnvironment)).toMatchObject({
      appUrl: "http://localhost:3000",
      authInviteTimeoutMs: 10_000,
      batchSize: 10,
      documentBucket: "documents-private",
      errorBackoffBaseMs: 1_000,
      errorBackoffMaximumMs: 30_000,
      heartbeatIntervalMs: 20_000,
      leaseSeconds: 60,
      exportBucket: "exports-private",
      exportGeneration: { maximumConcurrentJobs: 2 },
      mediaProcessing: { enabled: false },
      pdfRendering: {
        maximumConcurrentJobs: 2,
        renderer: "playwright",
        timeoutMs: 60_000,
      },
      pollIntervalMs: 1_000,
      previewBucket: "preview-artifacts",
      workerId: "preview-worker-1",
    });
  });

  it("requires a private ClamD target only when media processing is enabled", () => {
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_MEDIA_PROCESSING_ENABLED: "true",
      }),
    ).toThrow(/VYNLO_CLAMD_HOST/u);
    expect(
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_CLAMD_HOST: "clamd.internal",
        VYNLO_MEDIA_PROCESSING_ENABLED: "true",
      }).mediaProcessing,
    ).toEqual({
      clamdConnectTimeoutMs: 3_000,
      clamdHost: "clamd.internal",
      clamdPort: 3_310,
      clamdScanTimeoutMs: 30_000,
      enabled: true,
      maximumConcurrentMediaJobs: 1,
    });
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_MEDIA_PROCESSING_ENABLED: "yes",
      }),
    ).toThrow(/true or false/u);
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_CLAMD_HOST: "clamd.internal",
        VYNLO_MEDIA_JOB_CONCURRENCY: "3",
        VYNLO_MEDIA_PROCESSING_ENABLED: "true",
      }),
    ).toThrow(/MEDIA_JOB_CONCURRENCY/u);
  });

  it("rejects missing service credentials and insecure remote transport", () => {
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_SUPABASE_SERVICE_ROLE_KEY: undefined,
      }),
    ).toThrow(/VYNLO_SUPABASE_SERVICE_ROLE_KEY/u);
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_SUPABASE_URL: "http://example.invalid",
      }),
    ).toThrow(/HTTPS/u);
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_APP_URL: "http://example.invalid",
      }),
    ).toThrow(/VYNLO_APP_URL.*HTTPS/u);
  });

  it("rejects overlapping heartbeat and invalid polling bounds", () => {
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_WORKER_HEARTBEAT_INTERVAL_MS: "60000",
      }),
    ).toThrow(/HEARTBEAT/u);
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_WORKER_BATCH_SIZE: "0",
      }),
    ).toThrow(/BATCH/u);
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_AUTH_INVITE_TIMEOUT_MS: "999",
      }),
    ).toThrow(/AUTH_INVITE_TIMEOUT/u);
  });

  it("requires private M4 buckets and the approved bounded PDF runtime", () => {
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_DOCUMENT_BUCKET: "",
      }),
    ).toThrow(/VYNLO_DOCUMENT_BUCKET/u);
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        PDF_RENDERER: "wkhtmltopdf",
      }),
    ).toThrow(/PDF_RENDERER/u);
    expect(() =>
      readWorkerRuntimeConfig({
        ...validEnvironment,
        VYNLO_EXPORT_JOB_CONCURRENCY: "5",
      }),
    ).toThrow(/EXPORT_JOB_CONCURRENCY/u);
  });
});
