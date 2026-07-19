import {
  MediaPolicyError,
  normalizeVehiclePhotoUploadIntent,
} from "@vynlo/media";
import { z } from "zod";

import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const positiveVersionSchema = z
  .number()
  .int()
  .min(1)
  .max(Number.MAX_SAFE_INTEGER);
const jobStatusSchema = z.enum([
  "queued",
  "running",
  "retry_wait",
  "succeeded",
  "dead_letter",
  "cancelled",
]);
const sha256Schema = z.string().regex(/^[a-f0-9]{64}$/u);
const managedMediaKindSchema = z.enum([
  "attachment",
  "legal_document",
  "signed_document",
  "vehicle_photo",
]);
const mimeTypeSchema = z.enum([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]);

const createUploadBodySchema = z
  .object({
    byteSize: z.number().int().min(1).max(20_000_000),
    checksumSha256: sha256Schema,
    filename: z.string().trim().min(1).max(255),
    mimeType: mimeTypeSchema,
  })
  .strict();
const completeUploadBodySchema = z
  .object({ uploadSessionId: uuidSchema })
  .strict();
const reprocessBodySchema = z
  .object({
    expectedVersion: positiveVersionSchema,
    reason: z.string().trim().min(1).max(1_000),
  })
  .strict();
const reorderBodySchema = z
  .object({
    expectedCollectionVersion: positiveVersionSchema,
    orderedMediaIds: z.array(uuidSchema).min(1).max(50),
  })
  .strict()
  .superRefine((body, context) => {
    if (new Set(body.orderedMediaIds).size !== body.orderedMediaIds.length) {
      context.addIssue({ code: "custom", message: "duplicate_media_id" });
    }
  });
const setCoverBodySchema = z
  .object({ expectedCollectionVersion: positiveVersionSchema })
  .strict();
const downloadBodySchema = z
  .object({ expiresInSeconds: z.number().int().min(30).max(300) })
  .strict();
const captionBodySchema = z
  .object({
    caption: z
      .string()
      .trim()
      .min(1)
      .max(500)
      .refine((value) => !/[\u0000-\u001f\u007f]/u.test(value))
      .nullable(),
    expectedVersion: positiveVersionSchema,
  })
  .strict();
const archiveBodySchema = z
  .object({
    expectedCollectionVersion: positiveVersionSchema,
    expectedMediaVersion: positiveVersionSchema,
    reason: z
      .string()
      .trim()
      .min(1)
      .max(1_000)
      .refine((value) => !/[\u0000-\u001f\u007f]/u.test(value)),
  })
  .strict();
const retryUploadVerificationBodySchema = z
  .object({ reason: z.string().trim().min(1).max(2_000) })
  .strict();

const vehicleMediaFileSchema = z
  .object({
    byteSize: z.number().int().min(1).max(Number.MAX_SAFE_INTEGER),
    checksumSha256: sha256Schema,
    createdAt: z.iso.datetime({ offset: true }),
    fileClass: z.enum(["vehicle_photo_raw", "vehicle_photo_derivative"]),
    height: z.number().int().positive().nullable(),
    id: uuidSchema,
    metadataStripped: z.boolean(),
    mimeType: z.string().min(3).max(120),
    processingRunId: uuidSchema.nullable(),
    status: z.enum(["available", "retired"]),
    variant: z.enum([
      "raw_original",
      "normalized_master",
      "website_1080",
      "thumbnail_640",
      "thumbnail_320",
    ]),
    width: z.number().int().positive().nullable(),
  })
  .strict()
  .superRefine((file, context) => {
    if ((file.width === null) !== (file.height === null)) {
      context.addIssue({ code: "custom", message: "invalid_dimensions" });
    }
    if (
      (file.fileClass === "vehicle_photo_raw") !==
      (file.variant === "raw_original")
    ) {
      context.addIssue({ code: "custom", message: "invalid_file_variant" });
    }
  });
