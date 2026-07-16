import { normalizeCreatePartyCommand, PartyCommandError } from "@vynlo/crm";
import {
  DealDraftCommandError,
  normalizeCreateDealDraftCommand,
} from "@vynlo/deals";
import {
  DocumentPreviewCommandError,
  normalizeRequestDocumentPreviewCommand,
  PREVIEW_WATERMARK,
} from "@vynlo/documents";
import {
  InventoryCommandError,
  normalizeCreateInventoryUnitCommand,
} from "@vynlo/inventory";
import { z } from "zod";

const uuidSchema = z.string().uuid();
const safeIntegerSchema = z
  .number()
  .int()
  .min(Number.MIN_SAFE_INTEGER)
  .max(Number.MAX_SAFE_INTEGER);
const nonNegativeSafeIntegerSchema = safeIntegerSchema.min(0);

const inventoryBodySchema = z
  .object({
    acquisitionDate: z.string().max(10).nullable(),
    advertisedPriceMinor: nonNegativeSafeIntegerSchema.nullable(),
    currencyCode: z.string().min(1).max(8),
    make: z.string().max(100).nullable(),
    model: z.string().max(100).nullable(),
    modelYear: z.number().int().min(1886).max(2200).nullable(),
    odometer: z
      .object({
        unit: z.enum(["km", "mi"]),
        value: nonNegativeSafeIntegerSchema,
      })
      .strict()
      .nullable(),
    publicNotes: z.string().max(4_000).nullable(),
    stockNumberDefinitionId: uuidSchema,
    vin: z.string().min(1).max(64),
  })
  .strict();

const partyBodySchema = z
  .object({
    displayName: z.string().min(1).max(200),
    partyType: z.enum(["person", "organization"]),
  })
  .strict();

const dealBodySchema = z
  .object({
    currencyCode: z.string().min(1).max(8),
    dealTypeKey: z.string().min(1).max(200),
    inventory: z
      .object({
        inventoryUnitId: uuidSchema,
        roleKey: z.string().min(1).max(200),
      })
      .strict(),
    notes: z.string().max(4_000).nullable(),
    participant: z
      .object({
        partyId: uuidSchema,
        roleKey: z.string().min(1).max(200),
      })
      .strict(),
  })
  .strict();

const previewBodySchema = z
  .object({
    dealId: uuidSchema,
    locale: z.string().min(1).max(64),
    templateVersionId: uuidSchema,
  })
  .strict();

const inventoryResultSchema = z
  .object({
    inventory_unit_id: uuidSchema,
    replayed: z.boolean(),
    stock_number: z.string().min(1).max(200),
    vehicle_id: uuidSchema,
  })
  .strict();

