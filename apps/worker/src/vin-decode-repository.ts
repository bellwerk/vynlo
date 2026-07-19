import { JobExecutionError } from "./job-runner";
import type {
  VinDecodeCompletion,
  VinDecodeResultRepository,
} from "./vin-decode-handler";

function invalidDatabaseContract(): JobExecutionError {
  return new JobExecutionError({
    classification: "permanent",
    code: "vin.invalid_database_contract",
    safeDetail: "The VIN database response failed contract validation.",
  });
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

function classifyResponse(response: Response): JobExecutionError {
  if (response.status === 401 || response.status === 403) {
    return new JobExecutionError({
      classification: "provider_auth",
      code: "vin.database_access_denied",
      safeDetail: "The VIN database denied the worker request.",
    });
  }
  if (response.status === 409) {
    return new JobExecutionError({
      classification: "permanent",
      code: "vin.result_conflict",
      safeDetail: "The VIN result conflicts with immutable terminal state.",
    });
  }
  if (response.status === 429 || response.status >= 500) {
    return new JobExecutionError({
      classification: "transient",
      code: "vin.database_temporarily_unavailable",
      safeDetail: "The VIN database is temporarily unavailable.",
    });
  }
  return new JobExecutionError({
    classification: "permanent",
    code: "vin.database_request_rejected",
    safeDetail: "The VIN database rejected the validated worker request.",
  });
}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidDatabaseContract();
  }
  return value as Record<string, unknown>;
}

function uuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(
      value,
    )
  ) {
    throw invalidDatabaseContract();
  }
  return value.toLowerCase();
}

function positiveInteger(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1) {
    throw invalidDatabaseContract();
  }
  return value as number;
}

export class PostgrestVinDecodeResultRepository implements VinDecodeResultRepository {
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
    this.#baseUrl = validatedBaseUrl(input.supabaseUrl);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#headers = {
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
      "Content-Profile": "app",
      "Content-Type": "application/json",
    };
  }

  async completeResult(
    input: Parameters<VinDecodeResultRepository["completeResult"]>[0],
  ): Promise<VinDecodeCompletion> {
    let response: Response;
    try {
      response = await this.#fetch(
        `${this.#baseUrl}/rest/v1/rpc/complete_vin_decode_request`,
        {
          body: JSON.stringify({
            p_body_type: input.facts.bodyType,
            p_correlation_id: input.correlationId,
            p_cylinders: input.facts.cylinders,
            p_decoded_at: input.decodedAt,
            p_drivetrain: input.facts.drivetrain,
            p_engine_liters: input.facts.engineLiters,
            p_fuel_type: input.facts.fuelType,
            p_horsepower: input.facts.horsepower,
            p_job_id: input.jobId,
            p_lease_token: input.leaseToken,
            p_make: input.facts.make,
            p_model: input.facts.model,
            p_model_year: input.facts.modelYear,
            p_provider_key: input.providerKey,
            p_provider_version: input.providerVersion,
            p_raw_response: input.rawResponse,
            p_request_id: input.requestId,
            p_transmission: input.facts.transmission,
            p_trim_name: input.facts.trim,
            p_vin_decode_request_id: input.vinDecodeRequestId,
            p_warnings: input.warnings,
            p_worker_id: input.workerId,
            p_workspace_id: input.workspaceId,
          }),
          headers: this.#headers,
          method: "POST",
          signal: input.signal,
        },
      );
    } catch {
      throw new JobExecutionError({
        classification: "transient",
        code: "vin.database_transport_failed",
        safeDetail: "The VIN database request did not complete.",
      });
    }
    if (!response.ok) {
      throw classifyResponse(response);
    }

    let value: unknown;
    try {
      value = await response.json();
    } catch {
      throw invalidDatabaseContract();
    }
    if (!Array.isArray(value) || value.length !== 1) {
      throw invalidDatabaseContract();
    }
    const row = record(value[0]);
    if (
      row.decode_status !== "succeeded" ||
      typeof row.replayed !== "boolean" ||
      !Number.isSafeInteger(row.duplicate_candidate_count) ||
      (row.duplicate_candidate_count as number) < 0
    ) {
      throw invalidDatabaseContract();
    }
    return {
      aggregateVersion: positiveInteger(row.aggregate_version),
      auditEventId: uuid(row.audit_event_id),
      decodeStatus: "succeeded",
      duplicateCandidateCount: row.duplicate_candidate_count as number,
      outboxEventId: uuid(row.outbox_event_id),
      replayed: row.replayed,
      vinDecodeResultId: uuid(row.vin_decode_result_id),
    };
  }
}
