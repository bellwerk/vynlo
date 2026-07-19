import {
  compileExportDefinition,
  type CompiledExportDefinition,
  type ExportFormat,
} from "@vynlo/exports";

import { JobExecutionError } from "./job-runner";
import {
  invalidM4Contract,
  requireArray,
  requireRecord,
  requireString,
  UUID_PATTERN,
} from "./m4-worker-validation";

export interface ExportExecutionSource {
  readonly authorizedColumnPlan: readonly unknown[];
  readonly definitionChecksum: string;
  readonly definitionKey: string;
  readonly expiresAt: string;
  readonly filters: Readonly<Record<string, unknown>>;
  readonly locale: string;
  readonly maximumRows: number;
  readonly requestedFormat: ExportFormat;
  readonly semanticVersion: string;
  readonly sortSpecification: readonly unknown[];
  readonly sourceKey: string;
}

export interface ExportSourceReadRequest {
  readonly exportRunId: string;
  readonly filters: Readonly<Record<string, string>>;
  readonly jobId: string;
  readonly leaseToken: string;
  readonly maximumRows: number;
  readonly select: string;
  readonly signal: AbortSignal;
  readonly table: "deals" | "inventory_units" | "leads";
  readonly workerId: string;
  readonly workspaceId: string;
}

export interface ExportSourceSnapshot {
  readonly capturedAt: string;
  readonly fingerprint: string;
  readonly id: string;
  readonly rowCount: number;
}

export interface ExportSourceSnapshotRead {
  readonly rows: readonly Record<string, unknown>[];
  readonly snapshot: ExportSourceSnapshot;
}

export interface ExportSourceReader {
  read(request: ExportSourceReadRequest): Promise<ExportSourceSnapshotRead>;
}

export interface AuthorizedExportRows {
  readonly rows: readonly Readonly<Record<string, unknown>>[];
  readonly snapshot: ExportSourceSnapshot;
}

interface SourceRegistry {
  readonly allowedFilters: readonly string[];
  readonly allowedSources: readonly string[];
  readonly definitionKeys: readonly string[];
  readonly entity: "deal" | "inventory_unit" | "lead";
  readonly sourceKeys: readonly string[];
}

const INVENTORY_SOURCES = Object.freeze([
  "inventory_unit.stock_number",
  "inventory_unit.workflow_state",
  "inventory_unit.acquired_at",
  "inventory_unit.advertised_price_minor",
  "inventory_unit.currency_code",
  "vehicle.display_name",
  "vehicle.vin",
  "vehicle.model_year",
  "vehicle.make",
  "vehicle.model",
  "metrics.days_in_stock",
  "metrics.aging_bucket",
  "metrics.total_cost_minor",
  "metrics.estimated_gross_minor",
]);

const REGISTRIES: readonly SourceRegistry[] = Object.freeze([
  Object.freeze({
    allowedFilters: Object.freeze([
      "include_archived",
      "location_id",
      "states",
      "acquired_before",
    ]),
    allowedSources: INVENTORY_SOURCES,
    definitionKeys: Object.freeze([
      "inventory_summary",
      "inventory_aging",
      "inventory_gross",
    ]),
    entity: "inventory_unit",
    sourceKeys: Object.freeze([
      "inventory",
      "inventory_unit",
      "inventory_summary",
      "inventory_aging",
      "inventory_gross",
    ]),
  }),
  Object.freeze({
    allowedFilters: Object.freeze([
      "statuses",
      "assignee_id",
      "created_from",
      "created_to",
    ]),
    allowedSources: Object.freeze([
      "lead.reference",
      "lead.status",
      "lead.source",
      "lead.assignee_name",
      "lead.created_at",
    ]),
    definitionKeys: Object.freeze(["leads"]),
    entity: "lead",
    sourceKeys: Object.freeze(["lead", "leads"]),
  }),
  Object.freeze({
    allowedFilters: Object.freeze([
      "workflow_states",
      "deal_type_keys",
      "updated_from",
      "updated_to",
    ]),
    allowedSources: Object.freeze([
      "deal.reference",
      "deal.deal_type",
      "deal.workflow_state",
      "deal.total_minor",
      "deal.currency_code",
      "deal.updated_at",
    ]),
    definitionKeys: Object.freeze(["deals"]),
    entity: "deal",
    sourceKeys: Object.freeze(["deal", "deals"]),
  }),
]);

