export const FEATURE_ENTITLEMENT_KEYS = [
  "inventory",
  "media",
  "crm",
  "deals",
  "one_time_payments",
  "documents",
  "website_publishing",
  "third_party_finance",
  "exports",
  "custom_workflows",
  "tenant_calculations",
] as const;

export type FeatureEntitlementKey = (typeof FEATURE_ENTITLEMENT_KEYS)[number];

export type FeatureEntitlementStatus =
  "draft" | "active" | "superseded" | "retired";

export interface FeatureEntitlementVersion {
  readonly id: string;
  readonly workspaceId: string;
  readonly key: FeatureEntitlementKey;
  readonly version: number;
  readonly status: FeatureEntitlementStatus;
  readonly enabled: boolean;
  readonly effectiveFrom: string;
  readonly effectiveUntil?: string | null;
}

export type ConfigurationVersionStatus =
  | "draft"
  | "validated"
  | "reviewed"
  | "approved"
  | "active"
  | "superseded"
  | "retired";

export interface ConfigurationVersionSnapshot {
  readonly id: string;
  readonly workspaceId: string;
  readonly key: string;
  readonly version: number;
  readonly status: ConfigurationVersionStatus;
  readonly checksum: string;
  readonly minimumPlatformSchemaVersion: number;
  readonly maximumPlatformSchemaVersion: number;
  readonly effectiveFrom: string;
  readonly effectiveUntil?: string | null;
}

export interface ConfigurationApprovalSnapshot {
  readonly workspaceId: string;
  readonly artifactId: string;
  readonly artifactChecksum: string;
  readonly decision: "approved" | "rejected" | "revoked";
  readonly expiresAt?: string | null;
}

export type ConfigurationPolicyErrorCode =
  | "workspace_context_mismatch"
  | "entitlement_history_conflict"
  | "entitlement_not_effective"
  | "configuration_state_changed"
  | "configuration_checksum_mismatch"
  | "configuration_transition_invalid"
  | "configuration_approval_missing"
  | "configuration_approval_expired"
  | "configuration_platform_incompatible"
  | "configuration_not_effective";

export class ConfigurationPolicyError extends Error {
  readonly code: ConfigurationPolicyErrorCode;

  constructor(code: ConfigurationPolicyErrorCode) {
    super(code);
    this.name = "ConfigurationPolicyError";
    this.code = code;
  }
}

function parseInstant(value: string): number | undefined {
  const instant = Date.parse(value);
  return Number.isFinite(instant) ? instant : undefined;
}

function isEffective(
  effectiveFrom: string,
  effectiveUntil: string | null | undefined,
  at: string,
): boolean {
  const effectiveFromInstant = parseInstant(effectiveFrom);
  const effectiveUntilInstant = effectiveUntil
    ? parseInstant(effectiveUntil)
    : undefined;
  const atInstant = parseInstant(at);

  if (
    effectiveFromInstant === undefined ||
    atInstant === undefined ||
    (effectiveUntil !== null &&
      effectiveUntil !== undefined &&
      effectiveUntilInstant === undefined)
  ) {
    return false;
  }

  return (
    effectiveFromInstant <= atInstant &&
    (effectiveUntilInstant === undefined || atInstant < effectiveUntilInstant)
  );
}

/**
 * Shared UI/API/job entitlement decision. It fails closed when history contains
 * more than one active version for the same workspace capability.
 */
export function isFeatureEntitled(input: {
  readonly authoritativeWorkspaceId: string;
  readonly key: FeatureEntitlementKey;
  readonly versions: readonly FeatureEntitlementVersion[];
  readonly at: string;
}): boolean {
  const activeVersions = input.versions.filter(
    (version) =>
      version.workspaceId === input.authoritativeWorkspaceId &&
      version.key === input.key &&
      version.status === "active",
  );

  if (activeVersions.length > 1) {
    throw new ConfigurationPolicyError("entitlement_history_conflict");
  }

  const activeVersion = activeVersions[0];
  return (
    activeVersion?.enabled === true &&
    isEffective(
      activeVersion.effectiveFrom,
      activeVersion.effectiveUntil,
      input.at,
    )
  );
}

const LIFECYCLE_TRANSITIONS: Readonly<
  Record<ConfigurationVersionStatus, readonly ConfigurationVersionStatus[]>
> = {
  draft: ["validated", "retired"],
  validated: ["reviewed", "retired"],
  reviewed: ["approved", "retired"],
  approved: ["active", "retired"],
  active: ["superseded", "retired"],
  superseded: ["active", "retired"],
  retired: [],
};

/**
 * Validates an optimistic lifecycle command without mutating its snapshot.
 * Database commands remain authoritative and repeat the same invariants while
 * holding workspace/version locks.
 */
export function assertConfigurationTransition(input: {
  readonly version: ConfigurationVersionSnapshot;
  readonly authoritativeWorkspaceId: string;
  readonly expectedStatus: ConfigurationVersionStatus;
  readonly targetStatus: ConfigurationVersionStatus;
  readonly expectedChecksum: string;
  readonly platformSchemaVersion: number;
  readonly approval?: ConfigurationApprovalSnapshot;
  readonly at: string;
}): void {
  const { version } = input;

  if (version.workspaceId !== input.authoritativeWorkspaceId) {
    throw new ConfigurationPolicyError("workspace_context_mismatch");
  }

  if (version.status !== input.expectedStatus) {
    throw new ConfigurationPolicyError("configuration_state_changed");
  }

  if (version.checksum !== input.expectedChecksum) {
    throw new ConfigurationPolicyError("configuration_checksum_mismatch");
  }

  if (!LIFECYCLE_TRANSITIONS[version.status].includes(input.targetStatus)) {
    throw new ConfigurationPolicyError("configuration_transition_invalid");
  }

  if (input.targetStatus === "approved" || input.targetStatus === "active") {
    const approval = input.approval;
    if (
      !approval ||
      approval.workspaceId !== version.workspaceId ||
      approval.artifactId !== version.id ||
      approval.artifactChecksum !== version.checksum ||
      approval.decision !== "approved"
    ) {
      throw new ConfigurationPolicyError("configuration_approval_missing");
    }

    const approvalExpiry = approval.expiresAt
      ? parseInstant(approval.expiresAt)
      : undefined;
    const atInstant = parseInstant(input.at);
    if (
      atInstant === undefined ||
      (approval.expiresAt &&
        (approvalExpiry === undefined || approvalExpiry <= atInstant))
    ) {
      throw new ConfigurationPolicyError("configuration_approval_expired");
    }
  }

  if (
    input.targetStatus === "active" &&
    (input.platformSchemaVersion < version.minimumPlatformSchemaVersion ||
      input.platformSchemaVersion > version.maximumPlatformSchemaVersion)
  ) {
    throw new ConfigurationPolicyError("configuration_platform_incompatible");
  }

  if (
    input.targetStatus === "active" &&
    !isEffective(version.effectiveFrom, version.effectiveUntil, input.at)
  ) {
    throw new ConfigurationPolicyError("configuration_not_effective");
  }
}
