import {
  assertExactKeys,
  canonicalJson,
  checksumJson,
  freezeJson,
  DocumentDomainError,
  normalizeIsoInstant,
  normalizeLabels,
  requireChecksum,
  requireDenseArray,
  requireKey,
  requireLocale,
  requirePlainRecord,
  requireUuid,
  requireVersion,
  type PlainRecord,
} from "./domain-common";
import { normalizeNumberingDefinition } from "./numbering";
import {
  compileDocumentTemplate,
  type DocumentTemplateSourceBundle,
} from "./template-runtime";

export const DOCUMENT_CONFIGURATION_STATUSES = [
  "draft",
  "validated",
  "test_passed",
  "reviewed",
  "approved",
  "active",
  "superseded",
  "retired",
] as const;
export type DocumentConfigurationStatus =
  (typeof DOCUMENT_CONFIGURATION_STATUSES)[number];

const APPROVAL_TYPE_PATTERN =
  /^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})*$/u;
const RENDERER_VERSION_PATTERN = /^[a-z][a-z0-9_.-]{0,127}$/u;

export interface ImmutableVersionReference {
  readonly id: string;
  readonly key: string;
  readonly version: string;
  readonly checksum: string;
}

export interface VersionIdentityReference {
  readonly id: string;
  readonly key: string;
  readonly version: string;
}

export interface DocumentTypeVersion {
  readonly id: string;
  readonly key: string;
  readonly version: string;
  readonly checksum: string;
  readonly labels: Readonly<Record<"en" | "fr", string>>;
  readonly fieldSchema: Readonly<PlainRecord>;
  readonly fieldSchemaChecksum: string;
  readonly templateVersionRefs: readonly ImmutableVersionReference[];
  readonly numberingVersionRef: ImmutableVersionReference;
  readonly workflowVersionRef: ImmutableVersionReference | null;
  readonly taxPackVersionRef: ImmutableVersionReference | null;
  readonly calculationVersionRef: ImmutableVersionReference | null;
  readonly productionEnabled: boolean;
  readonly requiredApprovalTypes: readonly string[];
  readonly status: DocumentConfigurationStatus;
}

export interface DocumentTemplateVersion {
  readonly id: string;
  readonly key: string;
  readonly documentTypeRef: VersionIdentityReference;
  readonly version: string;
  readonly checksum: string;
  readonly locale: string;
  readonly rendererVersion: string;
  readonly fieldSchema: Readonly<PlainRecord>;
  readonly fieldSchemaChecksum: string;
  readonly sourceBundle: DocumentTemplateSourceBundle;
  readonly productionApproved: boolean;
  readonly requiredApprovalTypes: readonly string[];
  readonly status: DocumentConfigurationStatus;
}

export interface DocumentApprovalRecord {
  readonly id: string;
  readonly artifactType:
    "document_type" | "document_template" | "numbering_definition";
  readonly artifactId: string;
  readonly artifactKey: string;
  readonly artifactVersion: string;
  readonly artifactChecksum: string;
  readonly approvalType: string;
  readonly decision: "approved" | "rejected" | "revoked";
  readonly decidedAt: string;
  readonly expiresAt: string | null;
}

export interface ResolvedDocumentConfiguration {
  readonly documentType: ImmutableVersionReference;
  readonly template: ImmutableVersionReference & {
    readonly locale: string;
    readonly rendererVersion: string;
    readonly sourceBundleChecksum: string;
  };
  readonly numbering: ImmutableVersionReference;
  readonly workflow: ImmutableVersionReference | null;
  readonly taxPack: ImmutableVersionReference | null;
  readonly calculation: ImmutableVersionReference | null;
  readonly fieldSchemaChecksum: string;
  readonly activationEvidence: readonly string[];
  readonly productionReady: boolean;
}

export type DocumentTypeVersionPayload = Omit<
  DocumentTypeVersion,
  "checksum" | "status"
>;
export type DocumentTemplateVersionPayload = Omit<
  DocumentTemplateVersion,
  "checksum" | "status"
>;

function normalizeReference(value: unknown): ImmutableVersionReference {
  const record = requirePlainRecord(value);
  assertExactKeys(record, ["id", "key", "version", "checksum"]);
  return Object.freeze({
    id: requireUuid(record.id),
    key: requireKey(record.key),
    version: requireVersion(record.version),
    checksum: requireChecksum(record.checksum),
  });
}

