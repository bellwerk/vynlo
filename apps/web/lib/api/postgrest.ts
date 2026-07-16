import {
  type AuthenticatedRpcGateway,
  type AuthenticatedRpcRequest,
  VerticalSliceApplicationService,
  WorkspaceInvitationApplicationService,
} from "@vynlo/application";
import { z } from "zod";

export type SafeApiErrorCode =
  | "authentication_required"
  | "permission_denied"
  | "conflict"
  | "invalid_request"
  | "rate_limited"
  | "unprocessable_command"
  | "service_unavailable";

export class PostgrestCommandError extends Error {
  readonly code: SafeApiErrorCode;
  readonly status: 400 | 401 | 403 | 409 | 422 | 429 | 503;

  constructor(
    code: SafeApiErrorCode,
    status: 400 | 401 | 403 | 409 | 422 | 429 | 503,
  ) {
    super("The command data store rejected the request.");
    this.name = "PostgrestCommandError";
    this.code = code;
    this.status = status;
  }
}

export interface PostgrestConfig {
  readonly publicKey: string;
  readonly url: string;
}

interface PostgrestGatewayOptions {
  readonly fetchImplementation?: typeof fetch;
  readonly publicKey: string;
  readonly timeoutMilliseconds?: number;
  readonly url: string;
}

const postgrestErrorSchema = z
  .object({ code: z.string().min(1).max(100) })
  .passthrough();

function isLocalHostname(hostname: string): boolean {
  return ["127.0.0.1", "localhost", "::1"].includes(hostname);
}

function parseLegacyJwtRole(key: string): string | null {
  const parts = key.split(".");
  if (parts.length !== 3 || !parts[1]) {
    return null;
  }

  try {
    const base64 = parts[1].replace(/-/gu, "+").replace(/_/gu, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    const payload: unknown = JSON.parse(atob(padded));
    const parsed = z
      .object({ role: z.string() })
      .passthrough()
      .safeParse(payload);
    return parsed.success ? parsed.data.role : null;
  } catch {
    return null;
  }
}

export function parsePostgrestConfig(
  urlValue: string | undefined,
  publishableKeyValue: string | undefined,
  anonKeyValue: string | undefined,
): PostgrestConfig {
  let url: URL;
  try {
    url = new URL(urlValue?.trim() ?? "");
  } catch {
    throw new PostgrestCommandError("service_unavailable", 503);
  }

  const isSafeProtocol =
    url.protocol === "https:" ||
    (url.protocol === "http:" && isLocalHostname(url.hostname));
  if (
    !isSafeProtocol ||
    url.username !== "" ||
    url.password !== "" ||
    url.search !== "" ||
    url.hash !== "" ||
    (url.pathname !== "" && url.pathname !== "/")
  ) {
    throw new PostgrestCommandError("service_unavailable", 503);
  }

  const publicKey = (
    publishableKeyValue?.trim() ||
    anonKeyValue?.trim() ||
    ""
  ).trim();
  const legacyRole = parseLegacyJwtRole(publicKey);
  const isPublishableKey =
    publicKey.startsWith("sb_publishable_") &&
    /^[A-Za-z0-9_-]+$/u.test(publicKey);
  const isLegacyAnonKey =
    publicKey.split(".").length === 3 && legacyRole === "anon";
  if (
    publicKey.length < 20 ||
    publicKey.length > 16_384 ||
    publicKey.startsWith("sb_secret_") ||
    (!isPublishableKey && !isLegacyAnonKey)
  ) {
    throw new PostgrestCommandError("service_unavailable", 503);
  }

  return Object.freeze({
    publicKey,
    url: url.toString().replace(/\/$/u, ""),
  });
}

function mapPostgrestError(
  status: number,
  sqlState: string | null,
): PostgrestCommandError {
  if (status === 401 || sqlState?.startsWith("PGRST3")) {
    return new PostgrestCommandError("authentication_required", 401);
  }
  if (status === 403 || sqlState === "42501") {
    return new PostgrestCommandError("permission_denied", 403);
  }
  if (status === 409 || sqlState === "23505") {
    return new PostgrestCommandError("conflict", 409);
  }
  if (status === 429) {
    return new PostgrestCommandError("rate_limited", 429);
  }
  if (sqlState === "22023") {
    return new PostgrestCommandError("invalid_request", 400);
  }
  if (["23502", "23503", "23514"].includes(sqlState ?? "")) {
    return new PostgrestCommandError("unprocessable_command", 422);
  }
  if (status === 400) {
    return new PostgrestCommandError("invalid_request", 400);
  }
  return new PostgrestCommandError("service_unavailable", 503);
}

async function readResponseJson(response: Response): Promise<unknown> {
  try {
    const value: unknown = await response.json();
    return value;
  } catch {
    throw new PostgrestCommandError("service_unavailable", 503);
  }
}

export class PostgrestAuthenticatedRpcGateway implements AuthenticatedRpcGateway {
  readonly #fetch: typeof fetch;
  readonly #publicKey: string;
  readonly #timeoutMilliseconds: number;
  readonly #url: string;

  constructor(options: PostgrestGatewayOptions) {
    if (
      !Number.isInteger(options.timeoutMilliseconds ?? 10_000) ||
      (options.timeoutMilliseconds ?? 10_000) < 100 ||
      (options.timeoutMilliseconds ?? 10_000) > 30_000
    ) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }

    const config = parsePostgrestConfig(
      options.url,
      options.publicKey,
      undefined,
    );
    this.#fetch = options.fetchImplementation ?? fetch;
    this.#publicKey = config.publicKey;
    this.#timeoutMilliseconds = options.timeoutMilliseconds ?? 10_000;
    this.#url = config.url;
  }

  async invoke(request: AuthenticatedRpcRequest): Promise<unknown> {
    let response: Response;
    try {
      response = await this.#fetch(
        `${this.#url}/rest/v1/rpc/${request.functionName}`,
        {
          body: JSON.stringify(request.parameters),
          cache: "no-store",
          headers: {
            Accept: "application/json",
            "Accept-Profile": "app",
            apikey: this.#publicKey,
            Authorization: `Bearer ${request.accessToken}`,
            "Content-Type": "application/json",
            "Content-Profile": "app",
          },
          method: "POST",
          signal: AbortSignal.timeout(this.#timeoutMilliseconds),
        },
      );
    } catch {
      throw new PostgrestCommandError("service_unavailable", 503);
    }

    if (!response.ok) {
      let sqlState: string | null = null;
      try {
        const body = await readResponseJson(response);
        const parsed = postgrestErrorSchema.safeParse(body);
        sqlState = parsed.success ? parsed.data.code : null;
      } catch {
        sqlState = null;
      }
      throw mapPostgrestError(response.status, sqlState);
    }

    return readResponseJson(response);
  }
}

export function createVerticalSliceApplicationService(): VerticalSliceApplicationService {
  const config = parsePostgrestConfig(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
  return new VerticalSliceApplicationService(
    new PostgrestAuthenticatedRpcGateway({
      publicKey: config.publicKey,
      url: config.url,
    }),
  );
}

export function createWorkspaceInvitationApplicationService(): WorkspaceInvitationApplicationService {
  const config = parsePostgrestConfig(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
  return new WorkspaceInvitationApplicationService(
    new PostgrestAuthenticatedRpcGateway({
      publicKey: config.publicKey,
      url: config.url,
    }),
  );
}
