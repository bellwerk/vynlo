// Stable test IDs: T-EXP-001, T-EXP-002, T-JOB-003, T-STOR-001.
import { describe, expect, it, vi } from "vitest";

import {
  createExportGenerationJobHandler,
  type ExportRunRepository,
} from "./export-handler";
import type { ImmutableArtifactStorage } from "./immutable-artifact-storage";
import type { ClaimedJob } from "./job-store";

const ids = {
  correlation: "20000000-0000-4000-8000-000000000001",
  exportFile: "20000000-0000-4000-8000-000000000002",
  exportRun: "20000000-0000-4000-8000-000000000003",
  exportVersion: "20000000-0000-4000-8000-000000000004",
  job: "20000000-0000-4000-8000-000000000005",
  lease: "20000000-0000-4000-8000-000000000006",
  outbox: "20000000-0000-4000-8000-000000000007",
  workspace: "20000000-0000-4000-8000-000000000008",
  snapshot: "20000000-0000-4000-8000-000000000009",
} as const;

const loadedExport = {
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
  definitionChecksum: "c".repeat(64),
  definitionKey: "leads",
  expiresAt: "2026-07-16T19:00:00.000Z",
  exportRunId: ids.exportRun,
  filters: {},
  locale: "fr-CA",
  maximumRows: 100,
  requestedFormat: "csv" as const,
  semanticVersion: "1.0.0",
  sortSpecification: [
    { direction: "asc", source: "lead.reference" },
    {
      direction: "asc",
      opaque: true,
      source: "__vynlo_source_id",
    },
  ],
  sourceKey: "lead",
  completion: null,
} as const;

function job(): ClaimedJob {
  return {
    attemptNumber: 1,
    causationId: null,
    correlationId: ids.correlation,
    entityId: ids.exportRun,
    entityType: "export_run",
    idempotencyKey: "export:request-0001",
    jobId: ids.job,
    jobType: "exports.generate",
    leaseExpiresAt: "2026-07-16T18:00:00.000Z",
    leaseToken: ids.lease,
    maximumAttempts: 5,
    outboxEventId: ids.outbox,
    payload: {
      column_plan_checksum: "a".repeat(64),
      export_run_id: ids.exportRun,
      export_version_id: ids.exportVersion,
      filters_checksum: "b".repeat(64),
      format: "csv",
      locale: "fr-CA",
      sort_plan_checksum: "f".repeat(64),
      source_key: "lead",
    },
    payloadSchemaVersion: 1,
    workspaceId: ids.workspace,
  };
}

function dependencies() {
  const exports: ExportRunRepository = {
    complete: vi.fn().mockResolvedValue({
      exportFileId: ids.exportFile,
      replayed: false,
      rowCount: 1,
    }),
    load: vi.fn().mockResolvedValue(loadedExport),
    read: vi.fn().mockResolvedValue({
      rows: [
        {
          assignee_membership_id: null,
          created_at: "2026-07-16T12:00:00.000Z",
          id: "20000000-0000-4000-8000-000000000010",
          source_key: "website",
          state_key: "new",
          workspace_id: ids.workspace,
        },
      ],
      snapshot: {
        capturedAt: "2026-07-16T12:00:00.000Z",
        fingerprint: "e".repeat(64),
        id: ids.snapshot,
        rowCount: 1,
      },
    }),
    recordFailure: vi.fn().mockResolvedValue(undefined),
  };
  const storage: ImmutableArtifactStorage = {
    put: vi.fn(async (write) => ({
      bucket: "exports-private",
      byteSize: write.body.byteLength,
      checksum: write.checksum,
      contentType: write.contentType,
      generation: '"export-generation-1"',
      objectPath: write.objectPath,
    })),
  };
  return { exports, storage };
}

