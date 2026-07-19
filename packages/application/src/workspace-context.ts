import {
  isActiveMembership,
  type MembershipStatus,
  type UserProfileStatus,
} from "@vynlo/auth";

export type WorkspaceMembershipStatus = MembershipStatus;

export interface WorkspaceMembershipSnapshot {
  readonly id: string;
  readonly userId: string;
  readonly workspaceId: string;
  readonly status: WorkspaceMembershipStatus;
  readonly userStatus: UserProfileStatus;
}

export interface ResolveWorkspaceContextInput {
  readonly authenticatedUserId: string;
  readonly selectedWorkspaceId?: string | null;
  readonly bodyWorkspaceId?: string | null;
  readonly memberships: readonly WorkspaceMembershipSnapshot[];
}

export interface ResolvedWorkspaceContext {
  readonly authenticatedUserId: string;
  readonly membershipId: string;
  readonly workspaceId: string;
}

export type WorkspaceContextErrorCode =
  | "workspace_selection_required"
  | "workspace_context_mismatch"
  | "workspace_access_denied"
  | "workspace_membership_invariant_violation";

export class WorkspaceContextError extends Error {
  readonly code: WorkspaceContextErrorCode;

  constructor(code: WorkspaceContextErrorCode) {
    super(code);
    this.name = "WorkspaceContextError";
    this.code = code;
  }
}

/**
 * Resolves the authoritative workspace for an application command.
 *
 * The selected workspace must come from a validated route or header. A body
 * value may be checked for consistency, but it is never accepted as the source
 * of workspace authority.
 */
export function resolveWorkspaceContext(
  input: ResolveWorkspaceContextInput,
): ResolvedWorkspaceContext {
  const authenticatedUserId = input.authenticatedUserId.trim();
  const selectedWorkspaceId = input.selectedWorkspaceId?.trim();
  const bodyWorkspaceId = input.bodyWorkspaceId?.trim();

  if (!authenticatedUserId || !selectedWorkspaceId) {
    throw new WorkspaceContextError("workspace_selection_required");
  }

  if (bodyWorkspaceId && bodyWorkspaceId !== selectedWorkspaceId) {
    throw new WorkspaceContextError("workspace_context_mismatch");
  }

  const memberships = input.memberships.filter(
    (membership) =>
      membership.userId === authenticatedUserId &&
      membership.workspaceId === selectedWorkspaceId,
  );

  if (memberships.length > 1) {
    throw new WorkspaceContextError("workspace_membership_invariant_violation");
  }

  const membership = memberships[0];
  if (!membership || !isActiveMembership(membership)) {
    throw new WorkspaceContextError("workspace_access_denied");
  }

  return {
    authenticatedUserId,
    membershipId: membership.id,
    workspaceId: membership.workspaceId,
  };
}
