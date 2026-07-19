import { describe, expect, it, vi } from "vitest";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  M2InventoryApplicationService,
  M2InventoryRpcContractError,
  M2InventoryValidationError,
} from "./m2-inventory-api";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const inventoryUnitId = "20000000-0000-4000-8000-000000000001";
const locationId = "30000000-0000-4000-8000-000000000001";
const eventId = "40000000-0000-4000-8000-000000000001";
const auditEventId = "60000000-0000-4000-8000-000000000001";
const outboxEventId = "70000000-0000-4000-8000-000000000001";

function service(result: unknown) {
  const gateway: AuthenticatedRpcGateway = {
    invoke: vi.fn(async () => result),
  };
  return { application: new M2InventoryApplicationService(gateway), gateway };
}

function input(body: unknown) {
  return {
    body,
    inventoryUnitId,
    metadata: {
      accessToken: "user.header.signature",
      correlationId: "50000000-0000-4000-8000-000000000001",
      idempotencyKey: "inventory-command-0001",
      requestId: "request-m2-inventory-1",
      workspaceId,
    },
  };
}

describe("T-INV-004 / T-API-001 M2InventoryApplicationService", () => {
  it("round-trips PostgreSQL timestamp precision without coupling a hidden internal note", async () => {
    const { application, gateway } = service([
      {
        aggregate_version: 6,
        audit_event_id: auditEventId,
        canonical_status: "active",
        inventory_unit_id: inventoryUnitId,
        outbox_event_id: outboxEventId,
        replayed: false,
        state_key: "ready",
      },
    ]);

    await expect(
      application.updateDetails(
        input({
          acquisitionDate: "2026-07-10",
          acquiredAt: "2026-07-10T14:30:00Z",
          advertisedPriceMinor: "2499500",
          availableAt: "2026-07-11T09:15:00.123456+00:00",
          conditionKey: "used.ready",
          expectedSalePrice: { amountMinor: "2650000", currencyCode: "cad" },
          expectedVersion: 5,
          odometer: { unit: "km", value: 41_250 },
          publicNotes: "Single owner",
        }),
      ),
    ).resolves.toEqual({
      aggregateVersion: 6,
      auditEventId,
      canonicalStatus: "active",
      inventoryUnitId,
      outboxEventId,
      replayed: false,
      stateKey: "ready",
    });

    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: "user.header.signature",
      functionName: "update_inventory_unit_details",
      parameters: {
        p_acquired_at: "2026-07-10T14:30:00Z",
        p_acquisition_date: "2026-07-10",
        p_advertised_price_minor: "2499500",
        p_available_at: "2026-07-11T09:15:00.123456+00:00",
        p_condition_key: "used.ready",
        p_correlation_id: "50000000-0000-4000-8000-000000000001",
        p_expected_sale_price_currency_code: "CAD",
        p_expected_sale_price_minor: "2650000",
        p_expected_version: 5,
        p_idempotency_key: "inventory-command-0001",
        p_internal_notes: null,
        p_inventory_unit_id: inventoryUnitId,
        p_odometer_unit: "km",
        p_odometer_value: 41_250,
        p_public_notes: "Single owner",
        p_request_id: "request-m2-inventory-1",
        p_update_internal_notes: false,
        p_workspace_id: workspaceId,
      },
    });
  });

  it("only sends an internal-note mutation when the field is explicitly present", async () => {
    const { application, gateway } = service([
      {
        aggregate_version: 2,
        audit_event_id: auditEventId,
        canonical_status: "draft",
        inventory_unit_id: inventoryUnitId,
        outbox_event_id: outboxEventId,
        replayed: false,
        state_key: "draft",
      },
    ]);

    await application.updateDetails(
      input({
        acquisitionDate: null,
        acquiredAt: null,
        advertisedPriceMinor: null,
        availableAt: null,
        conditionKey: null,
        expectedSalePrice: null,
        expectedVersion: 1,
        internalNotes: "  restricted note  ",
        odometer: null,
        publicNotes: null,
      }),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        parameters: expect.objectContaining({
          p_internal_notes: "restricted note",
          p_update_internal_notes: true,
        }),
      }),
    );
  });

  it("maps a strict location transfer to the authenticated workspace RPC", async () => {
    const { application, gateway } = service([
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
    ]);

    await expect(
      application.transferLocation(
        input({
          expectedVersion: 3,
          reason: "Moved to the delivery area",
          toLocationId: locationId,
        }),
      ),
    ).resolves.toEqual({
      aggregateVersion: 4,
      auditEventId,
      canonicalStatus: "active",
      inventoryUnitId,
      locationEventId: eventId,
      locationId,
      outboxEventId,
      replayed: false,
      stateKey: "ready",
    });
    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: "user.header.signature",
      functionName: "transfer_inventory_unit_location",
      parameters: {
        p_correlation_id: "50000000-0000-4000-8000-000000000001",
        p_expected_version: 3,
        p_idempotency_key: "inventory-command-0001",
        p_inventory_unit_id: inventoryUnitId,
        p_reason: "Moved to the delivery area",
        p_request_id: "request-m2-inventory-1",
        p_to_location_id: locationId,
        p_workspace_id: workspaceId,
      },
    });
  });

  it("maps a versioned transition without inventing tenant workflow behavior", async () => {
    const { application, gateway } = service([
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
    ]);

    await expect(
      application.transitionWorkflow(
        input({
          expectedVersion: 7,
          reason: null,
          transitionKey: "in_preparation__ready",
        }),
      ),
    ).resolves.toEqual({
      aggregateVersion: 8,
      auditEventId,
      canonicalStatus: "active",
      inventoryUnitId,
      outboxEventId,
      replayed: false,
      stateKey: "ready",
      workflowEventId: eventId,
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "transition_inventory_workflow",
        parameters: expect.objectContaining({
          p_expected_version: 7,
          p_reason: null,
          p_transition_key: "in_preparation__ready",
        }),
      }),
    );
  });

  it.each([
    ["invalid inventory ID", { ...input({}), inventoryUnitId: "not-a-uuid" }],
    [
      "extra body authority",
      input({
        expectedVersion: 1,
        reason: "move",
        toLocationId: locationId,
        workspaceId,
      }),
    ],
    [
      "unsafe transition key",
      input({
        expectedVersion: 1,
        reason: null,
        transitionKey: "javascript:run()",
      }),
    ],
  ])("rejects %s before RPC invocation", async (_label, invalidInput) => {
    const { application, gateway } = service([]);
    const action =
      "toLocationId" in (invalidInput.body as Record<string, unknown>)
        ? application.transferLocation(invalidInput)
        : application.transitionWorkflow(invalidInput);
    await expect(action).rejects.toBeInstanceOf(M2InventoryValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("fails closed on extra or malformed RPC response fields", async () => {
    const { application } = service([
      {
        aggregate_version: 2,
        audit_event_id: auditEventId,
        canonical_status: "active",
        inventory_unit_id: inventoryUnitId,
        outbox_event_id: outboxEventId,
        replayed: false,
        state_key: "ready",
        workflow_event_id: eventId,
        workspace_secret: "must-not-cross",
      },
    ]);

    await expect(
      application.transitionWorkflow(
        input({
          expectedVersion: 1,
          reason: null,
          transitionKey: "prepare",
        }),
      ),
    ).rejects.toBeInstanceOf(M2InventoryRpcContractError);
  });

  it("fails closed when an RPC echoes a different inventory aggregate", async () => {
    const { application } = service([
      {
        aggregate_version: 2,
        audit_event_id: auditEventId,
        canonical_status: "active",
        inventory_unit_id: "20000000-0000-4000-8000-000000000099",
        outbox_event_id: outboxEventId,
        replayed: false,
        state_key: "ready",
        workflow_event_id: eventId,
      },
    ]);

    await expect(
      application.transitionWorkflow(
        input({
          expectedVersion: 1,
          reason: null,
          transitionKey: "prepare",
        }),
      ),
    ).rejects.toBeInstanceOf(M2InventoryRpcContractError);
  });
});

describe("T-INV-004 / T-API-001 M2 inventory operator reads and fact correction", () => {
  const vehicleId = "21000000-0000-4000-8000-000000000001";
  const historyId = "41000000-0000-4000-8000-000000000001";

  it("maps the exact permission-masked operator projection", async () => {
    const { application, gateway } = service([
      {
        acquired_at: "2026-07-01T10:00:00.000Z",
        acquisition_date: "2026-07-01",
        advertised_price_minor: "2500000",
        aggregate_version: 7,
        allowed_transitions: [
          {
            canonicalStatus: "active",
            key: "publish",
            labels: { en: "Publish", fr: "Publier" },
            reasonRequired: false,
            toStateKey: "available",
          },
        ],
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
        condition_key: "used.ready",
        currency_code: "CAD",
        estimated_gross_minor: "500000",
        expected_sale_price_minor: "2600000",
        has_recent_strong_authentication: true,
        internal_notes: null,
        inventory_unit_id: inventoryUnitId,
        location_id: locationId,
        location_name: "Synthetic showroom",
        odometer_unit: "km",
        odometer_value: "42000",
        posted_cost_minor: "2100000",
        public_notes: "Ready",
        sold_at: null,
        stock_number: "S001",
        updated_at: "2026-07-16T12:00:00.000Z",
        vehicle_facts: {
          bodyType: "SUV",
          cylinders: 4,
          drivetrain: "AWD",
          engineLiters: "2.5",
          factsVersion: 3,
          fuelType: "Gasoline",
          horsepower: 200,
          make: "Synthetic",
          model: "Operator",
          modelYear: 2025,
          transmission: "Automatic",
          trimName: "Lab",
          vin: "1HGCM82633A004352",
        },
        vehicle_id: vehicleId,
        workflow_configuration_version: "1.0.0",
        workflow_instance_version: 7,
        workflow_state_key: "in_preparation",
      },
    ]);

    await expect(
      application.getOperations({
        accessToken: "user.header.signature",
        inventoryUnitId,
        workspaceId,
      }),
    ).resolves.toMatchObject({
      aggregateVersion: 7,
      capabilities: { canReadInternal: false, canReadCosts: true },
      estimatedGrossMinor: "500000",
      internalNotes: null,
      location: { id: locationId, name: "Synthetic showroom" },
      vehicleFacts: { factsVersion: 3, vin: "1HGCM82633A004352" },
      workflowConfigurationVersion: "1.0.0",
    });
    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: "user.header.signature",
      functionName: "get_inventory_unit_operations",
      parameters: {
        p_inventory_unit_id: inventoryUnitId,
        p_workspace_id: workspaceId,
      },
    });
  });

  it("returns only the bounded active location contract", async () => {
    const { application } = service([
      {
        locale: "fr-CA",
        location_id: locationId,
        location_key: "showroom.main",
        name: "Salle de montre",
        timezone: "America/Toronto",
        version: 2,
      },
    ]);
    await expect(
      application.listActiveLocations({
        accessToken: "user.header.signature",
        workspaceId,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: locationId,
          key: "showroom.main",
          locale: "fr-CA",
          name: "Salle de montre",
          timezone: "America/Toronto",
          version: 2,
        },
      ],
    });
  });

  it("sends a full, reasoned fact replacement through the step-up RPC", async () => {
    const { application, gateway } = service([
      {
        audit_event_id: auditEventId,
        facts_version: 4,
        history_id: historyId,
        outbox_event_id: outboxEventId,
        replayed: false,
        vehicle_id: vehicleId,
      },
    ]);
    const body = {
      expectedFactsVersion: 3,
      facts: {
        bodyType: "Sedan",
        cylinders: 4,
        drivetrain: "FWD",
        engineLiters: "2.0",
        fuelType: "Gasoline",
        horsepower: 190,
        make: "Synthetic",
        model: "Corrected",
        modelYear: 2025,
        transmission: "Automatic",
        trimName: "Lab",
      },
      reason: "Registration document correction",
    };
    await expect(
      application.overrideVehicleFacts({
        body,
        metadata: input({}).metadata,
        vehicleId,
      }),
    ).resolves.toEqual({
      auditEventId,
      factsVersion: 4,
      historyId,
      outboxEventId,
      replayed: false,
      vehicleId,
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "override_vehicle_facts",
        parameters: expect.objectContaining({
          p_expected_facts_version: 3,
          p_reason: "Registration document correction",
          p_vehicle_id: vehicleId,
        }),
      }),
    );
  });

  it("rejects partial or authority-bearing fact replacements before the RPC", async () => {
    const { application, gateway } = service([]);
    await expect(
      application.overrideVehicleFacts({
        body: {
          expectedFactsVersion: 1,
          facts: { make: "Only one field" },
          reason: "unsafe partial overwrite",
          workspaceId,
        },
        metadata: input({}).metadata,
        vehicleId,
      }),
    ).rejects.toBeInstanceOf(M2InventoryValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("fails closed if the detail RPC adds an unreviewed field", async () => {
    const { application } = service([{ workspace_secret: "no" }]);
    await expect(
      application.getOperations({
        accessToken: "user.header.signature",
        inventoryUnitId,
        workspaceId,
      }),
    ).rejects.toBeInstanceOf(M2InventoryRpcContractError);
  });
});
