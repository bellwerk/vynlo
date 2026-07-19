import {
  assertExactKeys,
  canonicalJson,
  checksumJson,
  DocumentDomainError,
  freezeJson,
  normalizeIsoInstant,
  requireBoundedText,
  requireChecksum,
  requireDenseArray,
  requireLocale,
  requirePlainRecord,
  requireUuid,
  type PlainRecord,
} from "./domain-common";
import {
  versionReference,
  type ImmutableVersionReference,
  type ResolvedDocumentConfiguration,
} from "./configuration";
import { PREVIEW_WATERMARK } from "./first-vertical-slice";

export const DOCUMENT_STATUSES = [
  "queued",
  "render_failed",
  "generated",
  "signed",
  "voided",
  "superseded",
] as const;
export type DocumentStatus = (typeof DOCUMENT_STATUSES)[number];

export const DOCUMENT_FILE_ROLES = [
  "preview",
  "generated_original",
  "signed_scan",
  "attachment",
  "void_notice",
] as const;
export type DocumentFileRole = (typeof DOCUMENT_FILE_ROLES)[number];

const OFFICIAL_NUMBER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$/u;
const FAILURE_CODE_PATTERN = /^[a-z][a-z0-9_.-]{0,99}$/u;
const MIME_TYPE_PATTERN = /^[a-z0-9][a-z0-9.+-]*\/[a-z0-9][a-z0-9.+-]*$/u;

export interface DocumentFileVersion {
  readonly id: string;
  readonly role: DocumentFileRole;
  readonly version: number;
  readonly storageFileId: string;
  readonly filename: string;
  readonly mimeType: string;
  readonly byteSize: number;
  readonly checksum: string;
  readonly createdAt: string;
}

export interface ImmutableDocumentSnapshot {
  readonly id: string;
  readonly mode: "preview" | "official";
  readonly status: DocumentStatus;
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
  readonly officialNumber: string | null;
  readonly numberAllocationId: string | null;
  readonly intendedSignatureDate: string | null;
  readonly watermark: typeof PREVIEW_WATERMARK | null;
  readonly renderInputSnapshot: Readonly<PlainRecord>;
  readonly renderInputChecksum: string;
  readonly generatedChecksum: string | null;
  readonly failureCode: string | null;
  readonly renderAttempt: number;
  readonly files: readonly DocumentFileVersion[];
  readonly currentSignedFileId: string | null;
  readonly supersedesDocumentId: string | null;
  readonly supersededByDocumentId: string | null;
  readonly voidReason: string | null;
  readonly supersedesReason: string | null;
  readonly supersededReason: string | null;
  readonly version: number;
}

type NewDocumentFile = Omit<DocumentFileVersion, "role" | "version">;

function validDate(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/u.test(value)) {
    throw new DocumentDomainError("invalid_document", "signature_date");
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (date.toISOString().slice(0, 10) !== value) {
    throw new DocumentDomainError("invalid_document", "signature_date");
  }
  return value;
}

function validateConfiguration(
  value: ResolvedDocumentConfiguration,
  requireProduction: boolean,
): ResolvedDocumentConfiguration {
  const record = requirePlainRecord(value, "invalid_document");
  assertExactKeys(
    record,
    [
      "documentType",
      "template",
      "numbering",
      "workflow",
      "taxPack",
      "calculation",
      "fieldSchemaChecksum",
      "activationEvidence",
      "productionReady",
    ],
    "invalid_document",
  );
  if (
    value.productionReady !== requireProduction ||
    typeof value.fieldSchemaChecksum !== "string" ||
    requireChecksum(value.fieldSchemaChecksum) !== value.fieldSchemaChecksum ||
    !Array.isArray(value.activationEvidence) ||
    value.activationEvidence.length > 100 ||
    (!requireProduction && value.activationEvidence.length !== 0)
  ) {
    throw new DocumentDomainError("invalid_document", "configuration");
  }
  assertConfigurationReference(value.documentType);
  assertTemplateReference(value.template);
  assertConfigurationReference(value.numbering);
  if (value.workflow) assertConfigurationReference(value.workflow);
  if (value.taxPack) assertConfigurationReference(value.taxPack);
  if (value.calculation) assertConfigurationReference(value.calculation);
  const evidence = requireDenseArray(
    value.activationEvidence,
    "invalid_document",
  ).map(requireUuid);
  if (
    new Set(evidence).size !== evidence.length ||
    evidence.some((id, index) => id !== value.activationEvidence[index])
  ) {
    throw new DocumentDomainError("invalid_document", "activation_evidence");
  }
  if (
    requireChecksum(value.template.sourceBundleChecksum) !==
    value.template.sourceBundleChecksum
  ) {
    throw new DocumentDomainError("invalid_document", "template_configuration");
  }
  return value;
}

