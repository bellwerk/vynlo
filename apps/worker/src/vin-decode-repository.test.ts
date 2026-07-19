import { describe, expect, it, vi } from "vitest";

import { JobExecutionError } from "./job-runner";
import { PostgrestVinDecodeResultRepository } from "./vin-decode-repository";

const completionInput = {
  correlationId: "a8100000-0000-4000-8000-000000000001",
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
  jobId: "a8200000-0000-4000-8000-000000000001",
  leaseToken: "a8300000-0000-4000-8000-000000000001",
  providerKey: "nhtsa_vpic" as const,
  providerVersion: "vpic-4.06",
  rawResponse: { Results: [{ Make: "HONDA" }] },
  requestId: "job:a8200000-0000-4000-8000-000000000001",
  signal: new AbortController().signal,
  vinDecodeRequestId: "a8400000-0000-4000-8000-000000000001",
  warnings: ["decoded clean"],
  workerId: "vin-worker-a",
  workspaceId: "10000000-0000-4000-8000-000000000001",
} as const;

function repository(fetchImplementation: typeof fetch) {
  return new PostgrestVinDecodeResultRepository({
    fetchImplementation,
    serviceRoleKey: "service-role-key-for-tests-only",
    supabaseUrl: "http://127.0.0.1:54321",
  });
}

describe("T-INV-002 / T-JOB-001 PostgrestVinDecodeResultRepository", () => {
  it("sends all provider facts and exact lease identifiers to the fenced RPC", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 2,
          audit_event_id: "a8500000-0000-4000-8000-000000000001",
          decode_status: "succeeded",
          duplicate_candidate_count: 1,
          outbox_event_id: "a8600000-0000-4000-8000-000000000001",
          replayed: false,
          vin_decode_result_id: "a8700000-0000-4000-8000-000000000001",
        },
      ]),
    );

    await expect(
      repository(fetchImplementation).completeResult(completionInput),
    ).resolves.toMatchObject({
      aggregateVersion: 2,
      decodeStatus: "succeeded",
      duplicateCandidateCount: 1,
      replayed: false,
    });
    const [url, init] = fetchImplementation.mock.calls[0]!;
    expect(url).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/complete_vin_decode_request",
    );
    expect(new Headers(init?.headers).get("content-profile")).toBe("app");
    expect(JSON.parse(String(init?.body))).toEqual({
      p_body_type: "Sedan/Saloon",
      p_correlation_id: completionInput.correlationId,
      p_cylinders: 4,
      p_decoded_at: completionInput.decodedAt,
      p_drivetrain: "4x2",
      p_engine_liters: "2.4",
      p_fuel_type: "Gasoline",
      p_horsepower: 160,
      p_job_id: completionInput.jobId,
      p_lease_token: completionInput.leaseToken,
      p_make: "HONDA",
      p_model: "Accord",
      p_model_year: 2003,
      p_provider_key: "nhtsa_vpic",
      p_provider_version: "vpic-4.06",
      p_raw_response: completionInput.rawResponse,
      p_request_id: completionInput.requestId,
      p_transmission: "Automatic",
      p_trim_name: "EX-V6",
      p_vin_decode_request_id: completionInput.vinDecodeRequestId,
      p_warnings: ["decoded clean"],
      p_worker_id: "vin-worker-a",
      p_workspace_id: completionInput.workspaceId,
    });
  });

  it.each([
    [403, "provider_auth", "vin.database_access_denied"],
    [409, "permanent", "vin.result_conflict"],
    [429, "transient", "vin.database_temporarily_unavailable"],
    [503, "transient", "vin.database_temporarily_unavailable"],
    [422, "permanent", "vin.database_request_rejected"],
  ] as const)(
    "classifies HTTP %s without leaking its body",
    async (status, classification, code) => {
      const error = await repository(
        vi.fn(async () =>
          Response.json({ secret: "must-not-leak" }, { status }),
        ),
      )
        .completeResult(completionInput)
        .catch((cause: unknown) => cause);
      expect(error).toBeInstanceOf(JobExecutionError);
      expect(error).toMatchObject({ classification, code });
      expect(String(error)).not.toContain("must-not-leak");
    },
  );

  it("fails closed on malformed success responses and transport errors", async () => {
    await expect(
      repository(
        vi.fn(async () => Response.json([{ replayed: false }])),
      ).completeResult(completionInput),
    ).rejects.toMatchObject({ code: "vin.invalid_database_contract" });
    await expect(
      repository(
        vi.fn(async () => {
          throw new Error("network detail");
        }),
      ).completeResult(completionInput),
    ).rejects.toMatchObject({
      classification: "transient",
      code: "vin.database_transport_failed",
    });
  });

  it("rejects non-HTTPS remote database configuration", () => {
    expect(
      () =>
        new PostgrestVinDecodeResultRepository({
          serviceRoleKey: "service-role-key-for-tests-only",
          supabaseUrl: "http://example.invalid",
        }),
    ).toThrow(/HTTPS/u);
  });
});
