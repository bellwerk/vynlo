import { JobExecutionError } from "./job-runner";
import { sha256Hex } from "./preview-renderer";

export interface PrivateArtifactWrite {
  readonly body: Uint8Array;
  readonly checksum: string;
  readonly contentType: string;
  readonly objectPath: string;
  readonly signal: AbortSignal;
}

export interface StoredPrivateArtifact {
  readonly bucket: string;
  readonly byteSize: number;
  readonly checksum: string;
  readonly objectPath: string;
}

export interface PrivateArtifactStorage {
  put(write: PrivateArtifactWrite): Promise<StoredPrivateArtifact>;
}

function validatedBaseUrl(value: string): string {
  const url = new URL(value);
  const isLocal = ["127.0.0.1", "localhost", "::1"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && isLocal)) {
    throw new TypeError(
      "Supabase URL must use HTTPS except for local development.",
    );
  }
  return url.toString().replace(/\/$/u, "");
}

function encodedPath(value: string): string {
  if (
    value.length === 0 ||
    value.length > 1_000 ||
    value.startsWith("/") ||
    value.endsWith("/") ||
    value
      .split("/")
      .some((segment) => segment === "" || segment === "." || segment === "..")
  ) {
    throw new TypeError("Invalid private artifact object path.");
  }
  return value.split("/").map(encodeURIComponent).join("/");
}

function storageFailure(response: Response): JobExecutionError {
  const retryAfterHeader = response.headers.get("retry-after");
  const parsedRetryAfter =
    retryAfterHeader === null ? Number.NaN : Number(retryAfterHeader);
  const retryAfterSeconds =
    Number.isInteger(parsedRetryAfter) &&
    parsedRetryAfter >= 1 &&
    parsedRetryAfter <= 86_400
      ? parsedRetryAfter
      : undefined;

  if (response.status === 401 || response.status === 403) {
    return new JobExecutionError({
      classification: "provider_auth",
      code: "storage.access_denied",
      safeDetail: "Private artifact storage denied the worker request.",
    });
  }
  if (response.status === 429 || response.status >= 500) {
    return new JobExecutionError({
      classification: "transient",
      code: "storage.temporarily_unavailable",
      retryAfterSeconds,
      safeDetail: "Private artifact storage is temporarily unavailable.",
    });
  }
  return new JobExecutionError({
    classification: "permanent",
    code: "storage.write_rejected",
    safeDetail: "Private artifact storage rejected the validated artifact.",
  });
}

export class SupabasePrivateArtifactStorage implements PrivateArtifactStorage {
  readonly #baseUrl: string;
  readonly #bucket: string;
  readonly #fetch: typeof fetch;
  readonly #serviceRoleKey: string;

  constructor(input: {
    readonly bucket: string;
    readonly fetchImplementation?: typeof fetch;
    readonly serviceRoleKey: string;
    readonly supabaseUrl: string;
  }) {
    if (!/^[a-z0-9][a-z0-9_-]{2,62}$/u.test(input.bucket)) {
      throw new TypeError("Invalid private artifact bucket name.");
    }
    if (input.serviceRoleKey.trim().length < 20) {
      throw new TypeError("A server-only service role key is required.");
    }
    this.#baseUrl = validatedBaseUrl(input.supabaseUrl);
    this.#bucket = input.bucket;
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#serviceRoleKey = input.serviceRoleKey;
  }

  async put(write: PrivateArtifactWrite): Promise<StoredPrivateArtifact> {
    if (
      !/^[a-f0-9]{64}$/u.test(write.checksum) ||
      sha256Hex(write.body) !== write.checksum ||
      write.body.byteLength < 1 ||
      write.body.byteLength > 10_000_000 ||
      write.contentType !== "text/html; charset=utf-8"
    ) {
      throw new JobExecutionError({
        classification: "validation",
        code: "storage.invalid_preview_artifact",
        safeDetail: "The rendered preview artifact failed storage validation.",
      });
    }

    const objectPath = encodedPath(write.objectPath);
    const uploadBody = new Uint8Array(write.body.byteLength);
    uploadBody.set(write.body);
    const commonHeaders = {
      apikey: this.#serviceRoleKey,
      Authorization: `Bearer ${this.#serviceRoleKey}`,
    } as const;
    let response: Response;
    try {
      response = await this.#fetch(
        `${this.#baseUrl}/storage/v1/object/${encodeURIComponent(this.#bucket)}/${objectPath}`,
        {
          body: uploadBody,
          headers: {
            ...commonHeaders,
            "Cache-Control": "private, no-store",
            "Content-Type": write.contentType,
            "x-upsert": "false",
          },
          method: "POST",
          signal: write.signal,
        },
      );
    } catch {
      throw new JobExecutionError({
        classification: "transient",
        code: "storage.transport_failed",
        safeDetail: "The private artifact storage request did not complete.",
      });
    }

    if (!response.ok && ![400, 409].includes(response.status)) {
      throw storageFailure(response);
    }

    if ([400, 409].includes(response.status)) {
      let existing: Response;
      try {
        existing = await this.#fetch(
          `${this.#baseUrl}/storage/v1/object/authenticated/${encodeURIComponent(this.#bucket)}/${objectPath}`,
          {
            headers: commonHeaders,
            method: "GET",
            signal: write.signal,
          },
        );
      } catch {
        throw new JobExecutionError({
          classification: "transient",
          code: "storage.replay_verification_failed",
          safeDetail: "The existing private artifact could not be verified.",
        });
      }
      if (!existing.ok && existing.status === 404) {
        throw storageFailure(response);
      }
      if (!existing.ok) {
        throw storageFailure(existing);
      }
      const existingBody = new Uint8Array(await existing.arrayBuffer());
      if (
        existingBody.byteLength !== write.body.byteLength ||
        sha256Hex(existingBody) !== write.checksum
      ) {
        throw new JobExecutionError({
          classification: "permanent",
          code: "storage.deterministic_path_conflict",
          safeDetail:
            "The deterministic preview path contains different bytes.",
        });
      }
    }

    return {
      bucket: this.#bucket,
      byteSize: write.body.byteLength,
      checksum: write.checksum,
      objectPath: write.objectPath,
    };
  }
}