function immutableConfiguration(
  value: ResolvedDocumentConfiguration,
): Pick<
  ImmutableDocumentSnapshot,
  | "documentType"
  | "template"
  | "numbering"
  | "workflow"
  | "taxPack"
  | "calculation"
  | "fieldSchemaChecksum"
> {
  return {
    documentType: Object.freeze({ ...value.documentType }),
    template: Object.freeze({ ...value.template }),
    numbering: Object.freeze({ ...value.numbering }),
    workflow: value.workflow ? Object.freeze({ ...value.workflow }) : null,
    taxPack: value.taxPack ? Object.freeze({ ...value.taxPack }) : null,
    calculation: value.calculation
      ? Object.freeze({ ...value.calculation })
      : null,
    fieldSchemaChecksum: value.fieldSchemaChecksum,
  };
}

function normalizeRenderInput(input: {
  readonly snapshot: unknown;
  readonly checksum: unknown;
}): { readonly snapshot: Readonly<PlainRecord>; readonly checksum: string } {
  const record = requirePlainRecord(input.snapshot, "invalid_document");
  canonicalJson(record);
  const checksum = requireChecksum(input.checksum);
  if (checksumJson(record) !== checksum) {
    throw new DocumentDomainError("checksum_mismatch", "render_input");
  }
  return Object.freeze({ snapshot: freezeJson(record), checksum });
}

function baseDocument(input: {
  readonly id: unknown;
  readonly configuration: ResolvedDocumentConfiguration;
  readonly mode: "preview" | "official";
  readonly renderInputSnapshot: unknown;
  readonly renderInputChecksum: unknown;
  readonly intendedSignatureDate: unknown;
  readonly officialNumber: string | null;
  readonly numberAllocationId: string | null;
}): ImmutableDocumentSnapshot {
  const renderInput = normalizeRenderInput({
    snapshot: input.renderInputSnapshot,
    checksum: input.renderInputChecksum,
  });
  return Object.freeze({
    id: requireUuid(input.id),
    mode: input.mode,
    status: "queued",
    ...immutableConfiguration(input.configuration),
    officialNumber: input.officialNumber,
    numberAllocationId: input.numberAllocationId,
    intendedSignatureDate: validDate(input.intendedSignatureDate),
    watermark: input.mode === "preview" ? PREVIEW_WATERMARK : null,
    renderInputSnapshot: renderInput.snapshot,
    renderInputChecksum: renderInput.checksum,
    generatedChecksum: null,
    failureCode: null,
    renderAttempt: 1,
    files: Object.freeze([]),
    currentSignedFileId: null,
    supersedesDocumentId: null,
    supersededByDocumentId: null,
    voidReason: null,
    supersedesReason: null,
    supersededReason: null,
    version: 1,
  });
}