const ALLOWED_EXPORT_PERMISSIONS = Object.freeze([
  "exports.run",
  "exports.run_sensitive",
  "reports.read",
  "inventory.read_internal",
]);

function registryFor(source: ExportExecutionSource): SourceRegistry {
  const registry = REGISTRIES.find(
    (candidate) =>
      candidate.sourceKeys.includes(source.sourceKey) &&
      candidate.definitionKeys.includes(source.definitionKey),
  );
  if (registry === undefined) {
    throw new JobExecutionError({
      classification: "permanent",
      code: "export.source_not_registered",
      safeDetail: "The export source is not registered in the worker.",
    });
  }
  return registry;
}

export function compileAuthorizedExportDefinition(
  source: ExportExecutionSource,
): CompiledExportDefinition {
  const registry = registryFor(source);
  const availableFilters = Object.keys(source.filters).sort();
  const compiled = compileExportDefinition(
    {
      schema_version: "1.1",
      export: {
        available_filters: availableFilters,
        columns: source.authorizedColumnPlan,
        entity: registry.entity,
        formats: [source.requestedFormat],
        key: source.definitionKey,
        labels: { en: source.definitionKey, fr: source.definitionKey },
        security: { audit_required: true, links_expire: true },
        version: source.semanticVersion,
      },
    },
    {
      allowedFiltersByEntity: {
        [registry.entity]: registry.allowedFilters,
      },
      allowedPermissions: ALLOWED_EXPORT_PERMISSIONS,
      allowedSourcesByEntity: {
        [registry.entity]: registry.allowedSources,
      },
      maxRows: source.maximumRows,
    },
  );
  // The database checksum is bound to the immutable approved version record;
  // the synthetic wrapper above exists only to validate its authorized plan.
  return Object.freeze({
    ...compiled,
    definitionChecksum: source.definitionChecksum,
  });
}

function optionalString(value: unknown, label: string): string | null {
  if (value === null || value === undefined) return null;
  return requireString(value, "export", label, 2_000);
}

function sourceRowId(value: unknown, label: string): string {
  const id = requireString(value, "export", label, 36);
  if (!UUID_PATTERN.test(id)) throw invalidM4Contract("export", label);
  return id;
}

function safeInteger(value: unknown, label: string): number | null {
  if (value === null || value === undefined) return null;
  if (!Number.isSafeInteger(value)) throw invalidM4Contract("export", label);
  return value as number;
}

function minorUnits(value: unknown, label: string): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string" || !/^-?(?:0|[1-9][0-9]{0,18})$/u.test(value)) {
    throw invalidM4Contract("export", label);
  }
  return value;
}

function relation(value: unknown, label: string): Record<string, unknown>;
function relation(
  value: unknown,
  label: string,
  nullable: true,
): Record<string, unknown> | null;
function relation(
  value: unknown,
  label: string,
  nullable = false,
): Record<string, unknown> | null {
  if (value === null && nullable) return null;
  if (Array.isArray(value)) {
    if (value.length === 0 && nullable) return null;
    if (value.length !== 1) throw invalidM4Contract("export", label);
    return requireRecord(value[0], "export", label);
  }
  return requireRecord(value, "export", label);
}

function booleanFilter(
  value: unknown,
  label: string,
  fallback: boolean,
): boolean {
  if (value === undefined) return fallback;
  if (typeof value !== "boolean") throw invalidM4Contract("export", label);
  return value;
}

function stringFilter(value: unknown, label: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  return requireString(value, "export", label, 200);
}

function stringArrayFilter(
  value: unknown,
  label: string,
): readonly string[] | undefined {
  if (value === undefined || value === null) return undefined;
  const values = requireArray(value, "export", label).map((item, index) =>
    requireString(item, "export", `${label}_${index}`, 200),
  );
  if (values.length > 100 || new Set(values).size !== values.length) {
    throw invalidM4Contract("export", label);
  }
  return values;
}

function inFilter(values: readonly string[]): string {
  if (values.some((value) => !/^[A-Za-z0-9_.-]{1,200}$/u.test(value))) {
    throw invalidM4Contract("export", "filter_value");
  }
  return `in.(${values.join(",")})`;
}

