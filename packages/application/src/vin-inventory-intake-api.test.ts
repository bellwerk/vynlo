// Stable test IDs: T-INV-001, T-INV-002, T-INV-003, T-NUM-001, T-API-001.
import { describe, expect, it, vi } from "vitest";

import {
  VinInventoryIntakeApplicationService,
  VinInventoryIntakeRpcContractError,
  VinInventoryIntakeValidationError,
  type VinInventoryIntakeRpcGateway,
} from "./vin-inventory-intake-api";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const vinDecodeRequestId = "b1000000-0000-4000-8000-000000000001";
const vinDecodeResultId = "b2000000-0000-4000-8000-000000000001";
const stockDefinitionId = "b3000000-0000-4000-8000-000000000001";
const locationId = "b3000000-0000-4000-8000-000000000002";
const intakeId = "b4000000-0000-4000-8000-000000000001";
const inventoryUnitId = "b5000000-0000-4000-8000-000000000001";
const vehicleId = "b6000000-0000-4000-8000-000000000001";
const auditEventId = "b7000000-0000-4000-8000-000000000001";
const outboxEventId = "b8000000-0000-4000-8000-000000000001";
const terminalJobId = "b8000000-0000-4000-8000-000000000002";
const manualIntakeId = "b8000000-0000-4000-8000-000000000003";

const metadata = {
  accessToken: "header.payload.signature",
  correlationId: "b9000000-0000-4000-8000-000000000001",
  idempotencyKey: "vin-intake-command-001",
  requestId: "request-vin-intake-001",
  workspaceId,
} as const;

const body = {
  conditionKey: " USED.READY ",
  confirmation: {
    accepted: true,
    expectedRequestVersion: 2,
    vinDecodeResultId,
  },
  inventory: {
    acquisitionDate: "2026-07-16",
    advertisedPriceMinor: "2500000",
    currencyCode: " cad ",
    odometer: { unit: "km", value: 12_345 },
    publicNotes: " Confirmed inventory ",
  },
  locationId,
  stockDefinitionId,
  vehicleFacts: {
    bodyType: " Sedan ",
    cylinders: 4,
    drivetrain: " FWD ",
    engineLiters: "2.4",
    fuelType: " Gasoline ",
    horsepower: 160,
    make: " HONDA ",
    model: " Accord ",
    modelYear: 2003,
    transmission: " Automatic ",
    trimName: " EX ",
  },
  vinDecodeRequestId,
} as const;

function gatewayReturning(value: unknown): VinInventoryIntakeRpcGateway {
  return { invoke: vi.fn(async () => value) };
}

