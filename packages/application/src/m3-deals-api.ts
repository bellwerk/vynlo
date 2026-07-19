import {
  M3DealDomainError,
  normalizeDealLineItemCommand,
  normalizeTradeInCommand,
  normalizeTradeInDetails,
} from "@vynlo/deals";
import { z } from "zod";

import {
  M3ApplicationValidationError,
  m3CommandEvidenceSchema,
  m3CurrencyCodeSchema,
  m3ExpectedVersionSchema,
  m3KeySchema,
  m3MinorUnitSchema,
  m3MoneySchema,
  m3NullableTimestampSchema,
  m3ReasonSchema,
  m3TimestampSchema,
  m3UuidSchema,
  parseM3Body,
  parseM3EntityId,
  parseM3RpcRow,
  parseM3RpcRows,
  type M3EntityCommandInput,
} from "./m3-api-common";
import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const nullableText = (maximum: number) =>
  z.string().trim().max(maximum).nullable();
const nullableUuid = m3UuidSchema.nullable();
const nonNegativeInteger = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const lineItemTypeSchema = z.enum([
  "vehicle",
  "fee",
  "discount",
  "accessory",
  "service",
  "other",
]);
const canonicalStatusSchema = z.enum([
  "draft",
  "active",
  "pending",
  "closed",
  "archived",
]);
const lifecycleStatusSchema = z.enum(["active", "completed"]);
const quantitySchema = z
  .string()
  .regex(/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/u)
  .refine((value) => Number(value) > 0);

const forbiddenMetadataKeys = new Set([
  "command",
  "eval",
  "fetch",
  "filesystem",
  "function",
  "http",
  "import",
  "javascript",
  "module",
  "network",
  "script",
  "shell",
  "sql",
  "url",
]);

function isSafeMetadata(value: unknown, depth = 0): boolean {
  if (depth > 16) return false;
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean" ||
    (typeof value === "number" && Number.isFinite(value))
  ) {
    return true;
  }
  if (Array.isArray(value)) {
    return (
      value.length <= 200 &&
      value.every((entry) => isSafeMetadata(entry, depth + 1))
    );
  }
  if (typeof value !== "object") return false;
  const prototype = Object.getPrototypeOf(value) as unknown;
  if (prototype !== Object.prototype && prototype !== null) return false;
  return Object.entries(value).every(([key, entry]) => {
    const normalizedKey = key.toLowerCase().replaceAll(/[^a-z0-9]/gu, "");
    return (
      key.length <= 128 &&
      !forbiddenMetadataKeys.has(normalizedKey) &&
      isSafeMetadata(entry, depth + 1)
    );
  });
}

const safeMetadataSchema = z
  .record(z.string().min(1).max(128), z.unknown())
  .refine(isSafeMetadata)
  .refine((value) => JSON.stringify(value).length <= 16_384);

const boundedConfigurationObjectSchema = z
  .record(z.string().min(1).max(128), z.unknown())
  .refine((value) => JSON.stringify(value).length <= 65_536);

const dealCreateBodySchema = z
  .object({
    currencyCode: m3CurrencyCodeSchema,
    dealTypeKey: m3KeySchema,
    legalEntityId: m3UuidSchema,
    locationId: m3UuidSchema,
    notes: nullableText(4_000),
    originatingLeadId: nullableUuid,
    ownerMembershipId: nullableUuid,
  })
  .strict();

const dealUpdateBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    legalEntityId: m3UuidSchema.optional(),
    locationId: m3UuidSchema.optional(),
    notes: nullableText(4_000).optional(),
    ownerMembershipId: m3UuidSchema.optional(),
  })
  .strict()
  .refine(
    (body) =>
      body.legalEntityId !== undefined ||
      body.locationId !== undefined ||
      body.notes !== undefined ||
      body.ownerMembershipId !== undefined,
    { message: "At least one deal field must be updated." },
  );

const dealTransitionBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    reason: m3ReasonSchema.nullable(),
    transitionKey: m3KeySchema,
  })
  .strict();

const participantBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    isPrimary: z.boolean(),
    partyId: m3UuidSchema,
    roleKey: m3KeySchema,
  })
  .strict();

const releaseBodySchema = z
  .object({ expectedVersion: m3ExpectedVersionSchema })
  .strict();

const inventoryBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    inventoryUnitId: m3UuidSchema,
    metadata: safeMetadataSchema,
    money: m3MoneySchema.nullable(),
    roleKey: m3KeySchema,
  })
  .strict();

const tradeInDetailsSchema = z
  .object({
    allowance: m3MoneySchema,
    conditionKey: m3KeySchema.nullable(),
    enteredVehicleFacts: safeMetadataSchema.nullable(),
    lenderPartyId: nullableUuid,
    lienAmount: m3MoneySchema,
    odometerUnit: z.enum(["km", "mi"]).nullable(),
    odometerValue: nonNegativeInteger.nullable(),
    ownerPartyId: m3UuidSchema,
    payoffAmount: m3MoneySchema,
    taxEligibilityInputs: safeMetadataSchema,
    vehicleId: nullableUuid,
  })
  .strict()
  .refine(
    (body) => body.vehicleId !== null || body.enteredVehicleFacts !== null,
    { message: "A trade-in vehicle reference or entered facts are required." },
  )
  .refine(
    (body) => (body.odometerValue === null) === (body.odometerUnit === null),
    { message: "Trade-in odometer value and unit must be supplied together." },
  );

const tradeInCreateBodySchema = tradeInDetailsSchema
  .extend({ expectedVersion: m3ExpectedVersionSchema })
  .strict();

const tradeInUpdateBodySchema = tradeInDetailsSchema
  .extend({
    expectedTradeInVersion: m3ExpectedVersionSchema,
    expectedVersion: m3ExpectedVersionSchema,
  })
  .strict();

const tradeInInventoryBodySchema = z
  .object({
    expectedTradeInVersion: m3ExpectedVersionSchema,
    expectedVersion: m3ExpectedVersionSchema,
    inventoryUnitId: m3UuidSchema,
  })
  .strict();

const lineItemBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    itemType: lineItemTypeSchema,
    key: m3KeySchema,
    label: z.string().trim().min(1).max(200),
    paymentTimingKey: m3KeySchema.nullable(),
    quantity: quantitySchema,
    sortOrder: nonNegativeInteger,
    sourceKey: m3KeySchema.nullable(),
    sourceReference: nullableText(500),
    taxClassificationKey: m3KeySchema.nullable(),
    unitAmount: m3MoneySchema,
  })
  .strict();

const lineItemUpdateBodySchema = lineItemBodySchema
  .omit({ key: true })
  .extend({ expectedLineItemVersion: m3ExpectedVersionSchema })
  .strict();

const lineItemUpdateByIdBodySchema = lineItemUpdateBodySchema
  .extend({ dealId: m3UuidSchema })
  .strict();

const dealResultSchema = m3CommandEvidenceSchema
  .extend({
    canonical_status: canonicalStatusSchema,
    deal_id: m3UuidSchema,
    state_key: m3KeySchema,
  })
  .strict();

const dealTransitionResultSchema = dealResultSchema
  .extend({ workflow_event_id: m3UuidSchema })
  .strict();

const participantResultSchema = dealResultSchema
  .extend({ participant_id: m3UuidSchema })
  .strict();

const inventoryResultSchema = dealResultSchema
  .extend({ inventory_link_id: m3UuidSchema })
  .strict();

const tradeInResultSchema = dealResultSchema
  .extend({
    trade_in_id: m3UuidSchema,
    trade_in_version: m3ExpectedVersionSchema,
  })
  .strict();

const lineItemResultSchema = dealResultSchema
  .extend({ line_item_id: m3UuidSchema })
  .strict();

const lineItemUpdateResultSchema = lineItemResultSchema
  .extend({ line_item_version: m3ExpectedVersionSchema })
  .strict();

const translatedLabelsSchema = z
  .object({
    en: z.string().trim().min(1).max(200),
    fr: z.string().trim().min(1).max(200),
  })
  .strict();

const localizedDealOptionSchema = z
  .object({
    key: m3KeySchema,
    labels: translatedLabelsSchema,
  })
  .strict();

const dealListRowSchema = z
  .object({
    active_inventory_count: nonNegativeInteger,
    active_line_item_count: nonNegativeInteger,
    active_participant_count: nonNegativeInteger,
    aggregate_version: m3ExpectedVersionSchema,
    canonical_status: canonicalStatusSchema,
    currency_code: m3CurrencyCodeSchema,
    deal_id: m3UuidSchema,
    deal_type_key: m3KeySchema,
    deal_type_labels: translatedLabelsSchema,
    deal_type_version_id: m3UuidSchema,
    legal_entity_id: m3UuidSchema,
    lifecycle_status: lifecycleStatusSchema,
    location_id: m3UuidSchema,
    notes: nullableText(4_000),
    originating_lead_id: nullableUuid,
    owner_membership_id: m3UuidSchema,
    state_key: m3KeySchema,
    updated_at: m3TimestampSchema,
  })
  .strict();

