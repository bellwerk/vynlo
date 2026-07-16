import { z } from "zod";

import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;
const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const versionSchema = z.number().int().min(1).max(2_147_483_647);
const moneyMinorSchema = z
  .string()
  .trim()
  .refine(
    (value) =>
      /^(?:0|[1-9]\d{0,18})$/u.test(value) &&
      BigInt(value) <= POSTGRES_BIGINT_MAX,
  )
  .transform((value) => BigInt(value).toString());
const positiveMoneyMinorSchema = moneyMinorSchema.refine(
  (value) => value !== "0",
);
const signedMoneyMinorSchema = z.string().refine((value) => {
  if (!/^-?(?:0|[1-9]\d{0,18})$/u.test(value)) {
    return false;
  }
  const parsed = BigInt(value);
  return parsed >= -POSTGRES_BIGINT_MAX && parsed <= POSTGRES_BIGINT_MAX;
});
const currencySchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z]{3}$/u);
const nullableTrimmedText = (maximumLength: number) =>
  z
    .string()
    .trim()
    .max(maximumLength)
    .transform((value) => (value === "" ? null : value))
    .nullable();
const canonicalStatusSchema = z.enum([
  "draft",
  "active",
  "pending",
  "closed",
  "archived",
]);
const stateKeySchema = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_]*$/u);

const postCostBodySchema = z
  .object({
    amountMinor: positiveMoneyMinorSchema,
    categoryDefinitionId: uuidSchema,
    currencyCode: currencySchema,
    description: nullableTrimmedText(2_000),
    expectedVersion: versionSchema,
    incurredOn: z.iso.date(),
    supportingFileId: uuidSchema.nullable(),
    vendorPartyId: uuidSchema.nullable(),
  })
  .strict();

const reverseCostBodySchema = z
  .object({
    expectedVersion: versionSchema,
    reason: z.string().trim().min(1).max(2_000),
    reversedOn: z.iso.date(),
  })
  .strict();

const costPostedRowSchema = z
  .object({
    aggregate_version: versionSchema,
    audit_event_id: uuidSchema,
    cost_entry_id: uuidSchema,
    inventory_unit_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();

const costReversedRowSchema = z
  .object({
    aggregate_version: versionSchema,
    audit_event_id: uuidSchema,
    inventory_unit_id: uuidSchema,
    original_cost_entry_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    reversal_entry_id: uuidSchema,
  })
  .strict();

const savedViewColumnSchema = z.enum([
  "cover",
  "stock",
  "vehicle",
  "vin",
  "price",
  "location",
  "state",
  "days_in_stock",
  "media_readiness",
  "listing_status",
  "warnings",
  "posted_cost",
  "estimated_gross",
]);
const savedViewFiltersSchema = z
  .object({
    locationIds: z.array(uuidSchema).max(20).optional(),
    make: z.string().trim().min(1).max(100).optional(),
    maximumDaysInStock: z.number().int().min(0).max(100_000).optional(),
    maximumPriceMinor: moneyMinorSchema.optional(),
    minimumDaysInStock: z.number().int().min(0).max(100_000).optional(),
    minimumPriceMinor: moneyMinorSchema.optional(),
    missingFields: z
      .array(
        z.enum([
          "vin",
          "model_year",
          "make",
          "model",
          "location",
          "price",
          "media",
        ]),
      )
      .max(7)
      .optional(),
    model: z.string().trim().min(1).max(100).optional(),
    status: z.array(canonicalStatusSchema).max(5).optional(),
  })
  .strict();
const savedViewSortSchema = z
  .object({
    direction: z.enum(["asc", "desc"]),
    key: z.enum([
      "updated_at",
      "stock_number",
      "advertised_price",
      "days_in_stock",
      "estimated_gross",
    ]),
  })
  .strict();
const saveViewBodySchema = z
  .object({
    density: z.enum(["comfortable", "compact"]),
    expectedVersion: versionSchema.nullable(),
    filters: savedViewFiltersSchema,
    layout: z.enum(["responsive", "cards", "table"]),
    name: z.string().trim().min(1).max(120),
    savedViewId: uuidSchema.nullable(),
    shareScope: z.enum(["private", "workspace"]),
    sort: savedViewSortSchema,
    visibleColumns: z.array(savedViewColumnSchema).min(1).max(20),
  })
  .strict()
  .superRefine((value, context) => {
    if ((value.savedViewId === null) !== (value.expectedVersion === null)) {
      context.addIssue({ code: "custom", message: "version contract" });
    }
    if (new Set(value.visibleColumns).size !== value.visibleColumns.length) {
      context.addIssue({ code: "custom", message: "duplicate column" });
    }
  });
const savedViewResultRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    replayed: z.boolean(),
    saved_view_id: uuidSchema,
    saved_view_version: versionSchema,
  })
  .strict();