export function createPreviewDocument(input: {
  readonly id: unknown;
  readonly configuration: ResolvedDocumentConfiguration;
  readonly renderInputSnapshot: unknown;
  readonly renderInputChecksum: unknown;
}): ImmutableDocumentSnapshot {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    ["id", "configuration", "renderInputSnapshot", "renderInputChecksum"],
    "invalid_document",
  );
  validateConfiguration(input.configuration, false);
  return baseDocument({
    ...input,
    mode: "preview",
    intendedSignatureDate: null,
    officialNumber: null,
    numberAllocationId: null,
  });
}

export function createOfficialDocument(input: {
  readonly id: unknown;
  readonly configuration: ResolvedDocumentConfiguration;
  readonly renderInputSnapshot: unknown;
  readonly renderInputChecksum: unknown;
  readonly officialNumber: unknown;
  readonly numberAllocationId: unknown;
  readonly intendedSignatureDate: unknown;
}): ImmutableDocumentSnapshot {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    [
      "id",
      "configuration",
      "renderInputSnapshot",
      "renderInputChecksum",
      "officialNumber",
      "numberAllocationId",
      "intendedSignatureDate",
    ],
    "invalid_document",
  );
  validateConfiguration(input.configuration, true);
  if (
    typeof input.officialNumber !== "string" ||
    !OFFICIAL_NUMBER_PATTERN.test(input.officialNumber)
  ) {
    throw new DocumentDomainError("invalid_document", "official_number");
  }
  return baseDocument({
    ...input,
    mode: "official",
    officialNumber: input.officialNumber,
    numberAllocationId: requireUuid(input.numberAllocationId),
  });
}

