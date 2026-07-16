import type { M2MediaDownloadGrantPort } from "@vynlo/application";
import { z } from "zod";

import { PostgrestCommandError } from "./postgrest-error";

const MAX_DOWNLOAD_BYTES = 50_000_000;
const SHA256_PATTERN = /^[a-f0-9]{64}$/u;
const serviceRowSchema = z
  .object({
    authorization_expires_at: z.string().datetime({ offset: true }),
    authorization_id: z.string().uuid(),
    byte_size: z.number().int().min(1).max(MAX_DOWNLOAD_BYTES),
    checksum_sha256: z.string().regex(SHA256_PATTERN),
    media_file_id: z.string().uuid(),
    media_kind: z.enum([
      "attachment",
      "legal_document",
      "signed_document",
      "vehicle_photo",
    ]),
    mime_type: z.string().min(3).max(120),
    signed_url_ttl_seconds: z.number().int().min(30).max(300),
    storage_bucket: z.literal("media-private"),
    storage_generation: z.string().min(1).max(200).nullable(),
    storage_object_key: z.string().min(1).max(1_000),
    workspace_id: z.string().uuid(),
  })
  .strict();

function safeOrigin(value: string): string {
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
    throw new PostgrestCommandError("service_unavailable", 503);
  }
  return url.toString().replace(/\/$/u, "");
}

function encodedObject(bucket: string, objectKey: string): string {
  if (
    !/^[a-z0-9][a-z0-9_-]{2,62}$/u.test(bucket) ||
    objectKey.length < 1 ||
    objectKey.length > 1_000 ||
    objectKey
      .split("/")
      .some((segment) => segment === "" || segment === "." || segment === "..")
  ) {
    throw new PostgrestCommandError("service_unavailable", 503);
  }
  return `${encodeURIComponent(bucket)}/${objectKey
    .split("/")
    .map(encodeURIComponent)
    .join("/")}`;
}

