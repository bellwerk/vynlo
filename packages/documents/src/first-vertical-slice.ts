const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOCALE_PATTERN = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/;
const CHECKSUM_PATTERN = /^[a-f0-9]{64}$/;

export const PREVIEW_WATERMARK = "DRAFT / NON-PRODUCTION" as const;

export const SYNTHETIC_NON_PRODUCTION_TEMPLATE = Object.freeze({
  key: "synthetic.preview",
  version: 1,
  locale: "en-CA",
  rendererVersion: "synthetic-html-v1",
  productionApproved: false,
  officialGenerationEnabled: false,
  watermark: PREVIEW_WATERMARK,
  sourceHtml:
    "<!doctype html><html><body><main><h1>Preview</h1><p>{{ deal.id }}</p></main></body></html>",
});

export type DocumentPreviewCommandErrorCode =
  | "invalid_idempotency_key"
  | "invalid_deal_id"
  | "invalid_template_version_id"
  | "invalid_locale"
  | "invalid_preview_record"
  | "invalid_preview_transition";

export class DocumentPreviewCommandError extends Error {
  readonly code: DocumentPreviewCommandErrorCode;

  constructor(code: DocumentPreviewCommandErrorCode) {
    super(code);
    this.name = "DocumentPreviewCommandError";
    this.code = code;
  }
}

export interface RequestDocumentPreviewCommand {
  readonly idempotencyKey: string;
  readonly dealId: string;
  readonly templateVersionId: string;
  readonly locale: string;
}

export type PreviewDocumentState =
  | Readonly<{ status: "queued"; generatedChecksum: null; failureCode: null }>
  | Readonly<{
      status: "generated";
      generatedChecksum: string;
      failureCode: null;
    }>
  | Readonly<{
      status: "failed";
      generatedChecksum: null;
      failureCode: string;
    }>;

export interface PreviewDocumentRecord {
  readonly mode: "preview";
  readonly officialNumber: null;
  readonly watermark: typeof PREVIEW_WATERMARK;
  readonly state: PreviewDocumentState;
}

export function normalizeRequestDocumentPreviewCommand(
  command: RequestDocumentPreviewCommand,
): Readonly<RequestDocumentPreviewCommand> {
  const idempotencyKey = command.idempotencyKey.trim();
  if (idempotencyKey.length < 8 || idempotencyKey.length > 200) {
    throw new DocumentPreviewCommandError("invalid_idempotency_key");
  }

  if (!UUID_PATTERN.test(command.dealId)) {
    throw new DocumentPreviewCommandError("invalid_deal_id");
  }
  if (!UUID_PATTERN.test(command.templateVersionId)) {
    throw new DocumentPreviewCommandError("invalid_template_version_id");
  }

  const locale = command.locale.trim();
  if (!LOCALE_PATTERN.test(locale)) {
    throw new DocumentPreviewCommandError("invalid_locale");
  }

  return Object.freeze({
    idempotencyKey,
    dealId: command.dealId.toLowerCase(),
    templateVersionId: command.templateVersionId.toLowerCase(),
    locale,
  });
}

export function assertSafePreviewRecord(
  record: PreviewDocumentRecord,
): PreviewDocumentRecord {
  if (
    record.mode !== "preview" ||
    record.officialNumber !== null ||
    record.watermark !== PREVIEW_WATERMARK
  ) {
    throw new DocumentPreviewCommandError("invalid_preview_record");
  }
  return record;
}

export function completePreviewState(
  current: PreviewDocumentState,
  outcome:
    | Readonly<{ status: "generated"; generatedChecksum: string }>
    | Readonly<{ status: "failed"; failureCode: string }>,
): PreviewDocumentState {
  if (current.status !== "queued") {
    throw new DocumentPreviewCommandError("invalid_preview_transition");
  }

  if (outcome.status === "generated") {
    const generatedChecksum = outcome.generatedChecksum.trim().toLowerCase();
    if (!CHECKSUM_PATTERN.test(generatedChecksum)) {
      throw new DocumentPreviewCommandError("invalid_preview_transition");
    }
    return Object.freeze({
      status: "generated",
      generatedChecksum,
      failureCode: null,
    });
  }

  const failureCode = outcome.failureCode.trim();
  if (!failureCode || failureCode.length > 100) {
    throw new DocumentPreviewCommandError("invalid_preview_transition");
  }
  return Object.freeze({
    status: "failed",
    generatedChecksum: null,
    failureCode,
  });
}
