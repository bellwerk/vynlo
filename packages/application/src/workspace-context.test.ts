import { describe, expect, it } from "vitest";

import {
  resolveWorkspaceContext,
  WorkspaceContextError,
  type ResolveWorkspaceContextInput,
  type WorkspaceContextErrorCode,
  type WorkspaceMembershipSnapshot,
} from "./workspace-context";

const userId = "30000000-0000-4000-8000-000000000001";
const workspaceA = "10000000-0000-4000-8000-000000000001";
const workspaceB = "20000000-0000-4000-8000-000000000002";

function membership(
  overrides: Partial<WorkspaceMembershipSnapshot> = {},
): WorkspaceMembershipSnapshot {
  return {
    id: "40000000-0000-4000-8000-000000000001",
    userId,
    workspaceId: workspaceA,
    status: "active",
    userStatus: "active",
    ...overrides,
  };
}

function expectContextError(
  input: ResolveWorkspaceContextInput,
  code: WorkspaceContextErrorCode,
) {
  try {
    resolveWorkspaceContext(input);
    throw new Error(`Expected workspace context error: ${code}`);
  } catch (error) {
    expect(error).toBeInstanceOf(WorkspaceContextError);
    expect((error as WorkspaceContextError).code).toBe(code);
  }
}

describe("authoritative workspace context", () => {
  it("resolves an explicitly selected workspace from an active membership", () => {
    expect(
      resolveWorkspaceContext({
        authenticatedUserId: userId,
        selectedWorkspaceId: workspaceA,
        memberships: [membership()],
      }),
    ).toEqual({
      authenticatedUserId: userId,
      membershipId: "40000000-0000-4000-8000-000000000001",
      workspaceId: workspaceA,
    });
  });

  it("T-TEN-002 rejects a body workspace that disagrees with the selected context", () => {
    expectContextError(
      {
        authenticatedUserId: userId,
        selectedWorkspaceId: workspaceA,
        bodyWorkspaceId: workspaceB,
        memberships: [membership(), membership({ workspaceId: workspaceB })],
      },
      "workspace_context_mismatch",
    );
  });

  it("T-TEN-002 never accepts a body workspace as the authority", () => {
    expectContextError(
      {
        authenticatedUserId: userId,
        bodyWorkspaceId: workspaceA,
        memberships: [membership()],
      },
      "workspace_selection_required",
    );
  });

  it.each(["invited", "suspended", "deactivated"] as const)(
    "T-TEN-001 denies a %s membership",
    (status) => {
      expectContextError(
        {
          authenticatedUserId: userId,
          selectedWorkspaceId: workspaceA,
          memberships: [membership({ status })],
        },
        "workspace_access_denied",
      );
    },
  );

  it("T-TEN-001 denies another user's otherwise active membership", () => {
    expectContextError(
      {
        authenticatedUserId: userId,
        selectedWorkspaceId: workspaceA,
        memberships: [
          membership({
            userId: "30000000-0000-4000-8000-000000000099",
          }),
        ],
      },
      "workspace_access_denied",
    );
  });

  it.each(["suspended", "deactivated"] as const)(
    "T-AUTH-003 denies an active membership for a %s user profile",
    (userStatus) => {
      expectContextError(
        {
          authenticatedUserId: userId,
          selectedWorkspaceId: workspaceA,
          memberships: [membership({ userStatus })],
        },
        "workspace_access_denied",
      );
    },
  );

  it("fails closed when a supposedly unique membership is duplicated", () => {
    expectContextError(
      {
        authenticatedUserId: userId,
        selectedWorkspaceId: workspaceA,
        memberships: [
          membership(),
          membership({ id: "40000000-0000-4000-8000-000000000002" }),
        ],
      },
      "workspace_membership_invariant_violation",
    );
  });
});
