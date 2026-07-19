import {
  M3CrmDomainError,
  normalizeActivityCommand,
  normalizeAppointmentCommand,
  normalizeAppointmentTransitionCommand,
  normalizeLeadCreateCommand,
  normalizePartyAddressCommand,
  normalizePartyContactCommand,
  normalizeTaskCommand,
  normalizeTaskCancellationCommand,
} from "@vynlo/crm";
import { z } from "zod";

import {
  M3ApplicationValidationError,
  M3RpcContractError,
  m3CommandEvidenceSchema,
  m3CurrencyCodeSchema,
  m3DateSchema,
  m3ExpectedVersionSchema,
  m3KeySchema,
  m3NullableTimestampSchema,
  m3ReasonSchema,
  m3TimestampSchema,
  m3UuidSchema,
  parseM3Body,
  parseM3EntityId,
  parseM3RpcRow,
  parseM3RpcRows,
  type M3EntityCommandInput,
} from "./m3-api-common";
import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const nullableText = (maximum: number) =>
  z.string().trim().max(maximum).nullable();
const nullableUuid = m3UuidSchema.nullable();

const personProfileSchema = z
  .object({
    birthDate: m3DateSchema.nullable(),
    familyName: z.string().trim().min(1).max(100),
    givenName: z.string().trim().min(1).max(100),
    preferredName: nullableText(100),
  })
  .strict();

const organizationProfileSchema = z
  .object({
    legalName: z.string().trim().min(1).max(200),
    registrationName: nullableText(200),
  })
  .strict();

const personPartyBodySchema = z
  .object({
    partyType: z.literal("person"),
    displayName: z.string().trim().min(1).max(200),
    preferredLocale: z.enum(["en", "fr"]),
    person: personProfileSchema,
  })
  .strict();

const organizationPartyBodySchema = z
  .object({
    partyType: z.literal("organization"),
    displayName: z.string().trim().min(1).max(200),
    preferredLocale: z.enum(["en", "fr"]),
    organization: organizationProfileSchema,
  })
  .strict();

const partyBodySchema = z.discriminatedUnion("partyType", [
  personPartyBodySchema,
  organizationPartyBodySchema,
]);

const partyContactBodySchema = z
  .object({
    contactType: z.enum(["email", "phone"]),
    consentSource: nullableText(500),
    consentStatus: z.enum(["unknown", "granted", "denied", "withdrawn"]),
    doNotContact: z.boolean(),
    isPreferred: z.boolean(),
    isPrimary: z.boolean(),
    value: z.string().trim().min(1).max(320),
  })
  .strict();

const partyAddressBodySchema = z
  .object({
    addressType: m3KeySchema,
    countryCode: z
      .string()
      .trim()
      .toUpperCase()
      .regex(/^[A-Z]{2}$/u),
    isPrimary: z.boolean(),
    line1: z.string().trim().min(1).max(200),
    line2: nullableText(200),
    locality: z.string().trim().min(1).max(100),
    postalCode: z.string().trim().min(1).max(32),
    region: z.string().trim().min(1).max(100),
  })
  .strict();

const partyIdentifierBodySchema = z
  .object({
    effectiveFrom: m3DateSchema.nullable(),
    effectiveTo: m3DateSchema.nullable(),
    identifierType: m3KeySchema,
    jurisdiction: z.string().trim().min(2).max(100),
    reason: m3ReasonSchema,
    value: z.string().trim().min(2).max(500),
  })
  .strict()
  .refine(
    (value) =>
      value.effectiveFrom === null ||
      value.effectiveTo === null ||
      value.effectiveTo >= value.effectiveFrom,
    { message: "Identifier effective dates are invalid." },
  );

const partyRelationshipBodySchema = z
  .object({
    effectiveFrom: m3DateSchema.nullable(),
    effectiveTo: m3DateSchema.nullable(),
    relatedPartyId: m3UuidSchema,
    relationshipType: m3KeySchema,
  })
  .strict();

const personPartyUpdateBodySchema = z
  .object({
    displayName: z.string().trim().min(1).max(200),
    expectedVersion: m3ExpectedVersionSchema,
    partyType: z.literal("person"),
    person: personProfileSchema,
    preferredLocale: z.enum(["en", "fr"]),
  })
  .strict();

const organizationPartyUpdateBodySchema = z
  .object({
    displayName: z.string().trim().min(1).max(200),
    expectedVersion: m3ExpectedVersionSchema,
    organization: organizationProfileSchema,
    partyType: z.literal("organization"),
    preferredLocale: z.enum(["en", "fr"]),
  })
  .strict();

