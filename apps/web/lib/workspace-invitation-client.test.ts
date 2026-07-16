import { describe, expect, it, vi } from "vitest";
import {
  acceptWorkspaceInvitationSession,
  parseWorkspaceInvitationContext,
  workspaceInvitationLoginRedirect,
} from "./workspace-invitation-client";

const invitationId = "00000000-0000-4000-8000-000000000001";
const workspaceId = "00000000-0000-4000-8000-000000000002";

describe("workspace invitation browser boundary", () => {
  it("accepts one exact pair of UUID routing identifiers", () => {
    expect(
      parseWorkspaceInvitationContext({
        invitation: invitationId.toUpperCase(),
        workspace: workspaceId.toUpperCase(),
      }),
    ).toEqual({
      context: { invitationId, workspaceId },
      invalid: false,
    });
    expect(
      parseWorkspaceInvitationContext({ invitation: invitationId }),
    ).toEqual({ context: null, invalid: true });
    expect(
      parseWorkspaceInvitationContext({
        invitation: [invitationId, invitationId],
        workspace: workspaceId,
      }),
    ).toEqual({ context: null, invalid: true });
    expect(parseWorkspaceInvitationContext({})).toEqual({
      context: null,
      invalid: false,
    });
  });

  it("builds a same-origin login callback with routing identifiers only", () => {
    expect(
      workspaceInvitationLoginRedirect("https://app.example.test/current", {
        invitationId,
        workspaceId,
      }),
    ).toBe(
      `https://app.example.test/login?invitation=${invitationId}&workspace=${workspaceId}`,
    );
  });

  it("accepts only after authentication and never forwards email or provider token material", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json({ data: { invitationId, membershipId: workspaceId } }),
    );
    const identifiers = [
      "00000000-0000-4000-8000-000000000003",
      "request-0001",
    ];

    await acceptWorkspaceInvitationSession({
      accessToken: "user.header.signature",
      context: { invitationId, workspaceId },
      fetchImplementation,
      randomUuid: () => identifiers.shift() ?? "unexpected",
    });

    const [url, init] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe("/api/v1/workspace-invitations/accept");
    expect(init?.method).toBe("POST");
    expect(JSON.parse(String(init?.body))).toEqual({ invitationId });
    expect(String(init?.body)).not.toMatch(/email|token/iu);
    const headers = new Headers(init?.headers);
    expect(headers.get("authorization")).toBe("Bearer user.header.signature");
    expect(headers.get("idempotency-key")).toBe(
      `accept-invitation-${invitationId}`,
    );
    expect(headers.get("x-correlation-id")).toBe(
      "00000000-0000-4000-8000-000000000003",
    );
    expect(headers.get("x-request-id")).toBe("request-0001");
    expect(headers.get("x-workspace-id")).toBe(workspaceId);
  });

  it("fails closed when the acceptance command is rejected", async () => {
    await expect(
      acceptWorkspaceInvitationSession({
        accessToken: "user.header.signature",
        context: { invitationId, workspaceId },
        fetchImplementation: async () => Response.json({}, { status: 403 }),
      }),
    ).rejects.toThrow("invitation_acceptance_failed");
  });
});
