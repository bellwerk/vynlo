import type { M4DownloadGrantPort } from "@vynlo/application";
import { z } from "zod";

import { PostgrestCommandError } from "./postgrest-error";

const MAX_BYTES = 104_857_600;
const authorizationFields = {
  authorization_expires_at: z.iso.datetime({ offset: true }),
  authorization_id: z.string().uuid(),
  byte_size: z.number().int().min(1).max(MAX_BYTES),
  checksum_sha256: z.string().regex(/^[a-f0-9]{64}$/u),
  filename: z.string().trim().min(1).max(255),
  mime_type: z.string().trim().min(1).max(150),
  signed_url_ttl_seconds: z.number().int().min(30).max(300),
  storage_bucket: z.string().regex(/^[a-z0-9][a-z0-9_-]{2,62}$/u),
  storage_generation: z.string().min(1).max(200),
  storage_object_path: z.string().min(1).max(1_000),
  verification_receipt: z.record(z.string(), z.unknown()),
  workspace_id: z.string().uuid(),
} as const;
const documentAuthorizationRowSchema = z
  .object({
    ...authorizationFields,
    document_file_id: z.string().uuid(),
    document_id: z.string().uuid(),
  })
  .strict();
const exportAuthorizationRowSchema = z
  .object({
    ...authorizationFields,
    export_file_id: z.string().uuid(),
    export_run_id: z.string().uuid(),
  })
  .strict();

function safeOrigin(value: string): string {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new PostgrestCommandError("service_unavailable", 503);
  }
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
    (!/^\d+$/u.test(declared) || Number(declared) > MAX_BYTES)
  ) {
    throw new PostgrestCommandError("conflict", 409);
  }
  if (response.body === null) throw new PostgrestCommandError("conflict", 409);
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
      if (total > MAX_BYTES) throw new PostgrestCommandError("conflict", 409);
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

function contentTypeMatches(
  observed: string | null,
  expected: string,
): boolean {
  const base = (value: string | null) =>
    value?.split(";", 1)[0]?.trim().toLowerCase() ?? "";
  return base(observed) === base(expected);
}

/** M4-DOC-AC-010, M4-EXP-AC-004: verify immutable bytes before signing. */
export class SupabaseM4DownloadGrantPort implements M4DownloadGrantPort {
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
    input: Parameters<M4DownloadGrantPort["issue"]>[0],
  ): ReturnType<M4DownloadGrantPort["issue"]> {
    let loaded: Response;
    const loader =
      input.kind === "document"
        ? "m4_load_document_file_download_authorization"
        : "m4_load_export_download_authorization";
    try {
      loaded = await this.#fetch(`${this.#baseUrl}/rest/v1/rpc/${loader}`, {
        body: JSON.stringify({
          p_authorization_id: input.authorizationId,
        }),
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
      });
    } catch {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    if (!loaded.ok) {
      throw new PostgrestCommandError(
        loaded.status === 404 ? "conflict" : "service_unavailable",
        loaded.status === 404 ? 409 : 503,
      );
    }
    const value: unknown = await loaded.json().catch(() => null);
    const schema =
      input.kind === "document"
        ? documentAuthorizationRowSchema
        : exportAuthorizationRowSchema;
    const parsed = z.array(schema).length(1).safeParse(value);
    if (!parsed.success)
      throw new PostgrestCommandError("service_unavailable", 503);
    const row = parsed.data[0]!;
    const ownerId = "document_id" in row ? row.document_id : row.export_run_id;
    const fileId =
      "document_file_id" in row ? row.document_file_id : row.export_file_id;
    const expectedExpiry = Date.parse(input.authorizationExpiresAt);
    const observedExpiry = Date.parse(row.authorization_expires_at);
    if (
      row.authorization_id !== input.authorizationId ||
      row.workspace_id !== input.workspaceId ||
      ownerId !== input.ownerId ||
      fileId !== input.fileId ||
      row.filename !== input.filename ||
      row.mime_type !== input.mimeType ||
      row.byte_size !== input.byteSize ||
      row.checksum_sha256 !== input.checksumSha256 ||
      observedExpiry !== expectedExpiry ||
      observedExpiry <= this.#now()
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
    const observedGeneration =
      observed.headers.get("etag") ??
      observed.headers.get("x-supabase-version");
    if (
      bytes.byteLength !== row.byte_size ||
      (await sha256Hex(bytes)) !== row.checksum_sha256 ||
      !contentTypeMatches(
        observed.headers.get("content-type"),
        row.mime_type,
      ) ||
      observedGeneration !== row.storage_generation
    ) {
      throw new PostgrestCommandError("conflict", 409);
    }

    const remainingSeconds = Math.floor((observedExpiry - this.#now()) / 1_000);
    const expiresIn = Math.min(row.signed_url_ttl_seconds, remainingSeconds);
    if (expiresIn < 30) throw new PostgrestCommandError("conflict", 409);

    let signed: Response;
    try {
      signed = await this.#fetch(
        `${this.#baseUrl}/storage/v1/object/sign/${object}`,
        {
          body: JSON.stringify({ expiresIn }),
          headers: { ...this.#headers, "Content-Type": "application/json" },
          method: "POST",
          signal: AbortSignal.timeout(10_000),
        },
      );
    } catch {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    if (!signed.ok) throw new PostgrestCommandError("service_unavailable", 503);
    const signedValue: unknown = await signed.json().catch(() => null);
    const signedPath = z
      .object({ signedURL: z.string().min(1) })
      .passthrough()
      .safeParse(signedValue);
    if (!signedPath.success) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    const url = new URL(signedPath.data.signedURL, this.#baseUrl);
    if (url.origin !== new URL(this.#baseUrl).origin) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    return Object.freeze({
      expiresAt: new Date(this.#now() + expiresIn * 1_000).toISOString(),
      url: url.toString(),
    });
  }
}