const dealDetailRowSchema = z
  .object({
    aggregate_version: m3ExpectedVersionSchema,
    available_transitions: z
      .array(
        z
          .object({
            labels: translatedLabelsSchema,
            reasonRequired: z.boolean(),
            toStateKey: m3KeySchema,
            transitionKey: m3KeySchema,
          })
          .strict(),
      )
      .max(100),
    cancelled_at: m3NullableTimestampSchema,
    canonical_status: canonicalStatusSchema,
    closed_reason: nullableText(2_000),
    completed_at: m3NullableTimestampSchema,
    created_at: m3TimestampSchema,
    currency_code: m3CurrencyCodeSchema,
    deal_id: m3UuidSchema,
    deal_type_behavior_flags: boundedConfigurationObjectSchema,
    deal_type_checksum: z.string().regex(/^[a-f0-9]{64}$/u),
    deal_type_definition_id: m3UuidSchema,
    deal_type_field_schema: boundedConfigurationObjectSchema,
    deal_type_key: m3KeySchema,
    deal_type_labels: translatedLabelsSchema,
    deal_type_revision: m3ExpectedVersionSchema,
    deal_type_source: z.enum([
      "configuration",
      "starter_pack",
      "migration_compatibility",
    ]),
    deal_type_version: z.string().regex(/^[0-9]+\.[0-9]+\.[0-9]+$/u),
    deal_type_version_id: m3UuidSchema,
    effective_at: m3NullableTimestampSchema,
    inventory_role_options: z.array(localizedDealOptionSchema).max(64),
    legal_entity_id: m3UuidSchema,
    lifecycle_status: lifecycleStatusSchema,
    location_id: m3UuidSchema,
    notes: nullableText(4_000),
    one_time_event_type_options: z.array(localizedDealOptionSchema).max(32),
    originating_lead_id: nullableUuid,
    owner_membership_id: m3UuidSchema,
    participant_role_options: z.array(localizedDealOptionSchema).max(64),
    state_key: m3KeySchema,
    updated_at: m3TimestampSchema,
    workflow_instance_id: m3UuidSchema,
    workflow_version_id: m3UuidSchema,
  })
  .strict();

const dealParticipantRowSchema = z
  .object({
    created_at: m3TimestampSchema,
    created_by: m3UuidSchema,
    is_primary: z.boolean(),
    participant_id: m3UuidSchema,
    party_display_name: z.string().trim().min(1).max(200),
    party_id: m3UuidSchema,
    released_at: m3NullableTimestampSchema,
    released_by: nullableUuid,
    role_key: m3KeySchema,
    status: z.enum(["active", "released"]),
    version: m3ExpectedVersionSchema,
  })
  .strict();

const dealInventoryRowSchema = z
  .object({
    amount_minor: m3MinorUnitSchema.nullable(),
    created_at: m3TimestampSchema,
    created_by: m3UuidSchema,
    currency_code: m3CurrencyCodeSchema,
    inventory_link_id: m3UuidSchema,
    inventory_status: z.string().trim().min(1).max(64),
    inventory_unit_id: m3UuidSchema,
    metadata: safeMetadataSchema,
    released_at: m3NullableTimestampSchema,
    released_by: nullableUuid,
    role_key: m3KeySchema,
    status: z.enum(["active", "released"]),
    stock_number: z.string().trim().min(1).max(200),
    version: m3ExpectedVersionSchema,
  })
  .strict();

const dealLineItemRowSchema = z
  .object({
    created_at: m3TimestampSchema,
    created_by: m3UuidSchema,
    currency_code: m3CurrencyCodeSchema,
    item_type: lineItemTypeSchema,
    key: m3KeySchema,
    label: z.string().trim().min(1).max(200),
    line_item_id: m3UuidSchema,
    payment_timing_key: m3KeySchema.nullable(),
    quantity: quantitySchema,
    released_at: m3NullableTimestampSchema,
    released_by: nullableUuid,
    sort_order: nonNegativeInteger,
    source_key: m3KeySchema.nullable(),
    source_reference: nullableText(500),
    status: z.enum(["active", "released"]),
    tax_classification_key: m3KeySchema.nullable(),
    unit_amount_minor: m3MinorUnitSchema,
    updated_at: m3TimestampSchema,
    updated_by: m3UuidSchema,
    version: m3ExpectedVersionSchema,
  })
  .strict();

