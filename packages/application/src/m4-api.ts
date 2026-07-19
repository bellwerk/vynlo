import {
  CALCULATION_ENGINE_VERSION,
  CalculationRuntimeError,
  DEFAULT_CALCULATION_LIMITS,
  canonicalJson,
  compileCalculationDefinition,
  runCalculation,
  sha256Hex,
  type CalculationErrorCode,
  type CalculationJson,
  type CalculationLimits,
} from "@vynlo/calculations";
import {
  TAX_ENGINE_VERSION,
  TaxRuntimeError,
  compileTaxPack,
  executeTaxCalculation,
  selectTaxPack,
  type TaxCalculationRequest,
  type TaxErrorCode,
} from "@vynlo/tax";
import { z } from "zod";

import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

/**
 * M4-CFG-AC-004, M4-DOC-AC-003..010, M4-NUM-AC-003,
 * M4-CALC-AC-003..005, M4-TAX-AC-001..005, M4-EXP-AC-001..005.
 *
 * This registry is the only place where the HTTP/application layer names M4
 * database functions. Keeping the names centralized makes contract drift
 * visible to SQL and application tests.
 */
export const M4_RPC = Object.freeze({
  activateCalculationVersion: "m4_transition_artifact_version",
  activateDocumentTemplateVersion: "m4_transition_artifact_version",
  activateDocumentType: "m4_transition_artifact_version",
  activateNumberingVersion: "m4_transition_artifact_version",
  activateTaxPackVersion: "m4_transition_artifact_version",
  approveCalculationVersion: "m4_transition_artifact_version",
  authorizeDocumentFileDownload: "m4_authorize_document_file_download",
  authorizeExportDownload: "m4_authorize_export_download",
  createApprovalRecord: "m4_record_artifact_approval",
  createNumberingDefinitionVersion: "m4_create_numbering_version",
  getDocument: "m4_get_document_detail",
  getExportRun: "m4_get_export_run",
  listApprovalRecords: "m4_list_approval_records",
  listCalculationDefinitions: "m4_list_calculation_definitions",
  listDocumentTypes: "m4_list_document_types",
  listDocuments: "m4_list_documents",
  listExportDefinitions: "m4_list_export_definitions",
  listNumberingDefinitions: "m4_list_numbering_definitions",
  listTaxPacks: "m4_list_tax_packs",
  loadCalculationPreviewConfiguration:
    "m4_load_calculation_preview_configuration",
  loadDealRuntimeInput: "m4_load_deal_runtime_input",
  loadTaxPreviewConfiguration: "m4_load_tax_preview_configuration",
  markDocumentSigned: "m4_mark_document_signed",
  reportDeals: "m4_report_deals",
  reportInventoryAging: "m4_report_inventory_aging",
  reportInventoryGross: "m4_report_inventory_gross",
  reportLeads: "m4_report_leads",
  requestDocumentPreview: "m4_request_document_preview",
  requestExportRun: "m4_request_export_run",
  requestOfficialDocument: "request_official_document",
  retryDocumentRender: "m4_retry_document_render",
  validateDocument: "m4_validate_document",
  voidDocument: "m4_void_document",
} as const);

const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const checksumSchema = z.string().regex(/^[a-f0-9]{64}$/u);
const timestampSchema = z.iso.datetime({ offset: true });
const nullableTimestampSchema = timestampSchema.nullable();
const dateSchema = z.iso.date();
const localeSchema = z
  .string()
  .trim()
  .min(2)
  .max(35)
  .regex(/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/u);
const keySchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_]*(?:[.-][a-z0-9_]+)*$/u);
const simpleKeySchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_]{0,127}$/u);
const permissionKeySchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(3)
  .max(160)
  .regex(/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/u);
const semanticVersionSchema = z
  .string()
  .regex(/^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$/u);
const positiveVersionSchema = z
  .number()
  .int()
  .min(1)
  .max(Number.MAX_SAFE_INTEGER);
const nonnegativeVersionSchema = z
  .number()
  .int()
  .min(0)
  .max(Number.MAX_SAFE_INTEGER);
const bigintTextSchema = z
  .string()
  .trim()
  .regex(/^(?:0|[1-9][0-9]{0,18})$/u)
  .refine((value) => BigInt(value) <= 9_223_372_036_854_775_807n, {
    message: "Value exceeds PostgreSQL bigint bounds.",
  });
const signedBigintTextSchema = z
  .string()
  .trim()
  .regex(/^(?:0|-?[1-9][0-9]{0,18})$/u)
  .refine(
    (value) => {
      const parsed = BigInt(value);
      return (
        parsed >= -9_223_372_036_854_775_808n &&
        parsed <= 9_223_372_036_854_775_807n
      );
    },
    { message: "Value exceeds PostgreSQL bigint bounds." },
  );
const currencySchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z]{3}$/u);
const jurisdictionSchema = z.string().regex(/^[A-Z]{2}(?:-[A-Z0-9]{1,3})?$/u);
const reasonSchema = z
  .string()
  .min(1)
  .max(2_000)
  .refine((value) => value.trim() === value, {
    message: "Reason must be canonical and trimmed.",
  });
const labelsSchema = z
  .object({
    en: z.string().trim().min(1).max(200),
    fr: z.string().trim().min(1).max(200),
  })
  .strict();
const jsonObjectSchema = z
  .record(z.string().min(1).max(160), z.unknown())
  .refine((value) => Object.keys(value).length <= 500, {
    message: "Object has too many properties.",
  });
const jsonArraySchema = z.array(z.unknown()).max(1_000);
const statusSchema = z.enum([
  "draft",
  "validated",
  "test_passed",
  "approved",
  "active",
  "retired",
]);
const jobStatusSchema = z.enum([
  "queued",
  "running",
  "retry_wait",
  "succeeded",
  "dead_letter",
  "cancelled",
]);

export type M4ApplicationValidationErrorCode =
  | "invalid_request_body"
  | "invalid_entity_id"
  | "invalid_file_id"
  | "invalid_version_id"
  | "invalid_definition_key"
  | "invalid_query"
  | CalculationErrorCode
  | TaxErrorCode;

export class M4ApplicationValidationError extends Error {
  readonly code: M4ApplicationValidationErrorCode;

  constructor(code: M4ApplicationValidationErrorCode) {
    super("The Milestone 4 request input is invalid.");
    this.name = "M4ApplicationValidationError";
    this.code = code;
  }
}

export class M4RpcContractError extends Error {
  constructor() {
    super("The Milestone 4 data store returned an invalid response.");
    this.name = "M4RpcContractError";
  }
}

export interface M4AuthenticatedQueryMetadata {
  readonly accessToken: string;
  readonly correlationId: string;
  readonly requestId: string;
  readonly workspaceId: string;
}

export interface M4DownloadGrantPort {
  issue(input: {
    readonly authorizationExpiresAt: string;
    readonly authorizationId: string;
    readonly byteSize: number;
    readonly checksumSha256: string;
    readonly fileId: string;
    readonly filename: string;
    readonly kind: "document" | "export";
    readonly mimeType: string;
    readonly ownerId: string;
    readonly workspaceId: string;
  }): Promise<{ readonly expiresAt: string; readonly url: string }>;
}

export interface M4RuntimeEvidencePort {
  record(input: {
    readonly accessToken: string;
    readonly assignmentId: string | null;
    readonly correlationId: string;
    readonly dealId: string | null;
    readonly evidence: Readonly<Record<string, unknown>>;
    readonly idempotencyKey: string;
    readonly kind: "calculation" | "tax";
    readonly requestId: string;
    readonly versionId: string;
    readonly workspaceId: string;
  }): Promise<{ readonly evidenceId: string }>;
}

function parseBody<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    throw new M4ApplicationValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseUuid(
  value: unknown,
  code: "invalid_entity_id" | "invalid_file_id" | "invalid_version_id",
): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) throw new M4ApplicationValidationError(code);
  return parsed.data;
}

function parseKey(value: unknown): string {
  const parsed = keySchema.safeParse(value);
  if (!parsed.success) {
    throw new M4ApplicationValidationError("invalid_definition_key");
  }
  return parsed.data;
}

function parseQuery<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) throw new M4ApplicationValidationError("invalid_query");
  return parsed.data;
}

function parseOne<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = z.array(schema).length(1).safeParse(value);
  if (!parsed.success) throw new M4RpcContractError();
  return parsed.data[0]!;
}

