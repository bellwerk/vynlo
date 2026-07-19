// Stable test IDs: T-EXP-001, T-EXP-002, T-TEN-001.
import { describe, expect, it, vi } from "vitest";

import {
  compileAuthorizedExportDefinition,
  readAuthorizedExportRows,
  type ExportExecutionSource,
  type ExportSourceReader,
} from "./export-source-registry";

const ids = {
  exportRun: "10000000-0000-4000-8000-000000000020",
  job: "10000000-0000-4000-8000-000000000021",
  lease: "10000000-0000-4000-8000-000000000022",
  snapshot: "10000000-0000-4000-8000-000000000023",
  workspace: "10000000-0000-4000-8000-000000000010",
} as const;

function snapshotRows(rows: readonly Record<string, unknown>[]) {
  return Object.freeze({
    rows,
    snapshot: Object.freeze({
      capturedAt: "2026-07-20T00:00:00.000Z",
      fingerprint: "f".repeat(64),
      id: ids.snapshot,
      rowCount: rows.length,
    }),
  });
}

function source(
  overrides: Partial<ExportExecutionSource> = {},
): ExportExecutionSource {
  return {
    authorizedColumnPlan: [
      {
        format: "text",
        key: "stock_number",
        labels: { en: "Stock number", fr: "Numéro de stock" },
        source: "inventory_unit.stock_number",
      },
      {
        format: "minor_units",
        key: "total_cost_minor",
        labels: { en: "Total cost", fr: "Coût total" },
        permission: "inventory.read_internal",
        sensitive: true,
        source: "metrics.total_cost_minor",
      },
      {
        format: "integer",
        key: "days_in_stock",
        labels: { en: "Days", fr: "Jours" },
        source: "metrics.days_in_stock",
      },
    ],
    definitionChecksum: "a".repeat(64),
    definitionKey: "inventory_aging",
    expiresAt: "2026-07-20T12:00:00.000Z",
    filters: { include_archived: false, states: ["available"] },
    locale: "en-CA",
    maximumRows: 100,
    requestedFormat: "csv",
    semanticVersion: "1.0.0",
    sortSpecification: [
      { direction: "asc", source: "inventory_unit.stock_number" },
      {
        direction: "asc",
        opaque: true,
        source: "__vynlo_source_id",
      },
    ],
    sourceKey: "inventory_unit",
    ...overrides,
  };
}

