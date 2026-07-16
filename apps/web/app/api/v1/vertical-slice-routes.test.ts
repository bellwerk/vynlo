// Stable test IDs: T-INV-001, T-DEAL-001, T-DOC-001, T-API-001.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { POST as createDeal } from "./deals/route";
import { POST as requestPreview } from "./documents/preview/route";
import { POST as createInventory } from "./inventory-units/route";
import { POST as createParty } from "./parties/route";

const workspaceId = "00000000-0000-4000-8000-000000000001";
const correlationId = "00000000-0000-4000-8000-000000000002";
const stockDefinitionId = "00000000-0000-4000-8000-000000000003";
const locationId = "00000000-0000-4000-8000-000000000018";
const inventoryUnitId = "00000000-0000-4000-8000-000000000004";
const vehicleId = "00000000-0000-4000-8000-000000000005";
const partyId = "00000000-0000-4000-8000-000000000006";
const dealId = "00000000-0000-4000-8000-000000000007";
const participantId = "00000000-0000-4000-8000-000000000008";
const inventoryLinkId = "00000000-0000-4000-8000-000000000009";
const templateVersionId = "00000000-0000-4000-8000-000000000010";
const documentId = "00000000-0000-4000-8000-000000000011";
const outboxEventId = "00000000-0000-4000-8000-000000000012";
const jobId = "00000000-0000-4000-8000-000000000013";
const vinDecodeRequestId = "00000000-0000-4000-8000-000000000014";
const vinDecodeResultId = "00000000-0000-4000-8000-000000000015";
const vinInventoryIntakeId = "00000000-0000-4000-8000-000000000016";
const auditEventId = "00000000-0000-4000-8000-000000000017";
const userAccessToken = "user-header.user-payload.user-signature";
const publicProjectKey = "sb_publishable_public_project_key_material_0001";
const serviceRoleSecret = "server-service-role-must-never-be-used";

const inventoryBody = Object.freeze({
  conditionKey: "used.ready",
  confirmation: {
    accepted: true,
    expectedRequestVersion: 4,
    vinDecodeResultId,
  },
  inventory: {
    acquisitionDate: null,
    advertisedPriceMinor: "1250000",
    currencyCode: "CAD",
    odometer: { unit: "km", value: 150 },
    publicNotes: null,
  },
  locationId,
  stockDefinitionId,
  vehicleFacts: {
    bodyType: "Sedan/Saloon",
    cylinders: 4,
    drivetrain: "4x2",
    engineLiters: "2.4",
    fuelType: "Gasoline",
    horsepower: 160,
    make: "Toyota",
    model: "Corolla",
    modelYear: 2025,
    transmission: "Automatic",
    trimName: "LE",
  },
  vinDecodeRequestId,
});

const partyBody = Object.freeze({
  displayName: "Alice Example",
  partyType: "person",
});

const dealBody = Object.freeze({
  currencyCode: "CAD",
  dealTypeKey: "retail.cash",
  inventory: { inventoryUnitId, roleKey: "sold" },
  notes: null,
  participant: { partyId, roleKey: "customer.primary" },
});

const previewBody = Object.freeze({
  dealId,
  locale: "en-CA",
  templateVersionId,
});

function commandRequest(path: string, body: unknown): Request {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: {
      Authorization: `Bearer ${userAccessToken}`,
      "Content-Type": "application/json",
      "Idempotency-Key": "command-key-0001",
      "X-Correlation-Id": correlationId,
      "X-Request-Id": "request-0001",
      "X-Workspace-Id": workspaceId,
    },
    method: "POST",
  });
}

