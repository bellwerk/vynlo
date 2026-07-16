import { z } from "zod";

import type {
  VerticalSliceCommandInput,
  VerticalSliceCommandMetadata,
} from "./vertical-slice-api";

const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const vinSchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-HJ-NPR-Z0-9]{17}$/u);
const modelYearSchema = z.number().int().min(1886).max(2200);
const jobStatusSchema = z.enum([
  "queued",
  "running",
  "retry_wait",
  "succeeded",
  "dead_letter",
  "cancelled",
]);
const requestStatusSchema = z.enum([
  "queued",
  "running",
  "retry_wait",
  "succeeded",
  "dead_letter",
  "cancelled",
  "consumed",
]);
const aggregateVersionSchema = z
  .number()
  .int()
  .min(1)
  .max(Number.MAX_SAFE_INTEGER);
const nullableText = (maximum: number) =>
  z.string().min(1).max(maximum).nullable();

const requestBodySchema = z
  .object({
    modelYear: modelYearSchema.nullable().optional(),
    vin: vinSchema,
  })
  .strict();
const retryBodySchema = z
  .object({ reason: z.string().trim().min(1).max(2_000) })
  .strict();
const reviewBodySchema = z
  .object({
    decision: z.enum([
      "reuse_existing_vehicle",
      "reacquire_existing_vehicle",
      "override_open_duplicate",
    ]),
    reason: z.string().trim().min(1).max(2_000),
  })
  .strict();

const requestResultRowSchema = z
  .object({
    aggregate_version: aggregateVersionSchema,
    audit_event_id: uuidSchema,
    duplicate_candidate_count: z.number().int().min(0),
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    vin_decode_request_id: uuidSchema,
  })
  .strict();
const retryResultRowSchema = z
  .object({
    aggregate_version: aggregateVersionSchema,
    audit_event_id: uuidSchema,
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    vin_decode_request_id: uuidSchema,
  })
  .strict();
const reviewResultRowSchema = z
  .object({
    aggregate_version: aggregateVersionSchema,
    approved_for_intake: z.boolean(),
    audit_event_id: uuidSchema,
    decision: reviewBodySchema.shape.decision,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
    vehicle_id: uuidSchema,
    vin_decode_request_id: uuidSchema,
    vin_duplicate_review_id: uuidSchema,
  })
  .strict();

const duplicateCandidateRowSchema = z
  .object({
    id: uuidSchema,
    inventory_status: z
      .enum(["draft", "active", "pending", "closed", "archived"])
      .nullable(),
    inventory_unit_id: uuidSchema.nullable(),
    kind: z.enum(["open_inventory", "historical_inventory", "vehicle_only"]),
    observed_at: z.iso.datetime({ offset: true }),
    stock_number: nullableText(200),
    vehicle_id: uuidSchema,
  })
  .strict();
const duplicateReviewRowSchema = z
  .object({
    decision: reviewBodySchema.shape.decision,
    id: uuidSchema,
    reason: z.string().min(1).max(2_000),
    reviewed_at: z.iso.datetime({ offset: true }),
    vehicle_id: uuidSchema,
  })
  .strict();
const statusResultRowSchema = z
  .object({
    aggregate_version: aggregateVersionSchema,
    attempt_count: z.number().int().min(0),
    body_type: nullableText(200),
    completed_at: z.iso.datetime({ offset: true }).nullable(),
    cylinders: z.number().int().min(1).max(64).nullable(),
    decoded_at: z.iso.datetime({ offset: true }).nullable(),
    drivetrain: nullableText(100),
    duplicate_candidates: z.array(duplicateCandidateRowSchema),
    duplicate_review: duplicateReviewRowSchema.nullable(),
    engine_liters: z
      .string()
      .regex(/^\d{1,2}(?:\.\d{1,3})?$/u)
      .nullable(),
    fuel_type: nullableText(100),
    horsepower: z.number().int().min(1).max(10_000).nullable(),
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    last_error_classification: z
      .enum([
        "transient",
        "rate_limited",
        "permanent",
        "validation",
        "permission",
        "provider_auth",
        "unknown",
        "lease_expired",
      ])
      .nullable(),
    last_error_code: nullableText(120),
    make: nullableText(100),
    maximum_attempts: z.number().int().min(1).max(32),
    model: nullableText(100),
    model_year: modelYearSchema.nullable(),
    model_year_hint: modelYearSchema.nullable(),
    provider_key: z.literal("nhtsa_vpic").nullable(),
    provider_version: nullableText(100),
    raw_result_reference: uuidSchema.nullable(),
    requested_at: z.iso.datetime({ offset: true }),
    retry_at: z.iso.datetime({ offset: true }).nullable(),
    retryable: z.boolean(),
    review_required: z.boolean(),
    status: requestStatusSchema,
    transmission: nullableText(200),
    trim_name: nullableText(200),
    vin: vinSchema,
    vin_decode_request_id: uuidSchema,
    warnings: z.array(z.string().max(1_000)),
  })
  .strict();

