import { describe, expect, it } from "vitest";
import type {
  AuthenticatedRpcGateway,
  AuthenticatedRpcRequest,
} from "./vertical-slice-api";
import {
  WorkspaceInvitationApplicationService,
  WorkspaceInvitationRpcContractError,
  WorkspaceInvitationValidationError,
} from "./workspace-invitations-api";

const workspaceId = "00000000-0000-4000-8000-000000000001";
const correlationId = "00000000-0000-4000-8000-000000000002";
const invitationId = "00000000-0000-4000-8000-000000000003";
const roleIdOne = "00000000-0000-4000-8000-000000000004";
const roleIdTwo = "00000000-0000-4000-8000-000000000005";
const outboxEventId = "00000000-0000-4000-8000-000000000006";
const jobId = "00000000-0000-4000-8000-000000000007";
const membershipId = "00000000-0000-4000-8000-000000000008";

const metadata = Object.freeze({
  accessToken: "header.payload.signature",
  correlationId,
  idempotencyKey: "invite-command-0001",
  requestId: "request-0001",
  workspaceId,
});

class RecordingGateway implements AuthenticatedRpcGateway {
  readonly requests: AuthenticatedRpcRequest[] = [];

  constructor(readonly response: unknown) {}

  async invoke(request: AuthenticatedRpcRequest): Promise<unknown> {
    this.requests.push(request);
    return this.response;
  }
}

