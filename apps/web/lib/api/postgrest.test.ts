import { describe, expect, it, vi } from "vitest";
import {
  parsePostgrestConfig,
  PostgrestAuthenticatedRpcGateway,
  PostgrestCommandError,
} from "./postgrest";

function jwtForRole(role: string): string {
  const encode = (value: unknown) =>
    btoa(JSON.stringify(value))
      .replace(/\+/gu, "-")
      .replace(/\//gu, "_")
      .replace(/=+$/gu, "");
  return `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ role })}.signature`;
}

describe("PostgrestAuthenticatedRpcGateway", () => {
  it("accepts HTTPS and loopback URLs with an anon or publishable key", () => {
    expect(
      parsePostgrestConfig(
        "https://project.supabase.co/",
        "sb_publishable_public_key_material",
        undefined,
      ),
    ).toEqual({
      publicKey: "sb_publishable_public_key_material",
      url: "https://project.supabase.co",
    });
    expect(
      parsePostgrestConfig(
        "http://127.0.0.1:54321",
        undefined,
        jwtForRole("anon"),
      ).url,
    ).toBe("http://127.0.0.1:54321");
  });

  it.each([
    "http://project.supabase.co",
    "https://user:password@project.supabase.co",
    "https://project.supabase.co/untrusted-path",
    "https://project.supabase.co?key=value",
  ])("rejects unsafe PostgREST URL %s", (url) => {
    expect(() => parsePostgrestConfig(url, "x".repeat(32), undefined)).toThrow(
      PostgrestCommandError,
    );
  });

  it("rejects secret and legacy service-role keys", () => {
    expect(() =>
      parsePostgrestConfig(
        "https://project.supabase.co",
        "sb_secret_server-only-key-material",
        undefined,
      ),
    ).toThrow(PostgrestCommandError);
    expect(() =>
      parsePostgrestConfig(
        "https://project.supabase.co",
        undefined,
        jwtForRole("service_role"),
      ),
    ).toThrow(PostgrestCommandError);
  });

  it("forwards the user bearer separately from the public project key", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([{ party_id: "party", replayed: false }]),
    );
    const gateway = new PostgrestAuthenticatedRpcGateway({
      fetchImplementation,
      publicKey: "sb_publishable_public_key_material",
      timeoutMilliseconds: 500,
      url: "http://127.0.0.1:54321",
    });

    await gateway.invoke({
      accessToken: "user.header.signature",
      functionName: "create_party",
      parameters: { p_workspace_id: "workspace" },
    });

    const [url, init] = fetchImplementation.mock.calls[0] ?? [];
    const headers = new Headers(init?.headers);
    expect(url).toBe("http://127.0.0.1:54321/rest/v1/rpc/create_party");
    expect(headers.get("apikey")).toBe("sb_publishable_public_key_material");
    expect(headers.get("authorization")).toBe("Bearer user.header.signature");
    expect(headers.get("content-profile")).toBe("app");
    expect(init?.signal).toBeInstanceOf(AbortSignal);
    expect(init?.cache).toBe("no-store");
  });

  it.each([
    [401, "PGRST301", 401, "authentication_required"],
    [400, "42501", 403, "permission_denied"],
    [400, "23505", 409, "conflict"],
    [400, "22023", 400, "invalid_request"],
    [400, "23514", 422, "unprocessable_command"],
    [429, "PGRST003", 429, "rate_limited"],
    [500, "XX000", 503, "service_unavailable"],
  ] as const)(
    "maps HTTP %s / SQLSTATE %s without exposing provider detail",
    async (responseStatus, sqlState, expectedStatus, expectedCode) => {
      const gateway = new PostgrestAuthenticatedRpcGateway({
        fetchImplementation: vi.fn<typeof fetch>(async () =>
          Response.json(
            {
              code: sqlState,
              details: "Bearer should-never-leak",
              message: "private database message",
            },
            { status: responseStatus },
          ),
        ),
        publicKey: "sb_publishable_public_key_material",
        url: "https://project.supabase.co",
      });

      const error = await gateway
        .invoke({
          accessToken: "user.header.signature",
          functionName: "create_party",
          parameters: {},
        })
        .catch((caught: unknown) => caught);

      expect(error).toBeInstanceOf(PostgrestCommandError);
      expect(error).toMatchObject({
        code: expectedCode,
        status: expectedStatus,
      });
      expect(JSON.stringify(error)).not.toContain("Bearer should-never-leak");
      if (!(error instanceof Error)) {
        throw new TypeError("Expected a safe PostgREST error.");
      }
      expect(error.message).not.toContain("database message");
    },
  );

  it("maps network failures and malformed success bodies to availability errors", async () => {
    const networkGateway = new PostgrestAuthenticatedRpcGateway({
      fetchImplementation: vi.fn<typeof fetch>(async () => {
        throw new Error("socket included credential material");
      }),
      publicKey: "sb_publishable_public_key_material",
      url: "https://project.supabase.co",
    });
    await expect(
      networkGateway.invoke({
        accessToken: "user.header.signature",
        functionName: "create_party",
        parameters: {},
      }),
    ).rejects.toMatchObject({ code: "service_unavailable", status: 503 });

    const invalidJsonGateway = new PostgrestAuthenticatedRpcGateway({
      fetchImplementation: vi.fn<typeof fetch>(
        async () =>
          new Response("not-json", {
            headers: { "Content-Type": "application/json" },
            status: 200,
          }),
      ),
      publicKey: "sb_publishable_public_key_material",
      url: "https://project.supabase.co",
    });
    await expect(
      invalidJsonGateway.invoke({
        accessToken: "user.header.signature",
        functionName: "create_party",
        parameters: {},
      }),
    ).rejects.toMatchObject({ code: "service_unavailable", status: 503 });
  });
});