describe("M4 exports.generate handler", () => {
  it("rejects a job that omits the immutable sort-plan checksum", async () => {
    const { exports, storage } = dependencies();
    const handler = createExportGenerationJobHandler({
      exports,
      storage,
      workerId: "worker-m4-1",
    });
    const invalidJob = job();
    const { sort_plan_checksum: _sortPlanChecksum, ...payload } =
      invalidJob.payload as Record<string, unknown>;
    void _sortPlanChecksum;
    await expect(
      handler(
        { ...invalidJob, payload },
        { signal: new AbortController().signal },
      ),
    ).rejects.toMatchObject({ code: "export.invalid_job_payload_keys" });
    expect(exports.load).not.toHaveBeenCalled();
    expect(storage.put).not.toHaveBeenCalled();
  });

  it("generates localized deterministic CSV and persists the authorized receipt", async () => {
    const { exports, storage } = dependencies();
    const handler = createExportGenerationJobHandler({
      exports,
      storage,
      workerId: "worker-m4-1",
    });
    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).resolves.toMatchObject({
      summary: {
        export_file_id: ids.exportFile,
        export_run_id: ids.exportRun,
        format: "csv",
        row_count: 1,
      },
    });
    const write = vi.mocked(storage.put).mock.calls[0]?.[0];
    expect(write?.contentType).toBe("text/csv; charset=utf-8");
    expect(new TextDecoder().decode(write!.body)).toContain('"Référence"');
    expect(exports.complete).toHaveBeenCalledWith(
      expect.objectContaining({
        receipt: {
          columnPlanChecksum: "a".repeat(64),
          exportVersionId: ids.exportVersion,
          filtersChecksum: "b".repeat(64),
          sortPlanChecksum: "f".repeat(64),
          sourceSnapshotCapturedAt: "2026-07-16T12:00:00.000Z",
          sourceSnapshotFingerprint: "e".repeat(64),
          sourceSnapshotId: ids.snapshot,
          sourceSnapshotRowCount: 1,
          storage: expect.objectContaining({
            bucket: "exports-private",
            generation: '"export-generation-1"',
          }),
        },
        rowCount: 1,
      }),
    );
    expect(exports.recordFailure).not.toHaveBeenCalled();
  });

  it("generates the same authorized row set as genuine Open XML XLSX", async () => {
    const { exports, storage } = dependencies();
    vi.mocked(exports.load).mockResolvedValueOnce({
      ...loadedExport,
      requestedFormat: "xlsx",
    });
    const handler = createExportGenerationJobHandler({
      exports,
      storage,
      workerId: "worker-m4-1",
    });

    await expect(
      handler(
        { ...job(), payload: { ...job().payload, format: "xlsx" } },
        { signal: new AbortController().signal },
      ),
    ).resolves.toMatchObject({
      summary: { format: "xlsx", row_count: 1 },
    });
    const write = vi.mocked(storage.put).mock.calls[0]?.[0];
    expect(write?.contentType).toBe(
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    );
    expect(new TextDecoder().decode(write!.body.subarray(0, 2))).toBe("PK");
    expect(exports.complete).toHaveBeenCalledWith(
      expect.objectContaining({ rowCount: 1 }),
    );
  });

  it("records source failure evidence and rethrows for runner settlement", async () => {
    const { exports, storage } = dependencies();
    vi.mocked(exports.load).mockResolvedValueOnce({
      ...loadedExport,
      sourceKey: "unregistered_source",
    });
    const handler = createExportGenerationJobHandler({
      exports,
      storage,
      workerId: "worker-m4-1",
    });
    await expect(
      handler(
        {
          ...job(),
          payload: { ...job().payload, source_key: "unregistered_source" },
        },
        { signal: new AbortController().signal },
      ),
    ).rejects.toMatchObject({ code: "export.source_not_registered" });
    expect(exports.recordFailure).toHaveBeenCalledWith(
      expect.objectContaining({
        errorCode: "export.source_not_registered",
        exportRunId: ids.exportRun,
      }),
    );
    expect(exports.complete).not.toHaveBeenCalled();
  });

  it("replays a committed export completion without rereading mutable rows", async () => {
    const { exports, storage } = dependencies();
    vi.mocked(exports.load).mockResolvedValueOnce({
      ...loadedExport,
      completion: {
        artifactChecksum: "d".repeat(64),
        byteSize: 512,
        exportFileId: ids.exportFile,
        rowCount: 7,
      },
    });
    const handler = createExportGenerationJobHandler({
      exports,
      storage,
      workerId: "worker-m4-1",
    });

    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).resolves.toMatchObject({
      summary: {
        export_file_id: ids.exportFile,
        replayed: true,
        row_count: 7,
      },
    });
    expect(exports.read).not.toHaveBeenCalled();
    expect(storage.put).not.toHaveBeenCalled();
    expect(exports.complete).not.toHaveBeenCalled();
  });
});
