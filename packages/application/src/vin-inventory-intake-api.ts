import { z } from "zod";

import type {
  VerticalSliceCommandInput,
  VerticalSliceCommandMetadata,
} from "./vertical-slice-api";

const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const expectedVersionSchema = z
  .number()
  .int()
  .min(1)
  .max(Number.MAX_SAFE_INTEGER);
const moneyMinorSchema = z
  .string()
  .trim()
  .regex(/^(?:0|[1-9]\d{0,18})$/u)
  .refine((value) => BigInt(value) <= 9_223_372_036_854_775_807n);
const conditionKeySchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1)
  .max(100)
  .regex(/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/u);
const nullableText = (maximum: number) =>
  z.union([z.string().trim().min(1).max(maximum), z.null()]);
const vehicleFactsSchema = z
  .object({
    bodyType: nullableText(200),
    cylinders: z.number().int().min(1).max(64).nullable(),
    drivetrain: nullableText(100),
    engineLiters: z
      .string()
      .trim()
      .regex(/^\d{1,2}(?:\.\d{1,3})?$/u)
      .nullable(),
    fuelType: nullableText(100),
    horsepower: z.number().int().min(1).max(10_000).nullable(),
    make: nullableText(100),
    model: nullableText(100),
    modelYear: z.number().int().min(1886).max(2200).nullable(),
    transmission: nullableText(200),
    trimName: nullableText(200),
  })
  .strict();
const inventoryDetailsSchema = z
  .object({
    acquisitionDate: z.iso.date().nullable(),
    advertisedPriceMinor: moneyMinorSchema.nullable(),
    currencyCode: z
      .string()
      .trim()
      .toUpperCase()
      .regex(/^[A-Z]{3}$/u),
    odometer: z
      .object({
        unit: z.enum(["km", "mi"]),
        value: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
      })
      .strict()
      .nullable(),
    publicNotes: nullableText(4_000),
  })
  .strict();
const createFromVinBodySchema = z
  .object({
    conditionKey: conditionKeySchema,
    confirmation: z
      .object({
        accepted: z.literal(true),
        expectedRequestVersion: expectedVersionSchema,
        vinDecodeResultId: uuidSchema,
      })
      .strict(),
    inventory: inventoryDetailsSchema,
    locationId: uuidSchema,
    stockDefinitionId: uuidSchema,
    vehicleFacts: vehicleFactsSchema,
    vinDecodeRequestId: uuidSchema,
  })
  .strict();
const duplicateDecisionSchema = z
  .object({
    decision: z.enum([
      "reuse_existing_vehicle",
      "reacquire_existing_vehicle",
      "override_open_duplicate",
    ]),
    reason: z.string().trim().min(1).max(2_000),
  })
  .strict();
const manualIntakeBodySchema = z
  .object({
    conditionKey: conditionKeySchema,
    confirmation: z
      .object({
        accepted: z.literal(true),
        expectedRequestVersion: expectedVersionSchema,
      })
      .strict(),
    duplicateDecision: duplicateDecisionSchema.nullable(),
    inventory: inventoryDetailsSchema,
    locationId: uuidSchema,
    manualReason: z.string().trim().min(1).max(2_000),
    stockDefinitionId: uuidSchema,
    vehicleFacts: vehicleFactsSchema.refine(
      (facts) =>
        facts.modelYear !== null && facts.make !== null && facts.model !== null,
      { message: "Manual intake requires model year, make, and model." },
    ),
  })
  .strict();
const intakeResultRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    inventory_unit_id: uuidSchema,
    linked_existing_open_unit: z.boolean(),
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    stock_number: z.string().min(1).max(200),
    vehicle_id: uuidSchema,
    vin_decode_request_id: uuidSchema,
    vin_decode_request_version: expectedVersionSchema,
    vin_inventory_intake_id: uuidSchema,
  })
  .strict();
const manualIntakeResultRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    inventory_unit_id: uuidSchema,
    linked_existing_open_unit: z.boolean(),
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    stock_number: z.string().min(1).max(200),
    terminal_job_id: uuidSchema,
    vehicle_id: uuidSchema,
    vin_decode_request_id: uuidSchema,
    vin_decode_request_version: expectedVersionSchema,
    vin_manual_inventory_intake_id: uuidSchema,
  })
  .strict();