function dateOnly(value: unknown, label: string): string | undefined {
  const parsed = stringFilter(value, label);
  if (parsed === undefined) return undefined;
  if (
    !/^\d{4}-\d{2}-\d{2}$/u.test(parsed) ||
    Number.isNaN(Date.parse(`${parsed}T00:00:00Z`))
  ) {
    throw invalidM4Contract("export", label);
  }
  return parsed;
}

function instant(value: unknown, label: string): string | undefined {
  const parsed = stringFilter(value, label);
  if (parsed === undefined) return undefined;
  const timestamp = Date.parse(parsed);
  if (!Number.isFinite(timestamp)) throw invalidM4Contract("export", label);
  return new Date(timestamp).toISOString();
}

function inventoryQuery(
  source: ExportExecutionSource,
): Omit<
  ExportSourceReadRequest,
  "exportRunId" | "jobId" | "leaseToken" | "signal" | "workerId" | "workspaceId"
> {
  const states = stringArrayFilter(source.filters.states, "states");
  const locationId = stringFilter(source.filters.location_id, "location_id");
  if (locationId !== undefined && !UUID_PATTERN.test(locationId)) {
    throw invalidM4Contract("export", "location_id");
  }
  const acquiredBefore = dateOnly(
    source.filters.acquired_before,
    "acquired_before",
  );
  return {
    filters: Object.freeze({
      ...(booleanFilter(
        source.filters.include_archived,
        "include_archived",
        false,
      )
        ? {}
        : { status: "neq.archived" }),
      ...(locationId === undefined ? {} : { location_id: `eq.${locationId}` }),
      ...(states === undefined ? {} : { workflow_state_key: inFilter(states) }),
      ...(acquiredBefore === undefined
        ? {}
        : { acquisition_date: `lte.${acquiredBefore}` }),
    }),
    maximumRows: source.maximumRows,
    select:
      "id,stock_number,status,acquisition_date,acquired_at,workflow_state_key,currency_code,advertised_price_minor,vehicle:vehicles(vin,model_year,make,model),metrics:inventory_cost_metrics(posted_cost_minor,estimated_gross_minor)",
    table: "inventory_units",
  };
}

function leadQuery(
  source: ExportExecutionSource,
): Omit<
  ExportSourceReadRequest,
  "exportRunId" | "jobId" | "leaseToken" | "signal" | "workerId" | "workspaceId"
> {
  const statuses = stringArrayFilter(source.filters.statuses, "statuses");
  const assigneeId = stringFilter(source.filters.assignee_id, "assignee_id");
  if (assigneeId !== undefined && !UUID_PATTERN.test(assigneeId)) {
    throw invalidM4Contract("export", "assignee_id");
  }
  const createdFrom = instant(source.filters.created_from, "created_from");
  const createdTo = instant(source.filters.created_to, "created_to");
  const createdBounds = [
    ...(createdFrom === undefined ? [] : [`created_at.gte.${createdFrom}`]),
    ...(createdTo === undefined ? [] : [`created_at.lte.${createdTo}`]),
  ];
  return {
    filters: Object.freeze({
      ...(statuses === undefined ? {} : { state_key: inFilter(statuses) }),
      ...(assigneeId === undefined
        ? {}
        : { assignee_membership_id: `eq.${assigneeId}` }),
      ...(createdBounds.length === 0
        ? {}
        : { and: `(${createdBounds.join(",")})` }),
    }),
    maximumRows: source.maximumRows,
    select: "id,state_key,source_key,created_at,assignee_membership_id",
    table: "leads",
  };
}

function dealQuery(
  source: ExportExecutionSource,
): Omit<
  ExportSourceReadRequest,
  "exportRunId" | "jobId" | "leaseToken" | "signal" | "workerId" | "workspaceId"
