// Stable test IDs: T-EXP-001, T-EXP-002, T-JOB-003, T-TEN-001.
import { describe, expect, it, vi } from "vitest";

import { PostgrestExportRunRepository } from "./export-repository";

const id = (suffix: string) =>
  `30000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

describe("M4 export worker repository", () => {
  it("loads immutable run metadata through the active lease RPC", async () => {
    const fetchImplementation = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          authorized_column_plan: [
            {
              format: "text",
              key: "reference",
              labels: { en: "Reference", fr: "Référence" },
              source: "lead.reference",
            },
          ],
          completed_byte_size: null,
          completed_checksum: null,
          completed_file_id: null,
          completed_row_count: null,
          definition_checksum: "a".repeat(64),
          definition_key: "leads",
          expires_at: "2026-07-16T19:00:00.000Z",
          export_run_id: id("1"),
          filters: {},
          locale: "en-CA",
          maximum_rows: 100,
          requested_format: "csv",
          semantic_version: "1.0.0",
          sort_specification: [
            { direction: "asc", source: "lead.reference" },
            {
              direction: "asc",
              opaque: true,
              source: "__vynlo_source_id",
            },
          ],
          source_key: "lead",
        },
      ]),
    );
    const repository = new PostgrestExportRunRepository({
      fetchImplementation,
      serviceRoleKey: "x".repeat(32),
      supabaseUrl: "http://127.0.0.1:54321",
    });
    await expect(
      repository.load({
        exportRunId: id("1"),
        jobId: id("2"),
        leaseToken: id("3"),
        signal: new AbortController().signal,
        workerId: "worker-m4-1",
        workspaceId: id("4"),
      }),
    ).resolves.toMatchObject({
      definitionKey: "leads",
      exportRunId: id("1"),
      requestedFormat: "csv",
      sourceKey: "lead",
      completion: null,
    });
    expect(String(fetchImplementation.mock.calls[0]?.[0])).toContain(
      "/rest/v1/rpc/m4_load_export_run",
    );
  });

  it("lease-verifies failure without settling the durable job", async () => {
    const fetchImplementation = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          job_status: "running",
          retry_at: null,
          review_required: false,
          run_status: "running",
        },
      ]),
    );
    const repository = new PostgrestExportRunRepository({
      fetchImplementation,
      serviceRoleKey: "x".repeat(32),
      supabaseUrl: "http://127.0.0.1:54321",
    });

    await repository.recordFailure({
      classification: "transient",
      correlationId: id("5"),
      errorCode: "export.source_transport_failed",
      errorDetailSafe: "The registered export source query did not complete.",
      exportRunId: id("1"),
      jobId: id("2"),
      leaseToken: id("3"),
      requestId: `job:${id("2")}:failure`,
      signal: new AbortController().signal,
      workerId: "worker-m4-1",
      workspaceId: id("4"),
    });

    const body = JSON.parse(
      String((fetchImplementation.mock.calls[0]?.[1] as RequestInit).body),
    ) as Record<string, unknown>;
    expect(body).not.toHaveProperty("p_job_status");
    expect(body).toMatchObject({
      p_error_classification: "transient",
      p_job_id: id("2"),
    });
  });

  it("pages one immutable snapshot and preserves PostgreSQL bigint money as text", async () => {
    const fetchImplementation = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          next_ordinal: 1,
          snapshot_captured_at: "2026-07-16T12:00:00.000Z",
          source_row_count: 1,
          source_rows: [
            {
              advertised_price_minor: "9007199254740993",
              id: id("5"),
              workspace_id: id("4"),
            },
          ],
          source_snapshot_fingerprint: "b".repeat(64),
          source_snapshot_id: id("6"),
        },
      ]),
    );
    const repository = new PostgrestExportRunRepository({
      fetchImplementation,
      serviceRoleKey: "x".repeat(32),
      supabaseUrl: "http://127.0.0.1:54321",
    });
    await expect(
      repository.read({
        exportRunId: id("1"),
        filters: {},
        jobId: id("2"),
        leaseToken: id("3"),
        maximumRows: 10,
        select: "id,advertised_price_minor",
        signal: new AbortController().signal,
        table: "inventory_units",
        workerId: "worker-m4-1",
        workspaceId: id("4"),
      }),
    ).resolves.toMatchObject({
      rows: [{ advertised_price_minor: "9007199254740993" }],
      snapshot: { id: id("6"), rowCount: 1 },
    });
    const url = String(fetchImplementation.mock.calls[0]?.[0]);
    expect(url).toContain("/rest/v1/rpc/m4_read_export_source_snapshot_page");
    const body = JSON.parse(
      String((fetchImplementation.mock.calls[0]?.[1] as RequestInit).body),
    ) as Record<string, unknown>;
    expect(body).toMatchObject({
      p_after_ordinal: 0,
      p_export_run_id: id("1"),
      p_job_id: id("2"),
      p_lease_token: id("3"),
      p_worker_id: "worker-m4-1",
      p_workspace_id: id("4"),
    });
  });
});
