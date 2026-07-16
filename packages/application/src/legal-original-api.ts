import { MediaPolicyError, normalizeLegalOriginalIntent } from "@vynlo/media";
import { z } from "zod";

import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const jobStatusSchema = z.enum([
  "queued",
  "running",
  "retry_wait",
  "succeeded",
  "dead_letter",
  "cancelled",
]);
const intentBodySchema = z
  .object({
    byteSize: z.number().int().min(1).max(50_000_000),
    checksumSha256: z.string().regex(/^[a-f0-9]{64}$/u),
    filename: z.string().trim().min(1).max(255),
    mediaKind: z.enum(["legal_document", "signed_document"]),
    mimeType: z.enum([
      "application/pdf",
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/heic",
      "image/heif",
    ]),
  })
  .strict();
const verificationBodySchema = z
  .object({ uploadSessionId: uuidSchema })
  .strict();
const retryBodySchema = z
  .object({ reason: z.string().trim().min(1).max(2_000) })
  .strict();
const intentRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    document_id: uuidSchema,
    expires_at: z.iso.datetime({ offset: true }),
    media_kind: z.enum(["legal_document", "signed_document"]),
    replayed: z.boolean(),
    upload_bucket: z.literal("media-private"),
    upload_object_key: z.string().min(1).max(1_000),
    upload_session_id: uuidSchema,
  })
  .strict();
const verificationRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    document_id: uuidSchema,
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    upload_session_id: uuidSchema,
  })
  .strict();
const projectedStatusSchema = z.enum([
  "awaiting_upload",
  "queued",
  "running",
  "retry_wait",
  "dead_letter",
  "rejected",
  "completed",
]);
const errorClassificationSchema = z.enum([
  "transient",
  "rate_limited",
  "permanent",
  "validation",
  "permission",
  "provider_auth",
  "unknown",
  "lease_expired",
]);
const statusRowSchema = z
  .object({
    attempt_count: z.number().int().min(0),
    completed_at: z.iso.datetime({ offset: true }).nullable(),
    document_id: uuidSchema,
    error_classification: errorClassificationSchema.nullable(),
    error_code: z
      .string()
      .regex(/^[a-z][a-z0-9_.-]{0,119}$/u)
      .nullable(),
    job_id: uuidSchema.nullable(),
    maximum_attempts: z.number().int().min(1).max(32).nullable(),
    media_kind: z.enum(["legal_document", "signed_document"]),
    retry_at: z.iso.datetime({ offset: true }).nullable(),
    retryable: z.boolean(),
    status: projectedStatusSchema,
    upload_session_id: uuidSchema,
  })
  .strict()
  .superRefine((row, context) => {
    if ((row.job_id === null) !== (row.maximum_attempts === null)) {
      context.addIssue({
        code: "custom",
        message: "job identity and retry policy must be projected together",
      });
    }
    if (row.retryable !== (row.status === "dead_letter")) {
      context.addIssue({
        code: "custom",
        message: "only dead-letter status may be manually retryable",
      });
    }
    if ((row.retry_at !== null) !== (row.status === "retry_wait")) {
      context.addIssue({
        code: "custom",
        message: "retry time must match retry-wait status",
      });
    }
    if (
      ["queued", "running", "retry_wait", "dead_letter", "completed"].includes(
        row.status,
      ) &&
      row.job_id === null
    ) {
      context.addIssue({
        code: "custom",
        message: "active and completed verification status requires a job",
      });
    }
    if (
      ["dead_letter", "rejected"].includes(row.status) &&
      row.error_classification === null &&
      row.error_code === null
    ) {
      context.addIssue({
        code: "custom",
        message: "terminal failure status requires a bounded safe failure",
      });
    }
  });
const retryRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    document_id: uuidSchema,
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    source_job_id: uuidSchema,
    upload_session_id: uuidSchema,
  })
  .strict();

export class LegalOriginalValidationError extends Error {
  readonly code:
    | "invalid_document_id"
    | "invalid_request_body"
    | "invalid_retry_reason"
    | "invalid_upload_session_id";

  constructor(code: LegalOriginalValidationError["code"]) {
    super("The legal original command input is invalid.");
    this.name = "LegalOriginalValidationError";
    this.code = code;
  }
}

export class LegalOriginalRpcContractError extends Error {
  constructor() {
    super("The legal original data store returned an invalid response.");
    this.name = "LegalOriginalRpcContractError";
  }
}

function documentId(value: string): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new LegalOriginalValidationError("invalid_document_id");
  }
  return parsed.data;
}

function uploadSessionId(value: string): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new LegalOriginalValidationError("invalid_upload_session_id");
  }
  return parsed.data;
}

