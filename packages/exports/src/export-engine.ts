import { createDeterministicXlsx } from "./xlsx";

export const EXPORT_STEP_UP_MAX_AGE_MS = 15 * 60 * 1000;
export const DEFAULT_EXPORT_RUN_PERMISSION = "exports.run";
export const DEFAULT_SENSITIVE_EXPORT_PERMISSION = "exports.run_sensitive";

export type ExportFormat = "csv" | "xlsx";
export type ExportCellFormat =
  | "text"
  | "integer"
  | "decimal"
  | "minor_units"
  | "currency_code"
  | "date"
  | "datetime"
  | "boolean";

export interface ExportDefinitionPolicy {
  readonly allowedSourcesByEntity: Readonly<Record<string, readonly string[]>>;
  readonly allowedFiltersByEntity?: Readonly<Record<string, readonly string[]>>;
  readonly allowedPermissions: readonly string[];
  readonly defaultRunPermission?: string;
  readonly sensitiveRunPermission?: string;
  readonly maxColumns?: number;
  readonly maxRows?: number;
}

export interface CompiledExportColumn {
  readonly key: string;
  readonly source: string;
  readonly sourceSegments: readonly string[];
  readonly label: string | null;
  readonly labels: Readonly<Record<string, string>>;
  readonly format: ExportCellFormat;
  readonly sensitive: boolean;
  readonly permission: string | null;
  readonly nullable: boolean;
}

export interface CompiledExportSecurity {
  readonly permission: string | null;
  readonly stepUpRequired: boolean;
  readonly auditRequired: boolean;
  readonly linksExpire: boolean;
}

export interface CompiledExportProfile {
  readonly key: string;
  readonly labels: Readonly<Record<string, string>>;
  readonly columns: readonly CompiledExportColumn[];
  readonly security: Pick<
    CompiledExportSecurity,
    "permission" | "stepUpRequired"
  >;
}

export interface CompiledExportDefinition {
  readonly schemaVersion: "1.0" | "1.1";
  readonly key: string;
  readonly version: string;
  readonly owner: string | null;
  readonly labels: Readonly<Record<string, string>>;
  readonly entity: string;
  readonly formats: readonly ExportFormat[];
  readonly columns: readonly CompiledExportColumn[] | null;
  readonly profiles: Readonly<Record<string, CompiledExportProfile>> | null;
  readonly enabledDocumentTypes: readonly string[];
  readonly defaultFilters: Readonly<Record<string, ExportFilterValue>>;
  readonly availableFilters: readonly string[];
  readonly security: CompiledExportSecurity;
  readonly activationGate: string | null;
  readonly definitionChecksum: string;
  readonly defaultRunPermission: string;
  readonly sensitiveRunPermission: string;
  readonly maxRows: number;
}

export type ExportFilterScalar = string | number | boolean | null;
export type ExportFilterValue =
  ExportFilterScalar | readonly ExportFilterScalar[];

export interface ExportAuthorizationContext {
  readonly grantedPermissions: readonly string[];
  readonly strongAuthAt?: Date | string | number | null;
  readonly now?: Date | string | number;
}

export type ExportAuthorizationCode =
  | "EXPORT_AUTHORIZED"
  | "EXPORT_PERMISSION_REQUIRED"
  | "EXPORT_STEP_UP_REQUIRED";

export interface ExportAuthorizationDecision {
  readonly allowed: boolean;
  readonly code: ExportAuthorizationCode;
  readonly requiredPermissions: readonly string[];
  readonly missingPermissions: readonly string[];
  readonly requiresStepUp: boolean;
  readonly stepUpSatisfied: boolean;
}

export interface GenerateExportArtifactInput {
  readonly definition: CompiledExportDefinition;
  readonly format: ExportFormat;
  readonly locale: string;
  readonly rows: readonly Readonly<Record<string, unknown>>[];
  readonly authorization: ExportAuthorizationContext;
  readonly profileKey?: string;
}

export interface GeneratedExportArtifact {
  readonly definitionKey: string;
  readonly definitionVersion: string;
  readonly definitionChecksum: string;
  readonly profileKey: string | null;
  readonly format: ExportFormat;
  readonly locale: string;
  readonly contentType: string;
  readonly extension: ExportFormat;
  readonly bytes: Uint8Array;
  readonly checksum: string;
  readonly byteCount: number;
  readonly rowCount: number;
  readonly columnCount: number;
  readonly labels: readonly string[];
  readonly authorization: ExportAuthorizationDecision;
}

export interface CreateExportRunMetadataInput {
  readonly workspaceId: string;
  readonly actorId: string;
  readonly filters?: Readonly<Record<string, unknown>>;
  readonly createdAt: Date | string | number;
  readonly expiresAt?: Date | string | number;
}

export interface ExportRunMetadata {
  readonly workspaceId: string;
  readonly actorId: string;
  readonly definitionKey: string;
  readonly definitionVersion: string;
  readonly definitionChecksum: string;
  readonly profileKey: string | null;
  readonly format: ExportFormat;
  readonly locale: string;
  readonly filters: Readonly<Record<string, ExportFilterValue>>;
  readonly filtersChecksum: string;
  readonly rowCount: number;
  readonly byteCount: number;
  readonly artifactChecksum: string;
  readonly createdAt: string;
  readonly expiresAt: string | null;
  readonly auditRequired: true;
}

export class ExportDefinitionError extends Error {
  readonly code: string;
  readonly path: string;

  constructor(code: string, path: string, message: string) {
    super(`${code} at ${path}: ${message}`);
    this.name = "ExportDefinitionError";
    this.code = code;
    this.path = path;
  }
}