function assertDocumentInvariant(document: ImmutableDocumentSnapshot): void {
  const record = requirePlainRecord(document, "invalid_document");
  assertExactKeys(
    record,
    [
      "id",
      "mode",
      "status",
      "documentType",
      "template",
      "numbering",
      "workflow",
      "taxPack",
      "calculation",
      "fieldSchemaChecksum",
      "officialNumber",
      "numberAllocationId",
      "intendedSignatureDate",
      "watermark",
      "renderInputSnapshot",
      "renderInputChecksum",
      "generatedChecksum",
      "failureCode",
      "renderAttempt",
      "files",
      "currentSignedFileId",
      "supersedesDocumentId",
      "supersededByDocumentId",
      "voidReason",
      "supersedesReason",
      "supersededReason",
      "version",
    ],
    "invalid_document",
  );
  requireUuid(document.id);
  if (
    !["preview", "official"].includes(document.mode) ||
    !DOCUMENT_STATUSES.includes(document.status) ||
    !Array.isArray(document.files) ||
    !Number.isSafeInteger(document.version) ||
    document.version < 1 ||
    !Number.isSafeInteger(document.renderAttempt) ||
    document.renderAttempt < 1 ||
    checksumJson(document.renderInputSnapshot) !== document.renderInputChecksum
  ) {
    throw new DocumentDomainError("invalid_document");
  }
  canonicalJson(document.files);
  assertConfigurationReference(document.documentType);
  assertTemplateReference(document.template);
  assertConfigurationReference(document.numbering);
  if (document.workflow) assertConfigurationReference(document.workflow);
  if (document.taxPack) assertConfigurationReference(document.taxPack);
  if (document.calculation) assertConfigurationReference(document.calculation);
  requireChecksum(document.fieldSchemaChecksum);
  requireChecksum(document.renderInputChecksum);
  if (document.generatedChecksum !== null) {
    requireChecksum(document.generatedChecksum);
  }
  if (
    document.mode === "preview"
      ? document.officialNumber !== null ||
        document.numberAllocationId !== null ||
        document.watermark !== PREVIEW_WATERMARK ||
        document.intendedSignatureDate !== null
      : typeof document.officialNumber !== "string" ||
        !OFFICIAL_NUMBER_PATTERN.test(document.officialNumber) ||
        document.numberAllocationId === null ||
        requireUuid(document.numberAllocationId) !==
          document.numberAllocationId ||
        document.watermark !== null ||
        validDate(document.intendedSignatureDate) !==
          document.intendedSignatureDate
  ) {
    throw new DocumentDomainError("invalid_document", "mode");
  }
  if (
    document.mode === "preview" &&
    (!["queued", "render_failed", "generated"].includes(document.status) ||
      document.files.some((file) => file.role === "signed_scan") ||
      document.currentSignedFileId !== null ||
      document.supersedesDocumentId !== null ||
      document.supersededByDocumentId !== null)
  ) {
    throw new DocumentDomainError("invalid_document", "preview_state");
  }
  const generatedRoles = document.files.filter((file) =>
    ["preview", "generated_original"].includes(file.role),
  );
  if (generatedRoles.length > 1) {
    throw new DocumentDomainError("duplicate_document_file", "generated");
  }
  if (
    document.currentSignedFileId !== null &&
    (requireUuid(document.currentSignedFileId) !==
      document.currentSignedFileId ||
      !document.files.some(
        (file) =>
          file.id === document.currentSignedFileId &&
          file.role === "signed_scan",
      ))
  ) {
    throw new DocumentDomainError("invalid_document", "signed_selection");
  }
  const fileIds = new Set<string>();
  const storageFileIds = new Set<string>();
  const roleVersions = new Set<string>();
  for (const file of document.files) {
    assertDocumentFileInvariant(file);
    const roleVersion = `${file.role}:${file.version}`;
    if (
      fileIds.has(file.id) ||
      storageFileIds.has(file.storageFileId) ||
      roleVersions.has(roleVersion)
    ) {
      throw new DocumentDomainError("duplicate_document_file", "identity");
    }
    fileIds.add(file.id);
    storageFileIds.add(file.storageFileId);
    roleVersions.add(roleVersion);
  }
  const signedVersions = document.files
    .filter((file) => file.role === "signed_scan")
    .map((file) => file.version)
    .sort((left, right) => left - right);
  if (signedVersions.some((version, index) => version !== index + 1)) {
    throw new DocumentDomainError("invalid_document", "signed_versions");
  }
  if (document.files.length > 1_000) {
    throw new DocumentDomainError("invalid_document", "file_limit");
  }
  const generatedFile = generatedRoles[0];
  if (
    (generatedFile === undefined) !== (document.generatedChecksum === null) ||
    (generatedFile !== undefined &&
      generatedFile.checksum !== document.generatedChecksum) ||
    (generatedFile !== undefined &&
      generatedFile.role !==
        (document.mode === "preview" ? "preview" : "generated_original")) ||
    (["queued", "render_failed"].includes(document.status) &&
      generatedFile !== undefined) ||
    (document.status === "generated" && generatedFile === undefined) ||
    (document.status === "signed" &&
      (generatedFile === undefined || document.currentSignedFileId === null)) ||
    (document.status === "render_failed" &&
      (document.failureCode === null ||
        !FAILURE_CODE_PATTERN.test(document.failureCode))) ||
    (document.status === "voided" &&
      (generatedFile === undefined
        ? document.failureCode === null ||
          !FAILURE_CODE_PATTERN.test(document.failureCode)
        : document.failureCode !== null)) ||
    (["queued", "generated", "signed"].includes(document.status) &&
      document.failureCode !== null)
  ) {
    throw new DocumentDomainError("invalid_document", "state");
  }
  if (
    document.supersedesDocumentId !== null &&
    requireUuid(document.supersedesDocumentId) !== document.supersedesDocumentId
  ) {
    throw new DocumentDomainError("invalid_document", "supersedes");
  }
  if (
    document.supersededByDocumentId !== null &&
    requireUuid(document.supersededByDocumentId) !==
      document.supersededByDocumentId
  ) {
    throw new DocumentDomainError("invalid_document", "superseded_by");
  }
  if (
    (document.supersedesDocumentId === null) !==
      (document.supersedesReason === null) ||
    (document.supersededByDocumentId === null) !==
      (document.supersededReason === null) ||
    (document.status === "superseded") !==
      (document.supersededByDocumentId !== null) ||
    (document.status === "voided" && document.voidReason === null) ||
    (document.voidReason !== null &&
      !["voided", "superseded"].includes(document.status))
  ) {
    throw new DocumentDomainError("invalid_document", "lineage");
  }
  for (const reason of [
    document.voidReason,
    document.supersedesReason,
    document.supersededReason,
  ]) {
    if (
      reason !== null &&
      requireBoundedText(reason, 2_000, "invalid_document") !== reason
    ) {
      throw new DocumentDomainError("invalid_document", "reason");
    }
  }
}

