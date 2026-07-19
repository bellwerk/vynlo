const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const KEY_PATTERN = /^[a-z][a-z0-9_.-]{0,127}$/u;
const VERSION_PATTERN = /^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$/u;
const CHECKSUM_PATTERN = /^[a-f0-9]{64}$/u;
const LOCALE_PATTERN = /^[a-z]{2,3}(?:-[A-Z][A-Za-z0-9]{1,7})?$/u;
const ISO_INSTANT_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:\d{2})$/u;

export type DocumentDomainErrorCode =
  | "invalid_identifier"
  | "invalid_key"
  | "invalid_version"
  | "invalid_checksum"
  | "checksum_mismatch"
  | "invalid_definition"
  | "invalid_activation"
  | "approval_required"
  | "arbitrary_execution_not_allowed"
  | "unsafe_template_source"
  | "template_syntax_invalid"
  | "template_resource_limit"
  | "template_field_missing"
  | "template_value_invalid"
  | "invalid_numbering_definition"
  | "number_out_of_range"
  | "invalid_document"
  | "invalid_document_transition"
  | "immutable_document_field"
  | "duplicate_document_file"
  | "reason_required";

export class DocumentDomainError extends Error {
  readonly code: DocumentDomainErrorCode;
  readonly detail: string | null;

  constructor(code: DocumentDomainErrorCode, detail: string | null = null) {
    super(detail === null ? code : `${code}:${detail}`);
    this.name = "DocumentDomainError";
    this.code = code;
    this.detail = detail;
  }
}

export type PlainRecord = Record<string, unknown>;

export function requirePlainRecord(
  value: unknown,
  code: DocumentDomainErrorCode = "invalid_definition",
): PlainRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new DocumentDomainError(code);
  }
  const prototype = Object.getPrototypeOf(value) as unknown;
  if (prototype !== Object.prototype && prototype !== null) {
    throw new DocumentDomainError(code);
  }
  for (const key of Reflect.ownKeys(value)) {
    if (typeof key !== "string") {
      throw new DocumentDomainError(code);
    }
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor?.get || descriptor?.set) {
      throw new DocumentDomainError("arbitrary_execution_not_allowed", key);
    }
    if (!descriptor || !descriptor.enumerable) {
      throw new DocumentDomainError(code, key);
    }
  }
  return value as PlainRecord;
}

export function assertExactKeys(
  record: PlainRecord,
  allowed: readonly string[],
  code: DocumentDomainErrorCode = "invalid_definition",
): void {
  const allowedSet = new Set(allowed);
  for (const key of Object.keys(record)) {
    if (!allowedSet.has(key)) {
      throw new DocumentDomainError(code, key);
    }
  }
}

export function requireDenseArray(
  value: unknown,
  code: DocumentDomainErrorCode = "invalid_definition",
): readonly unknown[] {
  if (
    !Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Array.prototype
  ) {
    throw new DocumentDomainError(code, "array");
  }
  let indexes = 0;
  for (const key of Reflect.ownKeys(value)) {
    if (key === "length") continue;
    if (
      typeof key !== "string" ||
      !/^(?:0|[1-9]\d*)$/u.test(key) ||
      Number(key) >= value.length
    ) {
      throw new DocumentDomainError(code, "array_property");
    }
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor?.get || descriptor?.set) {
      throw new DocumentDomainError("arbitrary_execution_not_allowed", key);
    }
    if (!descriptor || !descriptor.enumerable) {
      throw new DocumentDomainError(code, "array_property");
    }
    indexes += 1;
  }
  if (indexes !== value.length) {
    throw new DocumentDomainError(code, "sparse_array");
  }
  return value;
}

export function requireUuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new DocumentDomainError("invalid_identifier");
  }
  return value.toLowerCase();
}

export function requireKey(value: unknown): string {
  if (typeof value !== "string") {
    throw new DocumentDomainError("invalid_key");
  }
  const normalized = value.trim().toLowerCase();
  if (!KEY_PATTERN.test(normalized)) {
    throw new DocumentDomainError("invalid_key");
  }
  return normalized;
}

