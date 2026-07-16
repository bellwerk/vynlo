import { describe, expect, it } from "vitest";

import {
  MAXIMUM_NORMAL_SESSION_AGE_MS,
  MAXIMUM_STEP_UP_AGE_MS,
  PLATFORM_PERMISSION_KEYS,
  evaluateNormalSession,
  evaluatePermission,
  evaluateRecentStepUp,
  evaluateWorkspaceMfaAccess,
  hasEffectivePermission,
  isPlatformPermissionKey,
  resolveEffectivePermissionKeys,
  type WorkspaceMembership,
} from "./index";

const NOW_MS = Date.UTC(2026, 6, 15, 12, 0, 0);

const activeMember: WorkspaceMembership = {
  id: "membership-1",
  workspaceId: "workspace-1",
  userId: "user-1",
  status: "active",
  userStatus: "active",
  isWorkspaceAdministrator: false,
};

describe("authentication assurance policy", () => {
  it("T-AUTH-002 denies an administrator without MFA and honors workspace-wide MFA", () => {
    const administrator: WorkspaceMembership = {
      ...activeMember,
      isWorkspaceAdministrator: true,
    };

    expect(
      evaluateWorkspaceMfaAccess(
        administrator,
        false,
        { level: "aal1", mfaAuthenticatedAtMs: null },
        NOW_MS,
      ),
    ).toEqual({ allowed: false, reason: "mfa_required" });

    expect(
      evaluateWorkspaceMfaAccess(
        activeMember,
        false,
        { level: "aal1", mfaAuthenticatedAtMs: null },
        NOW_MS,
      ),
    ).toEqual({ allowed: true, reason: "allowed" });

    expect(
      evaluateWorkspaceMfaAccess(
        activeMember,
        true,
        { level: "aal1", mfaAuthenticatedAtMs: null },
        NOW_MS,
      ),
    ).toEqual({ allowed: false, reason: "mfa_required" });

    expect(
      evaluateWorkspaceMfaAccess(
        administrator,
        false,
        { level: "aal2", mfaAuthenticatedAtMs: NOW_MS - 1_000 },
        NOW_MS,
      ),
    ).toEqual({ allowed: true, reason: "allowed" });

    expect(
      evaluateWorkspaceMfaAccess(
        { ...administrator, status: "deactivated" },
        false,
        { level: "aal2", mfaAuthenticatedAtMs: NOW_MS - 1_000 },
        NOW_MS,
      ),
    ).toEqual({ allowed: false, reason: "inactive_membership" });

    expect(
      evaluateWorkspaceMfaAccess(
        { ...administrator, userStatus: "deactivated" },
        false,
        { level: "aal2", mfaAuthenticatedAtMs: NOW_MS - 1_000 },
        NOW_MS,
      ),
    ).toEqual({ allowed: false, reason: "inactive_membership" });
  });

  it("T-AUTH-003 expires sessions at the 14-day maximum and rejects longer windows", () => {
    const session = {
      issuedAtMs: NOW_MS,
      expiresAtMs: NOW_MS + MAXIMUM_NORMAL_SESSION_AGE_MS,
      revokedAtMs: null,
    } as const;

    expect(
      evaluateNormalSession(
        session,
        NOW_MS + MAXIMUM_NORMAL_SESSION_AGE_MS - 1,
      ),
    ).toEqual({ allowed: true, reason: "allowed" });
    expect(
      evaluateNormalSession(session, NOW_MS + MAXIMUM_NORMAL_SESSION_AGE_MS),
    ).toEqual({ allowed: false, reason: "expired" });
    expect(
      evaluateNormalSession(
        {
          ...session,
          expiresAtMs: NOW_MS + MAXIMUM_NORMAL_SESSION_AGE_MS + 1,
        },
        NOW_MS + 1,
      ),
    ).toEqual({
      allowed: false,
      reason: "session_lifetime_exceeds_policy",
    });
    expect(
      evaluateNormalSession({ ...session, revokedAtMs: Number.NaN }, NOW_MS),
    ).toEqual({
      allowed: false,
      reason: "invalid_revocation_timestamp",
    });
    expect(
      evaluateNormalSession({ ...session, revokedAtMs: NOW_MS + 1 }, NOW_MS),
    ).toEqual({
      allowed: false,
      reason: "invalid_revocation_timestamp",
    });
    expect(
      evaluateNormalSession({ ...session, revokedAtMs: NOW_MS }, NOW_MS),
    ).toEqual({ allowed: false, reason: "revoked" });
    expect(evaluateNormalSession(session, NOW_MS - 1)).toEqual({
      allowed: false,
      reason: "not_yet_valid",
    });
  });

  it("T-AUTH-004 rejects stale assurance and succeeds after a recent step-up", () => {
    expect(
      evaluateRecentStepUp(
        {
          level: "aal2",
          mfaAuthenticatedAtMs: NOW_MS,
          strongAuthenticationAtMs: null,
        },
        NOW_MS,
      ),
    ).toEqual({ allowed: false, reason: "step_up_required" });

    expect(
      evaluateRecentStepUp(
        {
          level: "aal2",
          mfaAuthenticatedAtMs: NOW_MS - MAXIMUM_STEP_UP_AGE_MS - 1,
          strongAuthenticationAtMs: NOW_MS - MAXIMUM_STEP_UP_AGE_MS - 1,
        },
        NOW_MS,
      ),
    ).toEqual({ allowed: false, reason: "step_up_stale" });

    expect(
      evaluateRecentStepUp(
        {
          level: "aal2",
          mfaAuthenticatedAtMs: NOW_MS - MAXIMUM_STEP_UP_AGE_MS,
          strongAuthenticationAtMs: NOW_MS - MAXIMUM_STEP_UP_AGE_MS,
        },
        NOW_MS,
      ),
    ).toEqual({ allowed: true, reason: "allowed" });

    expect(
      evaluateRecentStepUp(
        {
          level: "aal2",
          mfaAuthenticatedAtMs: NOW_MS,
          strongAuthenticationAtMs: NOW_MS,
        },
        NOW_MS,
      ),
    ).toEqual({ allowed: true, reason: "allowed" });

    expect(
      evaluateRecentStepUp(
        {
          level: "aal1",
          mfaAuthenticatedAtMs: null,
          strongAuthenticationAtMs: NOW_MS,
        },
        NOW_MS,
      ),
    ).toEqual({ allowed: false, reason: "mfa_required" });
  });
});