const vehicleMediaAssetSchema = z
  .object({
    archivedAt: z.iso.datetime({ offset: true }).nullable(),
    caption: z.string().min(1).max(500).nullable(),
    collectionVersion: positiveVersionSchema,
    createdAt: z.iso.datetime({ offset: true }),
    files: z.array(vehicleMediaFileSchema).max(5),
    id: uuidSchema,
    inventoryUnitId: uuidSchema,
    isCover: z.boolean(),
    mediaVersion: positiveVersionSchema,
    processingProfile: z
      .object({
        checksumSha256: sha256Schema,
        id: uuidSchema,
        version: positiveVersionSchema,
      })
      .strict(),
    sortOrder: z.number().int().min(0).max(49),
    status: z.enum([
      "awaiting_upload",
      "quarantined",
      "processing",
      "ready",
      "failed",
      "archived",
    ]),
    updatedAt: z.iso.datetime({ offset: true }),
  })
  .strict()
  .superRefine((asset, context) => {
    if (
      (asset.status === "archived") !== (asset.archivedAt !== null) ||
      (asset.status === "archived" && asset.isCover)
    ) {
      context.addIssue({ code: "custom", message: "invalid_archive_state" });
    }
    const fileIds = asset.files.map((file) => file.id);
    if (new Set(fileIds).size !== fileIds.length) {
      context.addIssue({ code: "custom", message: "duplicate_file_id" });
    }
  });
const vehicleMediaListRowSchema = z
  .object({
    collection_version: positiveVersionSchema,
    inventory_unit_id: uuidSchema,
    media_items: z.array(vehicleMediaAssetSchema).max(50),
  })
  .strict();
const vehicleMediaReadRowSchema = z
  .object({ media: vehicleMediaAssetSchema })
  .strict();

const createUploadRowSchema = z
  .object({
    aggregate_version: positiveVersionSchema,
    audit_event_id: uuidSchema,
    collection_version: positiveVersionSchema,
    expires_at: z.iso.datetime({ offset: true }),
    media_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    upload_bucket: z.literal("media-private"),
    upload_object_key: z.string().min(1).max(1_000),
    upload_session_id: uuidSchema,
  })
  .strict();
const verificationRowSchema = z
  .object({
    aggregate_version: positiveVersionSchema,
    audit_event_id: uuidSchema,
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    media_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    upload_session_id: uuidSchema,
  })
  .strict();