const partyUpdateBodySchema = z.discriminatedUnion("partyType", [
  personPartyUpdateBodySchema,
  organizationPartyUpdateBodySchema,
]);

const partyArchiveBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    reason: m3ReasonSchema,
  })
  .strict();

const partyPreferenceBodySchema = z
  .object({
    allowed: z.boolean(),
    channelKey: m3KeySchema,
    consentSource: nullableText(500),
    consentStatus: z.enum(["unknown", "granted", "denied", "withdrawn"]),
    doNotContact: z.boolean(),
    expectedVersion: m3ExpectedVersionSchema,
  })
  .strict()
  .refine((body) => !(body.allowed && body.doNotContact), {
    message: "A blocked communication channel cannot also be allowed.",
  })
  .refine(
    (body) => body.consentStatus !== "granted" || body.consentSource !== null,
    { message: "Granted consent requires its source." },
  );

const identifierRevealBodySchema = z
  .object({ reason: m3ReasonSchema })
  .strict();

const leadBodySchema = z
  .object({
    assigneeMembershipId: nullableUuid,
    interestedInventoryUnitId: nullableUuid,
    nextActionAt: m3NullableTimestampSchema,
    prospectPartyId: nullableUuid,
    sourceKey: m3KeySchema,
    summary: z.string().trim().min(1).max(2_000),
  })
  .strict();

const leadUpdateBodySchema = z
  .object({
    assigneeMembershipId: nullableUuid.optional(),
    expectedVersion: m3ExpectedVersionSchema,
    interestedInventoryUnitId: nullableUuid.optional(),
    nextActionAt: m3NullableTimestampSchema.optional(),
    summary: z.string().trim().min(1).max(2_000).optional(),
  })
  .strict()
  .refine(
    (body) =>
      body.assigneeMembershipId !== undefined ||
      body.interestedInventoryUnitId !== undefined ||
      body.nextActionAt !== undefined ||
      body.summary !== undefined,
    { message: "At least one lead field must be updated." },
  );

const transitionBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    reason: m3ReasonSchema.nullable(),
    transitionKey: m3KeySchema,
  })
  .strict();

const conversionBodySchema = z
  .object({
    currencyCode: m3CurrencyCodeSchema,
    dealTypeKey: m3KeySchema,
    expectedVersion: m3ExpectedVersionSchema,
    legalEntityId: nullableUuid,
    locationId: m3UuidSchema,
    ownerMembershipId: nullableUuid,
  })
  .strict();

const activityBodySchema = z
  .object({
    activityType: z.enum([
      "note",
      "call",
      "email_reference",
      "text_reference",
      "appointment",
      "assignment",
      "status_change",
      "document",
      "deal_event",
    ]),
    body: nullableText(10_000),
    channelKey: m3KeySchema.nullable(),
    dealId: nullableUuid,
    direction: z.enum(["inbound", "outbound", "internal"]),
    leadId: nullableUuid,
    occurredAt: m3TimestampSchema,
    partyId: nullableUuid,
    providerReference: nullableText(500),
    subject: z.string().trim().min(1).max(200),
  })
  .strict();

const taskBodySchema = z
  .object({
    assigneeMembershipId: m3UuidSchema,
    dealId: nullableUuid,
    description: nullableText(4_000),
    dueAt: m3TimestampSchema,
    leadId: nullableUuid,
    partyId: nullableUuid,
    priority: z.enum(["low", "normal", "high", "urgent"]),
    reminderAt: m3NullableTimestampSchema,
    title: z.string().trim().min(1).max(200),
  })
  .strict();

const taskCompleteBodySchema = z
  .object({ expectedVersion: m3ExpectedVersionSchema })
  .strict();

const taskCancelBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    reason: m3ReasonSchema,
  })
  .strict();

const appointmentBodySchema = z
  .object({
    attendeePartyIds: z.array(m3UuidSchema).max(100),
    dealId: nullableUuid,
    endsAt: m3TimestampSchema,
    leadId: nullableUuid,
    locationId: nullableUuid,
    notes: nullableText(4_000),
    remoteDetails: nullableText(2_000),
    startsAt: m3TimestampSchema,
    timezone: z.string().trim().min(1).max(100),
    title: z.string().trim().min(1).max(200),
  })
  .strict();

const appointmentTransitionBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    outcome: nullableText(4_000),
    reason: m3ReasonSchema.nullable(),
    targetStatus: z.enum(["completed", "cancelled", "no_show"]),
  })
  .strict();

const partyResultSchema = m3CommandEvidenceSchema
  .extend({ party_id: m3UuidSchema })
  .strict();
const contactResultSchema = m3CommandEvidenceSchema
  .extend({ contact_id: m3UuidSchema, party_id: m3UuidSchema })
  .strict();
