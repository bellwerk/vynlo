import {
  type ManagedObjectDownloadGrant,
  type ManagedObjectIdentity,
  type ManagedObjectMetadata,
  type ManagedObjectStorage,
  type ManagedObjectUploadGrant,
  type MediaBinarySource,
  type LegalOriginalObjectRead,
  type LegalOriginalObjectStorage,
} from "@vynlo/media";
import { JobExecutionError } from "./job-runner";

const SHA256_PATTERN = /^[a-f0-9]{64}$/u;
const BUCKET_PATTERN = /^[a-z0-9][a-z0-9_-]{2,62}$/u;
const MAX_MEDIA_BYTES = 50_000_000;

interface InspectedManagedObject {
  readonly generation: string | null;
  readonly metadata: ManagedObjectMetadata;
}

export async function mediaSha256Hex(value: Uint8Array): Promise<string> {
  const bytes = new Uint8Array(value);
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function storageError(
  code: string,
  detail: string,
  classification: "permanent" | "provider_auth" | "transient" = "permanent",
): JobExecutionError {
  return new JobExecutionError({ classification, code, safeDetail: detail });
}

function validateBaseUrl(value: string): string {
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
    throw new TypeError("Supabase media storage URL must be a safe origin.");
  }
  return url.toString().replace(/\/$/u, "");
}

function encodedObject(object: ManagedObjectIdentity): string {
  if (!BUCKET_PATTERN.test(object.bucket)) {
    throw new TypeError("Invalid managed media bucket.");
  }
  if (
    object.objectKey.length < 1 ||
    object.objectKey.length > 1_000 ||
    object.objectKey.startsWith("/") ||
    object.objectKey.endsWith("/") ||
    object.objectKey
      .split("/")
      .some((segment) => segment === "" || segment === "." || segment === "..")
  ) {
    throw new TypeError("Invalid managed media object key.");
  }
  return `${encodeURIComponent(object.bucket)}/${object.objectKey
    .split("/")
    .map(encodeURIComponent)
    .join("/")}`;
}

export async function materializeMediaSource(
  source: MediaBinarySource,
  maximumBytes = MAX_MEDIA_BYTES,
): Promise<Uint8Array> {
  if (source instanceof Uint8Array) {
    if (source.byteLength < 1 || source.byteLength > maximumBytes) {
      throw storageError(
        "media.storage_invalid_body",
        "Managed media storage received an invalid bounded object body.",
      );
    }
    return new Uint8Array(source);
  }
  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  for await (const chunk of source) {
    byteLength += chunk.byteLength;
    if (byteLength > maximumBytes) {
      throw storageError(
        "media.storage_invalid_body",
        "Managed media storage received an invalid bounded object body.",
      );
    }
    chunks.push(new Uint8Array(chunk));
  }
  if (byteLength < 1) {
    throw storageError(
      "media.storage_invalid_body",
      "Managed media storage received an invalid bounded object body.",
    );
  }
  const bytes = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function responseError(response: Response): JobExecutionError {
  if (response.status === 401 || response.status === 403) {
    return storageError(
      "media.storage_access_denied",
      "Private managed media storage denied the server request.",
      "provider_auth",
    );
  }
  if (response.status === 429 || response.status >= 500) {
    return storageError(
      "media.storage_temporarily_unavailable",
      "Private managed media storage is temporarily unavailable.",
      "transient",
    );
  }
  return storageError(
    "media.storage_request_rejected",
    "Private managed media storage rejected the validated request.",
  );
}

async function* responseBodySource(
  response: Response,
): AsyncIterable<Uint8Array> {
  if (response.body === null) {
    throw storageError(
      "media.storage_invalid_object",
      "Private managed media storage returned an empty object stream.",
    );
  }
  const reader = response.body.getReader();
  let completed = false;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) {
        completed = true;
        return;
      }
      yield new Uint8Array(chunk.value);
    }
  } finally {
    if (!completed) {
      await reader.cancel().catch(() => undefined);
    }
    reader.releaseLock();
  }
}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw storageError(
      "media.storage_invalid_response",
      "Private managed media storage returned an invalid response.",
    );
  }
  return value as Record<string, unknown>;
}