const KEY_PATTERN = /^[a-z][a-z0-9_]{1,95}$/;
const FILTER_PATTERN = /^[a-z][a-z0-9_]{0,95}$/;
const VERSION_PATTERN = /^\d+\.\d+\.\d+$/;
const SOURCE_PATTERN = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/;
const PERMISSION_PATTERN = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/;
const LOCALE_PATTERN = /^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/;
const INTEGER_PATTERN = /^-?(?:0|[1-9]\d*)$/;
const DECIMAL_PATTERN = /^-?(?:0|[1-9]\d*)(?:\.\d+)?$/;
const INVALID_XML_CONTROL_PATTERN = /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/;
const CSV_FORMULA_PATTERN = /^(?:[ \t\r\n])*[=+\-@]/;
const ISO_DATETIME_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/;
const FORBIDDEN_PATH_SEGMENTS = new Set([
  "__proto__",
  "prototype",
  "constructor",
]);
const CELL_FORMATS = new Set<ExportCellFormat>([
  "text",
  "integer",
  "decimal",
  "minor_units",
  "currency_code",
  "date",
  "datetime",
  "boolean",
]);
const UTF8_ENCODER = new TextEncoder();
const SHA256_CONSTANTS = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

function fail(code: string, path: string, message: string): never {
  throw new ExportDefinitionError(code, path, message);
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function ownValue(
  record: Record<string, unknown>,
  key: string,
  path: string,
): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(record, key);
  if (descriptor === undefined) {
    return undefined;
  }
  if (!("value" in descriptor)) {
    return fail(
      "EXPORT_ACCESSOR_FORBIDDEN",
      `${path}.${key}`,
      "accessor properties are not accepted",
    );
  }
  return descriptor.value;
}

function recordAt(
  value: unknown,
  path: string,
  allowedKeys?: readonly string[],
  requiredKeys: readonly string[] = [],
): Record<string, unknown> {
  if (!isPlainRecord(value)) {
    return fail("EXPORT_OBJECT_REQUIRED", path, "expected a plain object");
  }
  if (allowedKeys !== undefined) {
    const allowed = new Set(allowedKeys);
    for (const key of Object.keys(value)) {
      if (!allowed.has(key)) {
        fail(
          "EXPORT_UNKNOWN_PROPERTY",
          `${path}.${key}`,
          "property is not allowed",
        );
      }
    }
  }
  for (const key of requiredKeys) {
    if (!Object.hasOwn(value, key)) {
      fail(
        "EXPORT_REQUIRED_PROPERTY",
        `${path}.${key}`,
        "property is required",
      );
    }
  }
  return value;
}

function stringAt(value: unknown, path: string, pattern?: RegExp): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    return fail("EXPORT_STRING_REQUIRED", path, "expected a non-empty string");
  }
  if (pattern !== undefined && !pattern.test(value)) {
    return fail("EXPORT_STRING_INVALID", path, "value has an invalid format");
  }
  return value;
}

function booleanAt(value: unknown, path: string): boolean {
  if (typeof value !== "boolean") {
    return fail("EXPORT_BOOLEAN_REQUIRED", path, "expected a boolean");
  }
  return value;
}

function arrayAt(value: unknown, path: string): readonly unknown[] {
  if (!Array.isArray(value)) {
    return fail("EXPORT_ARRAY_REQUIRED", path, "expected an array");
  }
  return value;
}

function assertUnique(values: readonly string[], path: string): void {
  if (new Set(values).size !== values.length) {
    fail("EXPORT_DUPLICATE_VALUE", path, "values must be unique");
  }
}

function localizedLabelsAt(
  value: unknown,
  path: string,
): Readonly<Record<string, string>> {
  if (value === undefined) {
    return Object.freeze({});
  }
  const record = recordAt(value, path);
  const result: Record<string, string> = {};
  for (const locale of Object.keys(record).sort()) {
    stringAt(locale, `${path} locale`, LOCALE_PATTERN);
    const label = stringAt(ownValue(record, locale, path), `${path}.${locale}`);
    if (label.length > 256) {
      fail(
        "EXPORT_LABEL_TOO_LONG",
        `${path}.${locale}`,
        "label exceeds 256 characters",
      );
    }
    if (INVALID_XML_CONTROL_PATTERN.test(label)) {
      fail(
        "EXPORT_CONTROL_CHARACTER_INVALID",
        `${path}.${locale}`,
        "label contains an invalid control character",
      );
    }
    result[locale] = label;
  }
  if (Object.keys(result).length === 0) {
    fail(
      "EXPORT_LABELS_EMPTY",
      path,
      "at least one localized label is required",
    );
  }
  return Object.freeze(result);
}

function permissionAt(
  value: unknown,
  path: string,
  allowedPermissions: ReadonlySet<string>,
): string {
  const permission = stringAt(value, path, PERMISSION_PATTERN);
  if (!allowedPermissions.has(permission)) {
    fail(
      "EXPORT_PERMISSION_NOT_ALLOWED",
      path,
      "permission is not allowlisted",
    );
  }
  return permission;
}

function securityAt(
  value: unknown,
  path: string,
  allowedPermissions: ReadonlySet<string>,
): CompiledExportSecurity {
  if (value === undefined) {
    return Object.freeze({
      permission: null,
      stepUpRequired: false,
      auditRequired: true,
      linksExpire: true,
    });
  }
  const record = recordAt(value, path, [
    "permission",
    "step_up_required",
    "audit_required",
    "links_expire",
  ]);
  const rawPermission = ownValue(record, "permission", path);
  const rawStepUp = ownValue(record, "step_up_required", path);
  const rawAudit = ownValue(record, "audit_required", path);
  const rawExpiry = ownValue(record, "links_expire", path);
  const permission =
    rawPermission === undefined
      ? null
      : permissionAt(rawPermission, `${path}.permission`, allowedPermissions);
  const stepUpRequired =
    rawStepUp === undefined
      ? false
      : booleanAt(rawStepUp, `${path}.step_up_required`);
  const auditRequired =
    rawAudit === undefined
      ? true
      : booleanAt(rawAudit, `${path}.audit_required`);
  const linksExpire =
    rawExpiry === undefined
      ? true
      : booleanAt(rawExpiry, `${path}.links_expire`);
  if (!auditRequired) {
    fail(
      "EXPORT_AUDIT_REQUIRED",
      `${path}.audit_required`,
      "export runs cannot disable audit",
    );
  }
  if (!linksExpire) {
    fail(
      "EXPORT_EXPIRY_REQUIRED",
      `${path}.links_expire`,
      "generated export links must expire",
    );
  }
  return Object.freeze({
    permission,
    stepUpRequired,
    auditRequired: true,
    linksExpire: true,
  });
}

