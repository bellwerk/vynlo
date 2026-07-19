import { JobExecutionError } from "./job-runner";
import type { OfficialDocumentRepository } from "./official-document-handler";
import type { OfficialDocumentRenderSource } from "./official-document-renderer";
import {
  classifyM4Response,
  invalidM4Contract,
  requireChecksum,
  requireInteger,
  requireRecord,
  requireString,
  requireUuid,
  validatedSupabaseOrigin,
} from "./m4-worker-validation";

export class PostgrestOfficialDocumentRepository implements OfficialDocumentRepository {
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #headers: Readonly<Record<string, string>>;

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
    this.#headers = Object.freeze({
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
      "Content-Profile": "app",
      "Content-Type": "application/json",
    });
  }

  async load(
    input: Parameters<OfficialDocumentRepository["load"]>[0],
  ): ReturnType<OfficialDocumentRepository["load"]> {
    const row = await this.#single(
      "m4_load_official_document_render",
      {
        p_document_id: input.documentId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    const sourceCss = row.source_css;
    if (typeof sourceCss !== "string" || sourceCss.length > 1_000_000) {
      throw invalidM4Contract("document", "source_css");
    }
    const hasCompletion = row.completed_file_id !== null;
    if (
      hasCompletion !==
      (row.completed_checksum !== null &&
        row.completed_byte_size !== null &&
        row.completed_aggregate_version !== null)
    ) {
      throw invalidM4Contract("document", "completion_replay_shape");
    }
    const result = {
      assetManifest: requireRecord(
        row.asset_manifest,
        "document",
        "asset_manifest",
      ),
      documentId: requireUuid(row.document_id, "document", "document_id"),
      fontManifest: requireRecord(
        row.font_manifest,
        "document",
        "font_manifest",
      ),
      locale: requireString(row.locale, "document", "locale", 100),
      officialNumber: requireString(
        row.official_number,
        "document",
        "official_number",
        128,
      ),
      renderInputChecksum: requireChecksum(
        row.render_input_checksum,
        "document",
        "render_input_checksum",
      ),
      renderInputSnapshot: requireRecord(
        row.render_input_snapshot,
        "document",
        "render_input_snapshot",
      ),
      rendererVersion: requireString(
        row.renderer_version,
        "document",
        "renderer_version",
        200,
      ),
      sourceBundleChecksum: requireChecksum(
        row.source_bundle_checksum,
        "document",
        "source_bundle_checksum",
      ),
      sourceCss,
      sourceHtml: requireString(
        row.source_html,
        "document",
        "source_html",
        1_000_000,
      ),
      versionSnapshot: requireRecord(
        row.version_snapshot,
        "document",
        "version_snapshot",
      ),
      versionSnapshotChecksum: requireChecksum(
        row.version_snapshot_checksum,
        "document",
        "version_snapshot_checksum",
      ),
      completion: hasCompletion
        ? Object.freeze({
            aggregateVersion: requireInteger(
              row.completed_aggregate_version,
              "document",
              "completed_aggregate_version",
              1,
              Number.MAX_SAFE_INTEGER,
            ),
            artifactChecksum: requireChecksum(
              row.completed_checksum,
              "document",
              "completed_checksum",
            ),
            byteSize: requireInteger(
              row.completed_byte_size,
              "document",
              "completed_byte_size",
              1,
              52_428_800,
            ),
            documentFileId: requireUuid(
              row.completed_file_id,
              "document",
              "completed_file_id",
            ),
          })
        : null,
    } satisfies OfficialDocumentRenderSource &
      Readonly<{
        readonly completion: Awaited<
          ReturnType<OfficialDocumentRepository["load"]>
        >["completion"];
      }>;
    if (result.documentId !== input.documentId) {
      throw invalidM4Contract("document", "workspace_document_binding");
    }
    return Object.freeze(result);
  }

  async complete(
    input: Parameters<OfficialDocumentRepository["complete"]>[0],
  ): ReturnType<OfficialDocumentRepository["complete"]> {
    const row = await this.#single(
      "m4_complete_official_document_render",
      {
        p_byte_size: input.byteSize,
        p_checksum: input.artifactChecksum,
        p_correlation_id: input.correlationId,
        p_document_id: input.documentId,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_renderer_version: input.rendererVersion,
        p_request_id: input.requestId,
        p_storage_bucket: input.storageBucket,
        p_storage_generation: input.storageGeneration,
        p_storage_object_path: input.objectPath,
        p_verification_receipt: input.receipt,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    if (
      row.document_status !== "generated" ||
      typeof row.replayed !== "boolean"
    ) {
      throw invalidM4Contract("document", "completion_state");
    }
    return Object.freeze({
      aggregateVersion: requireInteger(
        row.aggregate_version,
        "document",
        "aggregate_version",
        1,
        Number.MAX_SAFE_INTEGER,
      ),
      documentFileId: requireUuid(
        row.document_file_id,
        "document",
        "document_file_id",
      ),
      replayed: row.replayed,
    });
  }

  async recordFailure(
    input: Parameters<OfficialDocumentRepository["recordFailure"]>[0],
  ): Promise<void> {
    const row = await this.#single(
      "m4_fail_official_document_render",
      {
        p_correlation_id: input.correlationId,
        p_document_id: input.documentId,
        p_error_classification: input.classification,
        p_error_code: input.errorCode,
        p_error_detail_safe: input.errorDetailSafe,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_request_id: input.requestId,
        p_retry_after_seconds: input.retryAfterSeconds ?? null,
        p_worker_id: input.workerId,
        p_workspace_id: input.workspaceId,
      },
      input.signal,
    );
    if (row.document_status !== "generating" || row.job_status !== "running") {
      throw invalidM4Contract("document", "failure_recording_state");
    }
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
          headers: this.#headers,
          method: "POST",
          signal,
        },
      );
    } catch {
      throw new JobExecutionError({
        classification: "transient",
        code: "document.database_transport_failed",
        safeDetail: "The document database request did not complete.",
      });
    }
    if (!response.ok) throw classifyM4Response("document", response);
    let value: unknown;
    try {
      value = await response.json();
    } catch {
      throw invalidM4Contract("document", "json_response");
    }
    if (!Array.isArray(value) || value.length !== 1) {
      throw invalidM4Contract("document", "response_count");
    }
    return requireRecord(value[0], "document", "response_row");
  }
}