function assertConfigurationReference(value: ImmutableVersionReference): void {
  const record = requirePlainRecord(value, "invalid_document");
  assertExactKeys(
    record,
    ["id", "key", "version", "checksum"],
    "invalid_document",
  );
  const normalized = versionReference(value);
  if (canonicalJson(normalized) !== canonicalJson(value)) {
    throw new DocumentDomainError(
      "invalid_document",
      "configuration_reference",
    );
  }
}

function assertTemplateReference(
  value: ImmutableDocumentSnapshot["template"],
): void {
  const record = requirePlainRecord(value, "invalid_document");
  assertExactKeys(
    record,
    [
      "id",
      "key",
      "version",
      "checksum",
      "locale",
      "rendererVersion",
      "sourceBundleChecksum",
    ],
    "invalid_document",
  );
  const normalized = versionReference(value);
  const rendererVersion = requireBoundedText(
    value.rendererVersion,
    128,
    "invalid_document",
  );
  if (
    normalized.id !== value.id ||
    normalized.key !== value.key ||
    normalized.version !== value.version ||
    normalized.checksum !== value.checksum ||
    requireLocale(value.locale) !== value.locale ||
    rendererVersion !== value.rendererVersion ||
    !/^[a-z][a-z0-9_.-]{0,127}$/u.test(rendererVersion)
  ) {
    throw new DocumentDomainError("invalid_document", "template_reference");
  }
  requireChecksum(value.sourceBundleChecksum);
}

function assertDocumentFileInvariant(file: DocumentFileVersion): void {
  const record = requirePlainRecord(file, "invalid_document");
  assertExactKeys(
    record,
    [
      "id",
      "role",
      "version",
      "storageFileId",
      "filename",
      "mimeType",
      "byteSize",
      "checksum",
      "createdAt",
    ],
    "invalid_document",
  );
  if (
    !DOCUMENT_FILE_ROLES.includes(file.role) ||
    !Number.isSafeInteger(file.version) ||
    file.version < 1 ||
    (["preview", "generated_original"].includes(file.role) &&
      file.version !== 1) ||
    typeof file.filename !== "string" ||
    !file.filename ||
    file.filename.trim() !== file.filename ||
    file.filename.length > 255 ||
    file.filename.includes("/") ||
    file.filename.includes("\\") ||
    /[\u0000-\u001f\u007f]/u.test(file.filename) ||
    typeof file.mimeType !== "string" ||
    !MIME_TYPE_PATTERN.test(file.mimeType) ||
    file.mimeType !== file.mimeType.toLowerCase() ||
    !Number.isSafeInteger(file.byteSize) ||
    file.byteSize < 1 ||
    file.byteSize > 50_000_000 ||
    normalizeIsoInstant(
      file.createdAt,
      "invalid_document",
      "file_created_at",
    ) !== file.createdAt
  ) {
    throw new DocumentDomainError("invalid_document", "file");
  }
  requireUuid(file.id);
  requireUuid(file.storageFileId);
  requireChecksum(file.checksum);
}

function nextVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value >= Number.MAX_SAFE_INTEGER) {
    throw new DocumentDomainError(
      "invalid_document_transition",
      "version_overflow",
    );
  }
  return value + 1;
}

