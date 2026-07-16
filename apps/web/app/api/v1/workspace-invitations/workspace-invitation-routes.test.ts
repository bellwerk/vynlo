import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { POST as acceptInvitation } from "./accept/route";
import { POST as createInvitation } from "./route";

const workspaceId = "00000000-0000-4000-8000-000000000001";
const correlationId = "00000000-0000-4000-8000-000000000002";
const invitationId = "00000000-0000-4000-8000-000000000003";
const roleIdOne = "00000000-0000-4000-8000-000000000004";
const roleIdTwo = "00000000-0000-4000-8000-000000000005";
const outboxEventId = "00000000-0000-4000-8000-000000000006";
const jobId = "00000000-0000-4000-8000-000000000007";
const membershipId = "00000000-0000-4000-8000-000000000008";
const userAccessToken = "user-header.user-payload.user-signature";
const publicProjectKey = "sb_publishable_public_project_key_material_0001";
const serviceRoleSecret = "server-service-role-must-never-be-used";

const createBody = Object.freeze({
  email: "invited.user@example.invalid",
  expiresAt: "2026-07-20T18:00:00Z",
  requestedLocale: "fr-CA",
  roleIds: [roleIdOne, roleIdTwo],
});

function commandRequest(path: string, body: unknown): Request {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: {
      Authorization: `Bearer ${userAccessToken}`,
      "Content-Type": "application/json",
      "Idempotency-Key": "invite-command-0001",
      "X-Correlation-Id": correlationId,
      "X-Request-Id": "request-0001",
      "X-Workspace-Id": workspaceId,
    },
    method: "POST",
  });
}

function assertForwardedRequest(
  fetchImplementation: ReturnType<typeof vi.fn<typeof fetch>>,
  functionName: string,
): Record<string, unknown> {
  const [url, init] = fetchImplementation.mock.calls[0] ?? [];
  const headers = new Headers(init?.headers);
  expect(url).toBe(`http://127.0.0.1:54321/rest/v1/rpc/${functionName}`);
  expect(headers.get("apikey")).toBe(publicProjectKey);
  expect(headers.get("authorization")).toBe(`Bearer ${userAccessToken}`);
  expect(headers.get("accept-profile")).toBe("app");
  expect(headers.get("content-profile")).toBe("app");
  expect(headers.get("apikey")).not.toBe(serviceRoleSecret);
  const parsed: unknown = JSON.parse(String(init?.body));
  return z.record(z.string(), z.unknown()).parse(parsed);
}

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", publicProjectKey);
  vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", serviceRoleSecret);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("invite-only authentication routes", () => {
  it("queues a pending invitation through the exact app-schema RPC contract", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          invitation_id: invitationId,
          invitation_status: "pending",
          job_id: jobId,
          job_status: "queued",
          outbox_event_id: outboxEventId,
          replayed: false,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createInvitation(
      commandRequest("/api/v1/workspace-invitations", createBody),
    );

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toEqual({
      data: {
        invitationId,
        invitationStatus: "pending",
        jobId,
        jobStatus: "queued",
        outboxEventId,
        replayed: false,
      },
    });
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-request-id")).toBe("request-0001");
    expect(response.headers.get("x-correlation-id")).toBe(correlationId);
    expect(
      assertForwardedRequest(
        fetchImplementation,
        "create_workspace_invitation_job",
      ),
    ).toEqual({
      p_correlation_id: correlationId,
      p_email: createBody.email,
      p_expires_at: "2026-07-20T18:00:00.000Z",
      p_idempotency_key: "invite-command-0001",
      p_request_id: "request-0001",
      p_requested_locale: "fr-CA",
      p_role_ids: [roleIdOne, roleIdTwo],
      p_workspace_id: workspaceId,
    });
  });

  it("returns 200 for an idempotent invitation replay", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(async () =>
        Response.json([
          {
            invitation_id: invitationId,
            invitation_status: "pending",
            job_id: jobId,
            job_status: "queued",
            outbox_event_id: outboxEventId,
            replayed: true,
          },
        ]),
      ),
    );

    const response = await createInvitation(
      commandRequest("/api/v1/workspace-invitations", createBody),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: { invitationId, replayed: true },
    });
  });

  it("accepts a matching authenticated invitation without accepting identity fields", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          invitation_id: invitationId,
          invitation_status: "accepted",
          membership_id: membershipId,
          replayed: false,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await acceptInvitation(
      commandRequest("/api/v1/workspace-invitations/accept", {
        invitationId,
      }),
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({
      data: {
        invitationId,
        invitationStatus: "accepted",
        membershipId,
        replayed: false,
      },
    });
    expect(
      assertForwardedRequest(
        fetchImplementation,
        "accept_workspace_invitation",
      ),
    ).toEqual({
      p_correlation_id: correlationId,
      p_idempotency_key: "invite-command-0001",
      p_invitation_id: invitationId,
      p_request_id: "request-0001",
      p_workspace_id: workspaceId,
    });
  });

  it.each([
    ["workspace authority", { ...createBody, workspaceId }],
    ["provider token", { ...createBody, token: "not-an-api-input" }],
    ["duplicate roles", { ...createBody, roleIds: [roleIdOne, roleIdOne] }],
    ["invalid email", { ...createBody, email: "not-an-email" }],
  ])("rejects %s in the body before PostgREST", async (_label, body) => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createInvitation(
      commandRequest("/api/v1/workspace-invitations", body),
    );

    expect(response.status).toBe(422);
    await expect(response.json()).resolves.toEqual({
      error: {
        code: "invalid_request_body",
        message: "The command body is invalid.",
      },
    });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("maps database MFA and permission rejection to a safe 403 envelope", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(async () =>
        Response.json(
          {
            code: "42501",
            details: serviceRoleSecret,
            message: `private ${userAccessToken}`,
          },
          { status: 400 },
        ),
      ),
    );

    const response = await createInvitation(
      commandRequest("/api/v1/workspace-invitations", createBody),
    );
    const serialized = JSON.stringify(await response.json());

    expect(response.status).toBe(403);
    expect(JSON.parse(serialized)).toEqual({
      error: {
        code: "permission_denied",
        message: "The command is not permitted.",
      },
    });
    expect(serialized).not.toContain(serviceRoleSecret);
    expect(serialized).not.toContain(userAccessToken);
  });

  it("fails closed when an RPC success includes provider token material", async () => {
    const providerToken = "provider-invite-token-must-not-cross-api";
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(async () =>
        Response.json([
          {
            invitation_id: invitationId,
            invitation_status: "pending",
            invite_token: providerToken,
            job_id: jobId,
            job_status: "queued",
            outbox_event_id: outboxEventId,
            replayed: false,
          },
        ]),
      ),
    );

    const response = await createInvitation(
      commandRequest("/api/v1/workspace-invitations", createBody),
    );
    const serialized = JSON.stringify(await response.json());

    expect(response.status).toBe(503);
    expect(serialized).toContain("service_unavailable");
    expect(serialized).not.toContain(providerToken);
  });
});
