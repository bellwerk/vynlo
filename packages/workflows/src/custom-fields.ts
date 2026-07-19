export const CUSTOM_FIELD_TYPES = [
  "short_text",
  "long_text",
  "integer",
  "decimal",
  "money",
  "boolean",
  "date",
  "datetime",
  "single_select",
  "multi_select",
  "party_reference",
  "inventory_reference",
  "location_reference",
  "user_reference",
] as const;

export type CustomFieldType = (typeof CUSTOM_FIELD_TYPES)[number];

export const CUSTOM_FIELD_VERSION_STATUSES = [
  "draft",
  "active",
  "retired",
] as const;

export type CustomFieldVersionStatus =
  (typeof CUSTOM_FIELD_VERSION_STATUSES)[number];

const CORE_FIELD_KEYS = new Set([
  "currency",
  "currency_code",
  "official_number",
  "organization_id",
  "provider_id",
  "provider_ids",
  "stock",
  "stock_number",
  "vin",
  "workflow_state",
  "workflow_state_key",
  "workspace_id",
]);

const PROHIBITED_EXECUTION_KEYS = new Set([
  "command",
  "endpoint",
  "eval",
  "fetch",
  "filesystem",
  "function",
  "http",
  "https",
  "import",
  "javascript",
  "js",
  "module",
  "network",
  "query",
  "request",
  "script",
  "shell",
  "sql",
  "uri",
  "url",
]);

const FIELD_KEY_PATTERN = /^[a-z][a-z0-9_]{0,127}$/u;
const ENTITY_TYPE_PATTERN = /^[a-z][a-z0-9_]{0,127}$/u;
const PERMISSION_KEY_PATTERN =
  /^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})+$/u;
const SECTION_KEY_PATTERN = /^[a-z][a-z0-9_.-]{0,127}$/u;
const SHA256_PATTERN = /^[a-f0-9]{64}$/u;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const INTEGER_PATTERN = /^-?(?:0|[1-9]\d*)$/u;
const DECIMAL_PATTERN = /^-?(?:0|[1-9]\d*)(?:\.\d+)?$/u;
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/u;
const DATETIME_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/u;
const CURRENCY_PATTERN = /^[A-Z]{3}$/u;
const POSTGRES_BIGINT_MIN = -9_223_372_036_854_775_808n;
const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;

export type CustomFieldPolicyErrorCode =
  | "invalid_definition"
  | "invalid_definition_identity"
  | "invalid_field_key"
  | "core_field_shadow_not_allowed"
  | "invalid_field_type"
  | "invalid_localization"
  | "invalid_validation"
  | "invalid_options"
  | "invalid_permission_key"
  | "invalid_default_value"
  | "arbitrary_execution_not_allowed"
  | "inactive_definition"
  | "required_value_missing"
  | "invalid_value"
  | "value_out_of_range"
  | "invalid_option_value"
  | "invalid_reference"
  | "workspace_mismatch"
  | "entity_mismatch"
  | "expected_version_conflict"
  | "permission_denied"
  | "invalid_command_metadata";

export class CustomFieldPolicyError extends Error {
  readonly code: CustomFieldPolicyErrorCode;
  readonly detail: string | null;

  constructor(code: CustomFieldPolicyErrorCode, detail: string | null = null) {
    super(detail === null ? code : `${code}:${detail}`);
    this.name = "CustomFieldPolicyError";
    this.code = code;
    this.detail = detail;
  }
}

type PlainRecord = Record<string, unknown>;

export interface LocalizedText {
  readonly en: string;
  readonly fr: string;
  readonly [locale: string]: string;
}

export interface CustomFieldOption {
  readonly key: string;
  readonly labels: LocalizedText;
  readonly order: number;
  readonly active: boolean;
}

export interface CustomFieldValidation {
  readonly minLength: number | null;
  readonly maxLength: number | null;
  readonly minimum: string | null;
  readonly maximum: string | null;
  readonly scale: number | null;
  readonly minItems: number | null;
  readonly maxItems: number | null;
  readonly allowedCurrencies: readonly string[];
}

export interface MoneyCustomFieldValue {
  readonly amountMinor: string;
  readonly currencyCode: string;
}

export type CustomFieldValue =
  string | boolean | readonly string[] | MoneyCustomFieldValue | null;