function normalizeFile(
  value: NewDocumentFile,
  role: DocumentFileRole,
  version: number,
): DocumentFileVersion {
  const record = requirePlainRecord(value, "invalid_document");
  assertExactKeys(
    record,
    [
      "id",
      "storageFileId",
      "filename",
      "mimeType",
      "byteSize",
      "checksum",
      "createdAt",
    ],
    "invalid_document",
  );
  if (
    typeof record.filename !== "string" ||
    !record.filename.trim() ||
    record.filename.length > 255 ||
    record.filename.includes("/") ||
    record.filename.includes("\\") ||
    /[\u0000-\u001f\u007f]/u.test(record.filename) ||
    typeof record.mimeType !== "string" ||
    !MIME_TYPE_PATTERN.test(record.mimeType) ||
    !Number.isSafeInteger(record.byteSize) ||
    (record.byteSize as number) < 1 ||
    (record.byteSize as number) > 50_000_000
  ) {
    throw new DocumentDomainError("invalid_document", "file");
  }
  return Object.freeze({
    id: requireUuid(record.id),
    role,
    version,
    storageFileId: requireUuid(record.storageFileId),
    filename: record.filename.trim(),
    mimeType: record.mimeType.toLowerCase(),
    byteSize: record.byteSize as number,
    checksum: requireChecksum(record.checksum),
    createdAt: normalizeIsoInstant(
      record.createdAt,
      "invalid_document",
      "file_created_at",
    ),
  });
}

function sameFile(
  left: DocumentFileVersion,
  right: DocumentFileVersion,
): boolean {
  return canonicalJson(left) === canonicalJson(right);
}

export function recordGeneratedDocumentFile(input: {
  readonly document: ImmutableDocumentSnapshot;
  readonly file: NewDocumentFile;
}): ImmutableDocumentSnapshot {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    ["document", "file"],
    "invalid_document",
  );
  assertDocumentInvariant(input.document);
  const role =
    input.document.mode === "preview" ? "preview" : "generated_original";
  const file = normalizeFile(input.file, role, 1);
  if (file.mimeType !== "application/pdf") {
    throw new DocumentDomainError("invalid_document", "generated_pdf");
  }
  const existing = input.document.files.find(
    (candidate) => candidate.role === role,
  );
  if (existing) {
    if (sameFile(existing, file)) {
      return input.document;
    }
    throw new DocumentDomainError("duplicate_document_file", role);
  }
  if (input.document.status !== "queued") {
    throw new DocumentDomainError("invalid_document_transition", "generated");
  }
  if (input.document.files.length >= 1_000) {
    throw new DocumentDomainError("invalid_document_transition", "file_limit");
  }
  return Object.freeze({
    ...input.document,
    status: "generated",
    generatedChecksum: file.checksum,
    failureCode: null,
    files: Object.freeze([...input.document.files, file]),
    version: nextVersion(input.document.version),
  });
}

export function failDocumentRender(input: {
  readonly document: ImmutableDocumentSnapshot;
  readonly failureCode: unknown;
}): ImmutableDocumentSnapshot {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    ["document", "failureCode"],
    "invalid_document",
  );
  assertDocumentInvariant(input.document);
  if (
    input.document.status !== "queued" ||
    typeof input.failureCode !== "string" ||
    !FAILURE_CODE_PATTERN.test(input.failureCode)
  ) {
    throw new DocumentDomainError(
      "invalid_document_transition",
      "render_failure",
    );
  }
  return Object.freeze({
    ...input.document,
    status: "render_failed",
    failureCode: input.failureCode,
    version: nextVersion(input.document.version),
  });
}

export function retryDocumentRender(
  document: ImmutableDocumentSnapshot,
): ImmutableDocumentSnapshot {
  assertDocumentInvariant(document);
  if (document.status !== "render_failed") {
    throw new DocumentDomainError("invalid_document_transition", "retry");
  }
  if (document.renderAttempt >= Number.MAX_SAFE_INTEGER) {
    throw new DocumentDomainError(
      "invalid_document_transition",
      "attempt_overflow",
    );
  }
  return Object.freeze({
    ...document,
    status: "queued",
    failureCode: null,
    renderAttempt: document.renderAttempt + 1,
    version: nextVersion(document.version),
  });
}