function absoluteGrantUrl(baseUrl: string, value: unknown): string {
  if (typeof value !== "string" || value.length < 1) {
    throw storageError(
      "media.storage_invalid_response",
      "Private managed media storage returned an invalid grant.",
    );
  }
  const url = new URL(value, baseUrl);
  const base = new URL(baseUrl);
  if (url.origin !== base.origin || url.protocol !== base.protocol) {
    throw storageError(
      "media.storage_invalid_response",
      "Private managed media storage returned an invalid grant.",
    );
  }
  return url.toString();
}

/** Private exact-key Supabase Storage adapter; it never lists a bucket. */
export class SupabaseManagedMediaStorage
  implements ManagedObjectStorage, LegalOriginalObjectStorage
{
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #headers: Readonly<Record<string, string>>;

  constructor(input: {
    readonly fetchImplementation?: typeof fetch;
    readonly serviceRoleKey: string;
    readonly supabaseUrl: string;
  }) {
    if (input.serviceRoleKey.trim().length < 20) {
      throw new TypeError("A server-only service role key is required.");
    }
    this.#baseUrl = validateBaseUrl(input.supabaseUrl);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#headers = Object.freeze({
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
    });
  }

  async createUploadGrant(input: {
    readonly object: ManagedObjectIdentity;
    readonly expectedByteSize: number;
    readonly expectedMimeType: string;
    readonly expectedChecksumSha256: string;
    readonly expiresInSeconds: number;
    readonly signal?: AbortSignal;
  }): Promise<ManagedObjectUploadGrant> {
    if (
      !Number.isSafeInteger(input.expectedByteSize) ||
      input.expectedByteSize < 1 ||
      input.expectedByteSize > MAX_MEDIA_BYTES ||
      input.expectedMimeType.length < 3 ||
      !SHA256_PATTERN.test(input.expectedChecksumSha256) ||
      !Number.isInteger(input.expiresInSeconds) ||
      input.expiresInSeconds < 60 ||
      input.expiresInSeconds > 900
    ) {
      throw new TypeError("Invalid managed media upload grant request.");
    }
    const response = await this.#request(
      `/storage/v1/object/upload/sign/${encodedObject(input.object)}`,
      {
        body: JSON.stringify({}),
        headers: { ...this.#headers, "Content-Type": "application/json" },
        method: "POST",
        ...(input.signal === undefined ? {} : { signal: input.signal }),
      },
    );
    const body = record(await response.json());
    return Object.freeze({
      ...input.object,
      expiresAt: new Date(
        Date.now() + input.expiresInSeconds * 1_000,
      ).toISOString(),
      requiredHeaders: Object.freeze({
        "Content-Type": input.expectedMimeType,
        "x-upsert": "false",
      }),
      url: absoluteGrantUrl(
        this.#baseUrl,
        body.url ?? body.signedURL ?? body.signedUrl,
      ),
    });
  }

  async createDownloadGrant(input: {
    readonly object: ManagedObjectIdentity;
    readonly expectedByteSize: number;
    readonly expectedChecksumSha256: string;
    readonly expectedGeneration: string | null;
    readonly expectedMimeType: string;
    readonly expiresInSeconds: number;
    readonly signal?: AbortSignal;
  }): Promise<ManagedObjectDownloadGrant> {
    if (
      !Number.isInteger(input.expiresInSeconds) ||
      input.expiresInSeconds < 30 ||
      input.expiresInSeconds > 900 ||
      !Number.isSafeInteger(input.expectedByteSize) ||
      input.expectedByteSize < 1 ||
      input.expectedByteSize > MAX_MEDIA_BYTES ||
      !SHA256_PATTERN.test(input.expectedChecksumSha256) ||
      input.expectedMimeType.length < 3 ||
      (input.expectedGeneration !== null &&
        (input.expectedGeneration.trim().length < 1 ||
          input.expectedGeneration.length > 200))
    ) {
      throw new TypeError("Invalid managed media download grant request.");
    }
    const observed = await this.#inspectObject(input.object, input.signal);
    if (
      observed === null ||
      observed.metadata.byteSize !== input.expectedByteSize ||
      observed.metadata.checksumSha256 !== input.expectedChecksumSha256 ||
      observed.metadata.mimeType !== input.expectedMimeType ||
      (input.expectedGeneration !== null &&
        observed.generation !== input.expectedGeneration)
    ) {
      throw storageError(
        "media.storage_provider_drift",
        "Private managed media storage differs from immutable provenance.",
      );
    }
    const response = await this.#request(
      `/storage/v1/object/sign/${encodedObject(input.object)}`,
      {
        body: JSON.stringify({ expiresIn: input.expiresInSeconds }),
        headers: { ...this.#headers, "Content-Type": "application/json" },
        method: "POST",
        ...(input.signal === undefined ? {} : { signal: input.signal }),
      },
    );
    const body = record(await response.json());
    return Object.freeze({
      ...input.object,
      expiresAt: new Date(
        Date.now() + input.expiresInSeconds * 1_000,
      ).toISOString(),
      url: absoluteGrantUrl(
        this.#baseUrl,
        body.signedURL ?? body.signedUrl ?? body.url,
      ),
    });
  }

  async head(input: {
    readonly object: ManagedObjectIdentity;
    readonly signal?: AbortSignal;
  }): Promise<ManagedObjectMetadata | null> {
    return (
      (await this.#inspectObject(input.object, input.signal))?.metadata ?? null
    );
  }

  async #inspectObject(
    object: ManagedObjectIdentity,
    signal?: AbortSignal,
  ): Promise<InspectedManagedObject | null> {
    const response = await this.#fetch(
      `${this.#baseUrl}/storage/v1/object/authenticated/${encodedObject(object)}`,
      {
        headers: this.#headers,
        method: "GET",
        ...(signal === undefined ? {} : { signal }),
      },
    );
    if (response.status === 404) return null;
    if (!response.ok) throw responseError(response);
    const bytes = await materializeMediaSource(
      responseBodySource(response),
      MAX_MEDIA_BYTES,
    );
    return Object.freeze({
      generation:
        response.headers.get("etag") ??
        response.headers.get("x-supabase-version"),
      metadata: Object.freeze({
        ...object,
        byteSize: bytes.byteLength,
        checksumSha256: await mediaSha256Hex(bytes),
        mimeType:
          response.headers.get("content-type")?.split(";", 1)[0] ??
          "application/octet-stream",
      }),
    });
  }

  async read(input: {
    readonly object: ManagedObjectIdentity;
    readonly signal?: AbortSignal;
  }): Promise<MediaBinarySource> {
    const response = await this.#request(
      `/storage/v1/object/authenticated/${encodedObject(input.object)}`,
      {
        headers: this.#headers,
        method: "GET",
        ...(input.signal === undefined ? {} : { signal: input.signal }),
      },
    );
    const contentLength = response.headers.get("content-length");
    if (
      contentLength !== null &&
      /^\d+$/u.test(contentLength) &&
      Number(contentLength) > MAX_MEDIA_BYTES
    ) {
      throw storageError(
        "media.storage_invalid_object",
        "Private managed media storage returned an invalid bounded object.",
      );
    }
    return responseBodySource(response);
  }

  async readLegalOriginal(input: {
    readonly object: ManagedObjectIdentity;
    readonly signal?: AbortSignal;
  }): Promise<LegalOriginalObjectRead> {
    const response = await this.#request(
      `/storage/v1/object/authenticated/${encodedObject(input.object)}`,
      {
        headers: this.#headers,
        method: "GET",
        ...(input.signal === undefined ? {} : { signal: input.signal }),
      },
    );
    const contentLength = response.headers.get("content-length");
    if (
      contentLength !== null &&
      (!/^\d+$/u.test(contentLength) || Number(contentLength) > MAX_MEDIA_BYTES)
    ) {
      throw storageError(
        "media.storage_invalid_object",
        "Private managed media storage returned an invalid bounded object.",
      );
    }
    const generation = (
      response.headers.get("etag") ??
      response.headers.get("x-supabase-version") ??
      ""
    ).trim();
    const providerMimeType =
      response.headers
        .get("content-type")
        ?.split(";", 1)[0]
        ?.trim()
        .toLowerCase() ?? "";
    if (
      generation.length < 1 ||
      generation.length > 200 ||
      providerMimeType.length < 3 ||
      providerMimeType.length > 200
    ) {
      throw storageError(
        "media.storage_invalid_object_provenance",
        "Private managed media storage omitted immutable object provenance.",
      );
    }
    return Object.freeze({
      generation,
      providerMimeType,
      source: responseBodySource(response),
    });
  }

  async putIfAbsent(input: {
    readonly object: ManagedObjectIdentity;
    readonly body: MediaBinarySource;
    readonly byteSize: number;
    readonly mimeType: string;
    readonly checksumSha256: string;
    readonly signal?: AbortSignal;
  }): Promise<ManagedObjectMetadata> {
    const bytes = await materializeMediaSource(input.body);
    if (
      bytes.byteLength !== input.byteSize ||
      !SHA256_PATTERN.test(input.checksumSha256) ||
      (await mediaSha256Hex(bytes)) !== input.checksumSha256 ||
      input.mimeType.length < 3
    ) {
      throw storageError(
        "media.storage_receipt_mismatch",
        "Managed media bytes differ from their validated storage receipt.",
      );
    }
    const response = await this.#fetch(
      `${this.#baseUrl}/storage/v1/object/${encodedObject(input.object)}`,
      {
        body: bytes.buffer.slice(
          bytes.byteOffset,
          bytes.byteOffset + bytes.byteLength,
        ) as ArrayBuffer,
        headers: {
          ...this.#headers,
          "Cache-Control": "private, no-store",
          "Content-Type": input.mimeType,
          "x-upsert": "false",
        },
        method: "POST",
        ...(input.signal === undefined ? {} : { signal: input.signal }),
      },
    );
    if (!response.ok && ![400, 409].includes(response.status)) {
      throw responseError(response);
    }
    if ([400, 409].includes(response.status)) {
      const existing = await this.head({
        object: input.object,
        ...(input.signal === undefined ? {} : { signal: input.signal }),
      });
      if (
        existing === null ||
        existing.byteSize !== input.byteSize ||
        existing.checksumSha256 !== input.checksumSha256 ||
        existing.mimeType !== input.mimeType
      ) {
        throw storageError(
          "media.storage_deterministic_path_conflict",
          "The deterministic managed media path contains different bytes.",
        );
      }
    }
    return Object.freeze({
      ...input.object,
      byteSize: input.byteSize,
      checksumSha256: input.checksumSha256,
      mimeType: input.mimeType,
    });
  }

  async delete(input: {
    readonly object: ManagedObjectIdentity;
    readonly ifChecksumSha256: string;
    readonly signal?: AbortSignal;
  }): Promise<"deleted" | "not_found" | "precondition_failed"> {
    if (!SHA256_PATTERN.test(input.ifChecksumSha256)) {
      throw new TypeError("Invalid conditional managed media checksum.");
    }
    encodedObject(input.object);
    throw storageError(
      "media.storage_atomic_delete_unsupported",
      "Supabase Storage does not expose a proven atomic checksum-preconditioned delete; automated deletion is disabled.",
    );
  }

  async #request(path: string, init: RequestInit): Promise<Response> {
    let response: Response;
    try {
      response = await this.#fetch(`${this.#baseUrl}${path}`, init);
    } catch {
      throw storageError(
        "media.storage_transport_failed",
        "Private managed media storage request did not complete.",
        "transient",
      );
    }
    if (!response.ok) throw responseError(response);
    return response;
  }
}
