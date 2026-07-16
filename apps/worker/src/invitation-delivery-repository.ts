import type {
  AuthoritativeInvitationDelivery,
  InvitationDeliveryRepository,
} from "./invitation-delivery-handler";
import { JobExecutionError } from "./job-runner";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const localePattern = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/u;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/u;

function invalidDatabaseContract(): JobExecutionError {
  return new JobExecutionError({
    classification: "permanent",
    code: "auth.invitation_invalid_database_contract",
    safeDetail:
      "The invitation delivery database response failed contract validation.",
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
  if (
    url.username !== "" ||
    url.password !== "" ||
    url.pathname !== "/" ||
    url.search !== "" ||
    url.hash !== ""
  ) {
    throw new TypeError("Supabase URL must be an origin without credentials.");
  }
  return url.toString().replace(/\/$/u, "");
}

function retryAfterSeconds(response: Response): number | undefined {
  const raw = response.headers.get("retry-after");
  if (raw === null || !/^\d{1,5}$/u.test(raw)) {
    return undefined;
  }
  const value = Number(raw);
  return value >= 1 && value <= 86_400 ? value : undefined;
}

function classifyResponse(response: Response): JobExecutionError {
  if (response.status === 401 || response.status === 403) {
    return new JobExecutionError({
      classification: "provider_auth",
      code: "auth.invitation_database_access_denied",
      safeDetail: "The invitation database denied the worker request.",
    });
  }
  if (response.status === 429) {
    return new JobExecutionError({
      classification: "rate_limited",
      code: "auth.invitation_database_rate_limited",
      retryAfterSeconds: retryAfterSeconds(response),
      safeDetail: "The invitation database asked the worker to retry later.",
    });
  }
  if ([408, 425].includes(response.status) || response.status >= 500) {
    return new JobExecutionError({
      classification: "transient",
      code: "auth.invitation_database_temporarily_unavailable",
      safeDetail: "The invitation database is temporarily unavailable.",
    });
  }
  if ([400, 409, 422].includes(response.status)) {
    return new JobExecutionError({
      classification: "validation",
      code: "auth.invitation_delivery_state_rejected",
      safeDetail:
        "The invitation is not eligible for delivery in its current state.",
    });
  }
  return new JobExecutionError({
    classification: "permanent",
    code: "auth.invitation_database_request_rejected",
    safeDetail:
      "The invitation database rejected the validated worker request.",
  });
}

function parseDelivery(value: unknown): AuthoritativeInvitationDelivery {
  if (!Array.isArray(value) || value.length !== 1) {
    throw invalidDatabaseContract();
  }
  const row = value[0];
  if (typeof row !== "object" || row === null || Array.isArray(row)) {
    throw invalidDatabaseContract();
  }
  const record = row as Record<string, unknown>;
  const expectedKeys = [
    "email",
    "expires_at",
    "invitation_id",
    "provider_identity_exists",
    "requested_locale",
    "workspace_id",
  ];
  const actualKeys = Object.keys(record).sort();
  if (
    actualKeys.length !== expectedKeys.length ||
    actualKeys.some((key, index) => key !== expectedKeys[index]) ||
    typeof record.invitation_id !== "string" ||
    !uuidPattern.test(record.invitation_id) ||
    typeof record.workspace_id !== "string" ||
    !uuidPattern.test(record.workspace_id) ||
    typeof record.email !== "string" ||
    record.email.length > 320 ||
    !emailPattern.test(record.email) ||
    typeof record.requested_locale !== "string" ||
    record.requested_locale.length > 64 ||
    !localePattern.test(record.requested_locale) ||
    typeof record.expires_at !== "string" ||
    !Number.isFinite(Date.parse(record.expires_at)) ||
    typeof record.provider_identity_exists !== "boolean"
  ) {
    throw invalidDatabaseContract();
  }

  return {
    email: record.email,
    expiresAt: record.expires_at,
    invitationId: record.invitation_id,
    providerIdentityExists: record.provider_identity_exists,
    requestedLocale: record.requested_locale,
    workspaceId: record.workspace_id,
  };
}

export class PostgrestInvitationDeliveryRepository implements InvitationDeliveryRepository {
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

  async readDeliveryJob(
    input: Parameters<InvitationDeliveryRepository["readDeliveryJob"]>[0],
  ): Promise<AuthoritativeInvitationDelivery> {
    let response: Response;
    try {
      response = await this.#fetch(
        `${this.#baseUrl}/rest/v1/rpc/read_invitation_delivery_job`,
        {
          body: JSON.stringify({
            p_job_id: input.jobId,
            p_lease_token: input.leaseToken,
            p_worker_id: input.workerId,
          }),
          headers: this.#headers,
          method: "POST",
          signal: input.signal,
        },
      );
    } catch {
      throw new JobExecutionError({
        classification: "transient",
        code: input.signal.aborted
          ? "auth.invitation_database_cancelled"
          : "auth.invitation_database_transport_failed",
        safeDetail: input.signal.aborted
          ? "The invitation database request was cancelled."
          : "The invitation database request did not complete.",
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
    return parseDelivery(value);
  }
}
