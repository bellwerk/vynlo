import { JobExecutionError } from "./job-runner";
import type {
  PreviewArtifactCompletion,
  PreviewDocumentRepository,
} from "./preview-handler";
import {
  PREVIEW_WATERMARK,
  type PreviewRenderSource,
} from "./preview-renderer";

function requireRecord(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidDatabaseContract(label);
  }
  return value as Record<string, unknown>;
}

function requireString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw invalidDatabaseContract(label);
  }
  return value;
}

function invalidDatabaseContract(label: string): JobExecutionError {
  return new JobExecutionError({
    classification: "permanent",
    code: `preview.invalid_${label}`,
    safeDetail: "The preview database response failed contract validation.",
  });
}

function validatedBaseUrl(value: string): string {
  const url = new URL(value);
  const isLocal = ["127.0.0.1", "localhost", "::1"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && isLocal)) {
    throw new TypeError(
      "Supabase URL must use HTTPS except for local development.",
    );
  }
  return url.toString().replace(/\/$/u, "");
}

function classifyResponse(response: Response): JobExecutionError {
  if (response.status === 401 || response.status === 403) {
    return new JobExecutionError({
      classification: "provider_auth",
      code: "preview.database_access_denied",
      safeDetail: "The preview database denied the worker request.",
    });
  }
  if (response.status === 409) {
    return new JobExecutionError({
      classification: "permanent",
      code: "preview.artifact_conflict",
      safeDetail:
        "The preview artifact conflicts with recorded terminal state.",
    });
  }
  if (response.status === 429 || response.status >= 500) {
    return new JobExecutionError({
      classification: "transient",
      code: "preview.database_temporarily_unavailable",
      safeDetail: "The preview database is temporarily unavailable.",
    });
  }
  return new JobExecutionError({
    classification: "permanent",
    code: "preview.database_request_rejected",
    safeDetail: "The preview database rejected the validated worker request.",
  });
}