const tradeInListRowSchema = z
  .object({
    allowance_minor: m3MinorUnitSchema,
    condition_key: m3KeySchema.nullable(),
    created_at: m3TimestampSchema,
    currency_code: m3CurrencyCodeSchema,
    deal_id: m3UuidSchema,
    entered_vehicle_facts: safeMetadataSchema.nullable(),
    lender_party_id: nullableUuid,
    lien_amount_minor: m3MinorUnitSchema,
    odometer_unit: z.enum(["km", "mi"]).nullable(),
    odometer_value: nonNegativeInteger.nullable(),
    owner_party_id: m3UuidSchema,
    payoff_amount_minor: m3MinorUnitSchema,
    resulting_inventory_unit_id: nullableUuid,
    status: z.enum(["active", "confirmed", "cancelled"]),
    tax_eligibility_inputs: safeMetadataSchema,
    trade_in_id: m3UuidSchema,
    updated_at: m3TimestampSchema,
    vehicle_id: nullableUuid,
    version: m3ExpectedVersionSchema,
  })
  .strict();

export interface M3DealListInput {
  readonly accessToken: string;
  readonly cursorId?: string;
  readonly cursorUpdatedAt?: string;
  readonly limit?: number;
  readonly ownerMembershipId?: string;
  readonly status?: z.infer<typeof canonicalStatusSchema>;
  readonly workspaceId: string;
}

export interface M3DealChildListInput {
  readonly accessToken: string;
  readonly cursorCreatedAt?: string;
  readonly cursorId?: string;
  readonly cursorSortOrder?: number;
  readonly dealId: string;
  readonly limit?: number;
  readonly workspaceId: string;
}

export interface M3DealQueryInput {
  readonly accessToken: string;
  readonly dealId: string;
  readonly workspaceId: string;
}

export interface M3DealChildCommandInput extends M3EntityCommandInput {
  readonly childId: string;
}

export interface M3TradeInQueryInput {
  readonly accessToken: string;
  readonly dealId: string;
  readonly workspaceId: string;
}

function normalizeDeal<T>(operation: () => T): T {
  try {
    return operation();
  } catch (error) {
    if (error instanceof M3DealDomainError) {
      throw new M3ApplicationValidationError("invalid_request_body");
    }
    throw error;
  }
}

function commandEvidence(row: z.infer<typeof m3CommandEvidenceSchema>) {
  return {
    aggregateVersion: row.aggregate_version,
    auditEventId: row.audit_event_id,
    outboxEventId: row.outbox_event_id,
    replayed: row.replayed,
  } as const;
}

function dealEvidence(row: z.infer<typeof dealResultSchema>) {
  return {
    ...commandEvidence(row),
    canonicalStatus: row.canonical_status,
    dealId: row.deal_id,
    stateKey: row.state_key,
  } as const;
}

function parseOptionalUuid(value: string | undefined): string | null {
  return value === undefined ? null : parseM3EntityId(value);
}

function childListParameters(
  input: M3DealChildListInput,
  cursorMode: "created_at" | "sort_order",
) {
  const limit = input.limit ?? 100;
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new M3ApplicationValidationError("invalid_request_body");
  }
  const cursorId = parseOptionalUuid(input.cursorId);
  if (cursorMode === "created_at") {
    const cursorCreatedAt =
      input.cursorCreatedAt === undefined
        ? null
        : parseM3Body(m3TimestampSchema, input.cursorCreatedAt);
    if (
      input.cursorSortOrder !== undefined ||
      (cursorCreatedAt === null) !== (cursorId === null)
    ) {
      throw new M3ApplicationValidationError("invalid_request_body");
    }
    return {
      p_cursor_created_at: cursorCreatedAt,
      p_cursor_id: cursorId,
      p_deal_id: parseM3EntityId(input.dealId),
      p_limit: limit,
      p_workspace_id: input.workspaceId,
    } as const;
  }
  const cursorSortOrder = input.cursorSortOrder ?? null;
  if (
    input.cursorCreatedAt !== undefined ||
    (cursorSortOrder === null) !== (cursorId === null) ||
    (cursorSortOrder !== null &&
      (!Number.isInteger(cursorSortOrder) || cursorSortOrder < 0))
  ) {
    throw new M3ApplicationValidationError("invalid_request_body");
  }
  return {
    p_cursor_id: cursorId,
    p_cursor_sort_order: cursorSortOrder,
    p_deal_id: parseM3EntityId(input.dealId),
    p_limit: limit,
    p_workspace_id: input.workspaceId,
  } as const;
}

