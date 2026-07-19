import type { Locale } from "../i18n/messages";
import {
  M3ApiError,
  newM3IdempotencyKey,
  requestM3Json,
  type M3ApiContext,
} from "./m3-api-client";

export type M4ApiContext = M3ApiContext;
export { M3ApiError as M4ApiError };

export function newM4IdempotencyKey(prefix: string): string {
  return newM3IdempotencyKey(`m4-${prefix}`);
}

export function requestM4Json<T>(input: {
  readonly body?: unknown;
  readonly context: M4ApiContext;
  readonly idempotencyKey?: string;
  readonly method?: "DELETE" | "GET" | "PATCH" | "POST";
  readonly path: string;
}): Promise<T> {
  return requestM3Json<T>(input);
}

export type M4ArtifactStatus =
  "draft" | "validated" | "test_passed" | "approved" | "active" | "retired";
export type M4JobStatus =
  | "queued"
  | "running"
  | "retry_wait"
  | "succeeded"
  | "dead_letter"
  | "cancelled";

export interface M4DocumentType {
  readonly activation_status: M4ArtifactStatus;
  readonly field_schema: Readonly<Record<string, unknown>>;
  readonly field_schema_checksum: string;
  readonly id: string;
  readonly key: string;
  readonly labels: Readonly<Record<Locale, string>>;
  readonly official_generation_enabled: boolean;
  readonly preview_generation_enabled: boolean;
  readonly production_enabled: boolean;
  readonly template_locales: readonly string[];
  readonly version: number;
}

export type M4DocumentStatus =
  | "queued"
  | "generating"
  | "generated"
  | "failed"
  | "generation_failed"
  | "signed_received"
  | "completed"
  | "voided"
  | "superseded";

export interface M4DocumentListRow {
  readonly aggregate_version: number;
  readonly created_at: string;
  readonly current_file_id: string | null;
  readonly deal_id: string;
  readonly document_type_key: string;
  readonly generated_at: string | null;
  readonly id: string;
  readonly job_status: M4JobStatus | null;
  readonly locale: string;
  readonly mode: "preview" | "official";
  readonly official_number: string | null;
  readonly preview_artifact_id: string | null;
  readonly status: M4DocumentStatus;
  readonly superseded_by_document_id: string | null;
  readonly supersedes_document_id: string | null;
}

export interface M4DocumentFile {
  readonly byte_size: number;
  readonly checksum_sha256: string;
  readonly created_at: string;
  readonly current: boolean;
  readonly filename: string;
  readonly id: string;
  readonly mime_type: string;
  readonly role:
    | "preview"
    | "generated_original"
    | "signed_scan"
    | "attachment"
    | "void_notice";
  readonly version: number;
}

export interface M4DocumentJob {
  readonly attempt_count: number;
  readonly failure_code: string | null;
  readonly job_id: string;
  readonly review_required: boolean;
  readonly status: M4JobStatus;
  readonly updated_at: string;
}

export interface M4DocumentDetail extends M4DocumentListRow {
  readonly calculation_snapshot: Readonly<Record<string, unknown>> | null;
  readonly document_date: string | null;
  readonly files: readonly M4DocumentFile[];
  readonly intended_signature_date: string | null;
  readonly jobs: readonly M4DocumentJob[];
  readonly render_input_checksum: string;
  readonly signed_at: string | null;
  readonly tax_snapshot: Readonly<Record<string, unknown>> | null;
  readonly version_snapshot: Readonly<Record<string, unknown>>;
  readonly version_snapshot_checksum: string | null;
  readonly void_reason: string | null;
}

export interface M4DocumentActionEligibility {
  readonly retryRender: boolean;
  readonly markSigned: boolean;
  readonly supersede: boolean;
  readonly void: boolean;
}

/**
 * M4-DOC-AC-006..009: mirror the lifecycle predicates enforced by the
 * document command RPCs. Permissions and recent-auth checks remain server
 * authoritative, so this helper only controls whether the action is offered.
 */
export function m4DocumentActionEligibility(
  document: Pick<M4DocumentDetail, "files" | "jobs" | "mode" | "status">,
): M4DocumentActionEligibility {
  const latestJob = document.jobs[0];
  const official = document.mode === "official";
  const mutableOfficial =
    official &&
    (document.status === "generated" ||
      document.status === "signed_received" ||
      document.status === "completed");
  const voidableOfficial =
    mutableOfficial || (official && document.status === "generation_failed");
  return Object.freeze({
    markSigned:
      official &&
      document.status === "generated" &&
      document.files.some(
        (file) => file.current && file.role === "signed_scan",
      ),
    retryRender:
      official &&
      document.status === "generation_failed" &&
      latestJob?.status === "dead_letter" &&
      latestJob.review_required,
    supersede: mutableOfficial,
    void: voidableOfficial,
  });
}

export interface M4DocumentValidation {
  readonly calculation_ready: boolean;
  readonly document_type_ready: boolean;
  readonly errors: readonly string[];
  readonly numbering_ready: boolean;
  readonly official_ready: boolean;
  readonly preview_ready: boolean;
  readonly tax_ready: boolean;
  readonly template_ready: boolean;
  readonly warnings: readonly string[];
}

export interface M4DocumentRequestResult {
  readonly aggregate_version: number;
  readonly audit_event_id: string;
  readonly document_id: string;
  readonly document_status: M4DocumentStatus;
  readonly job_id: string;
  readonly number_allocation_id: string | null;
  readonly official_number: string | null;
  readonly outbox_event_id: string;
  readonly replayed: boolean;
}

export interface M4ArtifactVersion {
  readonly checksum: string;
  readonly id: string;
  readonly semantic_version: string;
  readonly status: M4ArtifactStatus;
  readonly version: number;
}

