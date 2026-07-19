import {
  assertExactKeys,
  checksumJson,
  DocumentDomainError,
  normalizeIsoInstant,
  normalizeLabels,
  requireChecksum,
  requireDenseArray,
  requireKey,
  requirePlainRecord,
  requireUuid,
  requireVersion,
} from "./domain-common";

export const NUMBERING_SCOPE_DIMENSIONS = [
  "workspace",
  "legal_entity",
  "location",
  "document_type",
] as const;
export type NumberingScopeDimension =
  (typeof NUMBERING_SCOPE_DIMENSIONS)[number];

export const NUMBERING_RESET_POLICIES = ["never", "yearly", "monthly"] as const;
export type NumberingResetPolicy = (typeof NUMBERING_RESET_POLICIES)[number];

export const NUMBERING_VERSION_STATUSES = [
  "draft",
  "validated",
  "test_passed",
  "reviewed",
  "approved",
  "active",
  "superseded",
  "retired",
] as const;
export type NumberingVersionStatus =
  (typeof NUMBERING_VERSION_STATUSES)[number];

const POSITIVE_BIGINT_PATTERN = /^[1-9][0-9]{0,18}$/u;
const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;
const LITERAL_PATTERN = /^[A-Za-z0-9._/-]{0,32}$/u;
const SUFFIX_PATTERN = /^[A-Za-z0-9._-]{1,32}$/u;
const SCOPE_KEY_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$/u;
const FORMATTED_NUMBER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$/u;
const FORMAT_TOKEN =
  /\{\{(prefix|scope|suffix|deterministic_suffix|period|sequence(?::\d{1,2})?)\}\}/gu;
const APPROVAL_KEY_PATTERN =
  /^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})*$/u;

export interface VersionedNumberingDefinition {
  readonly id: string;
  readonly key: string;
  readonly version: string;
  readonly checksum: string;
  readonly labels: Readonly<Record<"en" | "fr", string>>;
  readonly scopeDimensions: readonly NumberingScopeDimension[];
  readonly prefix: string;
  readonly suffix: string;
  readonly numericWidth: number;
  readonly startingValue: string;
  readonly increment: string;
  readonly reset: NumberingResetPolicy;
  readonly timezone: string;
  readonly formatPattern: string;
  readonly deterministicSuffix: "none" | "provided";
  readonly importsAllowed: boolean;
  readonly reservationsAllowed: boolean;
  readonly reusePolicy: "never";
  readonly allocationEvent: "official_document_created";
  readonly requiredApprovalTypes: readonly string[];
  readonly status: NumberingVersionStatus;
}

export type NumberingDefinitionPayload = Omit<
  VersionedNumberingDefinition,
  "checksum" | "status"
>;

function requirePositiveBigint(value: unknown): string {
  if (typeof value !== "string" || !POSITIVE_BIGINT_PATTERN.test(value)) {
    throw new DocumentDomainError("invalid_numbering_definition", "integer");
  }
  const parsed = BigInt(value);
  if (parsed > POSTGRES_BIGINT_MAX) {
    throw new DocumentDomainError("invalid_numbering_definition", "integer");
  }
  return parsed.toString();
}

function requireTimezone(value: unknown): string {
  if (typeof value !== "string" || value.length < 1 || value.length > 100) {
    throw new DocumentDomainError("invalid_numbering_definition", "timezone");
  }
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: value }).format(0);
  } catch {
    throw new DocumentDomainError("invalid_numbering_definition", "timezone");
  }
  return value;
}

function normalizeApprovals(value: unknown): readonly string[] {
  const values = requireDenseArray(value, "invalid_numbering_definition");
  if (values.length > 20) {
    throw new DocumentDomainError("invalid_numbering_definition", "approvals");
  }
  const approvals = values.map((entry) => {
    if (typeof entry !== "string" || !APPROVAL_KEY_PATTERN.test(entry)) {
      throw new DocumentDomainError(
        "invalid_numbering_definition",
        "approval_type",
      );
    }
    return entry;
  });
  if (new Set(approvals).size !== approvals.length) {
    throw new DocumentDomainError("invalid_numbering_definition", "approvals");
  }
  return Object.freeze(approvals);
}