function tradeInParameters(
  command: Readonly<{
    allowance: { readonly amountMinor: string; readonly currencyCode: string };
    conditionKey: string | null;
    enteredVehicleFacts: Readonly<Record<string, unknown>> | null;
    lenderPartyId: string | null;
    lienAmount: { readonly amountMinor: string };
    odometerUnit: "km" | "mi" | null;
    odometerValue: number | null;
    ownerPartyId: string;
    payoffAmount: { readonly amountMinor: string };
    taxEligibilityInputs: Readonly<Record<string, unknown>>;
    vehicleId: string | null;
  }>,
  input: M3EntityCommandInput,
  expectedVersion: number,
) {
  return {
    p_allowance_minor: command.allowance.amountMinor,
    p_condition_key: command.conditionKey,
    p_correlation_id: input.metadata.correlationId,
    p_currency_code: command.allowance.currencyCode,
    p_entered_vehicle_facts: command.enteredVehicleFacts,
    p_expected_version: expectedVersion,
    p_idempotency_key: input.metadata.idempotencyKey,
    p_lender_party_id: command.lenderPartyId,
    p_lien_amount_minor: command.lienAmount.amountMinor,
    p_odometer_unit: command.odometerUnit,
    p_odometer_value: command.odometerValue,
    p_owner_party_id: command.ownerPartyId,
    p_payoff_amount_minor: command.payoffAmount.amountMinor,
    p_request_id: input.metadata.requestId,
    p_tax_eligibility_inputs: command.taxEligibilityInputs,
    p_vehicle_id: command.vehicleId,
    p_workspace_id: input.metadata.workspaceId,
  } as const;
}

