import { MediaPolicyError, type MediaPolicyErrorCode } from "./errors";

export const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu;
export const SHA256_PATTERN = /^[a-f0-9]{64}$/u;

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function hasExactKeys(
  value: Record<string, unknown>,
  expectedKeys: readonly string[],
): boolean {
  const actualKeys = Object.keys(value).sort();
  const normalizedExpected = [...expectedKeys].sort();
  return (
    actualKeys.length === normalizedExpected.length &&
    actualKeys.every((key, index) => key === normalizedExpected[index])
  );
}

export function requireUuid(
  value: unknown,
  code: MediaPolicyErrorCode,
): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new MediaPolicyError(code);
  }
  return value.toLowerCase();
}

export function requireSha256(
  value: unknown,
  code: MediaPolicyErrorCode,
): string {
  if (typeof value !== "string") {
    throw new MediaPolicyError(code);
  }
  const normalized = value.toLowerCase();
  if (!SHA256_PATTERN.test(normalized)) {
    throw new MediaPolicyError(code);
  }
  return normalized;
}

export function requirePositiveSafeInteger(
  value: unknown,
  code: MediaPolicyErrorCode,
): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1) {
    throw new MediaPolicyError(code);
  }
  return value as number;
}

export function deepFreeze<T>(value: T): Readonly<T> {
  if (typeof value !== "object" || value === null || Object.isFrozen(value)) {
    return value;
  }

  for (const child of Object.values(value)) {
    deepFreeze(child);
  }
  return Object.freeze(value);
}

export async function sha256Hex(value: string | Uint8Array): Promise<string> {
  const suppliedBytes =
    typeof value === "string" ? new TextEncoder().encode(value) : value;
  const bytes = new Uint8Array(suppliedBytes.byteLength);
  bytes.set(suppliedBytes);
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
