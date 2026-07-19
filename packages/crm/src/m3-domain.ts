const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const KEY_PATTERN = /^[a-z][a-z0-9_.-]{0,127}$/u;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/u;
const PHONE_PATTERN = /^\+[1-9][0-9]{6,14}$/u;
const RFC3339_INSTANT_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/u;

export const CRM_ACTIVITY_TYPES = [
  "note",
  "call",
  "email_reference",
  "text_reference",
  "appointment",
  "assignment",
  "status_change",
  "document",
  "deal_event",
] as const;

export const CRM_TASK_PRIORITIES = ["low", "normal", "high", "urgent"] as const;
export const CRM_APPOINTMENT_STATUSES = [
  "scheduled",
  "completed",
  "cancelled",
  "no_show",
] as const;

export type M3CrmDomainErrorCode =
  | "invalid_identifier"
  | "invalid_idempotency_key"
  | "invalid_expected_version"
  | "invalid_key"
  | "invalid_text"
  | "invalid_contact"
  | "invalid_address"
  | "invalid_lead"
  | "invalid_activity"
  | "invalid_task"
  | "invalid_appointment"
  | "invalid_timezone"
  | "invalid_lead_conversion"
  | "lead_version_conflict"
  | "reason_required";

export class M3CrmDomainError extends Error {
  readonly code: M3CrmDomainErrorCode;

  constructor(code: M3CrmDomainErrorCode) {
    super(code);
    this.name = "M3CrmDomainError";
    this.code = code;
  }
}

function requireUuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new M3CrmDomainError("invalid_identifier");
  }
  return value.toLowerCase();
}

function nullableUuid(value: unknown): string | null {
  return value === null ? null : requireUuid(value);
}

function requireKey(value: unknown): string {
  if (typeof value !== "string") {
    throw new M3CrmDomainError("invalid_key");
  }
  const normalized = value.trim().toLowerCase();
  if (!KEY_PATTERN.test(normalized)) {
    throw new M3CrmDomainError("invalid_key");
  }
  return normalized;
}

function requireIdempotencyKey(value: unknown): string {
  if (typeof value !== "string") {
    throw new M3CrmDomainError("invalid_idempotency_key");
  }
  const normalized = value.trim();
  if (normalized.length < 8 || normalized.length > 200) {
    throw new M3CrmDomainError("invalid_idempotency_key");
  }
  return normalized;
}

function requireVersion(value: unknown): number {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 1 ||
    (value as number) >= Number.MAX_SAFE_INTEGER
  ) {
    throw new M3CrmDomainError("invalid_expected_version");
  }
  return value as number;
}

function normalizeText(
  value: unknown,
  maximumLength: number,
  nullable = false,
): string | null {
  if (value === null && nullable) return null;
  if (typeof value !== "string") {
    throw new M3CrmDomainError("invalid_text");
  }
  const normalized = value.trim().replace(/\s+/gu, " ");
  if ((!normalized && !nullable) || normalized.length > maximumLength) {
    throw new M3CrmDomainError("invalid_text");
  }
  return normalized || null;
}

function normalizeInstant(value: unknown): string {
  if (typeof value !== "string" || !RFC3339_INSTANT_PATTERN.test(value)) {
    throw new M3CrmDomainError("invalid_text");
  }
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) {
    throw new M3CrmDomainError("invalid_text");
  }
  return new Date(milliseconds).toISOString();
}

function nullableInstant(value: unknown): string | null {
  return value === null ? null : normalizeInstant(value);
}

function requireTimezone(value: unknown): string {
  if (typeof value !== "string" || !value.trim() || value.length > 100) {
    throw new M3CrmDomainError("invalid_timezone");
  }
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: value }).format(0);
  } catch {
    throw new M3CrmDomainError("invalid_timezone");
  }
  return value;
}

export interface NormalizedPartyContactCommand {
  readonly idempotencyKey: string;
  readonly partyId: string;
  readonly contactType: "email" | "phone";
  readonly value: string;
  readonly normalizedValue: string;
  readonly isPrimary: boolean;
  readonly isPreferred: boolean;
  readonly consentStatus: "unknown" | "granted" | "denied" | "withdrawn";
  readonly consentSource: string | null;
  readonly doNotContact: boolean;
}

