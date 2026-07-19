import { JobExecutionError } from "./job-runner";

export const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
export const CHECKSUM_PATTERN = /^[a-f0-9]{64}$/u;

export function invalidM4Contract(
  area: "document" | "export",
  label: string,
): JobExecutionError {
  return new JobExecutionError({
    classification: "permanent",
    code: `${area}.invalid_${label}`,
    safeDetail: `The ${area} worker database response failed contract validation.`,
  });
}

export function requireRecord(
  value: unknown,
  area: "document" | "export",
  label: string,
): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidM4Contract(area, label);
  }
  return value as Record<string, unknown>;
}

export function requireArray(
  value: unknown,
  area: "document" | "export",
  label: string,
): readonly unknown[] {
  if (!Array.isArray(value)) throw invalidM4Contract(area, label);
  return value;
}

export function requireString(
  value: unknown,
  area: "document" | "export",
  label: string,
  maximumLength = 2_000_000,
): string {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > maximumLength
  ) {
    throw invalidM4Contract(area, label);
  }
  return value;
}

export function requireUuid(
  value: unknown,
  area: "document" | "export",
  label: string,
): string {
  const result = requireString(value, area, label, 36);
  if (!UUID_PATTERN.test(result)) throw invalidM4Contract(area, label);
  return result;
}

export function requireChecksum(
  value: unknown,
  area: "document" | "export",
  label: string,
): string {
  const result = requireString(value, area, label, 64);
  if (!CHECKSUM_PATTERN.test(result)) throw invalidM4Contract(area, label);
  return result;
}

export function requireInteger(
  value: unknown,
  area: "document" | "export",
  label: string,
  minimum: number,
  maximum: number,
): number {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < minimum ||
    (value as number) > maximum
  ) {
    throw invalidM4Contract(area, label);
  }
  return value as number;
}

export function assertExactKeys(
  value: Readonly<Record<string, unknown>>,
  expected: readonly string[],
  area: "document" | "export",
  label: string,
): void {
  const actual = Object.keys(value).sort();
  const normalizedExpected = [...expected].sort();
  if (
    actual.length !== normalizedExpected.length ||
    actual.some((key, index) => key !== normalizedExpected[index])
  ) {
    throw invalidM4Contract(area, label);
  }
}

export function validatedSupabaseOrigin(value: string): string {
  const url = new URL(value);
  const local = ["127.0.0.1", "localhost", "::1"].includes(url.hostname);
  if (
    (url.protocol !== "https:" && !(url.protocol === "http:" && local)) ||
    url.username !== "" ||
    url.password !== "" ||
    !["", "/"].includes(url.pathname) ||
    url.search !== "" ||
    url.hash !== ""
  ) {
    throw new TypeError("Supabase worker URL must be a safe origin.");
  }
  return url.toString().replace(/\/$/u, "");
}

export function classifyM4Response(
  area: "document" | "export",
  response: Response,
): JobExecutionError {
  if (response.status === 401 || response.status === 403) {
    return new JobExecutionError({
      classification: "provider_auth",
      code: `${area}.database_access_denied`,
      safeDetail: `The ${area} database denied the worker request.`,
    });
  }
  if (response.status === 409) {
    return new JobExecutionError({
      classification: "permanent",
      code: `${area}.database_state_conflict`,
      safeDetail: `The ${area} worker result conflicts with recorded state.`,
    });
  }
  if (response.status === 429 || response.status >= 500) {
    return new JobExecutionError({
      classification: "transient",
      code: `${area}.database_temporarily_unavailable`,
      safeDetail: `The ${area} database is temporarily unavailable.`,
    });
  }
  return new JobExecutionError({
    classification: "permanent",
    code: `${area}.database_request_rejected`,
    safeDetail: `The ${area} database rejected the validated worker request.`,
  });
}

export function m4Failure(
  area: "document" | "export",
  error: unknown,
): JobExecutionError {
  if (error instanceof JobExecutionError) return error;
  if (
    typeof error === "object" &&
    error !== null &&
    "name" in error &&
    ((error.name === "DocumentDomainError" &&
      "code" in error &&
      typeof error.code === "string" &&
      /^[a-z][a-z0-9_]{1,119}$/u.test(error.code)) ||
      (error.name === "ExportDefinitionError" &&
        "code" in error &&
        typeof error.code === "string" &&
        /^[A-Z][A-Z0-9_]{1,119}$/u.test(error.code))) &&
    "code" in error &&
    typeof error.code === "string"
  ) {
    return new JobExecutionError({
      classification: "validation",
      code: `${area}.${error.code.toLowerCase()}`,
      safeDetail: `The ${area} artifact failed deterministic domain validation.`,
    });
  }
  return new JobExecutionError({
    classification: "unknown",
    code: `${area}.worker_unhandled_failure`,
    safeDetail: `The ${area} worker failed without a safe classified error.`,
  });
}