export class M3DealsApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async listDeals(input: M3DealListInput) {
    const limit = input.limit ?? 50;
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
      throw new M3ApplicationValidationError("invalid_request_body");
    }
    const cursorUpdatedAt =
      input.cursorUpdatedAt === undefined
        ? null
        : parseM3Body(m3TimestampSchema, input.cursorUpdatedAt);
    const cursorId = parseOptionalUuid(input.cursorId);
    if ((cursorUpdatedAt === null) !== (cursorId === null)) {
      throw new M3ApplicationValidationError("invalid_request_body");
    }
    const rows = parseM3RpcRows(
      dealListRowSchema,
      100,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_deals",
        parameters: {
          p_cursor_id: cursorId,
          p_cursor_updated_at: cursorUpdatedAt,
          p_limit: limit,
          p_owner_membership_id: parseOptionalUuid(input.ownerMembershipId),
          p_status: input.status ?? null,
          p_workspace_id: input.workspaceId,
        },
      }),
    );
    return rows.map((row) => ({
      activeInventoryCount: row.active_inventory_count,
      activeLineItemCount: row.active_line_item_count,
      activeParticipantCount: row.active_participant_count,
      aggregateVersion: row.aggregate_version,
      canonicalStatus: row.canonical_status,
      currencyCode: row.currency_code,
      dealId: row.deal_id,
      dealTypeKey: row.deal_type_key,
      dealTypeLabels: row.deal_type_labels,
      dealTypeVersionId: row.deal_type_version_id,
      legalEntityId: row.legal_entity_id,
      lifecycleStatus: row.lifecycle_status,
      locationId: row.location_id,
      notes: row.notes,
      originatingLeadId: row.originating_lead_id,
      ownerMembershipId: row.owner_membership_id,
      stateKey: row.state_key,
      updatedAt: row.updated_at,
    }));
  }

  async getDeal(input: M3DealQueryInput) {
    const row = parseM3RpcRow(
      dealDetailRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_get_deal",
        parameters: {
          p_deal_id: parseM3EntityId(input.dealId),
          p_workspace_id: input.workspaceId,
        },
      }),
    );
    return {
      aggregateVersion: row.aggregate_version,
      availableTransitions: row.available_transitions,
      cancelledAt: row.cancelled_at,
      canonicalStatus: row.canonical_status,
      closedReason: row.closed_reason,
      completedAt: row.completed_at,
      createdAt: row.created_at,
      currencyCode: row.currency_code,
      dealId: row.deal_id,
      dealTypeBehaviorFlags: row.deal_type_behavior_flags,
      dealTypeChecksum: row.deal_type_checksum,
      dealTypeDefinitionId: row.deal_type_definition_id,
      dealTypeFieldSchema: row.deal_type_field_schema,
      dealTypeKey: row.deal_type_key,
      dealTypeLabels: row.deal_type_labels,
      dealTypeRevision: row.deal_type_revision,
      dealTypeSource: row.deal_type_source,
      dealTypeVersion: row.deal_type_version,
      dealTypeVersionId: row.deal_type_version_id,
      effectiveAt: row.effective_at,
      inventoryRoleOptions: row.inventory_role_options,
      legalEntityId: row.legal_entity_id,
      lifecycleStatus: row.lifecycle_status,
      locationId: row.location_id,
      notes: row.notes,
      oneTimeEventTypeOptions: row.one_time_event_type_options,
      originatingLeadId: row.originating_lead_id,
      ownerMembershipId: row.owner_membership_id,
      participantRoleOptions: row.participant_role_options,
      stateKey: row.state_key,
      updatedAt: row.updated_at,
      workflowInstanceId: row.workflow_instance_id,
      workflowVersionId: row.workflow_version_id,
    } as const;
  }

  async listDealParticipants(input: M3DealChildListInput) {
    return parseM3RpcRows(
      dealParticipantRowSchema,
      100,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_deal_participants",
        parameters: childListParameters(input, "created_at"),
      }),
    ).map((row) => ({
      createdAt: row.created_at,
      createdBy: row.created_by,
      isPrimary: row.is_primary,
      participantId: row.participant_id,
      partyDisplayName: row.party_display_name,
      partyId: row.party_id,
      releasedAt: row.released_at,
      releasedBy: row.released_by,
      roleKey: row.role_key,
      status: row.status,
      version: row.version,
    }));
  }

  async listDealInventory(input: M3DealChildListInput) {
    return parseM3RpcRows(
      dealInventoryRowSchema,
      100,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_deal_inventory",
        parameters: childListParameters(input, "created_at"),
      }),
    ).map((row) => ({
      amountMinor: row.amount_minor,
      createdAt: row.created_at,
      createdBy: row.created_by,
      currencyCode: row.currency_code,
      inventoryLinkId: row.inventory_link_id,
      inventoryStatus: row.inventory_status,
      inventoryUnitId: row.inventory_unit_id,
      metadata: row.metadata,
      releasedAt: row.released_at,
      releasedBy: row.released_by,
      roleKey: row.role_key,
      status: row.status,
      stockNumber: row.stock_number,
      version: row.version,
    }));
  }

  async listDealLineItems(input: M3DealChildListInput) {
    return parseM3RpcRows(
      dealLineItemRowSchema,
      100,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_deal_line_items",
        parameters: childListParameters(input, "sort_order"),
      }),
    ).map((row) => ({
      createdAt: row.created_at,
      createdBy: row.created_by,
      currencyCode: row.currency_code,
      itemType: row.item_type,
      key: row.key,
      label: row.label,
      lineItemId: row.line_item_id,
      paymentTimingKey: row.payment_timing_key,
      quantity: row.quantity,
      releasedAt: row.released_at,
      releasedBy: row.released_by,
      sortOrder: row.sort_order,
      sourceKey: row.source_key,
      sourceReference: row.source_reference,
      status: row.status,
      taxClassificationKey: row.tax_classification_key,
      unitAmountMinor: row.unit_amount_minor,
      updatedAt: row.updated_at,
      updatedBy: row.updated_by,
      version: row.version,
    }));
  }

  async createDeal(input: VerticalSliceCommandInput) {
    const body = parseM3Body(dealCreateBodySchema, input.body);
    const row = parseM3RpcRow(
      dealResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_create_deal",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: body.currencyCode,
          p_deal_type_key: body.dealTypeKey,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_legal_entity_id: body.legalEntityId,
          p_location_id: body.locationId,
          p_notes: body.notes,
          p_originating_lead_id: body.originatingLeadId,
          p_owner_membership_id: body.ownerMembershipId,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return dealEvidence(row);
  }

  async updateDeal(input: M3EntityCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const body = parseM3Body(dealUpdateBodySchema, input.body);
    const row = parseM3RpcRow(
      dealResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_update_deal",
        parameters: {
          p_clear_notes: body.notes === null,
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: dealId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_legal_entity_id: body.legalEntityId ?? null,
          p_location_id: body.locationId ?? null,
          p_notes: typeof body.notes === "string" ? body.notes : null,
          p_owner_membership_id: body.ownerMembershipId ?? null,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return dealEvidence(row);
  }

  async transitionDeal(input: M3EntityCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const body = parseM3Body(dealTransitionBodySchema, input.body);
    const row = parseM3RpcRow(
      dealTransitionResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_transition_deal",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: dealId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_transition_key: body.transitionKey,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...dealEvidence(row), workflowEventId: row.workflow_event_id };
  }

  async addParticipant(input: M3EntityCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const body = parseM3Body(participantBodySchema, input.body);
    const row = parseM3RpcRow(
      participantResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_add_deal_participant",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: dealId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_is_primary: body.isPrimary,
          p_party_id: body.partyId,
          p_request_id: input.metadata.requestId,
          p_role_key: body.roleKey,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...dealEvidence(row), participantId: row.participant_id };
  }

  async releaseParticipant(input: M3DealChildCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const participantId = parseM3EntityId(input.childId);
    const body = parseM3Body(releaseBodySchema, input.body);
    const row = parseM3RpcRow(
      participantResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_release_deal_participant",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: dealId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_participant_id: participantId,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...dealEvidence(row), participantId: row.participant_id };
  }

  async addInventory(input: M3EntityCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const body = parseM3Body(inventoryBodySchema, input.body);
    const row = parseM3RpcRow(
      inventoryResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_add_deal_inventory",
        parameters: {
          p_amount_minor: body.money?.amountMinor ?? null,
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: body.money?.currencyCode ?? null,
          p_deal_id: dealId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_inventory_unit_id: body.inventoryUnitId,
          p_metadata: body.metadata,
          p_request_id: input.metadata.requestId,
          p_role_key: body.roleKey,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...dealEvidence(row), inventoryLinkId: row.inventory_link_id };
  }

  async releaseInventory(input: M3DealChildCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const inventoryLinkId = parseM3EntityId(input.childId);
    const body = parseM3Body(releaseBodySchema, input.body);
    const row = parseM3RpcRow(
      inventoryResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_release_deal_inventory",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: dealId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_inventory_link_id: inventoryLinkId,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...dealEvidence(row), inventoryLinkId: row.inventory_link_id };
  }

  async listTradeIns(input: M3TradeInQueryInput) {
    return parseM3RpcRows(
      tradeInListRowSchema,
      100,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_trade_ins",
        parameters: {
          p_deal_id: parseM3EntityId(input.dealId),
          p_workspace_id: input.workspaceId,
        },
      }),
    ).map((row) => ({
      allowanceMinor: row.allowance_minor,
      conditionKey: row.condition_key,
      createdAt: row.created_at,
      currencyCode: row.currency_code,
      dealId: row.deal_id,
      enteredVehicleFacts: row.entered_vehicle_facts,
      lenderPartyId: row.lender_party_id,
      lienAmountMinor: row.lien_amount_minor,
      odometerUnit: row.odometer_unit,
      odometerValue: row.odometer_value,
      ownerPartyId: row.owner_party_id,
      payoffAmountMinor: row.payoff_amount_minor,
      resultingInventoryUnitId: row.resulting_inventory_unit_id,
      status: row.status,
      taxEligibilityInputs: row.tax_eligibility_inputs,
      tradeInId: row.trade_in_id,
      updatedAt: row.updated_at,
      vehicleId: row.vehicle_id,
      version: row.version,
    }));
  }

  async createTradeIn(input: M3EntityCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const body = parseM3Body(tradeInCreateBodySchema, input.body);
    const command = normalizeDeal(() =>
      normalizeTradeInCommand({ ...body, dealId }),
    );
    const row = parseM3RpcRow(
      tradeInResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_create_trade_in",
        parameters: {
          ...tradeInParameters(command, input, body.expectedVersion),
          p_deal_id: dealId,
        },
      }),
    );
    return {
      ...dealEvidence(row),
      tradeInId: row.trade_in_id,
      tradeInVersion: row.trade_in_version,
    };
  }

  async updateTradeIn(input: M3EntityCommandInput) {
    const tradeInId = parseM3EntityId(input.entityId);
    const body = parseM3Body(tradeInUpdateBodySchema, input.body);
    const command = normalizeDeal(() => normalizeTradeInDetails(body));
    const row = parseM3RpcRow(
      tradeInResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_update_trade_in",
        parameters: {
          ...tradeInParameters(command, input, body.expectedVersion),
          p_expected_trade_in_version: body.expectedTradeInVersion,
          p_trade_in_id: tradeInId,
        },
      }),
    );
    return {
      ...dealEvidence(row),
      tradeInId: row.trade_in_id,
      tradeInVersion: row.trade_in_version,
    };
  }

  async confirmTradeInInventory(input: M3EntityCommandInput) {
    const tradeInId = parseM3EntityId(input.entityId);
    const body = parseM3Body(tradeInInventoryBodySchema, input.body);
    const row = parseM3RpcRow(
      tradeInResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_confirm_trade_in_inventory",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_trade_in_version: body.expectedTradeInVersion,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_inventory_unit_id: body.inventoryUnitId,
          p_request_id: input.metadata.requestId,
          p_trade_in_id: tradeInId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...dealEvidence(row),
      tradeInId: row.trade_in_id,
      tradeInVersion: row.trade_in_version,
    };
  }

  async addLineItem(input: M3EntityCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const body = parseM3Body(lineItemBodySchema, input.body);
    const command = normalizeDeal(() =>
      normalizeDealLineItemCommand({
        ...body,
        dealCurrencyCode: body.unitAmount.currencyCode,
        dealId,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseM3RpcRow(
      lineItemResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_add_deal_line_item",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: command.unitAmount.currencyCode,
          p_deal_id: command.dealId,
          p_expected_version: command.expectedVersion,
          p_idempotency_key: command.idempotencyKey,
          p_item_type: command.itemType,
          p_key: command.key,
          p_label: command.label,
          p_payment_timing_key: command.paymentTimingKey,
          p_quantity: command.quantity,
          p_request_id: input.metadata.requestId,
          p_sort_order: command.sortOrder,
          p_source_key: command.sourceKey,
          p_source_reference: command.sourceReference,
          p_tax_classification_key: command.taxClassificationKey,
          p_unit_amount_minor: command.unitAmount.amountMinor,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...dealEvidence(row), lineItemId: row.line_item_id };
  }

  async updateLineItem(input: M3DealChildCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const lineItemId = parseM3EntityId(input.childId);
    const body = parseM3Body(lineItemUpdateBodySchema, input.body);
    const command = normalizeDeal(() =>
      normalizeDealLineItemCommand({
        ...body,
        dealCurrencyCode: body.unitAmount.currencyCode,
        dealId,
        idempotencyKey: input.metadata.idempotencyKey,
        key: "line_item",
      }),
    );
    const row = parseM3RpcRow(
      lineItemUpdateResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_update_deal_line_item",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: command.unitAmount.currencyCode,
          p_deal_id: command.dealId,
          p_expected_line_item_version: body.expectedLineItemVersion,
          p_expected_version: command.expectedVersion,
          p_idempotency_key: command.idempotencyKey,
          p_item_type: command.itemType,
          p_label: command.label,
          p_line_item_id: lineItemId,
          p_payment_timing_key: command.paymentTimingKey,
          p_quantity: command.quantity,
          p_request_id: input.metadata.requestId,
          p_sort_order: command.sortOrder,
          p_source_key: command.sourceKey,
          p_source_reference: command.sourceReference,
          p_tax_classification_key: command.taxClassificationKey,
          p_unit_amount_minor: command.unitAmount.amountMinor,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...dealEvidence(row),
      lineItemId: row.line_item_id,
      lineItemVersion: row.line_item_version,
    };
  }

  async updateLineItemById(input: M3EntityCommandInput) {
    const lineItemId = parseM3EntityId(input.entityId);
    const body = parseM3Body(lineItemUpdateByIdBodySchema, input.body);
    const { dealId, ...details } = body;
    return this.updateLineItem({
      ...input,
      body: details,
      childId: lineItemId,
      entityId: dealId,
    });
  }
}
