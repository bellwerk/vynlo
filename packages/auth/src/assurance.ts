import { isActiveMembership, type WorkspaceMembership } from "./membership";

const DAY_IN_MILLISECONDS = 24 * 60 * 60 * 1_000;
const MINUTE_IN_MILLISECONDS = 60 * 1_000;

export const MAXIMUM_NORMAL_SESSION_AGE_MS = 14 * DAY_IN_MILLISECONDS;
export const MAXIMUM_STEP_UP_AGE_MS = 15 * MINUTE_IN_MILLISECONDS;

export const AUTH_ASSURANCE_POLICY = Object.freeze({
  maximumNormalSessionAgeMs: MAXIMUM_NORMAL_SESSION_AGE_MS,
  maximumStepUpAgeMs: MAXIMUM_STEP_UP_AGE_MS,
});

export const AUTHENTICATION_ASSURANCE_LEVELS = ["aal1", "aal2"] as const;

export type AuthenticationAssuranceLevel =
  (typeof AUTHENTICATION_ASSURANCE_LEVELS)[number];

export interface NormalSession {
  readonly issuedAtMs: number;
  readonly expiresAtMs: number;
  readonly revokedAtMs: number | null;
}

/** Timestamps must come from a trusted server-side authentication adapter. */
export interface AuthenticationAssurance {
  readonly level: AuthenticationAssuranceLevel;
  readonly mfaAuthenticatedAtMs: number | null;
  readonly strongAuthenticationAtMs: number | null;
}

export type PolicyDecision<DeniedReason extends string> =
  | Readonly<{ allowed: true; reason: "allowed" }>
  | Readonly<{ allowed: false; reason: DeniedReason }>;

export type NormalSessionDecision = PolicyDecision<
  | "invalid_session_window"
  | "invalid_revocation_timestamp"
  | "session_lifetime_exceeds_policy"
  | "not_yet_valid"
  | "revoked"
  | "expired"
>;

export type WorkspaceMfaDecision = PolicyDecision<
  "inactive_membership" | "mfa_required" | "invalid_mfa_timestamp"
>;

export type StepUpDecision = PolicyDecision<
  | "mfa_required"
  | "invalid_mfa_timestamp"
  | "step_up_required"
  | "invalid_strong_authentication_timestamp"
  | "step_up_stale"
>;

function isValidTimestamp(value: number): boolean {
  return Number.isFinite(value) && value >= 0;
}

export function evaluateNormalSession(
  session: NormalSession,
  nowMs: number,
): NormalSessionDecision {
  if (
    !isValidTimestamp(session.issuedAtMs) ||
    !isValidTimestamp(session.expiresAtMs) ||
    !isValidTimestamp(nowMs) ||
    session.expiresAtMs <= session.issuedAtMs
  ) {
    return { allowed: false, reason: "invalid_session_window" };
  }

  if (
    session.expiresAtMs - session.issuedAtMs >
    MAXIMUM_NORMAL_SESSION_AGE_MS
  ) {
    return { allowed: false, reason: "session_lifetime_exceeds_policy" };
  }

  if (nowMs < session.issuedAtMs) {
    return { allowed: false, reason: "not_yet_valid" };
  }

  if (
    session.revokedAtMs !== null &&
    (!isValidTimestamp(session.revokedAtMs) ||
      session.revokedAtMs < session.issuedAtMs ||
      session.revokedAtMs > nowMs)
  ) {
    return { allowed: false, reason: "invalid_revocation_timestamp" };
  }

  if (session.revokedAtMs !== null) {
    return { allowed: false, reason: "revoked" };
  }

  if (nowMs >= session.expiresAtMs) {
    return { allowed: false, reason: "expired" };
  }

  return { allowed: true, reason: "allowed" };
}

export function isMfaRequiredForWorkspaceAccess(
  membership: Pick<WorkspaceMembership, "isWorkspaceAdministrator">,
  workspaceRequiresMfaForAllMembers: boolean,
): boolean {
  return (
    membership.isWorkspaceAdministrator || workspaceRequiresMfaForAllMembers
  );
}

export function evaluateWorkspaceMfaAccess(
  membership: WorkspaceMembership,
  workspaceRequiresMfaForAllMembers: boolean,
  assurance: Pick<AuthenticationAssurance, "level" | "mfaAuthenticatedAtMs">,
  nowMs: number,
): WorkspaceMfaDecision {
  if (!isActiveMembership(membership)) {
    return { allowed: false, reason: "inactive_membership" };
  }

  if (
    !isMfaRequiredForWorkspaceAccess(
      membership,
      workspaceRequiresMfaForAllMembers,
    )
  ) {
    return { allowed: true, reason: "allowed" };
  }

  if (assurance.level !== "aal2" || assurance.mfaAuthenticatedAtMs === null) {
    return { allowed: false, reason: "mfa_required" };
  }

  if (
    !isValidTimestamp(assurance.mfaAuthenticatedAtMs) ||
    !isValidTimestamp(nowMs) ||
    assurance.mfaAuthenticatedAtMs > nowMs
  ) {
    return { allowed: false, reason: "invalid_mfa_timestamp" };
  }

  return { allowed: true, reason: "allowed" };
}

export function evaluateRecentStepUp(
  assurance: AuthenticationAssurance,
  nowMs: number,
): StepUpDecision {
  if (assurance.level !== "aal2" || assurance.mfaAuthenticatedAtMs === null) {
    return { allowed: false, reason: "mfa_required" };
  }

  if (
    !isValidTimestamp(assurance.mfaAuthenticatedAtMs) ||
    !isValidTimestamp(nowMs) ||
    assurance.mfaAuthenticatedAtMs > nowMs
  ) {
    return { allowed: false, reason: "invalid_mfa_timestamp" };
  }

  if (assurance.strongAuthenticationAtMs === null) {
    return { allowed: false, reason: "step_up_required" };
  }

  if (
    !isValidTimestamp(assurance.strongAuthenticationAtMs) ||
    !isValidTimestamp(nowMs) ||
    assurance.strongAuthenticationAtMs > nowMs
  ) {
    return {
      allowed: false,
      reason: "invalid_strong_authentication_timestamp",
    };
  }

  if (nowMs - assurance.strongAuthenticationAtMs > MAXIMUM_STEP_UP_AGE_MS) {
    return { allowed: false, reason: "step_up_stale" };
  }

  return { allowed: true, reason: "allowed" };
}