function profileSecurityAt(
  value: unknown,
  path: string,
  allowedPermissions: ReadonlySet<string>,
): Pick<CompiledExportSecurity, "permission" | "stepUpRequired"> {
  if (value === undefined) {
    return Object.freeze({ permission: null, stepUpRequired: false });
  }
  const record = recordAt(value, path, ["permission", "step_up_required"]);
  const rawPermission = ownValue(record, "permission", path);
  const rawStepUp = ownValue(record, "step_up_required", path);
  return Object.freeze({
    permission:
      rawPermission === undefined
        ? null
        : permissionAt(rawPermission, `${path}.permission`, allowedPermissions),
    stepUpRequired:
      rawStepUp === undefined
        ? false
        : booleanAt(rawStepUp, `${path}.step_up_required`),
  });
}

function columnsAt(
  value: unknown,
  path: string,
  allowedSources: ReadonlySet<string>,
  allowedPermissions: ReadonlySet<string>,
  maxColumns: number,
): readonly CompiledExportColumn[] {
  const rawColumns = arrayAt(value, path);
  if (rawColumns.length === 0 || rawColumns.length > maxColumns) {
    fail(
      "EXPORT_COLUMN_COUNT_INVALID",
      path,
      `column count must be between 1 and ${maxColumns}`,
    );
  }
  const columns = rawColumns.map((rawColumn, index) => {
    const columnPath = `${path}[${index}]`;
    const record = recordAt(
      rawColumn,
      columnPath,
      [
        "key",
        "label",
        "labels",
        "source",
        "format",
        "sensitive",
        "permission",
        "nullable",
      ],
      ["key", "source"],
    );
    const key = stringAt(
      ownValue(record, "key", columnPath),
      `${columnPath}.key`,
      KEY_PATTERN,
    );
    const source = stringAt(
      ownValue(record, "source", columnPath),
      `${columnPath}.source`,
      SOURCE_PATTERN,
    );
    if (
      source.split(".").some((segment) => FORBIDDEN_PATH_SEGMENTS.has(segment))
    ) {
      fail(
        "EXPORT_SOURCE_NOT_ALLOWED",
        `${columnPath}.source`,
        "prototype-related source segments are forbidden",
      );
    }
    if (!allowedSources.has(source)) {
      fail(
        "EXPORT_SOURCE_NOT_ALLOWED",
        `${columnPath}.source`,
        "source path is not allowlisted for this entity",
      );
    }
    const rawLabel = ownValue(record, "label", columnPath);
    const rawLabels = ownValue(record, "labels", columnPath);
    if (rawLabel !== undefined && rawLabels !== undefined) {
      fail(
        "EXPORT_LABEL_AMBIGUOUS",
        columnPath,
        "use label or labels, not both",
      );
    }
    const rawFormat = ownValue(record, "format", columnPath);
    const format =
      rawFormat === undefined
        ? "text"
        : stringAt(rawFormat, `${columnPath}.format`);
    if (!CELL_FORMATS.has(format as ExportCellFormat)) {
      fail(
        "EXPORT_FORMAT_NOT_ALLOWED",
        `${columnPath}.format`,
        "column format is not an allowlisted data format",
      );
    }
    const rawPermission = ownValue(record, "permission", columnPath);
    const rawSensitive = ownValue(record, "sensitive", columnPath);
    const rawNullable = ownValue(record, "nullable", columnPath);
    const label =
      rawLabel === undefined ? null : stringAt(rawLabel, `${columnPath}.label`);
    if (label !== null && label.length > 256) {
      fail(
        "EXPORT_LABEL_TOO_LONG",
        `${columnPath}.label`,
        "label exceeds 256 characters",
      );
    }
    if (label !== null && INVALID_XML_CONTROL_PATTERN.test(label)) {
      fail(
        "EXPORT_CONTROL_CHARACTER_INVALID",
        `${columnPath}.label`,
        "label contains an invalid control character",
      );
    }
    return Object.freeze({
      key,
      source,
      sourceSegments: Object.freeze(source.split(".")),
      label,
      labels: localizedLabelsAt(rawLabels, `${columnPath}.labels`),
      format: format as ExportCellFormat,
      sensitive:
        rawSensitive === undefined
          ? false
          : booleanAt(rawSensitive, `${columnPath}.sensitive`),
      permission:
        rawPermission === undefined
          ? null
          : permissionAt(
              rawPermission,
              `${columnPath}.permission`,
              allowedPermissions,
            ),
      nullable:
        rawNullable === undefined
          ? false
          : booleanAt(rawNullable, `${columnPath}.nullable`),
    });
  });
  assertUnique(
    columns.map((column) => column.key),
    `${path}.key`,
  );
  return Object.freeze(columns);
}

function normalizeFilterScalar(
  value: unknown,
  path: string,
): ExportFilterScalar {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean"
  ) {
    if (typeof value === "string" && value.length > 1_000) {
      fail(
        "EXPORT_FILTER_TOO_LONG",
        path,
        "filter string exceeds 1000 characters",
      );
    }
    return value;
  }
  if (typeof value === "number" && Number.isSafeInteger(value)) {
    return value;
  }
  if (typeof value === "bigint") {
    return value.toString();
  }
  return fail(
    "EXPORT_FILTER_VALUE_INVALID",
    path,
    "filter values must be scalar safe values",
  );
}

function normalizeFilterValue(value: unknown, path: string): ExportFilterValue {
  if (Array.isArray(value)) {
    if (value.length > 100) {
      fail(
        "EXPORT_FILTER_ARRAY_TOO_LARGE",
        path,
        "filter array exceeds 100 values",
      );
    }
    return Object.freeze(
      value.map((entry, index) =>
        normalizeFilterScalar(entry, `${path}[${index}]`),
      ),
    );
  }
  return normalizeFilterScalar(value, path);
}

