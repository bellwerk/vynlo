import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { GET as listLocations } from "../locations/route";
import { POST as overrideFacts } from "../vehicles/[id]/facts-override/route";
import { GET as getOperations, PATCH as updateDetails } from "./[id]/route";
import { POST as transferLocation } from "./[id]/location-transfers/route";
import { POST as transitionWorkflow } from "./[id]/transition/route";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const inventoryUnitId = "20000000-0000-4000-8000-000000000001";
const locationId = "30000000-0000-4000-8000-000000000001";
const eventId = "40000000-0000-4000-8000-000000000001";
const correlationId = "50000000-0000-4000-8000-000000000001";
const auditEventId = "60000000-0000-4000-8000-000000000001";
const outboxEventId = "70000000-0000-4000-8000-000000000001";
const publicProjectKey = "sb_publishable_public_project_key_material";
const userToken = "user.header.signature";

function request(path: string, body: unknown): Request {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: {
      Authorization: `Bearer ${userToken}`,
      "Content-Type": "application/json",
      "Idempotency-Key": "m2-inventory-command-0001",
      "X-Correlation-Id": correlationId,
      "X-Request-Id": "request-m2-inventory-0001",
      "X-Workspace-Id": workspaceId,
    },
    method: "POST",
  });
}

function patchRequest(path: string, body: unknown): Request {
  const base = request(path, body);
  return new Request(base, { method: "PATCH" });
}

function queryRequest(path: string): Request {
  return new Request(`http://localhost${path}`, {
    headers: {
      Authorization: `Bearer ${userToken}`,
      "X-Correlation-Id": correlationId,
      "X-Request-Id": "request-m2-inventory-query-0001",
      "X-Workspace-Id": workspaceId,
    },
  });
}

