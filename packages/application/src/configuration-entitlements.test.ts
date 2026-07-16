import { describe, expect, it } from "vitest";

import {
  assertConfigurationTransition,
  ConfigurationPolicyError,
  isFeatureEntitled,
  type ConfigurationPolicyErrorCode,
  type ConfigurationVersionSnapshot,
  type FeatureEntitlementVersion,
} from "./configuration-entitlements";

const workspaceA = "10000000-0000-4000-8000-000000000001";
const workspaceB = "20000000-0000-4000-8000-000000000002";
const versionId = "90000000-0000-4000-8000-000000000001";
const now = "2026-07-16T12:00:00.000Z";

function entitlement(
  overrides: Partial<FeatureEntitlementVersion> = {},
): FeatureEntitlementVersion {
  return {
    id: "91000000-0000-4000-8000-000000000001",
    workspaceId: workspaceA,
    key: "inventory",
    version: 1,
    status: "active",
    enabled: true,
    effectiveFrom: "2026-07-16T00:00:00.000Z",
    effectiveUntil: null,
    ...overrides,
  };
}

function configuration(
  overrides: Partial<ConfigurationVersionSnapshot> = {},
): ConfigurationVersionSnapshot {
  return {
    id: versionId,
    workspaceId: workspaceA,
    key: "workspace.core",
    version: 1,
    status: "reviewed",
    checksum: "a".repeat(64),
    minimumPlatformSchemaVersion: 1,
    maximumPlatformSchemaVersion: 2,
    effectiveFrom: "2026-07-16T00:00:00.000Z",
    effectiveUntil: null,
    ...overrides,
  };
}

function expectPolicyError(
  operation: () => unknown,
  code: ConfigurationPolicyErrorCode,
): void {
  expect(operation).toThrowError(ConfigurationPolicyError);
  try {
    operation();
  } catch (error) {
    expect((error as ConfigurationPolicyError).code).toBe(code);
  }
}

describe("workspace feature entitlements", () => {
  it("VYN-E02 makes an active, enabled, effective capability available", () => {
    expect(
      isFeatureEntitled({
        authoritativeWorkspaceId: workspaceA,
        key: "inventory",
        versions: [entitlement()],
        at: now,
      }),
    ).toBe(true);
  });

  it.each([
    entitlement({ status: "draft" }),
    entitlement({ enabled: false }),
    entitlement({ effectiveFrom: "2026-07-17T00:00:00.000Z" }),
    entitlement({ effectiveUntil: "2026-07-16T12:00:00.000Z" }),
    entitlement({ effectiveFrom: "not-an-instant" }),
  ])(
    "fails closed for unavailable or malformed entitlement state",
    (version) => {
      expect(
        isFeatureEntitled({
          authoritativeWorkspaceId: workspaceA,
          key: "inventory",
          versions: [version],
          at: now,
        }),
      ).toBe(false);
    },
  );

  it("does not accept an entitlement from a request-selected foreign workspace", () => {
    expect(
      isFeatureEntitled({
        authoritativeWorkspaceId: workspaceA,
        key: "inventory",
        versions: [entitlement({ workspaceId: workspaceB })],
        at: now,
      }),
    ).toBe(false);
  });

  it("fails closed when supposedly unique active history is duplicated", () => {
    expectPolicyError(
      () =>
        isFeatureEntitled({
          authoritativeWorkspaceId: workspaceA,
          key: "inventory",
          versions: [entitlement(), entitlement({ version: 2 })],
          at: now,
        }),
      "entitlement_history_conflict",
    );
  });
});

