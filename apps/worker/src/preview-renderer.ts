import { createHash } from "node:crypto";

import { JobExecutionError } from "./job-runner";

export const PREVIEW_JOB_TYPE = "documents.render_preview" as const;
export const PREVIEW_WATERMARK = "DRAFT / NON-PRODUCTION" as const;
export const PREVIEW_RENDERER_VERSION = "synthetic-html-v1" as const;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const checksumPattern = /^[a-f0-9]{64}$/u;
const localePattern = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/u;
const variablePattern = /\{\{\s*([^{}]+?)\s*\}\}/gu;
const allowedPlaceholders = new Set([
  "watermark",
  "deal.id",
  "deal.deal_type_key",
  "deal.currency_code",
  "participants[0].display_name",
  "inventory_units[0].stock_number",
  "inventory_units[0].vin",
]);
const unsupportedTemplateSyntax = /(\{[%#]|[%#]\})/u;
const unsafeTemplateSource =
  /(<\s*(?:script|iframe|object|embed|link|img|video|audio|source|form|base)\b|javascript\s*:|expression\s*\(|url\s*\(|\bon[a-z]+\s*=|@import\b|(?:src|href)\s*=\s*["']?\s*(?:https?:)?\/\/)/iu;

export interface PreviewJobPayload {
  readonly documentId: string;
  readonly locale: string;
  readonly renderInputChecksum: string;
  readonly templateVersionId: string;
}

export interface PreviewRenderSource {
  readonly documentId: string;
  readonly documentMode: "preview";
  readonly documentStatus: "queued" | "generated";
  readonly locale: string;
  readonly officialNumber: null;
  readonly productionApproved: false;
  readonly renderInputChecksum: string;
  readonly renderInputSnapshot: Readonly<Record<string, unknown>>;
  readonly rendererVersion: string;
  readonly sourceChecksum: string;
  readonly sourceHtml: string;
  readonly templateClass: "synthetic_non_production";
  readonly templateStatus: "active" | "retired";
  readonly templateVersionId: string;
  readonly watermark: typeof PREVIEW_WATERMARK;
  readonly workspaceId: string;
}

export interface RenderedPreviewArtifact {
  readonly body: Uint8Array;
  readonly byteSize: number;
  readonly checksum: string;
  readonly contentType: "text/html; charset=utf-8";
  readonly filename: "preview.html";
  readonly html: string;
  readonly rendererVersion: typeof PREVIEW_RENDERER_VERSION;
  readonly watermark: typeof PREVIEW_WATERMARK;
}

function invalidPayload(): never {
  throw new JobExecutionError({
    classification: "validation",
    code: "preview.invalid_job_payload",
    safeDetail: "The preview job payload does not match schema version one.",
  });
}

function requireUuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    invalidPayload();
  }
  return value;
}

export function parsePreviewJobPayload(input: {
  readonly entityId: string | null;
  readonly entityType: string;
  readonly jobType: string;
  readonly payload: Readonly<Record<string, unknown>>;
  readonly payloadSchemaVersion: number;
}): PreviewJobPayload {
  if (
    input.jobType !== PREVIEW_JOB_TYPE ||
    input.entityType !== "document" ||
    input.payloadSchemaVersion !== 1
  ) {
    invalidPayload();
  }

  const expectedKeys = [
    "document_id",
    "locale",
    "render_input_checksum",
    "template_version_id",
  ];
  const actualKeys = Object.keys(input.payload).sort();
  if (
    actualKeys.length !== expectedKeys.length ||
    actualKeys.some((key, index) => key !== expectedKeys[index])
  ) {
    invalidPayload();
  }

  const documentId = requireUuid(input.payload.document_id);
  const templateVersionId = requireUuid(input.payload.template_version_id);
  const renderInputChecksum = input.payload.render_input_checksum;
  const locale = input.payload.locale;

  if (
    input.entityId !== documentId ||
    typeof renderInputChecksum !== "string" ||
    !checksumPattern.test(renderInputChecksum) ||
    typeof locale !== "string" ||
    !localePattern.test(locale)
  ) {
    invalidPayload();
  }

  return { documentId, locale, renderInputChecksum, templateVersionId };
}

export function sha256Hex(value: string | Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function resolveVariable(
  snapshot: Readonly<Record<string, unknown>>,
  path: string,
): string {
  if (!allowedPlaceholders.has(path)) {
    throw new JobExecutionError({
      classification: "permanent",
      code: "preview.template_placeholder_not_allowed",
      safeDetail: "The preview template contains an unsupported placeholder.",
    });
  }
  if (path === "watermark") {
    return escapeHtml(PREVIEW_WATERMARK);
  }

  let value: unknown = snapshot;
  for (const segment of path.replaceAll(/\[(\d+)\]/gu, ".$1").split(".")) {
    if (
      typeof value !== "object" ||
      value === null ||
      !Object.hasOwn(value, segment)
    ) {
      throw new JobExecutionError({
        classification: "validation",
        code: "preview.template_field_missing",
        safeDetail: "The preview template references a missing scalar field.",
      });
    }
    value = (value as Readonly<Record<string, unknown>>)[segment];
  }

  if (value === null) {
    return "";
  }
  if (!["string", "number", "boolean"].includes(typeof value)) {
    throw new JobExecutionError({
      classification: "validation",
      code: "preview.template_field_not_scalar",
      safeDetail: "The preview template references a non-scalar field.",
    });
  }
  return escapeHtml(String(value));
}

function assertRenderSource(
  source: PreviewRenderSource,
  payload: PreviewJobPayload,
  workspaceId: string,
): void {
  if (
    source.workspaceId !== workspaceId ||
    source.documentId !== payload.documentId ||
    source.templateVersionId !== payload.templateVersionId ||
    source.renderInputChecksum !== payload.renderInputChecksum ||
    source.locale !== payload.locale ||
    source.documentMode !== "preview" ||
    source.officialNumber !== null ||
    source.watermark !== PREVIEW_WATERMARK ||
    source.templateClass !== "synthetic_non_production" ||
    source.productionApproved !== false ||
    !["active", "retired"].includes(source.templateStatus) ||
    source.rendererVersion !== PREVIEW_RENDERER_VERSION ||
    !checksumPattern.test(source.sourceChecksum) ||
    sha256Hex(source.sourceHtml) !== source.sourceChecksum ||
    source.sourceHtml.trim().length === 0 ||
    source.sourceHtml.length > 1_000_000 ||
    unsafeTemplateSource.test(source.sourceHtml) ||
    unsupportedTemplateSyntax.test(source.sourceHtml)
  ) {
    throw new JobExecutionError({
      classification: "validation",
      code: "preview.render_contract_rejected",
      safeDetail:
        "The preview source failed its non-production render contract.",
    });
  }
}

export function renderPreviewHtml(input: {
  readonly payload: PreviewJobPayload;
  readonly source: PreviewRenderSource;
  readonly workspaceId: string;
}): RenderedPreviewArtifact {
  assertRenderSource(input.source, input.payload, input.workspaceId);
  const templateContainsWatermark = /\{\{\s*watermark\s*\}\}/u.test(
    input.source.sourceHtml,
  );

  const interpolated = input.source.sourceHtml.replace(
    variablePattern,
    (_match, path: string) =>
      resolveVariable(input.source.renderInputSnapshot, path),
  );
  if (interpolated.includes("{{") || interpolated.includes("}}")) {
    throw new JobExecutionError({
      classification: "validation",
      code: "preview.template_syntax_unsupported",
      safeDetail: "The preview template contains unsupported variable syntax.",
    });
  }

  const banner =
    '<div data-vynlo-watermark="true" role="note" style="border:3px solid #9f1239;color:#9f1239;font:700 18px sans-serif;letter-spacing:.08em;margin:16px;padding:12px;text-align:center">' +
    PREVIEW_WATERMARK +
    "</div>";
  const html = templateContainsWatermark
    ? interpolated
    : /<body(?:\s[^>]*)?>/iu.test(interpolated)
      ? interpolated.replace(
          /<body(?:\s[^>]*)?>/iu,
          (bodyTag) => bodyTag + banner,
        )
      : `<html><body>${banner}${interpolated}</body></html>`;
  const body = new TextEncoder().encode(html);

  return {
    body,
    byteSize: body.byteLength,
    checksum: sha256Hex(body),
    contentType: "text/html; charset=utf-8",
    filename: "preview.html",
    html,
    rendererVersion: PREVIEW_RENDERER_VERSION,
    watermark: PREVIEW_WATERMARK,
  };
}

export function previewStorageObjectPath(input: {
  readonly artifactChecksum: string;
  readonly documentId: string;
  readonly workspaceId: string;
}): string {
  if (
    !uuidPattern.test(input.workspaceId) ||
    !uuidPattern.test(input.documentId) ||
    !checksumPattern.test(input.artifactChecksum)
  ) {
    throw new TypeError("Invalid preview storage path input.");
  }
  return `${input.workspaceId}/documents/${input.documentId}/preview/${input.artifactChecksum}.html`;
}