describe("M4 strict export source registry", () => {
  it("projects deterministic workspace inventory rows with exact minor units", async () => {
    const reader: ExportSourceReader = {
      read: vi.fn().mockResolvedValue(
        snapshotRows([
          {
            acquisition_date: "2026-07-01",
            acquired_at: null,
            advertised_price_minor: "2500000",
            currency_code: "CAD",
            id: "10000000-0000-4000-8000-000000000001",
            metrics: {
              estimated_gross_minor: "500000",
              posted_cost_minor: "2000000",
            },
            status: "active",
            stock_number: "STK-002",
            vehicle: {
              make: "Example",
              model: "Model",
              model_year: 2024,
              vin: "1HGCM82633A004352",
            },
            workflow_state_key: "available",
            workspace_id: "10000000-0000-4000-8000-000000000010",
          },
          {
            acquisition_date: "2026-07-10",
            acquired_at: null,
            advertised_price_minor: "1500000",
            currency_code: "CAD",
            id: "10000000-0000-4000-8000-000000000002",
            metrics: null,
            status: "active",
            stock_number: "STK-001",
            vehicle: {
              make: "Sample",
              model: "Car",
              model_year: 2023,
              vin: "1M8GDM9AXKP042788",
            },
            workflow_state_key: "available",
            workspace_id: "10000000-0000-4000-8000-000000000010",
          },
        ]),
      ),
    };
    const execution = source();
    const definition = compileAuthorizedExportDefinition(execution);
    const rows = await readAuthorizedExportRows({
      definition,
      exportRunId: ids.exportRun,
      jobId: ids.job,
      leaseToken: ids.lease,
      reader,
      signal: new AbortController().signal,
      source: execution,
      workerId: "worker-m4-1",
      workspaceId: ids.workspace,
    });
    expect(rows.rows).toHaveLength(2);
    expect(rows.rows[0]).toMatchObject({
      inventory_unit: { stock_number: "STK-001" },
      metrics: { days_in_stock: 10, total_cost_minor: "0" },
    });
    expect(rows.rows[1]).toMatchObject({
      inventory_unit: { stock_number: "STK-002" },
      metrics: { days_in_stock: 19, total_cost_minor: "2000000" },
    });
    expect(rows.rows[0]).not.toHaveProperty("__vynlo_source_id");
    expect(reader.read).toHaveBeenCalledWith(
      expect.objectContaining({
        filters: expect.objectContaining({
          status: "neq.archived",
          workflow_state_key: "in.(available)",
        }),
        table: "inventory_units",
        exportRunId: ids.exportRun,
        workspaceId: ids.workspace,
      }),
    );
  });

  it("derives deal totals using exact decimal arithmetic", async () => {
    const execution = source({
      authorizedColumnPlan: [
        {
          format: "minor_units",
          key: "total_minor",
          labels: { en: "Total", fr: "Total" },
          nullable: true,
          source: "deal.total_minor",
        },
      ],
      definitionKey: "deals",
      filters: {},
      sortSpecification: [
        { direction: "asc", source: "deal.total_minor" },
        {
          direction: "asc",
          opaque: true,
          source: "__vynlo_source_id",
        },
      ],
      sourceKey: "deal",
    });
    const reader: ExportSourceReader = {
      read: vi.fn().mockResolvedValue(
        snapshotRows([
          {
            currency_code: "CAD",
            deal_type_key: "retail",
            id: "10000000-0000-4000-8000-000000000003",
            line_items: [
              {
                currency_code: "CAD",
                quantity_text: "1.5",
                status: "active",
                unit_amount_minor: "9007199254740993",
              },
              {
                currency_code: "CAD",
                quantity_text: "1",
                status: "active",
                unit_amount_minor: "-50",
              },
            ],
            status: "active",
            updated_at: "2026-07-16T12:00:00.000Z",
            workflow_state_key: "draft",
            workspace_id: "10000000-0000-4000-8000-000000000010",
          },
        ]),
      ),
    };
    const definition = compileAuthorizedExportDefinition(execution);
    const rows = await readAuthorizedExportRows({
      definition,
      exportRunId: ids.exportRun,
      jobId: ids.job,
      leaseToken: ids.lease,
      reader,
      signal: new AbortController().signal,
      source: execution,
      workerId: "worker-m4-1",
      workspaceId: ids.workspace,
    });
    expect(rows.rows[0]).toMatchObject({
      deal: { total_minor: "13510798882111440" },
    });
  });

  it("honors the approved sort allowlist and appends the unique source ID tie-breaker", async () => {
    const execution = source({
      authorizedColumnPlan: [
        {
          format: "text",
          key: "reference",
          labels: { en: "Reference", fr: "Référence" },
          source: "lead.reference",
        },
        {
          format: "datetime",
          key: "created_at",
          labels: { en: "Created", fr: "Créé" },
          source: "lead.created_at",
        },
      ],
      definitionKey: "leads",
      filters: {},
      sortSpecification: [
        { direction: "desc", source: "lead.created_at" },
        {
          direction: "asc",
          opaque: true,
          source: "__vynlo_source_id",
        },
      ],
      sourceKey: "leads",
    });
    const reader: ExportSourceReader = {
      read: vi.fn().mockResolvedValue(
        snapshotRows([
          {
            assignee_membership_id: null,
            created_at: "2026-07-19T12:00:00.000Z",
            id: "10000000-0000-4000-8000-000000000032",
            source_key: "web",
            state_key: "new",
            workspace_id: ids.workspace,
          },
          {
            assignee_membership_id: null,
            created_at: "2026-07-20T12:00:00.000Z",
            id: "10000000-0000-4000-8000-000000000031",
            source_key: "web",
            state_key: "new",
            workspace_id: ids.workspace,
          },
          {
            assignee_membership_id: null,
            created_at: "2026-07-20T12:00:00.000Z",
            id: "10000000-0000-4000-8000-000000000030",
            source_key: "web",
            state_key: "new",
            workspace_id: ids.workspace,
          },
        ]),
      ),
    };
    const result = await readAuthorizedExportRows({
      definition: compileAuthorizedExportDefinition(execution),
      exportRunId: ids.exportRun,
      jobId: ids.job,
      leaseToken: ids.lease,
      reader,
      signal: new AbortController().signal,
      source: execution,
      workerId: "worker-m4-1",
      workspaceId: ids.workspace,
    });
    expect(
      result.rows.map((row) => valueAtForTest(row, "lead.reference")),
    ).toEqual([
      "10000000-0000-4000-8000-000000000030",
      "10000000-0000-4000-8000-000000000031",
      "10000000-0000-4000-8000-000000000032",
    ]);
  });

  it("rejects an unregistered source path before a table is addressed", async () => {
    const execution = source({
      authorizedColumnPlan: [
        {
          format: "text",
          key: "unsafe",
          labels: { en: "Unsafe", fr: "Non sûr" },
          source: "workspace.secret",
        },
      ],
    });
    expect(() => compileAuthorizedExportDefinition(execution)).toThrowError(
      /EXPORT_SOURCE_NOT_ALLOWED/u,
    );
  });

  it("rejects an allowlisted sort field that is absent from the authorized column plan", async () => {
    const execution = source({
      sortSpecification: [
        { direction: "desc", source: "inventory_unit.advertised_price_minor" },
        {
          direction: "asc",
          opaque: true,
          source: "__vynlo_source_id",
        },
      ],
    });
    await expect(
      readAuthorizedExportRows({
        definition: compileAuthorizedExportDefinition(execution),
        exportRunId: ids.exportRun,
        jobId: ids.job,
        leaseToken: ids.lease,
        reader: { read: vi.fn().mockResolvedValue(snapshotRows([])) },
        signal: new AbortController().signal,
        source: execution,
        workerId: "worker-m4-1",
        workspaceId: ids.workspace,
      }),
    ).rejects.toMatchObject({ code: "export.invalid_sort_source" });
  });

  it("rejects an absent or malformed opaque source-ID tie-breaker", async () => {
    const execution = source({
      sortSpecification: [
        { direction: "asc", source: "inventory_unit.stock_number" },
      ],
    });
    await expect(
      readAuthorizedExportRows({
        definition: compileAuthorizedExportDefinition(execution),
        exportRunId: ids.exportRun,
        jobId: ids.job,
        leaseToken: ids.lease,
        reader: { read: vi.fn().mockResolvedValue(snapshotRows([])) },
        signal: new AbortController().signal,
        source: execution,
        workerId: "worker-m4-1",
        workspaceId: ids.workspace,
      }),
    ).rejects.toMatchObject({ code: "export.invalid_sort_specification" });
  });
});

function valueAtForTest(
  row: Readonly<Record<string, unknown>>,
  path: string,
): unknown {
  return path
    .split(".")
    .reduce<unknown>(
      (value, key) =>
        typeof value === "object" && value !== null && !Array.isArray(value)
          ? (value as Readonly<Record<string, unknown>>)[key]
          : undefined,
      row,
    );
}