export function registerSignedDocumentFile(input: {
  readonly document: ImmutableDocumentSnapshot;
  readonly file: NewDocumentFile;
}): ImmutableDocumentSnapshot {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    ["document", "file"],
    "invalid_document",
  );
  assertDocumentInvariant(input.document);
  if (
    input.document.mode !== "official" ||
    !["generated", "signed"].includes(input.document.status)
  ) {
    throw new DocumentDomainError("invalid_document_transition", "signed_file");
  }
  const fileRecord = requirePlainRecord(input.file, "invalid_document");
  const candidateFileId = requireUuid(fileRecord.id);
  const existingById = input.document.files.find(
    (candidate) => candidate.id === candidateFileId,
  );
  if (existingById) {
    const replay = normalizeFile(
      input.file,
      "signed_scan",
      existingById.version,
    );
    if (existingById.role === "signed_scan" && sameFile(existingById, replay)) {
      return input.document;
    }
    throw new DocumentDomainError("duplicate_document_file", "signed_scan");
  }
  if (input.document.files.length >= 1_000) {
    throw new DocumentDomainError("invalid_document_transition", "file_limit");
  }
  const signedVersion =
    input.document.files.filter((file) => file.role === "signed_scan").length +
    1;
  const file = normalizeFile(input.file, "signed_scan", signedVersion);
  if (
    ![
      "application/pdf",
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/heic",
      "image/heif",
    ].includes(file.mimeType)
  ) {
    throw new DocumentDomainError("invalid_document", "signed_file_type");
  }
  if (
    input.document.files.some(
      (candidate) => candidate.storageFileId === file.storageFileId,
    )
  ) {
    throw new DocumentDomainError("duplicate_document_file", "storage_file");
  }
  return Object.freeze({
    ...input.document,
    files: Object.freeze([...input.document.files, file]),
    currentSignedFileId: file.id,
    version: nextVersion(input.document.version),
  });
}

export function selectCurrentSignedFile(input: {
  readonly document: ImmutableDocumentSnapshot;
  readonly fileId: unknown;
}): ImmutableDocumentSnapshot {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    ["document", "fileId"],
    "invalid_document",
  );
  assertDocumentInvariant(input.document);
  const fileId = requireUuid(input.fileId);
  if (
    input.document.mode !== "official" ||
    !["generated", "signed"].includes(input.document.status) ||
    !input.document.files.some(
      (file) => file.id === fileId && file.role === "signed_scan",
    )
  ) {
    throw new DocumentDomainError(
      "invalid_document_transition",
      "signed_selection",
    );
  }
  if (input.document.currentSignedFileId === fileId) return input.document;
  return Object.freeze({
    ...input.document,
    currentSignedFileId: fileId,
    version: nextVersion(input.document.version),
  });
}

export function markDocumentSigned(
  document: ImmutableDocumentSnapshot,
): ImmutableDocumentSnapshot {
  assertDocumentInvariant(document);
  if (
    document.mode !== "official" ||
    document.status !== "generated" ||
    document.currentSignedFileId === null
  ) {
    throw new DocumentDomainError("invalid_document_transition", "mark_signed");
  }
  return Object.freeze({
    ...document,
    status: "signed",
    version: nextVersion(document.version),
  });
}