export interface CustomFieldDefinitionVersion {
  readonly id: string;
  readonly workspaceId: string;
  readonly definitionId: string;
  readonly entityType: string;
  readonly key: string;
  readonly version: number;
  readonly checksum: string;
  readonly type: CustomFieldType;
  readonly labels: LocalizedText;
  readonly helpText: LocalizedText;
  readonly validation: CustomFieldValidation;
  readonly defaultValue: CustomFieldValue;
  readonly options: readonly CustomFieldOption[];
  readonly required: boolean;
  readonly visibilityPermissionKey: string | null;
  readonly editPermissionKey: string | null;
  readonly sensitive: boolean;
  readonly searchable: boolean;
  readonly sectionKey: string;
  readonly status: CustomFieldVersionStatus;
}

export interface CustomFieldValueSnapshot {
  readonly id: string;
  readonly workspaceId: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly definitionId: string;
  readonly definitionVersionId: string;
  readonly definitionVersion: number;
  readonly definitionChecksum: string;
  readonly fieldKey: string;
  readonly fieldType: CustomFieldType;
  readonly value: CustomFieldValue;
  readonly version: number;
}

export interface CustomFieldValueProjection {
  readonly definitionVersion: number;
  readonly fieldKey: string;
  readonly fieldType: CustomFieldType;
  readonly masked: boolean;
  readonly value: CustomFieldValue;
  readonly version: number | null;
}

export interface CustomFieldValueMutationPlan {
  readonly value: CustomFieldValueSnapshot;
  readonly audit: Readonly<{
    action: "custom_field_value.created" | "custom_field_value.updated";
    actorId: string;
    correlationId: string;
    entityId: string;
    entityType: string;
    fieldKey: string;
    previousVersion: number | null;
    resultingVersion: number;
    sensitiveValueRedacted: boolean;
  }>;
  readonly receipt: Readonly<{
    actorId: string;
    commandType: "set_custom_field_value";
    idempotencyKey: string;
    resultingVersion: number;
  }>;
}

function requirePlainRecord(
  value: unknown,
  code: CustomFieldPolicyErrorCode,
): PlainRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new CustomFieldPolicyError(code);
  }
  const prototype = Object.getPrototypeOf(value) as unknown;
  if (prototype !== Object.prototype && prototype !== null) {
    throw new CustomFieldPolicyError(code);
  }
  for (const key of Reflect.ownKeys(value)) {
    if (typeof key !== "string") {
      throw new CustomFieldPolicyError(code);
    }
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor?.get || descriptor?.set) {
      throw new CustomFieldPolicyError("arbitrary_execution_not_allowed", key);
    }
  }
  return value as PlainRecord;
}

function normalizedExecutionKey(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/gu, "");
}

function assertExactKeys(
  record: PlainRecord,
  allowed: ReadonlySet<string>,
  code: CustomFieldPolicyErrorCode,
): void {
  for (const key of Object.keys(record)) {
    if (allowed.has(key)) {
      continue;
    }
    if (PROHIBITED_EXECUTION_KEYS.has(normalizedExecutionKey(key))) {
      throw new CustomFieldPolicyError("arbitrary_execution_not_allowed", key);
    }
    throw new CustomFieldPolicyError(code, key);
  }
}

function requireUuid(value: unknown, code: CustomFieldPolicyErrorCode): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new CustomFieldPolicyError(code);
  }
  return value.toLowerCase();
}

function requirePositiveInteger(
  value: unknown,
  code: CustomFieldPolicyErrorCode,
): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1) {
    throw new CustomFieldPolicyError(code);
  }
  return value as number;
}

function requirePermissionKey(value: unknown): string | null {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string" || !PERMISSION_KEY_PATTERN.test(value)) {
    throw new CustomFieldPolicyError("invalid_permission_key");
  }
  return value;
}

function normalizeLocalizedText(value: unknown): LocalizedText {
  const record = requirePlainRecord(value, "invalid_localization");
  const normalized = Object.create(null) as Record<string, string>;
  for (const [locale, text] of Object.entries(record)) {
    if (
      !/^[a-z]{2,3}(?:-[A-Z0-9]{2,8})?$/u.test(locale) ||
      typeof text !== "string" ||
      !text.trim() ||
      text.length > 500
    ) {
      throw new CustomFieldPolicyError("invalid_localization", locale);
    }
    normalized[locale] = text.trim();
  }
  if (!normalized.en || !normalized.fr) {
    throw new CustomFieldPolicyError("invalid_localization", "en/fr");
  }
  return Object.freeze(normalized) as LocalizedText;
}