function normalizeIdentityReference(value: unknown): VersionIdentityReference {
  const record = requirePlainRecord(value);
  assertExactKeys(record, ["id", "key", "version"]);
  return Object.freeze({
    id: requireUuid(record.id),
    key: requireKey(record.key),
    version: requireVersion(record.version),
  });
}

export function versionReference(
  value: Readonly<{
    id: string;
    key: string;
    version: string;
    checksum: string;
  }>,
): ImmutableVersionReference {
  return Object.freeze({
    id: requireUuid(value.id),
    key: requireKey(value.key),
    version: requireVersion(value.version),
    checksum: requireChecksum(value.checksum),
  });
}

function normalizeOptionalReference(
  value: unknown,
): ImmutableVersionReference | null {
  return value === null ? null : normalizeReference(value);
}

function normalizeApprovalTypes(value: unknown): readonly string[] {
  const values = requireDenseArray(value);
  if (values.length > 20) {
    throw new DocumentDomainError("invalid_definition", "approval_types");
  }
  const result = values.map((entry) => {
    if (typeof entry !== "string" || !APPROVAL_TYPE_PATTERN.test(entry)) {
      throw new DocumentDomainError("invalid_definition", "approval_type");
    }
    return entry;
  });
  if (new Set(result).size !== result.length) {
    throw new DocumentDomainError("invalid_definition", "approval_types");
  }
  return Object.freeze(result);
}

function normalizeStatus(value: unknown): DocumentConfigurationStatus {
  if (
    typeof value !== "string" ||
    !DOCUMENT_CONFIGURATION_STATUSES.includes(
      value as DocumentConfigurationStatus,
    )
  ) {
    throw new DocumentDomainError("invalid_definition", "status");
  }
  return value as DocumentConfigurationStatus;
}

function normalizeFieldSchema(
  schema: unknown,
  suppliedChecksum: unknown,
): { readonly schema: Readonly<PlainRecord>; readonly checksum: string } {
  const record = requirePlainRecord(schema);
  canonicalJson(record);
  const checksum = requireChecksum(suppliedChecksum);
  if (checksumJson(record) !== checksum) {
    throw new DocumentDomainError("checksum_mismatch", "field_schema");
  }
  return Object.freeze({
    schema: freezeJson(record),
    checksum,
  });
}

function sameReference(
  left: ImmutableVersionReference,
  right: ImmutableVersionReference,
): boolean {
  return (
    left.id === right.id &&
    left.key === right.key &&
    left.version === right.version &&
    left.checksum === right.checksum
  );
}

function sameIdentity(
  left: VersionIdentityReference,
  right: ImmutableVersionReference,
): boolean {
  return (
    left.id === right.id &&
    left.key === right.key &&
    left.version === right.version
  );
}

export function computeDocumentTypeVersionChecksum(
  payload: DocumentTypeVersionPayload,
): string {
  return checksumJson(payload);
}

export function computeDocumentTemplateVersionChecksum(
  payload: DocumentTemplateVersionPayload,
): string {
  return checksumJson({
    ...payload,
    sourceBundle: {
      checksum: payload.sourceBundle.checksum,
      sourceHtml: payload.sourceBundle.sourceHtml,
      sourceCss: payload.sourceBundle.sourceCss,
      assets: [...payload.sourceBundle.assets]
        .sort((left, right) => left.key.localeCompare(right.key, "en"))
        .map(({ key, filename, mimeType, byteSize, checksum }) => ({
          key,
          filename,
          mimeType,
          byteSize,
          checksum,
        })),
    },
  });
}