const addressResultSchema = m3CommandEvidenceSchema
  .extend({ address_id: m3UuidSchema, party_id: m3UuidSchema })
  .strict();
const identifierResultSchema = m3CommandEvidenceSchema
  .extend({ identifier_id: m3UuidSchema, party_id: m3UuidSchema })
  .strict();
const relationshipResultSchema = m3CommandEvidenceSchema
  .extend({ party_id: m3UuidSchema, relationship_id: m3UuidSchema })
  .strict();
const preferenceResultSchema = m3CommandEvidenceSchema
  .extend({ party_id: m3UuidSchema, preference_id: m3UuidSchema })
  .strict();
const identifierRevealResultSchema = z
  .object({
    audit_event_id: m3UuidSchema,
    identifier_id: m3UuidSchema,
    party_id: m3UuidSchema,
    plaintext_value: z.string().min(1).max(500),
  })
  .strict();
const leadResultSchema = m3CommandEvidenceSchema
  .extend({
    lead_id: m3UuidSchema,
    state_key: m3KeySchema,
    workflow_event_id: m3UuidSchema.nullable(),
  })
  .strict();
const conversionResultSchema = m3CommandEvidenceSchema
  .extend({ deal_id: m3UuidSchema, lead_id: m3UuidSchema })
  .strict();
const activityResultSchema = m3CommandEvidenceSchema
  .extend({ activity_id: m3UuidSchema })
  .strict();
const taskResultSchema = m3CommandEvidenceSchema
  .extend({
    task_id: m3UuidSchema,
    task_state: z.enum(["open", "completed", "cancelled"]),
  })
  .strict();
const appointmentResultSchema = m3CommandEvidenceSchema
  .extend({
    appointment_id: m3UuidSchema,
    appointment_status: z.enum([
      "scheduled",
      "completed",
      "cancelled",
      "no_show",
    ]),
  })
  .strict();

const partyListRowSchema = z
  .object({
    display_name: z.string().min(1).max(200),
    party_id: m3UuidSchema,
    party_type: z.enum(["person", "organization"]),
    preferred_locale: z.enum(["en", "fr"]),
    status: z.enum(["active", "archived"]),
    version: m3ExpectedVersionSchema,
  })
  .strict();

const partyDetailBaseRowSchema = partyListRowSchema
  .omit({ party_type: true })
  .extend({
    addresses: z
      .array(
        z
          .object({
            addressId: m3UuidSchema,
            addressType: m3KeySchema,
            countryCode: z.string().regex(/^[A-Z]{2}$/u),
            isPrimary: z.boolean(),
            line1: z.string().min(1).max(200),
            line2: nullableText(200),
            locality: z.string().min(1).max(100),
            postalCode: z.string().min(1).max(32),
            region: z.string().min(1).max(100),
          })
          .strict(),
      )
      .max(100),
    contacts: z
      .array(
        z
          .object({
            contactId: m3UuidSchema,
            contactType: z.enum(["email", "phone"]),
            consentStatus: z.enum([
              "unknown",
              "granted",
              "denied",
              "withdrawn",
            ]),
            doNotContact: z.boolean(),
            isPreferred: z.boolean(),
            isPrimary: z.boolean(),
            value: z.string().min(1).max(320),
          })
          .strict(),
      )
      .max(100),
    identifiers: z
      .array(
        z
          .object({
            identifierId: m3UuidSchema,
            identifierType: m3KeySchema,
            jurisdiction: z.string().min(2).max(100),
            maskedValue: z.string().min(1).max(100),
          })
          .strict(),
      )
      .max(100),
    preferences: z
      .array(
        z
          .object({
            allowed: z.boolean(),
            channelKey: m3KeySchema,
            consentSource: nullableText(500),
            consentStatus: z.enum([
              "unknown",
              "granted",
              "denied",
              "withdrawn",
            ]),
            doNotContact: z.boolean(),
            preferenceId: m3UuidSchema,
            version: m3ExpectedVersionSchema,
          })
          .strict(),
      )
      .max(100),
    relationships: z
      .array(
        z
          .object({
            effectiveFrom: m3DateSchema.nullable(),
            effectiveTo: m3DateSchema.nullable(),
            relatedPartyId: m3UuidSchema,
            relationshipId: m3UuidSchema,
            relationshipType: m3KeySchema,
            version: m3ExpectedVersionSchema,
          })
          .strict(),
      )
      .max(100),
  })
  .strict();

