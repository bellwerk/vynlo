import type { ClaimedJob } from "./job-store";
import { JobExecutionError, type JobHandler } from "./job-runner";

export const INVITATION_DELIVERY_JOB_TYPE = "auth.invitation.deliver" as const;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;

export interface InvitationDeliveryJobPayload {
  readonly invitationId: string;
}

export interface AuthoritativeInvitationDelivery {
  readonly email: string;
  readonly expiresAt: string;
  readonly invitationId: string;
  readonly providerIdentityExists: boolean;
  readonly requestedLocale: string;
  readonly workspaceId: string;
}

export interface InvitationDeliveryRepository {
  readDeliveryJob(input: {
    readonly jobId: string;
    readonly leaseToken: string;
    readonly signal: AbortSignal;
    readonly workerId: string;
  }): Promise<AuthoritativeInvitationDelivery>;
}

export interface InvitationDeliveryProviderReceipt {
  readonly providerRequestId?: string | undefined;
}

export interface InvitationDeliveryProvider {
  deliver(input: {
    readonly email: string;
    readonly invitationId: string;
    readonly providerIdentityExists: boolean;
    readonly signal: AbortSignal;
    readonly workspaceId: string;
  }): Promise<InvitationDeliveryProviderReceipt>;
}

function invalidPayload(): never {
  throw new JobExecutionError({
    classification: "validation",
    code: "auth.invitation_invalid_job_payload",
    safeDetail:
      "The invitation delivery job does not match schema version one.",
  });
}

export function parseInvitationDeliveryJobPayload(input: {
  readonly entityId: string | null;
  readonly entityType: string;
  readonly jobType: string;
  readonly payload: Readonly<Record<string, unknown>>;
  readonly payloadSchemaVersion: number;
}): InvitationDeliveryJobPayload {
  if (
    input.jobType !== INVITATION_DELIVERY_JOB_TYPE ||
    input.entityType !== "workspace_invitation" ||
    input.payloadSchemaVersion !== 1 ||
    Object.keys(input.payload).length !== 1 ||
    !Object.hasOwn(input.payload, "invitation_id") ||
    typeof input.payload.invitation_id !== "string" ||
    !uuidPattern.test(input.payload.invitation_id) ||
    input.entityId !== input.payload.invitation_id
  ) {
    invalidPayload();
  }

  return { invitationId: input.payload.invitation_id };
}

export function createInvitationDeliveryJobHandler(input: {
  readonly provider: InvitationDeliveryProvider;
  readonly repository: InvitationDeliveryRepository;
  readonly workerId: string;
}): JobHandler {
  return async (job: ClaimedJob, context) => {
    const payload = parseInvitationDeliveryJobPayload(job);
    const invitation = await input.repository.readDeliveryJob({
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      signal: context.signal,
      workerId: input.workerId,
    });

    if (
      invitation.invitationId !== payload.invitationId ||
      invitation.workspaceId !== job.workspaceId
    ) {
      throw new JobExecutionError({
        classification: "permanent",
        code: "auth.invitation_authoritative_state_mismatch",
        safeDetail:
          "The authoritative invitation delivery state did not match the claimed job.",
      });
    }

    const receipt = await input.provider.deliver({
      email: invitation.email,
      invitationId: invitation.invitationId,
      providerIdentityExists: invitation.providerIdentityExists,
      signal: context.signal,
      workspaceId: invitation.workspaceId,
    });

    return {
      providerRequestId: receipt.providerRequestId,
      summary: {
        delivery_outcome: "submitted",
        invitation_id: invitation.invitationId,
      },
    };
  };
}