export function normalizeDocumentTypeVersion(
  value: unknown,
): DocumentTypeVersion {
  const record = requirePlainRecord(value);
  assertExactKeys(record, [
    "id",
    "key",
    "version",
    "checksum",
    "labels",
    "fieldSchema",
    "fieldSchemaChecksum",
    "templateVersionRefs",
    "numberingVersionRef",
    "workflowVersionRef",
    "taxPackVersionRef",
    "calculationVersionRef",
    "productionEnabled",
    "requiredApprovalTypes",
    "status",
  ]);
  const templateReferenceValues = requireDenseArray(record.templateVersionRefs);
  if (
    templateReferenceValues.length < 1 ||
    templateReferenceValues.length > 20
  ) {
    throw new DocumentDomainError("invalid_definition", "templates");
  }
  const templateVersionRefs = templateReferenceValues.map(normalizeReference);
  if (
    new Set(templateVersionRefs.map((reference) => reference.id)).size !==
    templateVersionRefs.length
  ) {
    throw new DocumentDomainError("invalid_definition", "templates");
  }
  if (typeof record.productionEnabled !== "boolean") {
    throw new DocumentDomainError("invalid_definition", "production_enabled");
  }
  const fieldSchema = normalizeFieldSchema(
    record.fieldSchema,
    record.fieldSchemaChecksum,
  );
  const normalized: DocumentTypeVersion = {
    id: requireUuid(record.id),
    key: requireKey(record.key),
    version: requireVersion(record.version),
    checksum: requireChecksum(record.checksum),
    labels: normalizeLabels(record.labels),
    fieldSchema: fieldSchema.schema,
    fieldSchemaChecksum: fieldSchema.checksum,
    templateVersionRefs: Object.freeze(templateVersionRefs),
    numberingVersionRef: normalizeReference(record.numberingVersionRef),
    workflowVersionRef: normalizeOptionalReference(record.workflowVersionRef),
    taxPackVersionRef: normalizeOptionalReference(record.taxPackVersionRef),
    calculationVersionRef: normalizeOptionalReference(
      record.calculationVersionRef,
    ),
    productionEnabled: record.productionEnabled,
    requiredApprovalTypes: normalizeApprovalTypes(record.requiredApprovalTypes),
    status: normalizeStatus(record.status),
  };
  const { checksum: _checksum, status: _status, ...payload } = normalized;
  void _checksum;
  void _status;
  if (computeDocumentTypeVersionChecksum(payload) !== normalized.checksum) {
    throw new DocumentDomainError("checksum_mismatch", "document_type");
  }
  return Object.freeze(normalized);
}

export function normalizeDocumentTemplateVersion(
  value: unknown,
): DocumentTemplateVersion {
  const record = requirePlainRecord(value);
  assertExactKeys(record, [
    "id",
    "key",
    "documentTypeRef",
    "version",
    "checksum",
    "locale",
    "rendererVersion",
    "fieldSchema",
    "fieldSchemaChecksum",
    "sourceBundle",
    "productionApproved",
    "requiredApprovalTypes",
    "status",
  ]);
  if (
    typeof record.rendererVersion !== "string" ||
    !RENDERER_VERSION_PATTERN.test(record.rendererVersion) ||
    typeof record.productionApproved !== "boolean"
  ) {
    throw new DocumentDomainError("invalid_definition", "template_metadata");
  }
  const fieldSchema = normalizeFieldSchema(
    record.fieldSchema,
    record.fieldSchemaChecksum,
  );
  const normalized: DocumentTemplateVersion = {
    id: requireUuid(record.id),
    key: requireKey(record.key),
    documentTypeRef: normalizeIdentityReference(record.documentTypeRef),
    version: requireVersion(record.version),
    checksum: requireChecksum(record.checksum),
    locale: requireLocale(record.locale),
    rendererVersion: record.rendererVersion,
    fieldSchema: fieldSchema.schema,
    fieldSchemaChecksum: fieldSchema.checksum,
    sourceBundle: compileDocumentTemplate(record.sourceBundle).sourceBundle,
    productionApproved: record.productionApproved,
    requiredApprovalTypes: normalizeApprovalTypes(record.requiredApprovalTypes),
    status: normalizeStatus(record.status),
  };
  const { checksum: _checksum, status: _status, ...payload } = normalized;
  void _checksum;
  void _status;
  if (computeDocumentTemplateVersionChecksum(payload) !== normalized.checksum) {
    throw new DocumentDomainError("checksum_mismatch", "document_template");
  }
  return Object.freeze(normalized);
}