function canonicalJson(value: unknown): string {
  if (value === null) {
    return "null";
  }
  if (typeof value === "string" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      fail(
        "EXPORT_CANONICAL_VALUE_INVALID",
        "$",
        "non-finite numbers are forbidden",
      );
    }
    return JSON.stringify(value);
  }
  if (typeof value === "bigint") {
    return JSON.stringify(value.toString());
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalJson(entry)).join(",")}]`;
  }
  if (isPlainRecord(value)) {
    return `{${Object.keys(value)
      .sort()
      .map(
        (key) =>
          `${JSON.stringify(key)}:${canonicalJson(ownValue(value, key, "$"))}`,
      )
      .join(",")}}`;
  }
  return fail(
    "EXPORT_CANONICAL_VALUE_INVALID",
    "$",
    "unsupported canonical value",
  );
}

export function sha256Hex(bytes: Uint8Array | string): string {
  const input = typeof bytes === "string" ? UTF8_ENCODER.encode(bytes) : bytes;
  const bitLength = input.byteLength * 8;
  const paddedLength = Math.ceil((input.byteLength + 9) / 64) * 64;
  const padded = new Uint8Array(paddedLength);
  padded.set(input);
  padded[input.byteLength] = 0x80;
  const paddedView = new DataView(padded.buffer);
  paddedView.setUint32(
    paddedLength - 8,
    Math.floor(bitLength / 0x1_0000_0000),
    false,
  );
  paddedView.setUint32(paddedLength - 4, bitLength >>> 0, false);

  const state = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
    0x1f83d9ab, 0x5be0cd19,
  ]);
  const words = new Uint32Array(64);
  const rotateRight = (value: number, count: number): number =>
    (value >>> count) | (value << (32 - count));

  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let index = 0; index < 16; index += 1) {
      words[index] = paddedView.getUint32(offset + index * 4, false);
    }
    for (let index = 16; index < 64; index += 1) {
      const left = words[index - 15]!;
      const right = words[index - 2]!;
      const sigma0 =
        rotateRight(left, 7) ^ rotateRight(left, 18) ^ (left >>> 3);
      const sigma1 =
        rotateRight(right, 17) ^ rotateRight(right, 19) ^ (right >>> 10);
      words[index] =
        (words[index - 16]! + sigma0 + words[index - 7]! + sigma1) >>> 0;
    }

    let a = state[0]!;
    let b = state[1]!;
    let c = state[2]!;
    let d = state[3]!;
    let e = state[4]!;
    let f = state[5]!;
    let g = state[6]!;
    let h = state[7]!;
    for (let index = 0; index < 64; index += 1) {
      const sigma1 =
        rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
      const choice = (e & f) ^ (~e & g);
      const temporary1 =
        (h + sigma1 + choice + SHA256_CONSTANTS[index]! + words[index]!) >>> 0;
      const sigma0 =
        rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
      const majority = (a & b) ^ (a & c) ^ (b & c);
      const temporary2 = (sigma0 + majority) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temporary1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) >>> 0;
    }
    state[0] = (state[0]! + a) >>> 0;
    state[1] = (state[1]! + b) >>> 0;
    state[2] = (state[2]! + c) >>> 0;
    state[3] = (state[3]! + d) >>> 0;
    state[4] = (state[4]! + e) >>> 0;
    state[5] = (state[5]! + f) >>> 0;
    state[6] = (state[6]! + g) >>> 0;
    state[7] = (state[7]! + h) >>> 0;
  }

  return [...state]
    .map((value) => value.toString(16).padStart(8, "0"))
    .join("");
}

function positiveBound(
  value: number | undefined,
  fallback: number,
  path: string,
  maximum: number,
): number {
  if (value === undefined) {
    return fallback;
  }
  if (!Number.isSafeInteger(value) || value <= 0 || value > maximum) {
    fail(
      "EXPORT_POLICY_BOUND_INVALID",
      path,
      `bound must be a positive safe integer no greater than ${maximum}`,
    );
  }
  return value;
}

export function compileExportDefinition(
  input: unknown,
  policy: ExportDefinitionPolicy,
): CompiledExportDefinition {
  const allowedPermissions = new Set(policy.allowedPermissions);
  if (allowedPermissions.size !== policy.allowedPermissions.length) {
    fail(
      "EXPORT_DUPLICATE_VALUE",
      "policy.allowedPermissions",
      "permissions must be unique",
    );
  }
  for (const permission of allowedPermissions) {
    stringAt(permission, "policy.allowedPermissions", PERMISSION_PATTERN);
  }
  const defaultRunPermission =
    policy.defaultRunPermission ?? DEFAULT_EXPORT_RUN_PERMISSION;
  const sensitiveRunPermission =
    policy.sensitiveRunPermission ?? DEFAULT_SENSITIVE_EXPORT_PERMISSION;
  for (const permission of [defaultRunPermission, sensitiveRunPermission]) {
    stringAt(permission, "policy permission", PERMISSION_PATTERN);
    if (!allowedPermissions.has(permission)) {
      fail(
        "EXPORT_POLICY_PERMISSION_MISSING",
        "policy.allowedPermissions",
        `${permission} must be allowlisted`,
      );
    }
  }
  const maxColumns = positiveBound(
    policy.maxColumns,
    256,
    "policy.maxColumns",
    16_384,
  );
  const maxRows = positiveBound(
    policy.maxRows,
    100_000,
    "policy.maxRows",
    1_048_575,
  );
  const root = recordAt(
    input,
    "$",
    ["schema_version", "export"],
    ["schema_version", "export"],
  );
  const schemaVersion = ownValue(root, "schema_version", "$.");
  if (schemaVersion !== "1.0" && schemaVersion !== "1.1") {
    fail(
      "EXPORT_SCHEMA_VERSION_UNSUPPORTED",
      "$.schema_version",
      "unsupported schema version",
    );
  }
  const exportRecord = recordAt(
    ownValue(root, "export", "$"),
    "$.export",
    [
      "key",
      "version",
      "owner",
      "labels",
      "entity",
      "formats",
      "columns",
      "profiles",
      "enabled_document_types",
      "default_filters",
      "available_filters",
      "security",
      "activation_gate",
    ],
    ["key", "version", "formats", "entity"],
  );
  const key = stringAt(
    ownValue(exportRecord, "key", "$.export"),
    "$.export.key",
    KEY_PATTERN,
  );
  const version = stringAt(
    ownValue(exportRecord, "version", "$.export"),
    "$.export.version",
    VERSION_PATTERN,
  );
  const entity = stringAt(
    ownValue(exportRecord, "entity", "$.export"),
    "$.export.entity",
    KEY_PATTERN,
  );
  const allowedSourceValues = Object.hasOwn(
    policy.allowedSourcesByEntity,
    entity,
  )
    ? policy.allowedSourcesByEntity[entity]
    : undefined;
  if (!Array.isArray(allowedSourceValues) || allowedSourceValues.length === 0) {
    fail(
      "EXPORT_ENTITY_NOT_ALLOWED",
      "$.export.entity",
      "entity has no source allowlist",
    );
  }
  const allowedSources = new Set<string>(
    allowedSourceValues as readonly string[],
  );
  for (const source of allowedSources) {
    stringAt(source, "policy.allowedSourcesByEntity", SOURCE_PATTERN);
    if (
      source.split(".").some((segment) => FORBIDDEN_PATH_SEGMENTS.has(segment))
    ) {
      fail(
        "EXPORT_SOURCE_NOT_ALLOWED",
        "policy.allowedSourcesByEntity",
        "prototype-related source segments are forbidden",
      );
    }
  }

  const rawFormats = arrayAt(
    ownValue(exportRecord, "formats", "$.export"),
    "$.export.formats",
  );
  if (rawFormats.length === 0) {
    fail(
      "EXPORT_FORMATS_EMPTY",
      "$.export.formats",
      "at least one format is required",
    );
  }
  const formats = rawFormats.map((format, index) => {
    if (format !== "csv" && format !== "xlsx") {
      return fail(
        "EXPORT_OUTPUT_FORMAT_INVALID",
        `$.export.formats[${index}]`,
        "format must be csv or xlsx",
      );
    }
    return format;
  });
  assertUnique(formats, "$.export.formats");

  const rawColumns = ownValue(exportRecord, "columns", "$.export");
  const rawProfiles = ownValue(exportRecord, "profiles", "$.export");
  if ((rawColumns === undefined) === (rawProfiles === undefined)) {
    fail(
      "EXPORT_COLUMN_MODE_INVALID",
      "$.export",
      "exactly one of columns or profiles is required",
    );
  }
  const columns =
    rawColumns === undefined
      ? null
      : columnsAt(
          rawColumns,
          "$.export.columns",
          allowedSources,
          allowedPermissions,
          maxColumns,
        );
  let profiles: Readonly<Record<string, CompiledExportProfile>> | null = null;
  if (rawProfiles !== undefined) {
    const profileRecord = recordAt(rawProfiles, "$.export.profiles");
    if (Object.keys(profileRecord).length === 0) {
      fail(
        "EXPORT_PROFILES_EMPTY",
        "$.export.profiles",
        "at least one profile is required",
      );
    }
    const compiledProfiles: Record<string, CompiledExportProfile> = {};
    for (const profileKey of Object.keys(profileRecord).sort()) {
      stringAt(profileKey, "$.export.profiles key", KEY_PATTERN);
      const profilePath = `$.export.profiles.${profileKey}`;
      const profile = recordAt(
        ownValue(profileRecord, profileKey, "$.export.profiles"),
        profilePath,
        ["labels", "columns", "security"],
        ["columns"],
      );
      compiledProfiles[profileKey] = Object.freeze({
        key: profileKey,
        labels: localizedLabelsAt(
          ownValue(profile, "labels", profilePath),
          `${profilePath}.labels`,
        ),
        columns: columnsAt(
          ownValue(profile, "columns", profilePath),
          `${profilePath}.columns`,
          allowedSources,
          allowedPermissions,
          maxColumns,
        ),
        security: profileSecurityAt(
          ownValue(profile, "security", profilePath),
          `${profilePath}.security`,
          allowedPermissions,
        ),
      });
    }
    profiles = Object.freeze(compiledProfiles);
  }

  const allowedFilterValues =
    policy.allowedFiltersByEntity !== undefined &&
    Object.hasOwn(policy.allowedFiltersByEntity, entity)
      ? policy.allowedFiltersByEntity[entity]
      : undefined;
  if (
    allowedFilterValues !== undefined &&
    !Array.isArray(allowedFilterValues)
  ) {
    fail(
      "EXPORT_POLICY_FILTERS_INVALID",
      "policy.allowedFiltersByEntity",
      "filter allowlist must be an array",
    );
  }
  const allowedFilters = new Set(allowedFilterValues ?? []);
  for (const filter of allowedFilters) {
    stringAt(filter, "policy.allowedFiltersByEntity", FILTER_PATTERN);
  }
  const rawAvailableFilters = ownValue(
    exportRecord,
    "available_filters",
    "$.export",
  );
  const availableFilters =
    rawAvailableFilters === undefined
      ? []
      : arrayAt(rawAvailableFilters, "$.export.available_filters").map(
          (filter, index) => {
            const keyValue = stringAt(
              filter,
              `$.export.available_filters[${index}]`,
              FILTER_PATTERN,
            );
            if (!allowedFilters.has(keyValue)) {
              fail(
                "EXPORT_FILTER_NOT_ALLOWED",
                `$.export.available_filters[${index}]`,
                "filter is not allowlisted for this entity",
              );
            }
            return keyValue;
          },
        );
  assertUnique(availableFilters, "$.export.available_filters");

  const rawDefaultFilters = ownValue(
    exportRecord,
    "default_filters",
    "$.export",
  );
  const defaultFilters: Record<string, ExportFilterValue> = {};
  if (rawDefaultFilters !== undefined) {
    const filterRecord = recordAt(
      rawDefaultFilters,
      "$.export.default_filters",
    );
    for (const filter of Object.keys(filterRecord).sort()) {
      stringAt(filter, "$.export.default_filters key", FILTER_PATTERN);
      if (!allowedFilters.has(filter)) {
        fail(
          "EXPORT_FILTER_NOT_ALLOWED",
          `$.export.default_filters.${filter}`,
          "filter is not allowlisted for this entity",
        );
      }
      defaultFilters[filter] = normalizeFilterValue(
        ownValue(filterRecord, filter, "$.export.default_filters"),
        `$.export.default_filters.${filter}`,
      );
    }
  }

  const rawEnabledDocumentTypes = ownValue(
    exportRecord,
    "enabled_document_types",
    "$.export",
  );
  const enabledDocumentTypes =
    rawEnabledDocumentTypes === undefined
      ? []
      : arrayAt(rawEnabledDocumentTypes, "$.export.enabled_document_types").map(
          (documentType, index) =>
            stringAt(
              documentType,
              `$.export.enabled_document_types[${index}]`,
              KEY_PATTERN,
            ),
        );
  assertUnique(enabledDocumentTypes, "$.export.enabled_document_types");

  const rawOwner = ownValue(exportRecord, "owner", "$.export");
  const rawActivationGate = ownValue(
    exportRecord,
    "activation_gate",
    "$.export",
  );
  return Object.freeze({
    schemaVersion,
    key,
    version,
    owner: rawOwner === undefined ? null : stringAt(rawOwner, "$.export.owner"),
    labels: localizedLabelsAt(
      ownValue(exportRecord, "labels", "$.export"),
      "$.export.labels",
    ),
    entity,
    formats: Object.freeze(formats),
    columns,
    profiles,
    enabledDocumentTypes: Object.freeze(enabledDocumentTypes),
    defaultFilters: Object.freeze(defaultFilters),
    availableFilters: Object.freeze(availableFilters),
    security: securityAt(
      ownValue(exportRecord, "security", "$.export"),
      "$.export.security",
      allowedPermissions,
    ),
    activationGate:
      rawActivationGate === undefined
        ? null
        : stringAt(rawActivationGate, "$.export.activation_gate", KEY_PATTERN),
    definitionChecksum: sha256Hex(canonicalJson(input)),
    defaultRunPermission,
    sensitiveRunPermission,
    maxRows,
  });
}

function localeCandidates(
  locale: string,
  fallbackLocale: string,
): readonly string[] {
  const result: string[] = [];
  for (const candidate of [
    locale,
    locale.split("-")[0],
    fallbackLocale,
    fallbackLocale.split("-")[0],
  ]) {
    if (
      candidate !== undefined &&
      candidate.length > 0 &&
      !result.includes(candidate)
    ) {
      result.push(candidate);
    }
  }
  return result;
}

export function resolveLocalizedLabel(
  labels: Readonly<Record<string, string>>,
  locale: string,
  fallback: string,
  fallbackLocale = "en",
): string {
  stringAt(locale, "locale", LOCALE_PATTERN);
  stringAt(fallbackLocale, "fallbackLocale", LOCALE_PATTERN);
  const entries = Object.entries(labels);
  for (const candidate of localeCandidates(locale, fallbackLocale)) {
    const entry = entries.find(
      ([key]) => key.toLowerCase() === candidate.toLowerCase(),
    );
    if (entry !== undefined) {
      return entry[1];
    }
  }
  return (
    entries.sort(([left], [right]) => left.localeCompare(right))[0]?.[1] ??
    fallback
  );
}

function selectionFor(
  definition: CompiledExportDefinition,
  profileKey: string | undefined,
): {
  readonly profile: CompiledExportProfile | null;
  readonly columns: readonly CompiledExportColumn[];
} {
  if (definition.columns !== null) {
    if (profileKey !== undefined) {
      fail(
        "EXPORT_PROFILE_NOT_SUPPORTED",
        "profileKey",
        "definition has direct columns",
      );
    }
    return { profile: null, columns: definition.columns };
  }
  if (profileKey === undefined) {
    return fail(
      "EXPORT_PROFILE_REQUIRED",
      "profileKey",
      "a profile must be selected",
    );
  }
  const profile = definition.profiles?.[profileKey];
  if (profile === undefined) {
    return fail(
      "EXPORT_PROFILE_UNKNOWN",
      "profileKey",
      "profile is not defined",
    );
  }
  return { profile, columns: profile.columns };
}

function epochMilliseconds(
  value: Date | string | number,
  path: string,
): number {
  const milliseconds =
    value instanceof Date
      ? value.getTime()
      : typeof value === "number"
        ? value
        : Date.parse(value);
  if (!Number.isSafeInteger(milliseconds)) {
    fail("EXPORT_TIMESTAMP_INVALID", path, "timestamp is invalid");
  }
  return milliseconds;
}

export function authorizeExportRun(
  definition: CompiledExportDefinition,
  context: ExportAuthorizationContext,
  profileKey?: string,
): ExportAuthorizationDecision {
  if (!Array.isArray(context.grantedPermissions)) {
    fail(
      "EXPORT_PERMISSIONS_INVALID",
      "authorization.grantedPermissions",
      "granted permissions must be an array",
    );
  }
  for (const permission of context.grantedPermissions) {
    stringAt(
      permission,
      "authorization.grantedPermissions",
      PERMISSION_PATTERN,
    );
  }
  const selection = selectionFor(definition, profileKey);
  const required = new Set<string>([definition.defaultRunPermission]);
  if (definition.security.permission !== null) {
    required.add(definition.security.permission);
  }
  if (
    selection.profile?.security.permission !== null &&
    selection.profile !== null
  ) {
    required.add(selection.profile.security.permission);
  }
  const hasSensitiveColumns = selection.columns.some(
    (column) => column.sensitive,
  );
  if (hasSensitiveColumns) {
    required.add(definition.sensitiveRunPermission);
  }
  for (const column of selection.columns) {
    if (column.permission !== null) {
      required.add(column.permission);
    }
  }
  const requiredPermissions = [...required].sort();
  const granted = new Set(context.grantedPermissions);
  const missingPermissions = requiredPermissions.filter(
    (permission) => !granted.has(permission),
  );
  const requiresStepUp =
    definition.security.stepUpRequired ||
    (selection.profile?.security.stepUpRequired ?? false) ||
    hasSensitiveColumns;
  const now =
    context.now === undefined
      ? Date.now()
      : epochMilliseconds(context.now, "authorization.now");
  const strongAuthAt =
    context.strongAuthAt === undefined || context.strongAuthAt === null
      ? null
      : epochMilliseconds(context.strongAuthAt, "authorization.strongAuthAt");
  const stepUpSatisfied =
    !requiresStepUp ||
    (strongAuthAt !== null &&
      strongAuthAt <= now &&
      now - strongAuthAt <= EXPORT_STEP_UP_MAX_AGE_MS);
  const code: ExportAuthorizationCode =
    missingPermissions.length > 0
      ? "EXPORT_PERMISSION_REQUIRED"
      : !stepUpSatisfied
        ? "EXPORT_STEP_UP_REQUIRED"
        : "EXPORT_AUTHORIZED";
  return Object.freeze({
    allowed: code === "EXPORT_AUTHORIZED",
    code,
    requiredPermissions: Object.freeze(requiredPermissions),
    missingPermissions: Object.freeze(missingPermissions),
    requiresStepUp,
    stepUpSatisfied,
  });
}

function sourceValue(
  row: Readonly<Record<string, unknown>>,
  column: CompiledExportColumn,
  rowIndex: number,
): unknown {
  if (!isPlainRecord(row)) {
    return fail(
      "EXPORT_ROW_INVALID",
      `rows[${rowIndex}]`,
      "row must be a plain data object",
    );
  }
  const flat = Object.getOwnPropertyDescriptor(row, column.source);
  if (flat !== undefined) {
    if (!("value" in flat)) {
      return fail(
        "EXPORT_ACCESSOR_FORBIDDEN",
        `rows[${rowIndex}].${column.source}`,
        "source may not be an accessor",
      );
    }
    return flat.value;
  }
  let current: unknown = row;
  for (const segment of column.sourceSegments) {
    if (!isPlainRecord(current)) {
      return undefined;
    }
    current = ownValue(current, segment, `rows[${rowIndex}]`);
  }
  return current;
}

function exactInteger(value: unknown, path: string): string {
  if (typeof value === "bigint") {
    return value.toString();
  }
  if (typeof value === "number" && Number.isSafeInteger(value)) {
    return value.toString();
  }
  if (typeof value === "string" && INTEGER_PATTERN.test(value)) {
    return value;
  }
  return fail(
    "EXPORT_EXACT_INTEGER_REQUIRED",
    path,
    "expected bigint, safe integer, or canonical integer string",
  );
}

function validCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return (
    !Number.isNaN(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value
  );
}

function normalizeCellValue(
  value: unknown,
  column: CompiledExportColumn,
  path: string,
): string {
  if (value === null || value === undefined) {
    if (column.nullable) {
      return "";
    }
    return fail(
      "EXPORT_VALUE_REQUIRED",
      path,
      "non-null export value is missing",
    );
  }
  let result: string;
  switch (column.format) {
    case "integer":
    case "minor_units":
      result = exactInteger(value, path);
      break;
    case "decimal":
      if (typeof value === "bigint") {
        result = value.toString();
      } else if (typeof value === "number" && Number.isSafeInteger(value)) {
        result = value.toString();
      } else if (typeof value === "string" && DECIMAL_PATTERN.test(value)) {
        result = value;
      } else {
        return fail(
          "EXPORT_EXACT_DECIMAL_REQUIRED",
          path,
          "decimal values must avoid binary floating point",
        );
      }
      break;
    case "currency_code":
      if (typeof value !== "string" || !/^[A-Z]{3}$/.test(value)) {
        return fail(
          "EXPORT_CURRENCY_INVALID",
          path,
          "expected an uppercase ISO currency code",
        );
      }
      result = value;
      break;
    case "date": {
      if (value instanceof Date && Number.isNaN(value.getTime())) {
        return fail("EXPORT_DATE_INVALID", path, "expected a valid date");
      }
      const dateValue =
        value instanceof Date ? value.toISOString().slice(0, 10) : value;
      if (typeof dateValue !== "string" || !validCalendarDate(dateValue)) {
        return fail(
          "EXPORT_DATE_INVALID",
          path,
          "expected a valid YYYY-MM-DD date",
        );
      }
      result = dateValue;
      break;
    }
    case "datetime": {
      if (
        !(value instanceof Date) &&
        (typeof value !== "string" || !ISO_DATETIME_PATTERN.test(value))
      ) {
        return fail(
          "EXPORT_DATETIME_INVALID",
          path,
          "expected an ISO timestamp",
        );
      }
      const parsed = value instanceof Date ? value : new Date(value);
      if (Number.isNaN(parsed.getTime())) {
        return fail(
          "EXPORT_DATETIME_INVALID",
          path,
          "expected an ISO timestamp",
        );
      }
      result = parsed.toISOString();
      break;
    }
    case "boolean":
      if (typeof value !== "boolean") {
        return fail(
          "EXPORT_BOOLEAN_VALUE_INVALID",
          path,
          "expected a boolean value",
        );
      }
      result = value ? "true" : "false";
      break;
    case "text":
      if (typeof value === "string") {
        result = value;
      } else if (typeof value === "bigint" || typeof value === "boolean") {
        result = value.toString();
      } else if (typeof value === "number" && Number.isSafeInteger(value)) {
        result = value.toString();
      } else if (value instanceof Date && !Number.isNaN(value.getTime())) {
        result = value.toISOString();
      } else {
        return fail(
          "EXPORT_TEXT_VALUE_INVALID",
          path,
          "text conversion rejects objects and inexact numbers",
        );
      }
      break;
  }
  if (INVALID_XML_CONTROL_PATTERN.test(result)) {
    fail(
      "EXPORT_CONTROL_CHARACTER_INVALID",
      path,
      "value contains an invalid control character",
    );
  }
  if (result.length > 32_767) {
    fail(
      "EXPORT_CELL_TOO_LONG",
      path,
      "cell exceeds the spreadsheet limit of 32767 characters",
    );
  }
  return result;
}

function csvCell(value: string, protectFormula: boolean): string {
  const protectedValue =
    protectFormula && (CSV_FORMULA_PATTERN.test(value) || /^[\t\r]/.test(value))
      ? `'${value}`
      : value;
  return `"${protectedValue.replaceAll('"', '""')}"`;
}