export function normalizePartyContactCommand(input: {
  readonly idempotencyKey: unknown;
  readonly partyId: unknown;
  readonly contactType: unknown;
  readonly value: unknown;
  readonly isPrimary: unknown;
  readonly isPreferred: unknown;
  readonly consentStatus: unknown;
  readonly consentSource: unknown;
  readonly doNotContact: unknown;
}): Readonly<NormalizedPartyContactCommand> {
  if (!["email", "phone"].includes(input.contactType as string)) {
    throw new M3CrmDomainError("invalid_contact");
  }
  if (typeof input.value !== "string") {
    throw new M3CrmDomainError("invalid_contact");
  }
  const value = input.value.trim();
  const normalizedValue =
    input.contactType === "email"
      ? value.toLowerCase()
      : value.replaceAll(/[\s().-]/gu, "");
  if (
    (input.contactType === "email" &&
      (normalizedValue.length > 320 || !EMAIL_PATTERN.test(normalizedValue))) ||
    (input.contactType === "phone" && !PHONE_PATTERN.test(normalizedValue))
  ) {
    throw new M3CrmDomainError("invalid_contact");
  }
  if (
    typeof input.isPrimary !== "boolean" ||
    typeof input.isPreferred !== "boolean" ||
    typeof input.doNotContact !== "boolean" ||
    !["unknown", "granted", "denied", "withdrawn"].includes(
      input.consentStatus as string,
    )
  ) {
    throw new M3CrmDomainError("invalid_contact");
  }
  const consentSource = normalizeText(input.consentSource, 500, true);
  if (input.consentStatus === "granted" && consentSource === null) {
    throw new M3CrmDomainError("invalid_contact");
  }
  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    partyId: requireUuid(input.partyId),
    contactType: input.contactType as "email" | "phone",
    value,
    normalizedValue,
    isPrimary: input.isPrimary as boolean,
    isPreferred: input.isPreferred as boolean,
    consentStatus:
      input.consentStatus as NormalizedPartyContactCommand["consentStatus"],
    consentSource,
    doNotContact: input.doNotContact as boolean,
  });
}

export interface NormalizedPartyAddressCommand {
  readonly partyId: string;
  readonly addressType: string;
  readonly line1: string;
  readonly line2: string | null;
  readonly locality: string;
  readonly region: string;
  readonly postalCode: string;
  readonly countryCode: string;
  readonly isPrimary: boolean;
}

export function normalizePartyAddressCommand(input: {
  readonly partyId: unknown;
  readonly addressType: unknown;
  readonly line1: unknown;
  readonly line2: unknown;
  readonly locality: unknown;
  readonly region: unknown;
  readonly postalCode: unknown;
  readonly countryCode: unknown;
  readonly isPrimary: unknown;
}): Readonly<NormalizedPartyAddressCommand> {
  if (
    typeof input.countryCode !== "string" ||
    !/^[A-Z]{2}$/u.test(input.countryCode.trim().toUpperCase()) ||
    typeof input.isPrimary !== "boolean"
  ) {
    throw new M3CrmDomainError("invalid_address");
  }
  return Object.freeze({
    partyId: requireUuid(input.partyId),
    addressType: requireKey(input.addressType),
    line1: normalizeText(input.line1, 200)!,
    line2: normalizeText(input.line2, 200, true),
    locality: normalizeText(input.locality, 100)!,
    region: normalizeText(input.region, 100)!,
    postalCode: normalizeText(input.postalCode, 32)!,
    countryCode: input.countryCode.trim().toUpperCase(),
    isPrimary: input.isPrimary,
  });
}

export interface NormalizedLeadCreateCommand {
  readonly idempotencyKey: string;
  readonly prospectPartyId: string | null;
  readonly sourceKey: string;
  readonly interestedInventoryUnitId: string | null;
  readonly assigneeMembershipId: string | null;
  readonly summary: string;
  readonly nextActionAt: string | null;
}

export function normalizeLeadCreateCommand(input: {
  readonly idempotencyKey: unknown;
  readonly prospectPartyId: unknown;
  readonly sourceKey: unknown;
  readonly interestedInventoryUnitId: unknown;
  readonly assigneeMembershipId: unknown;
  readonly summary: unknown;
  readonly nextActionAt: unknown;
}): Readonly<NormalizedLeadCreateCommand> {
  const prospectPartyId = nullableUuid(input.prospectPartyId);
  if (
    prospectPartyId === null &&
    normalizeText(input.summary, 2_000, true) === null
  ) {
    throw new M3CrmDomainError("invalid_lead");
  }
  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    prospectPartyId,
    sourceKey: requireKey(input.sourceKey),
    interestedInventoryUnitId: nullableUuid(input.interestedInventoryUnitId),
    assigneeMembershipId: nullableUuid(input.assigneeMembershipId),
    summary: normalizeText(input.summary, 2_000)!,
    nextActionAt: nullableInstant(input.nextActionAt),
  });
}