export type VinDecodeRpcFunctionName =
  | "request_vin_decode_job"
  | "get_vin_decode_request"
  | "retry_vin_decode_job"
  | "review_vin_duplicate_request";

export interface VinDecodeRpcGateway {
  invoke(request: {
    readonly accessToken: string;
    readonly functionName: VinDecodeRpcFunctionName;
    readonly parameters: Readonly<Record<string, unknown>>;
  }): Promise<unknown>;
}

export type VinDecodeValidationErrorCode =
  "invalid_request_body" | "invalid_vin_decode_request_id";

export class VinDecodeValidationError extends Error {
  readonly code: VinDecodeValidationErrorCode;

  constructor(code: VinDecodeValidationErrorCode) {
    super("The VIN decode request is invalid.");
    this.name = "VinDecodeValidationError";
    this.code = code;
  }
}

export class VinDecodeRpcContractError extends Error {
  constructor() {
    super("The VIN data store returned an invalid response.");
    this.name = "VinDecodeRpcContractError";
  }
}

export interface VinDecodeRequestResult {
  readonly aggregateVersion: number;
  readonly auditEventId: string;
  readonly duplicateCandidateCount: number;
  readonly jobId: string;
  readonly jobStatus: z.infer<typeof jobStatusSchema>;
  readonly outboxEventId: string;
  readonly replayed: boolean;
  readonly vinDecodeRequestId: string;
}

export interface VinDecodeReadMetadata {
  readonly accessToken: string;
  readonly workspaceId: string;
}

export interface VinDecodeStatusInput {
  readonly metadata: VinDecodeReadMetadata;
  readonly vinDecodeRequestId: string;
}

export interface VinDecodeEntityCommandInput extends VerticalSliceCommandInput {
  readonly vinDecodeRequestId: string;
}

export interface VinDecodeStatusResult {
  readonly aggregateVersion: number;
  readonly completedAt: string | null;
  readonly duplicateCandidates: readonly {
    readonly id: string;
    readonly inventoryStatus: string | null;
    readonly inventoryUnitId: string | null;
    readonly kind: "open_inventory" | "historical_inventory" | "vehicle_only";
    readonly observedAt: string;
    readonly stockNumber: string | null;
    readonly vehicleId: string;
  }[];
  readonly duplicateReview: {
    readonly decision:
      | "reuse_existing_vehicle"
      | "reacquire_existing_vehicle"
      | "override_open_duplicate";
    readonly id: string;
    readonly reason: string;
    readonly reviewedAt: string;
    readonly vehicleId: string;
  } | null;
  readonly job: {
    readonly attemptCount: number;
    readonly id: string;
    readonly lastErrorClassification: string | null;
    readonly lastErrorCode: string | null;
    readonly maximumAttempts: number;
    readonly retryAt: string | null;
    readonly retryable: boolean;
    readonly reviewRequired: boolean;
    readonly status: z.infer<typeof jobStatusSchema>;
  };
  readonly modelYearHint: number | null;
  readonly provider: {
    readonly decodedAt: string;
    readonly key: "nhtsa_vpic";
    readonly rawResultReference: string;
    readonly version: string;
    readonly warnings: readonly string[];
  } | null;
  readonly requestedAt: string;
  readonly status: z.infer<typeof requestStatusSchema>;
  readonly suggestions: {
    readonly bodyType: string | null;
    readonly cylinders: number | null;
    readonly drivetrain: string | null;
    readonly engineLiters: string | null;
    readonly fuelType: string | null;
    readonly horsepower: number | null;
    readonly make: string | null;
    readonly model: string | null;
    readonly modelYear: number | null;
    readonly transmission: string | null;
    readonly trimName: string | null;
  } | null;
  readonly vin: string;
  readonly vinDecodeRequestId: string;
}

function parseBody<T>(schema: z.ZodType<T>, body: unknown): T {
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    throw new VinDecodeValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseRequestId(value: string): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new VinDecodeValidationError("invalid_vin_decode_request_id");
  }
  return parsed.data;
}

function parseOne<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = z.array(schema).length(1).safeParse(value);
  if (!parsed.success) {
    throw new VinDecodeRpcContractError();
  }
  return parsed.data[0]!;
}

function assertEchoedRequestId(
  expectedRequestId: string,
  actualRequestId: string,
): void {
  if (actualRequestId !== expectedRequestId) {
    throw new VinDecodeRpcContractError();
  }
}

function commandParameters(
  metadata: VerticalSliceCommandMetadata,
): Readonly<Record<string, unknown>> {
  return {
    p_correlation_id: metadata.correlationId,
    p_idempotency_key: metadata.idempotencyKey,
    p_request_id: metadata.requestId,
    p_workspace_id: metadata.workspaceId,
  };
}

export class VinDecodeApplicationService {
  readonly #gateway: VinDecodeRpcGateway;

