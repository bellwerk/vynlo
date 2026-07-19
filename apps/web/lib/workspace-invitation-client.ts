export interface WorkspaceInvitationContext {
  readonly invitationId: string;
  readonly workspaceId: string;
}

type SearchParameters = Readonly<
  Record<string, string | readonly string[] | undefined>
>;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

function one(value: string | readonly string[] | undefined): string | null {
  return typeof value === "string" ? value.toLowerCase() : null;
}

export function parseWorkspaceInvitationContext(parameters: SearchParameters): {
  readonly context: WorkspaceInvitationContext | null;
  readonly invalid: boolean;
} {
  const invitationId = one(parameters.invitation);
  const workspaceId = one(parameters.workspace);
  const supplied =
    parameters.invitation !== undefined || parameters.workspace !== undefined;
  const context =
    invitationId &&
    workspaceId &&
    uuidPattern.test(invitationId) &&
    uuidPattern.test(workspaceId)
      ? Object.freeze({ invitationId, workspaceId })
      : null;
  return Object.freeze({ context, invalid: supplied && context === null });
}

export function workspaceInvitationLoginRedirect(
  origin: string,
  context: WorkspaceInvitationContext,
): string {
  const redirect = new URL("/login", origin);
  redirect.searchParams.set("invitation", context.invitationId);
  redirect.searchParams.set("workspace", context.workspaceId);
  return redirect.toString();
}

export async function acceptWorkspaceInvitationSession(input: {
  readonly accessToken: string;
  readonly context: WorkspaceInvitationContext;
  readonly fetchImplementation?: typeof fetch;
  readonly randomUuid?: () => string;
}): Promise<void> {
  const fetchImplementation = input.fetchImplementation ?? fetch;
  const randomUuid = input.randomUuid ?? crypto.randomUUID.bind(crypto);
  const response = await fetchImplementation(
    "/api/v1/workspace-invitations/accept",
    {
      body: JSON.stringify({ invitationId: input.context.invitationId }),
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${input.accessToken}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `accept-invitation-${input.context.invitationId}`,
        "X-Correlation-Id": randomUuid(),
        "X-Request-Id": randomUuid(),
        "X-Workspace-Id": input.context.workspaceId,
      },
      method: "POST",
      signal: AbortSignal.timeout(15_000),
    },
  );
  if (!response.ok) {
    throw new TypeError("invitation_acceptance_failed");
  }
}