function validateFormatPattern(input: {
  readonly formatPattern: string;
  readonly numericWidth: number;
  readonly reset: NumberingResetPolicy;
  readonly scopeDimensions: readonly NumberingScopeDimension[];
  readonly deterministicSuffix: "none" | "provided";
  readonly prefix: string;
  readonly suffix: string;
}): void {
  if (
    !input.formatPattern ||
    input.formatPattern.length > 128 ||
    /[\u0000-\u001f\u007f]/u.test(input.formatPattern)
  ) {
    throw new DocumentDomainError("invalid_numbering_definition", "format");
  }
  const tokens = [...input.formatPattern.matchAll(FORMAT_TOKEN)].map(
    (match) => match[1] ?? "",
  );
  const remaining = input.formatPattern.replaceAll(FORMAT_TOKEN, "");
  if (
    remaining.includes("{{") ||
    remaining.includes("}}") ||
    !/^[A-Za-z0-9._/-]*$/u.test(remaining)
  ) {
    throw new DocumentDomainError(
      "arbitrary_execution_not_allowed",
      "number_format",
    );
  }
  const sequenceTokens = tokens.filter((token) => token.startsWith("sequence"));
  if (sequenceTokens.length !== 1) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "sequence_token",
    );
  }
  const width = sequenceTokens[0]?.split(":")[1];
  if (width !== undefined && Number(width) !== input.numericWidth) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "sequence_width",
    );
  }
  if (
    tokens.filter((token) => token === "prefix").length > 1 ||
    tokens.filter((token) => token === "suffix").length > 1 ||
    tokens.filter((token) => token === "deterministic_suffix").length > 1 ||
    tokens.filter((token) => token === "scope").length > 1 ||
    tokens.filter((token) => token === "period").length > 1
  ) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "duplicate_token",
    );
  }
  const hasPeriod = tokens.includes("period");
  if ((input.reset === "never") === hasPeriod) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "period_token",
    );
  }
  if (tokens.includes("scope") !== input.scopeDimensions.length > 1) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "scope_token",
    );
  }
  if (
    tokens.includes("prefix") !== (input.prefix !== "") ||
    tokens.includes("suffix") !== (input.suffix !== "") ||
    tokens.includes("deterministic_suffix") !==
      (input.deterministicSuffix === "provided")
  ) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "suffix_token",
    );
  }
}

export function computeNumberingDefinitionChecksum(
  payload: NumberingDefinitionPayload,
): string {
  return checksumJson(payload);
}

