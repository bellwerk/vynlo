export const MEMBERSHIP_STATUSES = [
  "invited",
  "active",
  "suspended",
  "deactivated",
] as const;

export type MembershipStatus = (typeof MEMBERSHIP_STATUSES)[number];

export const USER_PROFILE_STATUSES = [
  "active",
  "suspended",
  "deactivated",
] as const;

export type UserProfileStatus = (typeof USER_PROFILE_STATUSES)[number];

/**
 * The authoritative, server-loaded membership facts needed by policy code.
 * `isWorkspaceAdministrator` is persisted policy state, not a localized role
 * label or a client-provided claim.
 */
export interface WorkspaceMembership {
  readonly id: string;
  readonly workspaceId: string;
  readonly userId: string;
  readonly status: MembershipStatus;
  readonly userStatus: UserProfileStatus;
  readonly isWorkspaceAdministrator: boolean;
}

export function isActiveMembership(
  membership: Pick<WorkspaceMembership, "status" | "userStatus">,
): boolean {
  return membership.status === "active" && membership.userStatus === "active";
}