const archiveSavedViewBodySchema = z
  .object({ expectedVersion: versionSchema })
  .strict();

const savedViewRowSchema = z
  .object({
    density: z.enum(["comfortable", "compact"]),
    filters: savedViewFiltersSchema,
    is_owner: z.boolean(),
    layout: z.enum(["responsive", "cards", "table"]),
    name: z.string().min(1).max(120),
    saved_view_id: uuidSchema,
    share_scope: z.enum(["private", "workspace"]),
    sort: savedViewSortSchema,
    status: z.enum(["active", "archived"]),
    updated_at: z.iso.datetime({ offset: true }),
    version: versionSchema,
    visible_columns: z.array(savedViewColumnSchema).min(1).max(20),
  })
  .strict();

const costLedgerQuerySchema = z
  .object({
    cursor: z
      .object({
        createdAt: z.iso.datetime({ offset: true }),
        id: uuidSchema,
      })
      .strict()
      .nullable()
      .default(null),
    pageSize: z.number().int().min(1).max(200).default(100),
  })
  .strict();

const costCategorySchema = z
  .object({
    id: uuidSchema,
    key: z.string().regex(/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/u),
    labels: z.record(z.string(), z.string()),
    version: versionSchema,
  })
  .strict();

const costLedgerEntrySchema = z
  .object({
    aggregateVersion: versionSchema,
    amountMinor: moneyMinorSchema,
    categoryDefinitionId: uuidSchema,
    categoryKey: z.string().regex(/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/u),
    categoryLabels: z.record(z.string(), z.string()),
    createdAt: z.iso.datetime({ offset: true }),
    currencyCode: currencySchema,
    description: z.string().max(2_000).nullable(),
    effectiveStatus: z.enum(["posted", "reversed", "reversal"]),
    entryKind: z.enum(["cost", "reversal"]),
    id: uuidSchema,
    incurredOn: z.iso.date(),
    reversalOfId: uuidSchema.nullable(),
    supportingFileId: uuidSchema.nullable(),
    vendorPartyId: uuidSchema.nullable(),
  })
  .strict();

const costLedgerRowSchema = z
  .object({
    aggregate_version: versionSchema,
    can_create: z.boolean(),
    can_reverse: z.boolean(),
    categories: z.array(costCategorySchema).max(500),
    currency_code: currencySchema,
    entries: z.array(costLedgerEntrySchema).max(200),
    estimated_gross_minor: signedMoneyMinorSchema.nullable(),
    has_recent_strong_authentication: z.boolean(),
    inventory_unit_id: uuidSchema,
    last_cost_at: z.iso.datetime({ offset: true }).nullable(),
    next_cursor: z
      .object({
        createdAt: z.iso.datetime({ offset: true }),
        id: uuidSchema,
      })
      .strict()
      .nullable(),
    posted_cost_minor: moneyMinorSchema,
    posted_entry_count: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
  })
  .strict();