export class PostgrestPreviewDocumentRepository implements PreviewDocumentRepository {
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
    this.#baseUrl = validatedBaseUrl(input.supabaseUrl);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#headers = {
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
      "Content-Type": "application/json",
    };
  }

  async loadRenderSource(
    input: Parameters<PreviewDocumentRepository["loadRenderSource"]>[0],
  ): Promise<PreviewRenderSource> {
    const documentQuery = new URLSearchParams({
      id: `eq.${input.payload.documentId}`,
      limit: "1",
      select:
        "id,workspace_id,template_version_id,mode,official_number,status,locale,watermark,render_input_snapshot,render_input_checksum",
      workspace_id: `eq.${input.workspaceId}`,
    });
    const templateQuery = new URLSearchParams({
      id: `eq.${input.payload.templateVersionId}`,
      limit: "1",
      select:
        "id,workspace_id,locale,template_class,source_html,source_checksum,renderer_version,production_approved,watermark,status",
      workspace_id: `eq.${input.workspaceId}`,
    });
    const [documents, templates] = await Promise.all([
      this.#requestJson(`/rest/v1/documents?${documentQuery.toString()}`, {
        method: "GET",
        signal: input.signal,
      }),
      this.#requestJson(
        `/rest/v1/document_template_versions?${templateQuery.toString()}`,
        { method: "GET", signal: input.signal },
      ),
    ]);

    if (
      !Array.isArray(documents) ||
      documents.length !== 1 ||
      !Array.isArray(templates) ||
      templates.length !== 1
    ) {
      throw invalidDatabaseContract("render_source_count");
    }
    const document = requireRecord(documents[0], "document");
    const template = requireRecord(templates[0], "template");
    const snapshot = requireRecord(
      document.render_input_snapshot,
      "render_input_snapshot",
    );
    const officialNumber = document.official_number;
    const productionApproved = template.production_approved;
    const documentMode = requireString(document.mode, "document_mode");
    const documentStatus = requireString(document.status, "document_status");
    const templateClass = requireString(
      template.template_class,
      "template_class",
    );
    const templateStatus = requireString(template.status, "template_status");
    const documentId = requireString(document.id, "document_id");
    const documentWorkspaceId = requireString(
      document.workspace_id,
      "document_workspace_id",
    );
    const documentTemplateVersionId = requireString(
      document.template_version_id,
      "document_template_version_id",
    );
    const documentLocale = requireString(document.locale, "document_locale");
    const templateId = requireString(template.id, "template_version_id");
    const templateWorkspaceId = requireString(
      template.workspace_id,
      "template_workspace_id",
    );
    const templateLocale = requireString(template.locale, "template_locale");
    const documentWatermark = requireString(
      document.watermark,
      "document_watermark",
    );
    const templateWatermark = requireString(
      template.watermark,
      "template_watermark",
    );

    if (
      officialNumber !== null ||
      productionApproved !== false ||
      documentMode !== "preview" ||
      !["queued", "generated"].includes(documentStatus) ||
      templateClass !== "synthetic_non_production" ||
      !["active", "retired"].includes(templateStatus) ||
      documentWatermark !== PREVIEW_WATERMARK ||
      templateWatermark !== PREVIEW_WATERMARK ||
      documentId !== input.payload.documentId ||
      documentWorkspaceId !== input.workspaceId ||
      templateWorkspaceId !== input.workspaceId ||
      documentTemplateVersionId !== input.payload.templateVersionId ||
      templateId !== input.payload.templateVersionId ||
      documentLocale !== input.payload.locale ||
      templateLocale !== input.payload.locale
    ) {
      throw invalidDatabaseContract("preview_only_state");
    }

    return {
      documentId,
      documentMode: "preview",
      documentStatus: documentStatus as "queued" | "generated",
      locale: documentLocale,
      officialNumber: null,
      productionApproved: false,
      renderInputChecksum: requireString(
        document.render_input_checksum,
        "render_input_checksum",
      ),
      renderInputSnapshot: snapshot,
      rendererVersion: requireString(
        template.renderer_version,
        "renderer_version",
      ),
      sourceChecksum: requireString(
        template.source_checksum,
        "source_checksum",
      ),
      sourceHtml: requireString(template.source_html, "source_html"),
      templateClass: "synthetic_non_production",
      templateStatus: templateStatus as "active" | "retired",
      templateVersionId: templateId,
      watermark: PREVIEW_WATERMARK,
      workspaceId: documentWorkspaceId,
    };
  }

  async completeArtifact(
    input: Parameters<PreviewDocumentRepository["completeArtifact"]>[0],
  ): Promise<PreviewArtifactCompletion> {
    const value = await this.#requestJson(
      "/rest/v1/rpc/complete_document_preview_artifact",
      {
        body: JSON.stringify({
          p_byte_size: input.byteSize,
          p_checksum: input.artifactChecksum,
          p_correlation_id: input.correlationId,
          p_document_id: input.documentId,
          p_filename: input.filename,
          p_job_id: input.jobId,
          p_lease_token: input.leaseToken,
          p_mime_type: input.contentType,
          p_renderer_version: input.rendererVersion,
          p_request_id: input.requestId,
          p_storage_bucket: input.storageBucket,
          p_storage_object_path: input.objectPath,
          p_worker_id: input.workerId,
          p_workspace_id: input.workspaceId,
        }),
        method: "POST",
        signal: input.signal,
      },
      "app",
    );
    if (!Array.isArray(value) || value.length !== 1) {
      throw invalidDatabaseContract("artifact_completion_count");
    }
    const completion = requireRecord(value[0], "artifact_completion");
    if (
      completion.document_status !== "generated" ||
      typeof completion.replayed !== "boolean"
    ) {
      throw invalidDatabaseContract("artifact_completion_state");
    }
    return {
      documentFileId: requireString(
        completion.document_file_id,
        "document_file_id",
      ),
      documentStatus: "generated",
      replayed: completion.replayed,
    };
  }

  async #requestJson(
    path: string,
    init: Omit<RequestInit, "headers">,
    contentProfile?: "app",
  ): Promise<unknown> {
    let response: Response;
    try {
      response = await this.#fetch(`${this.#baseUrl}${path}`, {
        ...init,
        headers:
          contentProfile === undefined
            ? this.#headers
            : { ...this.#headers, "Content-Profile": contentProfile },
      });
    } catch {
      throw new JobExecutionError({
        classification: "transient",
        code: "preview.database_transport_failed",
        safeDetail: "The preview database request did not complete.",
      });
    }
    if (!response.ok) {
      throw classifyResponse(response);
    }
    try {
      return await response.json();
    } catch {
      throw invalidDatabaseContract("json_response");
    }
  }
}
