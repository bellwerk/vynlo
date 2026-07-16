// Stable test IDs: T-AUTH-001, T-JOB-001, T-JOB-003.
import { describe, expect, it, vi } from "vitest";

import { PostgrestInvitationDeliveryRepository } from "./invitation-delivery-repository";

const invitationId = "30000000-0000-4000-8000-000000000001";
const workspaceId = "30000000-0000-4000-8000-000000000002";
const jobId = "30000000-0000-4000-8000-000000000003";
const leaseToken = "30000000-0000-4000-8000-000000000004";
const serviceRoleKey = "service-role-value-xxxxxxxxxxxx";

function row(overrides: Readonly<Record<string, unknown>> = {}) {
  return {
    email: "invited@example.test",
    expires_at: "2026-07-17T12:00:00.000Z",
    invitation_id: invitationId,
    provider_identity_exists: false,
    requested_locale: "en-CA",
    workspace_id: workspaceId,
    ...overrides,
  };
}

function repository(fetchImplementation: typeof fetch) {
  return new PostgrestInvitationDeliveryRepository({
    fetchImplementation,
    serviceRoleKey,
    supabaseUrl: "http://127.0.0.1:54321",
  });
}

describe("PostgrestInvitationDeliveryRepository", () => {
  it("reloads the job through the service-only lease-fenced RPC", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([row()]),
    );
    const signal = new AbortController().signal;

    const result = await repository(fetchImplementation).readDeliveryJob({
      jobId,
      leaseToken,
      signal,
      workerId: "invitation-worker-1",
    });

    expect(result).toEqual({
      email: "invited@example.test",
      expiresAt: "2026-07-17T12:00:00.000Z",
      invitationId,
      providerIdentityExists: false,
      requestedLocale: "en-CA",
      workspaceId,
    });
    const [url, init] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/read_invitation_delivery_job",
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      p_job_id: jobId,
      p_lease_token: leaseToken,
      p_worker_id: "invitation-worker-1",
    });
    expect(init?.signal).toBe(signal);
    const headers = new Headers(init?.headers);
    expect(headers.get("content-profile")).toBe("app");
    expect(headers.get("authorization")).toBe(`Bearer ${serviceRoleKey}`);
    expect(headers.get("apikey")).toBe(serviceRoleKey);
  });

  it("accepts the authoritative existing-provider-identity flag", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([row({ provider_identity_exists: true })]),
    );

    await expect(
      repository(fetchImplementation).readDeliveryJob({
        jobId,
        leaseToken,
        signal: new AbortController().signal,
        workerId: "invitation-worker-1",
      }),
    ).resolves.toMatchObject({ providerIdentityExists: true });
  });

  it.each([
    ["more than one row", [row(), row()]],
    ["extra field", [row({ unexpected: true })]],
    ["invalid email", [row({ email: "not-an-email" })]],
    ["invalid identity flag", [row({ provider_identity_exists: "true" })]],
  ])("fails closed on %s", async (_label, value) => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(value),
    );

    await expect(
      repository(fetchImplementation).readDeliveryJob({
        jobId,
        leaseToken,
        signal: new AbortController().signal,
        workerId: "invitation-worker-1",
      }),
    ).rejects.toMatchObject({
      classification: "permanent",
      code: "auth.invitation_invalid_database_contract",
    });
  });

  it("classifies ineligible terminal invitation state without response leakage", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(
      async () =>
        new Response(
          JSON.stringify({
            email: "invited@example.test",
            message: "terminal invitation detail",
          }),
          { status: 400 },
        ),
    );

    const error = await repository(fetchImplementation)
      .readDeliveryJob({
        jobId,
        leaseToken,
        signal: new AbortController().signal,
        workerId: "invitation-worker-1",
      })
      .catch((caught: unknown) => caught);

    expect(error).toMatchObject({
      classification: "validation",
      code: "auth.invitation_delivery_state_rejected",
    });
    expect(JSON.stringify(error)).not.toContain("invited@example.test");
    expect(JSON.stringify(error)).not.toContain("terminal invitation detail");
  });

  it("classifies transport and temporary database failures for durable retry", async () => {
    const transport = repository(
      vi.fn<typeof fetch>(async () => {
        throw new TypeError("private transport detail");
      }),
    );
    await expect(
      transport.readDeliveryJob({
        jobId,
        leaseToken,
        signal: new AbortController().signal,
        workerId: "invitation-worker-1",
      }),
    ).rejects.toMatchObject({ classification: "transient" });

    const unavailable = repository(
      vi.fn<typeof fetch>(async () => new Response("private", { status: 503 })),
    );
    await expect(
      unavailable.readDeliveryJob({
        jobId,
        leaseToken,
        signal: new AbortController().signal,
        workerId: "invitation-worker-1",
      }),
    ).rejects.toMatchObject({
      classification: "transient",
      code: "auth.invitation_database_temporarily_unavailable",
    });
  });
});