> {
  const states = stringArrayFilter(
    source.filters.workflow_states,
    "workflow_states",
  );
  const dealTypes = stringArrayFilter(
    source.filters.deal_type_keys,
    "deal_type_keys",
  );
  const updatedFrom = instant(source.filters.updated_from, "updated_from");
  const updatedTo = instant(source.filters.updated_to, "updated_to");
  const updatedBounds = [
    ...(updatedFrom === undefined ? [] : [`updated_at.gte.${updatedFrom}`]),
    ...(updatedTo === undefined ? [] : [`updated_at.lte.${updatedTo}`]),
  ];
  return {
    filters: Object.freeze({
      ...(states === undefined ? {} : { workflow_state_key: inFilter(states) }),
      ...(dealTypes === undefined
        ? {}
        : { deal_type_key: inFilter(dealTypes) }),
      ...(updatedBounds.length === 0
        ? {}
        : { and: `(${updatedBounds.join(",")})` }),
    }),
    maximumRows: source.maximumRows,
    select:
      "id,deal_type_key,status,workflow_state_key,currency_code,updated_at,line_items:deal_line_items(unit_amount_minor,quantity_text,currency_code,status)",
    table: "deals",
  };
}

function displayName(vehicle: Record<string, unknown>): string {
  const values = [
    safeInteger(vehicle.model_year, "vehicle_model_year"),
    optionalString(vehicle.make, "vehicle_make"),
    optionalString(vehicle.model, "vehicle_model"),
  ].filter((value): value is string | number => value !== null);
  const result = values.join(" ").trim();
  return result || requireString(vehicle.vin, "export", "vehicle_vin", 17);
}

function acquisitionDate(row: Record<string, unknown>): string | null {
  const date = optionalString(row.acquisition_date, "acquisition_date");
  if (date !== null) return date;
  return optionalString(row.acquired_at, "acquired_at")?.slice(0, 10) ?? null;
}

function daysBetween(from: string | null, through: string): number {
  if (from === null) return 0;
  const fromMs = Date.parse(`${from}T00:00:00Z`);
  const throughMs = Date.parse(`${through.slice(0, 10)}T00:00:00Z`);
  if (!Number.isFinite(fromMs) || !Number.isFinite(throughMs)) {
    throw invalidM4Contract("export", "aging_date");
  }
  return Math.max(0, Math.floor((throughMs - fromMs) / 86_400_000));
}

function agingBucket(days: number): string {
  if (days < 30) return "0-29";
  if (days < 60) return "30-59";
  if (days < 90) return "60-89";
  return "90+";
}

function projectInventory(
  rows: readonly Record<string, unknown>[],
  capturedAt: string,
): readonly Readonly<Record<string, unknown>>[] {
  return rows.map((row) => {
    const vehicle = relation(row.vehicle, "vehicle_relation");
    const metrics = relation(row.metrics, "metrics_relation", true);
    const acquiredAt = acquisitionDate(row);
    const days = daysBetween(acquiredAt, capturedAt);
    return Object.freeze({
      __vynlo_source_id: sourceRowId(row.id, "inventory_id"),
      inventory_unit: Object.freeze({
        acquired_at: acquiredAt,
        advertised_price_minor: minorUnits(
          row.advertised_price_minor,
          "advertised_price_minor",
        ),
        currency_code: requireString(
          row.currency_code,
          "export",
          "inventory_currency_code",
          3,
        ),
        stock_number: requireString(
          row.stock_number,
          "export",
          "stock_number",
          200,
        ),
        workflow_state:
          optionalString(row.workflow_state_key, "inventory_workflow_state") ??
          requireString(row.status, "export", "inventory_status", 50),
      }),
      metrics: Object.freeze({
        aging_bucket: agingBucket(days),
        days_in_stock: days,
        estimated_gross_minor:
          metrics === null
            ? null
            : minorUnits(
                metrics.estimated_gross_minor,
                "estimated_gross_minor",
              ),
        total_cost_minor:
          metrics === null
            ? "0"
            : (minorUnits(metrics.posted_cost_minor, "posted_cost_minor") ??
              "0"),
      }),
      vehicle: Object.freeze({
        display_name: displayName(vehicle),
        make: optionalString(vehicle.make, "vehicle_make"),
        model: optionalString(vehicle.model, "vehicle_model"),
        model_year: safeInteger(vehicle.model_year, "vehicle_model_year"),
        vin: requireString(vehicle.vin, "export", "vehicle_vin", 17),
      }),
    });
  });
}