describe("VinInventoryIntakeApplicationService", () => {
  it("sends only normalized confirmed facts and command metadata to the canonical RPC", async () => {
    const gateway = gatewayReturning([
      {
        audit_event_id: auditEventId,
        inventory_unit_id: inventoryUnitId,
        linked_existing_open_unit: false,
        outbox_event_id: outboxEventId,
        replayed: false,
        stock_number: "S00042",
        vehicle_id: vehicleId,
        vin_decode_request_id: vinDecodeRequestId,
        vin_decode_request_version: 3,
        vin_inventory_intake_id: intakeId,
      },
    ]);

    await expect(
      new VinInventoryIntakeApplicationService(
        gateway,
      ).createFromConfirmedDecode({
        body,
        metadata,
      }),
    ).resolves.toEqual({
      auditEventId,
      inventoryUnitId,
      linkedExistingOpenUnit: false,
      outboxEventId,
      replayed: false,
      stockNumber: "S00042",
      vehicleId,
      vinDecodeRequestId,
      vinDecodeRequestVersion: 3,
      vinInventoryIntakeId: intakeId,
    });
    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: "create_inventory_unit_from_vin_decode",
      parameters: {
        p_acquisition_date: "2026-07-16",
        p_advertised_price_minor: "2500000",
        p_body_type: "Sedan",
        p_condition_key: "used.ready",
        p_correlation_id: metadata.correlationId,
        p_currency_code: "CAD",
        p_cylinders: 4,
        p_drivetrain: "FWD",
        p_engine_liters: "2.4",
        p_expected_request_version: 2,
        p_facts_confirmed: true,
        p_fuel_type: "Gasoline",
        p_horsepower: 160,
        p_idempotency_key: metadata.idempotencyKey,
        p_location_id: locationId,
        p_make: "HONDA",
        p_model: "Accord",
        p_model_year: 2003,
        p_odometer_unit: "km",
        p_odometer_value: 12_345,
        p_public_notes: "Confirmed inventory",
        p_request_id: metadata.requestId,
        p_stock_definition_id: stockDefinitionId,
        p_transmission: "Automatic",
        p_trim_name: "EX",
        p_vin_decode_request_id: vinDecodeRequestId,
        p_vin_decode_result_id: vinDecodeResultId,
        p_workspace_id: workspaceId,
      },
    });
  });

  it.each([
    {
      ...body,
      confirmation: { ...body.confirmation, accepted: false },
    },
    {
      ...body,
      confirmation: { ...body.confirmation, expectedRequestVersion: 0 },
    },
    { ...body, authorityWorkspaceId: workspaceId },
    {
      ...body,
      inventory: { ...body.inventory, currencyCode: "dollars" },
    },
    {
      ...body,
      vehicleFacts: { ...body.vehicleFacts, engineLiters: "2.4567" },
    },
  ])(
    "rejects unconfirmed, authority-bearing, or malformed bodies %#",
    async (invalidBody) => {
      const gateway = gatewayReturning([]);
      await expect(
        new VinInventoryIntakeApplicationService(
          gateway,
        ).createFromConfirmedDecode({
          body: invalidBody,
          metadata,
        }),
      ).rejects.toBeInstanceOf(VinInventoryIntakeValidationError);
      expect(gateway.invoke).not.toHaveBeenCalled();
    },
  );

  it("rejects an invalid decode request identifier before invoking the gateway", async () => {
    const gateway = gatewayReturning([]);
    await expect(
      new VinInventoryIntakeApplicationService(
        gateway,
      ).createFromConfirmedDecode({
        body: { ...body, vinDecodeRequestId: "not-a-uuid" },
        metadata,
      }),
    ).rejects.toMatchObject({ code: "invalid_request_body" });
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("fails closed when the database result is missing or malformed", async () => {
    const gateway = gatewayReturning([{ inventory_unit_id: inventoryUnitId }]);
    await expect(
      new VinInventoryIntakeApplicationService(
        gateway,
      ).createFromConfirmedDecode({
        body,
        metadata,
      }),
    ).rejects.toBeInstanceOf(VinInventoryIntakeRpcContractError);
  });

  it("fails closed when a confirmed intake echoes another decode request", async () => {
    const gateway = gatewayReturning([
      {
        audit_event_id: auditEventId,
        inventory_unit_id: inventoryUnitId,
        linked_existing_open_unit: false,
        outbox_event_id: outboxEventId,
        replayed: false,
        stock_number: "S00042",
        vehicle_id: vehicleId,
        vin_decode_request_id: "b1000000-0000-4000-8000-000000000099",
        vin_decode_request_version: 3,
        vin_inventory_intake_id: intakeId,
      },
    ]);
    await expect(
      new VinInventoryIntakeApplicationService(
        gateway,
      ).createFromConfirmedDecode({ body, metadata }),
    ).rejects.toBeInstanceOf(VinInventoryIntakeRpcContractError);
  });

  it("preserves exact minor-unit strings in a dead-letter manual intake", async () => {
    const gateway = gatewayReturning([
      {
        audit_event_id: auditEventId,
        inventory_unit_id: inventoryUnitId,
        linked_existing_open_unit: true,
        outbox_event_id: outboxEventId,
        replayed: false,
        stock_number: "S00043",
        terminal_job_id: terminalJobId,
        vehicle_id: vehicleId,
        vin_decode_request_id: vinDecodeRequestId,
        vin_decode_request_version: 4,
        vin_manual_inventory_intake_id: manualIntakeId,
      },
    ]);

    await expect(
      new VinInventoryIntakeApplicationService(
        gateway,
      ).createFromDeadLetterManualFacts({
        body: {
          conditionKey: "used.ready",
          confirmation: { accepted: true, expectedRequestVersion: 3 },
          duplicateDecision: null,
          inventory: {
            ...body.inventory,
            advertisedPriceMinor: "9223372036854775807",
          },
          locationId,
          manualReason: "Provider exhausted its durable attempt budget",
          stockDefinitionId,
          vehicleFacts: body.vehicleFacts,
        },
        metadata,
        vinDecodeRequestId,
      }),
    ).resolves.toMatchObject({
      linkedExistingOpenUnit: true,
      terminalJobId,
      vinManualInventoryIntakeId: manualIntakeId,
    });

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "create_inventory_unit_from_failed_vin_decode",
        parameters: expect.objectContaining({
          p_advertised_price_minor: "9223372036854775807",
          p_duplicate_decision: null,
          p_duplicate_reason: null,
          p_manual_reason: "Provider exhausted its durable attempt budget",
          p_vin_decode_request_id: vinDecodeRequestId,
        }),
      }),
    );
  });

  it("fails closed when a manual intake echoes another decode request", async () => {
    const gateway = gatewayReturning([
      {
        audit_event_id: auditEventId,
        inventory_unit_id: inventoryUnitId,
        linked_existing_open_unit: false,
        outbox_event_id: outboxEventId,
        replayed: false,
        stock_number: "S00043",
        terminal_job_id: terminalJobId,
        vehicle_id: vehicleId,
        vin_decode_request_id: "b1000000-0000-4000-8000-000000000099",
        vin_decode_request_version: 4,
        vin_manual_inventory_intake_id: manualIntakeId,
      },
    ]);

    await expect(
      new VinInventoryIntakeApplicationService(
        gateway,
      ).createFromDeadLetterManualFacts({
        body: {
          conditionKey: "used.ready",
          confirmation: { accepted: true, expectedRequestVersion: 3 },
          duplicateDecision: null,
          inventory: body.inventory,
          locationId,
          manualReason: "Provider terminal failure",
          stockDefinitionId,
          vehicleFacts: body.vehicleFacts,
        },
        metadata,
        vinDecodeRequestId,
      }),
    ).rejects.toBeInstanceOf(VinInventoryIntakeRpcContractError);
  });

  it.each(["9223372036854775808", "01", 2500000])(
    "rejects a noncanonical or overflowing exact-money value %#",
    async (advertisedPriceMinor) => {
      const gateway = gatewayReturning([]);
      await expect(
        new VinInventoryIntakeApplicationService(
          gateway,
        ).createFromConfirmedDecode({
          body: {
            ...body,
            inventory: { ...body.inventory, advertisedPriceMinor },
          },
          metadata,
        }),
      ).rejects.toBeInstanceOf(VinInventoryIntakeValidationError);
      expect(gateway.invoke).not.toHaveBeenCalled();
    },
  );
});