const uploadVerificationProjectedStatusSchema = z.enum([
  "awaiting_upload",
  "queued",
  "running",
  "retry_wait",
  "dead_letter",
  "rejected",
  "completed",
]);
const uploadVerificationErrorClassificationSchema = z.enum([
  "transient",
  "rate_limited",
  "permanent",
  "validation",
  "permission",
  "provider_auth",
  "unknown",
  "lease_expired",
]);
const uploadVerificationStatusRowSchema = z
  .object({
    attempt_count: z.number().int().min(0),
    completed_at: z.iso.datetime({ offset: true }).nullable(),
    error_classification:
      uploadVerificationErrorClassificationSchema.nullable(),
    error_code: z
      .string()
      .regex(/^[a-z][a-z0-9_.-]{0,119}$/u)
      .nullable(),
    job_id: uuidSchema.nullable(),
    maximum_attempts: z.number().int().min(1).max(32).nullable(),
    media_id: uuidSchema,
    retry_at: z.iso.datetime({ offset: true }).nullable(),
    retryable: z.boolean(),
    status: uploadVerificationProjectedStatusSchema,
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
        message: "verification status requires a job",
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
const retryUploadVerificationRowSchema = z
  .object({
    aggregate_version: positiveVersionSchema,
    audit_event_id: uuidSchema,
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    media_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    source_job_id: uuidSchema,
    upload_session_id: uuidSchema,
  })
  .strict();
const reprocessRowSchema = z
  .object({
    aggregate_version: positiveVersionSchema,
    audit_event_id: uuidSchema,
    generation: positiveVersionSchema,
    job_id: uuidSchema,
    media_id: uuidSchema,
    media_status: z.literal("quarantined"),
    outbox_event_id: uuidSchema,
    processing_run_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();
const reorderRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    collection_version: positiveVersionSchema,
    inventory_unit_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();
const setCoverRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    collection_version: positiveVersionSchema,
    cover_media_id: uuidSchema,
    inventory_unit_id: uuidSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();
const downloadRowSchema = z
  .object({
    authorization_expires_at: z.iso.datetime({ offset: true }),
    authorization_id: uuidSchema,
    byte_size: z.number().int().min(1).max(Number.MAX_SAFE_INTEGER),
    checksum_sha256: sha256Schema,
    audit_event_id: uuidSchema,
    media_file_id: uuidSchema,
    media_kind: managedMediaKindSchema,
    mime_type: z.string().min(3).max(200),
    replayed: z.boolean(),
  })
  .strict();
const captionRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    caption: z.string().min(1).max(500).nullable(),
    media_id: uuidSchema,
    media_version: positiveVersionSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();
const archiveRowSchema = z
  .object({
    audit_event_id: uuidSchema,
    collection_version: positiveVersionSchema,
    inventory_unit_id: uuidSchema,
    media_id: uuidSchema,
    media_status: z.literal("archived"),
    media_version: positiveVersionSchema,
    outbox_event_id: uuidSchema,
    promoted_cover_media_id: uuidSchema.nullable(),
    replayed: z.boolean(),
  })
  .strict();

export type M2MediaRpcFunctionName =
  | "archive_vehicle_media"
  | "authorize_managed_media_download"
  | "create_vehicle_photo_upload_session"
  | "get_vehicle_photo_upload_status"
  | "get_vehicle_media_asset"
  | "list_inventory_vehicle_media"
  | "reorder_inventory_media"
  | "reprocess_vehicle_photo"
  | "request_vehicle_photo_upload_verification"
  | "retry_vehicle_photo_upload_verification"
  | "set_inventory_media_cover"
  | "update_vehicle_media_caption";

export type M2MediaValidationErrorCode =
  | "invalid_inventory_unit_id"
  | "invalid_media_file_id"
  | "invalid_media_id"
  | "invalid_request_body";

export class M2MediaValidationError extends Error {
  readonly code: M2MediaValidationErrorCode;

  constructor(code: M2MediaValidationErrorCode) {
    super("The media command input is invalid.");
    this.name = "M2MediaValidationError";
    this.code = code;
  }
}

export class M2MediaRpcContractError extends Error {
  constructor() {
    super("The media data store returned an invalid response.");
    this.name = "M2MediaRpcContractError";
  }
}

export interface M2MediaEntityCommandInput extends VerticalSliceCommandInput {
  readonly mediaId: string;
}

export interface M2MediaUploadSessionCommandInput extends M2MediaEntityCommandInput {
  readonly uploadSessionId: string;
}

export interface M2MediaInventoryCommandInput extends VerticalSliceCommandInput {
  readonly inventoryUnitId: string;
}

export interface M2MediaSetCoverCommandInput extends M2MediaInventoryCommandInput {
  readonly mediaId: string;
}

export interface M2MediaDownloadInput extends VerticalSliceCommandInput {
  readonly mediaFileId: string;
}

export interface M2MediaQueryInput {
  readonly accessToken: string;
  readonly workspaceId: string;
}

export interface M2MediaEntityQueryInput extends M2MediaQueryInput {
  readonly mediaId: string;
}

export interface M2MediaUploadSessionQueryInput extends M2MediaEntityQueryInput {
  readonly uploadSessionId: string;
}

export interface M2MediaInventoryQueryInput extends M2MediaQueryInput {
  readonly inventoryUnitId: string;
}

export type VehicleMediaAsset = z.infer<typeof vehicleMediaAssetSchema>;

export interface M2MediaDownloadGrantPort {
  issue(input: {
    readonly authorizationExpiresAt: string;
    readonly authorizationId: string;
    readonly byteSize: number;
    readonly checksumSha256: string;
    readonly expiresInSeconds: number;
    readonly mediaFileId: string;
    readonly mediaKind: z.infer<typeof managedMediaKindSchema>;
    readonly mimeType: string;
    readonly workspaceId: string;
  }): Promise<{
    readonly expiresAt: string;
    readonly url: string;
  }>;
}

function parseId(value: string, code: M2MediaValidationErrorCode): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) throw new M2MediaValidationError(code);
  return parsed.data;
}

function parseBody<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) throw new M2MediaValidationError("invalid_request_body");
  return parsed.data;
}

function parseOne<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = z.array(schema).length(1).safeParse(value);
  if (!parsed.success) throw new M2MediaRpcContractError();
  return parsed.data[0]!;
}