function parseRows<T>(
  schema: z.ZodType<T>,
  maximumRows: number,
  value: unknown,
): readonly T[] {
  const parsed = z.array(schema).max(maximumRows).safeParse(value);
  if (!parsed.success) throw new M4RpcContractError();
  return Object.freeze(parsed.data);
}

function parseRuntimeResult<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) throw new M4RpcContractError();
  return parsed.data;
}

function runtimeEvidenceChecksum(value: CalculationJson): string {
  return sha256Hex(canonicalJson(value));
}

function runtimeDefinitionChecksumWithout(
  value: Readonly<Record<string, unknown>>,
  excludedKeys: readonly string[],
): string {
  const projection = { ...value };
  for (const key of excludedKeys) delete projection[key];
  return runtimeEvidenceChecksum(projection as CalculationJson);
}

const paginationQuerySchema = z
  .object({
    cursorCreatedAt: timestampSchema.optional(),
    cursorId: uuidSchema.optional(),
    limit: z.number().int().min(1).max(200).default(50),
  })
  .strict()
  .refine(
    (value) =>
      (value.cursorCreatedAt === undefined) === (value.cursorId === undefined),
    { message: "Cursor parts must be supplied together." },
  );

const localizedDocumentTypeSchema = z
  .object({
    activation_status: statusSchema,
    field_schema: jsonObjectSchema,
    field_schema_checksum: checksumSchema,
    id: uuidSchema,
    key: keySchema,
    labels: labelsSchema,
    official_generation_enabled: z.boolean(),
    preview_generation_enabled: z.boolean(),
    production_enabled: z.boolean(),
    template_locales: z.array(localeSchema).max(50),
    version: positiveVersionSchema,
  })
  .strict();

const documentStatusSchema = z.enum([
  "queued",
  "generating",
  "generated",
  "failed",
  "generation_failed",
  "signed_received",
  "completed",
  "voided",
  "superseded",
]);
const documentModeSchema = z.enum(["preview", "official"]);
const documentFileSchema = z
  .object({
    byte_size: z.number().int().min(1).max(104_857_600),
    checksum_sha256: checksumSchema,
    created_at: timestampSchema,
    current: z.boolean(),
    filename: z.string().trim().min(1).max(255),
    id: uuidSchema,
    mime_type: z.string().trim().min(1).max(150),
    role: z.enum([
      "preview",
      "generated_original",
      "signed_scan",
      "attachment",
      "void_notice",
    ]),
    version: positiveVersionSchema,
  })
  .strict();
const documentJobSchema = z
  .object({
    attempt_count: z.number().int().min(0).max(100),
    failure_code: z.string().trim().min(1).max(100).nullable(),
    job_id: uuidSchema,
    review_required: z.boolean(),
    status: jobStatusSchema,
    updated_at: timestampSchema,
  })
  .strict();
const documentListRowSchema = z
  .object({
    aggregate_version: positiveVersionSchema,
    created_at: timestampSchema,
    current_file_id: uuidSchema.nullable(),
    deal_id: uuidSchema,
    document_type_key: keySchema,
    generated_at: nullableTimestampSchema,
    id: uuidSchema,
    job_status: jobStatusSchema.nullable(),
    locale: localeSchema,
    mode: documentModeSchema,
    official_number: z.string().trim().min(1).max(128).nullable(),
    preview_artifact_id: uuidSchema.nullable(),
    status: documentStatusSchema,
    superseded_by_document_id: uuidSchema.nullable(),
    supersedes_document_id: uuidSchema.nullable(),
  })
  .strict();
const documentDetailSchema = documentListRowSchema
  .extend({
    calculation_snapshot: jsonObjectSchema.nullable(),
    document_date: dateSchema.nullable(),
    files: z.array(documentFileSchema).max(500),
    intended_signature_date: dateSchema.nullable(),
    jobs: z.array(documentJobSchema).max(100),
    render_input_checksum: checksumSchema,
    signed_at: nullableTimestampSchema,
    tax_snapshot: jsonObjectSchema.nullable(),
    version_snapshot: jsonObjectSchema,
    version_snapshot_checksum: checksumSchema.nullable(),
    void_reason: z.string().min(1).max(2_000).nullable(),
  })
  .strict();

const calculationEvidenceSnapshotSchema = z
  .object({
    checksum: checksumSchema,
    components: jsonArraySchema,
    definition: jsonObjectSchema,
    definitionChecksum: checksumSchema,
    definitionKey: keySchema,
    definitionVersion: semanticVersionSchema,
    engineVersion: z.string().trim().min(1).max(100),
    input: jsonObjectSchema,
    inputBinding: z
      .object({
        dealContextChecksum: checksumSchema,
        inputProjectionChecksum: checksumSchema,
        mapperVersion: z.literal("deal-runtime-input-v1"),
      })
      .strict()
      .optional(),
    output: jsonObjectSchema,
    rounding: jsonObjectSchema,
    taxComponents: jsonArraySchema,
    versionId: uuidSchema,
  })
  .strict();
const calculationEvidenceSchema = calculationEvidenceSnapshotSchema
  .extend({ evidenceId: uuidSchema })
  .strict();
const taxOverrideEvidenceSchema = z
  .object({
    kind: z.literal("trade_in_eligibility"),
    permissionGranted: z.literal(true),
    permissionKey: z.literal("tax.override"),
    reason: reasonSchema,
    recentStrongAuth: z.literal(true),
    reviewReference: z.string().trim().min(3).max(200),
  })
  .strict();
const taxEvidenceFields = {
  checksum: checksumSchema,
  context: simpleKeySchema,
  currency: currencySchema,
  engineVersion: z.string().trim().min(1).max(100),
  input: jsonObjectSchema,
  inputBinding: z
    .object({
      dealContextChecksum: checksumSchema,
      inputProjectionChecksum: checksumSchema,
      mapperVersion: z.literal("deal-runtime-input-v1"),
    })
    .strict()
    .optional(),
  jurisdiction: jurisdictionSchema,
  output: jsonObjectSchema,
  override: taxOverrideEvidenceSchema.optional(),
  overrideReason: reasonSchema.optional(),
  pack: jsonObjectSchema,
  packChecksum: checksumSchema,
  packKey: keySchema,
  packVersion: semanticVersionSchema,
  transactionDate: dateSchema,
  versionId: uuidSchema,
} as const;
function taxEvidencePairIsValid(value: {
  readonly override?: z.infer<typeof taxOverrideEvidenceSchema> | undefined;
  readonly overrideReason?: string | undefined;
}): boolean {
  return (
    (value.override === undefined) === (value.overrideReason === undefined) &&
    (value.override === undefined ||
      value.override.reason === value.overrideReason)
  );
}
const taxEvidenceSchema = z
  .object({
    assignmentId: uuidSchema,
    evidenceId: uuidSchema,
    ...taxEvidenceFields,
  })
  .strict()
  .refine(taxEvidencePairIsValid, {
    message: "Tax override and reason must be supplied together.",
  });
const documentContextSchema = z
  .object({
    calculationEvidence: calculationEvidenceSchema.nullable().default(null),
    dealId: uuidSchema,
    documentDate: dateSchema,
    documentFields: jsonObjectSchema,
    documentTypeId: uuidSchema,
    intendedSignatureDate: dateSchema.nullable().default(null),
    locale: localeSchema,
    taxEvidence: taxEvidenceSchema.nullable().default(null),
    templateVersionId: uuidSchema,
  })
  .strict();
const documentValidateBodySchema = documentContextSchema;
const documentPreviewBodySchema = documentContextSchema.extend({}).strict();
const officialDocumentBodySchema = documentContextSchema
  .extend({ reason: reasonSchema })
  .strict();
const supersedeDocumentBodySchema = officialDocumentBodySchema
  .extend({ expectedVersion: positiveVersionSchema })
  .strict();
const documentValidationResultSchema = z
  .object({
    calculation_ready: z.boolean(),
    document_type_ready: z.boolean(),
    errors: z.array(keySchema).max(100),
    numbering_ready: z.boolean(),
    official_ready: z.boolean(),
    preview_ready: z.boolean(),
    tax_ready: z.boolean(),
    template_ready: z.boolean(),
    warnings: z.array(keySchema).max(100),
  })
  .strict();