function assertForwardedRequest(
  fetchImplementation: ReturnType<typeof vi.fn<typeof fetch>>,
  functionName: string,
): Record<string, unknown> {
  const [url, init] = fetchImplementation.mock.calls[0] ?? [];
  const headers = new Headers(init?.headers);
  expect(url).toBe(`http://127.0.0.1:54321/rest/v1/rpc/${functionName}`);
  expect(headers.get("apikey")).toBe(publicProjectKey);
  expect(headers.get("authorization")).toBe(`Bearer ${userAccessToken}`);
  expect(headers.get("content-profile")).toBe("app");
  expect(headers.get("apikey")).not.toBe(serviceRoleSecret);
  const parsed: unknown = JSON.parse(String(init?.body));
  return z.record(z.string(), z.unknown()).parse(parsed);
}

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", publicProjectKey);
  vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", serviceRoleSecret);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("authenticated vertical-slice routes", () => {
  it("creates inventory with the header workspace and returns a camelCase envelope", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          audit_event_id: auditEventId,
          inventory_unit_id: inventoryUnitId,
          linked_existing_open_unit: false,
          outbox_event_id: outboxEventId,
          replayed: false,
          stock_number: "V0001",
          vehicle_id: vehicleId,
          vin_decode_request_id: vinDecodeRequestId,
          vin_decode_request_version: 5,
          vin_inventory_intake_id: vinInventoryIntakeId,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createInventory(
      commandRequest("/api/v1/inventory-units", inventoryBody),
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({
      data: {
        auditEventId,
        inventoryUnitId,
        linkedExistingOpenUnit: false,
        outboxEventId,
        replayed: false,
        stockNumber: "V0001",
        vehicleId,
        vinDecodeRequestId,
        vinDecodeRequestVersion: 5,
        vinInventoryIntakeId,
      },
    });
    expect(response.headers.get("x-request-id")).toBe("request-0001");
    expect(response.headers.get("x-correlation-id")).toBe(correlationId);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(
      assertForwardedRequest(
        fetchImplementation,
        "create_inventory_unit_from_vin_decode",
      ),
    ).toMatchObject({
      p_correlation_id: correlationId,
      p_condition_key: "used.ready",
      p_expected_request_version: 4,
      p_facts_confirmed: true,
      p_idempotency_key: "command-key-0001",
      p_location_id: locationId,
      p_stock_definition_id: stockDefinitionId,
      p_vin_decode_request_id: vinDecodeRequestId,
      p_vin_decode_result_id: vinDecodeResultId,
      p_workspace_id: workspaceId,
    });
  });

  it("returns 200 and replayed=true for an idempotent party replay", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([{ party_id: partyId, replayed: true }]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createParty(
      commandRequest("/api/v1/parties", partyBody),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      data: { partyId, replayed: true },
    });
    expect(assertForwardedRequest(fetchImplementation, "create_party")).toEqual(
      {
        p_correlation_id: correlationId,
        p_display_name: "Alice Example",
        p_idempotency_key: "command-key-0001",
        p_party_type: "person",
        p_request_id: "request-0001",
        p_workspace_id: workspaceId,
      },
    );
  });

  it("creates a deal draft through the exact RPC argument shape", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          deal_id: dealId,
          inventory_link_id: inventoryLinkId,
          participant_id: participantId,
          replayed: false,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createDeal(
      commandRequest("/api/v1/deals", dealBody),
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({
      data: { dealId, inventoryLinkId, participantId, replayed: false },
    });
    expect(
      assertForwardedRequest(fetchImplementation, "create_deal_draft"),
    ).toMatchObject({
      p_inventory_unit_id: inventoryUnitId,
      p_party_id: partyId,
      p_workspace_id: workspaceId,
    });
  });

  it("queues preview work atomically and returns document plus job status", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          document_id: documentId,
          job_id: jobId,
          job_status: "queued",
          outbox_event_id: outboxEventId,
          preview_status: "queued",
          replayed: false,
          watermark: "DRAFT / NON-PRODUCTION",
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await requestPreview(
      commandRequest("/api/v1/documents/preview", previewBody),
    );

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toEqual({
      data: {
        documentId,
        jobId,
        jobStatus: "queued",
        outboxEventId,
        previewStatus: "queued",
        replayed: false,
        watermark: "DRAFT / NON-PRODUCTION",
      },
    });
    expect(
      assertForwardedRequest(
        fetchImplementation,
        "request_document_preview_job",
      ),
    ).toEqual({
      p_correlation_id: correlationId,
      p_deal_id: dealId,
      p_idempotency_key: "command-key-0001",
      p_locale: "en-CA",
      p_request_id: "request-0001",
      p_template_version_id: templateVersionId,
      p_workspace_id: workspaceId,
    });
  });

  it("rejects body workspace spoofing before any database request", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createParty(
      commandRequest("/api/v1/parties", { ...partyBody, workspaceId }),
    );

    expect(response.status).toBe(422);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "invalid_request_body" },
    });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("rejects malformed JWT, malformed JSON, and oversized bodies", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const invalidAuth = commandRequest("/api/v1/parties", partyBody);
    invalidAuth.headers.set("Authorization", "Bearer opaque-not-jwt");
    const authResponse = await createParty(invalidAuth);
    expect(authResponse.status).toBe(401);
    await expect(authResponse.json()).resolves.toMatchObject({
      error: { code: "authentication_required" },
    });

    const malformedJson = commandRequest("/api/v1/parties", partyBody);
    const malformedResponse = await createParty(
      new Request(malformedJson.url, {
        body: "{",
        headers: malformedJson.headers,
        method: "POST",
      }),
    );
    expect(malformedResponse.status).toBe(400);
    await expect(malformedResponse.json()).resolves.toMatchObject({
      error: { code: "invalid_json" },
    });

    const oversized = commandRequest("/api/v1/parties", {
      displayName: "x".repeat(33_000),
      partyType: "person",
    });
    const oversizedResponse = await createParty(oversized);
    expect(oversizedResponse.status).toBe(400);
    await expect(oversizedResponse.json()).resolves.toMatchObject({
      error: { code: "request_body_too_large" },
    });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it.each([
    [401, "PGRST301", 401, "authentication_required"],
    [400, "42501", 403, "permission_denied"],
    [400, "23505", 409, "conflict"],
    [400, "22023", 400, "invalid_request"],
    [400, "23514", 422, "unprocessable_command"],
    [429, "PGRST429", 429, "rate_limited"],
    [500, "XX000", 503, "service_unavailable"],
  ] as const)(
    "maps PostgREST %s/%s to safe HTTP %s",
    async (upstreamStatus, sqlState, expectedStatus, expectedCode) => {
      const fetchImplementation = vi.fn<typeof fetch>(async () =>
        Response.json(
          {
            code: sqlState,
            details: serviceRoleSecret,
            message: `private ${userAccessToken}`,
          },
          { status: upstreamStatus },
        ),
      );
      vi.stubGlobal("fetch", fetchImplementation);

      const response = await createParty(
        commandRequest("/api/v1/parties", partyBody),
      );
      const serialized = JSON.stringify(await response.json());

      expect(response.status).toBe(expectedStatus);
      expect(JSON.parse(serialized)).toMatchObject({
        error: { code: expectedCode },
      });
      expect(serialized).not.toContain(serviceRoleSecret);
      expect(serialized).not.toContain(userAccessToken);
      expect(response.headers.get("x-request-id")).toBe("request-0001");
      expect(response.headers.get("x-correlation-id")).toBe(correlationId);
    },
  );

  it("fails closed on malformed RPC success data", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(async () =>
        Response.json([
          { party_id: partyId, replayed: false, secret: serviceRoleSecret },
        ]),
      ),
    );

    const response = await createParty(
      commandRequest("/api/v1/parties", partyBody),
    );
    const serialized = JSON.stringify(await response.json());

    expect(response.status).toBe(503);
    expect(serialized).toContain("service_unavailable");
    expect(serialized).not.toContain(serviceRoleSecret);
  });
});