function normalizeCanonicalInteger(
  value: unknown,
  code: CustomFieldPolicyErrorCode = "invalid_value",
): string {
  if (
    typeof value !== "string" ||
    value.length > 20 ||
    !INTEGER_PATTERN.test(value)
  ) {
    throw new CustomFieldPolicyError(code);
  }
  let parsed: bigint;
  try {
    parsed = BigInt(value);
  } catch {
    throw new CustomFieldPolicyError(code);
  }
  if (parsed < POSTGRES_BIGINT_MIN || parsed > POSTGRES_BIGINT_MAX) {
    throw new CustomFieldPolicyError("value_out_of_range");
  }
  return parsed.toString();
}

function decimalParts(value: string): {
  readonly coefficient: bigint;
  readonly scale: number;
} {
  const negative = value.startsWith("-");
  const unsigned = negative ? value.slice(1) : value;
  const [whole = "0", fraction = ""] = unsigned.split(".");
  const coefficient = BigInt(`${negative ? "-" : ""}${whole}${fraction}`);
  return { coefficient, scale: fraction.length };
}

function compareDecimals(left: string, right: string): number {
  const a = decimalParts(left);
  const b = decimalParts(right);
  const scale = Math.max(a.scale, b.scale);
  const leftCoefficient = a.coefficient * 10n ** BigInt(scale - a.scale);
  const rightCoefficient = b.coefficient * 10n ** BigInt(scale - b.scale);
  return leftCoefficient < rightCoefficient
    ? -1
    : leftCoefficient > rightCoefficient
      ? 1
      : 0;
}

function normalizeCanonicalDecimal(
  value: unknown,
  code: CustomFieldPolicyErrorCode = "invalid_value",
): string {
  if (typeof value !== "string" || !DECIMAL_PATTERN.test(value)) {
    throw new CustomFieldPolicyError(code);
  }
  const unsigned = value.startsWith("-") ? value.slice(1) : value;
  const [wholeDigits = "", fractionalDigits = ""] = unsigned.split(".");
  if (
    wholeDigits.length + fractionalDigits.length > 38 ||
    fractionalDigits.length > 18
  ) {
    throw new CustomFieldPolicyError("value_out_of_range");
  }
  const [whole = "0", fraction] = value.split(".");
  const normalizedFraction = fraction?.replace(/0+$/u, "") ?? "";
  const normalizedWhole =
    whole === "-0" && !/[1-9]/u.test(normalizedFraction) ? "0" : whole;
  return normalizedFraction
    ? `${normalizedWhole}.${normalizedFraction}`
    : normalizedWhole;
}

function normalizeValidation(value: unknown): CustomFieldValidation {
  const record = requirePlainRecord(value ?? {}, "invalid_validation");
  assertExactKeys(
    record,
    new Set([
      "minLength",
      "maxLength",
      "minimum",
      "maximum",
      "scale",
      "minItems",
      "maxItems",
      "allowedCurrencies",
    ]),
    "invalid_validation",
  );

  const optionalCount = (
    candidate: unknown,
    maximum: number,
  ): number | null => {
    if (candidate === undefined || candidate === null) return null;
    if (
      !Number.isSafeInteger(candidate) ||
      (candidate as number) < 0 ||
      (candidate as number) > maximum
    ) {
      throw new CustomFieldPolicyError("invalid_validation");
    }
    return candidate as number;
  };

  const minLength = optionalCount(record.minLength, 100_000);
  const maxLength = optionalCount(record.maxLength, 100_000);
  const scale = optionalCount(record.scale, 18);
  const minItems = optionalCount(record.minItems, 100);
  const maxItems = optionalCount(record.maxItems, 100);
  if (
    (minLength !== null && maxLength !== null && minLength > maxLength) ||
    (minItems !== null && maxItems !== null && minItems > maxItems)
  ) {
    throw new CustomFieldPolicyError("invalid_validation");
  }

  const minimum =
    record.minimum === undefined || record.minimum === null
      ? null
      : normalizeCanonicalDecimal(record.minimum, "invalid_validation");
  const maximum =
    record.maximum === undefined || record.maximum === null
      ? null
      : normalizeCanonicalDecimal(record.maximum, "invalid_validation");
  if (
    minimum !== null &&
    maximum !== null &&
    compareDecimals(minimum, maximum) > 0
  ) {
    throw new CustomFieldPolicyError("invalid_validation");
  }

  if (
    record.allowedCurrencies !== undefined &&
    !Array.isArray(record.allowedCurrencies)
  ) {
    throw new CustomFieldPolicyError("invalid_validation");
  }
  const allowedCurrencies = (record.allowedCurrencies ?? []).map((currency) => {
    if (typeof currency !== "string" || !CURRENCY_PATTERN.test(currency)) {
      throw new CustomFieldPolicyError("invalid_validation");
    }
    return currency;
  });
  if (new Set(allowedCurrencies).size !== allowedCurrencies.length) {
    throw new CustomFieldPolicyError("invalid_validation");
  }

  return Object.freeze({
    minLength,
    maxLength,
    minimum,
    maximum,
    scale,
    minItems,
    maxItems,
    allowedCurrencies: Object.freeze(allowedCurrencies),
  });
}