async function boundedBytes(response: Response): Promise<Uint8Array> {
  const declared = response.headers.get("content-length");
  if (
    declared !== null &&
    /^\d+$/u.test(declared) &&
    Number(declared) > MAX_DOWNLOAD_BYTES
  ) {
    throw new PostgrestCommandError("conflict", 409);
  }
  if (response.body === null) {
    throw new PostgrestCommandError("conflict", 409);
  }
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let completed = false;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) {
        completed = true;
        break;
      }
      total += chunk.value.byteLength;
      if (total > MAX_DOWNLOAD_BYTES) {
        throw new PostgrestCommandError("conflict", 409);
      }
      chunks.push(new Uint8Array(chunk.value));
    }
  } finally {
    if (!completed) await reader.cancel().catch(() => undefined);
    reader.releaseLock();
  }
  if (total < 1) throw new PostgrestCommandError("conflict", 409);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array(bytes).buffer,
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export class SupabaseVerifiedMediaDownloadGrantPort implements M2MediaDownloadGrantPort {
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #headers: Readonly<Record<string, string>>;
  readonly #now: () => number;

  constructor(input: {
    readonly fetchImplementation?: typeof fetch;
    readonly now?: () => number;
    readonly serviceRoleKey: string;
    readonly supabaseUrl: string;
  }) {
    if (input.serviceRoleKey.trim().length < 20) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    this.#baseUrl = safeOrigin(input.supabaseUrl);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#headers = Object.freeze({
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
    });
    this.#now = input.now ?? Date.now;
  }

  async issue(
    input: Parameters<M2MediaDownloadGrantPort["issue"]>[0],
  ): ReturnType<M2MediaDownloadGrantPort["issue"]> {
    let loadedResponse: Response;
    try {
      loadedResponse = await this.#fetch(
        `${this.#baseUrl}/rest/v1/rpc/load_managed_media_download_authorization`,
        {
          body: JSON.stringify({ p_authorization_id: input.authorizationId }),
          cache: "no-store",
          headers: {
            ...this.#headers,
            Accept: "application/json",
            "Accept-Profile": "app",
            "Content-Profile": "app",
            "Content-Type": "application/json",
          },
          method: "POST",
          signal: AbortSignal.timeout(10_000),
        },
      );
    } catch {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    if (!loadedResponse.ok) {
      throw new PostgrestCommandError(
        loadedResponse.status === 404 ? "conflict" : "service_unavailable",
        loadedResponse.status === 404 ? 409 : 503,
      );
    }
    const loadedValue: unknown = await loadedResponse.json().catch(() => null);
    const loaded = z.array(serviceRowSchema).length(1).safeParse(loadedValue);
    if (!loaded.success) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    const row = loaded.data[0]!;
    const expectedAuthorizationExpiry = Date.parse(
      input.authorizationExpiresAt,
    );
    const observedAuthorizationExpiry = Date.parse(
      row.authorization_expires_at,
    );
    if (
      row.authorization_id !== input.authorizationId ||
      row.workspace_id !== input.workspaceId ||
      row.media_file_id !== input.mediaFileId ||
      row.media_kind !== input.mediaKind ||
      row.mime_type !== input.mimeType ||
      row.byte_size !== input.byteSize ||
      row.checksum_sha256 !== input.checksumSha256 ||
      row.signed_url_ttl_seconds !== input.expiresInSeconds ||
      observedAuthorizationExpiry !== expectedAuthorizationExpiry ||
      observedAuthorizationExpiry <= this.#now()
    ) {
      throw new PostgrestCommandError("conflict", 409);
    }

    const object = encodedObject(row.storage_bucket, row.storage_object_key);
    let observed: Response;
    try {
      observed = await this.#fetch(
        `${this.#baseUrl}/storage/v1/object/authenticated/${object}`,
        {
          cache: "no-store",
          headers: this.#headers,
          method: "GET",
          signal: AbortSignal.timeout(30_000),
        },
      );
    } catch {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    if (!observed.ok) {
      throw new PostgrestCommandError(
        observed.status === 404 ? "conflict" : "service_unavailable",
        observed.status === 404 ? 409 : 503,
      );
    }
    const bytes = await boundedBytes(observed);
    const observedMimeType =
      observed.headers.get("content-type")?.split(";", 1)[0] ?? "";
    const observedGeneration =
      observed.headers.get("etag") ??
      observed.headers.get("x-supabase-version");
    if (
      bytes.byteLength !== input.byteSize ||
      (await sha256Hex(bytes)) !== input.checksumSha256 ||
      observedMimeType !== input.mimeType ||
      (row.storage_generation !== null &&
        observedGeneration !== row.storage_generation)
    ) {
      throw new PostgrestCommandError("conflict", 409);
    }

    const remainingSeconds = Math.floor(
      (observedAuthorizationExpiry - this.#now()) / 1_000,
    );
    const effectiveTtlSeconds = Math.min(
      row.signed_url_ttl_seconds,
      remainingSeconds,
    );
    if (effectiveTtlSeconds < 30) {
      throw new PostgrestCommandError("conflict", 409);
    }

    let signed: Response;
    try {
      signed = await this.#fetch(
        `${this.#baseUrl}/storage/v1/object/sign/${object}`,
        {
          body: JSON.stringify({ expiresIn: effectiveTtlSeconds }),
          headers: { ...this.#headers, "Content-Type": "application/json" },
          method: "POST",
          signal: AbortSignal.timeout(10_000),
        },
      );
    } catch {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    if (!signed.ok) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    const value: unknown = await signed.json().catch(() => null);
    const record =
      typeof value === "object" && value !== null && !Array.isArray(value)
        ? (value as Record<string, unknown>)
        : null;
    const candidate = record?.signedURL ?? record?.signedUrl ?? record?.url;
    if (typeof candidate !== "string") {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    const url = new URL(candidate, this.#baseUrl);
    if (url.origin !== new URL(this.#baseUrl).origin) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    return Object.freeze({
      expiresAt: new Date(
        this.#now() + effectiveTtlSeconds * 1_000,
      ).toISOString(),
      url: url.toString(),
    });
  }
}