export interface NormalizedActivityCommand {
  readonly idempotencyKey: string;
  readonly partyId: string | null;
  readonly leadId: string | null;
  readonly dealId: string | null;
  readonly activityType: (typeof CRM_ACTIVITY_TYPES)[number];
  readonly channelKey: string | null;
  readonly direction: "inbound" | "outbound" | "internal";
  readonly subject: string;
  readonly body: string | null;
  readonly providerReference: string | null;
  readonly occurredAt: string;
}

export function normalizeActivityCommand(input: {
  readonly idempotencyKey: unknown;
  readonly partyId: unknown;
  readonly leadId: unknown;
  readonly dealId: unknown;
  readonly activityType: unknown;
  readonly channelKey: unknown;
  readonly direction: unknown;
  readonly subject: unknown;
  readonly body: unknown;
  readonly providerReference: unknown;
  readonly occurredAt: unknown;
}): Readonly<NormalizedActivityCommand> {
  const partyId = nullableUuid(input.partyId);
  const leadId = nullableUuid(input.leadId);
  const dealId = nullableUuid(input.dealId);
  if ([partyId, leadId, dealId].every((value) => value === null)) {
    throw new M3CrmDomainError("invalid_activity");
  }
  if (
    typeof input.activityType !== "string" ||
    !CRM_ACTIVITY_TYPES.includes(
      input.activityType as (typeof CRM_ACTIVITY_TYPES)[number],
    ) ||
    !["inbound", "outbound", "internal"].includes(input.direction as string)
  ) {
    throw new M3CrmDomainError("invalid_activity");
  }
  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    partyId,
    leadId,
    dealId,
    activityType: input.activityType as (typeof CRM_ACTIVITY_TYPES)[number],
    channelKey: input.channelKey === null ? null : requireKey(input.channelKey),
    direction: input.direction as NormalizedActivityCommand["direction"],
    subject: normalizeText(input.subject, 200)!,
    body: normalizeText(input.body, 10_000, true),
    providerReference: normalizeText(input.providerReference, 500, true),
    occurredAt: normalizeInstant(input.occurredAt),
  });
}

export interface NormalizedTaskCommand {
  readonly idempotencyKey: string;
  readonly partyId: string | null;
  readonly leadId: string | null;
  readonly dealId: string | null;
  readonly assigneeMembershipId: string;
  readonly title: string;
  readonly description: string | null;
  readonly priority: (typeof CRM_TASK_PRIORITIES)[number];
  readonly dueAt: string;
  readonly reminderAt: string | null;
}

export function normalizeTaskCommand(input: {
  readonly idempotencyKey: unknown;
  readonly partyId: unknown;
  readonly leadId: unknown;
  readonly dealId: unknown;
  readonly assigneeMembershipId: unknown;
  readonly title: unknown;
  readonly description: unknown;
  readonly priority: unknown;
  readonly dueAt: unknown;
  readonly reminderAt: unknown;
}): Readonly<NormalizedTaskCommand> {
  const partyId = nullableUuid(input.partyId);
  const leadId = nullableUuid(input.leadId);
  const dealId = nullableUuid(input.dealId);
  if (
    [partyId, leadId, dealId].every((value) => value === null) ||
    typeof input.priority !== "string" ||
    !CRM_TASK_PRIORITIES.includes(
      input.priority as (typeof CRM_TASK_PRIORITIES)[number],
    )
  ) {
    throw new M3CrmDomainError("invalid_task");
  }
  const dueAt = normalizeInstant(input.dueAt);
  const reminderAt = nullableInstant(input.reminderAt);
  if (reminderAt !== null && Date.parse(reminderAt) > Date.parse(dueAt)) {
    throw new M3CrmDomainError("invalid_task");
  }
  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    partyId,
    leadId,
    dealId,
    assigneeMembershipId: requireUuid(input.assigneeMembershipId),
    title: normalizeText(input.title, 200)!,
    description: normalizeText(input.description, 4_000, true),
    priority: input.priority as (typeof CRM_TASK_PRIORITIES)[number],
    dueAt,
    reminderAt,
  });
}

export interface NormalizedAppointmentCommand {
  readonly idempotencyKey: string;
  readonly leadId: string | null;
  readonly dealId: string | null;
  readonly title: string;
  readonly startsAt: string;
  readonly endsAt: string;
  readonly timezone: string;
  readonly locationId: string | null;
  readonly remoteDetails: string | null;
  readonly notes: string | null;
  readonly attendeePartyIds: readonly string[];
}

