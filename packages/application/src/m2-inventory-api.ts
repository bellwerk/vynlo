import { z } from "zod";

import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const expectedVersionSchema = z.number().int().min(1).max(2_147_483_647);
const transitionKeySchema = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_]*$/u);
const reasonSchema = z.string().trim().min(1).max(1_000);
const nullableTrimmedText = (maximumLength: number) =>
  z
    .string()
    .trim()
    .max(maximumLength)
    .transform((value) => (value === "" ? null : value))
    .nullable();
const nullableDateSchema = z.iso.date().nullable();
const nullableTimestampSchema = z.iso.datetime({ offset: true }).nullable();
const nullableMoneyMinorSchema = z
  .string()
  .trim()
  .regex(/^(?:0|[1-9]\d{0,18})$/u)
  .refine((value) => BigInt(value) <= 9_223_372_036_854_775_807n)
  .nullable();
const conditionKeySchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1)
  .max(100)
  .regex(/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/u)
  .nullable();
const bigintTextSchema = z
  .string()
  .regex(/^(?:0|[1-9]\d{0,18})$/u)
  .refine((value) => BigInt(value) <= 9_223_372_036_854_775_807n);
const nullableFactText = (maximumLength: number) =>
  z.string().trim().min(1).max(maximumLength).nullable();
const vehicleFactsSchema = z
  .object({
    bodyType: z.string().max(200).nullable(),
    cylinders: z.number().int().min(1).max(64).nullable(),
    drivetrain: z.string().max(100).nullable(),
    engineLiters: z
      .string()
      .regex(/^\d{1,2}(?:\.\d{1,3})?$/u)
      .nullable(),
    factsVersion: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
    fuelType: z.string().max(100).nullable(),
    horsepower: z.number().int().min(1).max(10_000).nullable(),
    make: z.string().max(100).nullable(),
    model: z.string().max(100).nullable(),
    modelYear: z.number().int().min(1886).max(2200).nullable(),
    transmission: z.string().max(200).nullable(),
    trimName: z.string().max(200).nullable(),
    vin: z.string().regex(/^[A-HJ-NPR-Z0-9]{17}$/u),
  })
  .strict();
const allowedTransitionSchema = z
  .object({
    canonicalStatus: z.enum([
      "draft",
      "active",
      "pending",
      "closed",
      "archived",
    ]),
    key: transitionKeySchema,
    labels: z.record(z.string(), z.string()),
    reasonRequired: z.boolean(),
    toStateKey: transitionKeySchema,
  })
  .strict();

const updateDetailsBodySchema = z
  .object({
    acquisitionDate: nullableDateSchema,
    acquiredAt: nullableTimestampSchema,
    advertisedPriceMinor: nullableMoneyMinorSchema,
    availableAt: nullableTimestampSchema,
    conditionKey: conditionKeySchema,
    expectedSalePrice: z
      .object({
        amountMinor: nullableMoneyMinorSchema.unwrap(),
        currencyCode: z
          .string()
          .trim()
          .toUpperCase()
          .regex(/^[A-Z]{3}$/u),
      })
      .strict()
      .nullable(),
    expectedVersion: expectedVersionSchema,
    internalNotes: nullableTrimmedText(8_000).optional(),
    odometer: z
      .object({
        unit: z.enum(["km", "mi"]),
        value: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
      })
      .strict()
      .nullable(),
    publicNotes: nullableTrimmedText(4_000),
  })
  .strict();

const transferBodySchema = z
  .object({
    expectedVersion: expectedVersionSchema,
    reason: reasonSchema,
    toLocationId: uuidSchema,
  })
  .strict();

const transitionBodySchema = z
  .object({
    expectedVersion: expectedVersionSchema,
    reason: reasonSchema.nullable(),
    transitionKey: transitionKeySchema,
  })
  .strict();

const overrideVehicleFactsBodySchema = z
  .object({
    expectedFactsVersion: z
      .number()
      .int()
      .positive()
      .max(Number.MAX_SAFE_INTEGER),
    facts: z
      .object({
        bodyType: nullableFactText(200),
        cylinders: z.number().int().min(1).max(64).nullable(),
        drivetrain: nullableFactText(100),
        engineLiters: z
          .string()
          .trim()
          .regex(/^\d{1,2}(?:\.\d{1,3})?$/u)
          .nullable(),
        fuelType: nullableFactText(100),
        horsepower: z.number().int().min(1).max(10_000).nullable(),
        make: nullableFactText(100),
        model: nullableFactText(100),
        modelYear: z.number().int().min(1886).max(2200).nullable(),
        transmission: nullableFactText(200),
        trimName: nullableFactText(200),
      })
      .strict(),
    reason: z.string().trim().min(1).max(2_000),
  })
  .strict();