const partyDetailRowSchema = z.discriminatedUnion("party_type", [
  partyDetailBaseRowSchema
    .extend({
      party_type: z.literal("person"),
      profile: personProfileSchema,
    })
    .strict(),
  partyDetailBaseRowSchema
    .extend({
      party_type: z.literal("organization"),
      profile: organizationProfileSchema,
    })
    .strict(),
]);

const leadListRowSchema = z
  .object({
    assignee_membership_id: nullableUuid,
    created_at: m3TimestampSchema,
    lead_id: m3UuidSchema,
    next_action_at: m3NullableTimestampSchema,
    prospect_party_id: nullableUuid,
    source_key: m3KeySchema,
    state_key: m3KeySchema,
    summary: z.string().max(2_000),
    version: m3ExpectedVersionSchema,
  })
  .strict();

const workflowTransitionOptionSchema = z
  .object({
    labels: z
      .object({
        en: z.string().trim().min(1).max(200),
        fr: z.string().trim().min(1).max(200),
      })
      .strict(),
    reasonRequired: z.boolean(),
    toStateKey: m3KeySchema,
    transitionKey: m3KeySchema,
  })
  .strict();

const leadDetailRowSchema = leadListRowSchema
  .extend({
    available_transitions: z.array(workflowTransitionOptionSchema).max(100),
    conversion_eligible: z.boolean(),
    interested_inventory_unit_id: nullableUuid,
    lost_reason: nullableText(2_000),
    converted_deal_id: nullableUuid,
    workflow_instance_id: m3UuidSchema,
  })
  .strict();

const activityListRowSchema = z
  .object({
    activity_id: m3UuidSchema,
    activity_type: activityBodySchema.shape.activityType,
    actor_user_id: m3UuidSchema,
    body: nullableText(10_000),
    deal_id: nullableUuid,
    direction: activityBodySchema.shape.direction,
    lead_id: nullableUuid,
    occurred_at: m3TimestampSchema,
    party_id: nullableUuid,
    subject: z.string().min(1).max(200),
  })
  .strict();

const taskListRowSchema = z
  .object({
    assignee_membership_id: m3UuidSchema,
    cancelled_at: m3NullableTimestampSchema,
    cancellation_reason: nullableText(2_000),
    completed_at: m3NullableTimestampSchema,
    completed_by: nullableUuid,
    created_at: m3TimestampSchema,
    deal_id: nullableUuid,
    description: nullableText(4_000),
    due_at: m3TimestampSchema,
    lead_id: nullableUuid,
    party_id: nullableUuid,
    priority: taskBodySchema.shape.priority,
    reminder_at: m3NullableTimestampSchema,
    state: z.enum(["open", "completed", "cancelled"]),
    task_id: m3UuidSchema,
    title: z.string().min(1).max(200),
    version: m3ExpectedVersionSchema,
  })
  .strict();

const appointmentListRowSchema = z
  .object({
    appointment_id: m3UuidSchema,
    attendee_party_ids: z.array(m3UuidSchema).max(100),
    created_at: m3TimestampSchema,
    deal_id: nullableUuid,
    ends_at: m3TimestampSchema,
    lead_id: nullableUuid,
    location_id: nullableUuid,
    notes: nullableText(4_000),
    outcome: nullableText(4_000),
    remote_details: nullableText(2_000),
    resolved_at: m3NullableTimestampSchema,
    starts_at: m3TimestampSchema,
    status: appointmentResultSchema.shape.appointment_status,
    status_reason: nullableText(2_000),
    timezone: z.string().min(1).max(100),
    title: z.string().min(1).max(200),
    version: m3ExpectedVersionSchema,
  })
  .strict();

export interface M3WorkspaceQueryInput {
  readonly accessToken: string;
  readonly workspaceId: string;
}

export interface M3CrmTimelineQueryInput extends M3WorkspaceQueryInput {
  readonly dealId?: string | null;
  readonly leadId?: string | null;
  readonly partyId?: string | null;
}

function normalizeCrm<T>(operation: () => T): T {
  try {
    return operation();
  } catch (error) {
    if (error instanceof M3CrmDomainError) {
      throw new M3ApplicationValidationError("invalid_request_body");
    }
    throw error;
  }
}

function commandEvidence(row: z.infer<typeof m3CommandEvidenceSchema>) {
  return {
    aggregateVersion: row.aggregate_version,
    auditEventId: row.audit_event_id,
    outboxEventId: row.outbox_event_id,
    replayed: row.replayed,
  } as const;
}