  constructor(gateway: VinDecodeRpcGateway) {
    this.#gateway = gateway;
  }

  async requestDecode(
    input: VerticalSliceCommandInput,
  ): Promise<VinDecodeRequestResult> {
    const body = parseBody(requestBodySchema, input.body);
    const row = parseOne(
      requestResultRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "request_vin_decode_job",
        parameters: {
          ...commandParameters(input.metadata),
          p_model_year_hint: body.modelYear ?? null,
          p_vin: body.vin,
        },
      }),
    );
    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      duplicateCandidateCount: row.duplicate_candidate_count,
      jobId: row.job_id,
      jobStatus: row.job_status,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      vinDecodeRequestId: row.vin_decode_request_id,
    };
  }

  async getStatus(input: VinDecodeStatusInput): Promise<VinDecodeStatusResult> {
    const vinDecodeRequestId = parseRequestId(input.vinDecodeRequestId);
    const row = parseOne(
      statusResultRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "get_vin_decode_request",
        parameters: {
          p_vin_decode_request_id: vinDecodeRequestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    assertEchoedRequestId(vinDecodeRequestId, row.vin_decode_request_id);
    const hasResult = row.raw_result_reference !== null;
    return {
      aggregateVersion: row.aggregate_version,
      completedAt: row.completed_at,
      duplicateCandidates: row.duplicate_candidates.map((candidate) => ({
        id: candidate.id,
        inventoryStatus: candidate.inventory_status,
        inventoryUnitId: candidate.inventory_unit_id,
        kind: candidate.kind,
        observedAt: candidate.observed_at,
        stockNumber: candidate.stock_number,
        vehicleId: candidate.vehicle_id,
      })),
      duplicateReview:
        row.duplicate_review === null
          ? null
          : {
              decision: row.duplicate_review.decision,
              id: row.duplicate_review.id,
              reason: row.duplicate_review.reason,
              reviewedAt: row.duplicate_review.reviewed_at,
              vehicleId: row.duplicate_review.vehicle_id,
            },
      job: {
        attemptCount: row.attempt_count,
        id: row.job_id,
        lastErrorClassification: row.last_error_classification,
        lastErrorCode: row.last_error_code,
        maximumAttempts: row.maximum_attempts,
        retryAt: row.retry_at,
        retryable: row.retryable,
        reviewRequired: row.review_required,
        status: row.job_status,
      },
      modelYearHint: row.model_year_hint,
      provider: hasResult
        ? {
            decodedAt: row.decoded_at!,
            key: row.provider_key!,
            rawResultReference: row.raw_result_reference!,
            version: row.provider_version!,
            warnings: row.warnings,
          }
        : null,
      requestedAt: row.requested_at,
      status: row.status,
      suggestions: hasResult
        ? {
            bodyType: row.body_type,
            cylinders: row.cylinders,
            drivetrain: row.drivetrain,
            engineLiters: row.engine_liters,
            fuelType: row.fuel_type,
            horsepower: row.horsepower,
            make: row.make,
            model: row.model,
            modelYear: row.model_year,
            transmission: row.transmission,
            trimName: row.trim_name,
          }
        : null,
      vin: row.vin,
      vinDecodeRequestId: row.vin_decode_request_id,
    };
  }

  async retry(input: VinDecodeEntityCommandInput) {
    const vinDecodeRequestId = parseRequestId(input.vinDecodeRequestId);
    const body = parseBody(retryBodySchema, input.body);
    const row = parseOne(
      retryResultRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "retry_vin_decode_job",
        parameters: {
          ...commandParameters(input.metadata),
          p_reason: body.reason,
          p_vin_decode_request_id: vinDecodeRequestId,
        },
      }),
    );
    assertEchoedRequestId(vinDecodeRequestId, row.vin_decode_request_id);
    return {
      aggregateVersion: row.aggregate_version,
      auditEventId: row.audit_event_id,
      jobId: row.job_id,
      jobStatus: row.job_status,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      vinDecodeRequestId: row.vin_decode_request_id,
    };
  }

  async reviewDuplicate(input: VinDecodeEntityCommandInput) {
    const vinDecodeRequestId = parseRequestId(input.vinDecodeRequestId);
    const body = parseBody(reviewBodySchema, input.body);
    const row = parseOne(
      reviewResultRowSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "review_vin_duplicate_request",
        parameters: {
          ...commandParameters(input.metadata),
          p_decision: body.decision,
          p_reason: body.reason,
          p_vin_decode_request_id: vinDecodeRequestId,
        },
      }),
    );
    assertEchoedRequestId(vinDecodeRequestId, row.vin_decode_request_id);
    return {
      aggregateVersion: row.aggregate_version,
      approvedForIntake: row.approved_for_intake,
      auditEventId: row.audit_event_id,
      decision: row.decision,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
      vehicleId: row.vehicle_id,
      vinDecodeRequestId: row.vin_decode_request_id,
      vinDuplicateReviewId: row.vin_duplicate_review_id,
    };
  }
}
