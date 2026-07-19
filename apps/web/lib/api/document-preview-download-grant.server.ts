import { type DocumentPreviewDownloadGrantPort } from "@vynlo/application";
import { z } from "zod";

import { PostgrestCommandError } from "./postgrest-error";

const MAX_PREVIEW_BYTES = 10_000_000;
const serviceRowSchema = z
  .object({
    artifact_id: z.string().uuid(),
    authorization_expires_at: z.string().datetime({ offset: true }),
    authorization_id: z.string().uuid(),
    byte_size: z.number().int().min(1).max(MAX_PREVIEW_BYTES),
    checksum_sha256: z.string().regex(/^[a-f0-9]{64}$/u),
    document_id: z.string().uuid(),
    filename: z.literal("preview.html"),
    mime_type: z.literal("text/html; charset=utf-8"),
    signed_url_ttl_seconds: z.number().int().min(30).max(300),
    storage_bucket: z.string().regex(/^[a-z0-9][a-z0-9_-]{2,62}$/u),
    storage_object_path: z.string().min(1).max(1_000),
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

function encodedObject(bucket: string, objectPath: string): string {
  if (
    !/^[a-z0-9][a-z0-9_-]{2,62}$/u.test(bucket) ||
    objectPath.length < 1 ||
    objectPath.length > 1_000 ||
    objectPath
      .split("/")
      .some((segment) => segment === "" || segment === "." || segment === "..")
  ) {
    throw new PostgrestCommandError("service_unavailable", 503);
  }
  return `${encodeURIComponent(bucket)}/${objectPath
    .split("/")
    .map(encodeURIComponent)
    .join("/")}`;
}

async function boundedBytes(response: Response): Promise<Uint8Array> {
  const declared = response.headers.get("content-length");
  if (
    declared !== null &&
    /^\d+$/u.test(declared) &&
    Number(declared) > MAX_PREVIEW_BYTES
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
      const next = await reader.read();
      if (next.done) {
        completed = true;
        break;
      }
      total += next.value.byteLength;
      if (total > MAX_PREVIEW_BYTES) {
        throw new PostgrestCommandError("conflict", 409);
      }
      chunks.push(new Uint8Array(next.value));
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

function mimeBase(value: string | null): string {
  return value?.split(";", 1)[0]?.trim().toLowerCase() ?? "";
}

export class SupabaseDocumentPreviewDownloadGrantPort implements DocumentPreviewDownloadGrantPort {
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
    input: Parameters<DocumentPreviewDownloadGrantPort["issue"]>[0],
  ): ReturnType<DocumentPreviewDownloadGrantPort["issue"]> {
    let loadedResponse: Response;
    try {
      loadedResponse = await this.#fetch(
        `${this.#baseUrl}/rest/v1/rpc/load_document_preview_download_authorization`,
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
      row.artifact_id !== input.artifactId ||
      row.document_id !== input.documentId ||
      row.filename !== input.filename ||
      row.mime_type !== input.mimeType ||
      row.byte_size !== input.byteSize ||
      row.checksum_sha256 !== input.checksumSha256 ||
      row.signed_url_ttl_seconds !== input.expiresInSeconds ||
      observedAuthorizationExpiry !== expectedAuthorizationExpiry ||
      observedAuthorizationExpiry <= this.#now()
    ) {
      throw new PostgrestCommandError("conflict", 409);
    }

    const object = encodedObject(row.storage_bucket, row.storage_object_path);
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
    if (
      bytes.byteLength !== row.byte_size ||
      (await sha256Hex(bytes)) !== row.checksum_sha256 ||
      mimeBase(observed.headers.get("content-type")) !== "text/html"
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
    const signedValue: unknown = await signed.json().catch(() => null);
    const signedRecord =
      typeof signedValue === "object" &&
      signedValue !== null &&
      !Array.isArray(signedValue)
        ? (signedValue as Record<string, unknown>)
        : null;
    const candidate =
      signedRecord?.signedURL ?? signedRecord?.signedUrl ?? signedRecord?.url;
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