export function normalizeDocumentApprovalRecord(
  value: unknown,
): DocumentApprovalRecord {
  const record = requirePlainRecord(value);
  assertExactKeys(record, [
    "id",
    "artifactType",
    "artifactId",
    "artifactKey",
    "artifactVersion",
    "artifactChecksum",
    "approvalType",
    "decision",
    "decidedAt",
    "expiresAt",
  ]);
  if (
    typeof record.artifactType !== "string" ||
    !["document_type", "document_template", "numbering_definition"].includes(
      record.artifactType,
    ) ||
    typeof record.approvalType !== "string" ||
    !APPROVAL_TYPE_PATTERN.test(record.approvalType) ||
    typeof record.decision !== "string" ||
    !["approved", "rejected", "revoked"].includes(record.decision) ||
    (record.expiresAt !== null && typeof record.expiresAt !== "string")
  ) {
    throw new DocumentDomainError("invalid_activation", "approval");
  }
  const decidedAt = normalizeIsoInstant(
    record.decidedAt,
    "invalid_activation",
    "approval_decided_at",
  );
  const expiresAt =
    record.expiresAt === null
      ? null
      : normalizeIsoInstant(
          record.expiresAt,
          "invalid_activation",
          "approval_expires_at",
        );
  if (expiresAt !== null && Date.parse(expiresAt) <= Date.parse(decidedAt)) {
    throw new DocumentDomainError("invalid_activation", "approval_expiry");
  }
  return Object.freeze({
    id: requireUuid(record.id),
    artifactType: record.artifactType as DocumentApprovalRecord["artifactType"],
    artifactId: requireUuid(record.artifactId),
    artifactKey: requireKey(record.artifactKey),
    artifactVersion: requireVersion(record.artifactVersion),
    artifactChecksum: requireChecksum(record.artifactChecksum),
    approvalType: record.approvalType,
    decision: record.decision as DocumentApprovalRecord["decision"],
    decidedAt,
    expiresAt,
  });
}

function approvalTargets(
  approval: DocumentApprovalRecord,
  artifactType: DocumentApprovalRecord["artifactType"],
  reference: ImmutableVersionReference,
  approvalType: string,
): boolean {
  return (
    approval.artifactType === artifactType &&
    approval.artifactId === reference.id &&
    approval.artifactKey === reference.key &&
    approval.artifactVersion === reference.version &&
    approval.artifactChecksum === reference.checksum &&
    approval.approvalType === approvalType
  );
}

function verifyApprovals(input: {
  readonly approvals: readonly DocumentApprovalRecord[];
  readonly artifactType: DocumentApprovalRecord["artifactType"];
  readonly reference: ImmutableVersionReference;
  readonly requiredTypes: readonly string[];
  readonly now: number;
}): readonly string[] {
  return Object.freeze(
    input.requiredTypes.map((approvalType) => {
      const matching = input.approvals
        .filter(
          (approval) =>
            approvalTargets(
              approval,
              input.artifactType,
              input.reference,
              approvalType,
            ) && Date.parse(approval.decidedAt) <= input.now,
        )
        .sort(
          (left, right) =>
            Date.parse(right.decidedAt) - Date.parse(left.decidedAt),
        );
      const latest = matching[0];
      if (
        matching[1]?.decidedAt === latest?.decidedAt ||
        latest?.decision !== "approved" ||
        (latest.expiresAt !== null && Date.parse(latest.expiresAt) <= input.now)
      ) {
        throw new DocumentDomainError("approval_required", approvalType);
      }
      return latest.id;
    }),
  );
}

function requireActivatable(status: DocumentConfigurationStatus): void {
  if (status !== "approved" && status !== "active") {
    throw new DocumentDomainError("invalid_activation", status);
  }
}