describe("WorkspaceInvitationApplicationService", () => {
  it("normalizes the invite and invokes the atomic delivery-job RPC", async () => {
    const gateway = new RecordingGateway([
      {
        invitation_id: invitationId,
        invitation_status: "pending",
        job_id: jobId,
        job_status: "queued",
        outbox_event_id: outboxEventId,
        replayed: false,
      },
    ]);
    const service = new WorkspaceInvitationApplicationService(gateway);

    await expect(
      service.createWorkspaceInvitation({
        body: {
          email: "  Invited.User@Example.Invalid ",
          expiresAt: "2026-07-20T10:30:00-04:00",
          requestedLocale: "fr-ca",
          roleIds: [roleIdTwo.toUpperCase(), roleIdOne],
        },
        metadata,
      }),
    ).resolves.toEqual({
      invitationId,
      invitationStatus: "pending",
      jobId,
      jobStatus: "queued",
      outboxEventId,
      replayed: false,
    });

    expect(gateway.requests).toEqual([
      {
        accessToken: metadata.accessToken,
        functionName: "create_workspace_invitation_job",
        parameters: {
          p_correlation_id: correlationId,
          p_email: "invited.user@example.invalid",
          p_expires_at: "2026-07-20T14:30:00.000Z",
          p_idempotency_key: metadata.idempotencyKey,
          p_request_id: metadata.requestId,
          p_requested_locale: "fr-CA",
          p_role_ids: [roleIdOne, roleIdTwo],
          p_workspace_id: workspaceId,
        },
      },
    ]);
  });

  it("accepts only an invitation identifier and maps an idempotent replay", async () => {
    const gateway = new RecordingGateway([
      {
        invitation_id: invitationId,
        invitation_status: "accepted",
        membership_id: membershipId,
        replayed: true,
      },
    ]);
    const service = new WorkspaceInvitationApplicationService(gateway);

    await expect(
      service.acceptWorkspaceInvitation({
        body: { invitationId: invitationId.toUpperCase() },
        metadata,
      }),
    ).resolves.toEqual({
      invitationId,
      invitationStatus: "accepted",
      membershipId,
      replayed: true,
    });
    expect(gateway.requests).toEqual([
      {
        accessToken: metadata.accessToken,
        functionName: "accept_workspace_invitation",
        parameters: {
          p_correlation_id: correlationId,
          p_idempotency_key: metadata.idempotencyKey,
          p_invitation_id: invitationId,
          p_request_id: metadata.requestId,
          p_workspace_id: workspaceId,
        },
      },
    ]);
  });

  it.each([
    [
      "an invalid email",
      {
        email: "not-an-email",
        expiresAt: "2026-07-20T10:30:00Z",
        requestedLocale: "en-CA",
        roleIds: [roleIdOne],
      },
    ],
    [
      "an empty role set",
      {
        email: "invited@example.invalid",
        expiresAt: "2026-07-20T10:30:00Z",
        requestedLocale: "en-CA",
        roleIds: [],
      },
    ],
    [
      "duplicate role identifiers",
      {
        email: "invited@example.invalid",
        expiresAt: "2026-07-20T10:30:00Z",
        requestedLocale: "en-CA",
        roleIds: [roleIdOne, roleIdOne.toUpperCase()],
      },
    ],
    [
      "more than 32 role identifiers",
      {
        email: "invited@example.invalid",
        expiresAt: "2026-07-20T10:30:00Z",
        requestedLocale: "en-CA",
        roleIds: Array.from(
          { length: 33 },
          (_, index) =>
            `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
        ),
      },
    ],
    [
      "a non-BCP47 locale",
      {
        email: "invited@example.invalid",
        expiresAt: "2026-07-20T10:30:00Z",
        requestedLocale: "not_a_locale",
        roleIds: [roleIdOne],
      },
    ],
    [
      "a non-ISO expiry",
      {
        email: "invited@example.invalid",
        expiresAt: "next week",
        requestedLocale: "en-CA",
        roleIds: [roleIdOne],
      },
    ],
    [
      "workspace authority in the body",
      {
        email: "invited@example.invalid",
        expiresAt: "2026-07-20T10:30:00Z",
        requestedLocale: "en-CA",
        roleIds: [roleIdOne],
        workspaceId,
      },
    ],
    [
      "a provider token field",
      {
        email: "invited@example.invalid",
        expiresAt: "2026-07-20T10:30:00Z",
        requestedLocale: "en-CA",
        roleIds: [roleIdOne],
        token: "must-never-cross-this-boundary",
      },
    ],
  ])("rejects %s before invoking the RPC", async (_label, body) => {
    const gateway = new RecordingGateway([]);
    const service = new WorkspaceInvitationApplicationService(gateway);

    await expect(
      service.createWorkspaceInvitation({ body, metadata }),
    ).rejects.toBeInstanceOf(WorkspaceInvitationValidationError);
    expect(gateway.requests).toEqual([]);
  });

  it("rejects owner or token fields on acceptance before invoking the RPC", async () => {
    const gateway = new RecordingGateway([]);
    const service = new WorkspaceInvitationApplicationService(gateway);

    await expect(
      service.acceptWorkspaceInvitation({
        body: {
          invitationId,
          token: "provider-token-must-remain-with-gotrue",
          userId: membershipId,
        },
        metadata,
      }),
    ).rejects.toBeInstanceOf(WorkspaceInvitationValidationError);
    expect(gateway.requests).toEqual([]);
  });

  it.each([
    [
      "wrong invitation state",
      [
        {
          invitation_id: invitationId,
          invitation_status: "accepted",
          job_id: jobId,
          job_status: "queued",
          outbox_event_id: outboxEventId,
          replayed: false,
        },
      ],
    ],
    [
      "unexpected token material",
      [
        {
          invitation_id: invitationId,
          invitation_status: "pending",
          invite_token: "must-not-be-returned",
          job_id: jobId,
          job_status: "queued",
          outbox_event_id: outboxEventId,
          replayed: false,
        },
      ],
    ],
    ["more than one result row", [{ invitation_id: invitationId }, {}]],
  ])("fails closed on %s in the RPC response", async (_label, response) => {
    const service = new WorkspaceInvitationApplicationService(
      new RecordingGateway(response),
    );

    await expect(
      service.createWorkspaceInvitation({
        body: {
          email: "invited@example.invalid",
          expiresAt: "2026-07-20T10:30:00Z",
          requestedLocale: "en-CA",
          roleIds: [roleIdOne],
        },
        metadata,
      }),
    ).rejects.toBeInstanceOf(WorkspaceInvitationRpcContractError);
  });
});