export class M3CrmApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async listParties(input: M3WorkspaceQueryInput) {
    return parseM3RpcRows(
      partyListRowSchema,
      500,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_parties",
        parameters: { p_workspace_id: input.workspaceId },
      }),
    ).map((row) => ({
      displayName: row.display_name,
      partyId: row.party_id,
      partyType: row.party_type,
      preferredLocale: row.preferred_locale,
      status: row.status,
      version: row.version,
    }));
  }

  async createParty(input: VerticalSliceCommandInput) {
    const body = parseM3Body(partyBodySchema, input.body);
    const row = parseM3RpcRow(
      partyResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_create_party",
        parameters: {
          p_birth_date:
            body.partyType === "person" ? body.person.birthDate : null,
          p_correlation_id: input.metadata.correlationId,
          p_display_name: body.displayName,
          p_family_name:
            body.partyType === "person" ? body.person.familyName : null,
          p_given_name:
            body.partyType === "person" ? body.person.givenName : null,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_legal_name:
            body.partyType === "organization"
              ? body.organization.legalName
              : null,
          p_party_type: body.partyType,
          p_preferred_locale: body.preferredLocale,
          p_preferred_name:
            body.partyType === "person" ? body.person.preferredName : null,
          p_registration_name:
            body.partyType === "organization"
              ? body.organization.registrationName
              : null,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...commandEvidence(row), partyId: row.party_id };
  }

  async getParty(input: M3WorkspaceQueryInput & { readonly partyId: string }) {
    const row = parseM3RpcRow(
      partyDetailRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_get_party",
        parameters: {
          p_party_id: parseM3EntityId(input.partyId),
          p_workspace_id: input.workspaceId,
        },
      }),
    );
    return {
      addresses: row.addresses,
      contacts: row.contacts,
      displayName: row.display_name,
      identifiers: row.identifiers,
      partyId: row.party_id,
      partyType: row.party_type,
      preferences: row.preferences,
      preferredLocale: row.preferred_locale,
      profile: row.profile,
      relationships: row.relationships,
      status: row.status,
      version: row.version,
    };
  }

  async updateParty(input: M3EntityCommandInput) {
    const partyId = parseM3EntityId(input.entityId);
    const body = parseM3Body(partyUpdateBodySchema, input.body);
    const row = parseM3RpcRow(
      partyResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_update_party",
        parameters: {
          p_birth_date:
            body.partyType === "person" ? body.person.birthDate : null,
          p_correlation_id: input.metadata.correlationId,
          p_display_name: body.displayName,
          p_expected_version: body.expectedVersion,
          p_family_name:
            body.partyType === "person" ? body.person.familyName : null,
          p_given_name:
            body.partyType === "person" ? body.person.givenName : null,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_legal_name:
            body.partyType === "organization"
              ? body.organization.legalName
              : null,
          p_party_id: partyId,
          p_preferred_locale: body.preferredLocale,
          p_preferred_name:
            body.partyType === "person" ? body.person.preferredName : null,
          p_registration_name:
            body.partyType === "organization"
              ? body.organization.registrationName
              : null,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...commandEvidence(row), partyId: row.party_id };
  }

  async archiveParty(input: M3EntityCommandInput) {
    const partyId = parseM3EntityId(input.entityId);
    const body = parseM3Body(partyArchiveBodySchema, input.body);
    const row = parseM3RpcRow(
      partyResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_archive_party",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_party_id: partyId,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...commandEvidence(row), partyId: row.party_id };
  }

  async setPartyCommunicationPreference(input: M3EntityCommandInput) {
    const partyId = parseM3EntityId(input.entityId);
    const body = parseM3Body(partyPreferenceBodySchema, input.body);
    const row = parseM3RpcRow(
      preferenceResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_set_party_communication_preference",
        parameters: {
          p_allowed: body.allowed,
          p_channel_key: body.channelKey,
          p_consent_source: body.consentSource,
          p_consent_status: body.consentStatus,
          p_correlation_id: input.metadata.correlationId,
          p_do_not_contact: body.doNotContact,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_party_id: partyId,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      partyId: row.party_id,
      preferenceId: row.preference_id,
    };
  }

  async revealPartyIdentifier(
    input: M3EntityCommandInput & { readonly childId: string },
  ) {
    const partyId = parseM3EntityId(input.entityId);
    const identifierId = parseM3EntityId(input.childId);
    const body = parseM3Body(identifierRevealBodySchema, input.body);
    const row = parseM3RpcRow(
      identifierRevealResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_reveal_party_identifier",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_identifier_id: identifierId,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    if (row.party_id !== partyId || row.identifier_id !== identifierId) {
      throw new M3RpcContractError();
    }
    return {
      auditEventId: row.audit_event_id,
      identifierId: row.identifier_id,
      partyId: row.party_id,
      value: row.plaintext_value,
    };
  }

  async addPartyContact(input: M3EntityCommandInput) {
    const partyId = parseM3EntityId(input.entityId);
    const body = parseM3Body(partyContactBodySchema, input.body);
    const command = normalizeCrm(() =>
      normalizePartyContactCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
        partyId,
      }),
    );
    const row = parseM3RpcRow(
      contactResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_add_party_contact",
        parameters: {
          p_consent_source: command.consentSource,
          p_consent_status: command.consentStatus,
          p_contact_type: command.contactType,
          p_correlation_id: input.metadata.correlationId,
          p_do_not_contact: command.doNotContact,
          p_idempotency_key: command.idempotencyKey,
          p_is_preferred: command.isPreferred,
          p_is_primary: command.isPrimary,
          p_party_id: command.partyId,
          p_request_id: input.metadata.requestId,
          p_value: command.value,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      contactId: row.contact_id,
      partyId: row.party_id,
    };
  }

  async addPartyAddress(input: M3EntityCommandInput) {
    const partyId = parseM3EntityId(input.entityId);
    const body = parseM3Body(partyAddressBodySchema, input.body);
    const command = normalizeCrm(() =>
      normalizePartyAddressCommand({ ...body, partyId }),
    );
    const row = parseM3RpcRow(
      addressResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_add_party_address",
        parameters: {
          p_address_type: command.addressType,
          p_correlation_id: input.metadata.correlationId,
          p_country_code: command.countryCode,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_is_primary: command.isPrimary,
          p_line_1: command.line1,
          p_line_2: command.line2,
          p_locality: command.locality,
          p_party_id: command.partyId,
          p_postal_code: command.postalCode,
          p_region: command.region,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      addressId: row.address_id,
      partyId: row.party_id,
    };
  }

  async replacePartyIdentifier(input: M3EntityCommandInput) {
    const partyId = parseM3EntityId(input.entityId);
    const body = parseM3Body(partyIdentifierBodySchema, input.body);
    const row = parseM3RpcRow(
      identifierResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_replace_party_identifier",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_effective_from: body.effectiveFrom,
          p_effective_to: body.effectiveTo,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_identifier_type: body.identifierType,
          p_jurisdiction: body.jurisdiction,
          p_party_id: partyId,
          p_plaintext_value: body.value,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      identifierId: row.identifier_id,
      partyId: row.party_id,
    };
  }

  async addPartyRelationship(input: M3EntityCommandInput) {
    const partyId = parseM3EntityId(input.entityId);
    const body = parseM3Body(partyRelationshipBodySchema, input.body);
    const row = parseM3RpcRow(
      relationshipResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_add_party_relationship",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_effective_from: body.effectiveFrom,
          p_effective_to: body.effectiveTo,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_party_id: partyId,
          p_related_party_id: body.relatedPartyId,
          p_relationship_type: body.relationshipType,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      partyId: row.party_id,
      relationshipId: row.relationship_id,
    };
  }

  async listLeads(input: M3WorkspaceQueryInput) {
    return parseM3RpcRows(
      leadListRowSchema,
      500,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_leads",
        parameters: { p_workspace_id: input.workspaceId },
      }),
    ).map((row) => ({
      assigneeMembershipId: row.assignee_membership_id,
      createdAt: row.created_at,
      leadId: row.lead_id,
      nextActionAt: row.next_action_at,
      prospectPartyId: row.prospect_party_id,
      sourceKey: row.source_key,
      stateKey: row.state_key,
      summary: row.summary,
      version: row.version,
    }));
  }

  async createLead(input: VerticalSliceCommandInput) {
    const body = parseM3Body(leadBodySchema, input.body);
    const command = normalizeCrm(() =>
      normalizeLeadCreateCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseM3RpcRow(
      leadResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_create_lead",
        parameters: {
          p_assignee_membership_id: command.assigneeMembershipId,
          p_correlation_id: input.metadata.correlationId,
          p_idempotency_key: command.idempotencyKey,
          p_interested_inventory_unit_id: command.interestedInventoryUnitId,
          p_next_action_at: command.nextActionAt,
          p_prospect_party_id: command.prospectPartyId,
          p_request_id: input.metadata.requestId,
          p_source_key: command.sourceKey,
          p_summary: command.summary,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      leadId: row.lead_id,
      stateKey: row.state_key,
      workflowEventId: row.workflow_event_id,
    };
  }

  async getLead(input: M3WorkspaceQueryInput & { readonly leadId: string }) {
    const row = parseM3RpcRow(
      leadDetailRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_get_lead",
        parameters: {
          p_lead_id: parseM3EntityId(input.leadId),
          p_workspace_id: input.workspaceId,
        },
      }),
    );
    return {
      assigneeMembershipId: row.assignee_membership_id,
      availableTransitions: row.available_transitions,
      conversionEligible: row.conversion_eligible,
      convertedDealId: row.converted_deal_id,
      createdAt: row.created_at,
      interestedInventoryUnitId: row.interested_inventory_unit_id,
      leadId: row.lead_id,
      lostReason: row.lost_reason,
      nextActionAt: row.next_action_at,
      prospectPartyId: row.prospect_party_id,
      sourceKey: row.source_key,
      stateKey: row.state_key,
      summary: row.summary,
      version: row.version,
      workflowInstanceId: row.workflow_instance_id,
    };
  }

  async updateLead(input: M3EntityCommandInput) {
    const leadId = parseM3EntityId(input.entityId);
    const body = parseM3Body(leadUpdateBodySchema, input.body);
    const row = parseM3RpcRow(
      leadResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_update_lead",
        parameters: {
          p_assignee_membership_id: body.assigneeMembershipId ?? null,
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_interested_inventory_unit_id:
            body.interestedInventoryUnitId ?? null,
          p_lead_id: leadId,
          p_next_action_at: body.nextActionAt ?? null,
          p_request_id: input.metadata.requestId,
          p_summary: body.summary ?? null,
          p_update_assignee: body.assigneeMembershipId !== undefined,
          p_update_interest: body.interestedInventoryUnitId !== undefined,
          p_update_next_action: body.nextActionAt !== undefined,
          p_update_summary: body.summary !== undefined,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      leadId: row.lead_id,
      stateKey: row.state_key,
      workflowEventId: row.workflow_event_id,
    };
  }

  async transitionLead(input: M3EntityCommandInput) {
    const leadId = parseM3EntityId(input.entityId);
    const body = parseM3Body(transitionBodySchema, input.body);
    const row = parseM3RpcRow(
      leadResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_transition_lead",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_lead_id: leadId,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_transition_key: body.transitionKey,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      leadId: row.lead_id,
      stateKey: row.state_key,
      workflowEventId: row.workflow_event_id,
    };
  }

  async convertLead(input: M3EntityCommandInput) {
    const leadId = parseM3EntityId(input.entityId);
    const body = parseM3Body(conversionBodySchema, input.body);
    const row = parseM3RpcRow(
      conversionResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_convert_lead",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: body.currencyCode,
          p_deal_type_key: body.dealTypeKey,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_lead_id: leadId,
          p_legal_entity_id: body.legalEntityId,
          p_location_id: body.locationId,
          p_owner_membership_id: body.ownerMembershipId,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      dealId: row.deal_id,
      leadId: row.lead_id,
    };
  }

  async createActivity(input: VerticalSliceCommandInput) {
    const body = parseM3Body(activityBodySchema, input.body);
    const command = normalizeCrm(() =>
      normalizeActivityCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseM3RpcRow(
      activityResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_create_activity",
        parameters: {
          p_activity_type: command.activityType,
          p_body: command.body,
          p_channel_key: command.channelKey,
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: command.dealId,
          p_direction: command.direction,
          p_idempotency_key: command.idempotencyKey,
          p_lead_id: command.leadId,
          p_occurred_at: command.occurredAt,
          p_party_id: command.partyId,
          p_provider_reference: command.providerReference,
          p_request_id: input.metadata.requestId,
          p_subject: command.subject,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return { ...commandEvidence(row), activityId: row.activity_id };
  }

  async listTimeline(input: M3CrmTimelineQueryInput) {
    return parseM3RpcRows(
      activityListRowSchema,
      500,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_crm_timeline",
        parameters: {
          p_deal_id:
            input.dealId === undefined || input.dealId === null
              ? null
              : parseM3EntityId(input.dealId),
          p_lead_id:
            input.leadId === undefined || input.leadId === null
              ? null
              : parseM3EntityId(input.leadId),
          p_party_id:
            input.partyId === undefined || input.partyId === null
              ? null
              : parseM3EntityId(input.partyId),
          p_workspace_id: input.workspaceId,
        },
      }),
    ).map((row) => ({
      activityId: row.activity_id,
      activityType: row.activity_type,
      actorUserId: row.actor_user_id,
      body: row.body,
      dealId: row.deal_id,
      direction: row.direction,
      leadId: row.lead_id,
      occurredAt: row.occurred_at,
      partyId: row.party_id,
      subject: row.subject,
    }));
  }

  async createTask(input: VerticalSliceCommandInput) {
    const body = parseM3Body(taskBodySchema, input.body);
    const command = normalizeCrm(() =>
      normalizeTaskCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseM3RpcRow(
      taskResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_create_task",
        parameters: {
          p_assignee_membership_id: command.assigneeMembershipId,
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: command.dealId,
          p_description: command.description,
          p_due_at: command.dueAt,
          p_idempotency_key: command.idempotencyKey,
          p_lead_id: command.leadId,
          p_party_id: command.partyId,
          p_priority: command.priority,
          p_reminder_at: command.reminderAt,
          p_request_id: input.metadata.requestId,
          p_title: command.title,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      taskId: row.task_id,
      taskState: row.task_state,
    };
  }

  async completeTask(input: M3EntityCommandInput) {
    const taskId = parseM3EntityId(input.entityId);
    const body = parseM3Body(taskCompleteBodySchema, input.body);
    const row = parseM3RpcRow(
      taskResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_complete_task",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_request_id: input.metadata.requestId,
          p_task_id: taskId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      taskId: row.task_id,
      taskState: row.task_state,
    };
  }

  async cancelTask(input: M3EntityCommandInput) {
    const taskId = parseM3EntityId(input.entityId);
    const body = parseM3Body(taskCancelBodySchema, input.body);
    const command = normalizeCrm(() => normalizeTaskCancellationCommand(body));
    const row = parseM3RpcRow(
      taskResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_cancel_task",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: command.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_reason: command.reason,
          p_request_id: input.metadata.requestId,
          p_task_id: taskId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      taskId: row.task_id,
      taskState: row.task_state,
    };
  }

  async listTasks(input: M3WorkspaceQueryInput) {
    return parseM3RpcRows(
      taskListRowSchema,
      500,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_tasks",
        parameters: { p_workspace_id: input.workspaceId },
      }),
    ).map((row) => ({
      assigneeMembershipId: row.assignee_membership_id,
      cancelledAt: row.cancelled_at,
      cancellationReason: row.cancellation_reason,
      completedAt: row.completed_at,
      completedBy: row.completed_by,
      createdAt: row.created_at,
      dealId: row.deal_id,
      description: row.description,
      dueAt: row.due_at,
      leadId: row.lead_id,
      partyId: row.party_id,
      priority: row.priority,
      reminderAt: row.reminder_at,
      state: row.state,
      taskId: row.task_id,
      title: row.title,
      version: row.version,
    }));
  }

  async createAppointment(input: VerticalSliceCommandInput) {
    const body = parseM3Body(appointmentBodySchema, input.body);
    const command = normalizeCrm(() =>
      normalizeAppointmentCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseM3RpcRow(
      appointmentResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_create_appointment",
        parameters: {
          p_attendee_party_ids: command.attendeePartyIds,
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: command.dealId,
          p_ends_at: command.endsAt,
          p_idempotency_key: command.idempotencyKey,
          p_lead_id: command.leadId,
          p_location_id: command.locationId,
          p_notes: command.notes,
          p_remote_details: command.remoteDetails,
          p_request_id: input.metadata.requestId,
          p_starts_at: command.startsAt,
          p_timezone: command.timezone,
          p_title: command.title,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      appointmentId: row.appointment_id,
      appointmentStatus: row.appointment_status,
    };
  }

  async transitionAppointment(input: M3EntityCommandInput) {
    const appointmentId = parseM3EntityId(input.entityId);
    const body = parseM3Body(appointmentTransitionBodySchema, input.body);
    const command = normalizeCrm(() =>
      normalizeAppointmentTransitionCommand(body),
    );
    const row = parseM3RpcRow(
      appointmentResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_transition_appointment",
        parameters: {
          p_appointment_id: appointmentId,
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: command.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_outcome: command.outcome,
          p_reason: command.reason,
          p_request_id: input.metadata.requestId,
          p_target_status: command.targetStatus,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      appointmentId: row.appointment_id,
      appointmentStatus: row.appointment_status,
    };
  }

  async listAppointments(input: M3WorkspaceQueryInput) {
    return parseM3RpcRows(
      appointmentListRowSchema,
      500,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_appointments",
        parameters: { p_workspace_id: input.workspaceId },
      }),
    ).map((row) => ({
      appointmentId: row.appointment_id,
      attendeePartyIds: row.attendee_party_ids,
      createdAt: row.created_at,
      dealId: row.deal_id,
      endsAt: row.ends_at,
      leadId: row.lead_id,
      locationId: row.location_id,
      notes: row.notes,
      outcome: row.outcome,
      remoteDetails: row.remote_details,
      resolvedAt: row.resolved_at,
      startsAt: row.starts_at,
      status: row.status,
      statusReason: row.status_reason,
      timezone: row.timezone,
      title: row.title,
      version: row.version,
    }));
  }
}