export function normalizeNumberingDefinition(
  value: unknown,
): VersionedNumberingDefinition {
  const record = requirePlainRecord(value, "invalid_numbering_definition");
  assertExactKeys(
    record,
    [
      "id",
      "key",
      "version",
      "checksum",
      "labels",
      "scopeDimensions",
      "prefix",
      "suffix",
      "numericWidth",
      "startingValue",
      "increment",
      "reset",
      "timezone",
      "formatPattern",
      "deterministicSuffix",
      "importsAllowed",
      "reservationsAllowed",
      "reusePolicy",
      "allocationEvent",
      "requiredApprovalTypes",
      "status",
    ],
    "invalid_numbering_definition",
  );
  const scopeDimensions = requireDenseArray(
    record.scopeDimensions,
    "invalid_numbering_definition",
  ).map((entry) => {
    if (
      typeof entry !== "string" ||
      !NUMBERING_SCOPE_DIMENSIONS.includes(entry as NumberingScopeDimension)
    ) {
      throw new DocumentDomainError("invalid_numbering_definition", "scope");
    }
    return entry as NumberingScopeDimension;
  });
  if (
    scopeDimensions.length < 1 ||
    scopeDimensions.length > NUMBERING_SCOPE_DIMENSIONS.length ||
    scopeDimensions[0] !== "workspace" ||
    new Set(scopeDimensions).size !== scopeDimensions.length
  ) {
    throw new DocumentDomainError("invalid_numbering_definition", "scope");
  }
  if (
    typeof record.prefix !== "string" ||
    !LITERAL_PATTERN.test(record.prefix) ||
    typeof record.suffix !== "string" ||
    !LITERAL_PATTERN.test(record.suffix)
  ) {
    throw new DocumentDomainError("invalid_numbering_definition", "literal");
  }
  if (
    !Number.isSafeInteger(record.numericWidth) ||
    (record.numericWidth as number) < 1 ||
    (record.numericWidth as number) > 18
  ) {
    throw new DocumentDomainError("invalid_numbering_definition", "width");
  }
  if (
    typeof record.reset !== "string" ||
    !NUMBERING_RESET_POLICIES.includes(record.reset as NumberingResetPolicy) ||
    typeof record.deterministicSuffix !== "string" ||
    !["none", "provided"].includes(record.deterministicSuffix) ||
    typeof record.importsAllowed !== "boolean" ||
    typeof record.reservationsAllowed !== "boolean" ||
    record.reusePolicy !== "never" ||
    record.allocationEvent !== "official_document_created" ||
    typeof record.status !== "string" ||
    !NUMBERING_VERSION_STATUSES.includes(
      record.status as NumberingVersionStatus,
    )
  ) {
    throw new DocumentDomainError("invalid_numbering_definition");
  }
  const normalized: VersionedNumberingDefinition = {
    id: requireUuid(record.id),
    key: requireKey(record.key),
    version: requireVersion(record.version),
    checksum: requireChecksum(record.checksum),
    labels: normalizeLabels(record.labels),
    scopeDimensions: Object.freeze(scopeDimensions),
    prefix: record.prefix,
    suffix: record.suffix,
    numericWidth: record.numericWidth as number,
    startingValue: requirePositiveBigint(record.startingValue),
    increment: requirePositiveBigint(record.increment),
    reset: record.reset as NumberingResetPolicy,
    timezone: requireTimezone(record.timezone),
    formatPattern:
      typeof record.formatPattern === "string" ? record.formatPattern : "",
    deterministicSuffix: record.deterministicSuffix as "none" | "provided",
    importsAllowed: record.importsAllowed,
    reservationsAllowed: record.reservationsAllowed,
    reusePolicy: "never",
    allocationEvent: "official_document_created",
    requiredApprovalTypes: normalizeApprovals(record.requiredApprovalTypes),
    status: record.status as NumberingVersionStatus,
  };
  validateFormatPattern(normalized);
  if (normalized.startingValue.length > normalized.numericWidth) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "starting_value_width",
    );
  }
  const { checksum: _checksum, status: _status, ...payload } = normalized;
  void _checksum;
  void _status;
  if (computeNumberingDefinitionChecksum(payload) !== normalized.checksum) {
    throw new DocumentDomainError("checksum_mismatch", "numbering_definition");
  }
  return Object.freeze(normalized);
}

export function numberingPeriodKey(input: {
  readonly instant: string;
  readonly reset: NumberingResetPolicy;
  readonly timezone: string;
}): string {
  assertExactKeys(
    requirePlainRecord(input, "invalid_numbering_definition"),
    ["instant", "reset", "timezone"],
    "invalid_numbering_definition",
  );
  if (!NUMBERING_RESET_POLICIES.includes(input.reset)) {
    throw new DocumentDomainError("invalid_numbering_definition", "reset");
  }
  if (input.reset === "never") return "never";
  const milliseconds = Date.parse(
    normalizeIsoInstant(
      input.instant,
      "invalid_numbering_definition",
      "instant",
    ),
  );
  const timezone = requireTimezone(input.timezone);
  const parts = new Intl.DateTimeFormat("en-CA", {
    calendar: "gregory",
    year: "numeric",
    month: "2-digit",
    numberingSystem: "latn",
    timeZone: timezone,
  }).formatToParts(milliseconds);
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  if (!year || !month) {
    throw new DocumentDomainError("invalid_numbering_definition", "period");
  }
  const normalizedYear = year.padStart(4, "0");
  return input.reset === "yearly"
    ? normalizedYear
    : `${normalizedYear}-${month}`;
}

