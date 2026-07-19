// Stable test IDs: T-INV-002, T-INV-003, T-JOB-003, T-API-001.
import { describe, expect, it, vi } from "vitest";

import {
  VinDecodeApplicationService,
  VinDecodeRpcContractError,
  VinDecodeValidationError,
  type VinDecodeRpcGateway,
} from "./vin-decode-api";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const requestId = "a8100000-0000-4000-8000-000000000001";
const jobId = "a8200000-0000-4000-8000-000000000001";
const outboxEventId = "a8300000-0000-4000-8000-000000000001";
const auditEventId = "a8400000-0000-4000-8000-000000000001";
const resultId = "a8500000-0000-4000-8000-000000000001";

const metadata = {
  accessToken: "header.payload.signature",
  correlationId: "a8600000-0000-4000-8000-000000000001",
  idempotencyKey: "vin-command-001",
  requestId: "request-vin-001",
  workspaceId,
} as const;

function gatewayReturning(value: unknown): VinDecodeRpcGateway {
  return { invoke: vi.fn(async () => value) };
}

function pendingStatusRow(echoedRequestId: string) {
  return {
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
    model_year_hint: null,
    provider_key: null,
    provider_version: null,
    raw_result_reference: null,
    requested_at: "2026-07-16T11:59:58.000Z",
    retry_at: null,
    retryable: false,
    review_required: false,
    status: "queued",
    transmission: null,
    trim_name: null,
    vin: "1HGCM82633A004352",
    vin_decode_request_id: echoedRequestId,
    warnings: [],
  };
}