const partyResultSchema = z
  .object({
    party_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();

const dealResultSchema = z
  .object({
    deal_id: uuidSchema,
    inventory_link_id: uuidSchema,
    participant_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();

const previewResultSchema = z
  .object({
    document_id: uuidSchema,
    job_id: uuidSchema,
    job_status: z.enum([
      "queued",
      "running",
      "retry_wait",
      "succeeded",
      "dead_letter",
      "cancelled",
    ]),
    outbox_event_id: uuidSchema,
    preview_status: z.enum(["queued", "generated", "failed"]),
    replayed: z.boolean(),
    watermark: z.literal(PREVIEW_WATERMARK),
  })
  .strict();

export type VerticalSliceRpcFunctionName =
  | "authorize_document_preview_download"
  | "create_inventory_unit"
  | "create_inventory_unit_from_failed_vin_decode"
  | "create_inventory_unit_from_vin_decode"
  | "create_party"
  | "create_deal_draft"
  | "request_document_preview_job"
  | "create_workspace_invitation_job"
  | "accept_workspace_invitation"
  | "update_inventory_unit_details"
  | "post_inventory_cost_entry"
  | "reverse_inventory_cost_entry"
  | "save_inventory_view"
  | "list_inventory_saved_views"
  | "archive_inventory_saved_view"
  | "search_inventory_units"
  | "get_inventory_unit_operations"
  | "list_active_inventory_locations"
  | "get_inventory_unit_costs"
  | "override_vehicle_facts"
  | "request_vin_decode_job"
  | "get_vin_decode_request"
  | "retry_vin_decode_job"
  | "review_vin_duplicate_request"
  | "create_vehicle_photo_upload_session"
  | "get_vehicle_photo_upload_status"
  | "request_vehicle_photo_upload_verification"
  | "retry_vehicle_photo_upload_verification"
  | "reprocess_vehicle_photo"
  | "reorder_inventory_media"
  | "set_inventory_media_cover"
  | "get_vehicle_media_asset"
  | "list_inventory_vehicle_media"
  | "update_vehicle_media_caption"
  | "archive_vehicle_media"
  | "authorize_managed_media_download"
  | "create_legal_original_upload_session"
  | "get_legal_original_upload_status"
  | "request_legal_original_upload_verification"
  | "retry_legal_original_upload_verification"
  | "transfer_inventory_unit_location"
  | "transition_inventory_workflow";

export interface AuthenticatedRpcRequest {
  readonly accessToken: string;
  readonly functionName: VerticalSliceRpcFunctionName;
  readonly parameters: Readonly<Record<string, unknown>>;
}

export interface AuthenticatedRpcGateway {
  invoke(request: AuthenticatedRpcRequest): Promise<unknown>;
}

export interface VerticalSliceCommandMetadata {
  readonly accessToken: string;
  readonly correlationId: string;
  readonly idempotencyKey: string;
  readonly requestId: string;
  readonly workspaceId: string;
}

export interface VerticalSliceCommandInput {
  readonly body: unknown;
  readonly metadata: VerticalSliceCommandMetadata;
}

export type VerticalSliceValidationErrorCode =
  | "invalid_request_body"
  | "invalid_idempotency_key"
  | "invalid_stock_definition_id"
  | "invalid_vin"
  | "invalid_model_year"
  | "invalid_vehicle_text"
  | "invalid_acquisition_date"
  | "invalid_odometer"
  | "invalid_currency"
  | "invalid_money_minor"
  | "invalid_public_notes"
  | "invalid_stock_format"
  | "invalid_party_type"
  | "invalid_display_name"
  | "invalid_deal_type_key"
  | "invalid_party_id"
  | "invalid_participant_role_key"
  | "invalid_inventory_unit_id"
  | "invalid_inventory_role_key"
  | "invalid_notes"
  | "invalid_deal_id"
  | "invalid_template_version_id"
  | "invalid_locale"
  | "invalid_preview_record"
  | "invalid_preview_transition";

export class VerticalSliceValidationError extends Error {
  readonly code: VerticalSliceValidationErrorCode;

  constructor(code: VerticalSliceValidationErrorCode) {
    super("The command input is invalid.");
    this.name = "VerticalSliceValidationError";
    this.code = code;
  }
}

export class VerticalSliceRpcContractError extends Error {
  constructor() {
    super("The command data store returned an invalid response.");
    this.name = "VerticalSliceRpcContractError";
  }
}

export interface CreateInventoryUnitResult {
  readonly inventoryUnitId: string;
  readonly replayed: boolean;
  readonly stockNumber: string;
  readonly vehicleId: string;
}

export interface CreatePartyResult {
  readonly partyId: string;
  readonly replayed: boolean;
}

export interface CreateDealDraftResult {
  readonly dealId: string;
  readonly inventoryLinkId: string;
  readonly participantId: string;
  readonly replayed: boolean;
}

export interface RequestDocumentPreviewResult {
  readonly documentId: string;
  readonly jobId: string;
  readonly jobStatus:
    | "queued"
    | "running"
    | "retry_wait"
    | "succeeded"
    | "dead_letter"
    | "cancelled";
  readonly outboxEventId: string;
  readonly previewStatus: "queued" | "generated" | "failed";
  readonly replayed: boolean;
  readonly watermark: typeof PREVIEW_WATERMARK;
}

function parseBody<T>(schema: z.ZodType<T>, body: unknown): T {
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    throw new VerticalSliceValidationError("invalid_request_body");
  }
  return parsed.data;
}

function normalizeCommand<T>(normalize: () => T): T {
  try {
    return normalize();
  } catch (error) {
    if (
      error instanceof InventoryCommandError ||
      error instanceof PartyCommandError ||
      error instanceof DealDraftCommandError ||
      error instanceof DocumentPreviewCommandError
    ) {
      throw new VerticalSliceValidationError(error.code);
    }
    throw error;
  }
}

function parseRpcRow<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = z.array(schema).length(1).safeParse(value);
  if (!result.success) {
    throw new VerticalSliceRpcContractError();
  }
  return result.data[0]!;
}

export class VerticalSliceApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async createInventoryUnit(
    input: VerticalSliceCommandInput,
  ): Promise<CreateInventoryUnitResult> {
    const body = parseBody(inventoryBodySchema, input.body);
    const command = normalizeCommand(() =>
      normalizeCreateInventoryUnitCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseRpcRow(
      inventoryResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_inventory_unit",
        parameters: {
          p_acquisition_date: command.acquisitionDate,
          p_advertised_price_minor: command.advertisedPriceMinor,
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: command.currencyCode,
          p_idempotency_key: command.idempotencyKey,
          p_make: command.make,
          p_model: command.model,
          p_model_year: command.modelYear,
          p_odometer_unit: command.odometer?.unit ?? null,
          p_odometer_value: command.odometer?.value ?? null,
          p_public_notes: command.publicNotes,
          p_request_id: input.metadata.requestId,
          p_stock_definition_id: command.stockNumberDefinitionId,
          p_vin: command.vin,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );

    return {
      inventoryUnitId: row.inventory_unit_id,
      replayed: row.replayed,
      stockNumber: row.stock_number,
      vehicleId: row.vehicle_id,
    };
  }

  async createParty(
    input: VerticalSliceCommandInput,
  ): Promise<CreatePartyResult> {
    const body = parseBody(partyBodySchema, input.body);
    const command = normalizeCommand(() =>
      normalizeCreatePartyCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseRpcRow(
      partyResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_party",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_display_name: command.displayName,
          p_idempotency_key: command.idempotencyKey,
          p_party_type: command.partyType,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );

    return { partyId: row.party_id, replayed: row.replayed };
  }

  async createDealDraft(
    input: VerticalSliceCommandInput,
  ): Promise<CreateDealDraftResult> {
    const body = parseBody(dealBodySchema, input.body);
    const command = normalizeCommand(() =>
      normalizeCreateDealDraftCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseRpcRow(
      dealResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_deal_draft",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: command.currencyCode,
          p_deal_type_key: command.dealTypeKey,
          p_idempotency_key: command.idempotencyKey,
          p_inventory_role_key: command.inventory.roleKey,
          p_inventory_unit_id: command.inventory.inventoryUnitId,
          p_notes: command.notes,
          p_participant_role_key: command.participant.roleKey,
          p_party_id: command.participant.partyId,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );

    return {
      dealId: row.deal_id,
      inventoryLinkId: row.inventory_link_id,
      participantId: row.participant_id,
      replayed: row.replayed,
    };
  }

  async requestDocumentPreview(
    input: VerticalSliceCommandInput,
  ): Promise<RequestDocumentPreviewResult> {
    const body = parseBody(previewBodySchema, input.body);
    const command = normalizeCommand(() =>
      normalizeRequestDocumentPreviewCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseRpcRow(
      previewResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "request_document_preview_job",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: command.dealId,
          p_idempotency_key: command.idempotencyKey,
          p_locale: command.locale,
          p_request_id: input.metadata.requestId,
          p_template_version_id: command.templateVersionId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );

    return {
      documentId: row.document_id,
      jobId: row.job_id,
      jobStatus: row.job_status,
      outboxEventId: row.outbox_event_id,
      previewStatus: row.preview_status,
      replayed: row.replayed,
      watermark: row.watermark,
    };
  }
}
