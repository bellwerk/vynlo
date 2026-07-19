// Stable test IDs: T-CALC-001, T-TAX-001, T-RBAC-001.
import { describe, expect, it, vi } from "vitest";

import { SupabaseM4RuntimeEvidencePort } from "./m4-runtime-evidence.server";

const ids = Object.freeze({
  actor: "10000000-0000-4000-8000-000000000001",
  correlation: "10000000-0000-4000-8000-000000000002",
  evidence: "10000000-0000-4000-8000-000000000003",
  version: "10000000-0000-4000-8000-000000000004",
  workspace: "10000000-0000-4000-8000-000000000005",
});
const accessToken = "user-header.user-payload.user-signature";
const publicKey = "sb_publishable_public_project_key_material_0001";
const serviceRoleKey = "server-only-service-role-material-fixture";

function input() {
  return {
    accessToken,
    assignmentId: null,
    correlationId: ids.correlation,
    dealId: null,
    evidence: {
      checksum: "a".repeat(64),
      definition: { key: "sale-total", version: "1.0.0" },
      output: { total_minor: "10500" },
    },
    idempotencyKey: "runtime-evidence-fixture-0001",
    kind: "calculation" as const,
    requestId: "runtime-evidence-request-0001",
    versionId: ids.version,
    workspaceId: ids.workspace,
  };
}

describe("Supabase M4 runtime-evidence port", () => {
  it("verifies the user, records with service credentials, and returns only the evidence ID", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json({ id: ids.actor, role: "authenticated" }),
      )
      .mockResolvedValueOnce(Response.json([{ evidence_id: ids.evidence }]));
    const port = new SupabaseM4RuntimeEvidencePort({
      fetchImplementation,
      publicKey,
      serviceRoleKey,
      supabaseUrl: "https://example.supabase.co",
    });

    const result = await port.record(input());

    expect(result).toEqual({ evidenceId: ids.evidence });
    expect(Object.keys(result)).toEqual(["evidenceId"]);
    expect(fetchImplementation).toHaveBeenCalledTimes(2);

    const [authUrl, authInit] = fetchImplementation.mock.calls[0] ?? [];
    expect(authUrl).toBe("https://example.supabase.co/auth/v1/user");
    expect(authInit?.method).toBe("GET");
    const authHeaders = new Headers(authInit?.headers);
    expect(authHeaders.get("apikey")).toBe(publicKey);
    expect(authHeaders.get("authorization")).toBe(`Bearer ${accessToken}`);
    expect(JSON.stringify(authInit)).not.toContain(serviceRoleKey);

    const [rpcUrl, rpcInit] = fetchImplementation.mock.calls[1] ?? [];
    expect(rpcUrl).toBe(
      "https://example.supabase.co/rest/v1/rpc/m4_record_runtime_evidence",
    );
    expect(rpcInit?.method).toBe("POST");
    const rpcHeaders = new Headers(rpcInit?.headers);
    expect(rpcHeaders.get("apikey")).toBe(serviceRoleKey);
    expect(rpcHeaders.get("authorization")).toBe(`Bearer ${serviceRoleKey}`);
    expect(rpcHeaders.get("accept-profile")).toBe("app");
    expect(rpcHeaders.get("content-profile")).toBe("app");
    const rpcBody: unknown = JSON.parse(String(rpcInit?.body));
    expect(rpcBody).toEqual({
      p_actor_user_id: ids.actor,
      p_assignment_id: null,
      p_correlation_id: ids.correlation,
      p_deal_id: null,
      p_evidence: input().evidence,
      p_idempotency_key: input().idempotencyKey,
      p_kind: "calculation",
      p_request_id: input().requestId,
      p_version_id: ids.version,
      p_workspace_id: ids.workspace,
    });
    expect(JSON.stringify(rpcBody)).not.toContain(accessToken);
    expect(JSON.stringify(result)).not.toMatch(/service-role|user-payload/iu);
  });

  it("does not invoke the service-only RPC when Auth rejects the access token", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(null, { status: 401 }));
    const port = new SupabaseM4RuntimeEvidencePort({
      fetchImplementation,
      publicKey,
      serviceRoleKey,
      supabaseUrl: "https://example.supabase.co",
    });

    await expect(port.record(input())).rejects.toMatchObject({
      code: "authentication_required",
      status: 401,
    });
    expect(fetchImplementation).toHaveBeenCalledOnce();
  });

  it("fails closed on an invalid receipt without leaking either credential", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json({ id: ids.actor }))
      .mockResolvedValueOnce(Response.json([{ evidence_id: "not-a-uuid" }]));
    const port = new SupabaseM4RuntimeEvidencePort({
      fetchImplementation,
      publicKey,
      serviceRoleKey,
      supabaseUrl: "https://example.supabase.co",
    });

    const error = await port.record(input()).catch((reason: unknown) => reason);
    expect(error).toMatchObject({ code: "service_unavailable", status: 503 });
    expect(JSON.stringify(error)).not.toContain(accessToken);
    expect(JSON.stringify(error)).not.toContain(serviceRoleKey);
  });
});
