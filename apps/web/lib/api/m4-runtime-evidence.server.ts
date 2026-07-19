import type { M4RuntimeEvidencePort } from "@vynlo/application";
import { z } from "zod";

import { PostgrestCommandError } from "./postgrest-error";

const runtimeEvidenceInputSchema = z
  .object({
    accessToken: z.string().min(16).max(8_192),
    assignmentId: z.string().uuid().nullable(),
    correlationId: z.string().uuid(),
    dealId: z.string().uuid().nullable(),
    evidence: z.record(z.string(), z.unknown()),
    idempotencyKey: z.string().trim().min(8).max(200),
    kind: z.enum(["calculation", "tax"]),
    requestId: z.string().trim().min(1).max(200),
    versionId: z.string().uuid(),
    workspaceId: z.string().uuid(),
  })
  .strict();
const authenticatedUserSchema = z
  .object({ id: z.string().uuid() })
  .passthrough();
const evidenceReceiptSchema = z
  .object({ evidence_id: z.string().uuid() })
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

async function safeJson(response: Response): Promise<unknown> {
  try {
    const value: unknown = await response.json();
    return value;
  } catch {
    throw new PostgrestCommandError("service_unavailable", 503);
  }
}

/**
 * M4-CALC-AC-004, M4-TAX-AC-002: bind a domain-runtime result to the
 * independently verified user before an official document may consume it.
 */
export class SupabaseM4RuntimeEvidencePort implements M4RuntimeEvidencePort {
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #publicKey: string;
  readonly #serviceRoleKey: string;

  constructor(input: {
    readonly fetchImplementation?: typeof fetch;
    readonly publicKey: string;
    readonly serviceRoleKey: string;
    readonly supabaseUrl: string;
  }) {
    if (
      input.publicKey.trim() !== input.publicKey ||
      input.publicKey.length < 20 ||
      input.serviceRoleKey.trim() !== input.serviceRoleKey ||
      input.serviceRoleKey.length < 20 ||
      input.publicKey === input.serviceRoleKey
    ) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    this.#baseUrl = safeOrigin(input.supabaseUrl);
    this.#fetch = input.fetchImplementation ?? fetch;
    this.#publicKey = input.publicKey;
    this.#serviceRoleKey = input.serviceRoleKey;
  }

  async record(
    value: Parameters<M4RuntimeEvidencePort["record"]>[0],
  ): ReturnType<M4RuntimeEvidencePort["record"]> {
    const parsed = runtimeEvidenceInputSchema.safeParse(value);
    if (!parsed.success) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    const input = parsed.data;

    let authenticated: Response;
    try {
      authenticated = await this.#fetch(`${this.#baseUrl}/auth/v1/user`, {
        cache: "no-store",
        headers: {
          Accept: "application/json",
          apikey: this.#publicKey,
          Authorization: `Bearer ${input.accessToken}`,
        },
        method: "GET",
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    if (!authenticated.ok) {
      if (authenticated.status === 401) {
        throw new PostgrestCommandError("authentication_required", 401);
      }
      if (authenticated.status === 403) {
        throw new PostgrestCommandError("permission_denied", 403);
      }
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    const user = authenticatedUserSchema.safeParse(
      await safeJson(authenticated),
    );
    if (!user.success) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }

    let recorded: Response;
    try {
      recorded = await this.#fetch(
        `${this.#baseUrl}/rest/v1/rpc/m4_record_runtime_evidence`,
        {
          body: JSON.stringify({
            p_actor_user_id: user.data.id,
            p_assignment_id: input.assignmentId,
            p_correlation_id: input.correlationId,
            p_deal_id: input.dealId,
            p_evidence: input.evidence,
            p_idempotency_key: input.idempotencyKey,
            p_kind: input.kind,
            p_request_id: input.requestId,
            p_version_id: input.versionId,
            p_workspace_id: input.workspaceId,
          }),
          cache: "no-store",
          headers: {
            Accept: "application/json",
            "Accept-Profile": "app",
            apikey: this.#serviceRoleKey,
            Authorization: `Bearer ${this.#serviceRoleKey}`,
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
    if (!recorded.ok) {
      if (recorded.status === 409) {
        throw new PostgrestCommandError("conflict", 409);
      }
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    const receipt = z
      .array(evidenceReceiptSchema)
      .length(1)
      .safeParse(await safeJson(recorded));
    if (!receipt.success) {
      throw new PostgrestCommandError("service_unavailable", 503);
    }
    return Object.freeze({ evidenceId: receipt.data[0]!.evidence_id });
  }
}