function assertIdentity(
  expectedDocumentId: string,
  expectedUploadSessionId: string,
  row: { readonly document_id: string; readonly upload_session_id: string },
): void {
  if (
    row.document_id !== expectedDocumentId ||
    row.upload_session_id !== expectedUploadSessionId
  ) {
    throw new LegalOriginalRpcContractError();
  }
}

function single<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = z.array(schema).length(1).safeParse(value);
  if (!parsed.success) throw new LegalOriginalRpcContractError();
  return parsed.data[0] as T;
}

export class LegalOriginalApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async createUploadIntent(
    input: VerticalSliceCommandInput & { readonly documentId: string },
  ) {
    const parsed = intentBodySchema.safeParse(input.body);
    if (!parsed.success) {
      throw new LegalOriginalValidationError("invalid_request_body");
    }
    let intent;
    try {
      intent = normalizeLegalOriginalIntent(parsed.data);
    } catch (error) {
      if (error instanceof MediaPolicyError) {
        throw new LegalOriginalValidationError("invalid_request_body");
      }
      throw error;
    }
    const row = single(
      intentRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_legal_original_upload_session",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_document_id: documentId(input.documentId),
          p_expected_byte_size: intent.byteSize,
          p_expected_checksum_sha256: intent.checksumSha256,
          p_expected_mime_type: intent.mimeType,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_media_kind: intent.mediaKind,
          p_original_filename: intent.filename,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return Object.freeze({
      auditEventId: row.audit_event_id,
      documentId: row.document_id,
      expiresAt: row.expires_at,
      mediaKind: row.media_kind,
      replayed: row.replayed,
      upload: Object.freeze({
        bucket: row.upload_bucket,
        objectKey: row.upload_object_key,
      }),
      uploadSessionId: row.upload_session_id,
    });
  }

  async requestVerification(
    input: VerticalSliceCommandInput & { readonly documentId: string },
  ) {
    const parsed = verificationBodySchema.safeParse(input.body);
    if (!parsed.success) {
      throw new LegalOriginalValidationError("invalid_upload_session_id");
    }
    const row = single(
      verificationRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "request_legal_original_upload_verification",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_document_id: documentId(input.documentId),
          p_idempotency_key: input.metadata.idempotencyKey,
          p_request_id: input.metadata.requestId,
          p_upload_session_id: parsed.data.uploadSessionId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return Object.freeze({
      auditEventId: row.audit_event_id,
      documentId: row.document_id,
      job: Object.freeze({ id: row.job_id, status: row.job_status }),
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      uploadSessionId: row.upload_session_id,
    });
  }

  async getUploadStatus(input: {
    readonly documentId: string;
    readonly metadata: {
      readonly accessToken: string;
      readonly workspaceId: string;
    };
    readonly uploadSessionId: string;
  }) {
    const parsedDocumentId = documentId(input.documentId);
    const parsedUploadSessionId = uploadSessionId(input.uploadSessionId);
    const row = single(
      statusRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "get_legal_original_upload_status",
        parameters: {
          p_document_id: parsedDocumentId,
          p_upload_session_id: parsedUploadSessionId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertIdentity(parsedDocumentId, parsedUploadSessionId, row);
    return Object.freeze({
      completedAt: row.completed_at,
      documentId: row.document_id,
      failure:
        row.error_classification === null && row.error_code === null
          ? null
          : Object.freeze({
              classification: row.error_classification,
              code: row.error_code,
            }),
      job:
        row.job_id === null
          ? null
          : Object.freeze({
              attemptCount: row.attempt_count,
              id: row.job_id,
              maximumAttempts: row.maximum_attempts!,
              retryAt: row.retry_at,
            }),
      mediaKind: row.media_kind,
      retryable: row.retryable,
      status: row.status,
      uploadSessionId: row.upload_session_id,
    });
  }

  async retryVerification(
    input: VerticalSliceCommandInput & {
      readonly documentId: string;
      readonly uploadSessionId: string;
    },
  ) {
    const parsed = retryBodySchema.safeParse(input.body);
    if (!parsed.success) {
      throw new LegalOriginalValidationError("invalid_retry_reason");
    }
    const parsedDocumentId = documentId(input.documentId);
    const parsedUploadSessionId = uploadSessionId(input.uploadSessionId);
    const row = single(
      retryRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "retry_legal_original_upload_verification",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_document_id: parsedDocumentId,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_reason: parsed.data.reason,
          p_request_id: input.metadata.requestId,
          p_upload_session_id: parsedUploadSessionId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertIdentity(parsedDocumentId, parsedUploadSessionId, row);
    return Object.freeze({
      auditEventId: row.audit_event_id,
      documentId: row.document_id,
      job: Object.freeze({ id: row.job_id, status: row.job_status }),
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      sourceJobId: row.source_job_id,
      uploadSessionId: row.upload_session_id,
    });
  }
}