export function voidDocument(input: {
  readonly document: ImmutableDocumentSnapshot;
  readonly reason: unknown;
  readonly allowSignedVoid: boolean;
}): ImmutableDocumentSnapshot {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    ["document", "reason", "allowSignedVoid"],
    "invalid_document",
  );
  assertDocumentInvariant(input.document);
  if (
    typeof input.allowSignedVoid !== "boolean" ||
    input.document.mode !== "official" ||
    !["generated", "render_failed", "signed", "voided"].includes(
      input.document.status,
    )
  ) {
    throw new DocumentDomainError("invalid_document_transition", "void");
  }
  const reason = requireBoundedText(input.reason, 2_000, "reason_required");
  if (input.document.status === "voided") {
    if (input.document.voidReason === reason) return input.document;
    throw new DocumentDomainError("invalid_document_transition", "void_reason");
  }
  if (input.document.status === "signed" && !input.allowSignedVoid) {
    throw new DocumentDomainError("invalid_document_transition", "void_signed");
  }
  return Object.freeze({
    ...input.document,
    status: "voided",
    voidReason: reason,
    version: nextVersion(input.document.version),
  });
}

export function supersedeDocument(input: {
  readonly original: ImmutableDocumentSnapshot;
  readonly replacement: ImmutableDocumentSnapshot;
  readonly reason: unknown;
}): Readonly<{
  original: ImmutableDocumentSnapshot;
  replacement: ImmutableDocumentSnapshot;
}> {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    ["original", "replacement", "reason"],
    "invalid_document",
  );
  assertDocumentInvariant(input.original);
  assertDocumentInvariant(input.replacement);
  const reason = requireBoundedText(input.reason, 2_000, "reason_required");
  if (
    input.original.mode !== "official" ||
    input.replacement.mode !== "official" ||
    input.original.id === input.replacement.id ||
    input.original.status === "superseded" ||
    input.original.supersededByDocumentId !== null ||
    input.replacement.status !== "queued" ||
    input.replacement.supersedesDocumentId !== null ||
    input.replacement.supersededByDocumentId !== null ||
    input.original.documentType.key !== input.replacement.documentType.key ||
    input.original.renderInputChecksum ===
      input.replacement.renderInputChecksum ||
    input.original.officialNumber === input.replacement.officialNumber ||
    input.original.numberAllocationId === input.replacement.numberAllocationId
  ) {
    throw new DocumentDomainError("invalid_document_transition", "supersede");
  }
  return Object.freeze({
    original: Object.freeze({
      ...input.original,
      status: "superseded",
      supersededByDocumentId: input.replacement.id,
      supersededReason: reason,
      version: nextVersion(input.original.version),
    }),
    replacement: Object.freeze({
      ...input.replacement,
      supersedesDocumentId: input.original.id,
      supersedesReason: reason,
      version: nextVersion(input.replacement.version),
    }),
  });
}

export function assertDocumentImmutableFields(input: {
  readonly previous: ImmutableDocumentSnapshot;
  readonly next: ImmutableDocumentSnapshot;
}): void {
  assertDocumentInvariant(input.previous);
  assertDocumentInvariant(input.next);
  const immutableProjection = (document: ImmutableDocumentSnapshot) => ({
    id: document.id,
    mode: document.mode,
    documentType: document.documentType,
    template: document.template,
    numbering: document.numbering,
    workflow: document.workflow,
    taxPack: document.taxPack,
    calculation: document.calculation,
    fieldSchemaChecksum: document.fieldSchemaChecksum,
    officialNumber: document.officialNumber,
    numberAllocationId: document.numberAllocationId,
    intendedSignatureDate: document.intendedSignatureDate,
    watermark: document.watermark,
    renderInputSnapshot: document.renderInputSnapshot,
    renderInputChecksum: document.renderInputChecksum,
  });
  if (
    canonicalJson(immutableProjection(input.previous)) !==
    canonicalJson(immutableProjection(input.next))
  ) {
    throw new DocumentDomainError("immutable_document_field");
  }
}

export function assertDocumentFileImmutable(input: {
  readonly previous: DocumentFileVersion;
  readonly next: DocumentFileVersion;
}): void {
  assertDocumentFileInvariant(input.previous);
  assertDocumentFileInvariant(input.next);
  if (canonicalJson(input.previous) !== canonicalJson(input.next)) {
    throw new DocumentDomainError("immutable_document_field", "document_file");
  }
}