export interface M4NumberingDefinition {
  readonly active_version_id: string | null;
  readonly created_at: string;
  readonly id: string;
  readonly key: string;
  readonly labels: Readonly<Record<Locale, string>>;
  readonly versions: readonly (M4ArtifactVersion & {
    readonly activated_at: string | null;
    readonly approval_record_id: string | null;
  })[];
}

export interface M4CalculationDefinition {
  readonly active_version_id: string | null;
  readonly id: string;
  readonly key: string;
  readonly labels: Readonly<Record<Locale, string>>;
  readonly versions: readonly (M4ArtifactVersion & {
    readonly engine_version: string;
  })[];
}

export interface M4TaxPack {
  readonly active_versions: readonly string[];
  readonly id: string;
  readonly key: string;
  readonly labels: Readonly<Record<Locale, string>>;
  readonly source_kind: "portable_pack" | "workspace_import";
  readonly versions: readonly (M4ArtifactVersion & {
    readonly contexts: readonly string[];
    readonly currency_codes: readonly string[];
    readonly effective_from: string;
    readonly effective_to: string | null;
    readonly jurisdiction_code: string;
  })[];
}

export interface M4ApprovalRecord {
  readonly approval_type: string;
  readonly artifact_checksum: string;
  readonly artifact_id: string;
  readonly artifact_key: string;
  readonly artifact_type: string;
  readonly artifact_version: number;
  readonly attachment_reference: string | null;
  readonly conditions: Readonly<Record<string, unknown>>;
  readonly decided_at: string;
  readonly decision: "approved" | "rejected" | "revoked";
  readonly expires_at: string | null;
  readonly id: string;
  readonly professional_organization: string | null;
  readonly professional_role: string | null;
  readonly review_due_at: string | null;
  readonly supersedes_approval_id: string | null;
}

export interface M4ExportDefinition {
  readonly active_version_id: string;
  readonly columns: readonly unknown[];
  readonly filter_schema: Readonly<Record<string, unknown>>;
  readonly formats: readonly ("csv" | "xlsx")[];
  readonly id: string;
  readonly key: string;
  readonly labels: Readonly<Record<Locale, string>>;
  readonly maximum_rows: number;
  readonly permission_key: string;
  readonly sensitivity: "standard" | "sensitive" | "restricted";
  readonly step_up_required: boolean;
  readonly version_checksum: string;
}

export type M4ExportStatus =
  | "queued"
  | "running"
  | "retry_wait"
  | "generated"
  | "failed"
  | "dead_letter"
  | "expired";

export interface M4ExportRun {
  readonly created_at: string;
  readonly expires_at: string;
  readonly export_definition_key: string;
  readonly export_file_id: string | null;
  readonly export_run_id: string;
  readonly export_version_id: string;
  readonly failure_code: string | null;
  readonly generated_checksum: string | null;
  readonly job_id: string | null;
  readonly locale: string;
  readonly outbox_event_id: string | null;
  readonly replayed: boolean;
  readonly requested_format: "csv" | "xlsx";
  readonly row_count: number | null;
  readonly status: M4ExportStatus;
}

export interface M4ExportRunRequest {
  readonly audit_event_id: string;
  readonly expires_at: string;
  readonly export_run_id: string;
  readonly job_id: string;
  readonly job_status: M4JobStatus;
  readonly replayed: boolean;
  readonly run_status: M4ExportStatus;
}

export interface M4DownloadGrant {
  readonly download: { readonly expiresAt: string; readonly url: string };
  readonly filename: string;
}

export interface M4InventoryAgingRow {
  readonly acquired_on: string;
  readonly age_days: number;
  readonly cost_amount_minor: string;
  readonly currency_code: string;
  readonly inventory_unit_id: string;
  readonly location_id: string;
  readonly make: string;
  readonly model: string;
  readonly model_year: number;
  readonly stock_number: string;
}

export interface M4InventoryGrossRow {
  readonly closed_at: string;
  readonly cost_amount_minor: string;
  readonly currency_code: string;
  readonly deal_id: string;
  readonly gross_amount_minor: string;
  readonly inventory_unit_id: string;
  readonly revenue_amount_minor: string;
  readonly stock_number: string;
}

export interface M4LeadReportRow {
  readonly converted_deal_id: string | null;
  readonly created_at: string;
  readonly id: string;
  readonly last_activity_at: string | null;
  readonly owner_membership_id: string | null;
  readonly source_key: string;
  readonly status: string;
}

export interface M4DealReportRow {
  readonly created_at: string;
  readonly currency_code: string;
  readonly deal_type_key: string;
  readonly id: string;
  readonly owner_membership_id: string | null;
  readonly status: string;
  readonly total_amount_minor: string;
  readonly updated_at: string;
}

export type M4ReportRow =
  M4InventoryAgingRow | M4InventoryGrossRow | M4LeadReportRow | M4DealReportRow;

export function localizedM4Label(
  labels: Readonly<Record<string, string>>,
  locale: Locale,
  unavailable: string,
): string {
  return labels[locale] ?? labels.en ?? unavailable;
}

export function m4Query(
  path: string,
  values: Readonly<Record<string, string | undefined>>,
): string {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) {
    if (value) query.set(key, value);
  }
  const suffix = query.toString();
  return suffix ? `${path}?${suffix}` : path;
}

export function parseM4JsonObject(
  value: string,
): Readonly<Record<string, unknown>> {
  const parsed: unknown = JSON.parse(value);
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new TypeError("json_object_required");
  }
  return parsed as Readonly<Record<string, unknown>>;
}

export function parseM4JsonArray(value: string): readonly unknown[] {
  const parsed: unknown = JSON.parse(value);
  if (!Array.isArray(parsed)) throw new TypeError("json_array_required");
  return parsed;
}
