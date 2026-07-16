import { z } from "zod";
import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const localePattern = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/u;

const createInvitationBodySchema = z
  .object({
    email: z.string().trim().min(3).max(320).email(),
    expiresAt: z.iso.datetime({ offset: true }),
    requestedLocale: z.string().trim().min(2).max(64).regex(localePattern),
    roleIds: z.array(uuidSchema).min(1).max(32),
  })
  .strict();

const acceptInvitationBodySchema = z
  .object({ invitationId: uuidSchema })
  .strict();

const jobStatusSchema = z.enum([
  "queued",
  "running",
  "retry_wait",
  "succeeded",
  "dead_letter",
  "cancelled",
]);

const createInvitationResultSchema = z
  .object({
    invitation_id: uuidSchema,
    invitation_status: z.literal("pending"),
    job_id: uuidSchema,
    job_status: jobStatusSchema,
    outbox_event_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();

const acceptInvitationResultSchema = z
  .object({
    invitation_id: uuidSchema,
    invitation_status: z.literal("accepted"),
    membership_id: uuidSchema,
    replayed: z.boolean(),
  })
  .strict();

export type WorkspaceInvitationValidationErrorCode = "invalid_request_body";

export class WorkspaceInvitationValidationError extends Error {
  readonly code: WorkspaceInvitationValidationErrorCode;

  constructor(code: WorkspaceInvitationValidationErrorCode) {
    super("The workspace invitation command input is invalid.");
    this.name = "WorkspaceInvitationValidationError";
    this.code = code;
  }
}

export class WorkspaceInvitationRpcContractError extends Error {
  constructor() {
    super("The workspace invitation data store returned an invalid response.");
    this.name = "WorkspaceInvitationRpcContractError";
  }
}

export interface CreateWorkspaceInvitationResult {
  readonly invitationId: string;
  readonly invitationStatus: "pending";
  readonly jobId: string;
  readonly jobStatus: z.infer<typeof jobStatusSchema>;
  readonly outboxEventId: string;
  readonly replayed: boolean;
}

export interface AcceptWorkspaceInvitationResult {
  readonly invitationId: string;
  readonly invitationStatus: "accepted";
  readonly membershipId: string;
  readonly replayed: boolean;
}

function parseCreateBody(body: unknown): {
  readonly email: string;
  readonly expiresAt: string;
  readonly requestedLocale: string;
  readonly roleIds: readonly string[];
} {
  const parsed = createInvitationBodySchema.safeParse(body);
  if (
    !parsed.success ||
    new Set(parsed.data.roleIds).size !== parsed.data.roleIds.length
  ) {
    throw new WorkspaceInvitationValidationError("invalid_request_body");
  }

  let requestedLocale: string;
  try {
    const canonicalLocales = Intl.getCanonicalLocales(
      parsed.data.requestedLocale,
    );
    if (canonicalLocales.length !== 1 || canonicalLocales[0] === undefined) {
      throw new RangeError("Expected exactly one locale.");
    }
    requestedLocale = canonicalLocales[0];
  } catch {
    throw new WorkspaceInvitationValidationError("invalid_request_body");
  }

  return Object.freeze({
    email: parsed.data.email.toLowerCase(),
    expiresAt: new Date(parsed.data.expiresAt).toISOString(),
    requestedLocale,
    roleIds: Object.freeze([...parsed.data.roleIds].sort()),
  });
}

function parseAcceptBody(body: unknown): { readonly invitationId: string } {
  const parsed = acceptInvitationBodySchema.safeParse(body);
  if (!parsed.success) {
    throw new WorkspaceInvitationValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseRpcRow<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = z.array(schema).length(1).safeParse(value);
  if (!result.success) {
    throw new WorkspaceInvitationRpcContractError();
  }
  return result.data[0]!;
}

export class WorkspaceInvitationApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async createWorkspaceInvitation(
    input: VerticalSliceCommandInput,
  ): Promise<CreateWorkspaceInvitationResult> {
    const body = parseCreateBody(input.body);
    const row = parseRpcRow(
      createInvitationResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_workspace_invitation_job",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_email: body.email,
          p_expires_at: body.expiresAt,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_request_id: input.metadata.requestId,
          p_requested_locale: body.requestedLocale,
          p_role_ids: body.roleIds,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );

    return Object.freeze({
      invitationId: row.invitation_id,
      invitationStatus: row.invitation_status,
      jobId: row.job_id,
      jobStatus: row.job_status,
      outboxEventId: row.outbox_event_id,
      replayed: row.replayed,
    });
  }

  async acceptWorkspaceInvitation(
    input: VerticalSliceCommandInput,
  ): Promise<AcceptWorkspaceInvitationResult> {
    const body = parseAcceptBody(input.body);
    const row = parseRpcRow(
      acceptInvitationResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "accept_workspace_invitation",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_invitation_id: body.invitationId,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );

    return Object.freeze({
      invitationId: row.invitation_id,
      invitationStatus: row.invitation_status,
      membershipId: row.membership_id,
      replayed: row.replayed,
    });
  }
}