const transferResultSchema = z
  .object({
    aggregate_version: expectedVersionSchema,
    audit_event_id: uuidSchema,
    canonical_status: z.enum([
      "draft",
      "active",
      "pending",
      "closed",
      "archived",
    ]),
    inventory_unit_id: uuidSchema,
    location_event_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    state_key: transitionKeySchema,
  })
  .strict();

const transitionResultSchema = z
  .object({
    aggregate_version: expectedVersionSchema,
    audit_event_id: uuidSchema,
    canonical_status: z.enum([
      "draft",
      "active",
      "pending",
      "closed",
      "archived",
    ]),
    inventory_unit_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    state_key: transitionKeySchema,
    workflow_event_id: uuidSchema,
  })
  .strict();

const updateDetailsResultSchema = z
  .object({
    aggregate_version: expectedVersionSchema,
    audit_event_id: uuidSchema,
    canonical_status: z.enum([
      "draft",
      "active",
      "pending",
      "closed",
      "archived",
    ]),
    inventory_unit_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    state_key: transitionKeySchema,
  })
  .strict();

const inventoryOperationsRowSchema = z
  .object({
    acquired_at: z.iso.datetime({ offset: true }).nullable(),
    acquisition_date: z.iso.date().nullable(),
    advertised_price_minor: bigintTextSchema.nullable(),
    aggregate_version: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
    allowed_transitions: z.array(allowedTransitionSchema).max(100),
    available_at: z.iso.datetime({ offset: true }).nullable(),
    can_create_costs: z.boolean(),
    can_override_facts: z.boolean(),
    can_read_costs: z.boolean(),
    can_read_internal: z.boolean(),
    can_reverse_costs: z.boolean(),
    can_transfer_location: z.boolean(),
    can_transition_workflow: z.boolean(),
    can_update_details: z.boolean(),
    can_update_internal: z.boolean(),
    canonical_status: z.enum([
      "draft",
      "active",
      "pending",
      "closed",
      "archived",
    ]),
    closed_at: z.iso.datetime({ offset: true }).nullable(),
    condition_key: conditionKeySchema,
    currency_code: z.string().regex(/^[A-Z]{3}$/u),
    estimated_gross_minor: z
      .string()
      .regex(/^-?(?:0|[1-9]\d{0,18})$/u)
      .nullable(),
    expected_sale_price_minor: bigintTextSchema.nullable(),
    has_recent_strong_authentication: z.boolean(),
    internal_notes: z.string().max(8_000).nullable(),
    inventory_unit_id: uuidSchema,
    location_id: uuidSchema.nullable(),
    location_name: z.string().max(200).nullable(),
    odometer_unit: z.enum(["km", "mi"]).nullable(),
    odometer_value: bigintTextSchema.nullable(),
    posted_cost_minor: bigintTextSchema.nullable(),
    public_notes: z.string().max(4_000).nullable(),
    sold_at: z.iso.datetime({ offset: true }).nullable(),
    stock_number: z.string().min(1).max(200),
    updated_at: z.iso.datetime({ offset: true }),
    vehicle_facts: vehicleFactsSchema,
    vehicle_id: uuidSchema,
    workflow_configuration_version: z.string().regex(/^\d+\.\d+\.\d+$/u),
    workflow_instance_version: z
      .number()
      .int()
      .positive()
      .max(Number.MAX_SAFE_INTEGER),
    workflow_state_key: transitionKeySchema,
  })
  .strict();

const locationRowSchema = z
  .object({
    locale: z.string().max(64).nullable(),
    location_id: uuidSchema,
    location_key: z.string().regex(/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/u),
    name: z.string().min(1).max(200),
    timezone: z.string().max(100).nullable(),
    version: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
  })
  .strict();

const overrideVehicleFactsResultSchema = z
  .object({
    audit_event_id: uuidSchema,
    facts_version: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
    history_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    vehicle_id: uuidSchema,
  })
  .strict();

export type M2InventoryValidationErrorCode =
  "invalid_request_body" | "invalid_inventory_unit_id" | "invalid_vehicle_id";

export class M2InventoryValidationError extends Error {
  readonly code: M2InventoryValidationErrorCode;

  constructor(code: M2InventoryValidationErrorCode) {
    super("The inventory command input is invalid.");
    this.name = "M2InventoryValidationError";
    this.code = code;
  }
}

export class M2InventoryRpcContractError extends Error {
  constructor() {
    super("The inventory data store returned an invalid response.");
    this.name = "M2InventoryRpcContractError";
  }
}

export interface M2InventoryEntityCommandInput extends VerticalSliceCommandInput {
  readonly inventoryUnitId: string;
}

export interface M2InventoryEntityQueryInput {
  readonly accessToken: string;
  readonly inventoryUnitId: string;
  readonly workspaceId: string;
}