function projectLeads(
  rows: readonly Record<string, unknown>[],
): readonly Readonly<Record<string, unknown>>[] {
  return rows.map((row) => {
    const membershipId = optionalString(
      row.assignee_membership_id,
      "lead_assignee_membership_id",
    );
    if (membershipId !== null && !UUID_PATTERN.test(membershipId)) {
      throw invalidM4Contract("export", "lead_assignee_membership_id");
    }
    return Object.freeze({
      __vynlo_source_id: sourceRowId(row.id, "lead_id"),
      lead: Object.freeze({
        assignee_name:
          membershipId === null
            ? null
            : optionalString(row.assignee_name, "lead_assignee_name"),
        created_at: requireString(
          row.created_at,
          "export",
          "lead_created_at",
          50,
        ),
        reference: requireString(row.id, "export", "lead_id", 36),
        source: optionalString(row.source_key, "lead_source"),
        status: requireString(row.state_key, "export", "lead_status", 200),
      }),
    });
  });
}

function roundedLineTotal(unitMinor: string, quantity: string): bigint {
  if (!/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/u.test(quantity)) {
    throw invalidM4Contract("export", "deal_line_quantity");
  }
  const [whole = "0", fraction = ""] = quantity.split(".");
  const scale = 1_000_000n;
  const scaledQuantity =
    BigInt(whole) * scale + BigInt(fraction.padEnd(6, "0"));
  const numerator = BigInt(unitMinor) * scaledQuantity;
  const negative = numerator < 0n;
  const absolute = negative ? -numerator : numerator;
  const rounded = (absolute + scale / 2n) / scale;
  return negative ? -rounded : rounded;
}

function dealTotal(lineItems: unknown, currencyCode: string): string | null {
  const values = requireArray(lineItems ?? [], "export", "deal_line_items");
  let total = 0n;
  let active = 0;
  for (const [index, value] of values.entries()) {
    const line = requireRecord(value, "export", `deal_line_item_${index}`);
    if (line.status !== "active") continue;
    const lineCurrency = requireString(
      line.currency_code,
      "export",
      "deal_line_currency",
      3,
    );
    if (lineCurrency !== currencyCode) {
      throw invalidM4Contract("export", "deal_line_currency_mismatch");
    }
    total += roundedLineTotal(
      minorUnits(line.unit_amount_minor, "deal_line_unit_minor") ?? "0",
      requireString(line.quantity_text, "export", "deal_line_quantity", 30),
    );
    active += 1;
  }
  return active === 0 ? null : total.toString();
}

function projectDeals(
  rows: readonly Record<string, unknown>[],
): readonly Readonly<Record<string, unknown>>[] {
  return rows.map((row) => {
    const currency = requireString(
      row.currency_code,
      "export",
      "deal_currency_code",
      3,
    );
    return Object.freeze({
      __vynlo_source_id: sourceRowId(row.id, "deal_id"),
      deal: Object.freeze({
        currency_code: currency,
        deal_type: requireString(row.deal_type_key, "export", "deal_type", 200),
        reference: requireString(row.id, "export", "deal_id", 36),
        total_minor: dealTotal(row.line_items, currency),
        updated_at: requireString(
          row.updated_at,
          "export",
          "deal_updated_at",
          50,
        ),
        workflow_state:
          optionalString(row.workflow_state_key, "deal_workflow_state") ??
          requireString(row.status, "export", "deal_status", 50),
      }),
    });
  });
}

function valueAt(
  row: Readonly<Record<string, unknown>>,
  source: string,
): unknown {
  let value: unknown = row;
  for (const segment of source.split(".")) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return null;
    }
    value = (value as Readonly<Record<string, unknown>>)[segment];
  }
  return value ?? null;
}

function compareValues(left: unknown, right: unknown): number {
  if (left === right) return 0;
  if (left === null) return 1;
  if (right === null) return -1;
  if (typeof left === "number" && typeof right === "number")
    return left - right;
  if (
    typeof left === "string" &&
    typeof right === "string" &&
    /^-?\d+$/u.test(left) &&
    /^-?\d+$/u.test(right)
  ) {
    const leftBig = BigInt(left);
    const rightBig = BigInt(right);
    return leftBig < rightBig ? -1 : leftBig > rightBig ? 1 : 0;
  }
  const leftText = String(left);
  const rightText = String(right);
  return leftText < rightText ? -1 : leftText > rightText ? 1 : 0;
}