const inventorySearchInputSchema = z
  .object({
    cursor: z
      .object({
        id: uuidSchema,
        rank: z.number().finite().min(0),
        updatedAt: z.iso.datetime({ offset: true }),
      })
      .strict()
      .nullable()
      .default(null),
    locationIds: z.array(uuidSchema).max(20).default([]),
    maximumDaysInStock: z
      .number()
      .int()
      .min(0)
      .max(100_000)
      .nullable()
      .default(null),
    maximumPriceMinor: moneyMinorSchema.nullable().default(null),
    minimumDaysInStock: z
      .number()
      .int()
      .min(0)
      .max(100_000)
      .nullable()
      .default(null),
    minimumPriceMinor: moneyMinorSchema.nullable().default(null),
    pageSize: z.number().int().min(1).max(100).default(50),
    query: z.string().trim().max(200).nullable().default(null),
    statuses: z.array(canonicalStatusSchema).max(5).default([]),
  })
  .strict()
  .superRefine((value, context) => {
    if (
      value.minimumPriceMinor !== null &&
      value.maximumPriceMinor !== null &&
      BigInt(value.minimumPriceMinor) > BigInt(value.maximumPriceMinor)
    ) {
      context.addIssue({ code: "custom", message: "price range" });
    }
    if (
      value.minimumDaysInStock !== null &&
      value.maximumDaysInStock !== null &&
      value.minimumDaysInStock > value.maximumDaysInStock
    ) {
      context.addIssue({ code: "custom", message: "age range" });
    }
  });

const searchRowSchema = z
  .object({
    advertised_price_minor: moneyMinorSchema.nullable(),
    aggregate_version: versionSchema,
    canonical_status: canonicalStatusSchema,
    currency_code: currencySchema,
    days_in_stock: z.number().int().min(0),
    estimated_gross_minor: signedMoneyMinorSchema.nullable(),
    inventory_unit_id: uuidSchema,
    location_id: uuidSchema.nullable(),
    location_name: z.string().nullable(),
    make: z.string().nullable(),
    model: z.string().nullable(),
    model_year: z.number().int().min(1886).max(2200).nullable(),
    posted_cost_minor: moneyMinorSchema.nullable(),
    search_rank: z.number().finite().min(0),
    stock_number: z.string().min(1).max(200),
    updated_at: z.iso.datetime({ offset: true }),
    vehicle_trim: z.string().nullable(),
    vin: z.string().regex(/^[A-HJ-NPR-Z0-9]{17}$/u),
    workflow_state_key: stateKeySchema,
  })
  .strict();

export type M2CostSearchValidationErrorCode =
  | "invalid_request_body"
  | "invalid_inventory_unit_id"
  | "invalid_cost_entry_id"
  | "invalid_search_query";

export class M2CostSearchValidationError extends Error {
  readonly code: M2CostSearchValidationErrorCode;

  constructor(code: M2CostSearchValidationErrorCode) {
    super("The inventory cost or search request is invalid.");
    this.name = "M2CostSearchValidationError";
    this.code = code;
  }
}

export class M2CostSearchRpcContractError extends Error {
  constructor() {
    super(
      "The inventory cost or search data store returned an invalid response.",
    );
    this.name = "M2CostSearchRpcContractError";
  }
}

export interface M2EntityCommandInput extends VerticalSliceCommandInput {
  readonly entityId: string;
}

export interface M2EntityQueryInput {
  readonly accessToken: string;
  readonly entityId: string;
  readonly query: unknown;
  readonly workspaceId: string;
}

export interface M2SavedViewsQueryInput {
  readonly accessToken: string;
  readonly includeArchived?: boolean;
  readonly workspaceId: string;
}

export interface InventorySearchInput {
  readonly accessToken: string;
  readonly query: unknown;
  readonly workspaceId: string;
}

function parseBody<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    throw new M2CostSearchValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseId(value: string, code: M2CostSearchValidationErrorCode): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new M2CostSearchValidationError(code);
  }
  return parsed.data;
}

function parseSingleRow<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = z.array(schema).length(1).safeParse(value);
  if (!parsed.success) {
    throw new M2CostSearchRpcContractError();
  }
  return parsed.data[0]!;
}