describe("VinDecodeApplicationService", () => {
  it("normalizes a pasted VIN and invokes the durable request RPC exactly", async () => {
    const gateway = gatewayReturning([
      {
        aggregate_version: 1,
        audit_event_id: auditEventId,
        duplicate_candidate_count: 0,
        job_id: jobId,
        job_status: "queued",
        outbox_event_id: outboxEventId,
        replayed: false,
        vin_decode_request_id: requestId,
      },
    ]);
    const service = new VinDecodeApplicationService(gateway);

    await expect(
      service.requestDecode({
        body: { modelYear: 2003, vin: " 1hgcm82633a004352 " },
        metadata,
      }),
    ).resolves.toEqual({
      aggregateVersion: 1,
      auditEventId,
      duplicateCandidateCount: 0,
      jobId,
      jobStatus: "queued",
      outboxEventId,
      replayed: false,
      vinDecodeRequestId: requestId,
    });
    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: "request_vin_decode_job",
      parameters: {
        p_correlation_id: metadata.correlationId,
        p_idempotency_key: metadata.idempotencyKey,
        p_model_year_hint: 2003,
        p_request_id: metadata.requestId,
        p_vin: "1HGCM82633A004352",
        p_workspace_id: workspaceId,
      },
    });
  });

  it.each([
    { vin: "short" },
    { vin: "1HGCM82633A00I352" },
    { extraAuthority: workspaceId, vin: "1HGCM82633A004352" },
    { modelYear: 1800, vin: "1HGCM82633A004352" },
  ])("rejects invalid or authority-bearing request body %#", async (body) => {
    const gateway = gatewayReturning([]);
    await expect(
      new VinDecodeApplicationService(gateway).requestDecode({
        body,
        metadata,
      }),
    ).rejects.toBeInstanceOf(VinDecodeValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("maps the safe status projection without exposing a raw provider payload", async () => {
    const gateway = gatewayReturning([
      {
        aggregate_version: 2,
        attempt_count: 1,
        body_type: "Sedan/Saloon",
        completed_at: "2026-07-16T12:00:01.000Z",
        cylinders: 4,
        decoded_at: "2026-07-16T12:00:00.000Z",
        drivetrain: "4x2",
        duplicate_candidates: [
          {
            id: "a8700000-0000-4000-8000-000000000001",
            inventory_status: "closed",
            inventory_unit_id: "a8800000-0000-4000-8000-000000000001",
            kind: "historical_inventory",
            observed_at: "2026-07-16T11:59:59.000Z",
            stock_number: "N-00001",
            vehicle_id: "a8900000-0000-4000-8000-000000000001",
          },
        ],
        duplicate_review: null,
        engine_liters: "2.4",
        fuel_type: "Gasoline",
        horsepower: 160,
        job_id: jobId,
        job_status: "succeeded",
        last_error_classification: null,
        last_error_code: null,
        make: "HONDA",
        maximum_attempts: 8,
        model: "Accord",
        model_year: 2003,
        model_year_hint: 2003,
        provider_key: "nhtsa_vpic",
        provider_version: "vpic-4.06",
        raw_result_reference: resultId,
        requested_at: "2026-07-16T11:59:58.000Z",
        retry_at: null,
        retryable: false,
        review_required: false,
        status: "succeeded",
        transmission: "Automatic",
        trim_name: "EX-V6",
        vin: "1HGCM82633A004352",
        vin_decode_request_id: requestId,
        warnings: [],
      },
    ]);
    const result = await new VinDecodeApplicationService(gateway).getStatus({
      metadata: { accessToken: metadata.accessToken, workspaceId },
      vinDecodeRequestId: requestId,
    });

    expect(result).toMatchObject({
      job: { status: "succeeded" },
      provider: { key: "nhtsa_vpic", rawResultReference: resultId },
      suggestions: { engineLiters: "2.4", trimName: "EX-V6" },
      vin: "1HGCM82633A004352",
    });
    expect(JSON.stringify(result)).not.toContain("Results");
    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: "get_vin_decode_request",
      parameters: {
        p_vin_decode_request_id: requestId,
        p_workspace_id: workspaceId,
      },
    });
  });

  it("keeps dead-letter job history under a terminal consumed request status", async () => {
    const gateway = gatewayReturning([
      {
        ...pendingStatusRow(requestId),
        aggregate_version: 3,
        attempt_count: 8,
        completed_at: "2026-07-16T12:15:00.000Z",
        job_status: "dead_letter",
        last_error_classification: "permanent",
        last_error_code: "provider_terminal",
        retryable: false,
        review_required: false,
        status: "consumed",
      },
    ]);

    await expect(
      new VinDecodeApplicationService(gateway).getStatus({
        metadata: { accessToken: metadata.accessToken, workspaceId },
        vinDecodeRequestId: requestId,
      }),
    ).resolves.toMatchObject({
      job: {
        retryable: false,
        reviewRequired: false,
        status: "dead_letter",
      },
      status: "consumed",
    });
  });

  it("maps dead-letter retry and duplicate-review commands", async () => {
    const retryGateway = gatewayReturning([
      {
        aggregate_version: 2,
        audit_event_id: auditEventId,
        job_id: jobId,
        job_status: "queued",
        outbox_event_id: outboxEventId,
        replayed: false,
        vin_decode_request_id: requestId,
      },
    ]);
    await expect(
      new VinDecodeApplicationService(retryGateway).retry({
        body: { reason: "Retry after a visible provider rejection" },
        metadata,
        vinDecodeRequestId: requestId,
      }),
    ).resolves.toMatchObject({ jobStatus: "queued", replayed: false });
    expect(retryGateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({ functionName: "retry_vin_decode_job" }),
    );

    const reviewId = "a9000000-0000-4000-8000-000000000001";
    const vehicleId = "a9100000-0000-4000-8000-000000000001";
    const reviewGateway = gatewayReturning([
      {
        aggregate_version: 3,
        approved_for_intake: true,
        audit_event_id: auditEventId,
        decision: "reacquire_existing_vehicle",
        outbox_event_id: outboxEventId,
        replayed: false,
        vehicle_id: vehicleId,
        vin_decode_request_id: requestId,
        vin_duplicate_review_id: reviewId,
      },
    ]);
    await expect(
      new VinDecodeApplicationService(reviewGateway).reviewDuplicate({
        body: {
          decision: "reacquire_existing_vehicle",
          reason: "Closed historical unit verified",
        },
        metadata,
        vinDecodeRequestId: requestId,
      }),
    ).resolves.toMatchObject({
      approvedForIntake: true,
      decision: "reacquire_existing_vehicle",
      vehicleId,
      vinDuplicateReviewId: reviewId,
    });
    expect(reviewGateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "review_vin_duplicate_request",
        parameters: expect.objectContaining({
          p_decision: "reacquire_existing_vehicle",
          p_vin_decode_request_id: requestId,
        }),
      }),
    );
  });

  it("reports an approved open-unit linkage review truthfully", async () => {
    const reviewId = "a9000000-0000-4000-8000-000000000002";
    const vehicleId = "a9100000-0000-4000-8000-000000000002";
    const gateway = gatewayReturning([
      {
        aggregate_version: 3,
        approved_for_intake: true,
        audit_event_id: auditEventId,
        decision: "override_open_duplicate",
        outbox_event_id: outboxEventId,
        replayed: false,
        vehicle_id: vehicleId,
        vin_decode_request_id: requestId,
        vin_duplicate_review_id: reviewId,
      },
    ]);

    await expect(
      new VinDecodeApplicationService(gateway).reviewDuplicate({
        body: {
          decision: "override_open_duplicate",
          reason: "Manager confirmed safe linkage to the existing open unit",
        },
        metadata,
        vinDecodeRequestId: requestId,
      }),
    ).resolves.toMatchObject({
      approvedForIntake: true,
      decision: "override_open_duplicate",
      vinDuplicateReviewId: reviewId,
    });
  });

  it("fails closed when status, retry, or review rows echo another request", async () => {
    const otherRequestId = "a8100000-0000-4000-8000-000000000099";
    await expect(
      new VinDecodeApplicationService(
        gatewayReturning([pendingStatusRow(otherRequestId)]),
      ).getStatus({
        metadata: { accessToken: metadata.accessToken, workspaceId },
        vinDecodeRequestId: requestId,
      }),
    ).rejects.toBeInstanceOf(VinDecodeRpcContractError);

    await expect(
      new VinDecodeApplicationService(
        gatewayReturning([
          {
            aggregate_version: 2,
            audit_event_id: auditEventId,
            job_id: jobId,
            job_status: "queued",
            outbox_event_id: outboxEventId,
            replayed: false,
            vin_decode_request_id: otherRequestId,
          },
        ]),
      ).retry({
        body: { reason: "Retry visible failure" },
        metadata,
        vinDecodeRequestId: requestId,
      }),
    ).rejects.toBeInstanceOf(VinDecodeRpcContractError);

    await expect(
      new VinDecodeApplicationService(
        gatewayReturning([
          {
            aggregate_version: 3,
            approved_for_intake: true,
            audit_event_id: auditEventId,
            decision: "reuse_existing_vehicle",
            outbox_event_id: outboxEventId,
            replayed: false,
            vehicle_id: "a9100000-0000-4000-8000-000000000003",
            vin_decode_request_id: otherRequestId,
            vin_duplicate_review_id: "a9000000-0000-4000-8000-000000000003",
          },
        ]),
      ).reviewDuplicate({
        body: {
          decision: "reuse_existing_vehicle",
          reason: "Vehicle-only duplicate verified",
        },
        metadata,
        vinDecodeRequestId: requestId,
      }),
    ).rejects.toBeInstanceOf(VinDecodeRpcContractError);
  });

  it("fails closed on invalid identifiers and malformed database rows", async () => {
    const gateway = gatewayReturning([{ unexpected: true }]);
    const service = new VinDecodeApplicationService(gateway);
    await expect(
      service.getStatus({
        metadata: { accessToken: metadata.accessToken, workspaceId },
        vinDecodeRequestId: "not-a-uuid",
      }),
    ).rejects.toMatchObject({
      code: "invalid_vin_decode_request_id",
    });
    expect(gateway.invoke).not.toHaveBeenCalled();

    await expect(
      service.requestDecode({
        body: { vin: "1HGCM82633A004352" },
        metadata,
      }),
    ).rejects.toBeInstanceOf(VinDecodeRpcContractError);
  });
});
