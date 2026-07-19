// Stable test IDs: T-INV-002, T-INV-003, T-NUM-001, T-JOB-003, T-API-001.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { GET as getDecodeStatus } from "./[requestId]/route";
import { POST as reviewDuplicate } from "./[requestId]/duplicate-review/route";
import { POST as manualIntake } from "./[requestId]/manual-intake/route";
import { POST as retryDecode } from "./[requestId]/retry/route";
import { POST as requestDecode } from "./route";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const decodeRequestId = "a8100000-0000-4000-8000-000000000001";
const jobId = "a8200000-0000-4000-8000-000000000001";
const auditEventId = "a8300000-0000-4000-8000-000000000001";
const outboxEventId = "a8400000-0000-4000-8000-000000000001";
const correlationId = "a8500000-0000-4000-8000-000000000001";
const publicProjectKey = "sb_publishable_public_project_key_material";
const userToken = "user.header.signature";

function headers(includeIdempotency = true): Record<string, string> {
  return {
    Authorization: `Bearer ${userToken}`,
    ...(includeIdempotency ? { "Idempotency-Key": "m2-vin-command-0001" } : {}),
    "X-Correlation-Id": correlationId,
    "X-Request-Id": "request-m2-vin-0001",
    "X-Workspace-Id": workspaceId,
  };
}

function commandRequest(path: string, body: unknown): Request {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: { ...headers(), "Content-Type": "application/json" },
    method: "POST",
  });
}