function createCsv(
  rows: readonly (readonly string[])[],
  columns: readonly CompiledExportColumn[],
): Uint8Array {
  const lines = rows.map((row, rowIndex) =>
    row
      .map((value, columnIndex) =>
        csvCell(
          value,
          rowIndex === 0 || columns[columnIndex]?.format === "text",
        ),
      )
      .join(","),
  );
  return UTF8_ENCODER.encode(`\ufeff${lines.join("\r\n")}\r\n`);
}

export function generateExportArtifact(
  input: GenerateExportArtifactInput,
): GeneratedExportArtifact {
  if (!Array.isArray(input.rows)) {
    fail("EXPORT_ROWS_INVALID", "rows", "rows must be an array");
  }
  const selection = selectionFor(input.definition, input.profileKey);
  if (!input.definition.formats.includes(input.format)) {
    fail(
      "EXPORT_OUTPUT_FORMAT_NOT_ENABLED",
      "format",
      "format is not enabled by definition",
    );
  }
  if (input.rows.length > input.definition.maxRows) {
    fail(
      "EXPORT_ROW_LIMIT_EXCEEDED",
      "rows",
      "row count exceeds the configured limit",
    );
  }
  const authorization = authorizeExportRun(
    input.definition,
    input.authorization,
    input.profileKey,
  );
  if (!authorization.allowed) {
    fail(authorization.code, "authorization", "export run is not authorized");
  }
  const labels = selection.columns.map((column) =>
    resolveLocalizedLabel(
      column.labels,
      input.locale,
      column.label ?? column.key,
    ),
  );
  const dataRows = input.rows.map((row, rowIndex) =>
    selection.columns.map((column) =>
      normalizeCellValue(
        sourceValue(row, column, rowIndex),
        column,
        `rows[${rowIndex}].${column.source}`,
      ),
    ),
  );
  const matrix: readonly (readonly string[])[] = Object.freeze([
    Object.freeze(labels),
    ...dataRows.map((row) => Object.freeze(row)),
  ]);
  const worksheetName = resolveLocalizedLabel(
    selection.profile?.labels ?? input.definition.labels,
    input.locale,
    selection.profile?.key ?? input.definition.key,
  );
  const bytes =
    input.format === "csv"
      ? createCsv(matrix, selection.columns)
      : createDeterministicXlsx(worksheetName, matrix);
  return Object.freeze({
    definitionKey: input.definition.key,
    definitionVersion: input.definition.version,
    definitionChecksum: input.definition.definitionChecksum,
    profileKey: selection.profile?.key ?? null,
    format: input.format,
    locale: input.locale,
    contentType:
      input.format === "csv"
        ? "text/csv; charset=utf-8"
        : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    extension: input.format,
    bytes,
    checksum: sha256Hex(bytes),
    byteCount: bytes.byteLength,
    rowCount: input.rows.length,
    columnCount: selection.columns.length,
    labels: Object.freeze(labels),
    authorization,
  });
}