describe("T-INV-004 / T-API-001 Milestone 2 inventory command routes", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", publicProjectKey);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("updates inventory details through the exact workspace RPC contract", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 2,
          audit_event_id: auditEventId,
          canonical_status: "draft",
          inventory_unit_id: inventoryUnitId,
          outbox_event_id: outboxEventId,
          replayed: false,
          state_key: "draft",
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await updateDetails(
      patchRequest(`/api/v1/inventory-units/${inventoryUnitId}`, {
        acquisitionDate: null,
        acquiredAt: null,
        advertisedPriceMinor: "1500000",
        availableAt: null,
        conditionKey: "used",
        expectedSalePrice: null,
        expectedVersion: 1,
        odometer: { unit: "km", value: 90_000 },
        publicNotes: null,
      }),
      { params: Promise.resolve({ id: inventoryUnitId }) },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        aggregateVersion: 2,
        inventoryUnitId,
        replayed: false,
      },
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_advertised_price_minor: "1500000",
      p_internal_notes: null,
      p_inventory_unit_id: inventoryUnitId,
      p_update_internal_notes: false,
    });
  });

  it("transfers location through the authenticated workspace command boundary", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 4,
          audit_event_id: auditEventId,
          canonical_status: "active",
          inventory_unit_id: inventoryUnitId,
          location_event_id: eventId,
          outbox_event_id: outboxEventId,
          replayed: false,
          state_key: "ready",
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await transferLocation(
      request(`/api/v1/inventory-units/${inventoryUnitId}/location-transfers`, {
        expectedVersion: 3,
        reason: "Moved to delivery",
        toLocationId: locationId,
      }),
      { params: Promise.resolve({ id: inventoryUnitId }) },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      data: {
        aggregateVersion: 4,
        auditEventId,
        canonicalStatus: "active",
        inventoryUnitId,
        locationEventId: eventId,
        locationId,
        outboxEventId,
        replayed: false,
        stateKey: "ready",
      },
    });
    const [url, init] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/transfer_inventory_unit_location",
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      p_correlation_id: correlationId,
      p_expected_version: 3,
      p_idempotency_key: "m2-inventory-command-0001",
      p_inventory_unit_id: inventoryUnitId,
      p_reason: "Moved to delivery",
      p_request_id: "request-m2-inventory-0001",
      p_to_location_id: locationId,
      p_workspace_id: workspaceId,
    });
    const headers = new Headers(init?.headers);
    expect(headers.get("authorization")).toBe(`Bearer ${userToken}`);
    expect(headers.get("apikey")).toBe(publicProjectKey);
    expect(headers.get("content-profile")).toBe("app");
  });

  it("executes a versioned workflow transition with a tenant-neutral key", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 8,
          audit_event_id: auditEventId,
          canonical_status: "active",
          inventory_unit_id: inventoryUnitId,
          outbox_event_id: outboxEventId,
          replayed: false,
          state_key: "ready",
          workflow_event_id: eventId,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await transitionWorkflow(
      request(`/api/v1/inventory-units/${inventoryUnitId}/transition`, {
        expectedVersion: 7,
        reason: null,
        transitionKey: "in_preparation__ready",
      }),
      { params: Promise.resolve({ id: inventoryUnitId }) },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        aggregateVersion: 8,
        canonicalStatus: "active",
        inventoryUnitId,
        stateKey: "ready",
        workflowEventId: eventId,
      },
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_expected_version: 7,
      p_reason: null,
      p_transition_key: "in_preparation__ready",
      p_workspace_id: workspaceId,
    });
  });

  it("rejects path/body authority and malformed versions before PostgREST", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await transferLocation(
      request("/api/v1/inventory-units/not-a-uuid/location-transfers", {
        expectedVersion: 0,
        reason: "move",
        toLocationId: locationId,
        workspaceId,
      }),
      { params: Promise.resolve({ id: "not-a-uuid" }) },
    );

    expect(response.status).toBe(422);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "invalid_inventory_unit_id" },
    });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("reads the exact masked operator dossier and active location choices", async () => {
    const vehicleId = "21000000-0000-4000-8000-000000000001";
    const fetchImplementation = vi.fn<typeof fetch>(async (input) =>
      String(input).endsWith("/list_active_inventory_locations")
        ? Response.json([
            {
              locale: "en-CA",
              location_id: locationId,
              location_key: "showroom.main",
              name: "Main showroom",
              timezone: "America/Toronto",
              version: 1,
            },
          ])
        : Response.json([
            {
              acquired_at: null,
              acquisition_date: "2026-07-01",
              advertised_price_minor: "2500000",
              aggregate_version: 2,
              allowed_transitions: [],
              available_at: null,
              can_create_costs: true,
              can_override_facts: true,
              can_read_costs: true,
              can_read_internal: false,
              can_reverse_costs: true,
              can_transfer_location: true,
              can_transition_workflow: true,
              can_update_details: true,
              can_update_internal: false,
              canonical_status: "active",
              closed_at: null,
              condition_key: null,
              currency_code: "CAD",
              estimated_gross_minor: "500000",
              expected_sale_price_minor: "2600000",
              has_recent_strong_authentication: true,
              internal_notes: null,
              inventory_unit_id: inventoryUnitId,
              location_id: locationId,
              location_name: "Main showroom",
              odometer_unit: "km",
              odometer_value: "40000",
              posted_cost_minor: "2100000",
              public_notes: null,
              sold_at: null,
              stock_number: "S001",
              updated_at: "2026-07-16T12:00:00.000Z",
              vehicle_facts: {
                bodyType: null,
                cylinders: null,
                drivetrain: null,
                engineLiters: null,
                factsVersion: 1,
                fuelType: null,
                horsepower: null,
                make: "Synthetic",
                model: "Operator",
                modelYear: 2025,
                transmission: null,
                trimName: null,
                vin: "1HGCM82633A004352",
              },
              vehicle_id: vehicleId,
              workflow_configuration_version: "1.0.0",
              workflow_instance_version: 2,
              workflow_state_key: "in_preparation",
            },
          ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const detailResponse = await getOperations(
      queryRequest(`/api/v1/inventory-units/${inventoryUnitId}`),
      { params: Promise.resolve({ id: inventoryUnitId }) },
    );
    const locationResponse = await listLocations(
      queryRequest("/api/v1/locations"),
    );

    expect(detailResponse.status).toBe(200);
    await expect(detailResponse.json()).resolves.toMatchObject({
      data: {
        capabilities: { canReadInternal: false },
        estimatedGrossMinor: "500000",
        internalNotes: null,
        inventoryUnitId,
      },
    });
    await expect(locationResponse.json()).resolves.toMatchObject({
      data: { items: [{ id: locationId, name: "Main showroom" }] },
    });
  });

  it("routes a reasoned full facts replacement to the vehicle boundary", async () => {
    const vehicleId = "21000000-0000-4000-8000-000000000001";
    const historyId = "22000000-0000-4000-8000-000000000001";
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          audit_event_id: auditEventId,
          facts_version: 2,
          history_id: historyId,
          outbox_event_id: outboxEventId,
          replayed: false,
          vehicle_id: vehicleId,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await overrideFacts(
      request(`/api/v1/vehicles/${vehicleId}/facts-override`, {
        expectedFactsVersion: 1,
        facts: {
          bodyType: "SUV",
          cylinders: 4,
          drivetrain: "AWD",
          engineLiters: "2.5",
          fuelType: "Gasoline",
          horsepower: 200,
          make: "Synthetic",
          model: "Corrected",
          modelYear: 2025,
          transmission: "Automatic",
          trimName: "Lab",
        },
        reason: "Registration correction",
      }),
      { params: Promise.resolve({ id: vehicleId }) },
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({
      data: { factsVersion: 2, historyId, vehicleId },
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_expected_facts_version: 1,
      p_reason: "Registration correction",
      p_vehicle_id: vehicleId,
    });
  });
});