describe("effective permission policy", () => {
  it("T-RBAC-001 uses active membership and explicit grants, never labels or client claims", () => {
    const untrustedHintsOnly = {
      membership: activeMember,
      grants: [],
      roleLabels: ["Administrator"],
      clientPermissionClaims: ["payments.refund"],
    };

    expect(resolveEffectivePermissionKeys(untrustedHintsOnly)).toEqual([]);

    const authoritativeInput = {
      membership: activeMember,
      grants: [
        {
          membershipId: activeMember.id,
          workspaceId: activeMember.workspaceId,
          roleId: "role-1",
          permissionKey: "inventory.read",
        },
        {
          membershipId: activeMember.id,
          workspaceId: "workspace-other",
          roleId: "role-1",
          permissionKey: "payments.refund",
        },
        {
          membershipId: "membership-other",
          workspaceId: activeMember.workspaceId,
          roleId: "role-1",
          permissionKey: "roles.manage",
        },
      ],
    } as const;

    expect(resolveEffectivePermissionKeys(authoritativeInput)).toEqual([
      "inventory.read",
    ]);
    expect(hasEffectivePermission(authoritativeInput, "inventory.read")).toBe(
      true,
    );
    expect(hasEffectivePermission(authoritativeInput, "payments.refund")).toBe(
      false,
    );
    expect(evaluatePermission(authoritativeInput, "payments.refund")).toEqual({
      allowed: false,
      reason: "permission_not_granted",
    });
    expect(
      evaluatePermission(
        {
          ...authoritativeInput,
          membership: { ...activeMember, status: "deactivated" },
        },
        "inventory.read",
      ),
    ).toEqual({ allowed: false, reason: "inactive_membership" });
    expect(
      evaluatePermission(
        {
          ...authoritativeInput,
          membership: { ...activeMember, userStatus: "suspended" },
        },
        "inventory.read",
      ),
    ).toEqual({ allowed: false, reason: "inactive_membership" });
  });

  it("T-RBAC-001 exposes the complete unique stable platform permission catalogue", () => {
    expect(PLATFORM_PERMISSION_KEYS).toHaveLength(75);
    expect(new Set(PLATFORM_PERMISSION_KEYS).size).toBe(
      PLATFORM_PERMISSION_KEYS.length,
    );
    expect(isPlatformPermissionKey("documents.generate_approved")).toBe(true);
    expect(isPlatformPermissionKey("unknown.manage")).toBe(false);
  });
});