export function normalizeExportFilters(
  definition: CompiledExportDefinition,
  requested: Readonly<Record<string, unknown>> = {},
): Readonly<Record<string, ExportFilterValue>> {
  const input = recordAt(requested, "filters");
  const allowed = new Set(definition.availableFilters);
  const merged: Record<string, ExportFilterValue> = {
    ...definition.defaultFilters,
  };
  for (const filter of Object.keys(input).sort()) {
    if (!allowed.has(filter)) {
      fail(
        "EXPORT_FILTER_NOT_AVAILABLE",
        `filters.${filter}`,
        "filter is not available to callers",
      );
    }
    merged[filter] = normalizeFilterValue(
      ownValue(input, filter, "filters"),
      `filters.${filter}`,
    );
  }
  return Object.freeze(
    Object.fromEntries(
      Object.keys(merged)
        .sort()
        .map((key) => [key, merged[key]!]),
    ) as Record<string, ExportFilterValue>,
  );
}

function opaqueId(value: string, path: string): string {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    fail("EXPORT_ID_INVALID", path, "identifier has an invalid format");
  }
  return value;
}

export function createExportRunMetadata(
  definition: CompiledExportDefinition,
  artifact: GeneratedExportArtifact,
  input: CreateExportRunMetadataInput,
): ExportRunMetadata {
  if (
    artifact.definitionKey !== definition.key ||
    artifact.definitionVersion !== definition.version ||
    artifact.definitionChecksum !== definition.definitionChecksum
  ) {
    fail(
      "EXPORT_ARTIFACT_DEFINITION_MISMATCH",
      "artifact",
      "artifact does not belong to the exact definition version",
    );
  }
  const createdMilliseconds = epochMilliseconds(input.createdAt, "createdAt");
  const expiresMilliseconds =
    input.expiresAt === undefined
      ? null
      : epochMilliseconds(input.expiresAt, "expiresAt");
  if (definition.security.linksExpire && expiresMilliseconds === null) {
    fail(
      "EXPORT_EXPIRY_REQUIRED",
      "expiresAt",
      "an expiring download timestamp is required",
    );
  }
  if (
    expiresMilliseconds !== null &&
    expiresMilliseconds <= createdMilliseconds
  ) {
    fail("EXPORT_EXPIRY_INVALID", "expiresAt", "expiry must be after creation");
  }
  const filters = normalizeExportFilters(definition, input.filters);
  return Object.freeze({
    workspaceId: opaqueId(input.workspaceId, "workspaceId"),
    actorId: opaqueId(input.actorId, "actorId"),
    definitionKey: artifact.definitionKey,
    definitionVersion: artifact.definitionVersion,
    definitionChecksum: artifact.definitionChecksum,
    profileKey: artifact.profileKey,
    format: artifact.format,
    locale: artifact.locale,
    filters,
    filtersChecksum: sha256Hex(canonicalJson(filters)),
    rowCount: artifact.rowCount,
    byteCount: artifact.byteCount,
    artifactChecksum: artifact.checksum,
    createdAt: new Date(createdMilliseconds).toISOString(),
    expiresAt:
      expiresMilliseconds === null
        ? null
        : new Date(expiresMilliseconds).toISOString(),
    auditRequired: true,
  });
}
