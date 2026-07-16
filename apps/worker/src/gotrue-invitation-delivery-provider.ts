import type {
  InvitationDeliveryProvider,
  InvitationDeliveryProviderReceipt,
} from "./invitation-delivery-handler";
import { JobExecutionError } from "./job-runner";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/u;
const providerRequestIdPattern = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/u;

function validatedOrigin(value: string, label: string): string {
  const url = new URL(value);
  const isLocal = ["127.0.0.1", "localhost", "::1"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && isLocal)) {
    throw new TypeError(`${label} must use HTTPS outside local development.`);
  }
  if (
    url.username !== "" ||
    url.password !== "" ||
    url.pathname !== "/" ||
    url.search !== "" ||
    url.hash !== ""
  ) {
    throw new TypeError(`${label} must be an origin without credentials.`);
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

function providerRequestId(response: Response): string | undefined {
  const value = response.headers.get("x-request-id");
  return value !== null && providerRequestIdPattern.test(value)
    ? value
    : undefined;
}

function classifyResponse(response: Response): JobExecutionError {
  const requestId = providerRequestId(response);
  if (response.status === 401 || response.status === 403) {
    return new JobExecutionError({
      classification: "provider_auth",
      code: "auth.invitation_provider_access_denied",
      providerRequestId: requestId,
      safeDetail: "The identity provider denied the worker request.",
    });
  }
  if (response.status === 429) {
    return new JobExecutionError({
      classification: "rate_limited",
      code: "auth.invitation_provider_rate_limited",
      providerRequestId: requestId,
      retryAfterSeconds: retryAfterSeconds(response),
      safeDetail: "The identity provider asked the worker to retry later.",
    });
  }
  if ([408, 425].includes(response.status) || response.status >= 500) {
    return new JobExecutionError({
      classification: "transient",
      code: "auth.invitation_provider_temporarily_unavailable",
      providerRequestId: requestId,
      safeDetail: "The identity provider is temporarily unavailable.",
    });
  }
  if ([409, 422].includes(response.status)) {
    return new JobExecutionError({
      classification: "transient",
      code: "auth.invitation_provider_identity_conflict",
      providerRequestId: requestId,
      safeDetail: "The identity record changed before invitation delivery.",
    });
  }
  return new JobExecutionError({
    classification: "permanent",
    code: "auth.invitation_provider_request_rejected",
    providerRequestId: requestId,
    safeDetail:
      "The identity provider rejected the validated invitation request.",
  });
}

export class GoTrueInvitationDeliveryProvider implements InvitationDeliveryProvider {
  readonly #appOrigin: string;
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #headers: Readonly<Record<string, string>>;
  readonly #timeoutMs: number;

  constructor(input: {
    readonly appUrl: string;
    readonly fetchImplementation?: typeof fetch;
    readonly serviceRoleKey: string;
    readonly supabaseUrl: string;
    readonly timeoutMs: number;
  }) {
    if (input.serviceRoleKey.trim().length < 20) {
      throw new TypeError("A server-only service role key is required.");
    }
    if (
      !Number.isInteger(input.timeoutMs) ||
      input.timeoutMs < 1_000 ||
      input.timeoutMs > 30_000
    ) {
      throw new RangeError(
        "Invitation delivery timeout must be 1000..30000ms.",
      );
    }
    this.#appOrigin = validatedOrigin(input.appUrl, "Application URL");
    this.#baseUrl = validatedOrigin(input.supabaseUrl, "Supabase URL");
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#headers = {
      apikey: input.serviceRoleKey,
      Authorization: `Bearer ${input.serviceRoleKey}`,
      "Content-Type": "application/json;charset=UTF-8",
    };
    this.#timeoutMs = input.timeoutMs;
  }

  async deliver(
    input: Parameters<InvitationDeliveryProvider["deliver"]>[0],
  ): Promise<InvitationDeliveryProviderReceipt> {
    if (
      !uuidPattern.test(input.invitationId) ||
      !uuidPattern.test(input.workspaceId) ||
      input.email.length > 320 ||
      !emailPattern.test(input.email)
    ) {
      throw new JobExecutionError({
        classification: "validation",
        code: "auth.invitation_provider_input_rejected",
        safeDetail:
          "The authoritative invitation data is invalid for provider delivery.",
      });
    }

    const redirect = new URL("/login", this.#appOrigin);
    redirect.searchParams.set("invitation", input.invitationId);
    redirect.searchParams.set("workspace", input.workspaceId);
    const endpoint = new URL(
      `${this.#baseUrl}/auth/v1/${input.providerIdentityExists ? "otp" : "invite"}`,
    );
    endpoint.searchParams.set("redirect_to", redirect.toString());
    const body = input.providerIdentityExists
      ? {
          code_challenge: null,
          code_challenge_method: null,
          create_user: false,
          data: {},
          email: input.email,
          gotrue_meta_security: {},
        }
      : { email: input.email };

    const timeout = new AbortController();
    const timeoutHandle = setTimeout(() => timeout.abort(), this.#timeoutMs);
    const signal = AbortSignal.any([input.signal, timeout.signal]);
    let response: Response;
    try {
      response = await this.#fetch(endpoint, {
        body: JSON.stringify(body),
        headers: this.#headers,
        method: "POST",
        signal,
      });
    } catch {
      if (input.signal.aborted) {
        throw new JobExecutionError({
          classification: "transient",
          code: "auth.invitation_provider_cancelled",
          safeDetail: "The identity provider request was cancelled.",
        });
      }
      if (timeout.signal.aborted) {
        throw new JobExecutionError({
          classification: "transient",
          code: "auth.invitation_provider_timeout",
          safeDetail: "The identity provider request exceeded its time limit.",
        });
      }
      throw new JobExecutionError({
        classification: "transient",
        code: "auth.invitation_provider_transport_failed",
        safeDetail: "The identity provider request did not complete.",
      });
    } finally {
      clearTimeout(timeoutHandle);
    }

    const requestId = providerRequestId(response);
    if (!response.ok) {
      const failure = classifyResponse(response);
      if (response.body !== null) {
        void response.body.cancel().catch(() => undefined);
      }
      throw failure;
    }
    if (response.body !== null) {
      void response.body.cancel().catch(() => undefined);
    }

    return requestId === undefined ? {} : { providerRequestId: requestId };
  }
}
