import type { JobErrorClassification } from "@vynlo/jobs";

export interface ClaimedJob {
  readonly attemptNumber: number;
  readonly causationId: string | null;
  readonly correlationId: string;
  readonly entityId: string | null;
  readonly entityType: string;
  readonly idempotencyKey: string;
  readonly jobId: string;
  readonly jobType: string;
  readonly leaseExpiresAt: string;
  readonly leaseToken: string;
  readonly maximumAttempts: number;
  readonly outboxEventId: string;
  readonly payload: Readonly<Record<string, unknown>>;
  readonly payloadSchemaVersion: number;
  readonly workspaceId: string;
}

export interface ClaimJobsInput {
  readonly jobTypes?: readonly string[];
  readonly leaseSeconds: number;
  readonly limit: number;
  readonly workerId: string;
}

export interface CompleteJobInput {
  readonly jobId: string;
  readonly leaseToken: string;
  readonly providerRequestId?: string | undefined;
  readonly resultSummary: Readonly<Record<string, unknown>>;
  readonly workerId: string;
}

export interface FailJobInput {
  readonly classification: Exclude<JobErrorClassification, "lease_expired">;
  readonly errorCode: string;
  readonly errorDetailSafe: string;
  readonly jobId: string;
  readonly leaseToken: string;
  readonly providerRequestId?: string | undefined;
  readonly retryAfterSeconds?: number | undefined;
  readonly workerId: string;
}

export interface HeartbeatJobInput {
  readonly extendSeconds: number;
  readonly jobId: string;
  readonly leaseToken: string;
  readonly signal?: AbortSignal | undefined;
  readonly workerId: string;
}

export interface DurableJobStore {
  claimJobs(input: ClaimJobsInput): Promise<readonly ClaimedJob[]>;
  completeJob(input: CompleteJobInput): Promise<void>;
  failJob(input: FailJobInput): Promise<void>;
  heartbeatJob(input: HeartbeatJobInput): Promise<string>;
  reclaimExpiredJobs(limit: number): Promise<number>;
}

export class JobStoreError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number) {
    super("The durable job store rejected the request.");
    this.name = "JobStoreError";
    this.code = code;
    this.status = status;
  }
}

interface RpcClientOptions {
  readonly fetchImplementation?: typeof fetch;
  readonly serviceRoleKey: string;
  readonly supabaseUrl: string;
}

function requireRecord(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new JobStoreError(`invalid_${label}`, 502);
  }
  return value as Record<string, unknown>;
}

function requireString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new JobStoreError(`invalid_${label}`, 502);
  }
  return value;
}

function requireNullableString(value: unknown, label: string): string | null {
  return value === null ? null : requireString(value, label);
}

function requirePositiveInteger(value: unknown, label: string): number {
  if (!Number.isInteger(value) || (value as number) < 1) {
    throw new JobStoreError(`invalid_${label}`, 502);
  }
  return value as number;
}

function validateSupabaseUrl(value: string): string {
  const url = new URL(value);
  const isLocal = ["127.0.0.1", "localhost", "::1"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && isLocal)) {
    throw new TypeError(
      "Supabase URL must use HTTPS except for local development.",
    );
  }
  return url.toString().replace(/\/$/u, "");
}

export class PostgrestJobStore implements DurableJobStore {
  readonly #fetch: typeof fetch;
  readonly #serviceRoleKey: string;
  readonly #supabaseUrl: string;

  constructor(options: RpcClientOptions) {
    if (options.serviceRoleKey.trim().length < 20) {
      throw new TypeError(
        "A non-empty server-only service role key is required.",
      );
    }
    this.#fetch = options.fetchImplementation ?? fetch;
    this.#serviceRoleKey = options.serviceRoleKey;
    this.#supabaseUrl = validateSupabaseUrl(options.supabaseUrl);
  }

