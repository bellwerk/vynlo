import { JobExecutionError } from "./job-runner";
import type { ExportRunRepository } from "./export-handler";
import type { ExportSourceReadRequest } from "./export-source-registry";
import {
  classifyM4Response,
  invalidM4Contract,
  requireArray,
  requireChecksum,
  requireInteger,
  requireRecord,
  requireString,
  requireUuid,
  validatedSupabaseOrigin,
} from "./m4-worker-validation";

const PAGE_SIZE = 500;

export class PostgrestExportRunRepository implements ExportRunRepository {
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #publicHeaders: Readonly<Record<string, string>>;
  readonly #rpcHeaders: Readonly<Record<string, string>>;

  constructor(input: {
    readonly fetchImplementation?: typeof fetch;
    readonly serviceRoleKey: string;
    readonly supabaseUrl: string;
  }) {
    if (input.serviceRoleKey.trim().length < 20) {
      throw new TypeError("A server-only service role key is required.");
    }
    this.#baseUrl = validatedSupabaseOrigin(input.supabaseUrl);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#publicHeaders = Object.freeze({
      "Accept-Profile": "public",
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
    });
    this.#rpcHeaders = Object.freeze({
      ...this.#publicHeaders,
      "Content-Profile": "app",
      "Content-Type": "application/json",
    });
  }

  async load(
    input: Parameters<ExportRunRepository["load"]>[0],
  ): ReturnType<ExportRunRepository["load"]> {
    const row = await this.#single(
      "m4_load_export_run",
      {
        p_export_run_id: input.exportRunId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const format = row.requested_format;
    if (format !== "csv" && format !== "xlsx") {
      throw invalidM4Contract("export", "requested_format");
    }
    const expiresAt = requireString(row.expires_at, "export", "expires_at", 50);
    if (!Number.isFinite(Date.parse(expiresAt))) {
      throw invalidM4Contract("export", "expires_at");
    }
    const hasCompletion = row.completed_file_id !== null;
    if (
      hasCompletion !==
      (row.completed_checksum !== null &&
        row.completed_byte_size !== null &&
        row.completed_row_count !== null)
    ) {
      throw invalidM4Contract("export", "completion_replay_shape");
    }
    const source = {
      authorizedColumnPlan: requireArray(
        row.authorized_column_plan,
        "export",
        "authorized_column_plan",
      ),
      definitionChecksum: requireChecksum(
        row.definition_checksum,
        "export",
        "definition_checksum",
      ),
      definitionKey: requireString(
        row.definition_key,
        "export",
        "definition_key",
        96,
      ),
      expiresAt,
      exportRunId: requireUuid(row.export_run_id, "export", "export_run_id"),
      filters: requireRecord(row.filters, "export", "filters"),
      locale: requireString(row.locale, "export", "locale", 100),
      maximumRows: requireInteger(
        row.maximum_rows,
        "export",
        "maximum_rows",
        1,
        100_000,
      ),
      requestedFormat: format,
      semanticVersion: requireString(
        row.semantic_version,
        "export",
        "semantic_version",
        50,
      ),
      sortSpecification: requireArray(
        row.sort_specification,
        "export",
        "sort_specification",
      ),
      sourceKey: requireString(row.source_key, "export", "source_key", 96),
      completion: hasCompletion
        ? Object.freeze({
            artifactChecksum: requireChecksum(
              row.completed_checksum,
              "export",
              "completed_checksum",
            ),
            byteSize: requireInteger(
              row.completed_byte_size,
              "export",
              "completed_byte_size",
              1,
              104_857_600,
            ),
            exportFileId: requireUuid(
              row.completed_file_id,
              "export",
              "completed_file_id",
            ),
            rowCount: requireInteger(
              row.completed_row_count,
              "export",
              "completed_row_count",
              0,
              100_000,
            ),
          })
        : null,
    } as const;
    if (source.exportRunId !== input.exportRunId) {
      throw invalidM4Contract("export", "workspace_run_binding");
    }
    return Object.freeze(source);
  }

  async complete(
    input: Parameters<ExportRunRepository["complete"]>[0],
  ): ReturnType<ExportRunRepository["complete"]> {
    const row = await this.#single(
      "m4_complete_export_run",
      {
        p_byte_size: input.byteSize,
        p_checksum: input.artifactChecksum,
        p_correlation_id: input.correlationId,
        p_export_run_id: input.exportRunId,
        p_filename: input.filename,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_mime_type: input.mimeType,
        p_request_id: input.requestId,
        p_row_count: input.rowCount,
        p_storage_bucket: input.storageBucket,
        p_storage_generation: input.storageGeneration,
        p_storage_object_path: input.objectPath,
        p_verification_receipt: input.receipt,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    if (row.run_status !== "generated" || typeof row.replayed !== "boolean") {
      throw invalidM4Contract("export", "completion_state");
    }
    return Object.freeze({
      exportFileId: requireUuid(row.export_file_id, "export", "export_file_id"),
      replayed: row.replayed,
      rowCount: requireInteger(
        row.row_count,
        "export",
        "row_count",
        0,
        100_000,
      ),
    });
  }

  async recordFailure(
    input: Parameters<ExportRunRepository["recordFailure"]>[0],
  ): Promise<void> {
    const row = await this.#single(
      "m4_fail_export_run",
      {
        p_correlation_id: input.correlationId,
        p_error_classification: input.classification,
        p_error_code: input.errorCode,
        p_error_detail_safe: input.errorDetailSafe,
        p_export_run_id: input.exportRunId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_request_id: input.requestId,
        p_retry_after_seconds: input.retryAfterSeconds ?? null,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    if (row.run_status !== "running" || row.job_status !== "running") {
      throw invalidM4Contract("export", "failure_recording_state");
    }
  }

  async read(
    request: ExportSourceReadRequest,
  ): ReturnType<import("./export-source-registry").ExportSourceReader["read"]> {
    const rows: Record<string, unknown>[] = [];
    let afterOrdinal = 0;
    let snapshot:
      | Readonly<{
          capturedAt: string;
          fingerprint: string;
          id: string;
          rowCount: number;
        }>
      | undefined;
    while (snapshot === undefined || afterOrdinal < snapshot.rowCount) {
      const pageSize = Math.min(
        PAGE_SIZE,
        request.maximumRows + 1 - Math.min(rows.length, request.maximumRows),
      );
      const response = await this.#single(
        "m4_read_export_source_snapshot_page",
        {
          p_after_ordinal: afterOrdinal,
          p_export_run_id: request.exportRunId,
          p_job_id: request.jobId,
          p_lease_token: request.leaseToken,
          p_page_size: pageSize,
          p_worker_id: request.workerId,
          p_workspace_id: request.workspaceId,
        },
        request.signal,
      );
      const capturedAt = requireString(
        response.snapshot_captured_at,
        "export",
        "snapshot_captured_at",
        50,
      );
      if (!Number.isFinite(Date.parse(capturedAt))) {
        throw invalidM4Contract("export", "snapshot_captured_at");
      }
      const receivedSnapshot = Object.freeze({
        capturedAt,
        fingerprint: requireChecksum(
          response.source_snapshot_fingerprint,
          "export",
          "source_snapshot_fingerprint",
        ),
        id: requireUuid(
          response.source_snapshot_id,
          "export",
          "source_snapshot_id",
        ),
        rowCount: requireInteger(
          response.source_row_count,
          "export",
          "source_row_count",
          0,
          request.maximumRows + 1,
        ),
      });
      if (
        snapshot !== undefined &&
        (snapshot.id !== receivedSnapshot.id ||
          snapshot.capturedAt !== receivedSnapshot.capturedAt ||
          snapshot.fingerprint !== receivedSnapshot.fingerprint ||
          snapshot.rowCount !== receivedSnapshot.rowCount)
      ) {
        throw invalidM4Contract("export", "source_snapshot_changed");
      }
      snapshot = receivedSnapshot;
      const nextOrdinal = requireInteger(
        response.next_ordinal,
        "export",
        "snapshot_next_ordinal",
        afterOrdinal,
        snapshot.rowCount,
      );
      const page = requireArray(
        response.source_rows,
        "export",
        "source_page",
      ).map((item, index) => {
        const row = requireRecord(item, "export", `source_row_${index}`);
        if (row.workspace_id !== request.workspaceId) {
          throw invalidM4Contract("export", "source_workspace_binding");
        }
        return row;
      });
      if (
        page.length > pageSize ||
        nextOrdinal - afterOrdinal !== page.length ||
        (nextOrdinal < snapshot.rowCount && page.length === 0)
      ) {
        throw invalidM4Contract("export", "source_page_size");
      }
      rows.push(...page);
      afterOrdinal = nextOrdinal;
      if (snapshot.rowCount > request.maximumRows) break;
    }
    if (snapshot === undefined) {
      throw invalidM4Contract("export", "source_snapshot_missing");
    }
    return Object.freeze({ rows: Object.freeze(rows), snapshot });
  }

  async #single(
    functionName: string,
    body: Readonly<Record<string, unknown>>,
    signal: AbortSignal,
  ): Promise<Record<string, unknown>> {
    let response: Response;
    try {
      response = await this.#fetch(
        `${this.#baseUrl}/rest/v1/rpc/${functionName}`,
        {
          body: JSON.stringify(body),
          headers: this.#rpcHeaders,
          method: "POST",
          signal,
        },
      );
    } catch {
      throw new JobExecutionError({
        classification: "transient",
        code: "export.database_transport_failed",
        safeDetail: "The export database request did not complete.",
      });
    }
    if (!response.ok) throw classifyM4Response("export", response);
    let value: unknown;
    try {
      value = await response.json();
    } catch {
      throw invalidM4Contract("export", "json_response");
    }
    if (!Array.isArray(value) || value.length !== 1) {
      throw invalidM4Contract("export", "response_count");
    }
    return requireRecord(value[0], "export", "response_row");
  }
}