function normalizeOptions(
  value: unknown,
  fieldType: CustomFieldType,
): readonly CustomFieldOption[] {
  const options = value ?? [];
  if (!Array.isArray(options)) {
    throw new CustomFieldPolicyError("invalid_options");
  }
  if (
    !["single_select", "multi_select"].includes(fieldType) &&
    options.length > 0
  ) {
    throw new CustomFieldPolicyError("invalid_options");
  }
  if (
    ["single_select", "multi_select"].includes(fieldType) &&
    options.length === 0
  ) {
    throw new CustomFieldPolicyError("invalid_options");
  }

  const normalized = options.map((option, index) => {
    const record = requirePlainRecord(option, "invalid_options");
    assertExactKeys(
      record,
      new Set(["key", "labels", "order", "active"]),
      "invalid_options",
    );
    if (typeof record.key !== "string" || !FIELD_KEY_PATTERN.test(record.key)) {
      throw new CustomFieldPolicyError("invalid_options");
    }
    const order = record.order ?? index;
    if (!Number.isSafeInteger(order) || (order as number) < 0) {
      throw new CustomFieldPolicyError("invalid_options");
    }
    if (record.active !== undefined && typeof record.active !== "boolean") {
      throw new CustomFieldPolicyError("invalid_options");
    }
    return Object.freeze({
      key: record.key,
      labels: normalizeLocalizedText(record.labels),
      order: order as number,
      active: record.active ?? true,
    });
  });
  if (
    new Set(normalized.map((option) => option.key)).size !== normalized.length
  ) {
    throw new CustomFieldPolicyError("invalid_options");
  }
  return Object.freeze(normalized);
}