  async #rpc(
    functionName: string,
    body: Record<string, unknown>,
    signal?: AbortSignal,
  ) {
    const response = await this.#fetch(
      `${this.#supabaseUrl}/rest/v1/rpc/${functionName}`,
      {
        body: JSON.stringify(body),
        headers: {
          apikey: this.#serviceRoleKey,
          Authorization: `Bearer ${this.#serviceRoleKey}`,
          "Content-Profile": "app",
          "Content-Type": "application/json",
        },
        method: "POST",
        ...(signal === undefined ? {} : { signal }),
      },
    );

    if (!response.ok) {
      throw new JobStoreError(`rpc_${functionName}_failed`, response.status);
    }

    return response.json() as Promise<unknown>;
  }

  async claimJobs(input: ClaimJobsInput): Promise<readonly ClaimedJob[]> {
    const value = await this.#rpc("claim_jobs", {
      p_job_types: input.jobTypes ?? null,
      p_lease_seconds: input.leaseSeconds,
      p_limit: input.limit,
      p_worker_id: input.workerId,
    });

    if (!Array.isArray(value)) {
      throw new JobStoreError("invalid_claim_jobs_response", 502);
    }

    return value.map((item) => {
      const row = requireRecord(item, "claimed_job");
      return {
        attemptNumber: requirePositiveInteger(
          row.attempt_number,
          "attempt_number",
        ),
        causationId: requireNullableString(row.causation_id, "causation_id"),
        correlationId: requireString(row.correlation_id, "correlation_id"),
        entityId: requireNullableString(row.entity_id, "entity_id"),
        entityType: requireString(row.entity_type, "entity_type"),
        idempotencyKey: requireString(row.idempotency_key, "idempotency_key"),
        jobId: requireString(row.job_id, "job_id"),
        jobType: requireString(row.job_type, "job_type"),
        leaseExpiresAt: requireString(row.lease_expires_at, "lease_expires_at"),
        leaseToken: requireString(row.lease_token, "lease_token"),
        maximumAttempts: requirePositiveInteger(
          row.max_attempts,
          "max_attempts",
        ),
        outboxEventId: requireString(row.outbox_event_id, "outbox_event_id"),
        payload: requireRecord(row.payload, "payload"),
        payloadSchemaVersion: requirePositiveInteger(
          row.payload_schema_version,
          "payload_schema_version",
        ),
        workspaceId: requireString(row.workspace_id, "workspace_id"),
      } satisfies ClaimedJob;
    });
  }

  async completeJob(input: CompleteJobInput): Promise<void> {
    await this.#rpc("complete_job", {
      p_job_id: input.jobId,
      p_lease_token: input.leaseToken,
      p_provider_request_id: input.providerRequestId ?? null,
      p_result_summary: input.resultSummary,
      p_worker_id: input.workerId,
    });
  }

  async failJob(input: FailJobInput): Promise<void> {
    await this.#rpc("fail_job", {
      p_error_classification: input.classification,
      p_error_code: input.errorCode,
      p_error_detail_safe: input.errorDetailSafe,
      p_job_id: input.jobId,
      p_lease_token: input.leaseToken,
      p_provider_request_id: input.providerRequestId ?? null,
      p_retry_after_seconds: input.retryAfterSeconds ?? null,
      p_worker_id: input.workerId,
    });
  }

  async heartbeatJob(input: HeartbeatJobInput): Promise<string> {
    const value = await this.#rpc(
      "heartbeat_job",
      {
        p_extend_seconds: input.extendSeconds,
        p_job_id: input.jobId,
        p_lease_token: input.leaseToken,
        p_worker_id: input.workerId,
      },
      input.signal,
    );
    return requireString(value, "heartbeat_response");
  }

  async reclaimExpiredJobs(limit: number): Promise<number> {
    if (!Number.isInteger(limit) || limit < 1 || limit > 1_000) {
      throw new RangeError("reclaim limit must be an integer from 1 to 1000.");
    }
    const value = await this.#rpc("reclaim_expired_job_leases", {
      p_limit: limit,
    });
    if (!Array.isArray(value)) {
      throw new JobStoreError("invalid_reclaim_response", 502);
    }
    for (const item of value) {
      const row = requireRecord(item, "reclaimed_job");
      requireString(row.job_id, "reclaimed_job_id");
      requireString(row.resulting_status, "reclaimed_job_status");
    }
    return value.length;
  }
}