export interface M2InventoryQueryInput {
  readonly accessToken: string;
  readonly workspaceId: string;
}

export interface M2VehicleEntityCommandInput extends VerticalSliceCommandInput {
  readonly vehicleId: string;
}

export interface UpdateInventoryDetailsResult {
  readonly aggregateVersion: number;
  readonly auditEventId: string;
  readonly canonicalStatus:
    "draft" | "active" | "pending" | "closed" | "archived";
  readonly inventoryUnitId: string;
  readonly outboxEventId: string;
  readonly replayed: boolean;
  readonly stateKey: string;
}

export interface TransferInventoryLocationResult {
  readonly aggregateVersion: number;
  readonly auditEventId: string;
  readonly canonicalStatus:
    "draft" | "active" | "pending" | "closed" | "archived";
  readonly inventoryUnitId: string;
  readonly locationEventId: string;
  readonly locationId: string;
  readonly outboxEventId: string;
  readonly replayed: boolean;
  readonly stateKey: string;
}

export interface TransitionInventoryWorkflowResult {
  readonly aggregateVersion: number;
  readonly auditEventId: string;
  readonly canonicalStatus:
    "draft" | "active" | "pending" | "closed" | "archived";
  readonly inventoryUnitId: string;
  readonly outboxEventId: string;
  readonly replayed: boolean;
  readonly stateKey: string;
  readonly workflowEventId: string;
}

function parseInventoryUnitId(value: string): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new M2InventoryValidationError("invalid_inventory_unit_id");
  }
  return parsed.data;
}

function parseVehicleId(value: string): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new M2InventoryValidationError("invalid_vehicle_id");
  }
  return parsed.data;
}

function parseWorkspaceId(value: string): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new M2InventoryValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseBody<T>(schema: z.ZodType<T>, body: unknown): T {
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    throw new M2InventoryValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseRpcRow<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = z.array(schema).length(1).safeParse(value);
  if (!parsed.success) {
    throw new M2InventoryRpcContractError();
  }
  return parsed.data[0]!;
}

function assertRpcEntityId(actual: string, expected: string): void {
  if (actual !== expected) {
    throw new M2InventoryRpcContractError();
  }
}

export class M2InventoryApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async getOperations(input: M2InventoryEntityQueryInput) {
    const inventoryUnitId = parseInventoryUnitId(input.inventoryUnitId);
    const workspaceId = parseWorkspaceId(input.workspaceId);
    const row = parseRpcRow(
      inventoryOperationsRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "get_inventory_unit_operations",
        parameters: {
          p_inventory_unit_id: inventoryUnitId,
          p_workspace_id: workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.inventory_unit_id, inventoryUnitId);

    return {
      acquisitionDate: row.acquisition_date,
      acquiredAt: row.acquired_at,
      advertisedPriceMinor: row.advertised_price_minor,
      aggregateVersion: row.aggregate_version,
      allowedTransitions: row.allowed_transitions,
      availableAt: row.available_at,
      capabilities: {
        canCreateCosts: row.can_create_costs,
        canOverrideFacts: row.can_override_facts,
        canReadCosts: row.can_read_costs,
        canReadInternal: row.can_read_internal,
        canReverseCosts: row.can_reverse_costs,
        canTransferLocation: row.can_transfer_location,
        canTransitionWorkflow: row.can_transition_workflow,
        canUpdateDetails: row.can_update_details,
        canUpdateInternal: row.can_update_internal,
        hasRecentStrongAuthentication: row.has_recent_strong_authentication,
      },
      canonicalStatus: row.canonical_status,
      closedAt: row.closed_at,
      conditionKey: row.condition_key,
      currencyCode: row.currency_code,
      estimatedGrossMinor: row.estimated_gross_minor,
      expectedSalePriceMinor: row.expected_sale_price_minor,
      internalNotes: row.internal_notes,
      inventoryUnitId: row.inventory_unit_id,
      location:
        row.location_id === null
          ? null
          : { id: row.location_id, name: row.location_name! },
      odometer:
        row.odometer_value === null || row.odometer_unit === null
          ? null
          : { unit: row.odometer_unit, value: row.odometer_value },
      postedCostMinor: row.posted_cost_minor,
      publicNotes: row.public_notes,
      soldAt: row.sold_at,
      stockNumber: row.stock_number,
      updatedAt: row.updated_at,
      vehicleFacts: row.vehicle_facts,
      vehicleId: row.vehicle_id,
      workflowConfigurationVersion: row.workflow_configuration_version,
      workflowInstanceVersion: row.workflow_instance_version,
      workflowStateKey: row.workflow_state_key,
    };
  }