/** Resolves an exact production-capable configuration; no fallback is allowed. */
export function resolveOfficialDocumentConfiguration(input: {
  readonly documentType: unknown;
  readonly template: unknown;
  readonly numbering: unknown;
  readonly approvals: readonly unknown[];
  readonly now: string;
}): ResolvedDocumentConfiguration {
  assertExactKeys(
    requirePlainRecord(input, "invalid_activation"),
    ["documentType", "template", "numbering", "approvals", "now"],
    "invalid_activation",
  );
  const approvalValues = requireDenseArray(
    input.approvals,
    "invalid_activation",
  );
  if (approvalValues.length > 200) {
    throw new DocumentDomainError("invalid_activation", "approvals");
  }
  const now = Date.parse(
    normalizeIsoInstant(input.now, "invalid_activation", "now"),
  );
  const documentType = normalizeDocumentTypeVersion(input.documentType);
  const template = normalizeDocumentTemplateVersion(input.template);
  const numbering = normalizeNumberingDefinition(input.numbering);
  const approvals = approvalValues.map(normalizeDocumentApprovalRecord);
  if (
    new Set(approvals.map((approval) => approval.id)).size !== approvals.length
  ) {
    throw new DocumentDomainError("invalid_activation", "duplicate_approval");
  }
  requireActivatable(documentType.status);
  requireActivatable(template.status);
  requireActivatable(numbering.status);
  const documentTypeRef = versionReference(documentType);
  const templateRef = versionReference(template);
  const numberingRef = versionReference(numbering);
  if (
    !documentType.productionEnabled ||
    !template.productionApproved ||
    !sameIdentity(template.documentTypeRef, documentTypeRef) ||
    !documentType.templateVersionRefs.some((reference) =>
      sameReference(reference, templateRef),
    ) ||
    !sameReference(documentType.numberingVersionRef, numberingRef) ||
    template.fieldSchemaChecksum !== documentType.fieldSchemaChecksum
  ) {
    throw new DocumentDomainError("invalid_activation", "version_binding");
  }
  const activationEvidence = [
    ...verifyApprovals({
      approvals,
      artifactType: "document_type",
      reference: documentTypeRef,
      requiredTypes: documentType.requiredApprovalTypes,
      now,
    }),
    ...verifyApprovals({
      approvals,
      artifactType: "document_template",
      reference: templateRef,
      requiredTypes: template.requiredApprovalTypes,
      now,
    }),
    ...verifyApprovals({
      approvals,
      artifactType: "numbering_definition",
      reference: numberingRef,
      requiredTypes: numbering.requiredApprovalTypes,
      now,
    }),
  ];
  return Object.freeze({
    documentType: documentTypeRef,
    template: Object.freeze({
      ...templateRef,
      locale: template.locale,
      rendererVersion: template.rendererVersion,
      sourceBundleChecksum: template.sourceBundle.checksum,
    }),
    numbering: numberingRef,
    workflow: documentType.workflowVersionRef,
    taxPack: documentType.taxPackVersionRef,
    calculation: documentType.calculationVersionRef,
    fieldSchemaChecksum: documentType.fieldSchemaChecksum,
    activationEvidence: Object.freeze(activationEvidence),
    productionReady: true,
  });
}

/** Preview accepts a reviewed candidate but still requires exact type/template parity. */
export function resolvePreviewDocumentConfiguration(input: {
  readonly documentType: unknown;
  readonly template: unknown;
}): ResolvedDocumentConfiguration {
  assertExactKeys(
    requirePlainRecord(input, "invalid_activation"),
    ["documentType", "template"],
    "invalid_activation",
  );
  const documentType = normalizeDocumentTypeVersion(input.documentType);
  const template = normalizeDocumentTemplateVersion(input.template);
  if (
    !["reviewed", "approved", "active"].includes(documentType.status) ||
    !["reviewed", "approved", "active"].includes(template.status)
  ) {
    throw new DocumentDomainError("invalid_activation", "preview_status");
  }
  const documentTypeRef = versionReference(documentType);
  const templateRef = versionReference(template);
  if (
    !sameIdentity(template.documentTypeRef, documentTypeRef) ||
    !documentType.templateVersionRefs.some((reference) =>
      sameReference(reference, templateRef),
    ) ||
    template.fieldSchemaChecksum !== documentType.fieldSchemaChecksum
  ) {
    throw new DocumentDomainError("invalid_activation", "version_binding");
  }
  return Object.freeze({
    documentType: documentTypeRef,
    template: Object.freeze({
      ...templateRef,
      locale: template.locale,
      rendererVersion: template.rendererVersion,
      sourceBundleChecksum: template.sourceBundle.checksum,
    }),
    numbering: documentType.numberingVersionRef,
    workflow: documentType.workflowVersionRef,
    taxPack: documentType.taxPackVersionRef,
    calculation: documentType.calculationVersionRef,
    fieldSchemaChecksum: documentType.fieldSchemaChecksum,
    activationEvidence: Object.freeze([]),
    productionReady: false,
  });
}

export function assertConfigurationPayloadImmutable(input: {
  readonly previous: Readonly<{
    checksum: string;
    id: string;
    key: string;
    version: string;
  }>;
  readonly next: Readonly<{
    checksum: string;
    id: string;
    key: string;
    version: string;
  }>;
}): void {
  if (
    input.previous.id !== input.next.id ||
    input.previous.key !== input.next.key ||
    input.previous.version !== input.next.version ||
    input.previous.checksum !== input.next.checksum
  ) {
    throw new DocumentDomainError("invalid_activation", "immutable_version");
  }
}