export function requireVersion(value: unknown): string {
  if (typeof value !== "string" || !VERSION_PATTERN.test(value)) {
    throw new DocumentDomainError("invalid_version");
  }
  return value;
}

export function requireChecksum(value: unknown): string {
  if (typeof value !== "string" || !CHECKSUM_PATTERN.test(value)) {
    throw new DocumentDomainError("invalid_checksum");
  }
  return value;
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    return leap ? 29 : 28;
  }
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

/** Accepts only an explicit ISO-8601 instant and returns canonical UTC form. */
export function normalizeIsoInstant(
  value: unknown,
  code: DocumentDomainErrorCode = "invalid_definition",
  detail = "instant",
): string {
  if (typeof value !== "string") {
    throw new DocumentDomainError(code, detail);
  }
  const match = ISO_INSTANT_PATTERN.exec(value);
  if (!match) {
    throw new DocumentDomainError(code, detail);
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const zone = match[8] ?? "";
  const offset = /^([+-])(\d{2}):(\d{2})$/u.exec(zone);
  if (
    year < 1 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > daysInMonth(year, month) ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    (offset !== null && (Number(offset[2]) > 23 || Number(offset[3]) > 59))
  ) {
    throw new DocumentDomainError(code, detail);
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) {
    throw new DocumentDomainError(code, detail);
  }
  const normalized = new Date(parsed).toISOString();
  if (!/^\d{4}-/u.test(normalized)) {
    throw new DocumentDomainError(code, detail);
  }
  return normalized;
}

export function requireLocale(value: unknown): string {
  if (typeof value !== "string" || !LOCALE_PATTERN.test(value)) {
    throw new DocumentDomainError("invalid_definition", "locale");
  }
  return value;
}

export function requireBoundedText(
  value: unknown,
  maximumLength: number,
  code: DocumentDomainErrorCode = "invalid_definition",
): string {
  if (typeof value !== "string") {
    throw new DocumentDomainError(code);
  }
  const normalized = value.trim();
  if (!normalized || normalized.length > maximumLength) {
    throw new DocumentDomainError(code);
  }
  return normalized;
}

export function normalizeLabels(
  value: unknown,
): Readonly<Record<"en" | "fr", string>> {
  const record = requirePlainRecord(value);
  assertExactKeys(record, ["en", "fr"]);
  const en = requireBoundedText(record.en, 200);
  const fr = requireBoundedText(record.fr, 200);
  return Object.freeze({ en, fr });
}

function canonicalValue(
  value: unknown,
  state: { nodes: number; readonly ancestors: Set<object> },
  depth: number,
): string {
  state.nodes += 1;
  if (state.nodes > 20_000 || depth > 64) {
    throw new DocumentDomainError("invalid_definition", "json_resource_limit");
  }
  if (value === null) return "null";
  if (typeof value === "string" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new DocumentDomainError("invalid_definition", "non_finite_number");
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    requireDenseArray(value);
    const indexKeys = Object.keys(value);
    if (state.ancestors.has(value)) {
      throw new DocumentDomainError("invalid_definition", "cyclic_json");
    }
    state.ancestors.add(value);
    const serialized = `[${indexKeys
      .sort((left, right) => Number(left) - Number(right))
      .map((key) => {
        const descriptor = Object.getOwnPropertyDescriptor(value, key);
        return canonicalValue(descriptor?.value, state, depth + 1);
      })
      .join(",")}]`;
    state.ancestors.delete(value);
    return serialized;
  }
  const record = requirePlainRecord(value);
  if (state.ancestors.has(record)) {
    throw new DocumentDomainError("invalid_definition", "cyclic_json");
  }
  state.ancestors.add(record);
  const serialized = `{${Object.keys(record)
    .sort()
    .map(
      (key) =>
        `${JSON.stringify(key)}:${canonicalValue(record[key], state, depth + 1)}`,
    )
    .join(",")}}`;
  state.ancestors.delete(record);
  return serialized;
}

/** RFC 8785-style stable JSON for the JSON subset used by configuration. */
export function canonicalJson(value: unknown): string {
  const serialized = canonicalValue(
    value,
    { ancestors: new Set<object>(), nodes: 0 },
    0,
  );
  if (serialized.length > 2_000_000) {
    throw new DocumentDomainError("invalid_definition", "json_too_large");
  }
  return serialized;
}

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

function rotateRight(value: number, bits: number): number {
  return (value >>> bits) | (value << (32 - bits));
}

/** Dependency-free synchronous SHA-256 for immutable configuration bytes. */
export function sha256Hex(value: string | Uint8Array): string {
  const bytes =
    typeof value === "string" ? new TextEncoder().encode(value) : value;
  const paddedLength = Math.ceil((bytes.byteLength + 9) / 64) * 64;
  const padded = new Uint8Array(paddedLength);
  padded.set(bytes);
  padded[bytes.byteLength] = 0x80;
  const bitLength = BigInt(bytes.byteLength) * 8n;
  const lengthView = new DataView(padded.buffer);
  lengthView.setUint32(paddedLength - 8, Number(bitLength >> 32n), false);
  lengthView.setUint32(
    paddedLength - 4,
    Number(bitLength & 0xffff_ffffn),
    false,
  );

  const hash = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
    0x1f83d9ab, 0x5be0cd19,
  ]);
  const words = new Uint32Array(64);
  const view = new DataView(padded.buffer);
  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let index = 0; index < 16; index += 1) {
      words[index] = view.getUint32(offset + index * 4, false);
    }
    for (let index = 16; index < 64; index += 1) {
      const left = words[index - 15] ?? 0;
      const right = words[index - 2] ?? 0;
      const sigma0 =
        rotateRight(left, 7) ^ rotateRight(left, 18) ^ (left >>> 3);
      const sigma1 =
        rotateRight(right, 17) ^ rotateRight(right, 19) ^ (right >>> 10);
      words[index] =
        ((words[index - 16] ?? 0) +
          sigma0 +
          (words[index - 7] ?? 0) +
          sigma1) >>>
        0;
    }

    let a = hash[0] ?? 0;
    let b = hash[1] ?? 0;
    let c = hash[2] ?? 0;
    let d = hash[3] ?? 0;
    let e = hash[4] ?? 0;
    let f = hash[5] ?? 0;
    let g = hash[6] ?? 0;
    let h = hash[7] ?? 0;
    for (let index = 0; index < 64; index += 1) {
      const sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
      const choose = (e & f) ^ (~e & g);
      const temporary1 =
        (h +
          sum1 +
          choose +
          (SHA256_CONSTANTS[index] ?? 0) +
          (words[index] ?? 0)) >>>
        0;
      const sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
      const majority = (a & b) ^ (a & c) ^ (b & c);
      const temporary2 = (sum0 + majority) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temporary1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) >>> 0;
    }
    hash[0] = ((hash[0] ?? 0) + a) >>> 0;
    hash[1] = ((hash[1] ?? 0) + b) >>> 0;
    hash[2] = ((hash[2] ?? 0) + c) >>> 0;
    hash[3] = ((hash[3] ?? 0) + d) >>> 0;
    hash[4] = ((hash[4] ?? 0) + e) >>> 0;
    hash[5] = ((hash[5] ?? 0) + f) >>> 0;
    hash[6] = ((hash[6] ?? 0) + g) >>> 0;
    hash[7] = ((hash[7] ?? 0) + h) >>> 0;
  }
  return [...hash].map((word) => word.toString(16).padStart(8, "0")).join("");
}

export function checksumJson(value: unknown): string {
  return sha256Hex(canonicalJson(value));
}

export function cloneJson<T>(value: T): T {
  return JSON.parse(canonicalJson(value)) as T;
}

export function freezeJson<T>(value: T): Readonly<T> {
  const cloned = cloneJson(value);
  const visit = (entry: unknown): void => {
    if (typeof entry !== "object" || entry === null) return;
    if (Array.isArray(entry)) {
      for (const item of entry) visit(item);
    } else {
      for (const item of Object.values(entry as PlainRecord)) visit(item);
    }
    Object.freeze(entry);
  };
  visit(cloned);
  return cloned;
}