function commandParameters(
  input: VerticalSliceCommandInput,
): Readonly<Record<string, unknown>> {
  return {
    p_correlation_id: input.metadata.correlationId,
    p_idempotency_key: input.metadata.idempotencyKey,
    p_request_id: input.metadata.requestId,
    p_workspace_id: input.metadata.workspaceId,
  };
}

export class M2MediaApplicationService {
  readonly #downloadGrants: M2MediaDownloadGrantPort | undefined;
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(
    gateway: AuthenticatedRpcGateway,
    downloadGrants?: M2MediaDownloadGrantPort,
  ) {
    this.#gateway = gateway;
    this.#downloadGrants = downloadGrants;
  }

  async getAsset(input: M2MediaEntityQueryInput): Promise<VehicleMediaAsset> {
    const workspaceId = parseId(input.workspaceId, "invalid_request_body");
    const mediaId = parseId(input.mediaId, "invalid_media_id");
    const row = parseOne(
      vehicleMediaReadRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "get_vehicle_media_asset",
        parameters: {
          p_media_id: mediaId,
          p_workspace_id: workspaceId,
        },
      }),
    );
    if (row.media.id !== mediaId) throw new M2MediaRpcContractError();
    return row.media;
  }

  async listInventoryMedia(input: M2MediaInventoryQueryInput) {
    const workspaceId = parseId(input.workspaceId, "invalid_request_body");
    const inventoryUnitId = parseId(
      input.inventoryUnitId,
      "invalid_inventory_unit_id",
    );
    const row = parseOne(
      vehicleMediaListRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "list_inventory_vehicle_media",
        parameters: {
          p_inventory_unit_id: inventoryUnitId,
          p_workspace_id: workspaceId,
        },
      }),
    );
    if (
      row.inventory_unit_id !== inventoryUnitId ||
      row.media_items.some(
        (media) =>
          media.inventoryUnitId !== inventoryUnitId ||
          media.collectionVersion !== row.collection_version ||
          media.status === "archived",
      )
    ) {
      throw new M2MediaRpcContractError();
    }
    return {
      collectionVersion: row.collection_version,
      inventoryUnitId: row.inventory_unit_id,
      items: row.media_items,
    };
  }

  async createUploadIntent(input: M2MediaInventoryCommandInput) {
    const inventoryUnitId = parseId(
      input.inventoryUnitId,
      "invalid_inventory_unit_id",
    );
    const body = parseBody(createUploadBodySchema, input.body);
    let intent: ReturnType<typeof normalizeVehiclePhotoUploadIntent>;
    try {
      intent = normalizeVehiclePhotoUploadIntent({
        checksumSha256: body.checksumSha256,
        declaredMimeType: body.mimeType,
        filename: body.filename,
        sizeBytes: body.byteSize,
      });
    } catch (error) {
      if (error instanceof MediaPolicyError) {
        throw new M2MediaValidationError("invalid_request_body");
      }
      throw error;
    }
    const row = parseOne(
      createUploadRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_vehicle_photo_upload_session",
        parameters: {
          ...commandParameters(input),
          p_byte_size: intent.sizeBytes,
          p_checksum_sha256: intent.checksumSha256,
          p_filename: intent.filename,
          p_inventory_unit_id: inventoryUnitId,
          p_mime_type: intent.declaredMimeType,
        },
      }),
    );
    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      collectionVersion: row.collection_version,
      mediaId: row.media_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      upload: {
        bucket: row.upload_bucket,
        expiresAt: row.expires_at,
        objectKey: row.upload_object_key,
        requiresAuthenticatedSession: true as const,
      },
      uploadSessionId: row.upload_session_id,
    };
  }

  async requestUploadVerification(input: M2MediaEntityCommandInput) {
    const mediaId = parseId(input.mediaId, "invalid_media_id");
    const body = parseBody(completeUploadBodySchema, input.body);
    const row = parseOne(
      verificationRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "request_vehicle_photo_upload_verification",
        parameters: {
          ...commandParameters(input),
          p_media_id: mediaId,
          p_upload_session_id: body.uploadSessionId,
        },
      }),
    );
    if (
      row.media_id !== mediaId ||
      row.upload_session_id !== body.uploadSessionId
    ) {
      throw new M2MediaRpcContractError();
    }
    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      jobId: row.job_id,
      jobStatus: row.job_status,
      mediaId: row.media_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      uploadSessionId: row.upload_session_id,
    };
  }

  async getUploadVerificationStatus(input: M2MediaUploadSessionQueryInput) {
    const workspaceId = parseId(input.workspaceId, "invalid_request_body");
    const mediaId = parseId(input.mediaId, "invalid_media_id");
    const uploadSessionId = parseId(
      input.uploadSessionId,
      "invalid_request_body",
    );
    const row = parseOne(
      uploadVerificationStatusRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "get_vehicle_photo_upload_status",
        parameters: {
          p_media_id: mediaId,
          p_upload_session_id: uploadSessionId,
          p_workspace_id: workspaceId,
        },
      }),
    );
    if (row.media_id !== mediaId || row.upload_session_id !== uploadSessionId) {
      throw new M2MediaRpcContractError();
    }
    return {
      completedAt: row.completed_at,
      failure:
        row.error_classification === null && row.error_code === null
          ? null
          : {
              classification: row.error_classification,
              code: row.error_code,
            },
      job:
        row.job_id === null
          ? null
          : {
              attemptCount: row.attempt_count,
              id: row.job_id,
              maximumAttempts: row.maximum_attempts!,
              retryAt: row.retry_at,
            },
      mediaId: row.media_id,
      retryable: row.retryable,
      status: row.status,
      uploadSessionId: row.upload_session_id,
    };
  }

  async retryUploadVerification(input: M2MediaUploadSessionCommandInput) {
    const mediaId = parseId(input.mediaId, "invalid_media_id");
    const uploadSessionId = parseId(
      input.uploadSessionId,
      "invalid_request_body",
    );
    const body = parseBody(retryUploadVerificationBodySchema, input.body);
    const row = parseOne(
      retryUploadVerificationRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "retry_vehicle_photo_upload_verification",
        parameters: {
          ...commandParameters(input),
          p_media_id: mediaId,
          p_reason: body.reason,
          p_upload_session_id: uploadSessionId,
        },
      }),
    );
    if (row.media_id !== mediaId || row.upload_session_id !== uploadSessionId) {
      throw new M2MediaRpcContractError();
    }
    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      jobId: row.job_id,
      jobStatus: row.job_status,
      mediaId: row.media_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      sourceJobId: row.source_job_id,
      uploadSessionId: row.upload_session_id,
    };
  }

  async reprocess(input: M2MediaEntityCommandInput) {
    const mediaId = parseId(input.mediaId, "invalid_media_id");
    const body = parseBody(reprocessBodySchema, input.body);
    const row = parseOne(
      reprocessRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "reprocess_vehicle_photo",
        parameters: {
          ...commandParameters(input),
          p_expected_version: body.expectedVersion,
          p_media_id: mediaId,
          p_reason: body.reason,
        },
      }),
    );
    if (row.media_id !== mediaId) throw new M2MediaRpcContractError();
    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      generation: row.generation,
      jobId: row.job_id,
      mediaId: row.media_id,
      mediaStatus: row.media_status,
      outboxEventId: row.outbox_event_id,
      processingRunId: row.processing_run_id,
      replayed: row.replayed,
    };
  }

  async reorder(input: M2MediaInventoryCommandInput) {
    const inventoryUnitId = parseId(
      input.inventoryUnitId,
      "invalid_inventory_unit_id",
    );
    const body = parseBody(reorderBodySchema, input.body);
    const row = parseOne(
      reorderRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "reorder_inventory_media",
        parameters: {
          ...commandParameters(input),
          p_expected_collection_version: body.expectedCollectionVersion,
          p_inventory_unit_id: inventoryUnitId,
          p_ordered_media_ids: body.orderedMediaIds,
        },
      }),
    );
    if (row.inventory_unit_id !== inventoryUnitId) {
      throw new M2MediaRpcContractError();
    }
    return {
      auditEventId: row.audit_event_id,
      collectionVersion: row.collection_version,
      inventoryUnitId: row.inventory_unit_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
    };
  }

  async setCover(input: M2MediaSetCoverCommandInput) {
    const inventoryUnitId = parseId(
      input.inventoryUnitId,
      "invalid_inventory_unit_id",
    );
    const mediaId = parseId(input.mediaId, "invalid_media_id");
    const body = parseBody(setCoverBodySchema, input.body);
    const row = parseOne(
      setCoverRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "set_inventory_media_cover",
        parameters: {
          ...commandParameters(input),
          p_expected_collection_version: body.expectedCollectionVersion,
          p_inventory_unit_id: inventoryUnitId,
          p_media_id: mediaId,
        },
      }),
    );
    if (
      row.inventory_unit_id !== inventoryUnitId ||
      row.cover_media_id !== mediaId
    ) {
      throw new M2MediaRpcContractError();
    }
    return {
      auditEventId: row.audit_event_id,
      collectionVersion: row.collection_version,
      coverMediaId: row.cover_media_id,
      inventoryUnitId: row.inventory_unit_id,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
    };
  }

  async updateCaption(input: M2MediaEntityCommandInput) {
    const mediaId = parseId(input.mediaId, "invalid_media_id");
    const body = parseBody(captionBodySchema, input.body);
    const row = parseOne(
      captionRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "update_vehicle_media_caption",
        parameters: {
          ...commandParameters(input),
          p_caption: body.caption,
          p_expected_media_version: body.expectedVersion,
          p_media_id: mediaId,
        },
      }),
    );
    if (row.media_id !== mediaId) throw new M2MediaRpcContractError();
    return {
      auditEventId: row.audit_event_id,
      caption: row.caption,
      mediaId: row.media_id,
      mediaVersion: row.media_version,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
    };
  }

  async archive(input: M2MediaEntityCommandInput) {
    const mediaId = parseId(input.mediaId, "invalid_media_id");
    const body = parseBody(archiveBodySchema, input.body);
    const row = parseOne(
      archiveRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "archive_vehicle_media",
        parameters: {
          ...commandParameters(input),
          p_expected_collection_version: body.expectedCollectionVersion,
          p_expected_media_version: body.expectedMediaVersion,
          p_media_id: mediaId,
          p_reason: body.reason,
        },
      }),
    );
    if (row.media_id !== mediaId) throw new M2MediaRpcContractError();
    return {
      auditEventId: row.audit_event_id,
      collectionVersion: row.collection_version,
      inventoryUnitId: row.inventory_unit_id,
      mediaId: row.media_id,
      mediaStatus: row.media_status,
      mediaVersion: row.media_version,
      outboxEventId: row.outbox_event_id,
      promotedCoverMediaId: row.promoted_cover_media_id,
      replayed: row.replayed,
    };
  }

  async authorizeDownload(input: M2MediaDownloadInput) {
    const workspaceId = parseId(
      input.metadata.workspaceId,
      "invalid_request_body",
    );
    const mediaFileId = parseId(input.mediaFileId, "invalid_media_file_id");
    const body = parseBody(downloadBodySchema, input.body);
    const row = parseOne(
      downloadRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "authorize_managed_media_download",
        parameters: {
          ...commandParameters(input),
          p_expires_in_seconds: body.expiresInSeconds,
          p_media_file_id: mediaFileId,
          p_workspace_id: workspaceId,
        },
      }),
    );
    if (row.media_file_id !== mediaFileId) {
      throw new M2MediaRpcContractError();
    }
    if (this.#downloadGrants === undefined) {
      throw new M2MediaRpcContractError();
    }
    const grant = await this.#downloadGrants.issue({
      authorizationExpiresAt: row.authorization_expires_at,
      authorizationId: row.authorization_id,
      byteSize: row.byte_size,
      checksumSha256: row.checksum_sha256,
      expiresInSeconds: body.expiresInSeconds,
      mediaFileId: row.media_file_id,
      mediaKind: row.media_kind,
      mimeType: row.mime_type,
      workspaceId,
    });
    return {
      auditEventId: row.audit_event_id,
      byteSize: row.byte_size,
      checksumSha256: row.checksum_sha256,
      download: grant,
      mediaFileId: row.media_file_id,
      mediaKind: row.media_kind,
      mimeType: row.mime_type,
      replayed: row.replayed,
    };
  }
}