const documentRequestResultSchema = z
  .object({
    aggregate_version: positiveVersionSchema,
    audit_event_id: uuidSchema,
    document_id: uuidSchema,
    document_status: documentStatusSchema,
    job_id: uuidSchema,
    number_allocation_id: uuidSchema.nullable(),
    official_number: z.string().trim().min(1).max(128).nullable(),
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();
const documentMutationBodySchema = z
  .object({
    expectedVersion: positiveVersionSchema,
    reason: reasonSchema,
  })
  .strict();
const documentMutationResultSchema = z
  .object({
    aggregate_version: positiveVersionSchema,
    audit_event_id: uuidSchema,
    document_id: uuidSchema,
    document_status: documentStatusSchema,
    replayed: z.boolean(),
  })
  .strict();
const markSignedResultSchema = documentMutationResultSchema
  .extend({ signed_at: timestampSchema })
  .strict();
const voidDocumentResultSchema = documentMutationResultSchema
  .extend({ voided_at: timestampSchema })
  .strict();
const retryDocumentResultSchema = documentMutationResultSchema
  .extend({ job_id: uuidSchema, job_status: jobStatusSchema })
  .strict();

const numberingListRowSchema = z
  .object({
    active_version_id: uuidSchema.nullable(),
    created_at: timestampSchema,
    id: uuidSchema,
    key: simpleKeySchema,
    labels: labelsSchema,
    versions: z
      .array(
        z
          .object({
            activated_at: nullableTimestampSchema,
            approval_record_id: uuidSchema.nullable(),
            checksum: checksumSchema,
            id: uuidSchema,
            semantic_version: semanticVersionSchema,
            status: statusSchema,
            version: positiveVersionSchema,
          })
          .strict(),
      )
      .max(100),
  })
  .strict();
const numberingVersionBodySchema = z
  .object({
    allocationEvent: permissionKeySchema,
    expectedLatestVersionId: uuidSchema.nullable().default(null),
    expectedChecksum: checksumSchema,
    formatPattern: z
      .string()
      .min(1)
      .max(200)
      .refine((value) => value.includes("{{sequence}}")),
    importPolicy: z.enum(["prohibited", "authorized_reservation"]),
    incrementBy: bigintTextSchema,
    labels: labelsSchema,
    numericWidth: z.number().int().min(1).max(18),
    periodAnchor: dateSchema.nullable().default(null),
    periodMonths: z.number().int().min(1).max(120).nullable().default(null),
    prefix: z.string().max(64),
    reason: reasonSchema,
    resetPolicy: z.enum(["never", "yearly", "monthly", "configured_period"]),
    scopeType: z.enum([
      "workspace",
      "legal_entity",
      "location",
      "document_type",
      "combined",
    ]),
    semanticVersion: semanticVersionSchema,
    startingValue: bigintTextSchema,
    suffix: z.string().max(64),
    timezoneName: z.string().trim().min(1).max(100),
  })
  .strict()
  .refine(
    (value) =>
      value.resetPolicy === "configured_period"
        ? value.periodMonths !== null && value.periodAnchor !== null
        : value.periodMonths === null && value.periodAnchor === null,
    { message: "Configured-period reset fields are inconsistent." },
  );
const artifactVersionResultSchema = z
  .object({
    artifact_id: uuidSchema,
    audit_event_id: uuidSchema,
    approval_record_id: uuidSchema.nullable(),
    artifact_status: statusSchema,
    replayed: z.boolean(),
  })
  .strict();
const numberingVersionResultSchema = z
  .object({
    artifact_status: statusSchema,
    audit_event_id: uuidSchema,
    numbering_definition_id: uuidSchema,
    numbering_version_id: uuidSchema,
    replayed: z.boolean(),
    version: positiveVersionSchema,
  })
  .strict();
const activationBodySchema = z
  .object({
    expectedChecksum: checksumSchema,
    expectedVersion: positiveVersionSchema,
    reason: reasonSchema,
  })
  .strict();

const approvalQuerySchema = paginationQuerySchema
  .safeExtend({
    artifactKey: keySchema.optional(),
    artifactType: keySchema.optional(),
    currentOnly: z.boolean().default(true),
  })
  .strict();
const approvalRowSchema = z
  .object({
    approval_type: keySchema,
    artifact_checksum: checksumSchema,
    artifact_id: uuidSchema,
    artifact_key: keySchema,
    artifact_type: keySchema,
    artifact_version: positiveVersionSchema,
    attachment_reference: z.string().trim().min(1).max(1_000).nullable(),
    conditions: jsonObjectSchema,
    decided_at: timestampSchema,
    decision: z.enum(["approved", "rejected", "revoked"]),
    expires_at: nullableTimestampSchema,
    id: uuidSchema,
    professional_organization: z.string().trim().min(1).max(500).nullable(),
    professional_role: z.string().trim().min(1).max(500).nullable(),
    review_due_at: nullableTimestampSchema,
    supersedes_approval_id: uuidSchema.nullable(),
  })
  .strict();
const approvalBodySchema = z
  .object({
    approvalType: keySchema,
    artifactId: uuidSchema,
    artifactType: keySchema,
    attachmentReference: z
      .string()
      .trim()
      .min(1)
      .max(1_000)
      .nullable()
      .default(null),
    conditions: jsonObjectSchema.default({}),
    decision: z.enum(["approved", "rejected", "revoked"]),
    expectedChecksum: checksumSchema,
    expiresAt: timestampSchema.nullable().default(null),
    professionalOrganization: z
      .string()
      .trim()
      .min(1)
      .max(500)
      .nullable()
      .default(null),
    professionalRole: z
      .string()
      .trim()
      .min(1)
      .max(500)
      .nullable()
      .default(null),
    reason: reasonSchema,
    reviewDueAt: timestampSchema.nullable().default(null),
    supersedesApprovalId: uuidSchema.nullable().default(null),
  })
  .strict()
  .refine(
    (value) =>
      value.decision === "revoked"
        ? value.supersedesApprovalId !== null
        : value.supersedesApprovalId === null,
    { message: "Approval supersession is inconsistent with the decision." },
  );
const approvalResultSchema = z
  .object({
    approval_record_id: uuidSchema,
    audit_event_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();

const taxPackRowSchema = z
  .object({
    active_versions: z.array(uuidSchema).max(100),
    id: uuidSchema,
    key: keySchema,
    labels: labelsSchema,
    source_kind: z.enum(["portable_pack", "workspace_import"]),
    versions: z
      .array(
        z
          .object({
            checksum: checksumSchema,
            contexts: z.array(simpleKeySchema).max(100),
            currency_codes: z.array(currencySchema).max(20),
            effective_from: dateSchema,
            effective_to: dateSchema.nullable(),
            id: uuidSchema,
            jurisdiction_code: jurisdictionSchema,
            semantic_version: semanticVersionSchema,
            status: statusSchema,
            version: positiveVersionSchema,
          })
          .strict(),
      )
      .max(100),
  })
  .strict();
const taxPreviewBodySchema = z
  .object({
    contextKey: simpleKeySchema,
    currencyCode: currencySchema,
    dealId: uuidSchema.nullable().default(null),
    inputs: jsonObjectSchema,
    jurisdictionCode: jurisdictionSchema,
    override: z
      .object({
        kind: z.literal("trade_in_eligibility"),
        reviewReference: z.string().trim().min(3).max(200),
      })
      .strict()
      .nullable()
      .default(null),
    overrideReason: reasonSchema.nullable().default(null),
    transactionDate: dateSchema,
  })
  .strict()
  .refine(
    (value) => (value.override === null) === (value.overrideReason === null),
    { message: "Tax override and reason must be supplied together." },
  );
const taxPreviewEvidenceSnapshotSchema = z
  .object({ assignmentId: uuidSchema.nullable(), ...taxEvidenceFields })
  .strict()
  .refine(taxEvidencePairIsValid, {
    message: "Tax override and reason must be supplied together.",
  });
const taxPreviewEvidenceSchema = z
  .object({
    assignmentId: uuidSchema.nullable(),
    evidenceId: uuidSchema,
    ...taxEvidenceFields,
  })
  .strict()
  .refine(taxEvidencePairIsValid, {
    message: "Tax override and reason must be supplied together.",
  });
const runtimeEvidenceReceiptSchema = z
  .object({ evidenceId: uuidSchema })
  .strict();
const taxPreviewConfigurationSchema = z
  .object({
    assignment_id: uuidSchema.nullable(),
    definition: jsonObjectSchema,
    definition_checksum: checksumSchema,
    engine_version: z.string().trim().min(1).max(100),
    override_authorized: z.boolean(),
    tax_pack_version_id: uuidSchema,
  })
  .strict();
const calculationDefinitionRowSchema = z
  .object({
    active_version_id: uuidSchema.nullable(),
    id: uuidSchema,
    key: simpleKeySchema,
    labels: labelsSchema,
    versions: z
      .array(
        z
          .object({
            checksum: checksumSchema,
            engine_version: z.string().trim().min(1).max(100),
            id: uuidSchema,
            semantic_version: semanticVersionSchema,
            status: statusSchema,
            version: positiveVersionSchema,
          })
          .strict(),
      )
      .max(100),
  })
  .strict();
const calculationValidateBodySchema = z
  .object({
    definition: jsonObjectSchema,
    expectedChecksum: checksumSchema.optional(),
  })
  .strict();
const calculationValidationResultSchema = z
  .object({
    checksum: checksumSchema.nullable(),
    checksum_matches: z.boolean().nullable(),
    errors: z.array(keySchema).max(500),
    fixture_count: z.number().int().min(0).max(1_000),
    valid: z.boolean(),
    warnings: z.array(keySchema).max(500),
  })
  .strict();
const calculationPreviewBodySchema = z
  .object({
    calculationVersionId: uuidSchema,
    dealId: uuidSchema.nullable().default(null),
    inputs: jsonObjectSchema,
  })
  .strict();
const calculationLimitValueSchema = z.number().int().min(1);
const calculationLimitsSchema = z
  .object({
    maximumDepth: calculationLimitValueSchema.max(
      DEFAULT_CALCULATION_LIMITS.maximumDepth,
    ),
    maximumInputBytes: calculationLimitValueSchema.max(
      DEFAULT_CALCULATION_LIMITS.maximumInputBytes,
    ),
    maximumNodes: calculationLimitValueSchema.max(
      DEFAULT_CALCULATION_LIMITS.maximumNodes,
    ),
    maximumOutputBytes: calculationLimitValueSchema.max(
      DEFAULT_CALCULATION_LIMITS.maximumOutputBytes,
    ),
    maximumOutputs: calculationLimitValueSchema.max(
      DEFAULT_CALCULATION_LIMITS.maximumOutputs,
    ),
    maximumRows: calculationLimitValueSchema.max(
      DEFAULT_CALCULATION_LIMITS.maximumRows,
    ),
    maximumRuntimeMs: calculationLimitValueSchema.max(
      DEFAULT_CALCULATION_LIMITS.maximumRuntimeMs,
    ),
  })
  .partial()
  .strict();
const calculationPreviewConfigurationSchema = z
  .object({
    calculation_version_id: uuidSchema,
    definition: jsonObjectSchema,
    definition_checksum: checksumSchema,
    engine_version: z.string().trim().min(1).max(100),
    resource_limits: calculationLimitsSchema,
  })
  .strict();
const dealRuntimeInputSchema = z
  .object({
    calculation_input: jsonObjectSchema,
    calculation_input_checksum: checksumSchema,
    deal_context_checksum: checksumSchema,
    deal_currency_code: currencySchema,
    tax_input: jsonObjectSchema.nullable(),
    tax_input_checksum: checksumSchema.nullable(),
  })
  .strict();

const exportDefinitionRowSchema = z
  .object({
    active_version_id: uuidSchema,
    columns: jsonArraySchema,
    filter_schema: jsonObjectSchema,
    formats: z
      .array(z.enum(["csv", "xlsx"]))
      .min(1)
      .max(2),
    id: uuidSchema,
    key: simpleKeySchema,
    labels: labelsSchema,
    maximum_rows: z.number().int().min(1).max(100_000),
    permission_key: permissionKeySchema,
    sensitivity: z.enum(["standard", "sensitive", "restricted"]),
    step_up_required: z.boolean(),
    version_checksum: checksumSchema,
  })
  .strict();
const exportRunBodySchema = z
  .object({
    filters: jsonObjectSchema.default({}),
    format: z.enum(["csv", "xlsx"]),
    locale: localeSchema,
    reason: reasonSchema,
  })
  .strict();
const exportStatusSchema = z.enum([
  "queued",
  "running",
  "retry_wait",
  "generated",
  "failed",
  "dead_letter",
  "expired",
]);
const exportRunSchema = z
  .object({
    created_at: timestampSchema,
    expires_at: timestampSchema,
    export_definition_key: simpleKeySchema,
    export_file_id: uuidSchema.nullable(),
    export_run_id: uuidSchema,
    export_version_id: uuidSchema,
    failure_code: z.string().trim().min(1).max(100).nullable(),
    generated_checksum: checksumSchema.nullable(),
    job_id: uuidSchema.nullable(),
    locale: localeSchema,
    outbox_event_id: uuidSchema.nullable(),
    replayed: z.boolean(),
    requested_format: z.enum(["csv", "xlsx"]),
    row_count: nonnegativeVersionSchema.nullable(),
    status: exportStatusSchema,
  })
  .strict();
const exportRunRequestSchema = z
  .object({
    audit_event_id: uuidSchema,
    expires_at: timestampSchema,
    export_run_id: uuidSchema,
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    replayed: z.boolean(),
    run_status: exportStatusSchema,
  })
  .strict();

const documentDownloadAuthorizationSchema = z
  .object({
    authorization_expires_at: timestampSchema,
    authorization_id: uuidSchema,
    audit_event_id: uuidSchema,
    byte_size: z.number().int().min(1).max(104_857_600),
    checksum_sha256: checksumSchema,
    document_file_id: uuidSchema,
    document_id: uuidSchema,
    filename: z.string().trim().min(1).max(255),
    mime_type: z.string().trim().min(1).max(150),
    replayed: z.boolean(),
  })
  .strict();
const exportDownloadAuthorizationSchema = z
  .object({
    authorization_expires_at: timestampSchema,
    authorization_id: uuidSchema,
    audit_event_id: uuidSchema,
    byte_size: z.number().int().min(1).max(104_857_600),
    checksum_sha256: checksumSchema,
    export_file_id: uuidSchema,
    filename: z.string().trim().min(1).max(255),
    mime_type: z.string().trim().min(1).max(150),
    replayed: z.boolean(),
  })
  .strict();

const reportQuerySchema = paginationQuerySchema
  .safeExtend({
    dateFrom: dateSchema.optional(),
    dateTo: dateSchema.optional(),
    locationId: uuidSchema.optional(),
  })
  .strict()
  .refine(
    (value) =>
      value.dateFrom === undefined ||
      value.dateTo === undefined ||
      value.dateFrom <= value.dateTo,
    { message: "Report date range is invalid." },
  );
const moneyColumns = {
  amount_minor: signedBigintTextSchema,
  currency_code: currencySchema,
} as const;
const inventoryAgingRowSchema = z
  .object({
    acquired_on: dateSchema,
    age_days: z.number().int().min(0).max(100_000),
    cost_amount_minor: moneyColumns.amount_minor,
    created_at: timestampSchema,
    currency_code: moneyColumns.currency_code,
    inventory_unit_id: uuidSchema,
    location_id: uuidSchema,
    make: z.string().trim().min(1).max(120),
    model: z.string().trim().min(1).max(120),
    model_year: z.number().int().min(1886).max(3000),
    stock_number: z.string().trim().min(1).max(100),
  })
  .strict();
const inventoryGrossRowSchema = z
  .object({
    closed_at: timestampSchema,
    cost_amount_minor: moneyColumns.amount_minor,
    currency_code: moneyColumns.currency_code,
    deal_id: uuidSchema,
    gross_amount_minor: moneyColumns.amount_minor,
    inventory_unit_id: uuidSchema,
    revenue_amount_minor: moneyColumns.amount_minor,
    stock_number: z.string().trim().min(1).max(100),
  })
  .strict();
const leadReportRowSchema = z
  .object({
    converted_deal_id: uuidSchema.nullable(),
    created_at: timestampSchema,
    id: uuidSchema,
    last_activity_at: nullableTimestampSchema,
    owner_membership_id: uuidSchema.nullable(),
    source_key: keySchema,
    status: simpleKeySchema,
  })
  .strict();
const dealReportRowSchema = z
  .object({
    created_at: timestampSchema,
    currency_code: currencySchema,
    deal_type_key: keySchema,
    id: uuidSchema,
    owner_membership_id: uuidSchema.nullable(),
    status: simpleKeySchema,
    total_amount_minor: signedBigintTextSchema,
    updated_at: timestampSchema,
  })
  .strict();

export interface M4ApplicationServiceOptions {
  readonly downloadGrants?: M4DownloadGrantPort;
  readonly gateway: AuthenticatedRpcGateway;
  readonly runtimeEvidence?: M4RuntimeEvidencePort;
}

export class M4ApplicationService {
  readonly #downloadGrants: M4DownloadGrantPort | undefined;
  readonly #gateway: AuthenticatedRpcGateway;
  readonly #runtimeEvidence: M4RuntimeEvidencePort | undefined;

  constructor(options: M4ApplicationServiceOptions) {
    this.#gateway = options.gateway;
    this.#downloadGrants = options.downloadGrants;
    this.#runtimeEvidence = options.runtimeEvidence;
  }

  async #recordRuntimeEvidence(input: {
    readonly assignmentId: string | null;
    readonly dealId: string | null;
    readonly evidence: Readonly<Record<string, unknown>>;
    readonly kind: "calculation" | "tax";
    readonly metadata: VerticalSliceCommandInput["metadata"];
    readonly versionId: string;
  }): Promise<string> {
    if (this.#runtimeEvidence === undefined) throw new M4RpcContractError();
    const receipt = parseRuntimeResult(
      runtimeEvidenceReceiptSchema,
      await this.#runtimeEvidence.record({
        accessToken: input.metadata.accessToken,
        assignmentId: input.assignmentId,
        correlationId: input.metadata.correlationId,
        dealId: input.dealId,
        evidence: input.evidence,
        idempotencyKey: input.metadata.idempotencyKey,
        kind: input.kind,
        requestId: input.metadata.requestId,
        versionId: input.versionId,
        workspaceId: input.metadata.workspaceId,
      }),
    );
    return receipt.evidenceId;
  }

  async #invokeOne<T>(
    accessToken: string,
    functionName: (typeof M4_RPC)[keyof typeof M4_RPC],
    parameters: Readonly<Record<string, unknown>>,
    schema: z.ZodType<T>,
  ): Promise<T> {
    return parseOne(
      schema,
      await this.#gateway.invoke({ accessToken, functionName, parameters }),
    );
  }

  async #loadDealRuntimeInput(input: {
    readonly dealId: string;
    readonly jurisdictionCode: string | null;
    readonly metadata: VerticalSliceCommandInput["metadata"];
  }) {
    const loaded = await this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.loadDealRuntimeInput,
      {
        p_deal_id: input.dealId,
        p_jurisdiction_code: input.jurisdictionCode,
        p_workspace_id: input.metadata.workspaceId,
      },
      dealRuntimeInputSchema,
    );
    if (
      runtimeEvidenceChecksum(
        loaded.calculation_input as unknown as CalculationJson,
      ) !== loaded.calculation_input_checksum ||
      (loaded.tax_input === null) !== (loaded.tax_input_checksum === null) ||
      (loaded.tax_input !== null &&
        runtimeEvidenceChecksum(
          loaded.tax_input as unknown as CalculationJson,
        ) !== loaded.tax_input_checksum)
    ) {
      throw new M4RpcContractError();
    }
    return loaded;
  }

  async #invokeRows<T>(
    accessToken: string,
    functionName: (typeof M4_RPC)[keyof typeof M4_RPC],
    parameters: Readonly<Record<string, unknown>>,
    schema: z.ZodType<T>,
    maximumRows: number,
  ): Promise<readonly T[]> {
    return parseRows(
      schema,
      maximumRows,
      await this.#gateway.invoke({ accessToken, functionName, parameters }),
    );
  }

  listDocumentTypes(metadata: M4AuthenticatedQueryMetadata) {
    return this.#invokeRows(
      metadata.accessToken,
      M4_RPC.listDocumentTypes,
      { p_workspace_id: metadata.workspaceId },
      localizedDocumentTypeSchema,
      250,
    );
  }

  validateDocument(input: VerticalSliceCommandInput) {
    const body = parseBody(documentValidateBodySchema, input.body);
    return this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.validateDocument,
      {
        p_calculation_evidence: body.calculationEvidence,
        p_deal_id: body.dealId,
        p_document_date: body.documentDate,
        p_document_fields: body.documentFields,
        p_document_type_id: body.documentTypeId,
        p_intended_signature_date: body.intendedSignatureDate,
        p_locale: body.locale,
        p_tax_evidence: body.taxEvidence,
        p_template_version_id: body.templateVersionId,
        p_workspace_id: input.metadata.workspaceId,
      },
      documentValidationResultSchema,
    );
  }

  requestDocumentPreview(input: VerticalSliceCommandInput) {
    const body = parseBody(documentPreviewBodySchema, input.body);
    return this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.requestDocumentPreview,
      {
        p_calculation_evidence: body.calculationEvidence,
        p_correlation_id: input.metadata.correlationId,
        p_deal_id: body.dealId,
        p_document_date: body.documentDate,
        p_document_fields: body.documentFields,
        p_document_type_id: body.documentTypeId,
        p_idempotency_key: input.metadata.idempotencyKey,
        p_intended_signature_date: body.intendedSignatureDate,
        p_locale: body.locale,
        p_request_id: input.metadata.requestId,
        p_tax_evidence: body.taxEvidence,
        p_template_version_id: body.templateVersionId,
        p_workspace_id: input.metadata.workspaceId,
      },
      documentRequestResultSchema,
    );
  }

  requestOfficialDocument(input: VerticalSliceCommandInput) {
    const body = parseBody(officialDocumentBodySchema, input.body);
    return this.#requestOfficial(input, body, null, null);
  }

  #requestOfficial(
    input: VerticalSliceCommandInput,
    body: z.infer<typeof officialDocumentBodySchema>,
    supersedesDocumentId: string | null,
    supersedesExpectedVersion: number | null,
  ) {
    return this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.requestOfficialDocument,
      {
        p_calculation_evidence: body.calculationEvidence,
        p_correlation_id: input.metadata.correlationId,
        p_deal_id: body.dealId,
        p_document_date: body.documentDate,
        p_document_fields: body.documentFields,
        p_document_type_id: body.documentTypeId,
        p_idempotency_key: input.metadata.idempotencyKey,
        p_intended_signature_date: body.intendedSignatureDate,
        p_locale: body.locale,
        p_reason: body.reason,
        p_request_id: input.metadata.requestId,
        p_supersedes_document_id: supersedesDocumentId,
        p_supersedes_expected_version: supersedesExpectedVersion,
        p_tax_evidence: body.taxEvidence,
        p_template_version_id: body.templateVersionId,
        p_workspace_id: input.metadata.workspaceId,
      },
      documentRequestResultSchema,
    );
  }

  listDocuments(metadata: M4AuthenticatedQueryMetadata, query: unknown) {
    const parsed = parseQuery(
      paginationQuerySchema
        .safeExtend({
          dealId: uuidSchema.optional(),
          documentTypeKey: keySchema.optional(),
          mode: documentModeSchema.optional(),
          status: documentStatusSchema.optional(),
        })
        .strict(),
      query,
    );
    return this.#invokeRows(
      metadata.accessToken,
      M4_RPC.listDocuments,
      {
        p_cursor_created_at: parsed.cursorCreatedAt ?? null,
        p_cursor_id: parsed.cursorId ?? null,
        p_deal_id: parsed.dealId ?? null,
        p_document_type_key: parsed.documentTypeKey ?? null,
        p_limit: parsed.limit,
        p_mode: parsed.mode ?? null,
        p_status: parsed.status ?? null,
        p_workspace_id: metadata.workspaceId,
      },
      documentListRowSchema,
      parsed.limit,
    );
  }

  getDocument(
    metadata: M4AuthenticatedQueryMetadata,
    documentIdValue: unknown,
  ) {
    const documentId = parseUuid(documentIdValue, "invalid_entity_id");
    return this.#invokeOne(
      metadata.accessToken,
      M4_RPC.getDocument,
      { p_document_id: documentId, p_workspace_id: metadata.workspaceId },
      documentDetailSchema,
    );
  }

  markDocumentSigned(
    input: VerticalSliceCommandInput & { readonly documentId: unknown },
  ) {
    const documentId = parseUuid(input.documentId, "invalid_entity_id");
    const body = parseBody(documentMutationBodySchema, input.body);
    return this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.markDocumentSigned,
      {
        p_correlation_id: input.metadata.correlationId,
        p_document_id: documentId,
        p_expected_version: body.expectedVersion,
        p_idempotency_key: input.metadata.idempotencyKey,
        p_reason: body.reason,
        p_request_id: input.metadata.requestId,
        p_workspace_id: input.metadata.workspaceId,
      },
      markSignedResultSchema,
    );
  }

  voidDocument(
    input: VerticalSliceCommandInput & { readonly documentId: unknown },
  ) {
    return this.#documentMutation(
      input,
      M4_RPC.voidDocument,
      voidDocumentResultSchema,
    );
  }

  retryDocumentRender(
    input: VerticalSliceCommandInput & { readonly documentId: unknown },
  ) {
    return this.#documentMutation(
      input,
      M4_RPC.retryDocumentRender,
      retryDocumentResultSchema,
    );
  }

  #documentMutation<T>(
    input: VerticalSliceCommandInput & { readonly documentId: unknown },
    functionName:
      typeof M4_RPC.voidDocument | typeof M4_RPC.retryDocumentRender,
    resultSchema: z.ZodType<T>,
  ): Promise<T> {
    const documentId = parseUuid(input.documentId, "invalid_entity_id");
    const body = parseBody(documentMutationBodySchema, input.body);
    return this.#invokeOne(
      input.metadata.accessToken,
      functionName,
      {
        p_correlation_id: input.metadata.correlationId,
        p_document_id: documentId,
        p_expected_version: body.expectedVersion,
        p_idempotency_key: input.metadata.idempotencyKey,
        p_reason: body.reason,
        p_request_id: input.metadata.requestId,
        p_workspace_id: input.metadata.workspaceId,
      },
      resultSchema,
    );
  }

  supersedeDocument(
    input: VerticalSliceCommandInput & { readonly documentId: unknown },
  ) {
    const documentId = parseUuid(input.documentId, "invalid_entity_id");
    const body = parseBody(supersedeDocumentBodySchema, input.body);
    return this.#requestOfficial(input, body, documentId, body.expectedVersion);
  }

  async authorizeDocumentFileDownload(
    metadata: M4AuthenticatedQueryMetadata,
    documentIdValue: unknown,
    fileIdValue: unknown,
  ) {
    const documentId = parseUuid(documentIdValue, "invalid_entity_id");
    const fileId = parseUuid(fileIdValue, "invalid_file_id");
    const row = await this.#invokeOne(
      metadata.accessToken,
      M4_RPC.authorizeDocumentFileDownload,
      {
        p_correlation_id: metadata.correlationId,
        p_document_file_id: fileId,
        p_expires_in_seconds: 60,
        p_idempotency_key: `download:document:${metadata.requestId}`,
        p_reason: "Authorized user-initiated document download.",
        p_request_id: metadata.requestId,
        p_workspace_id: metadata.workspaceId,
      },
      documentDownloadAuthorizationSchema,
    );
    if (row.document_id !== documentId || row.document_file_id !== fileId) {
      throw new M4RpcContractError();
    }
    return this.#issueDownload(metadata, "document", documentId, fileId, row);
  }

  async #issueDownload(
    metadata: M4AuthenticatedQueryMetadata,
    kind: "document" | "export",
    ownerId: string,
    fileId: string,
    row: {
      readonly authorization_expires_at: string;
      readonly authorization_id: string;
      readonly audit_event_id: string;
      readonly byte_size: number;
      readonly checksum_sha256: string;
      readonly filename: string;
      readonly mime_type: string;
    },
  ) {
    if (this.#downloadGrants === undefined) throw new M4RpcContractError();
    const download = await this.#downloadGrants.issue({
      authorizationExpiresAt: row.authorization_expires_at,
      authorizationId: row.authorization_id,
      byteSize: row.byte_size,
      checksumSha256: row.checksum_sha256,
      fileId,
      filename: row.filename,
      kind,
      mimeType: row.mime_type,
      ownerId,
      workspaceId: metadata.workspaceId,
    });
    return Object.freeze({
      auditEventId: row.audit_event_id,
      byteSize: row.byte_size,
      checksumSha256: row.checksum_sha256,
      download,
      fileId,
      filename: row.filename,
      mimeType: row.mime_type,
      ownerId,
    });
  }

  listNumberingDefinitions(metadata: M4AuthenticatedQueryMetadata) {
    return this.#invokeRows(
      metadata.accessToken,
      M4_RPC.listNumberingDefinitions,
      { p_workspace_id: metadata.workspaceId },
      numberingListRowSchema,
      250,
    );
  }

  createNumberingVersion(
    input: VerticalSliceCommandInput & { readonly definitionKey: unknown },
  ) {
    const definitionKey = parseKey(input.definitionKey);
    const body = parseBody(numberingVersionBodySchema, input.body);
    return this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.createNumberingDefinitionVersion,
      {
        p_correlation_id: input.metadata.correlationId,
        p_definition_key: definitionKey,
        p_expected_checksum: body.expectedChecksum,
        p_expected_latest_version_id: body.expectedLatestVersionId,
        p_idempotency_key: input.metadata.idempotencyKey,
        p_labels: body.labels,
        p_payload: {
          allocationEvent: body.allocationEvent,
          formatPattern: body.formatPattern,
          importPolicy: body.importPolicy,
          incrementBy: body.incrementBy,
          numericWidth: body.numericWidth,
          periodAnchor: body.periodAnchor,
          periodMonths: body.periodMonths,
          prefix: body.prefix,
          resetPolicy: body.resetPolicy,
          reusePolicy: "never",
          scopeType: body.scopeType,
          semanticVersion: body.semanticVersion,
          startingValue: body.startingValue,
          suffix: body.suffix,
          timezone: body.timezoneName,
        },
        p_reason: body.reason,
        p_request_id: input.metadata.requestId,
        p_workspace_id: input.metadata.workspaceId,
      },
      numberingVersionResultSchema,
    );
  }

  activateNumberingVersion(
    input: VerticalSliceCommandInput & { readonly versionId: unknown },
  ) {
    return this.#artifactLifecycle(
      input,
      input.versionId,
      M4_RPC.activateNumberingVersion,
      "numbering_definition",
      "active",
    );
  }

  activateDocumentType(
    input: VerticalSliceCommandInput & { readonly documentTypeId: unknown },
  ) {
    return this.#artifactLifecycle(
      input,
      input.documentTypeId,
      M4_RPC.activateDocumentType,
      "document_type",
      "active",
    );
  }

  activateDocumentTemplateVersion(
    input: VerticalSliceCommandInput & { readonly templateVersionId: unknown },
  ) {
    return this.#artifactLifecycle(
      input,
      input.templateVersionId,
      M4_RPC.activateDocumentTemplateVersion,
      "document_template",
      "active",
    );
  }

  listApprovalRecords(metadata: M4AuthenticatedQueryMetadata, query: unknown) {
    const parsed = parseQuery(approvalQuerySchema, query);
    return this.#invokeRows(
      metadata.accessToken,
      M4_RPC.listApprovalRecords,
      {
        p_artifact_key: parsed.artifactKey ?? null,
        p_artifact_type: parsed.artifactType ?? null,
        p_current_only: parsed.currentOnly,
        p_cursor_created_at: parsed.cursorCreatedAt ?? null,
        p_cursor_id: parsed.cursorId ?? null,
        p_limit: parsed.limit,
        p_workspace_id: metadata.workspaceId,
      },
      approvalRowSchema,
      parsed.limit,
    );
  }

  createApprovalRecord(input: VerticalSliceCommandInput) {
    const body = parseBody(approvalBodySchema, input.body);
    return this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.createApprovalRecord,
      {
        p_approval_type: body.approvalType,
        p_artifact_id: body.artifactId,
        p_artifact_type: body.artifactType,
        p_attachment_reference: body.attachmentReference,
        p_conditions: body.conditions,
        p_correlation_id: input.metadata.correlationId,
        p_decision: body.decision,
        p_expected_checksum: body.expectedChecksum,
        p_expires_at: body.expiresAt,
        p_idempotency_key: input.metadata.idempotencyKey,
        p_professional_organization: body.professionalOrganization,
        p_professional_role: body.professionalRole,
        p_reason: body.reason,
        p_request_id: input.metadata.requestId,
        p_review_due_at: body.reviewDueAt,
        p_supersedes_approval_id: body.supersedesApprovalId,
        p_workspace_id: input.metadata.workspaceId,
      },
      approvalResultSchema,
    );
  }

  listTaxPacks(metadata: M4AuthenticatedQueryMetadata) {
    return this.#invokeRows(
      metadata.accessToken,
      M4_RPC.listTaxPacks,
      { p_workspace_id: metadata.workspaceId },
      taxPackRowSchema,
      250,
    );
  }

  async runTaxPreview(input: VerticalSliceCommandInput) {
    const body = parseBody(taxPreviewBodySchema, input.body);
    const configuration = await this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.loadTaxPreviewConfiguration,
      {
        p_context_key: body.contextKey,
        p_currency_code: body.currencyCode,
        p_jurisdiction_code: body.jurisdictionCode,
        p_override_requested: body.override !== null,
        p_transaction_date: body.transactionDate,
        p_workspace_id: input.metadata.workspaceId,
      },
      taxPreviewConfigurationSchema,
    );
    if (
      configuration.engine_version !== TAX_ENGINE_VERSION ||
      (body.override !== null && !configuration.override_authorized)
    ) {
      throw new M4RpcContractError();
    }
    const boundInput =
      body.dealId === null
        ? null
        : await this.#loadDealRuntimeInput({
            dealId: body.dealId,
            jurisdictionCode: body.jurisdictionCode,
            metadata: input.metadata,
          });
    if (
      boundInput !== null &&
      (boundInput.tax_input === null ||
        boundInput.tax_input_checksum === null ||
        boundInput.deal_currency_code !== body.currencyCode)
    ) {
      throw new M4RpcContractError();
    }
    const taxInput = boundInput?.tax_input ?? body.inputs;

    let selected: ReturnType<typeof compileTaxPack>;
    try {
      const compiled = compileTaxPack(configuration.definition);
      if (
        runtimeDefinitionChecksumWithout(
          compiled.definition as unknown as Readonly<Record<string, unknown>>,
          ["activation_status", "approval_refs"],
        ) !== configuration.definition_checksum
      ) {
        throw new M4RpcContractError();
      }
      selected = selectTaxPack([compiled], {
        context: body.contextKey,
        currency: body.currencyCode,
        jurisdiction: body.jurisdictionCode,
        transactionDate: body.transactionDate,
        usage: "preview",
      });
    } catch (error) {
      if (error instanceof M4RpcContractError) throw error;
      if (error instanceof TaxRuntimeError) throw new M4RpcContractError();
      throw error;
    }

    let snapshot: ReturnType<typeof executeTaxCalculation>;
    try {
      const request: TaxCalculationRequest = {
        context: body.contextKey,
        currency: body.currencyCode,
        input: taxInput as TaxCalculationRequest["input"],
        jurisdiction: body.jurisdictionCode,
        transactionDate: body.transactionDate,
        ...(body.override === null
          ? {}
          : {
              override: {
                kind: body.override.kind,
                permissionGranted: configuration.override_authorized,
                permissionKey: "tax.override" as const,
                reason: body.overrideReason!,
                recentStrongAuth: configuration.override_authorized,
                reviewReference: body.override.reviewReference,
              },
            }),
      };
      snapshot = executeTaxCalculation(selected, request);
    } catch (error) {
      if (error instanceof TaxRuntimeError) {
        throw new M4ApplicationValidationError(error.code);
      }
      throw error;
    }
    if (
      boundInput !== null &&
      runtimeEvidenceChecksum(snapshot.input) !== boundInput.tax_input_checksum
    ) {
      throw new M4RpcContractError();
    }

    const evidenceWithoutChecksum = {
      assignmentId: configuration.assignment_id,
      context: snapshot.context,
      currency: snapshot.currency,
      engineVersion: snapshot.engineVersion,
      input: snapshot.input,
      ...(boundInput === null
        ? {}
        : {
            inputBinding: {
              dealContextChecksum: boundInput.deal_context_checksum,
              inputProjectionChecksum: boundInput.tax_input_checksum!,
              mapperVersion: "deal-runtime-input-v1" as const,
            },
          }),
      jurisdiction: snapshot.jurisdiction,
      output: snapshot.output,
      pack: snapshot.pack,
      packChecksum: snapshot.packChecksum,
      packKey: snapshot.packKey,
      packVersion: snapshot.packVersion,
      transactionDate: snapshot.transactionDate,
      versionId: configuration.tax_pack_version_id,
      ...(snapshot.override === null
        ? {}
        : {
            override: snapshot.override,
            overrideReason: snapshot.override.reason,
          }),
    };
    const evidence = {
      ...evidenceWithoutChecksum,
      checksum: runtimeEvidenceChecksum(
        evidenceWithoutChecksum as unknown as CalculationJson,
      ),
    };
    const snapshotEvidence = Object.freeze(
      parseRuntimeResult(taxPreviewEvidenceSnapshotSchema, evidence),
    );
    const evidenceId = await this.#recordRuntimeEvidence({
      assignmentId: configuration.assignment_id,
      dealId: body.dealId,
      evidence: snapshotEvidence,
      kind: "tax",
      metadata: input.metadata,
      versionId: configuration.tax_pack_version_id,
    });
    return Object.freeze(
      parseRuntimeResult(taxPreviewEvidenceSchema, {
        ...snapshotEvidence,
        evidenceId,
      }),
    );
  }

  activateTaxPackVersion(
    input: VerticalSliceCommandInput & { readonly versionId: unknown },
  ) {
    return this.#artifactLifecycle(
      input,
      input.versionId,
      M4_RPC.activateTaxPackVersion,
      "tax_pack",
      "active",
    );
  }

  listCalculationDefinitions(metadata: M4AuthenticatedQueryMetadata) {
    return this.#invokeRows(
      metadata.accessToken,
      M4_RPC.listCalculationDefinitions,
      { p_workspace_id: metadata.workspaceId },
      calculationDefinitionRowSchema,
      250,
    );
  }

  async validateCalculation(input: VerticalSliceCommandInput) {
    const body = parseBody(calculationValidateBodySchema, input.body);
    try {
      const compiled = compileCalculationDefinition(body.definition);
      const checksumMatches =
        body.expectedChecksum === undefined
          ? null
          : body.expectedChecksum === compiled.checksum;
      return parseRuntimeResult(calculationValidationResultSchema, {
        checksum: compiled.checksum,
        checksum_matches: checksumMatches,
        errors: checksumMatches === false ? ["checksum_mismatch"] : [],
        fixture_count: compiled.definition.fixtures.length,
        valid: checksumMatches !== false,
        warnings: [],
      });
    } catch (error) {
      if (!(error instanceof CalculationRuntimeError)) throw error;
      return parseRuntimeResult(calculationValidationResultSchema, {
        checksum: null,
        checksum_matches: null,
        errors: [error.code],
        fixture_count: 0,
        valid: false,
        warnings: [],
      });
    }
  }

  async runCalculationPreview(input: VerticalSliceCommandInput) {
    const body = parseBody(calculationPreviewBodySchema, input.body);
    const configuration = await this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.loadCalculationPreviewConfiguration,
      {
        p_calculation_version_id: body.calculationVersionId,
        p_workspace_id: input.metadata.workspaceId,
      },
      calculationPreviewConfigurationSchema,
    );
    if (configuration.engine_version !== CALCULATION_ENGINE_VERSION) {
      throw new M4RpcContractError();
    }
    const boundInput =
      body.dealId === null
        ? null
        : await this.#loadDealRuntimeInput({
            dealId: body.dealId,
            jurisdictionCode: null,
            metadata: input.metadata,
          });

    let compiled: ReturnType<typeof compileCalculationDefinition>;
    try {
      compiled = compileCalculationDefinition(
        configuration.definition,
        configuration.resource_limits as Partial<CalculationLimits>,
      );
    } catch (error) {
      if (error instanceof CalculationRuntimeError) {
        throw new M4RpcContractError();
      }
      throw error;
    }
    if (
      runtimeDefinitionChecksumWithout(
        compiled.definition as unknown as Readonly<Record<string, unknown>>,
        ["status", "approval_refs"],
      ) !== configuration.definition_checksum
    ) {
      throw new M4RpcContractError();
    }

    let snapshot: ReturnType<typeof runCalculation>;
    try {
      snapshot = runCalculation(
        compiled,
        boundInput?.calculation_input ?? body.inputs,
        {
          engineVersion: configuration.engine_version,
        },
      );
    } catch (error) {
      if (error instanceof CalculationRuntimeError) {
        throw new M4ApplicationValidationError(error.code);
      }
      throw error;
    }
    if (
      boundInput !== null &&
      runtimeEvidenceChecksum(snapshot.input) !==
        boundInput.calculation_input_checksum
    ) {
      throw new M4RpcContractError();
    }

    const evidenceWithoutChecksum = {
      components: snapshot.components,
      definition: snapshot.definition,
      definitionChecksum: snapshot.definitionChecksum,
      definitionKey: snapshot.definitionKey,
      definitionVersion: snapshot.definitionVersion,
      engineVersion: snapshot.engineVersion,
      input: snapshot.input,
      ...(boundInput === null
        ? {}
        : {
            inputBinding: {
              dealContextChecksum: boundInput.deal_context_checksum,
              inputProjectionChecksum: boundInput.calculation_input_checksum,
              mapperVersion: "deal-runtime-input-v1" as const,
            },
          }),
      output: snapshot.output,
      rounding: snapshot.rounding,
      taxComponents: snapshot.taxComponents,
      versionId: configuration.calculation_version_id,
    };
    const evidence = {
      ...evidenceWithoutChecksum,
      checksum: runtimeEvidenceChecksum(
        evidenceWithoutChecksum as unknown as CalculationJson,
      ),
    };
    const snapshotEvidence = Object.freeze(
      parseRuntimeResult(calculationEvidenceSnapshotSchema, evidence),
    );
    const evidenceId = await this.#recordRuntimeEvidence({
      assignmentId: null,
      dealId: body.dealId,
      evidence: snapshotEvidence,
      kind: "calculation",
      metadata: input.metadata,
      versionId: configuration.calculation_version_id,
    });
    return Object.freeze(
      parseRuntimeResult(calculationEvidenceSchema, {
        ...snapshotEvidence,
        evidenceId,
      }),
    );
  }

  approveCalculationVersion(
    input: VerticalSliceCommandInput & { readonly versionId: unknown },
  ) {
    return this.#artifactLifecycle(
      input,
      input.versionId,
      M4_RPC.approveCalculationVersion,
      "calculation",
      "approved",
    );
  }

  activateCalculationVersion(
    input: VerticalSliceCommandInput & { readonly versionId: unknown },
  ) {
    return this.#artifactLifecycle(
      input,
      input.versionId,
      M4_RPC.activateCalculationVersion,
      "calculation",
      "active",
    );
  }

  #artifactLifecycle(
    input: VerticalSliceCommandInput,
    versionIdValue: unknown,
    functionName:
      | typeof M4_RPC.activateNumberingVersion
      | typeof M4_RPC.approveCalculationVersion
      | typeof M4_RPC.activateCalculationVersion
      | typeof M4_RPC.activateDocumentType
      | typeof M4_RPC.activateDocumentTemplateVersion,
    artifactType:
      | "numbering_definition"
      | "calculation"
      | "tax_pack"
      | "document_type"
      | "document_template",
    targetStatus: "approved" | "active",
  ) {
    const versionId = parseUuid(versionIdValue, "invalid_version_id");
    const body = parseBody(activationBodySchema, input.body);
    return this.#invokeOne(
      input.metadata.accessToken,
      functionName,
      {
        p_correlation_id: input.metadata.correlationId,
        p_artifact_id: versionId,
        p_artifact_type: artifactType,
        p_evidence: { expectedVersion: body.expectedVersion },
        p_expected_checksum: body.expectedChecksum,
        p_idempotency_key: input.metadata.idempotencyKey,
        p_reason: body.reason,
        p_request_id: input.metadata.requestId,
        p_target_status: targetStatus,
        p_workspace_id: input.metadata.workspaceId,
      },
      artifactVersionResultSchema,
    );
  }

  listExportDefinitions(metadata: M4AuthenticatedQueryMetadata) {
    return this.#invokeRows(
      metadata.accessToken,
      M4_RPC.listExportDefinitions,
      { p_workspace_id: metadata.workspaceId },
      exportDefinitionRowSchema,
      250,
    );
  }

  requestExportRun(
    input: VerticalSliceCommandInput & { readonly definitionKey: unknown },
  ) {
    const definitionKey = parseKey(input.definitionKey);
    const body = parseBody(exportRunBodySchema, input.body);
    return this.#invokeOne(
      input.metadata.accessToken,
      M4_RPC.requestExportRun,
      {
        p_correlation_id: input.metadata.correlationId,
        p_definition_key: definitionKey,
        p_filters: body.filters,
        p_idempotency_key: input.metadata.idempotencyKey,
        p_locale: body.locale,
        p_reason: body.reason,
        p_request_id: input.metadata.requestId,
        p_requested_format: body.format,
        p_workspace_id: input.metadata.workspaceId,
      },
      exportRunRequestSchema,
    );
  }

  getExportRun(
    metadata: M4AuthenticatedQueryMetadata,
    exportRunIdValue: unknown,
  ) {
    const exportRunId = parseUuid(exportRunIdValue, "invalid_entity_id");
    return this.#invokeOne(
      metadata.accessToken,
      M4_RPC.getExportRun,
      { p_export_run_id: exportRunId, p_workspace_id: metadata.workspaceId },
      exportRunSchema,
    );
  }

  async authorizeExportDownload(
    metadata: M4AuthenticatedQueryMetadata,
    exportRunIdValue: unknown,
  ) {
    const exportRunId = parseUuid(exportRunIdValue, "invalid_entity_id");
    const row = await this.#invokeOne(
      metadata.accessToken,
      M4_RPC.authorizeExportDownload,
      {
        p_correlation_id: metadata.correlationId,
        p_expires_in_seconds: 60,
        p_export_run_id: exportRunId,
        p_idempotency_key: `download:export:${metadata.requestId}`,
        p_reason: "Authorized user-initiated export download.",
        p_request_id: metadata.requestId,
        p_workspace_id: metadata.workspaceId,
      },
      exportDownloadAuthorizationSchema,
    );
    return this.#issueDownload(
      metadata,
      "export",
      exportRunId,
      row.export_file_id,
      row,
    );
  }

  reportInventoryAging(metadata: M4AuthenticatedQueryMetadata, query: unknown) {
    return this.#report(
      metadata,
      query,
      M4_RPC.reportInventoryAging,
      inventoryAgingRowSchema,
    );
  }

  reportInventoryGross(metadata: M4AuthenticatedQueryMetadata, query: unknown) {
    return this.#report(
      metadata,
      query,
      M4_RPC.reportInventoryGross,
      inventoryGrossRowSchema,
    );
  }

  reportLeads(metadata: M4AuthenticatedQueryMetadata, query: unknown) {
    return this.#report(
      metadata,
      query,
      M4_RPC.reportLeads,
      leadReportRowSchema,
    );
  }

  reportDeals(metadata: M4AuthenticatedQueryMetadata, query: unknown) {
    return this.#report(
      metadata,
      query,
      M4_RPC.reportDeals,
      dealReportRowSchema,
    );
  }

  #report<T>(
    metadata: M4AuthenticatedQueryMetadata,
    query: unknown,
    functionName:
      | typeof M4_RPC.reportInventoryAging
      | typeof M4_RPC.reportInventoryGross
      | typeof M4_RPC.reportLeads
      | typeof M4_RPC.reportDeals,
    schema: z.ZodType<T>,
  ) {
    const parsed = parseQuery(reportQuerySchema, query);
    return this.#invokeRows(
      metadata.accessToken,
      functionName,
      {
        p_cursor_created_at: parsed.cursorCreatedAt ?? null,
        p_cursor_id: parsed.cursorId ?? null,
        p_date_from: parsed.dateFrom ?? null,
        p_date_to: parsed.dateTo ?? null,
        p_limit: parsed.limit,
        p_location_id: parsed.locationId ?? null,
        p_workspace_id: metadata.workspaceId,
      },
      schema,
      parsed.limit,
    );
  }
}