function sortRows(
  rows: readonly Readonly<Record<string, unknown>>[],
  source: ExportExecutionSource,
  definition: CompiledExportDefinition,
  registry: SourceRegistry,
): readonly Readonly<Record<string, unknown>>[] {
  const columns = definition.columns ?? [];
  const columnSourceByKey = new Map(
    columns.map((column) => [column.key, column.source]),
  );
  const authorizedSources = new Set(columnSourceByKey.values());
  if (
    source.sortSpecification.length < 2 ||
    source.sortSpecification.length > 101
  ) {
    throw invalidM4Contract("export", "sort_specification");
  }
  const specifications = source.sortSpecification.map((item, index) => {
    const record = requireRecord(item, "export", `sort_${index}`);
    const direction = record.direction;
    if (direction !== "asc" && direction !== "desc") {
      throw invalidM4Contract("export", "sort_direction");
    }
    const isTieBreaker = index === source.sortSpecification.length - 1;
    if (isTieBreaker) {
      if (
        Object.keys(record).sort().join(",") !== "direction,opaque,source" ||
        record.direction !== "asc" ||
        record.opaque !== true ||
        record.source !== "__vynlo_source_id"
      ) {
        throw invalidM4Contract("export", "sort_tie_breaker");
      }
      return Object.freeze({
        direction: "asc" as const,
        source: record.source,
      });
    }
    if (Object.keys(record).sort().join(",") !== "direction,source") {
      throw invalidM4Contract("export", "sort_specification");
    }
    const requestedSource = requireString(
      record.source,
      "export",
      "sort_source",
      193,
    );
    if (
      !registry.allowedSources.includes(requestedSource) ||
      !authorizedSources.has(requestedSource)
    ) {
      throw invalidM4Contract("export", "sort_source");
    }
    return Object.freeze({ direction, source: requestedSource });
  });
  return Object.freeze(
    [...rows]
      .sort((left, right) => {
        for (const specification of specifications) {
          const compared = compareValues(
            valueAt(left, specification.source),
            valueAt(right, specification.source),
          );
          if (compared !== 0) {
            return specification.direction === "asc" ? compared : -compared;
          }
        }
        return compareValues(
          valueAt(left, "__vynlo_source_id"),
          valueAt(right, "__vynlo_source_id"),
        );
      })
      .map((row) => {
        const { __vynlo_source_id: _sourceId, ...exportRow } = row;
        void _sourceId;
        return Object.freeze(exportRow);
      }),
  );
}

export async function readAuthorizedExportRows(input: {
  readonly definition: CompiledExportDefinition;
  readonly exportRunId: string;
  readonly jobId: string;
  readonly leaseToken: string;
  readonly reader: ExportSourceReader;
  readonly signal: AbortSignal;
  readonly source: ExportExecutionSource;
  readonly workerId: string;
  readonly workspaceId: string;
}): Promise<AuthorizedExportRows> {
  const registry = registryFor(input.source);
  const request =
    registry.entity === "inventory_unit"
      ? inventoryQuery(input.source)
      : registry.entity === "lead"
        ? leadQuery(input.source)
        : dealQuery(input.source);
  const snapshotRead = await input.reader.read({
    ...request,
    exportRunId: input.exportRunId,
    jobId: input.jobId,
    leaseToken: input.leaseToken,
    signal: input.signal,
    workerId: input.workerId,
    workspaceId: input.workspaceId,
  });
  if (snapshotRead.snapshot.rowCount > input.source.maximumRows) {
    throw new JobExecutionError({
      classification: "validation",
      code: "export.row_limit_exceeded",
      safeDetail: "The export source exceeded its approved row limit.",
    });
  }
  const raw = snapshotRead.rows;
  if (raw.length !== snapshotRead.snapshot.rowCount) {
    throw invalidM4Contract("export", "source_snapshot_row_count");
  }
  const projected =
    registry.entity === "inventory_unit"
      ? projectInventory(raw, snapshotRead.snapshot.capturedAt)
      : registry.entity === "lead"
        ? projectLeads(raw)
        : projectDeals(raw);
  return Object.freeze({
    rows: sortRows(projected, input.source, input.definition, registry),
    snapshot: snapshotRead.snapshot,
  });
}