describe("immutable configuration lifecycle", () => {
  const approval = {
    workspaceId: workspaceA,
    artifactId: versionId,
    artifactChecksum: "a".repeat(64),
    decision: "approved" as const,
    expiresAt: "2026-08-16T00:00:00.000Z",
  };

  it("accepts an exact-version reviewed to approved transition", () => {
    expect(() =>
      assertConfigurationTransition({
        version: configuration(),
        authoritativeWorkspaceId: workspaceA,
        expectedStatus: "reviewed",
        targetStatus: "approved",
        expectedChecksum: "a".repeat(64),
        platformSchemaVersion: 1,
        approval,
        at: now,
      }),
    ).not.toThrow();
  });

  it("rejects a stale expected status as an optimistic concurrency conflict", () => {
    expectPolicyError(
      () =>
        assertConfigurationTransition({
          version: configuration({ status: "approved" }),
          authoritativeWorkspaceId: workspaceA,
          expectedStatus: "reviewed",
          targetStatus: "approved",
          expectedChecksum: "a".repeat(64),
          platformSchemaVersion: 1,
          approval,
          at: now,
        }),
      "configuration_state_changed",
    );
  });

  it("rejects cross-workspace authority before evaluating lifecycle state", () => {
    expectPolicyError(
      () =>
        assertConfigurationTransition({
          version: configuration(),
          authoritativeWorkspaceId: workspaceB,
          expectedStatus: "reviewed",
          targetStatus: "approved",
          expectedChecksum: "a".repeat(64),
          platformSchemaVersion: 1,
          approval,
          at: now,
        }),
      "workspace_context_mismatch",
    );
  });

  it("rejects a payload checksum mismatch", () => {
    expectPolicyError(
      () =>
        assertConfigurationTransition({
          version: configuration(),
          authoritativeWorkspaceId: workspaceA,
          expectedStatus: "reviewed",
          targetStatus: "approved",
          expectedChecksum: "b".repeat(64),
          platformSchemaVersion: 1,
          approval,
          at: now,
        }),
      "configuration_checksum_mismatch",
    );
  });

  it("does not allow lifecycle stages to be skipped", () => {
    expectPolicyError(
      () =>
        assertConfigurationTransition({
          version: configuration({ status: "draft" }),
          authoritativeWorkspaceId: workspaceA,
          expectedStatus: "draft",
          targetStatus: "approved",
          expectedChecksum: "a".repeat(64),
          platformSchemaVersion: 1,
          approval,
          at: now,
        }),
      "configuration_transition_invalid",
    );
  });

  it.each([
    undefined,
    { ...approval, artifactChecksum: "b".repeat(64) },
    { ...approval, decision: "rejected" as const },
  ])("requires a matching positive approval", (candidateApproval) => {
    expectPolicyError(
      () =>
        assertConfigurationTransition({
          version: configuration(),
          authoritativeWorkspaceId: workspaceA,
          expectedStatus: "reviewed",
          targetStatus: "approved",
          expectedChecksum: "a".repeat(64),
          platformSchemaVersion: 1,
          ...(candidateApproval ? { approval: candidateApproval } : {}),
          at: now,
        }),
      "configuration_approval_missing",
    );
  });

  it("rejects an approval at its exclusive expiry boundary", () => {
    expectPolicyError(
      () =>
        assertConfigurationTransition({
          version: configuration(),
          authoritativeWorkspaceId: workspaceA,
          expectedStatus: "reviewed",
          targetStatus: "approved",
          expectedChecksum: "a".repeat(64),
          platformSchemaVersion: 1,
          approval: { ...approval, expiresAt: now },
          at: now,
        }),
      "configuration_approval_expired",
    );
  });

  it("blocks activation on an incompatible platform schema", () => {
    expectPolicyError(
      () =>
        assertConfigurationTransition({
          version: configuration({ status: "approved" }),
          authoritativeWorkspaceId: workspaceA,
          expectedStatus: "approved",
          targetStatus: "active",
          expectedChecksum: "a".repeat(64),
          platformSchemaVersion: 3,
          approval,
          at: now,
        }),
      "configuration_platform_incompatible",
    );
  });

  it("blocks activation outside the exact effective interval", () => {
    expectPolicyError(
      () =>
        assertConfigurationTransition({
          version: configuration({
            status: "approved",
            effectiveFrom: "2026-07-17T00:00:00.000Z",
          }),
          authoritativeWorkspaceId: workspaceA,
          expectedStatus: "approved",
          targetStatus: "active",
          expectedChecksum: "a".repeat(64),
          platformSchemaVersion: 1,
          approval,
          at: now,
        }),
      "configuration_not_effective",
    );
  });

  it("keeps the input snapshot immutable", () => {
    const snapshot = configuration();

    assertConfigurationTransition({
      version: snapshot,
      authoritativeWorkspaceId: workspaceA,
      expectedStatus: "reviewed",
      targetStatus: "approved",
      expectedChecksum: "a".repeat(64),
      platformSchemaVersion: 1,
      approval,
      at: now,
    });

    expect(snapshot.status).toBe("reviewed");
  });
});