export function formatDocumentNumber(input: {
  readonly definition: VersionedNumberingDefinition;
  readonly sequenceValue: string;
  readonly scopeKey: string;
  readonly periodKey: string;
  readonly deterministicSuffix?: string | null;
}): string {
  assertExactKeys(
    requirePlainRecord(input, "invalid_numbering_definition"),
    [
      "definition",
      "sequenceValue",
      "scopeKey",
      "periodKey",
      "deterministicSuffix",
    ],
    "invalid_numbering_definition",
  );
  const definition = normalizeNumberingDefinition(input.definition);
  const sequence = requirePositiveBigint(input.sequenceValue);
  if (sequence.length > definition.numericWidth) {
    throw new DocumentDomainError("number_out_of_range", "sequence_width");
  }
  if (
    typeof input.periodKey !== "string" ||
    (input.deterministicSuffix !== undefined &&
      input.deterministicSuffix !== null &&
      typeof input.deterministicSuffix !== "string")
  ) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "format_input",
    );
  }
  const periodKey = input.periodKey.trim();
  const scopeKey = input.scopeKey.trim();
  if (!SCOPE_KEY_PATTERN.test(scopeKey)) {
    throw new DocumentDomainError("invalid_numbering_definition", "scope_key");
  }
  if (
    definition.reset === "never"
      ? periodKey !== "never"
      : definition.reset === "yearly"
        ? !/^\d{4}$/u.test(periodKey)
        : !/^\d{4}-(?:0[1-9]|1[0-2])$/u.test(periodKey)
  ) {
    throw new DocumentDomainError("invalid_numbering_definition", "period");
  }
  const deterministicSuffix = input.deterministicSuffix?.trim() ?? "";
  if (
    (definition.deterministicSuffix === "provided" &&
      !SUFFIX_PATTERN.test(deterministicSuffix)) ||
    (definition.deterministicSuffix === "none" && deterministicSuffix !== "")
  ) {
    throw new DocumentDomainError("invalid_numbering_definition", "suffix");
  }
  const padded = sequence.padStart(definition.numericWidth, "0");
  const formatted = definition.formatPattern.replaceAll(
    FORMAT_TOKEN,
    (_token, name: string) => {
      if (name === "prefix") return definition.prefix;
      if (name === "suffix") return definition.suffix;
      if (name === "deterministic_suffix") return deterministicSuffix;
      if (name === "scope") return scopeKey;
      if (name === "period") return periodKey;
      return padded;
    },
  );
  if (!FORMATTED_NUMBER_PATTERN.test(formatted)) {
    throw new DocumentDomainError(
      "invalid_numbering_definition",
      "formatted_value",
    );
  }
  return formatted;
}

/** A committed allocation is permanent; this guard rejects pool-return semantics. */
export function assertNumberAllocationImmutable(input: {
  readonly previous: Readonly<{
    definitionId: string;
    sequenceValue: string;
    formattedValue: string;
    documentId: string;
  }>;
  readonly next: Readonly<{
    definitionId: string;
    sequenceValue: string;
    formattedValue: string;
    documentId: string;
  }>;
}): void {
  assertExactKeys(
    requirePlainRecord(input, "invalid_document"),
    ["previous", "next"],
    "invalid_document",
  );
  for (const allocation of [input.previous, input.next]) {
    const record = requirePlainRecord(allocation, "invalid_document");
    assertExactKeys(
      record,
      ["definitionId", "sequenceValue", "formattedValue", "documentId"],
      "invalid_document",
    );
    requireUuid(allocation.definitionId);
    requireUuid(allocation.documentId);
    requirePositiveBigint(allocation.sequenceValue);
    if (
      typeof allocation.formattedValue !== "string" ||
      !FORMATTED_NUMBER_PATTERN.test(allocation.formattedValue)
    ) {
      throw new DocumentDomainError("invalid_document", "number_allocation");
    }
  }
  if (
    input.previous.definitionId !== input.next.definitionId ||
    input.previous.sequenceValue !== input.next.sequenceValue ||
    input.previous.formattedValue !== input.next.formattedValue ||
    input.previous.documentId !== input.next.documentId
  ) {
    throw new DocumentDomainError(
      "immutable_document_field",
      "number_allocation",
    );
  }
}