export function normalizeAppointmentCommand(input: {
  readonly idempotencyKey: unknown;
  readonly leadId: unknown;
  readonly dealId: unknown;
  readonly title: unknown;
  readonly startsAt: unknown;
  readonly endsAt: unknown;
  readonly timezone: unknown;
  readonly locationId: unknown;
  readonly remoteDetails: unknown;
  readonly notes: unknown;
  readonly attendeePartyIds: unknown;
}): Readonly<NormalizedAppointmentCommand> {
  const leadId = nullableUuid(input.leadId);
  const dealId = nullableUuid(input.dealId);
  if (leadId === null && dealId === null) {
    throw new M3CrmDomainError("invalid_appointment");
  }
  const startsAt = normalizeInstant(input.startsAt);
  const endsAt = normalizeInstant(input.endsAt);
  if (Date.parse(endsAt) <= Date.parse(startsAt)) {
    throw new M3CrmDomainError("invalid_appointment");
  }
  if (
    !Array.isArray(input.attendeePartyIds) ||
    input.attendeePartyIds.length > 100
  ) {
    throw new M3CrmDomainError("invalid_appointment");
  }
  const attendeePartyIds = input.attendeePartyIds.map(requireUuid);
  if (new Set(attendeePartyIds).size !== attendeePartyIds.length) {
    throw new M3CrmDomainError("invalid_appointment");
  }
  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    leadId,
    dealId,
    title: normalizeText(input.title, 200)!,
    startsAt,
    endsAt,
    timezone: requireTimezone(input.timezone),
    locationId: nullableUuid(input.locationId),
    remoteDetails: normalizeText(input.remoteDetails, 2_000, true),
    notes: normalizeText(input.notes, 4_000, true),
    attendeePartyIds: Object.freeze(attendeePartyIds),
  });
}

export function normalizeTaskCancellationCommand(input: {
  readonly expectedVersion: unknown;
  readonly reason: unknown;
}): Readonly<{ readonly expectedVersion: number; readonly reason: string }> {
  return Object.freeze({
    expectedVersion: requireVersion(input.expectedVersion),
    reason: normalizeText(input.reason, 2_000)!,
  });
}

export function normalizeAppointmentTransitionCommand(input: {
  readonly expectedVersion: unknown;
  readonly targetStatus: unknown;
  readonly outcome: unknown;
  readonly reason: unknown;
}): Readonly<{
  readonly expectedVersion: number;
  readonly targetStatus: "completed" | "cancelled" | "no_show";
  readonly outcome: string | null;
  readonly reason: string | null;
}> {
  if (
    !(["completed", "cancelled", "no_show"] as const).includes(
      input.targetStatus as "completed" | "cancelled" | "no_show",
    )
  ) {
    throw new M3CrmDomainError("invalid_appointment");
  }
  const targetStatus = input.targetStatus as
    "completed" | "cancelled" | "no_show";
  const outcome = normalizeText(input.outcome, 4_000, true);
  const reason = normalizeText(input.reason, 2_000, true);
  if (
    (targetStatus === "completed" && outcome === null) ||
    (targetStatus !== "completed" && reason === null)
  ) {
    throw new M3CrmDomainError("reason_required");
  }
  return Object.freeze({
    expectedVersion: requireVersion(input.expectedVersion),
    targetStatus,
    outcome,
    reason,
  });
}

export function planLeadConversion(input: {
  readonly leadId: unknown;
  readonly conversionEligible: unknown;
  readonly currentVersion: unknown;
  readonly expectedVersion: unknown;
  readonly existingConvertedDealId: unknown;
  readonly dealTypeKey: unknown;
  readonly currencyCode: unknown;
  readonly idempotencyKey: unknown;
}): Readonly<{
  readonly leadId: string;
  readonly dealTypeKey: string;
  readonly currencyCode: string;
  readonly idempotencyKey: string;
  readonly resultingLeadVersion: number;
  readonly replayDealId: string | null;
}> {
  const currentVersion = requireVersion(input.currentVersion);
  const expectedVersion = requireVersion(input.expectedVersion);
  const replayDealId = nullableUuid(input.existingConvertedDealId);
  if (replayDealId === null && currentVersion !== expectedVersion) {
    throw new M3CrmDomainError("lead_version_conflict");
  }
  if (input.conversionEligible !== true && replayDealId === null) {
    throw new M3CrmDomainError("invalid_lead_conversion");
  }
  if (
    typeof input.currencyCode !== "string" ||
    !/^[A-Z]{3}$/u.test(input.currencyCode.trim().toUpperCase())
  ) {
    throw new M3CrmDomainError("invalid_lead_conversion");
  }
  return Object.freeze({
    leadId: requireUuid(input.leadId),
    dealTypeKey: requireKey(input.dealTypeKey),
    currencyCode: input.currencyCode.trim().toUpperCase(),
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    resultingLeadVersion:
      replayDealId === null ? currentVersion + 1 : currentVersion,
    replayDealId,
  });
}