describe("Milestone 2 VIN decode routes", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", publicProjectKey);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("queues a normalized VIN through the durable command contract", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 1,
          audit_event_id: auditEventId,
          duplicate_candidate_count: 0,
          job_id: jobId,
          job_status: "queued",
          outbox_event_id: outboxEventId,
          replayed: false,
          vin_decode_request_id: decodeRequestId,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await requestDecode(
      commandRequest("/api/v1/vin/decode", {
        modelYear: 2003,
        vin: " 1hgcm82633a004352 ",
      }),
    );

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        jobStatus: "queued",
        replayed: false,
        vinDecodeRequestId: decodeRequestId,
      },
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toEqual({
      p_correlation_id: correlationId,
      p_idempotency_key: "m2-vin-command-0001",
      p_model_year_hint: 2003,
      p_request_id: "request-m2-vin-0001",
      p_vin: "1HGCM82633A004352",
      p_workspace_id: workspaceId,
    });
  });

  it("reads the safe status projection without an idempotency header", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 1,
          attempt_count: 0,
          body_type: null,
          completed_at: null,
          cylinders: null,
          decoded_at: null,
          drivetrain: null,
          duplicate_candidates: [],
          duplicate_review: null,
          engine_liters: null,
          fuel_type: null,
          horsepower: null,
          job_id: jobId,
          job_status: "queued",
          last_error_classification: null,
          last_error_code: null,
          make: null,
          maximum_attempts: 8,
          model: null,
          model_year: null,
          model_year_hint: 2003,
          provider_key: null,
          provider_version: null,
          raw_result_reference: null,
          requested_at: "2026-07-16T12:00:00.000Z",
          retry_at: null,
          retryable: false,
          review_required: false,
          status: "queued",
          transmission: null,
          trim_name: null,
          vin: "1HGCM82633A004352",
          vin_decode_request_id: decodeRequestId,
          warnings: [],
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await getDecodeStatus(
      new Request(`http://localhost/api/v1/vin/decode/${decodeRequestId}`, {
        headers: headers(false),
      }),
      { params: Promise.resolve({ requestId: decodeRequestId }) },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        job: { status: "queued" },
        provider: null,
        suggestions: null,
        vin: "1HGCM82633A004352",
      },
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toEqual({
      p_vin_decode_request_id: decodeRequestId,
      p_workspace_id: workspaceId,
    });
  });

  it("projects manual consumption as terminal while preserving dead-letter job history", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(async () =>
        Response.json([
          {
            aggregate_version: 3,
            attempt_count: 8,
            body_type: null,
            completed_at: "2026-07-16T12:15:00.000Z",
            cylinders: null,
            decoded_at: null,
            drivetrain: null,
            duplicate_candidates: [],
            duplicate_review: null,
            engine_liters: null,
            fuel_type: null,
            horsepower: null,
            job_id: jobId,
            job_status: "dead_letter",
            last_error_classification: "permanent",
            last_error_code: "provider_terminal",
            make: null,
            maximum_attempts: 8,
            model: null,
            model_year: null,
            model_year_hint: 2003,
            provider_key: null,
            provider_version: null,
            raw_result_reference: null,
            requested_at: "2026-07-16T12:00:00.000Z",
            retry_at: null,
            retryable: false,
            review_required: false,
            status: "consumed",
            transmission: null,
            trim_name: null,
            vin: "1HGCM82633A004352",
            vin_decode_request_id: decodeRequestId,
            warnings: [],
          },
        ]),
      ),
    );

    const response = await getDecodeStatus(
      new Request(`http://localhost/api/v1/vin/decode/${decodeRequestId}`, {
        headers: headers(false),
      }),
      { params: Promise.resolve({ requestId: decodeRequestId }) },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        job: {
          retryable: false,
          reviewRequired: false,
          status: "dead_letter",
        },
        status: "consumed",
      },
    });
  });

  it("retries a visible failed job and records the operator reason", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 2,
          audit_event_id: auditEventId,
          job_id: jobId,
          job_status: "queued",
          outbox_event_id: outboxEventId,
          replayed: false,
          vin_decode_request_id: decodeRequestId,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await retryDecode(
      commandRequest(`/api/v1/vin/decode/${decodeRequestId}/retry`, {
        reason: "Provider recovered after a visible outage",
      }),
      { params: Promise.resolve({ requestId: decodeRequestId }) },
    );

    expect(response.status).toBe(202);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_reason: "Provider recovered after a visible outage",
      p_vin_decode_request_id: decodeRequestId,
    });
  });

  it("records a duplicate decision through a reasoned command", async () => {
    const reviewId = "a8600000-0000-4000-8000-000000000001";
    const vehicleId = "a8700000-0000-4000-8000-000000000001";
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(async () =>
        Response.json([
          {
            aggregate_version: 3,
            approved_for_intake: true,
            audit_event_id: auditEventId,
            decision: "reacquire_existing_vehicle",
            outbox_event_id: outboxEventId,
            replayed: false,
            vehicle_id: vehicleId,
            vin_decode_request_id: decodeRequestId,
            vin_duplicate_review_id: reviewId,
          },
        ]),
      ),
    );

    const response = await reviewDuplicate(
      commandRequest(`/api/v1/vin/decode/${decodeRequestId}/duplicate-review`, {
        decision: "reacquire_existing_vehicle",
        reason: "Closed historical holding verified",
      }),
      { params: Promise.resolve({ requestId: decodeRequestId }) },
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        approvedForIntake: true,
        vehicleId,
        vinDuplicateReviewId: reviewId,
      },
    });
  });

  it("creates manual inventory only through the dedicated dead-letter command", async () => {
    const inventoryUnitId = "a8800000-0000-4000-8000-000000000001";
    const vehicleId = "a8900000-0000-4000-8000-000000000001";
    const manualIntakeId = "a9000000-0000-4000-8000-000000000001";
    const locationId = "a9100000-0000-4000-8000-000000000001";
    const stockDefinitionId = "a9200000-0000-4000-8000-000000000001";
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          audit_event_id: auditEventId,
          inventory_unit_id: inventoryUnitId,
          linked_existing_open_unit: true,
          outbox_event_id: outboxEventId,
          replayed: false,
          stock_number: "S00044",
          terminal_job_id: jobId,
          vehicle_id: vehicleId,
          vin_decode_request_id: decodeRequestId,
          vin_decode_request_version: 3,
          vin_manual_inventory_intake_id: manualIntakeId,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await manualIntake(
      commandRequest(`/api/v1/vin/decode/${decodeRequestId}/manual-intake`, {
        conditionKey: "used.ready",
        confirmation: { accepted: true, expectedRequestVersion: 2 },
        duplicateDecision: null,
        inventory: {
          acquisitionDate: "2026-07-16",
          advertisedPriceMinor: "9007199254740992",
          currencyCode: "CAD",
          odometer: { unit: "km", value: 1200 },
          publicNotes: null,
        },
        locationId,
        manualReason: "Provider permanently rejected the request",
        stockDefinitionId,
        vehicleFacts: {
          bodyType: null,
          cylinders: null,
          drivetrain: null,
          engineLiters: null,
          fuelType: null,
          horsepower: null,
          make: "Honda",
          model: "Accord",
          modelYear: 2003,
          transmission: null,
          trimName: null,
        },
      }),
      { params: Promise.resolve({ requestId: decodeRequestId }) },
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        linkedExistingOpenUnit: true,
        terminalJobId: jobId,
        vinManualInventoryIntakeId: manualIntakeId,
      },
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_advertised_price_minor: "9007199254740992",
      p_manual_reason: "Provider permanently rejected the request",
      p_vin_decode_request_id: decodeRequestId,
    });
  });

  it.each([
    ["P0002", 404, "not_found"],
    ["55000", 409, "conflict"],
  ] as const)(
    "maps database state %s to a safe API error",
    async (sqlState, status, code) => {
      vi.stubGlobal(
        "fetch",
        vi.fn<typeof fetch>(async () =>
          Response.json({ code: sqlState }, { status: 400 }),
        ),
      );

      const response = await getDecodeStatus(
        new Request(`http://localhost/api/v1/vin/decode/${decodeRequestId}`, {
          headers: headers(false),
        }),
        { params: Promise.resolve({ requestId: decodeRequestId }) },
      );

      expect(response.status).toBe(status);
      await expect(response.json()).resolves.toMatchObject({ error: { code } });
    },
  );
});
