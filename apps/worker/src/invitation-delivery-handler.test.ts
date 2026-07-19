// Stable test IDs: T-AUTH-001, T-JOB-003.
import { describe, expect, it, vi } from "vitest";

import type { ClaimedJob } from "./job-store";
import {
  createInvitationDeliveryJobHandler,
  type AuthoritativeInvitationDelivery,
  type InvitationDeliveryProvider,
  type InvitationDeliveryRepository,
} from "./invitation-delivery-handler";
import { JobExecutionError } from "./job-runner";

const workspaceId = "20000000-0000-4000-8000-000000000001";
const invitationId = "20000000-0000-4000-8000-000000000002";
const jobId = "20000000-0000-4000-8000-000000000003";
const leaseToken = "20000000-0000-4000-8000-000000000004";
const workerId = "worker-invitations-1";

function job(overrides: Partial<ClaimedJob> = {}): ClaimedJob {
  return {
    attemptNumber: 1,
    causationId: null,
    correlationId: "20000000-0000-4000-8000-000000000005",
    entityId: invitationId,
    entityType: "workspace_invitation",
    idempotencyKey: "invitation-request-1",
    jobId,
    jobType: "auth.invitation.deliver",
    leaseExpiresAt: "2026-07-16T12:01:00.000Z",
    leaseToken,
    maximumAttempts: 8,
    outboxEventId: "20000000-0000-4000-8000-000000000006",
    payload: { invitation_id: invitationId },
    payloadSchemaVersion: 1,
    workspaceId,
    ...overrides,
  };
}

function invitation(
  overrides: Partial<AuthoritativeInvitationDelivery> = {},
): AuthoritativeInvitationDelivery {
  return {
    email: "invited@example.test",
    expiresAt: "2026-07-17T12:00:00.000Z",
    invitationId,
    providerIdentityExists: false,
    requestedLocale: "en-CA",
    workspaceId,
    ...overrides,
  };
}

function dependencies() {
  const repository: InvitationDeliveryRepository = {
    readDeliveryJob: vi.fn(async () => invitation()),
  };
  const provider: InvitationDeliveryProvider = {
    deliver: vi.fn(async () => ({ providerRequestId: "provider-request-1" })),
  };
  return { provider, repository };
}

describe("auth.invitation.deliver handler", () => {
  it("reloads authoritative state and submits only the invited identity", async () => {
    const { provider, repository } = dependencies();
    const handler = createInvitationDeliveryJobHandler({
      provider,
      repository,
      workerId,
    });
    const signal = new AbortController().signal;

    const result = await handler(job(), { signal });

    expect(repository.readDeliveryJob).toHaveBeenCalledWith({
      jobId,
      leaseToken,
      signal,
      workerId,
    });
    expect(provider.deliver).toHaveBeenCalledWith({
      email: "invited@example.test",
      invitationId,
      providerIdentityExists: false,
      signal,
      workspaceId,
    });
    expect(result).toEqual({
      providerRequestId: "provider-request-1",
      summary: {
        delivery_outcome: "submitted",
        invitation_id: invitationId,
      },
    });
    expect(JSON.stringify(result)).not.toContain("invited@example.test");
  });

  it("sends an existing provider identity a passwordless callback", async () => {
    const { provider, repository } = dependencies();
    vi.mocked(repository.readDeliveryJob).mockResolvedValueOnce(
      invitation({ providerIdentityExists: true }),
    );
    const handler = createInvitationDeliveryJobHandler({
      provider,
      repository,
      workerId,
    });

    const signal = new AbortController().signal;
    await expect(
      handler(job({ attemptNumber: 2 }), { signal }),
    ).resolves.toEqual({
      providerRequestId: "provider-request-1",
      summary: {
        delivery_outcome: "submitted",
        invitation_id: invitationId,
      },
    });
    expect(provider.deliver).toHaveBeenCalledWith({
      email: "invited@example.test",
      invitationId,
      providerIdentityExists: true,
      signal,
      workspaceId,
    });
  });

  it("switches an ambiguous invite retry to existing-identity delivery", async () => {
    const { provider, repository } = dependencies();
    vi.mocked(repository.readDeliveryJob)
      .mockResolvedValueOnce(invitation({ providerIdentityExists: false }))
      .mockResolvedValueOnce(invitation({ providerIdentityExists: true }));
    vi.mocked(provider.deliver)
      .mockRejectedValueOnce(
        new JobExecutionError({
          classification: "transient",
          code: "auth.invitation_provider_timeout",
          safeDetail: "The identity provider request exceeded its time limit.",
        }),
      )
      .mockResolvedValueOnce({});
    const handler = createInvitationDeliveryJobHandler({
      provider,
      repository,
      workerId,
    });

    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "transient",
      code: "auth.invitation_provider_timeout",
    });
    await expect(
      handler(job({ attemptNumber: 2 }), {
        signal: new AbortController().signal,
      }),
    ).resolves.toMatchObject({
      summary: { delivery_outcome: "submitted" },
    });

    expect(vi.mocked(provider.deliver).mock.calls).toEqual([
      [expect.objectContaining({ providerIdentityExists: false })],
      [expect.objectContaining({ providerIdentityExists: true })],
    ]);
  });

  it.each([
    [
      "extra payload field",
      { payload: { invitation_id: invitationId, email: "x@example.test" } },
    ],
    ["wrong schema", { payloadSchemaVersion: 2 }],
    ["wrong entity type", { entityType: "user" }],
    ["wrong entity id", { entityId: "20000000-0000-4000-8000-000000000099" }],
    ["wrong job type", { jobType: "auth.invitation.preview" }],
  ])("rejects %s before authoritative access", async (_label, overrides) => {
    const { provider, repository } = dependencies();
    const handler = createInvitationDeliveryJobHandler({
      provider,
      repository,
      workerId,
    });

    await expect(
      handler(job(overrides), { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "validation",
      code: "auth.invitation_invalid_job_payload",
    });
    expect(repository.readDeliveryJob).not.toHaveBeenCalled();
    expect(provider.deliver).not.toHaveBeenCalled();
  });

  it("fails closed when authoritative workspace state differs from the claim", async () => {
    const { provider, repository } = dependencies();
    vi.mocked(repository.readDeliveryJob).mockResolvedValueOnce(
      invitation({
        workspaceId: "20000000-0000-4000-8000-000000000099",
      }),
    );
    const handler = createInvitationDeliveryJobHandler({
      provider,
      repository,
      workerId,
    });

    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "permanent",
      code: "auth.invitation_authoritative_state_mismatch",
    });
    expect(provider.deliver).not.toHaveBeenCalled();
  });
});