function validDate(value: string): boolean {
  const match = DATE_PATTERN.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

function assertDecimalBounds(
  value: string,
  validation: CustomFieldValidation,
): void {
  if (
    (validation.minimum !== null &&
      compareDecimals(value, validation.minimum) < 0) ||
    (validation.maximum !== null &&
      compareDecimals(value, validation.maximum) > 0)
  ) {
    throw new CustomFieldPolicyError("value_out_of_range");
  }
  if (
    validation.scale !== null &&
    (value.split(".")[1]?.length ?? 0) > validation.scale
  ) {
    throw new CustomFieldPolicyError("value_out_of_range", "scale");
  }
}

export function normalizeCustomFieldValue(
  definition: Pick<
    CustomFieldDefinitionVersion,
    "type" | "required" | "validation" | "options"
  >,
  value: unknown,
): CustomFieldValue {
  if (value === null || value === undefined) {
    if (definition.required) {
      throw new CustomFieldPolicyError("required_value_missing");
    }
    return null;
  }

  const validation = definition.validation;
  switch (definition.type) {
    case "short_text":
    case "long_text": {
      if (typeof value !== "string") {
        throw new CustomFieldPolicyError("invalid_value");
      }
      const normalized = value.trim();
      if (!normalized && definition.required) {
        throw new CustomFieldPolicyError("required_value_missing");
      }
      const hardMaximum = definition.type === "short_text" ? 500 : 50_000;
      const maximum = Math.min(
        validation.maxLength ?? hardMaximum,
        hardMaximum,
      );
      if (
        normalized.length < (validation.minLength ?? 0) ||
        normalized.length > maximum
      ) {
        throw new CustomFieldPolicyError("value_out_of_range");
      }
      return normalized || null;
    }
    case "integer": {
      const normalized = normalizeCanonicalInteger(value);
      assertDecimalBounds(normalized, validation);
      return normalized;
    }
    case "decimal": {
      const normalized = normalizeCanonicalDecimal(value);
      assertDecimalBounds(normalized, validation);
      return normalized;
    }
    case "money": {
      const record = requirePlainRecord(value, "invalid_value");
      assertExactKeys(
        record,
        new Set(["amountMinor", "currencyCode"]),
        "invalid_value",
      );
      const amountMinor = normalizeCanonicalInteger(record.amountMinor);
      if (
        typeof record.currencyCode !== "string" ||
        !CURRENCY_PATTERN.test(record.currencyCode)
      ) {
        throw new CustomFieldPolicyError("invalid_value");
      }
      if (
        validation.allowedCurrencies.length > 0 &&
        !validation.allowedCurrencies.includes(record.currencyCode)
      ) {
        throw new CustomFieldPolicyError("value_out_of_range", "currency");
      }
      assertDecimalBounds(amountMinor, validation);
      return Object.freeze({ amountMinor, currencyCode: record.currencyCode });
    }
    case "boolean":
      if (typeof value !== "boolean") {
        throw new CustomFieldPolicyError("invalid_value");
      }
      return value;
    case "date":
      if (typeof value !== "string" || !validDate(value)) {
        throw new CustomFieldPolicyError("invalid_value");
      }
      return value;
    case "datetime": {
      if (typeof value !== "string" || !DATETIME_PATTERN.test(value)) {
        throw new CustomFieldPolicyError("invalid_value");
      }
      const parsed = new Date(value);
      if (Number.isNaN(parsed.valueOf())) {
        throw new CustomFieldPolicyError("invalid_value");
      }
      return parsed.toISOString();
    }
    case "single_select": {
      if (typeof value !== "string") {
        throw new CustomFieldPolicyError("invalid_option_value");
      }
      const option = definition.options.find(
        (candidate) => candidate.key === value,
      );
      if (!option?.active) {
        throw new CustomFieldPolicyError("invalid_option_value");
      }
      return value;
    }
    case "multi_select": {
      if (
        !Array.isArray(value) ||
        value.some((item) => typeof item !== "string")
      ) {
        throw new CustomFieldPolicyError("invalid_option_value");
      }
      const selected = value as string[];
      if (
        new Set(selected).size !== selected.length ||
        selected.length < (validation.minItems ?? 0) ||
        selected.length > (validation.maxItems ?? 100)
      ) {
        throw new CustomFieldPolicyError("value_out_of_range");
      }
      const activeKeys = new Set(
        definition.options
          .filter((option) => option.active)
          .map((option) => option.key),
      );
      if (selected.some((key) => !activeKeys.has(key))) {
        throw new CustomFieldPolicyError("invalid_option_value");
      }
      return Object.freeze([...selected]);
    }
    case "party_reference":
    case "inventory_reference":
    case "location_reference":
    case "user_reference":
      return requireUuid(value, "invalid_reference");
  }
}

/**
 * Validates, copies and deeply freezes one immutable custom-field version.
 * Tenant input is declarative data only; unknown or executable-shaped keys are
 * rejected before any accessor can execute.
 */
export function defineCustomFieldVersion(
  value: unknown,
): Readonly<CustomFieldDefinitionVersion> {
  const record = requirePlainRecord(value, "invalid_definition");
  assertExactKeys(
    record,
    new Set([
      "id",
      "workspaceId",
      "definitionId",
      "entityType",
      "key",
      "version",
      "checksum",
      "type",
      "labels",
      "helpText",
      "validation",
      "defaultValue",
      "options",
      "required",
      "visibilityPermissionKey",
      "editPermissionKey",
      "sensitive",
      "searchable",
      "sectionKey",
      "status",
    ]),
    "invalid_definition",
  );

  if (
    typeof record.entityType !== "string" ||
    !ENTITY_TYPE_PATTERN.test(record.entityType)
  ) {
    throw new CustomFieldPolicyError("invalid_definition_identity");
  }
  if (typeof record.key !== "string" || !FIELD_KEY_PATTERN.test(record.key)) {
    throw new CustomFieldPolicyError("invalid_field_key");
  }
  if (CORE_FIELD_KEYS.has(record.key)) {
    throw new CustomFieldPolicyError(
      "core_field_shadow_not_allowed",
      record.key,
    );
  }
  if (
    typeof record.type !== "string" ||
    !CUSTOM_FIELD_TYPES.includes(record.type as CustomFieldType)
  ) {
    throw new CustomFieldPolicyError("invalid_field_type");
  }
  if (
    typeof record.checksum !== "string" ||
    !SHA256_PATTERN.test(record.checksum)
  ) {
    throw new CustomFieldPolicyError("invalid_definition_identity");
  }
  if (
    typeof record.required !== "boolean" ||
    typeof record.sensitive !== "boolean" ||
    typeof record.searchable !== "boolean"
  ) {
    throw new CustomFieldPolicyError("invalid_definition");
  }
  if (
    typeof record.sectionKey !== "string" ||
    !SECTION_KEY_PATTERN.test(record.sectionKey)
  ) {
    throw new CustomFieldPolicyError("invalid_definition");
  }
  if (
    typeof record.status !== "string" ||
    !CUSTOM_FIELD_VERSION_STATUSES.includes(
      record.status as CustomFieldVersionStatus,
    )
  ) {
    throw new CustomFieldPolicyError("invalid_definition");
  }

  const visibilityPermissionKey = requirePermissionKey(
    record.visibilityPermissionKey,
  );
  const editPermissionKey = requirePermissionKey(record.editPermissionKey);
  if (record.sensitive && visibilityPermissionKey === null) {
    throw new CustomFieldPolicyError(
      "invalid_permission_key",
      "sensitive_visibility",
    );
  }
  const type = record.type as CustomFieldType;
  const validation = normalizeValidation(record.validation);
  const options = normalizeOptions(record.options, type);
  const provisional = {
    type,
    required: record.required,
    validation,
    options,
  };
  let defaultValue: CustomFieldValue = null;
  if (record.defaultValue !== undefined && record.defaultValue !== null) {
    try {
      defaultValue = normalizeCustomFieldValue(
        provisional,
        record.defaultValue,
      );
    } catch (error) {
      if (error instanceof CustomFieldPolicyError) {
        throw new CustomFieldPolicyError("invalid_default_value", error.code);
      }
      throw error;
    }
  }

  return Object.freeze({
    id: requireUuid(record.id, "invalid_definition_identity"),
    workspaceId: requireUuid(record.workspaceId, "invalid_definition_identity"),
    definitionId: requireUuid(
      record.definitionId,
      "invalid_definition_identity",
    ),
    entityType: record.entityType,
    key: record.key,
    version: requirePositiveInteger(
      record.version,
      "invalid_definition_identity",
    ),
    checksum: record.checksum,
    type,
    labels: normalizeLocalizedText(record.labels),
    helpText: normalizeLocalizedText(record.helpText),
    validation,
    defaultValue,
    options,
    required: record.required,
    visibilityPermissionKey,
    editPermissionKey,
    sensitive: record.sensitive,
    searchable: record.searchable,
    sectionKey: record.sectionKey,
    status: record.status as CustomFieldVersionStatus,
  });
}

export function projectCustomFieldValue(input: {
  readonly definition: CustomFieldDefinitionVersion;
  readonly snapshot?: CustomFieldValueSnapshot | null;
  readonly entityReadable: boolean;
  readonly effectivePermissionKeys: readonly string[];
}): Readonly<CustomFieldValueProjection> {
  const definition = defineCustomFieldVersion(input.definition);
  if (!input.entityReadable) {
    throw new CustomFieldPolicyError("permission_denied", "entity.read");
  }
  const masked =
    definition.visibilityPermissionKey !== null &&
    !input.effectivePermissionKeys.includes(definition.visibilityPermissionKey);
  const snapshot = input.snapshot ?? null;
  if (
    snapshot !== null &&
    (snapshot.workspaceId !== definition.workspaceId ||
      snapshot.definitionId !== definition.definitionId ||
      snapshot.definitionVersionId !== definition.id ||
      snapshot.definitionChecksum !== definition.checksum ||
      snapshot.entityType !== definition.entityType ||
      snapshot.fieldKey !== definition.key ||
      snapshot.fieldType !== definition.type)
  ) {
    throw new CustomFieldPolicyError("entity_mismatch");
  }
  return Object.freeze({
    definitionVersion: definition.version,
    fieldKey: definition.key,
    fieldType: definition.type,
    masked,
    value: masked ? null : (snapshot?.value ?? definition.defaultValue),
    version: snapshot?.version ?? null,
  });
}

export function planCustomFieldValueMutation(input: {
  readonly definition: CustomFieldDefinitionVersion;
  readonly current?: CustomFieldValueSnapshot | null;
  readonly valueId: string;
  readonly workspaceId: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly referenceWorkspaceId?: string | null;
  readonly expectedVersion: number;
  readonly entityWritable: boolean;
  readonly effectivePermissionKeys: readonly string[];
  readonly value: unknown;
  readonly actorId: string;
  readonly correlationId: string;
  readonly idempotencyKey: string;
}): Readonly<CustomFieldValueMutationPlan> {
  const definition = defineCustomFieldVersion(input.definition);
  if (definition.status !== "active") {
    throw new CustomFieldPolicyError("inactive_definition");
  }
  const workspaceId = requireUuid(
    input.workspaceId,
    "invalid_command_metadata",
  );
  const entityId = requireUuid(input.entityId, "invalid_command_metadata");
  const actorId = requireUuid(input.actorId, "invalid_command_metadata");
  const correlationId = requireUuid(
    input.correlationId,
    "invalid_command_metadata",
  );
  const valueId = requireUuid(input.valueId, "invalid_command_metadata");
  if (workspaceId !== definition.workspaceId) {
    throw new CustomFieldPolicyError("workspace_mismatch");
  }
  if (input.entityType !== definition.entityType) {
    throw new CustomFieldPolicyError("entity_mismatch");
  }
  if (!input.entityWritable) {
    throw new CustomFieldPolicyError("permission_denied", "entity.update");
  }
  if (
    definition.editPermissionKey !== null &&
    !input.effectivePermissionKeys.includes(definition.editPermissionKey)
  ) {
    throw new CustomFieldPolicyError(
      "permission_denied",
      definition.editPermissionKey,
    );
  }
  if (
    input.referenceWorkspaceId !== undefined &&
    input.referenceWorkspaceId !== null &&
    input.referenceWorkspaceId.toLowerCase() !== workspaceId
  ) {
    throw new CustomFieldPolicyError("workspace_mismatch", "reference");
  }
  if (
    typeof input.idempotencyKey !== "string" ||
    input.idempotencyKey !== input.idempotencyKey.trim() ||
    input.idempotencyKey.length < 8 ||
    input.idempotencyKey.length > 200
  ) {
    throw new CustomFieldPolicyError("invalid_command_metadata");
  }

  const current = input.current ?? null;
  if (current !== null) {
    if (
      current.workspaceId !== workspaceId ||
      current.entityType !== input.entityType ||
      current.entityId !== entityId ||
      current.definitionId !== definition.definitionId
    ) {
      throw new CustomFieldPolicyError("entity_mismatch");
    }
    if (current.version !== input.expectedVersion) {
      throw new CustomFieldPolicyError("expected_version_conflict");
    }
  } else if (input.expectedVersion !== 0) {
    throw new CustomFieldPolicyError("expected_version_conflict");
  }

  const normalizedValue = normalizeCustomFieldValue(definition, input.value);
  const resultingVersion = (current?.version ?? 0) + 1;
  const snapshot = Object.freeze({
    id: valueId,
    workspaceId,
    entityType: definition.entityType,
    entityId,
    definitionId: definition.definitionId,
    definitionVersionId: definition.id,
    definitionVersion: definition.version,
    definitionChecksum: definition.checksum,
    fieldKey: definition.key,
    fieldType: definition.type,
    value: normalizedValue,
    version: resultingVersion,
  });
  return Object.freeze({
    value: snapshot,
    audit: Object.freeze({
      action:
        current === null
          ? "custom_field_value.created"
          : "custom_field_value.updated",
      actorId,
      correlationId,
      entityId,
      entityType: definition.entityType,
      fieldKey: definition.key,
      previousVersion: current?.version ?? null,
      resultingVersion,
      sensitiveValueRedacted: definition.sensitive,
    }),
    receipt: Object.freeze({
      actorId,
      commandType: "set_custom_field_value",
      idempotencyKey: input.idempotencyKey,
      resultingVersion,
    }),
  });
}
