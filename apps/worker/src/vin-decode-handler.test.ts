import { VinDecoderError, type VinDecoderPort } from "@vynlo/integrations";
import { describe, expect, it, vi } from "vitest";

import type { ClaimedJob } from "./job-store";
import { JobExecutionError } from "./job-runner";
import {
  createVinDecodeJobHandler,
  parseVinDecodeJobPayload,
  type VinDecodeResultRepository,
} from "./vin-decode-handler";

const requestId = "a8100000-0000-4000-8000-000000000001";
const jobId = "a8200000-0000-4000-8000-000000000001";
const leaseToken = "a8300000-0000-4000-8000-000000000001";
const workspaceId = "10000000-0000-4000-8000-000000000001";

function claimedJob(overrides: Partial<ClaimedJob> = {}): ClaimedJob {
  return {
    attemptNumber: 1,
    causationId: null,
    correlationId: "a8400000-0000-4000-8000-000000000001",
    entityId: requestId,
    entityType: "vin_decode_request",
    idempotencyKey: "vin-job-request-001",
    jobId,
    jobType: "inventory.vin_decode",
    leaseExpiresAt: "2026-07-16T12:05:00.000Z",
    leaseToken,
    maximumAttempts: 8,
    outboxEventId: "a8500000-0000-4000-8000-000000000001",
    payload: {
      model_year_hint: 2003,
      request_id: requestId,
      vin: "1HGCM82633A004352",
    },
    payloadSchemaVersion: 1,
    workspaceId,
    ...overrides,
  };
}

const decoded = {
  decodedAt: "2026-07-16T12:00:00.000Z",
  facts: {
    bodyType: "Sedan/Saloon",
    cylinders: 4,
    drivetrain: "4x2",
    engineLiters: "2.4",
    fuelType: "Gasoline",
    horsepower: 160,
    make: "HONDA",
    model: "Accord",
    modelYear: 2003,
    transmission: "Automatic",
    trim: "EX-V6",
  },
  providerKey: "nhtsa_vpic" as const,
  providerVersion: "vpic-4.06",
  rawResponse: { Results: [{ Make: "HONDA" }] },
  vin: "1HGCM82633A004352",
  warnings: [] as const,
};

describe("T-INV-002 / T-JOB-003 VIN decode job handler", () => {
  it("rejects malformed or authority-bearing durable payloads before provider traffic", () => {
    expect(() =>
      parseVinDecodeJobPayload(
        claimedJob({
          payload: { ...claimedJob().payload, workspace_id: workspaceId },
        }),
      ),
    ).toThrow(JobExecutionError);
    expect(() =>
      parseVinDecodeJobPayload(claimedJob({ entityId: crypto.randomUUID() })),
    ).toThrow(/strict contract/u);
  });

  it("decodes and persists through the exact worker lease before job completion", async () => {
    const decoder: VinDecoderPort = { decode: vi.fn(async () => decoded) };
    const repository: VinDecodeResultRepository = {
      completeResult: vi.fn(async () => ({
        aggregateVersion: 2,
        auditEventId: "a8600000-0000-4000-8000-000000000001",
        decodeStatus: "succeeded" as const,
        duplicateCandidateCount: 1,
        outboxEventId: "a8700000-0000-4000-8000-000000000001",
        replayed: false,
        vinDecodeResultId: "a8800000-0000-4000-8000-000000000001",
      })),
    };
    const signal = new AbortController().signal;
    const result = await createVinDecodeJobHandler({
      decoder,
      repository,
      workerId: "vin-worker-a",
    })(claimedJob(), { signal });

    expect(decoder.decode).toHaveBeenCalledWith({
      modelYear: 2003,
      signal,
      vin: "1HGCM82633A004352",
    });
    expect(repository.completeResult).toHaveBeenCalledWith(
      expect.objectContaining({
        facts: decoded.facts,
        jobId,
        leaseToken,
        rawResponse: decoded.rawResponse,
        vinDecodeRequestId: requestId,
        workerId: "vin-worker-a",
        workspaceId,
      }),
    );
    expect(result).toEqual({
      summary: {
        aggregate_version: 2,
        decode_status: "succeeded",
        duplicate_candidate_count: 1,
        provider_key: "nhtsa_vpic",
        provider_version: "vpic-4.06",
        replayed: false,
        vin_decode_result_id: "a8800000-0000-4000-8000-000000000001",
      },
    });
  });

  it.each([
    ["provider_rate_limited", "rate_limited", "vin.provider_rate_limited", 17],
    [
      "provider_unavailable",
      "transient",
      "vin.provider_unavailable",
      undefined,
    ],
    ["provider_rejected", "permanent", "vin.provider_rejected", undefined],
    [
      "provider_response_invalid",
      "permanent",
      "vin.provider_response_invalid",
      undefined,
    ],
  ] as const)(
    "maps %s to safe durable failure telemetry",
    async (code, classification, expectedCode, retryAfterSeconds) => {
      const decoder: VinDecoderPort = {
        decode: vi.fn(async () => {
          throw new VinDecoderError(code, {
            retryAfterMs: code === "provider_rate_limited" ? 17_000 : null,
            retryable: [
              "provider_rate_limited",
              "provider_unavailable",
            ].includes(code),
          });
        }),
      };
      const repository: VinDecodeResultRepository = {
        completeResult: vi.fn(),
      };
      const error = await createVinDecodeJobHandler({
        decoder,
        repository,
        workerId: "vin-worker-a",
      })(claimedJob(), { signal: new AbortController().signal }).catch(
        (cause: unknown) => cause,
      );

      expect(error).toBeInstanceOf(JobExecutionError);
      expect(error).toMatchObject({
        classification,
        code: expectedCode,
        retryAfterSeconds,
      });
      expect(repository.completeResult).not.toHaveBeenCalled();
    },
  );

  it("rejects unsafe worker identifiers during assembly", () => {
    expect(() =>
      createVinDecodeJobHandler({
        decoder: { decode: vi.fn() },
        repository: { completeResult: vi.fn() },
        workerId: "contains secret token",
      }),
    ).toThrow(/stable non-secret/u);
  });

  it("caps retry telemetry at the exact database boundary", async () => {
    const error = await createVinDecodeJobHandler({
      decoder: {
        decode: vi.fn(async () => {
          throw new VinDecoderError("provider_rate_limited", {
            retryAfterMs: Number.MAX_SAFE_INTEGER,
            retryable: true,
          });
        }),
      },
      repository: { completeResult: vi.fn() },
      workerId: "vin-worker-a",
    })(claimedJob(), { signal: new AbortController().signal }).catch(
      (cause: unknown) => cause,
    );

    expect(error).toMatchObject({
      classification: "rate_limited",
      retryAfterSeconds: 86_400,
    });
  });
});
