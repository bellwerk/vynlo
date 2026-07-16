import { describe, expect, it } from "vitest";

import { readWorkerRuntimeConfig } from "./runtime-config";

const validEnvironment = {
  VYNLO_APP_URL: "http://localhost:3000",
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
      errorBackoffBaseMs: 1_000,
      errorBackoffMaximumMs: 30_000,
      heartbeatIntervalMs: 20_000,
      leaseSeconds: 60,
      pollIntervalMs: 1_000,
      previewBucket: "preview-artifacts",
      workerId: "preview-worker-1",
    });
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
});