function assertRpcEntityId(actual: string, expected: string): void {
  if (actual !== expected) {
    throw new M2CostSearchRpcContractError();
  }
}

export class M2CostSearchApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async postCost(input: M2EntityCommandInput) {
    const inventoryUnitId = parseId(
      input.entityId,
      "invalid_inventory_unit_id",
    );
    const body = parseBody(postCostBodySchema, input.body);
    const row = parseSingleRow(
      costPostedRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "post_inventory_cost_entry",
        parameters: {
          p_amount_minor: body.amountMinor,
          p_category_definition_id: body.categoryDefinitionId,
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: body.currencyCode,
          p_description: body.description,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_incurred_on: body.incurredOn,
          p_inventory_unit_id: inventoryUnitId,
          p_request_id: input.metadata.requestId,
          p_supporting_file_id: body.supportingFileId,
          p_vendor_party_id: body.vendorPartyId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.inventory_unit_id, inventoryUnitId);
    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      costEntryId: row.cost_entry_id,
      inventoryUnitId: row.inventory_unit_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
    };
  }

  async getCosts(input: M2EntityQueryInput) {
    const inventoryUnitId = parseId(
      input.entityId,
      "invalid_inventory_unit_id",
    );
    const workspaceId = parseId(input.workspaceId, "invalid_search_query");
    const query = parseBody(costLedgerQuerySchema, input.query);
    const row = parseSingleRow(
      costLedgerRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "get_inventory_unit_costs",
        parameters: {
          p_before_created_at: query.cursor?.createdAt ?? null,
          p_before_id: query.cursor?.id ?? null,
          p_inventory_unit_id: inventoryUnitId,
          p_page_size: query.pageSize,
          p_workspace_id: workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.inventory_unit_id, inventoryUnitId);
    return {
      aggregateVersion: row.aggregate_version,
      canCreate: row.can_create,
      canReverse: row.can_reverse,
      categories: row.categories,
      currencyCode: row.currency_code,
      entries: row.entries,
      estimatedGrossMinor: row.estimated_gross_minor,
      hasRecentStrongAuthentication: row.has_recent_strong_authentication,
      inventoryUnitId: row.inventory_unit_id,
      lastCostAt: row.last_cost_at,
      nextCursor: row.next_cursor,
      postedCostMinor: row.posted_cost_minor,
      postedEntryCount: row.posted_entry_count,
    };
  }

  async reverseCost(input: M2EntityCommandInput) {
    const costEntryId = parseId(input.entityId, "invalid_cost_entry_id");
    const body = parseBody(reverseCostBodySchema, input.body);
    const row = parseSingleRow(
      costReversedRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "reverse_inventory_cost_entry",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_cost_entry_id: costEntryId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_reversed_on: body.reversedOn,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.original_cost_entry_id, costEntryId);
    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      inventoryUnitId: row.inventory_unit_id,
      originalCostEntryId: row.original_cost_entry_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      reversalEntryId: row.reversal_entry_id,
    };
  }

  async saveView(input: VerticalSliceCommandInput) {
    const body = parseBody(saveViewBodySchema, input.body);
    const row = parseSingleRow(
      savedViewResultRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "save_inventory_view",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_density: body.density,
          p_expected_version: body.expectedVersion,
          p_filters: body.filters,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_layout: body.layout,
          p_name: body.name,
          p_request_id: input.metadata.requestId,
          p_saved_view_id: body.savedViewId,
          p_share_scope: body.shareScope,
          p_sort: body.sort,
          p_visible_columns: body.visibleColumns,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    if (body.savedViewId !== null) {
      assertRpcEntityId(row.saved_view_id, body.savedViewId);
    }
    return {
      auditEventId: row.audit_event_id,
      created: body.savedViewId === null && !row.replayed,
      replayed: row.replayed,
      savedViewId: row.saved_view_id,
      savedViewVersion: row.saved_view_version,
    };
  }

  async listSavedViews(input: M2SavedViewsQueryInput) {
    const workspaceId = parseId(input.workspaceId, "invalid_search_query");
    const value = await this.#gateway.invoke({
      accessToken: input.accessToken,
      functionName: "list_inventory_saved_views",
      parameters: {
        p_include_archived: input.includeArchived ?? false,
        p_workspace_id: workspaceId,
      },
    });
    const rows = z.array(savedViewRowSchema).max(100).safeParse(value);
    if (!rows.success) {
      throw new M2CostSearchRpcContractError();
    }
    return {
      items: rows.data.map((row) => ({
        density: row.density,
        filters: row.filters,
        isOwner: row.is_owner,
        layout: row.layout,
        name: row.name,
        savedViewId: row.saved_view_id,
        shareScope: row.share_scope,
        sort: row.sort,
        status: row.status,
        updatedAt: row.updated_at,
        version: row.version,
        visibleColumns: row.visible_columns,
      })),
    };
  }

  async archiveView(input: M2EntityCommandInput) {
    const savedViewId = parseId(input.entityId, "invalid_request_body");
    const body = parseBody(archiveSavedViewBodySchema, input.body);
    const row = parseSingleRow(
      savedViewResultRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "archive_inventory_saved_view",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_request_id: input.metadata.requestId,
          p_saved_view_id: savedViewId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertRpcEntityId(row.saved_view_id, savedViewId);
    return {
      auditEventId: row.audit_event_id,
      replayed: row.replayed,
      savedViewId: row.saved_view_id,
      savedViewVersion: row.saved_view_version,
    };
  }

  async search(input: InventorySearchInput) {
    const workspaceId = parseId(input.workspaceId, "invalid_search_query");
    const parsed = inventorySearchInputSchema.safeParse(input.query);
    if (!parsed.success) {
      throw new M2CostSearchValidationError("invalid_search_query");
    }
    const query = parsed.data;
    const value = await this.#gateway.invoke({
      accessToken: input.accessToken,
      functionName: "search_inventory_units",
      parameters: {
        p_before_id: query.cursor?.id ?? null,
        p_before_rank: query.cursor?.rank ?? null,
        p_before_updated_at: query.cursor?.updatedAt ?? null,
        p_location_ids:
          query.locationIds.length === 0 ? null : query.locationIds,
        p_maximum_days_in_stock: query.maximumDaysInStock,
        p_maximum_price_minor: query.maximumPriceMinor,
        p_minimum_days_in_stock: query.minimumDaysInStock,
        p_minimum_price_minor: query.minimumPriceMinor,
        p_page_size: query.pageSize,
        p_query: query.query,
        p_statuses: query.statuses.length === 0 ? null : query.statuses,
        p_workspace_id: workspaceId,
      },
    });
    const rows = z.array(searchRowSchema).max(query.pageSize).safeParse(value);
    if (!rows.success) {
      throw new M2CostSearchRpcContractError();
    }
    return {
      items: rows.data.map((row) => ({
        advertisedPriceMinor: row.advertised_price_minor,
        aggregateVersion: row.aggregate_version,
        canonicalStatus: row.canonical_status,
        currencyCode: row.currency_code,
        daysInStock: row.days_in_stock,
        estimatedGrossMinor: row.estimated_gross_minor,
        inventoryUnitId: row.inventory_unit_id,
        locationId: row.location_id,
        locationName: row.location_name,
        make: row.make,
        model: row.model,
        modelYear: row.model_year,
        postedCostMinor: row.posted_cost_minor,
        searchRank: row.search_rank,
        stockNumber: row.stock_number,
        trim: row.vehicle_trim,
        updatedAt: row.updated_at,
        vin: row.vin,
        workflowStateKey: row.workflow_state_key,
      })),
      nextCursor:
        rows.data.length === query.pageSize && rows.data.at(-1)
          ? {
              id: rows.data.at(-1)!.inventory_unit_id,
              rank: rows.data.at(-1)!.search_rank,
              updatedAt: rows.data.at(-1)!.updated_at,
            }
          : null,
    };
  }
}