  async listActiveLocations(input: M2InventoryQueryInput) {
    const workspaceId = parseWorkspaceId(input.workspaceId);
    const value = await this.#gateway.invoke({
      accessToken: input.accessToken,
      functionName: "list_active_inventory_locations",
      parameters: { p_workspace_id: workspaceId },
    });
    const rows = z.array(locationRowSchema).max(200).safeParse(value);
    if (!rows.success) {
      throw new M2InventoryRpcContractError();
    }
    return {
      items: rows.data.map((row) => ({
        id: row.location_id,
        key: row.location_key,
        locale: row.locale,
        name: row.name,
        timezone: row.timezone,
        version: row.version,
      })),
    };
  }

  async overrideVehicleFacts(input: M2VehicleEntityCommandInput) {
    const vehicleId = parseVehicleId(input.vehicleId);
    const body = parseBody(overrideVehicleFactsBodySchema, input.body);
    const row = parseRpcRow(
      overrideVehicleFactsResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "override_vehicle_facts",
        parameters: {
          p_body_type: body.facts.bodyType,
          p_correlation_id: input.metadata.correlationId,
          p_cylinders: body.facts.cylinders,
          p_drivetrain: body.facts.drivetrain,
          p_engine_liters: body.facts.engineLiters,
          p_expected_facts_version: body.expectedFactsVersion,
          p_fuel_type: body.facts.fuelType,
          p_horsepower: body.facts.horsepower,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_make: body.facts.make,
          p_model: body.facts.model,
          p_model_year: body.facts.modelYear,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_transmission: body.facts.transmission,
          p_trim_name: body.facts.trimName,
          p_vehicle_id: vehicleId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.vehicle_id, vehicleId);
    return {
      auditEventId: row.audit_event_id,
      factsVersion: row.facts_version,
      historyId: row.history_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      vehicleId: row.vehicle_id,
    };
  }

  async updateDetails(
    input: M2InventoryEntityCommandInput,
  ): Promise<UpdateInventoryDetailsResult> {
    const inventoryUnitId = parseInventoryUnitId(input.inventoryUnitId);
    const body = parseBody(updateDetailsBodySchema, input.body);
    const updateInternalNotes = body.internalNotes !== undefined;
    const row = parseRpcRow(
      updateDetailsResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "update_inventory_unit_details",
        parameters: {
          p_acquired_at: body.acquiredAt,
          p_acquisition_date: body.acquisitionDate,
          p_advertised_price_minor: body.advertisedPriceMinor,
          p_available_at: body.availableAt,
          p_condition_key: body.conditionKey,
          p_correlation_id: input.metadata.correlationId,
          p_expected_sale_price_currency_code:
            body.expectedSalePrice?.currencyCode ?? null,
          p_expected_sale_price_minor:
            body.expectedSalePrice?.amountMinor ?? null,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_internal_notes: body.internalNotes ?? null,
          p_inventory_unit_id: inventoryUnitId,
          p_odometer_unit: body.odometer?.unit ?? null,
          p_odometer_value: body.odometer?.value ?? null,
          p_public_notes: body.publicNotes,
          p_request_id: input.metadata.requestId,
          p_update_internal_notes: updateInternalNotes,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.inventory_unit_id, inventoryUnitId);

    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      canonicalStatus: row.canonical_status,
      inventoryUnitId: row.inventory_unit_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      stateKey: row.state_key,
    };
  }

  async transferLocation(
    input: M2InventoryEntityCommandInput,
  ): Promise<TransferInventoryLocationResult> {
    const inventoryUnitId = parseInventoryUnitId(input.inventoryUnitId);
    const body = parseBody(transferBodySchema, input.body);
    const row = parseRpcRow(
      transferResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "transfer_inventory_unit_location",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_inventory_unit_id: inventoryUnitId,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_to_location_id: body.toLocationId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.inventory_unit_id, inventoryUnitId);

    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      canonicalStatus: row.canonical_status,
      inventoryUnitId: row.inventory_unit_id,
      locationEventId: row.location_event_id,
      locationId: body.toLocationId,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      stateKey: row.state_key,
    };
  }

  async transitionWorkflow(
    input: M2InventoryEntityCommandInput,
  ): Promise<TransitionInventoryWorkflowResult> {
    const inventoryUnitId = parseInventoryUnitId(input.inventoryUnitId);
    const body = parseBody(transitionBodySchema, input.body);
    const row = parseRpcRow(
      transitionResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "transition_inventory_workflow",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_inventory_unit_id: inventoryUnitId,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_transition_key: body.transitionKey,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.inventory_unit_id, inventoryUnitId);

    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      canonicalStatus: row.canonical_status,
      inventoryUnitId: row.inventory_unit_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      stateKey: row.state_key,
      workflowEventId: row.workflow_event_id,
    };
  }
}
