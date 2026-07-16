import { afterEach, describe, expect, it, vi } from "vitest";

import { GoTrueInvitationDeliveryProvider } from "./gotrue-invitation-delivery-provider";

const invitationId = "40000000-0000-4000-8000-000000000001";
const workspaceId = "40000000-0000-4000-8000-000000000002";
const email = "invited@example.test";
const serviceRoleKey = "service-role-value-xxxxxxxxxxxx";

function provider(
  fetchImplementation: typeof fetch,
  overrides: Partial<
    ConstructorParameters<typeof GoTrueInvitationDeliveryProvider>[0]
  > = {},
) {
  return new GoTrueInvitationDeliveryProvider({
    appUrl: "http://localhost:3000",
    fetchImplementation,
    serviceRoleKey,
    supabaseUrl: "http://127.0.0.1:54321",
    timeoutMs: 10_000,
    ...overrides,
  });
}

function input(signal = new AbortController().signal) {
  return {
    email,
    invitationId,
    providerIdentityExists: false,
    signal,
    workspaceId,
  };
}

afterEach(() => {
  vi.useRealTimers();
});

describe("GoTrueInvitationDeliveryProvider", () => {
  it("uses the admin invite endpoint with only email and a safe app redirect", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(
        {
          email,
          hashed_token: "must-never-be-observed",
          user: { id: "provider-user-id" },
        },
        { headers: { "x-request-id": "provider-request-1" } },
      ),
    );

    const result = await provider(fetchImplementation).deliver(input());

    expect(result).toEqual({ providerRequestId: "provider-request-1" });
    expect(JSON.stringify(result)).not.toContain(email);
    expect(JSON.stringify(result)).not.toContain("must-never-be-observed");
    const [request, init] = fetchImplementation.mock.calls[0] ?? [];
    const endpoint = new URL(String(request));
    expect(endpoint.pathname).toBe("/auth/v1/invite");
    expect(endpoint.pathname).not.toContain("generate_link");
    expect(endpoint.searchParams.get("redirect_to")).toBe(
      `http://localhost:3000/login?invitation=${invitationId}&workspace=${workspaceId}`,
    );
    expect(JSON.parse(String(init?.body))).toEqual({ email });
    expect(init?.method).toBe("POST");
    const headers = new Headers(init?.headers);
    expect(headers.get("authorization")).toBe(`Bearer ${serviceRoleKey}`);
    expect(headers.get("apikey")).toBe(serviceRoleKey);
    expect(headers.get("content-type")).toBe("application/json;charset=UTF-8");
  });

  it("sends an existing identity a non-creating passwordless callback", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json({ generated_value: "must-never-be-observed" }),
    );

    const result = await provider(fetchImplementation).deliver({
      ...input(),
      providerIdentityExists: true,
    });

    expect(result).toEqual({});
    expect(JSON.stringify(result)).not.toContain("must-never-be-observed");

    const [request, init] = fetchImplementation.mock.calls[0] ?? [];
    const endpoint = new URL(String(request));
    expect(endpoint.pathname).toBe("/auth/v1/otp");
    expect(endpoint.searchParams.get("redirect_to")).toBe(
      `http://localhost:3000/login?invitation=${invitationId}&workspace=${workspaceId}`,
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      code_challenge: null,
      code_challenge_method: null,
      create_user: false,
      data: {},
      email,
      gotrue_meta_security: {},
    });
    const headers = new Headers(init?.headers);
    expect(headers.get("authorization")).toBe(`Bearer ${serviceRoleKey}`);
    expect(headers.get("apikey")).toBe(serviceRoleKey);
  });

  it("enforces a bounded provider timeout", async () => {
    vi.useFakeTimers();
    const fetchImplementation = vi.fn<typeof fetch>(
      async (_request, init) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener(
            "abort",
            () => reject(new DOMException("private", "AbortError")),
            { once: true },
          );
        }),
    );
    const delivery = provider(fetchImplementation, { timeoutMs: 1_000 })
      .deliver(input())
      .catch((error: unknown) => error);

    await vi.advanceTimersByTimeAsync(1_000);

    await expect(delivery).resolves.toMatchObject({
      classification: "transient",
      code: "auth.invitation_provider_timeout",
    });
  });

  it("stops on worker cancellation without exposing the abort reason", async () => {
    const abort = new AbortController();
    const fetchImplementation = vi.fn<typeof fetch>(
      async (_request, init) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener(
            "abort",
            () => reject(new DOMException("private", "AbortError")),
            { once: true },
          );
        }),
    );
    const delivery = provider(fetchImplementation)
      .deliver(input(abort.signal))
      .catch((error: unknown) => error);

    abort.abort("private cancellation reason");

    await expect(delivery).resolves.toMatchObject({
      classification: "transient",
      code: "auth.invitation_provider_cancelled",
    });
    expect(JSON.stringify(await delivery)).not.toContain("private");
  });

  it.each([
    [401, "provider_auth", "auth.invitation_provider_access_denied"],
    [422, "transient", "auth.invitation_provider_identity_conflict"],
    [503, "transient", "auth.invitation_provider_temporarily_unavailable"],
  ])(
    "classifies provider status %i as %s",
    async (status, classification, code) => {
      const fetchImplementation = vi.fn<typeof fetch>(
        async () =>
          new Response(
            JSON.stringify({
              email,
              hashed_token: "private-value",
              message: "private response detail",
            }),
            { status },
          ),
      );

      const error = await provider(fetchImplementation)
        .deliver(input())
        .catch((caught: unknown) => caught);

      expect(error).toMatchObject({ classification, code });
      expect(JSON.stringify(error)).not.toContain(email);
      expect(JSON.stringify(error)).not.toContain("private response detail");
      expect(JSON.stringify(error)).not.toContain("private-value");
    },
  );

  it("preserves a bounded provider retry hint", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(
      async () =>
        new Response(null, {
          headers: {
            "retry-after": "120",
            "x-request-id": "provider-request-2",
          },
          status: 429,
        }),
    );

    await expect(
      provider(fetchImplementation).deliver(input()),
    ).rejects.toMatchObject({
      classification: "rate_limited",
      code: "auth.invitation_provider_rate_limited",
      providerRequestId: "provider-request-2",
      retryAfterSeconds: 120,
    });
  });

  it("rejects insecure remote origins and malformed routing context", async () => {
    expect(
      () =>
        new GoTrueInvitationDeliveryProvider({
          appUrl: "http://app.example.test",
          fetchImplementation: vi.fn<typeof fetch>(),
          serviceRoleKey,
          supabaseUrl: "https://project.example.test",
          timeoutMs: 10_000,
        }),
    ).toThrow(/HTTPS/u);

    const fetchImplementation = vi.fn<typeof fetch>();
    await expect(
      provider(fetchImplementation).deliver({
        ...input(),
        invitationId: "not-a-uuid",
      }),
    ).rejects.toMatchObject({ classification: "validation" });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });
});
