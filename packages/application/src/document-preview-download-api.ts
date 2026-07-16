import { z } from "zod";

import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const uuidSchema = z.string().uuid();
const sha256Schema = z.string().regex(/^[a-f0-9]{64}$/u);
const bodySchema = z
  .object({
    expiresInSeconds: z.number().int().min(30).max(300),
  })
  .strict();
const authorizationRowSchema = z
  .object({
    artifact_id: uuidSchema,
    audit_event_id: uuidSchema,
    authorization_expires_at: z.string().datetime({ offset: true }),
    authorization_id: uuidSchema,
    byte_size: z.number().int().min(1).max(10_000_000),
    checksum_sha256: sha256Schema,
    document_id: uuidSchema,
    filename: z.literal("preview.html"),
    mime_type: z.literal("text/html; charset=utf-8"),
    replayed: z.boolean(),
  })
  .strict();

export type DocumentPreviewDownloadValidationErrorCode =
  "invalid_preview_artifact_id" | "invalid_request_body";

export class DocumentPreviewDownloadValidationError extends Error {
  readonly code: DocumentPreviewDownloadValidationErrorCode;

  constructor(code: DocumentPreviewDownloadValidationErrorCode) {
    super("The preview download command is invalid.");
    this.name = "DocumentPreviewDownloadValidationError";
    this.code = code;
  }
}

export class DocumentPreviewDownloadRpcContractError extends Error {
  constructor() {
    super("The preview download data store returned an invalid response.");
    this.name = "DocumentPreviewDownloadRpcContractError";
  }
}

export interface DocumentPreviewDownloadGrantPort {
  issue(input: {
    readonly artifactId: string;
    readonly authorizationExpiresAt: string;
    readonly authorizationId: string;
    readonly byteSize: number;
    readonly checksumSha256: string;
    readonly documentId: string;
    readonly expiresInSeconds: number;
    readonly filename: "preview.html";
    readonly mimeType: "text/html; charset=utf-8";
    readonly workspaceId: string;
  }): Promise<{
    readonly expiresAt: string;
    readonly url: string;
  }>;
}

export interface DocumentPreviewDownloadInput extends VerticalSliceCommandInput {
  readonly artifactId: string;
}

function parseArtifactId(value: string): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new DocumentPreviewDownloadValidationError(
      "invalid_preview_artifact_id",
    );
  }
  return parsed.data;
}

function parseBody(value: unknown): z.infer<typeof bodySchema> {
  const parsed = bodySchema.safeParse(value);
  if (!parsed.success) {
    throw new DocumentPreviewDownloadValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseAuthorization(value: unknown) {
  const parsed = z.array(authorizationRowSchema).length(1).safeParse(value);
  if (!parsed.success) throw new DocumentPreviewDownloadRpcContractError();
  return parsed.data[0]!;
}

export class DocumentPreviewDownloadApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;
  readonly #grants: DocumentPreviewDownloadGrantPort;

  constructor(
    gateway: AuthenticatedRpcGateway,
    grants: DocumentPreviewDownloadGrantPort,
  ) {
    this.#gateway = gateway;
    this.#grants = grants;
  }

  async authorize(input: DocumentPreviewDownloadInput) {
    const artifactId = parseArtifactId(input.artifactId);
    const body = parseBody(input.body);
    const row = parseAuthorization(
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "authorize_document_preview_download",
        parameters: {
          p_artifact_id: artifactId,
          p_correlation_id: input.metadata.correlationId,
          p_expires_in_seconds: body.expiresInSeconds,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    if (row.artifact_id !== artifactId) {
      throw new DocumentPreviewDownloadRpcContractError();
    }

    const download = await this.#grants.issue({
      artifactId: row.artifact_id,
      authorizationExpiresAt: row.authorization_expires_at,
      authorizationId: row.authorization_id,
      byteSize: row.byte_size,
      checksumSha256: row.checksum_sha256,
      documentId: row.document_id,
      expiresInSeconds: body.expiresInSeconds,
      filename: row.filename,
      mimeType: row.mime_type,
      workspaceId: input.metadata.workspaceId,
    });

    return Object.freeze({
      artifactId: row.artifact_id,
      auditEventId: row.audit_event_id,
      byteSize: row.byte_size,
      checksumSha256: row.checksum_sha256,
      documentId: row.document_id,
      download,
      filename: row.filename,
      mimeType: row.mime_type,
      replayed: row.replayed,
    });
  }
}