export interface VinInventoryIntakeRpcGateway {
  invoke(request: {
    readonly accessToken: string;
    readonly functionName:
      | "create_inventory_unit_from_failed_vin_decode"
      | "create_inventory_unit_from_vin_decode";
    readonly parameters: Readonly<Record<string, unknown>>;
  }): Promise<unknown>;
}

export type VinInventoryIntakeValidationErrorCode = "invalid_request_body";

export class VinInventoryIntakeValidationError extends Error {
  readonly code: VinInventoryIntakeValidationErrorCode;

  constructor(code: VinInventoryIntakeValidationErrorCode) {
    super("The VIN inventory intake request is invalid.");
    this.name = "VinInventoryIntakeValidationError";
    this.code = code;
  }
}

export class VinInventoryIntakeRpcContractError extends Error {
  constructor() {
    super("The VIN inventory data store returned an invalid response.");
    this.name = "VinInventoryIntakeRpcContractError";
  }
}

export interface VinInventoryIntakeResult {
  readonly auditEventId: string;
  readonly inventoryUnitId: string;
  readonly linkedExistingOpenUnit: boolean;
  readonly outboxEventId: string;
  readonly replayed: boolean;
  readonly stockNumber: string;
  readonly vehicleId: string;
  readonly vinDecodeRequestId: string;
  readonly vinDecodeRequestVersion: number;
  readonly vinInventoryIntakeId: string;
}

export interface VinManualInventoryIntakeResult {
  readonly auditEventId: string;
  readonly inventoryUnitId: string;
  readonly linkedExistingOpenUnit: boolean;
  readonly outboxEventId: string;
  readonly replayed: boolean;
  readonly stockNumber: string;
  readonly terminalJobId: string;
  readonly vehicleId: string;
  readonly vinDecodeRequestId: string;
  readonly vinDecodeRequestVersion: number;
  readonly vinManualInventoryIntakeId: string;
}

