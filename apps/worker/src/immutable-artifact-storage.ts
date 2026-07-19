import { createHash } from "node:crypto";

import { JobExecutionError } from "./job-runner";
import {
  CHECKSUM_PATTERN,
  validatedSupabaseOrigin,
} from "./m4-worker-validation";

const BUCKET_PATTERN = /^[a-z0-9][a-z0-9_-]{2,62}$/u;

export interface ImmutableArtifactWrite {
  readonly body: Uint8Array;
  readonly checksum: string;
  readonly contentType: string;
  readonly objectPath: string;
  readonly signal: AbortSignal;
}

export interface StoredImmutableArtifact {
  readonly bucket: string;
  readonly byteSize: number;
  readonly checksum: string;
  readonly contentType: string;
  readonly generation: string;
  readonly objectPath: string;
}

export interface ImmutableArtifactStorage {
  put(write: ImmutableArtifactWrite): Promise<StoredImmutableArtifact>;
}

export function artifactSha256Hex(value: Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

function encodedObjectPath(value: string): string {
  if (
    value.length < 1 ||
    value.length > 1_000 ||
    value.startsWith("/") ||
    value.endsWith("/") ||
    value.includes("\\") ||
    value
      .split("/")
      .some((segment) => segment === "" || segment === "." || segment === "..")
  ) {
    throw new TypeError("Invalid immutable artifact object path.");
  }
  return value.split("/").map(encodeURIComponent).join("/");
}

function storageFailure(response: Response): JobExecutionError {
  if (response.status === 401 || response.status === 403) {
    return new JobExecutionError({
      classification: "provider_auth",
      code: "artifact.storage_access_denied",
      safeDetail: "Private artifact storage denied the worker request.",
    });
  }
  if (response.status === 429 || response.status >= 500) {
    return new JobExecutionError({
      classification: "transient",
      code: "artifact.storage_temporarily_unavailable",
      safeDetail: "Private artifact storage is temporarily unavailable.",
    });
  }
  return new JobExecutionError({
    classification: "permanent",
    code: "artifact.storage_request_rejected",
    safeDetail: "Private artifact storage rejected the validated request.",
  });
}

/** Exact-key, create-only storage with byte-for-byte replay verification. */
export class SupabaseImmutableArtifactStorage implements ImmutableArtifactStorage {
  readonly #baseUrl: string;
  readonly #bucket: string;
  readonly #contentTypes: ReadonlySet<string>;
  readonly #fetch: typeof fetch;
  readonly #headers: Readonly<Record<string, string>>;
  readonly #maximumBytes: number;

  constructor(input: {
    readonly allowedContentTypes: readonly string[];
    readonly bucket: string;
    readonly fetchImplementation?: typeof fetch;
    readonly maximumBytes: number;
    readonly serviceRoleKey: string;
    readonly supabaseUrl: string;
  }) {
    if (!BUCKET_PATTERN.test(input.bucket)) {
      throw new TypeError("Invalid immutable artifact bucket name.");
    }
    if (
      !Number.isSafeInteger(input.maximumBytes) ||
      input.maximumBytes < 1 ||
      input.maximumBytes > 104_857_600
    ) {
      throw new RangeError("Invalid immutable artifact byte limit.");
    }
    if (
      input.allowedContentTypes.length < 1 ||
      new Set(input.allowedContentTypes).size !==
        input.allowedContentTypes.length
    ) {
      throw new TypeError("Artifact content types must be a non-empty set.");
    }
    if (input.serviceRoleKey.trim().length < 20) {
      throw new TypeError("A server-only service role key is required.");
    }
    this.#baseUrl = validatedSupabaseOrigin(input.supabaseUrl);
    this.#bucket = input.bucket;
    this.#contentTypes = new Set(input.allowedContentTypes);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#headers = Object.freeze({
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
    });
    this.#maximumBytes = input.maximumBytes;
  }

  async put(write: ImmutableArtifactWrite): Promise<StoredImmutableArtifact> {
    if (
      write.body.byteLength < 1 ||
      write.body.byteLength > this.#maximumBytes ||
      !CHECKSUM_PATTERN.test(write.checksum) ||
      artifactSha256Hex(write.body) !== write.checksum ||
      !this.#contentTypes.has(write.contentType)
    ) {
      throw new JobExecutionError({
        classification: "validation",
        code: "artifact.storage_receipt_mismatch",
        safeDetail: "Artifact bytes differ from their bounded storage receipt.",
      });
    }
    const objectPath = encodedObjectPath(write.objectPath);
    const encodedBucket = encodeURIComponent(this.#bucket);
    let upload: Response;
    try {
      upload = await this.#fetch(
        `${this.#baseUrl}/storage/v1/object/${encodedBucket}/${objectPath}`,
        {
          body: new Uint8Array(write.body),
          headers: {
            ...this.#headers,
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
        code: "artifact.storage_transport_failed",
        safeDetail: "Private artifact storage did not complete the write.",
      });
    }
    if (!upload.ok && ![400, 409].includes(upload.status)) {
      throw storageFailure(upload);
    }

    let observed: Response;
    try {
      observed = await this.#fetch(
        `${this.#baseUrl}/storage/v1/object/authenticated/${encodedBucket}/${objectPath}`,
        {
          headers: this.#headers,
          method: "GET",
          signal: write.signal,
        },
      );
    } catch {
      throw new JobExecutionError({
        classification: "transient",
        code: "artifact.storage_verification_failed",
        safeDetail: "The immutable private artifact could not be verified.",
      });
    }
    if (!observed.ok) throw storageFailure(observed);
    const bytes = new Uint8Array(await observed.arrayBuffer());
    const generation = (
      observed.headers.get("etag") ??
      observed.headers.get("x-supabase-version") ??
      ""
    ).trim();
    const contentType = (observed.headers.get("content-type") ?? "")
      .trim()
      .toLowerCase();
    if (
      bytes.byteLength !== write.body.byteLength ||
      artifactSha256Hex(bytes) !== write.checksum ||
      contentType !== write.contentType.toLowerCase() ||
      generation.length < 1 ||
      generation.length > 200
    ) {
      throw new JobExecutionError({
        classification: "permanent",
        code: "artifact.storage_deterministic_path_conflict",
        safeDetail:
          "The deterministic private artifact path has different provenance.",
      });
    }
    return Object.freeze({
      bucket: this.#bucket,
      byteSize: bytes.byteLength,
      checksum: write.checksum,
      contentType: write.contentType,
      generation,
      objectPath: write.objectPath,
    });
  }
}
