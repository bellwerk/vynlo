import { isActiveMembership, type WorkspaceMembership } from "./membership";
import type { PlatformPermissionKey } from "./permissions";

/**
 * One explicit permission reached through an authoritative
 * membership -> role -> role_permission join.
 */
export interface ExplicitRolePermissionGrant {
  readonly membershipId: string;
  readonly workspaceId: string;
  readonly roleId: string;
  readonly permissionKey: PlatformPermissionKey;
}

export interface EffectivePermissionEvaluationInput {
  readonly membership: WorkspaceMembership;
  readonly grants: readonly ExplicitRolePermissionGrant[];
}

export type PermissionDecision =
  | Readonly<{ allowed: true; reason: "allowed" }>
  | Readonly<{
      allowed: false;
      reason: "inactive_membership" | "permission_not_granted";
    }>;

const NO_PERMISSIONS: readonly PlatformPermissionKey[] = Object.freeze([]);

/**
 * Resolves effective permissions from current server-maintained records.
 *
 * Role labels and client/JWT permission claims are deliberately not accepted.
 * Inactive membership and grants from another membership/workspace fail closed.
 */
export function resolveEffectivePermissionKeys(
  input: EffectivePermissionEvaluationInput,
): readonly PlatformPermissionKey[] {
  if (!isActiveMembership(input.membership)) {
    return NO_PERMISSIONS;
  }

  const effectivePermissions = new Set<PlatformPermissionKey>();

  for (const grant of input.grants) {
    if (
      grant.membershipId === input.membership.id &&
      grant.workspaceId === input.membership.workspaceId &&
      grant.roleId.length > 0
    ) {
      effectivePermissions.add(grant.permissionKey);
    }
  }

  return Object.freeze([...effectivePermissions].sort());
}

export function hasEffectivePermission(
  input: EffectivePermissionEvaluationInput,
  requiredPermission: PlatformPermissionKey,
): boolean {
  return evaluatePermission(input, requiredPermission).allowed;
}

export function evaluatePermission(
  input: EffectivePermissionEvaluationInput,
  requiredPermission: PlatformPermissionKey,
): PermissionDecision {
  if (!isActiveMembership(input.membership)) {
    return { allowed: false, reason: "inactive_membership" };
  }

  if (!resolveEffectivePermissionKeys(input).includes(requiredPermission)) {
    return { allowed: false, reason: "permission_not_granted" };
  }

  return { allowed: true, reason: "allowed" };
}