function parseBody(body: unknown): z.infer<typeof createFromVinBodySchema> {
  const parsed = createFromVinBodySchema.safeParse(body);
  if (!parsed.success) {
    throw new VinInventoryIntakeValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseResult(value: unknown): z.infer<typeof intakeResultRowSchema> {
  const parsed = z.array(intakeResultRowSchema).length(1).safeParse(value);
  if (!parsed.success) {
    throw new VinInventoryIntakeRpcContractError();
  }
  return parsed.data[0]!;
}

function parseManualResult(
  value: unknown,
): z.infer<typeof manualIntakeResultRowSchema> {
  const parsed = z
    .array(manualIntakeResultRowSchema)
    .length(1)
    .safeParse(value);
  if (!parsed.success) {
    throw new VinInventoryIntakeRpcContractError();
  }
  return parsed.data[0]!;
}

function assertEchoedRequestId(
  expectedRequestId: string,
  actualRequestId: string,
): void {
  if (actualRequestId !== expectedRequestId) {
    throw new VinInventoryIntakeRpcContractError();
  }
}

function commandParameters(
  metadata: VerticalSliceCommandMetadata,
): Readonly<Record<string, unknown>> {
  return {
    p_correlation_id: metadata.correlationId,
    p_idempotency_key: metadata.idempotencyKey,
    p_request_id: metadata.requestId,
    p_workspace_id: metadata.workspaceId,
  };
}

export class VinInventoryIntakeApplicationService {
  readonly #gateway: VinInventoryIntakeRpcGateway;

  constructor(gateway: VinInventoryIntakeRpcGateway) {
    this.#gateway = gateway;
  }

  async createFromConfirmedDecode(
    input: VerticalSliceCommandInput,
  ): Promise<VinInventoryIntakeResult> {
    const body = parseBody(input.body);
    const row = parseResult(
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_inventory_unit_from_vin_decode",
        parameters: {
          ...commandParameters(input.metadata),
          p_acquisition_date: body.inventory.acquisitionDate,
          p_advertised_price_minor: body.inventory.advertisedPriceMinor,
          p_body_type: body.vehicleFacts.bodyType,
          p_condition_key: body.conditionKey,
          p_currency_code: body.inventory.currencyCode,
          p_cylinders: body.vehicleFacts.cylinders,
          p_drivetrain: body.vehicleFacts.drivetrain,
          p_engine_liters: body.vehicleFacts.engineLiters,
          p_expected_request_version: body.confirmation.expectedRequestVersion,
          p_facts_confirmed: body.confirmation.accepted,
          p_fuel_type: body.vehicleFacts.fuelType,
          p_horsepower: body.vehicleFacts.horsepower,
          p_location_id: body.locationId,
          p_make: body.vehicleFacts.make,
          p_model: body.vehicleFacts.model,
          p_model_year: body.vehicleFacts.modelYear,
          p_odometer_unit: body.inventory.odometer?.unit ?? null,
          p_odometer_value: body.inventory.odometer?.value ?? null,
          p_public_notes: body.inventory.publicNotes,
          p_stock_definition_id: body.stockDefinitionId,
          p_transmission: body.vehicleFacts.transmission,
          p_trim_name: body.vehicleFacts.trimName,
          p_vin_decode_request_id: body.vinDecodeRequestId,
          p_vin_decode_result_id: body.confirmation.vinDecodeResultId,
        },
      }),
    );
    assertEchoedRequestId(body.vinDecodeRequestId, row.vin_decode_request_id);

    return {
      auditEventId: row.audit_event_id,
      inventoryUnitId: row.inventory_unit_id,
      linkedExistingOpenUnit: row.linked_existing_open_unit,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      stockNumber: row.stock_number,
      vehicleId: row.vehicle_id,
      vinDecodeRequestId: row.vin_decode_request_id,
      vinDecodeRequestVersion: row.vin_decode_request_version,
      vinInventoryIntakeId: row.vin_inventory_intake_id,
    };
  }

  async createFromDeadLetterManualFacts(
    input: VerticalSliceCommandInput & {
      readonly vinDecodeRequestId: string;
    },
  ): Promise<VinManualInventoryIntakeResult> {
    const requestId = uuidSchema.safeParse(input.vinDecodeRequestId);
    const parsedBody = manualIntakeBodySchema.safeParse(input.body);
    if (!requestId.success || !parsedBody.success) {
      throw new VinInventoryIntakeValidationError("invalid_request_body");
    }
    const body = parsedBody.data;
    const row = parseManualResult(
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_inventory_unit_from_failed_vin_decode",
        parameters: {
          ...commandParameters(input.metadata),
          p_acquisition_date: body.inventory.acquisitionDate,
          p_advertised_price_minor: body.inventory.advertisedPriceMinor,
          p_body_type: body.vehicleFacts.bodyType,
          p_condition_key: body.conditionKey,
          p_currency_code: body.inventory.currencyCode,
          p_cylinders: body.vehicleFacts.cylinders,
          p_drivetrain: body.vehicleFacts.drivetrain,
          p_duplicate_decision: body.duplicateDecision?.decision ?? null,
          p_duplicate_reason: body.duplicateDecision?.reason ?? null,
          p_engine_liters: body.vehicleFacts.engineLiters,
          p_expected_request_version: body.confirmation.expectedRequestVersion,
          p_facts_confirmed: body.confirmation.accepted,
          p_fuel_type: body.vehicleFacts.fuelType,
          p_horsepower: body.vehicleFacts.horsepower,
          p_location_id: body.locationId,
          p_make: body.vehicleFacts.make,
          p_manual_reason: body.manualReason,
          p_model: body.vehicleFacts.model,
          p_model_year: body.vehicleFacts.modelYear,
          p_odometer_unit: body.inventory.odometer?.unit ?? null,
          p_odometer_value: body.inventory.odometer?.value ?? null,
          p_public_notes: body.inventory.publicNotes,
          p_stock_definition_id: body.stockDefinitionId,
          p_transmission: body.vehicleFacts.transmission,
          p_trim_name: body.vehicleFacts.trimName,
          p_vin_decode_request_id: requestId.data,
        },
      }),
    );
    assertEchoedRequestId(requestId.data, row.vin_decode_request_id);

    return {
      auditEventId: row.audit_event_id,
      inventoryUnitId: row.inventory_unit_id,
      linkedExistingOpenUnit: row.linked_existing_open_unit,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      stockNumber: row.stock_number,
      terminalJobId: row.terminal_job_id,
      vehicleId: row.vehicle_id,
      vinDecodeRequestId: row.vin_decode_request_id,
      vinDecodeRequestVersion: row.vin_decode_request_version,
      vinManualInventoryIntakeId: row.vin_manual_inventory_intake_id,
    };
  }
}
